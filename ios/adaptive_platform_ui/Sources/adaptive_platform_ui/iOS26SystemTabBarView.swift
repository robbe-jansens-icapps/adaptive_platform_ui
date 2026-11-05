import Flutter
import UIKit

/// Makes iOS's own tab bar for the iPhone Duo's vertical bar (Dart:
/// IOS26SystemTabBar), shown over the Flutter view only (NativeChromeHost).
///
/// The tabs leave the bar while a page is pushed over them and come back with
/// the pop, which makes a new view each time. Making a tab bar controller and
/// laying out its bar costs the main thread, which Dart shares, at the very
/// start of the pop; so the last view is kept, parked, for the next one.
final class iOS26SystemTabBarFactory: NSObject, FlutterPlatformViewFactory {
    private let registrar: FlutterPluginRegistrar
    private var parked: iOS26SystemTabBarView?

    init(registrar: FlutterPluginRegistrar) {
        self.registrar = registrar
        super.init()
    }

    func createArgsCodec() -> FlutterMessageCodec & NSObjectProtocol {
        FlutterStandardMessageCodec.sharedInstance()
    }

    func create(
        withFrame frame: CGRect,
        viewIdentifier viewId: Int64,
        arguments args: Any?
    ) -> FlutterPlatformView {
        if let view = parked {
            parked = nil
            if view.canBeReused(under: registrar.viewController) {
                view.reuse(viewId: viewId, args: args)
                return view
            }
            view.detach()
        }
        let view = iOS26SystemTabBarView(viewId: viewId, args: args, registrar: registrar)
        view.onParked = { [weak self] view in
            guard let self else { return view.detach() }
            if let other = self.parked, other !== view { other.detach() }
            self.parked = view
        }
        return view
    }
}

