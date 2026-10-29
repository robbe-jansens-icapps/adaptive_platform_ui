import Flutter
import UIKit

class iOS26GlassSurfaceFactory: NSObject, FlutterPlatformViewFactory {
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
        iOS26GlassSurfaceView(
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

/// A Liquid Glass surface: Flutter draws the content on top of it, or, over
/// the Flutter view (Dart: `chrome`), gives an image of it to show.
///
/// It never takes touches, and it rounds its own corners, because a Flutter
/// clip or opacity around a platform view becomes a mask or an alpha on it,
/// which breaks the glass.
class iOS26GlassSurfaceView: NSObject, FlutterPlatformView {
    private let container = UIView()
    private let effectView = UIVisualEffectView(effect: nil)
    /// Over the glass, in its shape: a partly opaque fill lets less of what is
    /// behind the glass show through.
    private let fillView = UIView()
    /// Over the fill: the image of the content, over the Flutter view.
    private let contentImageView = UIImageView()
    private let channel: FlutterMethodChannel

    init(
        frame: CGRect,
        viewIdentifier viewId: Int64,
        arguments args: Any?,
        binaryMessenger messenger: FlutterBinaryMessenger
    ) {
        channel = FlutterMethodChannel(
            name: "adaptive_platform_ui/ios26_glass_surface_\(viewId)",
            binaryMessenger: messenger
        )
        super.init()

        container.frame = frame
        container.backgroundColor = .clear
        container.isUserInteractionEnabled = false

        effectView.frame = container.bounds
        effectView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        effectView.isUserInteractionEnabled = false
        container.addSubview(effectView)

        fillView.frame = effectView.contentView.bounds
        fillView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        fillView.isUserInteractionEnabled = false
        fillView.isHidden = true
        effectView.contentView.addSubview(fillView)

        contentImageView.frame = effectView.contentView.bounds
        contentImageView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        // At its own size: one taken before the glass changed size stays as
        // it is until the next one.
        contentImageView.contentMode = .topLeft
        contentImageView.isUserInteractionEnabled = false
        effectView.contentView.addSubview(contentImageView)

        if let params = args as? [String: Any] {
            apply(params)
        }

        channel.setMethodCallHandler { [weak self] call, result in
            if call.method == "update", let params = call.arguments as? [String: Any] {
                self?.apply(params)
                result(nil)
            } else if call.method == "setContent", let args = call.arguments as? [String: Any] {
                self?.setContent(args)
                result(nil)
            } else {
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

        let radius = (params["cornerRadius"] as? NSNumber)?.doubleValue ?? 0
        let tint = (params["tint"] as? NSNumber).map { color(argb: $0.intValue) }
        let fill = (params["fill"] as? NSNumber).map { color(argb: $0.intValue) }
        fillView.backgroundColor = fill
        fillView.isHidden = fill == nil

        if #available(iOS 26.0, *) {
            let glass = UIGlassEffect(style: params["style"] as? String == "clear" ? .clear : .regular)
            glass.tintColor = tint
            glass.isInteractive = params["interactive"] as? Bool ?? false
            effectView.effect = glass
            let corners: UICornerConfiguration
            switch params["corners"] as? String {
            case "capsule":
                corners = .capsule()
            case "concentric":
                // Follows the corners of the display, never below `radius`.
                corners = .corners(radius: .containerConcentric(minimum: radius))
            default:
                corners = .corners(radius: .fixed(radius))
            }
            effectView.cornerConfiguration = corners
            // Inside the glass, concentric corners follow the glass's own: the
            // fill has the glass's shape.
            fillView.cornerConfiguration = corners
        } else {
            effectView.effect = UIBlurEffect(style: .systemThinMaterial)
            effectView.layer.cornerRadius = radius
            effectView.layer.cornerCurve = .continuous
            effectView.clipsToBounds = true
        }
    }

    private func setContent(_ args: [String: Any]) {
        guard let bytes = args["bytes"] as? FlutterStandardTypedData else { return }
        let scale = CGFloat((args["scale"] as? NSNumber)?.doubleValue ?? UIScreen.main.scale)
        contentImageView.image = UIImage(data: bytes.data, scale: scale)
    }

    private func color(argb: Int) -> UIColor {
        UIColor(
            red: CGFloat((argb >> 16) & 0xFF) / 255,
            green: CGFloat((argb >> 8) & 0xFF) / 255,
            blue: CGFloat(argb & 0xFF) / 255,
            alpha: CGFloat((argb >> 24) & 0xFF) / 255
        )
    }
}
