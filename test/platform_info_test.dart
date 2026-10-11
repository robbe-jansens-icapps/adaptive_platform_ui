import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:adaptive_platform_ui/adaptive_platform_ui.dart';

void main() {
  group('PlatformInfo', () {
    test('returns valid platform type', () {
      // At least one platform should be detected
      final hasValidPlatform =
          PlatformInfo.isIOS ||
          PlatformInfo.isAndroid ||
          PlatformInfo.isMacOS ||
          PlatformInfo.isWindows ||
          PlatformInfo.isLinux ||
          PlatformInfo.isFuchsia ||
          PlatformInfo.isWeb;

      expect(hasValidPlatform, isTrue);
    });

    test('iOS version methods work correctly', () {
      if (PlatformInfo.isIOS) {
        expect(PlatformInfo.iOSVersion, greaterThanOrEqualTo(0));

        // Version checks should be consistent
        final version = PlatformInfo.iOSVersion;
        if (version >= 26) {
          expect(PlatformInfo.isIOS26OrHigher(), isTrue);
          expect(PlatformInfo.isIOS18OrLower(), isFalse);
        } else if (version > 0 && version < 26) {
          expect(PlatformInfo.isIOS26OrHigher(), isFalse);
          expect(PlatformInfo.isIOS18OrLower(), isTrue);
        }
      } else {
        // Non-iOS platforms should return 0 for iOS version
        expect(PlatformInfo.iOSVersion, equals(0));
        expect(PlatformInfo.isIOS26OrHigher(), isFalse);
        expect(PlatformInfo.isIOS18OrLower(), isFalse);
      }
    });

    test('isIOSVersionInRange works correctly', () {
      if (PlatformInfo.isIOS) {
        final version = PlatformInfo.iOSVersion;
        if (version > 0) {
          expect(PlatformInfo.isIOSVersionInRange(version, version), isTrue);
          expect(
            PlatformInfo.isIOSVersionInRange(version - 1, version + 1),
            isTrue,
          );
          expect(
            PlatformInfo.isIOSVersionInRange(version + 1, version + 2),
            isFalse,
          );
        }
      } else {
        expect(PlatformInfo.isIOSVersionInRange(1, 100), isFalse);
      }
    });

    test('platformDescription returns non-empty string', () {
      expect(PlatformInfo.platformDescription.isNotEmpty, isTrue);
    });

    test('only one primary platform is detected', () {
      // On native platforms, only one platform should be true
      if (!PlatformInfo.isWeb) {
        final platformCount = [
          PlatformInfo.isIOS,
          PlatformInfo.isAndroid,
          PlatformInfo.isMacOS,
          PlatformInfo.isWindows,
          PlatformInfo.isLinux,
          PlatformInfo.isFuchsia,
        ].where((p) => p).length;

        expect(platformCount, equals(1));
      }
    });
  });

  group('PlatformInfo debug overrides', () {
    tearDown(() {
      PlatformInfo.debugPlatformOverride = null;
      PlatformInfo.debugIOSVersionOverride = null;
    });

    test('an iOS override with a version takes the iOS 26+ path', () {
      PlatformInfo.debugPlatformOverride = TargetPlatform.iOS;
      PlatformInfo.debugIOSVersionOverride = 27;

      expect(PlatformInfo.isIOS, isTrue);
      expect(PlatformInfo.isAndroid, isFalse);
      expect(PlatformInfo.isWeb, isFalse);
      expect(PlatformInfo.iOSVersion, 27);
      expect(PlatformInfo.isIOS26OrHigher(), isTrue);
      expect(PlatformInfo.platformDescription, 'iOS 27');
    });

    test('an older iOS version override takes the legacy iOS path', () {
      PlatformInfo.debugPlatformOverride = TargetPlatform.iOS;
      PlatformInfo.debugIOSVersionOverride = 18;

      expect(PlatformInfo.isIOS26OrHigher(), isFalse);
      expect(PlatformInfo.isIOS18OrLower(), isTrue);
    });

    test('an Android override reports no iOS version', () {
      PlatformInfo.debugPlatformOverride = TargetPlatform.android;
      PlatformInfo.debugIOSVersionOverride = 26;

      expect(PlatformInfo.isAndroid, isTrue);
      expect(PlatformInfo.isIOS, isFalse);
      expect(PlatformInfo.iOSVersion, 0);
      expect(PlatformInfo.isIOS26OrHigher(), isFalse);
    });

    test('other platforms can be overridden too', () {
      for (final platform in [
        TargetPlatform.macOS,
        TargetPlatform.windows,
        TargetPlatform.linux,
        TargetPlatform.fuchsia,
      ]) {
        PlatformInfo.debugPlatformOverride = platform;
        expect(PlatformInfo.isMacOS, platform == TargetPlatform.macOS);
        expect(PlatformInfo.isWindows, platform == TargetPlatform.windows);
        expect(PlatformInfo.isLinux, platform == TargetPlatform.linux);
        expect(PlatformInfo.isFuchsia, platform == TargetPlatform.fuchsia);
      }
    });
  });

  group('PlatformInfo.displayCornerRadius', () {
    TestWidgetsFlutterBinding.ensureInitialized();
    const device = MethodChannel('adaptive_platform_ui/device');
    Object? measured;

    setUp(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            device,
            (call) async =>
                call.method == 'displayCornerRadius' ? measured : null,
          );
    });

    tearDown(() async {
      // Back to square corners for the tests after these.
      measured = 0.0;
      PlatformInfo.debugPlatformOverride = TargetPlatform.iOS;
      await PlatformInfo.loadDisplayCornerRadius();
      PlatformInfo.debugPlatformOverride = null;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(device, null);
    });

    test('is measured on iOS, and measured again on request', () async {
      PlatformInfo.debugPlatformOverride = TargetPlatform.iOS;
      expect(PlatformInfo.displayCornerRadius, 0);

      measured = 55.0;
      await PlatformInfo.loadDisplayCornerRadius();
      expect(PlatformInfo.displayCornerRadius, 55);

      // The iPhone Duo, unfolded: the window is on the other display.
      measured = 38.0;
      await PlatformInfo.loadDisplayCornerRadius();
      expect(PlatformInfo.displayCornerRadius, 38);
    });

    test('is square elsewhere', () async {
      measured = 55.0;
      PlatformInfo.debugPlatformOverride = TargetPlatform.android;
      await PlatformInfo.loadDisplayCornerRadius();
      expect(PlatformInfo.displayCornerRadius, 0);
    });

    test('concentric glass follows it, never below its own radius', () {
      PlatformInfo.debugPlatformOverride = TargetPlatform.iOS;
      PlatformInfo.debugDisplayCornerRadiusOverride = 60;
      addTearDown(() => PlatformInfo.debugDisplayCornerRadiusOverride = null);
      expect(IOS26GlassSurface.concentricRadius(inset: 8, minimum: 34), 52);

      PlatformInfo.debugDisplayCornerRadiusOverride = 30;
      expect(IOS26GlassSurface.concentricRadius(inset: 8, minimum: 34), 34);
    });
  });
}
