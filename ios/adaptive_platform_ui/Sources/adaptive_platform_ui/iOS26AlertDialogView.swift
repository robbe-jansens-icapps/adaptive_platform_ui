import Flutter
import UIKit

/// A UIAlertController that manages its own background dimming
class TintAdjustingAlertController: UIAlertController {
    private var backgroundDimmingView: UIView?

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        // Disable automatic tint adjustment
        if let presentingVC = presentingViewController {
            presentingVC.view.tintAdjustmentMode = .normal
            if let navController = presentingVC as? UINavigationController {
                navController.navigationBar.tintAdjustmentMode = .normal
                navController.viewControllers.forEach { $0.view.tintAdjustmentMode = .normal }
            }
        }

        // Add custom dimming view
        addCustomDimmingView()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)

        // Remove custom dimming and restore normal tint
        removeCustomDimmingView()

        // Force all views to normal tint mode
        if let presentingVC = presentingViewController {
            presentingVC.view.tintAdjustmentMode = .automatic
            if let navController = presentingVC as? UINavigationController {
                navController.navigationBar.tintAdjustmentMode = .automatic
                navController.viewControllers.forEach { $0.view.tintAdjustmentMode = .automatic }
            }
        }
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        removeCustomDimmingView()
    }

    private func addCustomDimmingView() {
        guard let presentingVC = presentingViewController,
              backgroundDimmingView == nil else { return }

        let dimmingView = UIView()
        dimmingView.backgroundColor = UIColor.black.withAlphaComponent(0.3)
        dimmingView.frame = presentingVC.view.bounds
        dimmingView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        dimmingView.alpha = 0

        presentingVC.view.insertSubview(dimmingView, belowSubview: view)
        backgroundDimmingView = dimmingView

        UIView.animate(withDuration: 0.3) {
            dimmingView.alpha = 1
        }
    }

    private func removeCustomDimmingView() {
        guard let dimmingView = backgroundDimmingView else { return }

        UIView.animate(withDuration: 0.3, animations: {
            dimmingView.alpha = 0
        }) { _ in
            dimmingView.removeFromSuperview()
        }

        backgroundDimmingView = nil
    }
}

/// Platform view for iOS 26 alert dialog
class iOS26AlertDialogView: NSObject, FlutterPlatformView {
    private let channel: FlutterMethodChannel
    private let container: UIView
    private var alertController: TintAdjustingAlertController?
    private var alertStyle: String = "glass"

    init(frame: CGRect, viewId: Int64, args: Any?, messenger: FlutterBinaryMessenger) {
        self.channel = FlutterMethodChannel(name: "adaptive_platform_ui/ios26_alert_dialog_\(viewId)", binaryMessenger: messenger)
        self.container = UIView(frame: frame)

        var title: String = ""
        var message: String? = nil
        var actionTitles: [String] = []
        var actionStyles: [String] = []
        var actionEnabled: [Bool] = []
        var oneTimeCode: String? = nil
        var isDark: Bool = false
        var tint: UIColor? = nil
        var alertStyleParam: String = "glass"
        var textFieldPlaceholder: String? = nil
        var textFieldInitialValue: String? = nil
        var textFieldObscureText: Bool = false
        var textFieldMaxLength: Int? = nil
        var textFieldKeyboardType: String? = nil

        if let dict = args as? [String: Any] {
            if let t = dict["title"] as? String { title = t }
            if let m = dict["message"] as? String { message = m }
            if let at = dict["actionTitles"] as? [String] { actionTitles = at }
            if let ast = dict["actionStyles"] as? [String] { actionStyles = ast }
            if let ae = dict["actionEnabled"] as? [Bool] { actionEnabled = ae }
            if let otc = dict["oneTimeCode"] as? String { oneTimeCode = otc }
            if let v = dict["isDark"] as? NSNumber { isDark = v.boolValue }
            if let t = dict["tint"] as? NSNumber { tint = UIColor(argb: t.intValue) }
            if let alertStyleValue = dict["alertStyle"] as? String { alertStyleParam = alertStyleValue }
            if let tfp = dict["textFieldPlaceholder"] as? String { textFieldPlaceholder = tfp }
            if let tfiv = dict["textFieldInitialValue"] as? String { textFieldInitialValue = tfiv }
            if let tfot = dict["textFieldObscureText"] as? Bool { textFieldObscureText = tfot }
            if let tfml = dict["textFieldMaxLength"] as? NSNumber { textFieldMaxLength = tfml.intValue }
            if let tfkt = dict["textFieldKeyboardType"] as? String { textFieldKeyboardType = tfkt }
        }

        self.alertStyle = alertStyleParam

        super.init()

        setupAlert(
            title: title,
            message: message,
            actionTitles: actionTitles,
            actionStyles: actionStyles,
            actionEnabled: actionEnabled,
            oneTimeCode: oneTimeCode,
            isDark: isDark,
            tint: tint,
            textFieldPlaceholder: textFieldPlaceholder,
            textFieldInitialValue: textFieldInitialValue,
            textFieldObscureText: textFieldObscureText,
            textFieldMaxLength: textFieldMaxLength,
            textFieldKeyboardType: textFieldKeyboardType
        )

        self.channel.setMethodCallHandler(onMethodCall)
    }

