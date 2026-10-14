import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Provides platform detection and iOS version information
///
/// This class helps determine the current platform and iOS version
/// to enable adaptive widget rendering based on platform capabilities.
class PlatformInfo {
  /// Replaces the detected platform, so tests can take the iOS 26+ and
  /// Android paths on any host. Null uses the real platform.
  ///
  /// Native views still need UIKit: on a host without it they draw their
  /// Flutter fallbacks, whatever this says.
  @visibleForTesting
  static TargetPlatform? debugPlatformOverride;

  /// Replaces the detected iOS major version while [isIOS] is true.
  @visibleForTesting
  static int? debugIOSVersionOverride;

  /// Replaces [isIPad] in tests.
  @visibleForTesting
  static bool? debugIPadOverride;

  /// Replaces [displayCornerRadius] in tests.
  @visibleForTesting
  static double? debugDisplayCornerRadiusOverride;

  static bool _isIPad = false;
  static double _displayCornerRadius = 0;
  static Future<void>? _deviceLoad;

  /// Whether the app runs on an iPad, whose windows have window controls in
  /// their top leading corner. An iPhone (the iPhone Duo too, in split view)
  /// has none. Read from the device once [loadDevice] completes; false until
  /// then, and off iOS.
  static bool get isIPad => debugIPadOverride ?? (isIOS && _isIPad);

  /// The radius of the corners of the display the app is on, in logical
  /// pixels: what glass with concentric corners follows, less its distance
  /// from the display's edges. Read from the device once [loadDevice]
  /// completes, and again by [loadDisplayCornerRadius]; 0 until then, before
  /// iOS 26 and off iOS.
  static double get displayCornerRadius =>
      debugDisplayCornerRadiusOverride ?? (isIOS ? _displayCornerRadius : 0);

  static const _device = MethodChannel('adaptive_platform_ui/device');

  /// Asks the device what it is, once; [AdaptiveToolbarHost] does this.
  static Future<void> loadDevice() => _deviceLoad ??= _loadDevice();

  static Future<void> _loadDevice() async {
    if (!isIOS || debugPlatformOverride != null) return;
    try {
      _isIPad = await _device.invokeMethod<bool>('isPad') ?? false;
    } catch (_) {
      // Without the native side (tests, other hosts) it is no iPad.
    }
    await loadDisplayCornerRadius();
  }

  /// Measures [displayCornerRadius] again, for a window that moved to another
  /// display (the iPhone Duo, folded or unfolded); [AdaptiveToolbarHost] does
  /// this when the window changes size.
  static Future<void> loadDisplayCornerRadius() async {
    if (!isIOS) return;
    try {
      _displayCornerRadius =
          await _device.invokeMethod<double>('displayCornerRadius') ?? 0;
    } catch (_) {
      // Without the native side (tests, other hosts) the corners are square.
    }
  }

  static bool _isPlatform(TargetPlatform platform, bool Function() detect) {
    final override = debugPlatformOverride;
    if (override != null) return override == platform;
    return !kIsWeb && detect();
  }

  /// Returns true if the current platform is iOS
  static bool get isIOS =>
      _isPlatform(TargetPlatform.iOS, () => Platform.isIOS);

  /// Returns true if the current platform is Android
  static bool get isAndroid =>
      _isPlatform(TargetPlatform.android, () => Platform.isAndroid);

  /// Returns true if the current platform is macOS
  static bool get isMacOS =>
      _isPlatform(TargetPlatform.macOS, () => Platform.isMacOS);

  /// Returns true if the current platform is Windows
  static bool get isWindows =>
      _isPlatform(TargetPlatform.windows, () => Platform.isWindows);

  /// Returns true if the current platform is Linux
  static bool get isLinux =>
      _isPlatform(TargetPlatform.linux, () => Platform.isLinux);

  /// Returns true if the current platform is Fuchsia
  static bool get isFuchsia =>
      _isPlatform(TargetPlatform.fuchsia, () => Platform.isFuchsia);

  /// Returns true if running on web
  static bool get isWeb => debugPlatformOverride == null && kIsWeb;

  /// Returns the iOS major version number
  ///
  /// Returns 0 if not running on iOS or if version cannot be determined.
  /// Example: For iOS 26.1.2, returns 26
  static int get iOSVersion {
    if (!isIOS) return 0;
    final versionOverride = debugIOSVersionOverride;
    if (versionOverride != null) return versionOverride;
    // Read on every build of every page: the OS string is parsed once.
    return _detectedIOSVersion ??= _parseIOSVersion();
  }

  static int? _detectedIOSVersion;

  static int _parseIOSVersion() {
    try {
      final version = Platform.operatingSystemVersion;
      // Extract major version from string like "Version 26.1.2 (Build 20A123)"
      final match = RegExp(r'Version (\d+)').firstMatch(version);
      if (match != null) {
        return int.parse(match.group(1)!);
      }

      // Fallback: try to parse the first number in the version string
      final fallbackMatch = RegExp(r'(\d+)').firstMatch(version);
      if (fallbackMatch != null) {
        return int.parse(fallbackMatch.group(1)!);
      }
    } catch (e) {
      debugPrint('Error parsing iOS version: $e');
    }

    return 0;
  }

  /// Returns true if iOS version is 26 or higher
  ///
  /// This is used to determine if iOS 26+ specific widgets should be used.
  static bool isIOS26OrHigher() {
    return isIOS && iOSVersion >= 26;
  }

  /// Returns true if iOS version is 18 or lower (pre-iOS 26)
  ///
  /// This is used to determine if legacy Cupertino widgets should be used.
  static bool isIOS18OrLower() {
    return isIOS && iOSVersion > 0 && iOSVersion < 26;
  }

  /// Returns true if iOS version is in a specific range
  ///
  /// [min] - Minimum iOS version (inclusive)
  /// [max] - Maximum iOS version (inclusive)
  static bool isIOSVersionInRange(int min, int max) {
    return isIOS && iOSVersion >= min && iOSVersion <= max;
  }

  /// Returns a human-readable platform description
  static String get platformDescription {
    if (isIOS) return 'iOS $iOSVersion';
    if (isAndroid) return 'Android';
    if (isMacOS) return 'macOS';
    if (isWindows) return 'Windows';
    if (isLinux) return 'Linux';
    if (isFuchsia) return 'Fuchsia';
    if (isWeb) return 'Web';
    return 'Unknown';
  }
}
