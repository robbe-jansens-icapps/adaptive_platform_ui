import Flutter
import UIKit

private final class LayoutAwareTabBarContainerView: UIView {
    var onWidthChanged: ((CGFloat) -> Void)?
    var onLayout: (() -> Void)?
    private var lastReportedWidth: CGFloat = 0

    override func layoutSubviews() {
        super.layoutSubviews()

        guard window != nil else { return }
        onLayout?()

        let width = bounds.width
        guard width > 0 else { return }
        guard abs(width - lastReportedWidth) > 0.5 else { return }

        lastReportedWidth = width
        onWidthChanged?(width)
    }
}

class iOS26TabBarPlatformView: NSObject, FlutterPlatformView, UITabBarDelegate {
    private let channel: FlutterMethodChannel
    private let container: LayoutAwareTabBarContainerView
    private var tabBar: UITabBar?
    private var minimizeBehavior: Int = 3 // automatic
    private var currentLabels: [String] = []
    private var currentSymbols: [String] = []
    private var currentSelectedSymbols: [String] = []
    private var currentAssetIcons: [String] = []
    private var currentSelectedAssetIcons: [String] = []
    private var currentFileIcons: [String] = []
    private var currentSelectedFileIcons: [String] = []
    private var currentNetworkIcons: [String] = []
    private var currentSelectedNetworkIcons: [String] = []
    private var currentSearchFlags: [Bool] = []
    private var currentBadgeCounts: [Int?] = []
    private var currentBadgeTexts: [String?] = []
    private var currentBadgeColors: [Int?] = []
    private var currentBadgeTextColors: [Int?] = []
    private let imageCache = NSCache<NSString, UIImage>()
    private var fontObserver: NSObjectProtocol?

    /// Applies a badge to a tab bar item from the Flutter-provided styling.
    /// Precedence: a non-empty [text] wins over [count]; otherwise a positive
    /// [count] is shown; otherwise no badge. [colorARGB] sets the badge
    /// background (nil = system default red), [textColorARGB] the glyph color
    /// (nil = platform default). A transparent background + a colored glyph
    /// renders a clean dot (e.g. badgeText "●").
    private static func applyBadge(to item: UITabBarItem, count: Int?, text: String?, colorARGB: Int?, textColorARGB: Int?) {
        let value: String?
        if let text = text, !text.isEmpty {
            value = text
        } else {
            // A count, or a dot without one (Blue Bike fork).
            value = tabBadgeText(count)
        }
        item.badgeValue = value
        item.badgeColor = colorARGB != nil ? colorFromARGB(colorARGB!) : nil
        if let argb = textColorARGB {
            let attrs: [NSAttributedString.Key: Any] = [.foregroundColor: colorFromARGB(argb)]
            item.setBadgeTextAttributes(attrs, for: .normal)
            item.setBadgeTextAttributes(attrs, for: .selected)
        } else {
            item.setBadgeTextAttributes(nil, for: .normal)
            item.setBadgeTextAttributes(nil, for: .selected)
        }
    }

    private static func badgeAt<T>(_ arr: [T?], _ i: Int) -> T? {
        return i < arr.count ? arr[i] : nil
    }

    init(frame: CGRect, viewId: Int64, args: Any?, messenger: FlutterBinaryMessenger) {
        self.channel = FlutterMethodChannel(
            name: "adaptive_platform_ui/ios26_tab_bar_\(viewId)",
            binaryMessenger: messenger
        )
        self.container = LayoutAwareTabBarContainerView(frame: frame)

        var labels: [String] = []
        var symbols: [String] = []
        var selectedSymbols: [String] = []
        var assetIcons: [String] = []
        var selectedAssetIcons: [String] = []
        var fileIcons: [String] = []
        var selectedFileIcons: [String] = []
        var networkIcons: [String] = []
        var selectedNetworkIcons: [String] = []
        var searchFlags: [Bool] = []
        var badgeCounts: [Int?] = []
        var badgeTexts: [String?] = []
        var badgeColors: [Int?] = []
        var badgeTextColors: [Int?] = []
        var spacerFlags: [Bool] = []
        var selectedIndex: Int = 0
        var isDark: Bool = false
        var isRtl: Bool = false
        var tint: UIColor? = nil
        var bg: UIColor? = nil
        var minimize: Int = 3 // automatic
        var hidden = false

        var unselectedTint: UIColor? = nil

        if let dict = args as? [String: Any] {
            labels = (dict["labels"] as? [String]) ?? []
            symbols = (dict["sfSymbols"] as? [String]) ?? []
            selectedSymbols = (dict["selectedSfSymbols"] as? [String]) ?? []
            assetIcons = (dict["assetIcons"] as? [String]) ?? []
            selectedAssetIcons = (dict["selectedAssetIcons"] as? [String]) ?? []
            fileIcons = (dict["fileIcons"] as? [String]) ?? []
            selectedFileIcons = (dict["selectedFileIcons"] as? [String]) ?? []
            networkIcons = (dict["networkIcons"] as? [String]) ?? []
            selectedNetworkIcons = (dict["selectedNetworkIcons"] as? [String]) ?? []
            searchFlags = (dict["searchFlags"] as? [Bool]) ?? []
            spacerFlags = (dict["spacerFlags"] as? [Bool]) ?? []
            if let badgeData = dict["badgeCounts"] as? [NSNumber?] {
                badgeCounts = badgeData.map { $0?.intValue }
            }
            if let arr = dict["badgeTexts"] as? [Any?] {
                badgeTexts = arr.map { $0 as? String }
            }
            if let arr = dict["badgeColors"] as? [NSNumber?] {
                badgeColors = arr.map { $0?.intValue }
            }
            if let arr = dict["badgeTextColors"] as? [NSNumber?] {
                badgeTextColors = arr.map { $0?.intValue }
            }
            if let v = dict["selectedIndex"] as? NSNumber { selectedIndex = v.intValue }
            if let v = dict["isDark"] as? NSNumber { isDark = v.boolValue }
            if let v = dict["isRtl"] as? NSNumber { isRtl = v.boolValue }
            if let n = dict["tint"] as? NSNumber { tint = Self.colorFromARGB(n.intValue) }
            if let n = dict["unselectedItemTint"] as? NSNumber {
                unselectedTint = Self.colorFromARGB(n.intValue)
            }
            if let n = dict["backgroundColor"] as? NSNumber { bg = Self.colorFromARGB(n.intValue) }
            if let m = dict["minimizeBehavior"] as? NSNumber { minimize = m.intValue }
            if let v = dict["hidden"] as? NSNumber { hidden = v.boolValue }
        }

        super.init()

        container.isHidden = hidden

        container.backgroundColor = .clear
        if #available(iOS 13.0, *) {
            container.overrideUserInterfaceStyle = isDark ? .dark : .light
        }


