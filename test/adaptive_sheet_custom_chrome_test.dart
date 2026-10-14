import 'package:adaptive_platform_ui/adaptive_platform_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'custom_chrome_fixture.dart';

void main() {
  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform_views, (_) async => null);
  });

  tearDown(() {
    PlatformInfo.debugPlatformOverride = null;
    PlatformInfo.debugIOSVersionOverride = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform_views, null);
  });

  Widget app() => MaterialApp(
    builder: (context, child) => AdaptiveToolbarHost(
      chrome: TestChrome.chrome.copyWithGlass(const AdaptiveGlassStyle(tint: Color(0xE0101820))),
      child: child!,
    ),
    home: const Stack(
      children: [
        Positioned.fill(child: ColoredBox(color: Colors.green)),
        Positioned.fill(
          child: AdaptiveSheet(
            detents: [AdaptiveSheetDetent.collapsed, AdaptiveSheetDetent.fitContent],
            header: SizedBox(height: 60, child: Text('header')),
            child: SizedBox(height: 200, child: Text('content')),
          ),
        ),
      ],
    ),
  );

  for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
    testWidgets('under custom chrome a sheet floats on the app\'s glass on ${platform.name}', (tester) async {
      PlatformInfo.debugPlatformOverride = platform;
      PlatformInfo.debugIOSVersionOverride = 26;
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1;
      tester.view.padding = const FakeViewPadding(top: 60, bottom: 34);
      tester.view.viewPadding = const FakeViewPadding(top: 60, bottom: 34);
      addTearDown(tester.view.reset);
      await tester.pumpWidget(app());
      await tester.pumpAndSettle();

      final glass = find.ancestor(of: find.text('content'), matching: find.byType(AdaptiveGlass));
      expect(glass, findsOneWidget);
      expect(find.ancestor(of: find.text('content'), matching: find.byType(IOS26GlassSurface)), findsNothing);
      final rect = tester.getRect(glass);
      expect(rect.left, greaterThan(0));
      expect(rect.right, lessThan(400));
      final tint = tester
          .widgetList<DecoratedBox>(find.descendant(of: glass, matching: find.byType(DecoratedBox)))
          .map((box) => box.decoration)
          .whereType<ShapeDecoration>()
          .firstWhere((decoration) => decoration.color != null);
      expect(tint.color, const Color(0xE0101820));
    });
  }
}