/// The tabs as iOS draws them in the iPhone Duo's vertical bar.
///
/// iOS lays a tab bar out vertically only when a tab bar controller manages
/// it: a bare `UITabBar`, as the bar along the bottom is, stays horizontal
/// there. So this view holds a tab bar controller whose tabs are empty and
/// see-through, added as a child of the Flutter view controller: iOS puts its
/// bar in the vertical bar, with the labels it reveals on a held tab and the
/// lens, and a tap only tells Flutter, whose tab layout stays in charge of
/// what each tab shows.
///
/// The controller's view spans the Flutter view (`ChromeWindowAnchored`), as
/// iOS places the bar within it. The bar shows only while iOS has laid the
/// tabs out where Flutter keeps their place, a column of tabs a tap reaches,
/// which is checked with public API only, and only touches there are taken.
/// Should iOS lay them out anywhere else for good (a later iOS), Flutter is
/// told, and shows its own capsule in their place.
final class iOS26SystemTabBarView: NSObject, FlutterPlatformView, UITabBarControllerDelegate,
    ChromeHitRegion, ChromeWindowAnchored, ChromeRemovable
{
    /// How long, and over how many frames, the tabs must stay out of place
    /// with nothing else changing before Flutter shows its own capsule: a
    /// main thread busy at launch, or a fold arriving in steps, is no reason.
    private static let failureTime: CFTimeInterval = 1
    private static let failureFrames = 30

    /// How far a tab's centre may lie outside the place Flutter keeps.
    private static let tolerance: CGFloat = 4

    /// Told when the view's slot went and it waits, hidden, to be reused.
    var onParked: ((iOS26SystemTabBarView) -> Void)?

    private var channel: FlutterMethodChannel
    private let registrar: FlutterPluginRegistrar
    private let container = SystemTabBarContainerView()
    private let controller = SystemTabBarController()
    private var fontObserver: NSObjectProtocol?

    /// Where Flutter keeps the tabs, in the container's points.
    private var slot: CGRect?
    private var verified = false
    private var failing: (since: CFTimeInterval, frames: Int, key: String)?
    private var failureTicks: CADisplayLink?
    private var reportedAvailable: Bool?

    init(viewId: Int64, args: Any?, registrar: FlutterPluginRegistrar) {
        self.registrar = registrar
        channel = Self.channel(viewId, registrar)
        super.init()
        if #available(iOS 18.0, *) {
            controller.mode = .tabBar
        }
        if #available(iOS 26.0, *) {
            controller.tabBarMinimizeBehavior = .never
        }
        controller.delegate = self
        controller.view.backgroundColor = .clear
        controller.view.frame = container.bounds
        controller.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        container.isHidden = true
        container.addSubview(controller.view)
        apply(args as? [String: Any] ?? [:])
        container.onWindowChange = { [weak self] in self?.attach() }
        container.onChange = { [weak self] in self?.evaluate() }
        controller.onLayout = { [weak self] in
            guard let self, !self.verified else { return }
            self.evaluate()
        }
        listen()
        // The app font may only be registered after the bar is on screen.
        fontObserver = NotificationCenter.default.addObserver(
            forName: AdaptiveFontRegistry.didRegister,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self, let tabs = self.controller.viewControllers else { return }
            _ = applyAppFont(to: tabs.map(\.tabBarItem))
        }
    }

    deinit {
        fontObserver.map(NotificationCenter.default.removeObserver)
        failureTicks?.invalidate()
    }

    func view() -> UIView { container }

    private static func channel(_ viewId: Int64, _ registrar: FlutterPluginRegistrar) -> FlutterMethodChannel {
        FlutterMethodChannel(
            name: "adaptive_platform_ui/ios26_system_tab_bar_\(viewId)",
            binaryMessenger: registrar.messenger()
        )
    }

    private func listen() {
        channel.setMethodCallHandler { [weak self] call, result in
            guard let self else { result(nil); return }
            self.handle(call, result: result)
        }
    }

    // MARK: Containment

    /// Adds the controller under the Flutter view controller once the view is
    /// in a window: iOS decides where its bar goes from the controller's place
    /// among the window's view controllers.
    private func attach() {
        guard container.window != nil, !(container.superview is SystemTabBarParkingLot) else { return }
        guard let parent = registrar.viewController else {
            return report(available: false, reason: "noViewController")
        }
        if controller.parent !== parent {
            if controller.parent != nil {
                controller.willMove(toParent: nil)
                controller.removeFromParent()
            }
            parent.addChild(controller)
            controller.didMove(toParent: parent)
        }
        evaluate()
    }

    func canBeReused(under viewController: UIViewController?) -> Bool {
        controller.parent == nil || controller.parent === viewController
    }

    /// The slot went: the view waits, hidden in the Flutter view with its
    /// controller, for the next one (iOS26SystemTabBarFactory).
    func chromeWillRemove() {
        channel.setMethodCallHandler(nil)
        stopFailureTicks()
        slot = nil
        setVerified(false)
        guard let onParked, let lot = parkingLot() else { return detach() }
        lot.addSubview(container)
        onParked(self)
    }

    /// Takes the view back for a new slot, with that slot's channel and params.
    /// It is checked again with the slot's first frame, before it shows.
    func reuse(viewId: Int64, args: Any?) {
        channel = Self.channel(viewId, registrar)
        listen()
        reportedAvailable = nil
        failing = nil
        apply(args as? [String: Any] ?? [:])
    }

    /// Lets go of the controller for good.
    func detach() {
        channel.setMethodCallHandler(nil)
        stopFailureTicks()
        container.removeFromSuperview()
        guard controller.parent != nil else { return }
        controller.willMove(toParent: nil)
        controller.view.removeFromSuperview()
        controller.removeFromParent()
    }

    /// Where a parked view waits: hidden, in the Flutter view, so its
    /// controller stays in the window and its bar keeps its layout.
    private func parkingLot() -> UIView? {
        guard let host = registrar.viewController?.view else { return nil }
        if let lot = host.subviews.first(where: { $0 is SystemTabBarParkingLot }) {
            return lot
        }
        let lot = SystemTabBarParkingLot()
        lot.isHidden = true
        lot.isUserInteractionEnabled = false
        host.insertSubview(lot, at: 0)
        return lot
    }

    // MARK: Is iOS's bar where Flutter keeps the tabs?

    private enum Check { case unknown, unsupported, passed, failed }

    /// Whether iOS laid the tabs out in Flutter's slot: a column of tabs, each
    /// centred in the slot and reached by a tap there, with no bar along the
    /// bottom. Public API only, so no iOS release can turn it into a crash or
    /// a private symbol; one that lays the bar out otherwise fails it.
    private func check() -> Check {
        guard let slot, container.window != nil, controller.parent != nil,
              !(container.superview is SystemTabBarParkingLot)
        else { return .unknown }
        guard let edge = Self.verticalBarEdge(of: container.traitCollection) else {
            return .unsupported
        }
        guard edge != 0 else { return .failed }
        guard #available(iOS 17.0, *) else { return .unsupported }
        controller.view.layoutIfNeeded()
        let items = controller.tabBar.items ?? []
        guard !items.isEmpty else { return .failed }
        let area = slot.insetBy(dx: -Self.tolerance, dy: -Self.tolerance)
        let content = controller.selectedViewController?.view
        var lastY = -CGFloat.infinity
        for item in items {
            guard let frame = item.frame(in: container) else { return .failed }
            let centre = CGPoint(x: frame.midX, y: frame.midY)
            guard area.contains(centre), centre.y > lastY else { return .failed }
            lastY = centre.y
            let hit = controller.view.hitTest(container.convert(centre, to: controller.view), with: nil)
            guard let hit, !(content?.isDescendant(of: hit) ?? false) else { return .failed }
        }
        if let content, content.safeAreaInsets.bottom > controller.view.safeAreaInsets.bottom + 1 {
            return .failed
        }
        return .passed
    }

    /// Shows the bar while the check passes and hides it while not. Flutter
    /// is told only once the tabs stay out of place, or can never be checked.
    private func evaluate() {
        switch check() {
        case .unknown:
            setVerified(false)
        case .unsupported:
            setVerified(false)
            report(available: false, reason: "unsupported")
        case .passed:
            failing = nil
            stopFailureTicks()
            setVerified(true)
            report(available: true, reason: nil)
        case .failed:
            setVerified(false)
            let key = "\(slot.map(NSCoder.string(for:)) ?? "-")|\(NSCoder.string(for: container.bounds.size))"
            if failing?.key != key {
                failing = (CACurrentMediaTime(), 0, key)
            } else if let failing, failing.frames >= Self.failureFrames,
                      CACurrentMediaTime() - failing.since >= Self.failureTime {
                stopFailureTicks()
                return report(available: false, reason: "layout")
            }
            startFailureTicks()
        }
    }

    private func setVerified(_ value: Bool) {
        verified = value
        if container.isHidden == value {
            container.isHidden = !value
        }
    }

    /// Checks again each frame while the tabs are out of place: frames the
    /// main thread never got to are no reason to give up.
    private func startFailureTicks() {
        guard failureTicks == nil else { return }
        let link = CADisplayLink(target: FailureTicksTarget(self), selector: #selector(FailureTicksTarget.tick))
        link.add(to: .main, forMode: .common)
        failureTicks = link
    }

    private func stopFailureTicks() {
        failureTicks?.invalidate()
        failureTicks = nil
    }

    fileprivate func failureTick() {
        if let current = failing {
            failing = (current.since, current.frames + 1, current.key)
        }
        evaluate()
    }

    private func report(available: Bool, reason: String?) {
        guard reportedAvailable != available else { return }
        reportedAvailable = available
        var arguments: [String: Any] = ["available": available]
        if let reason { arguments["reason"] = reason }
        channel.invokeMethod("availability", arguments: arguments)
    }

    /// `UITraitCollection.verticalBarEdge` (iOS 27.1, public), read by key so
    /// the plugin still builds against older SDKs: nil where iOS has none.
    private static func verticalBarEdge(of traits: UITraitCollection) -> Int? {
        let key = "verticalBarEdge"
        guard traits.responds(to: NSSelectorFromString(key)) else { return nil }
        return (traits.value(forKey: key) as? NSNumber)?.intValue
    }

    // MARK: Over the Flutter view

    func chromePlaceholderChanged(_ frame: CGRect?) {
        slot = frame
        evaluate()
    }

    /// Touches on the tabs only: in Flutter's slot, while the bar is shown
    /// there, and not on the empty page behind them.
    func chromeHitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        guard verified, let slot,
              slot.insetBy(dx: -Self.tolerance, dy: -Self.tolerance).contains(point),
              let hit = controller.view.hitTest(container.convert(point, to: controller.view), with: event),
              !(controller.selectedViewController?.view.isDescendant(of: hit) ?? false)
        else { return nil }
        return hit
    }

    // MARK: Channel

    private func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        let args = call.arguments as? [String: Any] ?? [:]
        switch call.method {
        case "update":
            apply(args)
            result(nil)
        case "setSelectedIndex":
            if let index = (args["index"] as? NSNumber)?.intValue {
                select(index)
            }
            result(nil)
        default:
            result(FlutterMethodNotImplemented)
        }
    }

    private func apply(_ params: [String: Any]) {
        if let items = params["items"] as? [[String: Any]] {
            setItems(items)
        }
        if let tint = (params["tint"] as? NSNumber)?.intValue {
            // The vertical bar takes the tint of the views it is in, not the
            // tab bar's own `tintColor`, which it leaves at the system blue.
            controller.view.tintColor = UIColor(argb: tint)
            controller.tabBar.tintColor = UIColor(argb: tint)
        }
        if let isDark = params["isDark"] as? Bool {
            controller.overrideUserInterfaceStyle = isDark ? .dark : .light
        }
        if let index = (params["selectedIndex"] as? NSNumber)?.intValue {
            select(index)
        }
    }

    /// A selection from Flutter. iOS tells the delegate nothing of it, so it
    /// is not sent back.
    private func select(_ index: Int) {
        guard index >= 0, index < controller.viewControllers?.count ?? 0,
              controller.selectedIndex != index
        else { return }
        controller.selectedIndex = index
    }

    private func setItems(_ items: [[String: Any]]) {
        var tabs = controller.viewControllers ?? []
        if tabs.count != items.count {
            tabs = items.map { _ in Self.emptyTab() }
            controller.setViewControllers(tabs, animated: false)
            verified = false
        }
        for (tab, item) in zip(tabs, items) {
            Self.configure(tab.tabBarItem, with: item)
        }
        _ = applyAppFont(to: tabs.map(\.tabBarItem))
    }

    /// A tab that shows nothing and takes no touches: Flutter draws the page.
    private static func emptyTab() -> UIViewController {
        let tab = UIViewController()
        tab.view.backgroundColor = .clear
        tab.view.isUserInteractionEnabled = false
        return tab
    }

    private static func configure(_ item: UITabBarItem, with map: [String: Any]) {
        let label = map["label"] as? String ?? map["title"] as? String
        if item.title != label {
            item.title = label
            item.accessibilityLabel = label
        }
        let symbol = map["symbol"] as? String
        let selected = map["selectedSymbol"] as? String ?? symbol
        let asset = map["asset"] as? String
        let key = [symbol, selected, asset].map { $0 ?? "" }.joined(separator: "|")
        if item.accessibilityIdentifier != key {
            item.accessibilityIdentifier = key
            item.image = image(symbol: symbol, asset: asset)
            item.selectedImage = image(symbol: selected, asset: asset) ?? item.image
        }
        let badge = (map["badge"] as? NSNumber)?.intValue
        iOS26TabBarPlatformView.applyBadge(
            to: item, count: badge, text: nil, colorARGB: nil, textColorARGB: nil
        )
    }

    private static func image(symbol: String?, asset: String?) -> UIImage? {
        if let symbol, !symbol.isEmpty {
            return (UIImage(systemName: symbol) ?? UIImage(named: symbol))?
                .withRenderingMode(.alwaysTemplate)
        }
        if let asset, !asset.isEmpty {
            return UIImage(named: FlutterDartProject.lookupKey(forAsset: asset))?
                .withRenderingMode(.alwaysTemplate)
        }
        return nil
    }

    // MARK: UITabBarControllerDelegate

    func tabBarController(
        _ tabBarController: UITabBarController,
        didSelect viewController: UIViewController
    ) {
        // Also for the tab already selected: the app may act on a second tap.
        channel.invokeMethod("valueChanged", arguments: ["index": tabBarController.selectedIndex])
    }
}

/// Tells when iOS laid the tab bar controller's views out.
private final class SystemTabBarController: UITabBarController {
    var onLayout: (() -> Void)?

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        onLayout?()
    }
}

/// Holds the tab bar controller's view, and tells when it lands in a window
/// and when its size or traits change.
private final class SystemTabBarContainerView: UIView {
    var onWindowChange: (() -> Void)?
    var onChange: (() -> Void)?
    private var laidOutSize: CGSize?

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
    }

    required init?(coder: NSCoder) { nil }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        onWindowChange?()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard bounds.size != laidOutSize else { return }
        laidOutSize = bounds.size
        onChange?()
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        onChange?()
    }
}

/// Where a view whose slot went waits for the next one, hidden.
private final class SystemTabBarParkingLot: UIView {}

/// The display link's target, holding the view weakly: a display link keeps
/// its target alive until it is invalidated.
private final class FailureTicksTarget: NSObject {
    private weak var view: iOS26SystemTabBarView?

    init(_ view: iOS26SystemTabBarView) {
        self.view = view
    }

    @objc func tick() {
        view?.failureTick()
    }
}