        // Create single tab bar
        let bar = UITabBar(frame: .zero)
        tabBar = bar
        // The app font may only be registered after the bar is on screen.
        fontObserver = NotificationCenter.default.addObserver(
            forName: AdaptiveFontRegistry.didRegister,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let bar = self?.tabBar else { return }
            applyAppFont(to: bar)
        }
        bar.delegate = self
        // Its labels keep one size whatever the text size, as the system's do.
        // At the accessibility text sizes, a finger held on a tab shows it
        // large in the middle of the screen instead, as in the system's apps
        // (see TabLargeContentHUD).
        let press = UILongPressGestureRecognizer(target: self, action: #selector(onTabHeld(_:)))
        press.minimumPressDuration = 0.4
        press.cancelsTouchesInView = false
        press.delegate = self
        bar.addGestureRecognizer(press)
        bar.translatesAutoresizingMaskIntoConstraints = false
        let semanticAttribute: UISemanticContentAttribute = isRtl
            ? .forceRightToLeft
            : .forceLeftToRight
        bar.semanticContentAttribute = semanticAttribute
        // The iOS 26 selected Liquid Glass content is portal-backed and reads the trait direction.
        // Override both APIs so the app locale wins when it differs from the device locale.
        if #available(iOS 17.0, *) {
            bar.traitOverrides.layoutDirection = isRtl ? .rightToLeft : .leftToRight
        }
        container.semanticContentAttribute = semanticAttribute

