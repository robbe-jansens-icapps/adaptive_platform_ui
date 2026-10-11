import Flutter
import UIKit

/// Factory for the native date picker (Dart: IOS26DatePicker).
class iOS26DatePickerViewFactory: NSObject, FlutterPlatformViewFactory {
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
        return iOS26DatePickerView(
            frame: frame,
            viewIdentifier: viewId,
            arguments: args,
            binaryMessenger: messenger
        )
    }

    func createArgsCodec() -> FlutterMessageCodec & NSObjectProtocol {
        return FlutterStandardMessageCodec.sharedInstance()
    }
}

/// The system's date picker: the calendar of iOS (inline), or its wheels.
/// Reports every date picked, and the height it needs at the width it gets.
class iOS26DatePickerView: NSObject, FlutterPlatformView {
    private let container: LayoutReportingView
    private let picker = UIDatePicker()
    private let channel: FlutterMethodChannel
    private var reportedWidth: CGFloat = 0

    init(
        frame: CGRect,
        viewIdentifier viewId: Int64,
        arguments args: Any?,
        binaryMessenger messenger: FlutterBinaryMessenger
    ) {
        container = LayoutReportingView(frame: frame)
        channel = FlutterMethodChannel(
            name: "adaptive_platform_ui/ios26_date_picker_\(viewId)",
            binaryMessenger: messenger
        )
        super.init()

        let params = args as? [String: Any] ?? [:]
        container.backgroundColor = .clear
        container.overrideUserInterfaceStyle =
            (params["isDark"] as? Bool ?? false) ? .dark : .light

        picker.datePickerMode = Self.mode(params["mode"] as? String)
        picker.preferredDatePickerStyle =
            (params["style"] as? String) == "wheels" ? .wheels : .inline
        if let locale = params["locale"] as? String {
            picker.locale = Locale(identifier: locale)
        }
        if let interval = params["minuteInterval"] as? Int, interval > 0 {
            picker.minuteInterval = interval
        }
        if let minimum = params["minimum"] as? NSNumber {
            picker.minimumDate = Self.date(minimum)
        }
        if let maximum = params["maximum"] as? NSNumber {
            picker.maximumDate = Self.date(maximum)
        }
        if let initial = params["initial"] as? NSNumber {
            picker.date = Self.date(initial)
        }
        if let tint = params["tint"] as? NSNumber {
            picker.tintColor = UIColor(argb: tint.intValue)
        }
        picker.addTarget(self, action: #selector(changed), for: .valueChanged)

        picker.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(picker)
        NSLayoutConstraint.activate([
            picker.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            picker.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            picker.topAnchor.constraint(equalTo: container.topAnchor),
        ])
        container.onLayout = { [weak self] width in self?.reportHeight(for: width) }
    }

    func view() -> UIView {
        return container
    }

    @objc private func changed() {
        channel.invokeMethod(
            "changed",
            arguments: ["date": picker.date.timeIntervalSince1970 * 1000]
        )
    }

    private func reportHeight(for width: CGFloat) {
        guard width > 0, width != reportedWidth else { return }
        reportedWidth = width
        let size = picker.systemLayoutSizeFitting(
            CGSize(width: width, height: UIView.layoutFittingCompressedSize.height),
            withHorizontalFittingPriority: .required,
            verticalFittingPriority: .fittingSizeLevel
        )
        channel.invokeMethod("height", arguments: ["height": Double(size.height)])
    }

    private static func date(_ millis: NSNumber) -> Date {
        return Date(timeIntervalSince1970: millis.doubleValue / 1000)
    }

    private static func mode(_ name: String?) -> UIDatePicker.Mode {
        switch name {
        case "time": return .time
        case "dateAndTime": return .dateAndTime
        case "yearAndMonth":
            if #available(iOS 17.4, *) { return .yearAndMonth }
            return .date
        default: return .date
        }
    }
}

/// Tells its owner the width it is laid out at.
private class LayoutReportingView: UIView {
    var onLayout: ((CGFloat) -> Void)?

    override func layoutSubviews() {
        super.layoutSubviews()
        onLayout?(bounds.width)
    }
}
