import Flutter
import UIKit

/// The system's date picker in a sheet of its own (Dart:
/// AdaptiveDatePicker.show on iOS 26), which UIKit presents over the Flutter
/// view. UIKit makes the picker before the sheet moves and slides the sheet
/// up in Core Animation, so it comes up with the picker drawn and keeps every
/// frame of the slide while the main thread, which Dart shares, is busy. No
/// Flutter route covers the page meanwhile: its bar and native views stay as
/// they are, under UIKit's dimming.
///
/// `show` answers once the sheet is done: the date picked in milliseconds,
/// nil when it was closed, or an `unavailable` error when there was nothing
/// to present it from.
enum DatePickerSheet {
    static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(
            name: "adaptive_platform_ui/date_picker_sheet",
            binaryMessenger: registrar.messenger()
        )
        channel.setMethodCallHandler { [weak registrar] call, result in
            guard call.method == "show", #available(iOS 26.0, *) else {
                result(FlutterMethodNotImplemented)
                return
            }
            DatePickerSheetController.present(
                params: call.arguments as? [String: Any] ?? [:],
                over: registrar?.viewController,
                result: result
            )
        }
    }
}

/// A sheet with a close button, an optional title and a checkmark above the
/// picker, as tall as they need at the sheet's width, and no taller than the
/// window: then the picker scrolls.
@available(iOS 26.0, *)
final class DatePickerSheetController: UIViewController,
    UISheetPresentationControllerDelegate
{
    /// The buttons' row: 14 points above the 44 point buttons, 4 below.
    private static let headerHeight: CGFloat = 62
    private static let buttonInset: CGFloat = 14
    private static let buttonSize: CGFloat = 44

    /// The picker's room from the sheet's sides.
    private static let sideMargin: CGFloat = 12

    /// The width of a sheet in a regular width window, or along the bottom of
    /// a landscape iPhone, where it does not float.
    private static let fixedWidth: CGFloat = 440

    /// How far a floating sheet keeps from the window's sides, as UIKit last
    /// laid one out: the picker is measured for that width before the next
    /// one is presented.
    private static var floatingInset: CGFloat = 8

    private let picker = UIDatePicker()
    private lazy var calendarDays = CalendarDays(picker: picker)
    private let scrollView = UIScrollView()
    private let holder = UIView()
    private lazy var holderHeight = holder.heightAnchor.constraint(equalToConstant: 0)
    private let titleLabel = UILabel()
    private let closeButton = UIButton(type: .system)
    private let confirmButton = UIButton(type: .system)

    private let params: [String: Any]
    private var reply: FlutterResult?

    /// Room below the picker, the more the rounder the display's corners, as
    /// the sheet's bottom corners follow them.
    private let bottomRoom: CGFloat

    /// The height the picker needs at [measuredWidth] and [measuredTextSize].
    private var pickerHeight: CGFloat = 0
    private var measuredWidth: CGFloat = 0
    private var measuredTextSize: UIContentSizeCategory?

    /// The window size and text size the sheet went to its full height for,
    /// its content taller than that. It stays there until either changes:
    /// edge to edge it is wider, and the picker, laid out wider, can fit
    /// again, which would take it back to its narrower, floating self, where
    /// it would not.
    private var cappedFor: (window: CGSize, textSize: UIContentSizeCategory)?

    /// Taps on the checkmark are let through again from then on: just after
    /// it took the calendar back to its days, the second tap of a double tap
    /// would take it to its month and year wheels again.
    private var confirmBlockedUntil: CFTimeInterval = 0

    private init(params: [String: Any], result: @escaping FlutterResult) {
        self.params = params
        reply = result
        let concentric = max(34, CGFloat(AdaptivePlatformUiPlugin.displayCornerRadius()) - 8)
        bottomRoom = 12 + max(0, (concentric - 34) * 0.4)
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .formSheet
        // The app's reading direction, which can differ from the device's.
        traitOverrides.layoutDirection =
            (params["rtl"] as? Bool ?? false) ? .rightToLeft : .leftToRight
        if let sheet = sheetPresentationController {
            // The app's appearance, which can differ from the window's: on the
            // presentation, so the sheet's glass takes it along with its
            // content.
            sheet.traitOverrides.userInterfaceStyle =
                (params["isDark"] as? Bool ?? false) ? .dark : .light
            sheet.detents = [
                .custom(identifier: .init("content")) { [weak self] context in
                    self?.detentHeight(maximum: context.maximumDetentValue)
                        ?? context.maximumDetentValue
                },
            ]
            sheet.prefersGrabberVisible = false
            // Along the bottom of a landscape iPhone, rather than covering
            // the Flutter view, which would then take the app as gone.
            sheet.prefersEdgeAttachedInCompactHeight = true
            sheet.widthFollowsPreferredContentSizeWhenEdgeAttached = true
            sheet.delegate = self
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    deinit {
        reply?(nil)
    }

    /// Presents a sheet for [params] above [flutterViewController] and
    /// whatever is presented over it, and answers [result] once it is done.
    static func present(
        params: [String: Any],
        over flutterViewController: UIViewController?,
        result: @escaping FlutterResult
    ) {
        guard let presenter = presenter(above: flutterViewController) else {
            result(unavailable)
            return
        }
        // A sheet that has just been closed is still on its way down: what
        // is presented meanwhile is dropped.
        if let transition = presenter.transitionCoordinator {
            var retried = false
            let retry = {
                guard !retried else { return }
                retried = true
                present(params: params, over: flutterViewController, result: result)
            }
            if !transition.animate(alongsideTransition: nil, completion: { _ in retry() }) {
                DispatchQueue.main.async(execute: retry)
            }
            return
        }
        let sheet = DatePickerSheetController(params: params, result: result)
        sheet.prepare(for: presenter)
        presenter.present(sheet, animated: true)
        if presenter.presentedViewController !== sheet {
            sheet.finish(unavailable)
        }
    }

    private static var unavailable: FlutterError {
        FlutterError(
            code: "unavailable",
            message: "Nothing to present the date picker sheet from",
            details: nil
        )
    }

    /// What presents the sheet: the Flutter view's controller, or what is
    /// presented over it and not on its way out. The Flutter view sits in a
    /// tab bar controller of its own without its controller among the tab
    /// bar controller's (iOS26NativeTabBarManager): the window's root
    /// presents then.
    private static func presenter(
        above flutterViewController: UIViewController?
    ) -> UIViewController? {
        guard let flutterViewController,
              let window = flutterViewController.viewIfLoaded?.window
        else { return nil }
        let inHierarchy = window.rootViewController === flutterViewController
            || flutterViewController.parent != nil
            || flutterViewController.presentingViewController != nil
        guard var top = inHierarchy ? flutterViewController : window.rootViewController
        else { return nil }
        while let presented = top.presentedViewController, !presented.isBeingDismissed {
            top = presented
        }
        return top
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.accessibilityViewIsModal = true

        configure(
            closeButton,
            glass: .glass(),
            symbol: "xmark",
            label: params["closeLabel"] as? String,
            identifier: "adaptive_date_picker_close",
            action: #selector(close)
        )
        configure(
            confirmButton,
            glass: .prominentGlass(),
            symbol: "checkmark",
            glyphColor: .white,
            label: params["confirmLabel"] as? String,
            identifier: "adaptive_date_picker_confirm",
            action: #selector(confirm)
        )
        if let tint = params["tint"] as? NSNumber {
            confirmButton.tintColor = UIColor(argb: tint.intValue)
        }

        titleLabel.text = params["title"] as? String
        titleLabel.font = .preferredFont(forTextStyle: .headline)
        titleLabel.adjustsFontForContentSizeCategory = true
        // The title shares a row of fixed height with the buttons.
        titleLabel.maximumContentSizeCategory = .extraExtraExtraLarge
        titleLabel.textAlignment = .center
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.accessibilityTraits.insert(.header)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(titleLabel)

        DatePickerSetup.configure(picker, with: params)
        picker.translatesAutoresizingMaskIntoConstraints = false
        holder.addSubview(picker)
        holder.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(holder)
        scrollView.contentInsetAdjustmentBehavior = .scrollableAxes
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scrollView)

        // Clear of what the system keeps for itself along the sides, as the
        // picker keeps its own content: the iPhone Duo's vertical bar, beside
        // which a sheet on the cover display runs on.
        let sides = view.safeAreaLayoutGuide
        let centeredTitle = titleLabel.centerXAnchor.constraint(equalTo: sides.centerXAnchor)
        centeredTitle.priority = .defaultHigh
        NSLayoutConstraint.activate([
            closeButton.leadingAnchor.constraint(
                equalTo: sides.leadingAnchor, constant: Self.buttonInset
            ),
            confirmButton.trailingAnchor.constraint(
                equalTo: sides.trailingAnchor, constant: -Self.buttonInset
            ),
            titleLabel.centerYAnchor.constraint(equalTo: closeButton.centerYAnchor),
            centeredTitle,
            titleLabel.leadingAnchor.constraint(
                greaterThanOrEqualTo: closeButton.trailingAnchor, constant: 8
            ),
            titleLabel.trailingAnchor.constraint(
                lessThanOrEqualTo: confirmButton.leadingAnchor, constant: -8
            ),

            scrollView.topAnchor.constraint(equalTo: view.topAnchor, constant: Self.headerHeight),
            scrollView.leadingAnchor.constraint(equalTo: sides.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: sides.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            holder.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            holder.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            holder.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
            holder.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
            holder.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor),
            holderHeight,
            // Pinned on all sides, at the height measured for its width: left
            // to find its own height, the calendar can lay itself out again
            // and again at some widths and text sizes (iOS26DatePickerView).
            picker.topAnchor.constraint(equalTo: holder.topAnchor),
            picker.leadingAnchor.constraint(equalTo: holder.leadingAnchor, constant: Self.sideMargin),
            picker.trailingAnchor.constraint(equalTo: holder.trailingAnchor, constant: -Self.sideMargin),
            picker.bottomAnchor.constraint(equalTo: holder.bottomAnchor, constant: -bottomRoom),
        ])

        registerForTraitChanges([UITraitPreferredContentSizeCategory.self]) {
            (controller: DatePickerSheetController, _: UITraitCollection) in
            controller.view.setNeedsLayout()
        }
    }

    private func configure(
        _ button: UIButton,
        glass: UIButton.Configuration,
        symbol: String,
        glyphColor: UIColor? = nil,
        label: String?,
        identifier: String,
        action: Selector
    ) {
        var configuration = glass
        let image = UIImage(
            systemName: symbol,
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 17, weight: .semibold)
        )
        if let glyphColor {
            // In that colour outright: prominent glass mixes its tint into
            // the colour asked of its configuration.
            configuration.image = image?.withTintColor(glyphColor, renderingMode: .alwaysOriginal)
        } else {
            configuration.image = image
            configuration.baseForegroundColor = .label
        }
        configuration.cornerStyle = .capsule
        configuration.contentInsets = .zero
        button.configuration = configuration
        button.accessibilityLabel = label
        button.accessibilityIdentifier = identifier
        button.addTarget(self, action: action, for: .primaryActionTriggered)
        button.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(button)
        NSLayoutConstraint.activate([
            button.topAnchor.constraint(equalTo: view.topAnchor, constant: Self.buttonInset),
            button.widthAnchor.constraint(equalToConstant: Self.buttonSize),
            button.heightAnchor.constraint(equalToConstant: Self.buttonSize),
        ])
    }

    /// Measures the picker for the sheet [presenter] will show it in, before
    /// it does: the sheet then comes up at its height.
    private func prepare(for presenter: UIViewController) {
        let traits = presenter.traitCollection
        // Out of a window, the sheet has no text size of its own yet.
        traitOverrides.preferredContentSizeCategory = traits.preferredContentSizeCategory
        loadViewIfNeeded()
        let window = presenter.view.window
        let windowWidth = window?.bounds.width ?? presenter.view.bounds.width
        let floats = traits.horizontalSizeClass == .compact && traits.verticalSizeClass != .compact
        var width = min(Self.fixedWidth, windowWidth)
        if floats {
            // Across the window, less the system's room along its sides that
            // the sheet runs on into.
            let insets = window?.safeAreaInsets ?? .zero
            width = windowWidth - 2 * Self.floatingInset
                - max(0, insets.left - Self.floatingInset)
                - max(0, insets.right - Self.floatingInset)
        }
        measure(pickerWidth: width - 2 * Self.sideMargin)
        preferredContentSize = CGSize(width: Self.fixedWidth, height: contentHeight)
    }

    override func viewIsAppearing(_ animated: Bool) {
        super.viewIsAppearing(animated)
        traitOverrides.remove(UITraitPreferredContentSizeCategory.self)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        if cappedFor == nil, let window = view.window,
           traitCollection.horizontalSizeClass == .compact,
           traitCollection.verticalSizeClass != .compact {
            Self.floatingInset = max(0, (window.bounds.width - view.bounds.width) / 2)
        }
        let width = view.safeAreaLayoutGuide.layoutFrame.width
        guard measure(pickerWidth: width - 2 * Self.sideMargin) else { return }
        preferredContentSize = CGSize(width: Self.fixedWidth, height: contentHeight)
        // Not while UIKit lays the sheet out.
        DispatchQueue.main.async { [weak self] in
            guard let sheet = self?.sheetPresentationController else { return }
            sheet.animateChanges { sheet.invalidateDetents() }
        }
    }

    /// Measures the picker at [pickerWidth] and the text size, unless it was
    /// already; says whether the height it needs changed.
    @discardableResult
    private func measure(pickerWidth: CGFloat) -> Bool {
        let textSize = traitCollection.preferredContentSizeCategory
        guard pickerWidth > 0,
              abs(pickerWidth - measuredWidth) > 0.5 || textSize != measuredTextSize
        else { return false }
        measuredWidth = pickerWidth
        measuredTextSize = textSize
        let height = DatePickerSetup.height(of: picker, width: pickerWidth)
        guard height != pickerHeight else { return false }
        pickerHeight = height
        holderHeight.constant = height + bottomRoom
        return true
    }

    private var contentHeight: CGFloat {
        Self.headerHeight + pickerHeight + bottomRoom
    }

    private func detentHeight(maximum: CGFloat) -> CGFloat {
        let window = view.window?.bounds.size ?? .zero
        let textSize = traitCollection.preferredContentSizeCategory
        if let cappedFor, cappedFor.window == window, cappedFor.textSize == textSize {
            return maximum
        }
        guard contentHeight < maximum else {
            cappedFor = (window, textSize)
            return maximum
        }
        cappedFor = nil
        return contentHeight
    }

    @objc private func confirm() {
        guard reply != nil, CACurrentMediaTime() >= confirmBlockedUntil else { return }
        if calendarDays.show() {
            confirmBlockedUntil = CACurrentMediaTime() + 0.4
            return
        }
        finish(DatePickerSetup.millis(picker.date))
        dismiss(animated: true)
    }

    @objc private func close() {
        guard reply != nil else { return }
        finish(nil)
        dismiss(animated: true)
    }

    // A swipe down, or a tap beside the sheet.
    func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
        finish(nil)
    }

    // Taken away with what presented it, which tells no delegate.
    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        if isBeingDismissed || presentingViewController == nil {
            finish(nil)
        }
    }

    private func finish(_ value: Any?) {
        guard let reply else { return }
        self.reply = nil
        reply(value)
    }
}
