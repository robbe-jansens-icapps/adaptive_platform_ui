import 'package:adaptive_platform_ui/adaptive_platform_ui.dart';
import 'package:flutter/foundation.dart';
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

  const list = ValueKey<String>('list');
  const pinned = ValueKey<String>('pinned');

  void cover(WidgetTester tester) {
    tester.view.physicalSize = const Size(466, 678);
    tester.view.devicePixelRatio = 1;
    tester.view.padding = const FakeViewPadding(right: 84);
    tester.view.viewPadding = const FakeViewPadding(right: 84);
    addTearDown(tester.view.reset);
  }

  void phone(WidgetTester tester) {
    tester.view.physicalSize = const Size(402, 874);
    tester.view.devicePixelRatio = 1;
    tester.view.padding = const FakeViewPadding(top: 62, bottom: 34);
    tester.view.viewPadding = const FakeViewPadding(top: 62, bottom: 34);
    addTearDown(tester.view.reset);
  }

  late ValueListenable<double> shown;

  Widget rows() => Builder(
    builder: (context) {
      shown = AdaptiveTopBarVisibility.of(context);
      return ListView(
        key: list,
        children: [
          for (var i = 0; i < 40; i++) SizedBox(height: 60, child: Text('$i')),
        ],
      );
    },
  );

  Future<void> pumpPage(
    WidgetTester tester, {
    bool hidesOnScroll = true,
    bool disableAnimations = false,
    Widget? body,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(disableAnimations: disableAnimations),
          child: AdaptiveToolbarHost(debugFold: duo(), child: child!),
        ),
        home: AdaptiveScaffold(
          appBar: AdaptiveAppBar(
            title: 'Page',
            useNativeToolbar: true,
            hidesOnScroll: hidesOnScroll,
          ),
          body: body ?? rows(),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  double titleBandShown(WidgetTester tester) => tester
      .widget<DuoTitleBandTransition>(find.byType(DuoTitleBandTransition).first)
      .shown
      .value;

  testWidgets('beside the iPhone Duo\'s vertical bar the title band moves out '
      'of the way while the page scrolls on and comes back as it scrolls '
      'back, and the page can follow it', (tester) async {
    cover(tester);
    await pumpPage(tester);
    expect(titleBandShown(tester), 1);
    expect(shown.value, 1);

    await tester.drag(find.byKey(list), const Offset(0, -300));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 120));
    expect(shown.value, inExclusiveRange(0, 1));
    expect(titleBandShown(tester), shown.value);
    await tester.pumpAndSettle();
    expect(titleBandShown(tester), 0);
    expect(shown.value, 0);

    await tester.drag(find.byKey(list), const Offset(0, 40));
    await tester.pumpAndSettle();
    expect(titleBandShown(tester), 1);
    expect(shown.value, 1);
  });

  testWidgets('a page that keeps its bar tells so as it scrolls on', (
    tester,
  ) async {
    cover(tester);
    await pumpPage(tester, hidesOnScroll: false);

    await tester.drag(find.byKey(list), const Offset(0, -300));
    await tester.pumpAndSettle();
    expect(titleBandShown(tester), 1);
    expect(shown.value, 1);
  });

  testWidgets('on an iPhone the bar stays, and so does what follows it', (
    tester,
  ) async {
    phone(tester);
    await pumpPage(tester);

    await tester.drag(find.byKey(list), const Offset(0, -300));
    await tester.pumpAndSettle();
    expect(shown.value, 1);
  });

  testWidgets('with reduced motion the title band is gone and back at once', (
    tester,
  ) async {
    cover(tester);
    await pumpPage(tester, disableAnimations: true);

    await tester.drag(find.byKey(list), const Offset(0, -300));
    await tester.pump();
    expect(shown.value, 0);

    await tester.drag(find.byKey(list), const Offset(0, 40));
    await tester.pump();
    expect(shown.value, 1);
  });

  testWidgets('what a page pins below its bar leaves with the title band and '
      'comes back with it', (tester) async {
    cover(tester);
    await pumpPage(
      tester,
      body: AdaptiveSafeAreaBar(
        bar: const SizedBox(key: pinned, height: 44, child: Text('Search')),
        child: rows(),
      ),
    );
    double pinnedOpacity() => tester
        .widgetList<Opacity>(
          find.ancestor(of: find.byKey(pinned), matching: find.byType(Opacity)),
        )
        .fold(1, (opacity, widget) => opacity * widget.opacity);
    expect(tester.getTopLeft(find.byKey(pinned)).dy, kDuoTitleBandHeight);
    expect(pinnedOpacity(), 1);

    await tester.drag(find.byKey(list), const Offset(0, -300));
    await tester.pumpAndSettle();
    expect(pinnedOpacity(), 0);
    expect(tester.getBottomLeft(find.byKey(pinned)).dy, kDuoTitleBandHeight);

    await tester.drag(find.byKey(list), const Offset(0, 40));
    await tester.pumpAndSettle();
    expect(pinnedOpacity(), 1);
    expect(tester.getTopLeft(find.byKey(pinned)).dy, kDuoTitleBandHeight);
  });

  test('what is pinned in a scroll view sits below the bar while it is there '
      'and above the top edge once it is gone', () {
    expect(AdaptiveTopBarVisibility.pinnedTop(1, top: 70, extent: 40), 70);
    expect(AdaptiveTopBarVisibility.pinnedTop(0.5, top: 70, extent: 40), 15);
    expect(AdaptiveTopBarVisibility.pinnedTop(0, top: 70, extent: 40), -40);
  });
}
