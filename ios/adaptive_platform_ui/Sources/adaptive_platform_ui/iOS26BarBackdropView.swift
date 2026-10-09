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

/// The system's scroll edge effect under the fixed toolbar.
///
/// UIKit draws that effect for its own scroll views where they pass under a
/// bar. The page's content is Flutter's, so UIKit cannot see it scroll: a
/// stand-in scroll view tells it instead, scrolled while the page is, and the
/// bar's area is registered as the elements over its top edge
/// (`UIScrollEdgeElementContainerInteraction`). The effect itself, and its
/// blur of whatever is underneath, native views included, is UIKit's own.
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
        container.setScrolledUnder(visible, animated: animated)
    }
}

/// A stand-in scroll view, empty and clear, with the bar's area over its top
/// edge.
final class BarBackdropContainer: UIView {
    private let scrollView = UIScrollView()
    private let barArea = UIView()
    private let barShape = UIImageView()

    /// How far below the bar the effect may soften out.
    var fade: CGFloat = 16 {
        didSet {
            if fade != oldValue { setNeedsLayout() }
        }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isUserInteractionEnabled = false

        scrollView.backgroundColor = .clear
        scrollView.isUserInteractionEnabled = false
        scrollView.contentInsetAdjustmentBehavior = .never
        scrollView.showsVerticalScrollIndicator = false
        scrollView.showsHorizontalScrollIndicator = false
        addSubview(scrollView)

        // The effect takes its shape from the elements in the bar's area: a
        // clear image spanning it gives the band of a navigation bar.
        barArea.backgroundColor = .clear
        barArea.isUserInteractionEnabled = false
        barShape.image = UIGraphicsImageRenderer(size: CGSize(width: 1, height: 1)).image { _ in }
        barShape.contentMode = .scaleToFill
        barArea.addSubview(barShape)
        addSubview(barArea)

        if #available(iOS 26.0, *) {
            scrollView.topEdgeEffect.style = .soft
            let interaction = UIScrollEdgeElementContainerInteraction()
            interaction.scrollView = scrollView
            interaction.edge = .top
            barArea.addInteraction(interaction)
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        scrollView.frame = bounds
        scrollView.contentSize = CGSize(width: bounds.width, height: max(bounds.height, 1) * 20)
        barArea.frame = CGRect(x: 0, y: 0, width: bounds.width, height: max(0, bounds.height - fade))
        barShape.frame = barArea.bounds
    }

    /// Content under the edge is what brings the effect in, as it does for a
    /// UIKit scroll view.
    func setScrolledUnder(_ scrolledUnder: Bool, animated: Bool) {
        let offset = CGPoint(x: 0, y: scrolledUnder ? 120 : 0)
        scrollView.setContentOffset(offset, animated: animated)
    }
}
