import Flutter
import UIKit

class iOS26BarBackdropFactory: NSObject, FlutterPlatformViewFactory {
    private let messenger: FlutterBinaryMessenger

    init(messenger: FlutterBinaryMessenger) {
        self.messenger = messenger
        super.init()
    }

    func create(
        withFrame frame: CGRect,
        viewIdentifier viewId: Int64,
        arguments args: Any?
    ) -> FlutterPlatformView {
        iOS26BarBackdropView(
            frame: frame,
            viewIdentifier: viewId,
            arguments: args,
            binaryMessenger: messenger
        )
    }

    func createArgsCodec() -> FlutterMessageCodec & NSObjectProtocol {
        FlutterStandardMessageCodec.sharedInstance()
    }
}

/// What the fixed toolbar has behind it: nothing while the page rests at its
/// top, and the system's bar blur while content is scrolled underneath, its
/// lower edge softened. A UIKit blur, so it blurs everything below it, native
/// views included, the way the system bars do.
///
/// It shows and hides itself by animating its effect: an alpha on a blur
/// breaks it, so it is never faded.
class iOS26BarBackdropView: NSObject, FlutterPlatformView {
    private let container = BarBackdropContainer()
    private let channel: FlutterMethodChannel
    private var visible: Bool?

    init(
        frame: CGRect,
        viewIdentifier viewId: Int64,
        arguments args: Any?,
        binaryMessenger messenger: FlutterBinaryMessenger
    ) {
        channel = FlutterMethodChannel(
            name: "adaptive_platform_ui/ios26_bar_backdrop_\(viewId)",
            binaryMessenger: messenger
        )
        super.init()

        container.frame = frame
        if let params = args as? [String: Any] {
            apply(params, animated: false)
        }

        channel.setMethodCallHandler { [weak self] call, result in
            if call.method == "update", let params = call.arguments as? [String: Any] {
                self?.apply(params, animated: true)
                result(nil)
            } else {
                result(FlutterMethodNotImplemented)
            }
        }
    }

    func view() -> UIView {
        container
    }

    private func apply(_ params: [String: Any], animated: Bool) {
        let isDark = params["isDark"] as? Bool ?? false
        container.overrideUserInterfaceStyle = isDark ? .dark : .light
        container.fade = CGFloat((params["fade"] as? NSNumber)?.doubleValue ?? 16)

        let visible = params["visible"] as? Bool ?? false
        guard visible != self.visible else { return }
        self.visible = visible
        let effect: UIVisualEffect? = visible ? UIBlurEffect(style: .systemUltraThinMaterial) : nil
        guard animated else {
            container.effectView.effect = effect
            return
        }
        UIView.animate(
            withDuration: 0.25,
            delay: 0,
            options: [.beginFromCurrentState, .allowUserInteraction, .curveEaseOut]
        ) {
            self.container.effectView.effect = effect
        }
    }
}

/// The blur, masked so that it fades out over its last `fade` points.
final class BarBackdropContainer: UIView {
    let effectView = UIVisualEffectView(effect: nil)
    private let fadeMask = GradientMaskView()

    var fade: CGFloat = 16 {
        didSet {
            if fade != oldValue { setNeedsLayout() }
        }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isUserInteractionEnabled = false
        effectView.isUserInteractionEnabled = false
        addSubview(effectView)
        effectView.mask = fadeMask
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        effectView.frame = bounds
        // A mask is not in the view hierarchy, so it is laid out by hand.
        fadeMask.frame = effectView.bounds
        fadeMask.solidUntil = bounds.height > 0 ? max(0, (bounds.height - fade) / bounds.height) : 1
    }
}

/// Opaque down to `solidUntil` (a fraction of its height), clear at the bottom.
final class GradientMaskView: UIView {
    override class var layerClass: AnyClass { CAGradientLayer.self }

    var solidUntil: CGFloat = 1 {
        didSet { updateGradient() }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        updateGradient()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func updateGradient() {
        guard let gradient = layer as? CAGradientLayer else { return }
        gradient.colors = [UIColor.black.cgColor, UIColor.black.cgColor, UIColor.clear.cgColor]
        gradient.locations = [0, NSNumber(value: Double(solidUntil)), 1]
    }
}
