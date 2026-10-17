import 'package:adaptive_platform_ui/adaptive_platform_ui.dart';
import 'package:adaptive_platform_ui/src/toolbar/hosted_duo_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'custom_chrome_fixture.dart';

void main() {
  setUp(() {
    PlatformInfo.debugPlatformOverride = TargetPlatform.iOS;
    PlatformInfo.debugIOSVersionOverride = 26;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          SystemChannels.platform_views,
          (_) async => null,
        );
  });

  tearDown(() {
    PlatformInfo.debugPlatformOverride = null;
    PlatformInfo.debugIOSVersionOverride = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform_views, null);
  });

  const body = Key('body');

  Future<EdgeInsets> pumpPage(
    WidgetTester tester, {
    required bool extend,
    Color? tint,
    bool tintsBack = false,
  }) async {
    tester.view.physicalSize = const Size(951, 669);
    tester.view.devicePixelRatio = 1;
    tester.view.padding = const FakeViewPadding(right: 84, bottom: 34);
    tester.view.viewPadding = const FakeViewPadding(right: 84, bottom: 34);
    addTearDown(tester.view.reset);
    late EdgeInsets padding;
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) =>
            AdaptiveToolbarHost(debugFold: duo(), child: child!),
        home: const Scaffold(body: Text('first')),
      ),
    );
    final navigator = tester.state<NavigatorState>(find.byType(Navigator));
    navigator.push(
      MaterialPageRoute<void>(
        builder: (context) => AdaptiveScaffold(
          appBar: AdaptiveAppBar(
            title: 'Page',
            useNativeToolbar: true,
            tintColor: tint,
            tintsBackButton: tintsBack,
          ),
          extendBodyUnderDuoBar: extend,
          body: Builder(
            builder: (context) {
              padding = MediaQuery.paddingOf(context);
              return const SizedBox.expand(key: body);
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return padding;
  }

  testWidgets('a page keeps out of the strip of the vertical bar by default', (
    tester,
  ) async {
    final padding = await pumpPage(tester, extend: false);

    expect(tester.getRect(find.byKey(body)).right, 951 - 84);
    expect(padding.right, 0);
  });

  testWidgets(
    'a page that keeps its content clear runs under the bar, the strip left in its padding',
    (tester) async {
      final padding = await pumpPage(tester, extend: true);

      expect(tester.getRect(find.byKey(body)).right, 951);
      expect(padding.right, 84);
    },
  );

  testWidgets('the back button in the bar keeps the system\'s colour, or '
      'takes the tint of the bar where the app bar asks for it', (
    tester,
  ) async {
    IOS26GlassCapsule back() => tester.widget<IOS26GlassCapsule>(
      find
          .descendant(
            of: find.byType(HostedDuoBar),
            matching: find.byType(IOS26GlassCapsule),
          )
          .first,
    );
    await pumpPage(tester, extend: true, tint: const Color(0xFF007C30));
    expect(back().items.single.symbol, 'chevron.left');
    expect(back().items.single.tint, isNull);

    await pumpPage(
      tester,
      extend: true,
      tint: const Color(0xFF007C30),
      tintsBack: true,
    );
    expect(back().items.single.tint, const Color(0xFF007C30));
  });

  test('controls begin half a control from the middle of the band', () {
    const pose = DuoPose(
      side: DuoBarSide.right,
      stripWidth: 84,
      reservedBySystem: true,
    );

    expect(pose.controlsEdge, 72);
    // A margin from the controls is a margin, as from the other edge.
    expect(
      pose.controlsEdge,
      (84 + kDuoVerticalBarBezelInset) / 2 + IOS26GlassCapsule.width / 2,
    );
  });
}
