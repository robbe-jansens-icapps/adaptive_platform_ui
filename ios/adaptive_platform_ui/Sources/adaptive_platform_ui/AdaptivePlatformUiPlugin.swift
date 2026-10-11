import Flutter
import UIKit

/// Main plugin class for Adaptive Platform UI
/// Registers platform views and handles plugin lifecycle
public class AdaptivePlatformUiPlugin: NSObject, FlutterPlugin {

    /// The radius of the corners of the app's window, which on a phone are
    /// the display's: measured on a view that fills the window, with corners
    /// concentric with it. 0 before iOS 26 and without a window.
    private static func displayCornerRadius() -> Double {
        guard #available(iOS 26.0, *) else { return 0 }
        let window = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first { $0.isKeyWindow }
        guard let window else { return 0 }
        let probe = UIView(frame: window.bounds)
        probe.isHidden = true
        probe.isUserInteractionEnabled = false
        probe.cornerConfiguration = .corners(radius: .containerConcentric())
        window.addSubview(probe)
        defer { probe.removeFromSuperview() }
        return Double(probe.effectiveRadius(corner: .bottomLeft))
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
    }
}
