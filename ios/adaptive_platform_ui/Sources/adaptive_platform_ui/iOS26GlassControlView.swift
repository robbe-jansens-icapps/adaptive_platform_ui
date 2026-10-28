import Flutter
import UIKit

class iOS26GlassControlFactory: NSObject, FlutterPlatformViewFactory {
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
        iOS26GlassControlView(viewIdentifier: viewId, binaryMessenger: messenger)
    }

    func createArgsCodec() -> FlutterMessageCodec & NSObjectProtocol {
        FlutterStandardMessageCodec.sharedInstance()
    }
}

/// A Liquid Glass capsule with an icon, a label and a trailing icon (Dart:
/// IOS26GlassControl), shown over the Flutter view. Flutter lays them out and
/// tells where each one goes; the label is drawn in the app font, the icons
/// from images Flutter took of its own. The glass answers touches as UIKit's
/// own glass buttons do.
class iOS26GlassControlView: NSObject, FlutterPlatformView {
    private let container = UIView()
    private let effectView = UIVisualEffectView(effect: nil)
    private let leadingView = UIImageView()
    private let label = UILabel()
    private let trailingView = UIImageView()
    private let channel: FlutterMethodChannel

    /// The least a touch target is across, as UIKit's own.
    private static let minimumTarget: CGFloat = 44

    init(viewIdentifier viewId: Int64, binaryMessenger messenger: FlutterBinaryMessenger) {
        channel = FlutterMethodChannel(
            name: "adaptive_platform_ui/ios26_glass_control_\(viewId)",
            binaryMessenger: messenger
        )
        super.init()

        container.backgroundColor = .clear
        effectView.frame = container.bounds
        effectView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        container.addSubview(effectView)
        if #available(iOS 26.0, *) {
            effectView.cornerConfiguration = .capsule()
        } else {
            effectView.clipsToBounds = true
        }

        label.lineBreakMode = .byTruncatingTail
        for view in [leadingView, label, trailingView] as [UIView] {
            view.isUserInteractionEnabled = false
            view.isHidden = true
            effectView.contentView.addSubview(view)
        }
        leadingView.contentMode = .center
        trailingView.contentMode = .center

        let tap = UITapGestureRecognizer(target: self, action: #selector(tapped(_:)))
        container.addGestureRecognizer(tap)

        channel.setMethodCallHandler { [weak self] call, result in
            guard let self, let args = call.arguments as? [String: Any] else {
                result(FlutterMethodNotImplemented)
                return
            }
            switch call.method {
            case "update":
                self.apply(args)
                result(nil)
            case "setImage":
                self.setImage(args)
                result(nil)
            default:
                result(FlutterMethodNotImplemented)
            }
        }
    }

    func view() -> UIView {
        container
    }

    private func apply(_ params: [String: Any]) {
        let isDark = params["isDark"] as? Bool ?? false
        container.overrideUserInterfaceStyle = isDark ? .dark : .light
        let interactive = params["interactive"] as? Bool ?? false
        container.isUserInteractionEnabled = interactive

        let tint = (params["tint"] as? NSNumber).map { UIColor(argb: $0.intValue) }
        if #available(iOS 26.0, *) {
            let glass = UIGlassEffect(style: .regular)
            glass.tintColor = tint
            glass.isInteractive = interactive
            effectView.effect = glass
        } else {
            effectView.effect = UIBlurEffect(style: .systemThinMaterial)
            effectView.layer.cornerRadius = container.bounds.height / 2
        }

        let size = CGFloat((params["fontSize"] as? NSNumber)?.doubleValue ?? 14)
        let weight = (params["fontWeight"] as? NSNumber)?.intValue ?? 400
        label.font = AdaptiveFontRegistry.shared.font(weight: weight, size: size)
            ?? .systemFont(ofSize: size, weight: Self.systemWeight(weight))
        label.textColor = (params["labelColor"] as? NSNumber).map { UIColor(argb: $0.intValue) }
        label.text = params["label"] as? String

        place(leadingView, at: params["leading"])
        place(label, at: params["labelFrame"])
        place(trailingView, at: params["trailing"])
    }

    private func place(_ view: UIView, at frame: Any?) {
        guard let values = frame as? [NSNumber], values.count == 4 else {
            view.isHidden = true
            return
        }
        view.frame = CGRect(
            x: values[0].doubleValue, y: values[1].doubleValue,
            width: values[2].doubleValue, height: values[3].doubleValue
        )
        view.isHidden = false
    }

    private func setImage(_ args: [String: Any]) {
        guard let bytes = args["bytes"] as? FlutterStandardTypedData else { return }
        let scale = CGFloat((args["scale"] as? NSNumber)?.doubleValue ?? UIScreen.main.scale)
        let image = UIImage(data: bytes.data, scale: scale)
        switch args["slot"] as? String {
        case "leading": leadingView.image = image
        case "trailing": trailingView.image = image
        default: break
        }
    }

    @objc private func tapped(_ recognizer: UITapGestureRecognizer) {
        let point = recognizer.location(in: effectView.contentView)
        let target = trailingView.frame.insetBy(
            dx: min(0, (trailingView.frame.width - Self.minimumTarget) / 2),
            dy: min(0, (trailingView.frame.height - Self.minimumTarget) / 2)
        )
        let onTrailing = !trailingView.isHidden && target.contains(point)
        channel.invokeMethod(onTrailing ? "trailingPressed" : "pressed", arguments: nil)
    }

    private static func systemWeight(_ weight: Int) -> UIFont.Weight {
        switch weight {
        case ..<200: return .ultraLight
        case ..<300: return .thin
        case ..<400: return .light
        case ..<500: return .regular
        case ..<600: return .medium
        case ..<700: return .semibold
        case ..<800: return .bold
        case ..<900: return .heavy
        default: return .black
        }
    }
}

/// Over the Flutter view, a dialog's barrier dims the control's capsule.
extension iOS26GlassControlView: ChromeDimmable {
    func chromeDimPath() -> UIBezierPath? {
        let bounds = container.bounds
        return UIBezierPath(
            roundedRect: bounds,
            cornerRadius: min(bounds.width, bounds.height) / 2
        )
    }
}
