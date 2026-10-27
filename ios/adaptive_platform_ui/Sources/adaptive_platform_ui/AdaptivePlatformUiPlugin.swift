import Flutter
import UIKit

/// Main plugin class for Adaptive Platform UI
/// Registers platform views and handles plugin lifecycle
public class AdaptivePlatformUiPlugin: NSObject, FlutterPlugin {

    /// The radius of the corners of the app's window, which on a phone are
    /// the display's: measured on a view that fills the window, with corners
    /// concentric with it. 0 before iOS 26 and without a window.
    static func displayCornerRadius() -> Double {
        guard #available(iOS 26.0, *) else { return 0 }
        // The key window, or else one of the app's windows: asked as the app
        // starts, it may have one that is not key yet.
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let windows = scenes.flatMap { $0.windows }
        let window = windows.first { $0.isKeyWindow }
            ?? scenes.first { $0.activationState == .foregroundActive }?.windows.first
            ?? windows.first
        guard let window else { return 0 }
        let probe = UIView(frame: window.bounds)
        probe.isHidden = true
        probe.isUserInteractionEnabled = false
        probe.cornerConfiguration = .corners(radius: .containerConcentric())
        window.addSubview(probe)
        defer { probe.removeFromSuperview() }
        return Double(probe.effectiveRadius(corner: .bottomLeft))
    }