    func view() -> UIView {
        return container
    }

    private func setupAlert(
        title: String,
        message: String?,
        actionTitles: [String],
        actionStyles: [String],
        actionEnabled: [Bool],
        oneTimeCode: String?,
        isDark: Bool,
        tint: UIColor?,
        textFieldPlaceholder: String?,
        textFieldInitialValue: String?,
        textFieldObscureText: Bool,
        textFieldMaxLength: Int?,
        textFieldKeyboardType: String?
    ) {
        // Create TintAdjustingAlertController
        alertController = TintAdjustingAlertController(title: title, message: message, preferredStyle: .alert)

        guard let alert = alertController else { return }

        // Apply liquid glass styling for iOS 15+
        if #available(iOS 15.0, *) {
            // Configure with iOS corner radius and continuous curve
            alert.view.layer.cornerRadius = 28.0
            alert.view.layer.cornerCurve = .continuous

            // Add subtle shadow for depth
            alert.view.layer.shadowOpacity = 0.1
            alert.view.layer.shadowOffset = CGSize(width: 0, height: 2)
            alert.view.layer.shadowRadius = 10
            alert.view.layer.masksToBounds = false

            // Add glass effect with proper iOS materials
            let blurEffect = UIBlurEffect(style: isDark ? .systemThinMaterialDark : .systemThinMaterialLight)
            let blurView = UIVisualEffectView(effect: blurEffect)
            blurView.frame = alert.view.bounds
            blurView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            blurView.layer.cornerRadius = 28.0
            blurView.layer.cornerCurve = .continuous
            blurView.clipsToBounds = true

            // Insert blur view behind content
            alert.view.insertSubview(blurView, at: 0)

            // Make alert background transparent to show blur
            alert.view.backgroundColor = UIColor.clear

            // Apply tint if available
            if let tintColor = tint {
                alert.view.tintColor = tintColor
            }
        }

        // UIKit has no public API for content of one's own in an alert: a
        // one-time code shows in the message, and an icon not at all.
        if let otpCode = oneTimeCode {
            alert.message = [message, otpCode].compactMap { $0 }.joined(separator: "\n\n")
        }

