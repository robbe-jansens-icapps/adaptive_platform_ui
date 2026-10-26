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

    /// The width and text size the height was last measured for.
    private var measuredWidth: CGFloat = 0
    private var measuredTextSize: UIContentSizeCategory?

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
        // The app's language with the device's region and clock, as the rest
        // of the app has them: on its own, a language such as English gave a
        // 12-hour clock on a device set to 24 hours.
        if let locale = params["locale"] as? String {
            if #available(iOS 16, *) {
                var components = Locale.Components(locale: Locale(identifier: locale))
                if components.region == nil {
                    components.region = Locale.current.region
                }
                components.hourCycle = Locale.current.hourCycle
                picker.locale = Locale(components: components)
            } else {
                picker.locale = Locale(identifier: locale)
            }
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
            picker.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
        container.onLayout = { [weak self] width in self?.reportHeight(for: width) }
        channel.setMethodCallHandler { [weak self] call, result in
            guard let self, call.method == "showDays" else {
                result(FlutterMethodNotImplemented)
                return
            }
            result(self.showDays())
        }
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

    /// While the calendar shows its month and year wheels, goes back to its
    /// days, as a tap on its header does, and says so. The calendar has no
    /// API for this: the wheels are a date picker of their own inside it, and
    /// the header's title is the control that holds a label. Should either
    /// not be found, nothing happens and the answer is false.
    private func showDays() -> Bool {
        guard !showDaysFails,
              picker.preferredDatePickerStyle == .inline,
              monthYearWheels(in: picker) != nil,
              let title = headerTitle(in: picker)
        else { return false }
        title.sendActions(
            for: title.allControlEvents.contains(.primaryActionTriggered)
                ? .primaryActionTriggered
                : .touchUpInside
        )
        // Should the wheels stay, confirming takes over from then on, rather
        // than a checkmark that does nothing.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
            guard let self else { return }
            if self.monthYearWheels(in: self.picker) != nil {
                self.showDaysFails = true
            }
        }
        return true
    }

    private var showDaysFails = false

    /// The month and year wheels inside [view], if they are on screen.
    private func monthYearWheels(in view: UIView) -> UIDatePicker? {
        for subview in view.subviews {
            if let wheels = subview as? UIDatePicker, wheels !== picker {
                if isShown(wheels) { return wheels }
                continue
            }
            if let wheels = monthYearWheels(in: subview) { return wheels }
        }
        return nil
    }

    /// Whether [view] shows: neither it nor any view up to the picker is
    /// hidden or faded out.
    private func isShown(_ view: UIView) -> Bool {
        var current: UIView? = view
        while let candidate = current, candidate !== picker {
            if candidate.isHidden || candidate.alpha < 0.01 { return false }
            current = candidate.superview
        }
        return view.bounds.height > 0
    }

    /// The header's title (month and year), the control that toggles the
    /// wheels: the one control of the calendar that holds a label.
    private func headerTitle(in view: UIView) -> UIControl? {
        for subview in view.subviews {
            if subview is UIDatePicker { continue }
            if let control = subview as? UIControl, holdsLabel(control) {
                return control
            }
            if let title = headerTitle(in: subview) { return title }
        }
        return nil
    }

    private func holdsLabel(_ view: UIView) -> Bool {
        view.subviews.contains { $0 is UILabel || holdsLabel($0) }
    }

    /// Measures the height the picker needs at [width] and the text size, once
    /// for each, and hands it to Flutter, which sizes the view to it. The
    /// picker fills the view on all sides: left to find its own height, at
    /// some widths and text sizes the calendar never settled on one and laid
    /// itself out again and again, which hung the app (the iPhone Duo cover
    /// display, the largest text sizes).
    private func reportHeight(for width: CGFloat) {
        let textSize = container.traitCollection.preferredContentSizeCategory
        guard width > 0, width != measuredWidth || textSize != measuredTextSize
        else { return }
        measuredWidth = width
        measuredTextSize = textSize
        let size = picker.systemLayoutSizeFitting(
            CGSize(width: width, height: UIView.layoutFittingCompressedSize.height),
            withHorizontalFittingPriority: .required,
            verticalFittingPriority: .fittingSizeLevel
        )
        channel.invokeMethod("height", arguments: ["height": Double(ceil(size.height))])
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

/// Tells its owner the width it is laid out at, also again when the text size
/// changes.
private class LayoutReportingView: UIView {
    var onLayout: ((CGFloat) -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        if #available(iOS 17.0, *) {
            registerForTraitChanges([UITraitPreferredContentSizeCategory.self]) {
                (view: LayoutReportingView, _: UITraitCollection) in
                view.setNeedsLayout()
            }
        }
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        onLayout?(bounds.width)
    }
}