        // iOS 26+ special handling - Skip appearance, use direct properties only
        if #available(iOS 26.0, *) {
            // For iOS 26, we skip UITabBarAppearance as it interferes with custom colors
            bar.isTranslucent = true
            bar.backgroundImage = UIImage()
            bar.shadowImage = UIImage()
            bar.backgroundColor = .clear
        }
        // iOS 13-25 - Use appearance
        else if #available(iOS 13.0, *) {
            let appearance = UITabBarAppearance()

            // Make transparent
            appearance.configureWithTransparentBackground()
            appearance.backgroundColor = .clear
            appearance.shadowColor = .clear

            // Set colors directly on the appearance layouts
            let unselColor = unselectedTint ?? UIColor.systemGray
            let selColor = tint ?? UIColor.systemBlue

            // Normal (unselected) items
            appearance.stackedLayoutAppearance.normal.iconColor = unselColor
            appearance.stackedLayoutAppearance.normal.titleTextAttributes = [.foregroundColor: unselColor]
            appearance.inlineLayoutAppearance.normal.iconColor = unselColor
            appearance.inlineLayoutAppearance.normal.titleTextAttributes = [.foregroundColor: unselColor]
            appearance.compactInlineLayoutAppearance.normal.iconColor = unselColor
            appearance.compactInlineLayoutAppearance.normal.titleTextAttributes = [.foregroundColor: unselColor]

            // Selected items
            appearance.stackedLayoutAppearance.selected.iconColor = selColor
            appearance.stackedLayoutAppearance.selected.titleTextAttributes = [.foregroundColor: selColor]
            appearance.inlineLayoutAppearance.selected.iconColor = selColor
            appearance.inlineLayoutAppearance.selected.titleTextAttributes = [.foregroundColor: selColor]
            appearance.compactInlineLayoutAppearance.selected.iconColor = selColor
            appearance.compactInlineLayoutAppearance.selected.titleTextAttributes = [.foregroundColor: selColor]

            bar.standardAppearance = appearance
            if #available(iOS 15.0, *) {
                bar.scrollEdgeAppearance = appearance
            }
        } else {
            // iOS 10-12 fallback
            bar.isTranslucent = true
            bar.backgroundImage = UIImage()
            bar.shadowImage = UIImage()
            bar.backgroundColor = .clear
        }

        // Also set direct properties as fallback
        if #available(iOS 10.0, *) {
            if let unselTint = unselectedTint {
                bar.unselectedItemTintColor = unselTint
            }
            if let tint = tint {
                bar.tintColor = tint
            }
        }

        if let bg = bg { bar.barTintColor = bg }

        // Build tab bar items
        func buildItems(_ range: Range<Int>) -> [UITabBarItem] {
            var items: [UITabBarItem] = []
            for i in range {
                let title = (i < labels.count) ? labels[i] : nil
                let isSearch = (i < searchFlags.count) && searchFlags[i]
                let badgeCount = (i < badgeCounts.count) ? badgeCounts[i] : nil

                let item: UITabBarItem

                // Use UITabBarSystemItem.search for search tabs (iOS 26+ Liquid Glass)
                if isSearch {
                    if #available(iOS 26.0, *) {
                        item = UITabBarItem(tabBarSystemItem: .search, tag: i)
                        if let title = title {
                            item.title = title
                        }

                    } else {
                        // Fallback for older iOS versions
                        let searchImage = UIImage(systemName: "magnifyingglass")
                        item = UITabBarItem(title: title, image: searchImage, selectedImage: searchImage)
                    }
                } else {
                    var image: UIImage? = nil
                    var selectedImage: UIImage? = nil

                    item = UITabBarItem(title: title ?? "Tab \(i+1)", image: nil, selectedImage: nil)
                    item.tag = i

                    if !self.configureRuntimeImages(for: item, index: i) {
                        if i < assetIcons.count && !assetIcons[i].isEmpty {
                            let assetName = assetIcons[i]
                            let key = FlutterDartProject.lookupKey(forAsset: assetName)
                            let rawImageOriginal = UIImage(named: key)
                            let rawImage = rawImageOriginal != nil ? self.resizeImage(image: rawImageOriginal!) : nil

                            var selRawImage = rawImage
                            if i < selectedAssetIcons.count && !selectedAssetIcons[i].isEmpty {
                                let selKey = FlutterDartProject.lookupKey(forAsset: selectedAssetIcons[i])
                                let selRawOriginal = UIImage(named: selKey)
                                if selRawOriginal != nil {
                                    selRawImage = self.resizeImage(image: selRawOriginal!)
                                }
                            }

                            if #available(iOS 26.0, *) {
                                if let unselTint = unselectedTint {
                                    image = rawImage?.withTintColor(unselTint, renderingMode: .alwaysOriginal)
                                } else {
                                    image = rawImage?.withRenderingMode(.alwaysTemplate)
                                }
                                selectedImage = selRawImage?.withRenderingMode(.alwaysTemplate)
                            } else {
                                image = rawImage
                                selectedImage = selRawImage
                            }
                        } else if i < symbols.count && !symbols[i].isEmpty {
                            // Selected state may use a distinct SF Symbol (e.g. filled variant).
                            let selSymbol = (i < selectedSymbols.count && !selectedSymbols[i].isEmpty)
                                ? selectedSymbols[i]
                                : symbols[i]
                            // iOS 26+: Use different rendering modes for selected/unselected
                            if #available(iOS 26.0, *) {
                                // Unselected: Only apply custom color if unselectedTint is provided
                                if let unselTint = unselectedTint {
                                    // Create colored image for unselected state
                                    if let originalImage = UIImage(systemName: symbols[i]) ?? UIImage(named: symbols[i]) {
                                        image = originalImage.withTintColor(unselTint, renderingMode: .alwaysOriginal)
                                    }
                                } else {
                                    // No custom color - use template mode to respect theme
                                    image = (UIImage(systemName: symbols[i]) ?? UIImage(named: symbols[i]))?.withRenderingMode(.alwaysTemplate)
                                }

                                // Selected: Use template rendering so tintColor applies
                                selectedImage = (UIImage(systemName: selSymbol) ?? UIImage(named: selSymbol))?.withRenderingMode(.alwaysTemplate)
                            } else {
                                // iOS <26: Use default behavior
                                image = UIImage(systemName: symbols[i]) ?? UIImage(named: symbols[i])
                                selectedImage = UIImage(systemName: selSymbol) ?? UIImage(named: selSymbol)
                            }
                        }

                        item.image = image
                        item.selectedImage = selectedImage
                    }
                }

                // Set badge (count / text / colors)
                Self.applyBadge(
                    to: item,
                    count: badgeCount,
                    text: Self.badgeAt(badgeTexts, i),
                    colorARGB: Self.badgeAt(badgeColors, i),
                    textColorARGB: Self.badgeAt(badgeTextColors, i)
                )

                items.append(item)
            }
            return items
        }

        let count = max(
            max(labels.count, symbols.count),
            max(max(assetIcons.count, fileIcons.count), networkIcons.count)
        )
        // Given the app font before they go into the bar, so they are measured
        // in it from the start.
        let items = buildItems(0..<count)
        applyAppFont(to: items)
        bar.items = items

        // Note: spacerFlags are received but not yet implemented for UITabBar
        // UITabBar doesn't natively support flexible spacing between items like UIToolbar does
        // This would require custom UITabBar subclass or different approach
        // TODO: Implement grouped tab bar layout if needed

        if selectedIndex >= 0, let items = bar.items, selectedIndex < items.count {
            bar.selectedItem = items[selectedIndex]
        }

        container.addSubview(bar)
        NSLayoutConstraint.activate([
            bar.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            bar.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            bar.topAnchor.constraint(equalTo: container.topAnchor),
            bar.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])

        self.minimizeBehavior = minimize
        self.currentLabels = labels
        self.currentSymbols = symbols
        self.currentSelectedSymbols = selectedSymbols
        self.currentAssetIcons = assetIcons
        self.currentSelectedAssetIcons = selectedAssetIcons
        self.currentFileIcons = fileIcons
        self.currentSelectedFileIcons = selectedFileIcons
        self.currentNetworkIcons = networkIcons
        self.currentSelectedNetworkIcons = selectedNetworkIcons
        self.currentSearchFlags = searchFlags
        self.currentBadgeCounts = badgeCounts
        self.currentBadgeTexts = badgeTexts
        self.currentBadgeColors = badgeColors
        self.currentBadgeTextColors = badgeTextColors
        // Apply minimize behavior if available
        self.applyMinimizeBehavior()

        container.onWidthChanged = { [weak self] _ in
            self?.handleContainerWidthChange()
        }
        container.onLayout = { [weak self] in
            self?.reportCapsuleIfChanged()
        }

        // Setup method call handler
        channel.setMethodCallHandler { [weak self] call, result in
            guard let self = self else { result(nil); return }
            self.handleMethodCall(call, result: result)
        }
    }

    /// The capsule the bar floats its tabs on, as last told to Flutter.
    private var lastCapsule: CGRect?

    /// The capsule the bar floats its tabs on (iOS 26), in the view's
    /// coordinates: for Flutter to dim it as a dialog's barrier dims the page,
    /// the bar being above the page, out of the barrier's reach. UIKit has no
    /// API for it: it is the platter view among the bar's own. Nil where the
    /// bar has none.
    private func capsuleFrame() -> CGRect? {
        guard let bar = tabBar, bar.bounds.width > 0 else { return nil }
        bar.layoutIfNeeded()
        let platters = bar.subviews.filter { view in
            !view.isHidden && view.alpha > 0.01 && !view.bounds.isEmpty &&
                String(describing: type(of: view)).contains("Platter")
        }
        guard let platter = platters.max(by: {
            $0.bounds.width * $0.bounds.height < $1.bounds.width * $1.bounds.height
        }) else { return nil }
        return platter.convert(platter.bounds, to: container)
    }

    private static func encode(_ frame: CGRect?) -> [String: Double]? {
        guard let frame = frame else { return nil }
        return [
            "x": Double(frame.minX),
            "y": Double(frame.minY),
            "width": Double(frame.width),
            "height": Double(frame.height),
        ]
    }

    /// Tells Flutter where the capsule is whenever a layout moves it.
    private func reportCapsuleIfChanged() {
        let frame = capsuleFrame()
        guard frame != lastCapsule else { return }
        lastCapsule = frame
        channel.invokeMethod("capsuleChanged", arguments: Self.encode(frame))
    }

    private func applyMinimizeBehavior() {
        // Note: UITabBarController.tabBarMinimizeBehavior is the official iOS 26+ API
        // However, since we're using a standalone UITabBar in a platform view,
        // we need to implement custom minimize behavior
        //
        // The minimize behavior should be controlled at the Flutter level
        // by adjusting the tab bar's height/visibility based on scroll events
        //
        // This method stores the behavior preference for future use
        // The actual minimization animation should be handled by Flutter
    }

    private func handleContainerWidthChange() {
        guard let bar = self.tabBar else { return }

        // A standalone UITabBar hosted in a platform view can lay out once
        // before it has its final width. Install the items again against the
        // real container width so item labels and spacing are computed from
        // the final bounds. The same items: building them again (images and
        // all) costs more and lays out no differently.
        if #available(iOS 26.0, *) {
            reinstallItems(of: bar)
        }

        bar.setNeedsLayout()
        bar.layoutIfNeeded()
        container.setNeedsLayout()
    }

    private func handleMethodCall(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "getIntrinsicSize":
            if let bar = self.tabBar {
                let size = bar.sizeThatFits(CGSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude))
                result(["width": Double(size.width), "height": Double(size.height)])
            } else {
                result(["width": Double(self.container.bounds.width), "height": 50.0])
            }

        case "setItems":
            guard let args = call.arguments as? [String: Any],
                  let labels = args["labels"] as? [String],
                  let symbols = args["sfSymbols"] as? [String] else {
                result(FlutterError(code: "bad_args", message: "Missing items", details: nil))
                return
            }

            let selectedSymbols = (args["selectedSfSymbols"] as? [String]) ?? []
            let assetIcons = (args["assetIcons"] as? [String]) ?? []
            let selectedAssetIcons = (args["selectedAssetIcons"] as? [String]) ?? []
            let fileIcons = (args["fileIcons"] as? [String]) ?? []
            let selectedFileIcons = (args["selectedFileIcons"] as? [String]) ?? []
            let networkIcons = (args["networkIcons"] as? [String]) ?? []
            let selectedNetworkIcons = (args["selectedNetworkIcons"] as? [String]) ?? []
            let searchFlags = (args["searchFlags"] as? [Bool]) ?? []
            let selectedIndex = (args["selectedIndex"] as? NSNumber)?.intValue ?? 0
            var badgeCounts: [Int?] = []
            if let badgeData = args["badgeCounts"] as? [NSNumber?] {
                badgeCounts = badgeData.map { $0?.intValue }
            }
            let badgeTexts: [String?] = (args["badgeTexts"] as? [Any?])?.map { $0 as? String } ?? []
            let badgeColors: [Int?] = (args["badgeColors"] as? [NSNumber?])?.map { $0?.intValue } ?? []
            let badgeTextColors: [Int?] = (args["badgeTextColors"] as? [NSNumber?])?.map { $0?.intValue } ?? []

            // The same items again: only the selection can have changed.
            if let bar = self.tabBar, let items = bar.items,
               labels == currentLabels, symbols == currentSymbols,
               selectedSymbols == currentSelectedSymbols,
               assetIcons == currentAssetIcons, selectedAssetIcons == currentSelectedAssetIcons,
               fileIcons == currentFileIcons, selectedFileIcons == currentSelectedFileIcons,
               networkIcons == currentNetworkIcons, selectedNetworkIcons == currentSelectedNetworkIcons,
               searchFlags == currentSearchFlags, badgeCounts == currentBadgeCounts,
               badgeTexts == currentBadgeTexts, badgeColors == currentBadgeColors,
               badgeTextColors == currentBadgeTextColors {
                if selectedIndex >= 0, selectedIndex < items.count {
                    bar.selectedItem = items[selectedIndex]
                }
                result(nil)
                return
            }

            self.currentLabels = labels
            self.currentSymbols = symbols
            self.currentSelectedSymbols = selectedSymbols
            self.currentAssetIcons = assetIcons
            self.currentSelectedAssetIcons = selectedAssetIcons
            self.currentFileIcons = fileIcons
            self.currentSelectedFileIcons = selectedFileIcons
            self.currentNetworkIcons = networkIcons
            self.currentSelectedNetworkIcons = selectedNetworkIcons
            self.currentSearchFlags = searchFlags
            self.currentBadgeCounts = badgeCounts
            self.currentBadgeTexts = badgeTexts
            self.currentBadgeColors = badgeColors
            self.currentBadgeTextColors = badgeTextColors

            let count = max(
                max(labels.count, symbols.count),
                max(max(assetIcons.count, fileIcons.count), networkIcons.count)
            )

            let buildItems: (Range<Int>) -> [UITabBarItem] = { range in
                var items: [UITabBarItem] = []
                for i in range {
                    let title = (i < labels.count) ? labels[i] : nil
                    let isSearch = (i < searchFlags.count) && searchFlags[i]
                    let badgeCount = (i < badgeCounts.count) ? badgeCounts[i] : nil

                    let item: UITabBarItem

                    // Use UITabBarSystemItem.search for search tabs (iOS 26+ Liquid Glass)
                    if isSearch {
                        if #available(iOS 26.0, *) {
                            item = UITabBarItem(tabBarSystemItem: .search, tag: i)
                            if let title = title {
                                item.title = title
                            }

                        } else {
                            // Fallback for older iOS versions
                            let searchImage = UIImage(systemName: "magnifyingglass")
                            item = UITabBarItem(title: title, image: searchImage, selectedImage: searchImage)
                        }
                    } else {
                        var image: UIImage? = nil
                        var selectedImage: UIImage? = nil

                        item = UITabBarItem(title: title ?? "Tab \(i+1)", image: nil, selectedImage: nil)
                        item.tag = i

                        if !self.configureRuntimeImages(for: item, index: i) {
                            if i < assetIcons.count && !assetIcons[i].isEmpty {
                                let assetName = assetIcons[i]
                                let key = FlutterDartProject.lookupKey(forAsset: assetName)
                                let rawImageOriginal = UIImage(named: key)
                                let rawImage = rawImageOriginal != nil ? self.resizeImage(image: rawImageOriginal!) : nil

                                var selRawImage = rawImage
                                if i < selectedAssetIcons.count && !selectedAssetIcons[i].isEmpty {
                                    let selKey = FlutterDartProject.lookupKey(forAsset: selectedAssetIcons[i])
                                    let selRawOriginal = UIImage(named: selKey)
                                    if selRawOriginal != nil {
                                        selRawImage = self.resizeImage(image: selRawOriginal!)
                                    }
                                }

                                if #available(iOS 26.0, *) {
                                    let unselTint = self.tabBar?.unselectedItemTintColor
                                    if let unselTint = unselTint {
                                        image = rawImage?.withTintColor(unselTint, renderingMode: .alwaysOriginal)
                                    } else {
                                        image = rawImage?.withRenderingMode(.alwaysTemplate)
                                    }
                                    selectedImage = selRawImage?.withRenderingMode(.alwaysTemplate)
                                } else {
                                    image = rawImage
                                    selectedImage = selRawImage
                                }
                            } else if i < symbols.count && !symbols[i].isEmpty {
                                // Selected state may use a distinct SF Symbol (e.g. filled variant).
                                let selSymbol = (i < selectedSymbols.count && !selectedSymbols[i].isEmpty)
                                    ? selectedSymbols[i]
                                    : symbols[i]
                                // iOS 26+: Use different rendering modes for selected/unselected
                                if #available(iOS 26.0, *) {
                                    // Get current unselected color from tab bar
                                    let unselTint = self.tabBar?.unselectedItemTintColor

                                    // Unselected: Only apply custom color if unselectedTint is set
                                    if let unselTint = unselTint {
                                        if let originalImage = UIImage(systemName: symbols[i]) ?? UIImage(named: symbols[i]) {
                                            image = originalImage.withTintColor(unselTint, renderingMode: .alwaysOriginal)
                                        }
                                    } else {
                                        // No custom color - use template mode to respect theme
                                        image = (UIImage(systemName: symbols[i]) ?? UIImage(named: symbols[i]))?.withRenderingMode(.alwaysTemplate)
                                    }

                                    // Selected: Use template rendering so tintColor applies
                                    selectedImage = (UIImage(systemName: selSymbol) ?? UIImage(named: selSymbol))?.withRenderingMode(.alwaysTemplate)
                                } else {
                                    // iOS <26: Use default behavior
                                    image = UIImage(systemName: symbols[i]) ?? UIImage(named: symbols[i])
                                    selectedImage = UIImage(systemName: selSymbol) ?? UIImage(named: selSymbol)
                                }
                            }

                            item.image = image
                            item.selectedImage = selectedImage
                        }
                    }

                    // Set badge (count / text / colors)
                    Self.applyBadge(
                        to: item,
                        count: badgeCount,
                        text: Self.badgeAt(badgeTexts, i),
                        colorARGB: Self.badgeAt(badgeColors, i),
                        textColorARGB: Self.badgeAt(badgeTextColors, i)
                    )

                    items.append(item)
                }
                return items
            }

            if let bar = self.tabBar {
                let items = buildItems(0..<count)
                applyAppFont(to: items)
                bar.items = items
                if selectedIndex >= 0, selectedIndex < items.count {
                    bar.selectedItem = items[selectedIndex]
                }
            }
            result(nil)

        case "setSelectedIndex":
            guard let args = call.arguments as? [String: Any],
                  let idx = (args["index"] as? NSNumber)?.intValue else {
                result(FlutterError(code: "bad_args", message: "Invalid index", details: nil))
                return
            }

            if let bar = self.tabBar, let items = bar.items, idx >= 0, idx < items.count {
                bar.selectedItem = items[idx]
            }
            result(nil)

        case "setStyle":
            guard let args = call.arguments as? [String: Any] else {
                result(FlutterError(code: "bad_args", message: "Missing style", details: nil))
                return
            }

            var tintColor: UIColor? = nil
            var unselectedColor: UIColor? = nil

            if let n = args["tint"] as? NSNumber {
                let c = Self.colorFromARGB(n.intValue)
                self.tabBar?.tintColor = c
                tintColor = c
            }
            if let n = args["unselectedItemTint"] as? NSNumber {
                let c = Self.colorFromARGB(n.intValue)
                if #available(iOS 10.0, *), self.tabBar?.unselectedItemTintColor != c {
                    self.tabBar?.unselectedItemTintColor = c

                    // iOS 26+: Rebuild items with current state so untinted
                    // and tinted icon variants are regenerated consistently.
                    if #available(iOS 26.0, *) {
                        self.rebuildItemsWithCurrentState()
                    }
                }
                unselectedColor = c
            }
            if let n = args["backgroundColor"] as? NSNumber {
                let c = Self.colorFromARGB(n.intValue)
                self.tabBar?.barTintColor = c
            }

            result(nil)

        case "setBrightness":
            guard let args = call.arguments as? [String: Any],
                  let isDark = (args["isDark"] as? NSNumber)?.boolValue else {
                result(FlutterError(code: "bad_args", message: "Missing isDark", details: nil))
                return
            }

            if #available(iOS 13.0, *) {
                self.container.overrideUserInterfaceStyle = isDark ? .dark : .light
            }
            result(nil)

        case "setDirectionality":
            guard let args = call.arguments as? [String: Any],
                  let isRtl = (args["isRtl"] as? NSNumber)?.boolValue else {
                result(FlutterError(code: "bad_args", message: "Missing isRtl", details: nil))
                return
            }

            let attribute: UISemanticContentAttribute = isRtl
                ? .forceRightToLeft
                : .forceLeftToRight
            self.tabBar?.semanticContentAttribute = attribute
            if #available(iOS 17.0, *) {
                self.tabBar?.traitOverrides.layoutDirection = isRtl
                    ? .rightToLeft
                    : .leftToRight
            }
            self.container.semanticContentAttribute = attribute
            result(nil)

        case "setMinimizeBehavior":
            guard let args = call.arguments as? [String: Any],
                  let behavior = (args["behavior"] as? NSNumber)?.intValue else {
                result(FlutterError(code: "bad_args", message: "Missing behavior", details: nil))
                return
            }

            self.minimizeBehavior = behavior
            self.applyMinimizeBehavior()
            result(nil)

        case "setHidden":
            guard let args = call.arguments as? [String: Any],
                  let hidden = (args["hidden"] as? NSNumber)?.boolValue else {
                result(FlutterError(code: "bad_args", message: "Missing hidden", details: nil))
                return
            }

            self.container.isHidden = hidden
            result(nil)

        case "getCapsule":
            self.lastCapsule = self.capsuleFrame()
            result(Self.encode(self.lastCapsule))

        case "setBadgeCounts":
            guard let args = call.arguments as? [String: Any],
                  let badgeData = args["badgeCounts"] as? [NSNumber?] else {
                result(FlutterError(code: "bad_args", message: "Missing badge counts", details: nil))
                return
            }

            let badgeCounts = badgeData.map { $0?.intValue }
            self.currentBadgeCounts = badgeCounts
            self.currentBadgeTexts = (args["badgeTexts"] as? [Any?])?.map { $0 as? String } ?? []
            self.currentBadgeColors = (args["badgeColors"] as? [NSNumber?])?.map { $0?.intValue } ?? []
            self.currentBadgeTextColors = (args["badgeTextColors"] as? [NSNumber?])?.map { $0?.intValue } ?? []

            // Update existing tab bar items with new badge values
            if let bar = self.tabBar, let items = bar.items {
                for (index, item) in items.enumerated() {
                    Self.applyBadge(
                        to: item,
                        count: Self.badgeAt(badgeCounts, index),
                        text: Self.badgeAt(self.currentBadgeTexts, index),
                        colorARGB: Self.badgeAt(self.currentBadgeColors, index),
                        textColorARGB: Self.badgeAt(self.currentBadgeTextColors, index)
                    )
                }
            }
            result(nil)

        default:
            result(FlutterMethodNotImplemented)
        }
    }

    // iOS 26+: Rebuild tab items from the current native state.
    private func rebuildItemsWithCurrentState() {
        guard let bar = self.tabBar else { return }

        let currentSelectedIndex = bar.items?.firstIndex { $0 == bar.selectedItem } ?? 0

        // Rebuild items with new colors
        var items: [UITabBarItem] = []
        let itemCount = max(
            max(currentLabels.count, currentSymbols.count),
            max(max(currentAssetIcons.count, currentFileIcons.count), currentNetworkIcons.count)
        )
        for i in 0..<itemCount {
            let title = i < currentLabels.count ? currentLabels[i] : nil
            let isSearch = (i < currentSearchFlags.count) && currentSearchFlags[i]
            let badgeCount = (i < currentBadgeCounts.count) ? currentBadgeCounts[i] : nil
            let item: UITabBarItem

            if isSearch {
                if #available(iOS 26.0, *) {
                    item = UITabBarItem(tabBarSystemItem: .search, tag: i)
                    item.title = title
                } else {
                    let searchImage = UIImage(systemName: "magnifyingglass")
                    item = UITabBarItem(title: title, image: searchImage, selectedImage: searchImage)
                }
            } else {
                var image: UIImage? = nil
                var selectedImage: UIImage? = nil

                item = UITabBarItem(title: title, image: nil, selectedImage: nil)
                item.tag = i

                if !configureRuntimeImages(for: item, index: i) {
                    if i < currentAssetIcons.count && !currentAssetIcons[i].isEmpty {
                        if #available(iOS 26.0, *) {
                            let key = FlutterDartProject.lookupKey(forAsset: currentAssetIcons[i])
                            let rawImageOriginal = UIImage(named: key)
                            let rawImage = rawImageOriginal != nil ? self.resizeImage(image: rawImageOriginal!) : nil

                            var selRawImage = rawImage
                            if i < currentSelectedAssetIcons.count && !currentSelectedAssetIcons[i].isEmpty {
                                let selKey = FlutterDartProject.lookupKey(forAsset: currentSelectedAssetIcons[i])
                                let selRawOriginal = UIImage(named: selKey)
                                if selRawOriginal != nil {
                                    selRawImage = self.resizeImage(image: selRawOriginal!)
                                }
                            }

                            if let unselTint = bar.unselectedItemTintColor {
                                image = rawImage?.withTintColor(unselTint, renderingMode: .alwaysOriginal)
                            } else {
                                image = rawImage?.withRenderingMode(.alwaysTemplate)
                            }
                            selectedImage = selRawImage?.withRenderingMode(.alwaysTemplate)
                        } else {
                            let key = FlutterDartProject.lookupKey(forAsset: currentAssetIcons[i])
                            let rawImageOriginal = UIImage(named: key)
                            image = rawImageOriginal != nil ? self.resizeImage(image: rawImageOriginal!) : nil

                            if i < currentSelectedAssetIcons.count && !currentSelectedAssetIcons[i].isEmpty {
                                let selKey = FlutterDartProject.lookupKey(forAsset: currentSelectedAssetIcons[i])
                                let selRawOriginal = UIImage(named: selKey)
                                if selRawOriginal != nil {
                                    selectedImage = self.resizeImage(image: selRawOriginal!)
                                } else {
                                    selectedImage = image
                                }
                            } else {
                                selectedImage = image
                            }
                        }
                    } else if i < currentSymbols.count && !currentSymbols[i].isEmpty {
                        // Selected state may use a distinct SF Symbol (e.g. filled variant).
                        let selSymbol = (i < currentSelectedSymbols.count && !currentSelectedSymbols[i].isEmpty)
                            ? currentSelectedSymbols[i]
                            : currentSymbols[i]
                        if #available(iOS 26.0, *) {
                            let unselTint = bar.unselectedItemTintColor

                            if let unselTint = unselTint {
                                if let originalImage = UIImage(systemName: currentSymbols[i]) ?? UIImage(named: currentSymbols[i]) {
                                    image = originalImage.withTintColor(unselTint, renderingMode: .alwaysOriginal)
                                }
                            } else {
                                image = (UIImage(systemName: currentSymbols[i]) ?? UIImage(named: currentSymbols[i]))?.withRenderingMode(.alwaysTemplate)
                            }
                            selectedImage = (UIImage(systemName: selSymbol) ?? UIImage(named: selSymbol))?.withRenderingMode(.alwaysTemplate)
                        } else {
                            image = UIImage(systemName: currentSymbols[i]) ?? UIImage(named: currentSymbols[i])
                            selectedImage = UIImage(systemName: selSymbol) ?? UIImage(named: selSymbol)
                        }
                    }

                    item.image = image
                    item.selectedImage = selectedImage
                }
            }

            Self.applyBadge(
                to: item,
                count: badgeCount,
                text: Self.badgeAt(currentBadgeTexts, i),
                colorARGB: Self.badgeAt(currentBadgeColors, i),
                textColorARGB: Self.badgeAt(currentBadgeTextColors, i)
            )

            items.append(item)
        }

        applyAppFont(to: items)
        bar.items = items

        if currentSelectedIndex < items.count {
            bar.selectedItem = items[currentSelectedIndex]
        }
    }

    func view() -> UIView { container }

    deinit {
        if let fontObserver { NotificationCenter.default.removeObserver(fontObserver) }
    }

    /// The tab under [point]: the one whose button, found by its title,
    /// holds the point, or else the one nearest to it.
    private func item(at point: CGPoint) -> UITabBarItem? {
        guard let bar = tabBar, let items = bar.items, !items.isEmpty else { return nil }
        var buttons: [(UITabBarItem, CGRect)] = []
        func collect(_ view: UIView) {
            for subview in view.subviews {
                if let label = subview.accessibilityLabel,
                   let item = items.first(where: { $0.title == label }),
                   !buttons.contains(where: { $0.0 === item }) {
                    buttons.append((item, subview.convert(subview.bounds, to: bar)))
                    continue
                }
                collect(subview)
            }
        }
        collect(bar)
        if let hit = buttons.first(where: { $0.1.contains(point) }) { return hit.0 }
        return buttons.min(by: { abs($0.1.midX - point.x) < abs($1.1.midX - point.x) })?.0
    }

    private var largeContentHUD: TabLargeContentHUD?

    /// Shows the tab under the finger large while it is held there, at the
    /// accessibility text sizes; the bar itself selects the tab where the
    /// finger lifts.
    @objc private func onTabHeld(_ recognizer: UILongPressGestureRecognizer) {
        guard let bar = tabBar else { return }
        switch recognizer.state {
        case .began, .changed:
            guard UIApplication.shared.preferredContentSizeCategory.isAccessibilityCategory,
                  let window = bar.window,
                  let item = item(at: recognizer.location(in: bar))
            else {
                largeContentHUD?.dismiss()
                largeContentHUD = nil
                return
            }
            let hud = largeContentHUD ?? TabLargeContentHUD(in: window)
            largeContentHUD = hud
            hud.show(title: item.title, image: item.image)
        default:
            largeContentHUD?.dismiss()
            largeContentHUD = nil
        }
    }

    func tabBar(_ tabBar: UITabBar, didSelect item: UITabBarItem) {
        if let bar = self.tabBar, bar === tabBar, let items = bar.items, let idx = items.firstIndex(of: item) {
            channel.invokeMethod("valueChanged", arguments: ["index": idx])
        }
    }

    private static func colorFromARGB(_ argb: Int) -> UIColor {
        let a = CGFloat((argb >> 24) & 0xFF) / 255.0
        let r = CGFloat((argb >> 16) & 0xFF) / 255.0
        let g = CGFloat((argb >> 8) & 0xFF) / 255.0
        let b = CGFloat(argb & 0xFF) / 255.0
        return UIColor(red: r, green: g, blue: b, alpha: a)
    }

    private func runtimeFilePath(for index: Int, selected: Bool) -> String {
        let paths = selected ? currentSelectedFileIcons : currentFileIcons
        if index < paths.count, !paths[index].isEmpty {
            return paths[index]
        }
        if selected, index < currentFileIcons.count {
            return currentFileIcons[index]
        }
        return ""
    }

    private func runtimeNetworkURL(for index: Int, selected: Bool) -> String {
        let urls = selected ? currentSelectedNetworkIcons : currentNetworkIcons
        if index < urls.count, !urls[index].isEmpty {
            return urls[index]
        }
        if selected, index < currentNetworkIcons.count {
            return currentNetworkIcons[index]
        }
        return ""
    }

    private func hasRuntimeImage(for index: Int) -> Bool {
        return !runtimeFilePath(for: index, selected: false).isEmpty ||
            !runtimeNetworkURL(for: index, selected: false).isEmpty ||
            !runtimeFilePath(for: index, selected: true).isEmpty ||
            !runtimeNetworkURL(for: index, selected: true).isEmpty
    }

    private func placeholderAvatarImage() -> UIImage? {
        return UIImage(systemName: "person.crop.circle")
    }

    private func loadRuntimeImage(filePath: String, networkURL: String) -> UIImage? {
        if !filePath.isEmpty, let image = UIImage(contentsOfFile: filePath) {
            return avatarImage(from: image)
        }

        if !networkURL.isEmpty, let cached = imageCache.object(forKey: networkURL as NSString) {
            return avatarImage(from: cached)
        }

        return nil
    }

    private func fetchNetworkImageIfNeeded(
        urlString: String,
        completion: @escaping (UIImage?) -> Void
    ) {
        guard !urlString.isEmpty else {
            completion(nil)
            return
        }

        if let cached = imageCache.object(forKey: urlString as NSString) {
            completion(avatarImage(from: cached))
            return
        }

        guard let url = URL(string: urlString) else {
            completion(nil)
            return
        }

        URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
            guard let self = self,
                  let data = data,
                  let image = UIImage(data: data) else {
                DispatchQueue.main.async { completion(nil) }
                return
            }

            self.imageCache.setObject(image, forKey: urlString as NSString)
            let avatar = self.avatarImage(from: image)
            DispatchQueue.main.async {
                completion(avatar)
            }
        }.resume()
    }

    private func configureRuntimeImages(for item: UITabBarItem, index: Int) -> Bool {
        guard hasRuntimeImage(for: index) else { return false }

        let unselectedFile = runtimeFilePath(for: index, selected: false)
        let selectedFile = runtimeFilePath(for: index, selected: true)
        let unselectedNetwork = runtimeNetworkURL(for: index, selected: false)
        let selectedNetwork = runtimeNetworkURL(for: index, selected: true)

        let unselectedImage = loadRuntimeImage(filePath: unselectedFile, networkURL: unselectedNetwork)
        let selectedImage = loadRuntimeImage(filePath: selectedFile, networkURL: selectedNetwork)

        item.image = (unselectedImage ?? placeholderAvatarImage())?.withRenderingMode(.alwaysOriginal)
        item.selectedImage = (selectedImage ?? unselectedImage ?? placeholderAvatarImage())?.withRenderingMode(.alwaysOriginal)

        if unselectedImage == nil && !unselectedNetwork.isEmpty {
            fetchNetworkImageIfNeeded(urlString: unselectedNetwork) { [weak item] avatar in
                guard let item = item, let avatar = avatar else { return }
                item.image = avatar.withRenderingMode(.alwaysOriginal)
                if selectedImage == nil && selectedNetwork.isEmpty && selectedFile.isEmpty {
                    item.selectedImage = avatar.withRenderingMode(.alwaysOriginal)
                }
            }
        }

        if selectedImage == nil && !selectedNetwork.isEmpty {
            fetchNetworkImageIfNeeded(urlString: selectedNetwork) { [weak item] avatar in
                guard let item = item, let avatar = avatar else { return }
                item.selectedImage = avatar.withRenderingMode(.alwaysOriginal)
            }
        }

        return true
    }

    private func resizeImage(image: UIImage, targetSize: CGSize = CGSize(width: 26, height: 26)) -> UIImage {
        let size = image.size
        if size.width <= targetSize.width && size.height <= targetSize.height {
            return image
        }
        
        let widthRatio = targetSize.width / size.width
        let heightRatio = targetSize.height / size.height
        let ratio = min(widthRatio, heightRatio)
        
        let newSize = CGSize(width: size.width * ratio, height: size.height * ratio)
        let rect = CGRect(x: 0, y: 0, width: newSize.width, height: newSize.height)
        
        if #available(iOS 10.0, *) {
            let format = UIGraphicsImageRendererFormat()
            format.scale = UIScreen.main.scale
            let renderer = UIGraphicsImageRenderer(size: newSize, format: format)
            return renderer.image { context in
                image.draw(in: rect)
            }
        } else {
            UIGraphicsBeginImageContextWithOptions(newSize, false, UIScreen.main.scale)
            image.draw(in: rect)
            let newImage = UIGraphicsGetImageFromCurrentImageContext()
            UIGraphicsEndImageContext()
            return newImage ?? image
        }
    }

    private func avatarImage(from image: UIImage, targetSize: CGSize = CGSize(width: 26, height: 26)) -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: targetSize)
        return renderer.image { _ in
            UIBezierPath(ovalIn: CGRect(origin: .zero, size: targetSize)).addClip()

            let aspectFillScale = max(targetSize.width / image.size.width, targetSize.height / image.size.height)
            let scaledSize = CGSize(width: image.size.width * aspectFillScale, height: image.size.height * aspectFillScale)
            let origin = CGPoint(
                x: (targetSize.width - scaledSize.width) / 2.0,
                y: (targetSize.height - scaledSize.height) / 2.0
            )

            image.draw(in: CGRect(origin: origin, size: scaledSize))
        }
    }
}

