import 'package:adaptive_platform_ui/adaptive_platform_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const screen = Size(402, 874);
  const keyboard = 300.0;
  const pageKey = ValueKey<String>('page');

  setUp(() {
    PlatformInfo.debugPlatformOverride = TargetPlatform.iOS;
    PlatformInfo.debugIOSVersionOverride = 26;
  });

  tearDown(() {
    PlatformInfo.debugPlatformOverride = null;
    PlatformInfo.debugIOSVersionOverride = null;
  });

  testWidgets('a page with a toolbar makes room for the keyboard once', (
    tester,
  ) async {
    tester.view.physicalSize = screen;
    tester.view.devicePixelRatio = 1;
    tester.view.padding = const FakeViewPadding(top: 62);
    tester.view.viewPadding = const FakeViewPadding(top: 62, bottom: 34);
    tester.view.viewInsets = const FakeViewPadding(bottom: keyboard);
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      const MaterialApp(
        home: AdaptiveScaffold(
          appBar: AdaptiveAppBar(title: 'Login', useNativeToolbar: true),
          // A page that resizes for the keyboard on its own, as most do.
          body: Scaffold(body: SizedBox.expand(key: pageKey)),
        ),
      ),
    );

    expect(
      tester.getSize(find.byKey(pageKey)).height,
      screen.height - keyboard,
    );
  });
}
