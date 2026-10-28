import Flutter
import UIKit

/// A native view hosted over the Flutter view can take only some touches on
/// it (Dart: AdaptiveNativeView with `chrome: true`), such as those on a
/// bar's items, leaving the rest to the Flutter content around them: the view
/// to take the touch at `point` (in its own coordinates), or nil.
protocol ChromeHitRegion: AnyObject {
    func chromeHitTest(_ point: CGPoint, with event: UIEvent?) -> UIView?
}

/// The shape a dialog's barrier dims on a native view hosted over the Flutter
/// view, which the barrier cannot reach: its glass rather than its bounds.
/// Nil dims the whole view.
protocol ChromeDimmable: AnyObject {
    func chromeDimPath() -> UIBezierPath?
}

/// Native views shown over the Flutter view instead of inside it as platform
/// views (Dart: AdaptiveNativeView with `chrome: true`).
///
/// With a platform view on screen the engine draws every frame through extra
/// Metal surfaces presented in a Core Animation transaction on the main
/// thread, which Dart shares, and it pays for that per view. Views hosted
/// here are plain subviews of one root view above the Flutter content: Flutter
/// keeps an empty placeholder in their place and sends where each one is,
/// once per frame something changed, so the engine stays on its fast path.
///
/// Flutter's message for a frame arrives before the frame's pixels, which the
/// engine sets on the Flutter view's layer once the frame is rendered. Moved
/// at once, a view would be a frame ahead of the content around it whenever
/// the two landed on either side of a refresh. So each frame's message waits
/// for that frame's pixels, and is applied in the same Core Animation
/// transaction: Flutter sends one for every frame while views are shown, in
/// the order of the frames, and the frames come in the same order.
///
/// The views are made by the same factories as the platform views, so each
/// keeps its own channel and native logic.
final class NativeChromeHost: NSObject {
    /// Values per view in a `layout` batch (Dart: NativeChromeCoordinator).
    private static let stride = 29
    fileprivate static let hiddenFlag = 1
    fileprivate static let interactiveFlag = 2

    private static let attachInterval: TimeInterval = 0.05

    /// Messages that wait for their frame's pixels, oldest first. More than
    /// this many means frames went by without pixels (the engine left one
    /// out), and the oldest are applied at once.
    private static let maxPending = 2

    /// How long a message waits for its frame's pixels before it is applied
    /// all the same, about two refreshes: for a frame the engine never shows.
    private static let pendingTimeout: TimeInterval = 0.034

    private let registrar: FlutterPluginRegistrar
    private let factories: [String: FlutterPlatformViewFactory]
    private var slots: [Int64: NativeChromeSlot] = [:]
    private var root: NativeChromeRootView?
    private var attachScheduled = false

    private var pending: [(serial: Int, data: FlutterStandardTypedData)] = []
    private var nextSerial = 0
    private var framesObservation: NSKeyValueObservation?
    private weak var observedLayer: CALayer?

    private init(
        registrar: FlutterPluginRegistrar,
        factories: [String: FlutterPlatformViewFactory]
    ) {
        self.registrar = registrar
        self.factories = factories
        super.init()
    }

    static func register(
        with registrar: FlutterPluginRegistrar,
        factories: [String: FlutterPlatformViewFactory]
    ) {
        let host = NativeChromeHost(registrar: registrar, factories: factories)
        let channel = FlutterMethodChannel(
            name: "adaptive_platform_ui/native_chrome",
            binaryMessenger: registrar.messenger()
        )
        // The channel holds the host for as long as the engine runs.
        channel.setMethodCallHandler { call, result in
            host.handle(call, result: result)
        }
    }