class iOS26TabBarViewFactory: NSObject, FlutterPlatformViewFactory {
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
        return iOS26TabBarPlatformView(
            frame: frame,
            viewId: viewId,
            args: args,
            messenger: messenger
        )
    }

    func createArgsCodec() -> FlutterMessageCodec & NSObjectProtocol {
        return FlutterStandardMessageCodec.sharedInstance()
    }
}

/// The badge text for a count from Dart: nil for none, "99+" past 99, and an
/// empty string, which UIKit draws as a dot, for -1 (`kBadgeDot`).
func tabBadgeText(_ count: Int?) -> String? {
    guard let count = count else { return nil }
    if count == -1 { return "" }
    if count <= 0 { return nil }
    return count > 99 ? "99+" : String(count)
}

extension iOS26TabBarPlatformView: UIGestureRecognizerDelegate {
    /// Alongside the bar's own gestures (selecting, sliding across the tabs):
    /// the bar keeps doing what it does.
    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer
    ) -> Bool {
        return true
    }
}

/// The large view of a tab that a finger is held on, as the system's tab bars
/// show it at the accessibility text sizes: its icon and title on a
/// translucent panel in the middle of the screen. A standalone tab bar does
/// not get the system's large content viewer: the bar's own selection
/// gesture keeps it from starting.
private final class TabLargeContentHUD {
    private let panel = UIVisualEffectView(effect: UIBlurEffect(style: .systemThickMaterial))
    private let imageView = UIImageView()
    private let titleLabel = UILabel()

