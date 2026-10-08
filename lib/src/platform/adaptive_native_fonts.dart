import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Lets the native iOS 26 views draw their text (tab bar labels, segmented
/// controls) in the app's font instead of the system font, so they match the
/// Flutter UI around them.
abstract final class AdaptiveNativeFonts {
  static const _channel = MethodChannel('adaptive_platform_ui/fonts');

  /// Registers the font files of one family, by weight, as listed under
  /// `fonts:` in the app's pubspec. Call it once, before the native views
  /// that should use it are shown. Native views pick the closest weight
  /// available. Does nothing where there is no UIKit.
  static Future<void> register(Map<FontWeight, String> assetsByWeight) async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.iOS) return;
    await _channel.invokeMethod<void>('register', <String, Object>{
      'fonts': [
        for (final MapEntry(key: weight, value: asset)
            in assetsByWeight.entries)
          <String, Object>{'asset': asset, 'weight': weight.value},
      ],
    });
  }
}
