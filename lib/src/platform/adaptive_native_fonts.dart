import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:flutter/services.dart';

/// Lets the native iOS 26 views draw their text (tab bar labels, segmented
/// controls) in the app's font instead of the system font, so they match the
/// Flutter UI around them.
abstract final class AdaptiveNativeFonts {
  static const _channel = MethodChannel('adaptive_platform_ui/fonts');

  /// The weights of the faces registered.
  static List<FontWeight> _weights = const [];

  /// Registers the font files of one family, by weight, as listed under
  /// `fonts:` in the app's pubspec. Call it once, before the native views
  /// that should use it are shown. Native views pick the closest weight
  /// available. Does nothing where there is no UIKit.
  static Future<void> register(Map<FontWeight, String> assetsByWeight) async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.iOS) return;
    _weights = [...assetsByWeight.keys];
    await _channel.invokeMethod<void>('register', <String, Object>{
      'fonts': [
        for (final MapEntry(key: weight, value: asset)
            in assetsByWeight.entries)
          <String, Object>{'asset': asset, 'weight': weight.value},
      ],
    });
  }

  /// The style a native view draws text of [weight] in, for a Flutter
  /// stand-in of it to look the same: the registered face closest to
  /// [weight], a tie going to the heavier one as iOS picks it (Flutter would
  /// take the lighter), in the family of the text around it; or the system
  /// font, where the app registered none. Either without the letter spacing
  /// the text around it may have.
  static TextStyle textStyle(FontWeight weight) {
    if (_weights.isEmpty) {
      return TextStyle(
        fontFamily: 'CupertinoSystemText',
        fontWeight: weight,
        letterSpacing: 0,
      );
    }
    final nearest = _weights.reduce((a, b) {
      final da = (a.value - weight.value).abs();
      final db = (b.value - weight.value).abs();
      return da < db || (da == db && a.value > b.value) ? a : b;
    });
    return TextStyle(fontWeight: nearest, letterSpacing: 0);
  }

  /// Forgets the faces registered.
  @visibleForTesting
  static void debugReset() => _weights = const [];
}