    private func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        let args = call.arguments as? [String: Any] ?? [:]
        switch call.method {
        case "create":
            guard let id = (args["id"] as? NSNumber)?.int64Value,
                  let viewType = args["viewType"] as? String,
                  let factory = factories[viewType]
            else {
                result(FlutterError(code: "unknown_view_type", message: nil, details: nil))
                return
            }
            slots[id]?.remove()
            let platformView = factory.create(
                withFrame: .zero,
                viewIdentifier: id,
                arguments: args["params"]
            )
            let slot = NativeChromeSlot(platformView: platformView)
            slots[id] = slot
            if let root = attachedRoot() {
                root.addSubview(slot.clipView)
            }
            result(nil)
        case "dispose":
            if let id = (args["id"] as? NSNumber)?.int64Value {
                slots.removeValue(forKey: id)?.remove()
            }
            result(nil)
        case "layout":
            if let data = call.arguments as? FlutterStandardTypedData {
                enqueue(data)
            }
            result(nil)
        case "reset":
            // A hot restart: the views of the isolate before are gone in Dart.
            for slot in slots.values {
                slot.remove()
            }
            slots.removeAll()
            pending.removeAll()
            // Each frame's message is applied with its pixels.
            result(["frameLocked": true])
        default:
            result(FlutterMethodNotImplemented)
        }
    }

    private func enqueue(_ data: FlutterStandardTypedData) {
        // Placed over the Flutter view, the root view watches its frames.
        guard attachedRoot() != nil, observedLayer != nil else {
            apply(data)
            return
        }
        let serial = nextSerial
        nextSerial += 1
        pending.append((serial, data))
        while pending.count > Self.maxPending {
            apply(pending.removeFirst().data)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.pendingTimeout) { [weak self] in
            self?.applyPending(through: serial)
        }
    }

    /// The engine set the pixels of the next frame on the Flutter view: its
    /// message goes with them.
    private func framePresented() {
        guard !pending.isEmpty else { return }
        apply(pending.removeFirst().data)
    }

    private func applyPending(through serial: Int) {
        while let first = pending.first, first.serial <= serial {
            pending.removeFirst()
            apply(first.data)
        }
    }

    private func observeFrames(of host: UIView) {
        guard observedLayer !== host.layer else { return }
        observedLayer = host.layer
        framesObservation = host.layer.observe(\.contents, options: []) { [weak self] _, _ in
            self?.framePresented()
        }
    }

    private func apply(_ data: FlutterStandardTypedData) {
        let count = Int(data.elementCount)
        guard count > 0, let root = attachedRoot() else { return }
        var reorder = false
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        data.data.withUnsafeBytes { raw in
            let values = raw.bindMemory(to: Float64.self)
            var i = 0
            while i + Self.stride <= count {
                let id = Int64(values[i])
                if let slot = slots[id] {
                    reorder = slot.apply(values, at: i, in: root.bounds) || reorder
                }
                i += Self.stride
            }
        }
        if reorder {
            for slot in slots.values.sorted(by: { $0.z < $1.z }) {
                root.bringSubviewToFront(slot.clipView)
            }
        }
        if let host = root.superview, host.subviews.last !== root {
            host.bringSubviewToFront(root)
        }
        CATransaction.commit()
    }

    /// The root view over the Flutter view, put in place once the Flutter view
    /// controller has a view: with an implicit engine that comes after the
    /// plugins register, so it is tried again until then.
    private func attachedRoot() -> NativeChromeRootView? {
        if let root, root.superview != nil { return root }
        guard let host = registrar.viewController?.view else {
            scheduleAttach()
            return nil
        }
        let root = root ?? NativeChromeRootView(host: self)
        root.frame = host.bounds
        host.addSubview(root)
        Self.keepLast(in: host)
        observeFrames(of: host)
        self.root = root
        for slot in slots.values.sorted(by: { $0.z < $1.z }) {
            root.addSubview(slot.clipView)
        }
        return root
    }

    private func scheduleAttach() {
        guard !attachScheduled, !slots.isEmpty else { return }
        attachScheduled = true
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.attachInterval) { [weak self] in
            guard let self else { return }
            self.attachScheduled = false
            _ = self.attachedRoot()
        }
    }

    /// The topmost view that takes the touch at `point`: the views are tried
    /// from the top, each only where it is shown, takes touches and claims the
    /// point. Nil lets the touch through to Flutter.
    fileprivate func hitTest(
        _ point: CGPoint, in root: UIView, with event: UIEvent?
    ) -> UIView? {
        for case let clipView as NativeChromeClipView in root.subviews.reversed() {
            guard let slot = clipView.slot, slot.interactive,
                  !clipView.isHidden, clipView.alpha > 0.01
            else { continue }
            if clipView.clipsToBounds,
               !clipView.bounds.contains(root.convert(point, to: clipView)) {
                continue
            }
            let hosted = slot.hosted
            let local = root.convert(point, to: hosted)
            let hit = if let region = slot.platformView as? ChromeHitRegion {
                region.chromeHitTest(local, with: event)
            } else {
                hosted.hitTest(local, with: event)
            }
            if let hit { return hit }
        }
        return nil
    }

    private static var hookedClasses = Set<ObjectIdentifier>()

    /// Keeps the root view last among the Flutter view's subviews, where
    /// touches are tried first. The engine adds its platform views and their
    /// overlays to the Flutter view as they come, and a map filling the screen
    /// would otherwise take every touch meant for the views above it.
    private static func keepLast(in host: UIView) {
        let cls: AnyClass = type(of: host)
        guard hookedClasses.insert(ObjectIdentifier(cls)).inserted,
              let superclass = class_getSuperclass(cls),
              let method = class_getInstanceMethod(UIView.self, #selector(UIView.didAddSubview(_:)))
        else { return }
        let selector = #selector(UIView.didAddSubview(_:))
        typealias DidAddSubview = @convention(c) (UIView, Selector, UIView) -> Void
        let callSuper = unsafeBitCast(
            class_getMethodImplementation(superclass, selector),
            to: DidAddSubview.self
        )
        let block: @convention(block) (UIView, UIView) -> Void = { view, subview in
            callSuper(view, selector, subview)
            guard !(subview is NativeChromeRootView),
                  let root = view.subviews.last(where: { $0 is NativeChromeRootView }),
                  view.subviews.last !== root
            else { return }
            view.bringSubviewToFront(root)
        }
        // Fails if the class has its own didAddSubview; then `apply` raises the
        // root view on each layout instead.
        class_addMethod(
            cls, selector, imp_implementationWithBlock(block),
            method_getTypeEncoding(method)
        )
    }
}