    init(in window: UIWindow) {
        panel.layer.cornerRadius = 20
        panel.layer.cornerCurve = .continuous
        panel.clipsToBounds = true
        panel.alpha = 0
        panel.isUserInteractionEnabled = false
        imageView.contentMode = .scaleAspectFit
        imageView.tintColor = .secondaryLabel
        titleLabel.font = .systemFont(ofSize: 32)
        titleLabel.textColor = .secondaryLabel
        titleLabel.textAlignment = .center
        titleLabel.adjustsFontSizeToFitWidth = true
        titleLabel.minimumScaleFactor = 0.5
        let stack = UIStackView(arrangedSubviews: [imageView, titleLabel])
        stack.axis = .vertical
        stack.alignment = .center
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        panel.contentView.addSubview(stack)
        panel.translatesAutoresizingMaskIntoConstraints = false
        window.addSubview(panel)
        NSLayoutConstraint.activate([
            imageView.widthAnchor.constraint(equalToConstant: 56),
            imageView.heightAnchor.constraint(equalToConstant: 56),
            stack.topAnchor.constraint(equalTo: panel.contentView.topAnchor, constant: 24),
            stack.bottomAnchor.constraint(equalTo: panel.contentView.bottomAnchor, constant: -24),
            stack.leadingAnchor.constraint(equalTo: panel.contentView.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: panel.contentView.trailingAnchor, constant: -24),
            panel.centerXAnchor.constraint(equalTo: window.centerXAnchor),
            panel.centerYAnchor.constraint(equalTo: window.centerYAnchor),
            panel.widthAnchor.constraint(greaterThanOrEqualToConstant: 160),
            panel.widthAnchor.constraint(lessThanOrEqualTo: window.widthAnchor, constant: -64),
        ])
    }

    func show(title: String?, image: UIImage?) {
        titleLabel.text = title
        imageView.image = image?.withRenderingMode(.alwaysTemplate)
        imageView.isHidden = image == nil
        guard panel.alpha < 1 else { return }
        UIView.animate(withDuration: 0.15) { self.panel.alpha = 1 }
    }

    func dismiss() {
        let panel = self.panel
        UIView.animate(withDuration: 0.15, animations: { panel.alpha = 0 }) { _ in
            panel.removeFromSuperview()
        }
    }
}