    /// The glyph of a native glass button with the SF Symbol `name` at `size`
    /// points and `weight` (a Flutter FontWeight value), as iOS26ButtonView
    /// shows it in a button `side` points square: the button is made the same
    /// way and laid out, as its configuration can show the symbol at another
    /// size than the image it is given. In black on clear at the screen's
    /// scale, as PNG, a mask for Flutter to tint, with the colour the button
    /// draws it in (ARGB) in the light or dark appearance. For Flutter to stand
    /// in for the button. Nil for a symbol iOS lacks.
    private static func buttonGlyph(
        name: String, size: Double, weight: Int?, side: Double, isDark: Bool
    ) -> [String: Any]? {
        guard #available(iOS 15.0, *),
              let base = UIImage(systemName: name) ?? UIImage(named: name)
        else { return nil }
        let image = base.applyingSymbolConfiguration(
            UIImage.SymbolConfiguration(
                pointSize: CGFloat(size),
                weight: iOS26ButtonView.symbolWeight(weight)
            )
        ) ?? base

        // As iOS26ButtonView makes a glass button without a colour of its own.
        let button = UIButton(type: .system)
        button.overrideUserInterfaceStyle = isDark ? .dark : .light
        button.tintColor = .systemBlue
        var config: UIButton.Configuration
        if #available(iOS 26.0, *) {
            config = .glass()
        } else {
            config = .plain()
        }
        config.baseForegroundColor = .systemBlue
        config.contentInsets = NSDirectionalEdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16)
        config.cornerStyle = .capsule
        config.image = image
        button.configuration = config
        button.frame = CGRect(x: 0, y: 0, width: side, height: side)
        button.layoutIfNeeded()

        // The symbol as the button shows it, at the size and in the place it
        // shows it.
        var shown = image
        var shownSize = image.size
        var center = CGPoint(x: side / 2, y: side / 2)
        if let imageView = button.imageView, let displayed = imageView.image,
           imageView.bounds.width > 0, imageView.bounds.height > 0 {
            shown = displayed
            if let preferred = imageView.preferredSymbolConfiguration,
               let configured = displayed.applyingSymbolConfiguration(preferred) {
                shown = configured
            }
            shownSize = imageView.bounds.size
            center = imageView.convert(
                CGPoint(x: imageView.bounds.midX, y: imageView.bounds.midY),
                to: button
            )
        }
        // A glass button shows its glyph in the label colour, whatever colour
        // its configuration asks for (measured on device: #0D0D0D in the light
        // appearance, the label's black through the glass). Before iOS 26 the
        // plain button shows the configuration's.
        let shownColor: UIColor
        if #available(iOS 26.0, *) {
            shownColor = .label
        } else {
            shownColor = button.configuration?.baseForegroundColor ?? .systemBlue
        }
        // In the appearance the button is in, named outright: a button that is
        // in no window does not take its override into its traits, and would
        // resolve the colour for the device's appearance instead.
        let color = shownColor.resolvedColor(
            with: UITraitCollection(userInterfaceStyle: isDark ? .dark : .light)
        )

        let window = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first { $0.isKeyWindow }
        let scale = window?.screen.scale ?? UIScreen.main.scale
        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        let rendered = UIGraphicsImageRenderer(size: shownSize, format: format).image { _ in
            // Fitted as the image view fits it.
            let fit = min(
                shownSize.width / max(shown.size.width, 1),
                shownSize.height / max(shown.size.height, 1)
            )
            let drawn = CGSize(width: shown.size.width * fit, height: shown.size.height * fit)
            shown.withTintColor(.black, renderingMode: .alwaysOriginal).draw(in: CGRect(
                x: (shownSize.width - drawn.width) / 2,
                y: (shownSize.height - drawn.height) / 2,
                width: drawn.width,
                height: drawn.height
            ))
        }
        guard let data = rendered.pngData() else { return nil }
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        color.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        func byte(_ v: CGFloat) -> Int { Int((min(max(v, 0), 1) * 255).rounded()) }
        let argb = byte(alpha) << 24 | byte(red) << 16 | byte(green) << 8 | byte(blue)
        return [
            "bytes": FlutterStandardTypedData(bytes: data),
            "scale": Double(scale),
            "color": argb,
            // Where the glyph's centre is off the button's.
            "dx": Double(center.x - side / 2),
            "dy": Double(center.y - side / 2),
        ]
    }

    public static func register(with registrar: FlutterPluginRegistrar) {
        // The app font for native text (Dart: AdaptiveNativeFonts)
        let fontsChannel = FlutterMethodChannel(
            name: "adaptive_platform_ui/fonts",
            binaryMessenger: registrar.messenger()
        )
        fontsChannel.setMethodCallHandler { call, result in
            guard call.method == "register" else {
                result(FlutterMethodNotImplemented)
                return
            }
            let fonts = (call.arguments as? [String: Any])?["fonts"] as? [[String: Any]] ?? []
            AdaptiveFontRegistry.shared.register(fonts)
            result(nil)
        }

        // The glyphs of native glass buttons drawn into images (Dart:
        // GlassButtonGlyph), for their Flutter stand-ins while pages move.
        let symbolsChannel = FlutterMethodChannel(
            name: "adaptive_platform_ui/symbols",
            binaryMessenger: registrar.messenger()
        )
        symbolsChannel.setMethodCallHandler { call, result in
            guard call.method == "buttonGlyph",
                  let args = call.arguments as? [String: Any],
                  let name = args["name"] as? String
            else {
                result(FlutterMethodNotImplemented)
                return
            }
            result(buttonGlyph(
                name: name,
                size: (args["size"] as? NSNumber)?.doubleValue ?? 24,
                weight: (args["weight"] as? NSNumber)?.intValue,
                side: (args["side"] as? NSNumber)?.doubleValue ?? 44,
                isDark: (args["isDark"] as? NSNumber)?.boolValue ?? false
            ))
        }

        // What the device is (Dart: PlatformInfo.isIPad): iPad windows have
        // window controls that the fixed toolbar keeps clear of. And how round
        // the corners of its display are (Dart:
        // PlatformInfo.displayCornerRadius), which glass with concentric
        // corners follows.
        let deviceChannel = FlutterMethodChannel(
            name: "adaptive_platform_ui/device",
            binaryMessenger: registrar.messenger()
        )
        deviceChannel.setMethodCallHandler { call, result in
            switch call.method {
            case "isPad":
                result(UIDevice.current.userInterfaceIdiom == .pad)
            case "displayCornerRadius":
                result(displayCornerRadius())
            case "lockAppearance":
                // Dart: AdaptiveBrightnessLock.
                let style = (call.arguments as? [String: Any])?["style"] as? String
                AppearanceLock.shared.lock(
                    style == "dark" ? .dark : style == "light" ? .light : .unspecified
                )
                result(nil)
            default:
                result(FlutterMethodNotImplemented)
            }
        }

        // Initialize iOS 26+ Native Tab Bar Manager
        if #available(iOS 26.0, *) {
            iOS26NativeTabBarManager.shared.setup(messenger: registrar.messenger())
        }

        // Register iOS 26 Button platform view factory
        let ios26ButtonFactory = iOS26ButtonViewFactory(messenger: registrar.messenger())
        registrar.register(
            ios26ButtonFactory,
            withId: "adaptive_platform_ui/ios26_button"
        )

        // The system's date picker (Dart: IOS26DatePicker)
        registrar.register(
            iOS26DatePickerViewFactory(messenger: registrar.messenger()),
            withId: "adaptive_platform_ui/ios26_date_picker"
        )

        // The system's date picker in a sheet of its own (Dart:
        // AdaptiveDatePicker.show)
        DatePickerSheet.register(with: registrar)

        // Register iOS 26 Switch platform view factory
        let ios26SwitchFactory = iOS26SwitchViewFactory(messenger: registrar.messenger())
        registrar.register(
            ios26SwitchFactory,
            withId: "adaptive_platform_ui/ios26_switch"
        )

        // Register iOS 26 Slider platform view factory
        let ios26SliderFactory = iOS26SliderViewFactory(messenger: registrar.messenger())
        registrar.register(
            ios26SliderFactory,
            withId: "adaptive_platform_ui/ios26_slider"
        )

        // Register iOS 26 SegmentedControl platform view factory
        let ios26SegmentedControlFactory = iOS26SegmentedControlViewFactory(messenger: registrar.messenger())
        registrar.register(
            ios26SegmentedControlFactory,
            withId: "adaptive_platform_ui/ios26_segmented_control"
        )

        // Register iOS 26 AlertDialog platform view factory
        let ios26AlertDialogFactory = iOS26AlertDialogViewFactory(messenger: registrar.messenger())
        registrar.register(
            ios26AlertDialogFactory,
            withId: "adaptive_platform_ui/ios26_alert_dialog"
        )

        // Register iOS 26 PopupMenuButton platform view factory
        let ios26PopupMenuButtonFactory = iOS26PopupMenuButtonViewFactory(messenger: registrar.messenger())
        registrar.register(
            ios26PopupMenuButtonFactory,
            withId: "adaptive_platform_ui/ios26_popup_menu_button"
        )

        // Register iOS 26 ContextMenu platform view factory
        let ios26ContextMenuFactory = iOS26ContextMenuViewFactory(messenger: registrar.messenger())
        registrar.register(
            ios26ContextMenuFactory,
            withId: "adaptive_platform_ui/ios26_context_menu"
        )

        // Register iOS 26 TabBar platform view factory
        let ios26TabBarFactory = iOS26TabBarViewFactory(messenger: registrar.messenger())
        registrar.register(
            ios26TabBarFactory,
            withId: "adaptive_platform_ui/ios26_tab_bar"
        )

        // Register iOS 26 Toolbar platform view factory
        let ios26ToolbarFactory = iOS26ToolbarFactory(messenger: registrar.messenger())
        registrar.register(
            ios26ToolbarFactory,
            withId: "adaptive_platform_ui/ios26_toolbar"
        )

        // Register iOS 26 Blur View platform view factory
        let ios26BlurViewFactory = iOS26BlurViewFactory(messenger: registrar.messenger())
        registrar.register(
            ios26BlurViewFactory,
            withId: "adaptive_platform_ui/ios26_blur_view"
        )

        // Register the Liquid Glass capsule used by the iPhone Duo trailing bar
        let ios26GlassCapsuleFactory = iOS26GlassCapsuleFactory(messenger: registrar.messenger())
        registrar.register(
            ios26GlassCapsuleFactory,
            withId: "adaptive_platform_ui/ios26_glass_capsule"
        )

        // Register the Liquid Glass surface that Flutter content is drawn on
        let ios26GlassSurfaceFactory = iOS26GlassSurfaceFactory(messenger: registrar.messenger())
        registrar.register(
            ios26GlassSurfaceFactory,
            withId: "adaptive_platform_ui/ios26_glass_surface"
        )

        // iPhone Duo: where the system puts its vertical bar (iOS 27.1)
        let verticalBarEdgeChannel = FlutterEventChannel(
            name: "adaptive_platform_ui/vertical_bar_edge",
            binaryMessenger: registrar.messenger()
        )
        verticalBarEdgeChannel.setStreamHandler(VerticalBarEdgeStreamHandler(registrar: registrar))
    }
}

/// Holds the app's windows in one appearance (Dart: AdaptiveBrightnessLock),
/// whatever the device's: for an app without a design for the other one, so
/// that menus, alerts, pickers and every other view UIKit draws on its own
/// match the Flutter pages. `.unspecified` lets them follow the device again.
final class AppearanceLock {
    static let shared = AppearanceLock()

    private var style: UIUserInterfaceStyle = .unspecified
    private var observer: NSObjectProtocol?

    func lock(_ style: UIUserInterfaceStyle) {
        self.style = style
        for window in Self.windows() {
            window.overrideUserInterfaceStyle = style
        }
        // Windows that come later, such as one on another display of the
        // iPhone Duo, are held the same way.
        if style != .unspecified, observer == nil {
            observer = NotificationCenter.default.addObserver(
                forName: UIWindow.didBecomeVisibleNotification,
                object: nil,
                queue: .main
            ) { [weak self] note in
                guard let self, self.style != .unspecified,
                      let window = note.object as? UIWindow
                else { return }
                window.overrideUserInterfaceStyle = self.style
            }
        } else if style == .unspecified, let observer {
            NotificationCenter.default.removeObserver(observer)
            self.observer = nil
        }
    }

    private static func windows() -> [UIWindow] {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
    }
}
