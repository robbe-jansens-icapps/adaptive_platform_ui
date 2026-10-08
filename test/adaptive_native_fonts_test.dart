import 'package:adaptive_platform_ui/adaptive_platform_ui.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('adaptive_platform_ui/fonts');
  final calls = <MethodCall>[];

  setUp(() {
    calls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          return null;
        });
  });

  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('hands the font files and their weights to iOS', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;

    await AdaptiveNativeFonts.register({
      FontWeight.w400: 'assets/fonts/rubik/rubik_regular.ttf',
      FontWeight.w600: 'assets/fonts/rubik/rubik_semi_bold.ttf',
    });

    expect(calls.single.method, 'register');
    expect(calls.single.arguments, {
      'fonts': [
        {'asset': 'assets/fonts/rubik/rubik_regular.ttf', 'weight': 400},
        {'asset': 'assets/fonts/rubik/rubik_semi_bold.ttf', 'weight': 600},
      ],
    });
  });

  test('does nothing where there is no UIKit', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;

    await AdaptiveNativeFonts.register({FontWeight.w400: 'font.ttf'});

    expect(calls, isEmpty);
  });
}