        // Add text field if placeholder is provided
        if let placeholder = textFieldPlaceholder {
            alert.addTextField { textField in
                textField.placeholder = placeholder
                textField.text = textFieldInitialValue
                textField.isSecureTextEntry = textFieldObscureText

                // Set keyboard type
                if let keyboardType = textFieldKeyboardType {
                    switch keyboardType {
                    case "emailAddress":
                        textField.keyboardType = .emailAddress
                    case "number":
                        textField.keyboardType = .numberPad
                    case "phone":
                        textField.keyboardType = .phonePad
                    case "url":
                        textField.keyboardType = .URL
                    default:
                        textField.keyboardType = .default
                    }
                }

                // Add max length if specified
                if let maxLength = textFieldMaxLength {
                    textField.addTarget(self, action: #selector(self.textFieldDidChange(_:)), for: .editingChanged)
                    textField.accessibilityValue = "\(maxLength)" // Store maxLength in accessibilityValue
                }
            }
        }

        // Add actions
        var primaryAction: UIAlertAction?

        for (index, actionTitle) in actionTitles.enumerated() {
            let style = index < actionStyles.count ? actionStyles[index] : "defaultAction"
            let enabled = index < actionEnabled.count ? actionEnabled[index] : true

            // UIKit has no public API for an action's own colour or font: the
            // preferred action is bold, a destructive one red, the rest tinted.
            let alertActionStyle: UIAlertAction.Style = style == "destructive" ? .destructive : .default

            let action = UIAlertAction(title: actionTitle, style: alertActionStyle) { [weak self] _ in
                guard let self = self, let alert = self.alertController else { return }

                // Get text field value if exists
                var textFieldValue: String? = nil
                if let textField = alert.textFields?.first {
                    textFieldValue = textField.text
                }

                var arguments: [String: Any] = ["index": index]
                if let value = textFieldValue {
                    arguments["textFieldValue"] = value
                }

                self.channel.invokeMethod("actionPressed", arguments: arguments)
            }

            action.isEnabled = enabled && style != "disabled"
            alert.addAction(action)
            if style == "primary" {
                primaryAction = action
            }
        }

        // Only promote explicit primary actions.
        // A cancel action should remain neutral and must not force the
        // alert tint to red when no primary action is present.
        if let action = primaryAction {
            alert.preferredAction = action
            alert.view.tintColor = tint ?? UIColor.systemBlue
        }

        // Present the alert
        DispatchQueue.main.async { [weak self] in
            if let topController = self?.topViewController() {
                topController.present(alert, animated: true)
            }
        }
    }

    @objc private func textFieldDidChange(_ textField: UITextField) {
        // Enforce max length if stored in accessibilityValue
        if let maxLengthString = textField.accessibilityValue,
           let maxLength = Int(maxLengthString),
           let text = textField.text,
           text.count > maxLength {
            textField.text = String(text.prefix(maxLength))
        }
    }

    private func topViewController() -> UIViewController? {
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let window = windowScene.windows.first else {
            return nil
        }

        var topController = window.rootViewController
        while let presentedController = topController?.presentedViewController {
            topController = presentedController
        }
        return topController
    }

    private func onMethodCall(call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "setBrightness":
            if let args = call.arguments as? [String: Any],
               let isDark = args["isDark"] as? Bool {
                updateBrightness(isDark: isDark)
            }
            result(nil)

        case "setStyle":
            if let args = call.arguments as? [String: Any],
               let tint = args["tint"] as? NSNumber {
                updateStyle(tint: UIColor(argb: tint.intValue))
            }
            result(nil)

        default:
            result(FlutterMethodNotImplemented)
        }
    }

    private func updateBrightness(isDark: Bool) {
        guard let alert = alertController else { return }

        if #available(iOS 15.0, *) {
            if alertStyle == "glass" {
                let blurEffect = UIBlurEffect(style: isDark ? .systemThinMaterialDark : .systemThinMaterialLight)

                for subview in alert.view.subviews {
                    if let blurView = subview as? UIVisualEffectView {
                        blurView.effect = blurEffect
                        break
                    }
                }
            }
        }
    }

    private func updateStyle(tint: UIColor) {
        guard let alert = alertController else { return }
        alert.view.tintColor = tint
    }
}

/// Factory for creating iOS26AlertDialogView instances
class iOS26AlertDialogViewFactory: NSObject, FlutterPlatformViewFactory {
    private let messenger: FlutterBinaryMessenger

    init(messenger: FlutterBinaryMessenger) {
        self.messenger = messenger
        super.init()
    }

    func create(withFrame frame: CGRect, viewIdentifier viewId: Int64, arguments args: Any?) -> FlutterPlatformView {
        return iOS26AlertDialogView(frame: frame, viewId: viewId, args: args, messenger: messenger)
    }

    func createArgsCodec() -> FlutterMessageCodec & NSObjectProtocol {
        return FlutterStandardMessageCodec.sharedInstance()
    }
}
