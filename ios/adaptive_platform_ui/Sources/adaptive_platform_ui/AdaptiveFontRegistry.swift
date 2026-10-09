import CoreText
import Flutter
import UIKit

/// The app font, registered from the app's Flutter assets (Dart:
/// `AdaptiveNativeFonts.register`), so native views can draw their text in the
/// same typeface as the Flutter UI around them instead of the system font.
final class AdaptiveFontRegistry {
    static let shared = AdaptiveFontRegistry()

    /// Posted on the main queue once faces were registered, so native views
    /// that were already on screen can switch to the app font.
    static let didRegister = Notification.Name("AdaptiveFontRegistryDidRegister")

    /// PostScript names of the registered faces, by weight (100...900).
    private var faces: [Int: String] = [:]

    /// Registers `[{"asset": "assets/fonts/x.ttf", "weight": 400}, ...]`.
    func register(_ fonts: [[String: Any]]) {
        for font in fonts {
            guard let asset = font["asset"] as? String,
                  let weight = (font["weight"] as? NSNumber)?.intValue,
                  let path = Bundle.main.path(
                      forResource: FlutterDartProject.lookupKey(forAsset: asset),
                      ofType: nil
                  )
            else { continue }
            let url = URL(fileURLWithPath: path) as CFURL
            guard let provider = CGDataProvider(url: url),
                  let face = CGFont(provider),
                  let name = face.postScriptName as String?
            else { continue }
            // Fails for a face that is already registered (a hot restart, a
            // second engine), which is fine as it is.
            CTFontManagerRegisterFontsForURL(url, .process, nil)
            faces[weight] = name
        }
        NotificationCenter.default.post(name: Self.didRegister, object: self)
    }

    /// The registered face closest to `weight` (100...900; a tie goes to the
    /// heavier face), or nil when the app registered none.
    func font(weight: Int, size: CGFloat) -> UIFont? {
        let nearest = faces.keys.min { a, b in
            let da = abs(a - weight)
            let db = abs(b - weight)
            return da < db || (da == db && a > b)
        }
        guard let nearest, let name = faces[nearest] else { return nil }
        return UIFont(name: name, size: size)
    }
}

/// Draws the item titles of `bar` in the app font, if one is registered.
func applyAppFont(to bar: UITabBar) {
    guard let font = AdaptiveFontRegistry.shared.font(weight: 400, size: 10),
          let items = bar.items
    else { return }
    for item in items {
        item.setTitleTextAttributes([.font: font], for: .normal)
        item.setTitleTextAttributes([.font: font], for: .selected)
    }
    // Titles of items that are already in the bar keep the width they were
    // measured at in the system font, which truncates a wider face. Installed
    // again, they are laid out in the app font.
    let selected = bar.selectedItem
    bar.items = nil
    bar.items = items
    bar.selectedItem = selected
}