/// One hosted view: a clip view for the clip of its Flutter placeholder, in
/// it a view taking the placeholder's size and transform, and in that the
/// view the factory made.
private final class NativeChromeSlot {
    let platformView: FlutterPlatformView
    let hosted: UIView
    let clipView = NativeChromeClipView()
    let transformView = NativeChromeTouchSink()
    private let dimLayer = CAShapeLayer()

    private(set) var z: Double = -1
    private(set) var interactive = false

    init(platformView: FlutterPlatformView) {
        self.platformView = platformView
        hosted = platformView.view()
        clipView.slot = self
        clipView.isHidden = true
        transformView.layer.anchorPoint = .zero
        hosted.frame = .zero
        hosted.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        transformView.addSubview(hosted)
        dimLayer.isHidden = true
        transformView.layer.addSublayer(dimLayer)
        clipView.addSubview(transformView)
    }

    func remove() {
        clipView.removeFromSuperview()
    }

    /// Applies one view's values of a `layout` batch; true when its place
    /// among the other views changed.
    func apply(
        _ values: UnsafeBufferPointer<Float64>, at offset: Int, in rootBounds: CGRect
    ) -> Bool {
        func value(_ index: Int) -> CGFloat { CGFloat(values[offset + index]) }
        let flags = Int(values[offset + 27])
        interactive = flags & NativeChromeHost.interactiveFlag != 0
        if flags & NativeChromeHost.hiddenFlag != 0 {
            clipView.isHidden = true
            return false
        }

        let size = CGSize(width: value(1), height: value(2))
        if transformView.bounds.size != size {
            transformView.bounds = CGRect(origin: .zero, size: size)
        }
        let matrix = CATransform3D(
            m11: value(3), m12: value(4), m13: value(5), m14: value(6),
            m21: value(7), m22: value(8), m23: value(9), m24: value(10),
            m31: value(11), m32: value(12), m33: value(13), m34: value(14),
            m41: value(15), m42: value(16), m43: value(17), m44: value(18)
        )
        let clip: CGRect
        if values[offset + 20] != 0 {
            clip = CGRect(
                x: value(21), y: value(22),
                width: value(23) - value(21), height: value(24) - value(22)
            )
            clipView.clipsToBounds = true
            clipView.layer.cornerRadius = value(25)
        } else {
            clip = rootBounds
            clipView.clipsToBounds = false
            clipView.layer.cornerRadius = 0
        }
        clipView.frame = clip
        transformView.layer.position = .zero
        transformView.layer.transform = CATransform3DConcat(
            matrix, CATransform3DMakeTranslation(-clip.minX, -clip.minY, 0)
        )
        clipView.alpha = value(19)
        applyDim(Int(values[offset + 28]))
        clipView.isHidden = false

        let newZ = values[offset + 26]
        defer { z = newZ }
        return newZ != z
    }

    /// Lays a dialog's barrier over the view, in its colour as Flutter worked
    /// it out for the glass under it; 0 for none.
    private func applyDim(_ argb: Int) {
        guard argb != 0 else {
            dimLayer.isHidden = true
            return
        }
        dimLayer.isHidden = false
        dimLayer.frame = transformView.bounds
        dimLayer.fillColor = UIColor(argb: argb).cgColor
        let path = (platformView as? ChromeDimmable)?.chromeDimPath()
            ?? UIBezierPath(rect: transformView.bounds)
        dimLayer.path = path.cgPath
    }
}

/// Takes the touches that reach it and passes none on: a touch on a hosted
/// view that the view itself does not use would otherwise go up the responder
/// chain to the Flutter view, and Flutter would see a touch under the view.
private class NativeChromeTouchSink: UIView {
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {}
    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {}
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {}
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {}
}

private final class NativeChromeClipView: NativeChromeTouchSink {
    weak var slot: NativeChromeSlot?
}

/// Lies over the Flutter content and takes only the touches its views claim.
/// Hidden from VoiceOver: Flutter lays its own semantics over each view.
private final class NativeChromeRootView: NativeChromeTouchSink {
    private weak var host: NativeChromeHost?

    init(host: NativeChromeHost) {
        self.host = host
        super.init(frame: .zero)
        autoresizingMask = [.flexibleWidth, .flexibleHeight]
        // Over the platform views and their overlays, under the snapshot the
        // engine shows of the keyboard while it hides (z NSIntegerMax).
        layer.zPosition = 1e6
        accessibilityElementsHidden = true
    }

    required init?(coder: NSCoder) { nil }

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        host?.hitTest(point, in: self, with: event)
    }
}
