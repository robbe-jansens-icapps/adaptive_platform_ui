import 'package:adaptive_platform_ui/adaptive_platform_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:foldable/foldable.dart';

import 'custom_chrome_fixture.dart';

const innerPortrait = Size(669, 951);
const cluster = ReservedRegion(kind: ReservedRegionKind.occlusion, bounds: Rect.fromLTRB(549, 0, 669, 84), isActive: true);

void main() {
  setUp(() {
    PlatformInfo.debugPlatformOverride = TargetPlatform.iOS;
    PlatformInfo.debugIOSVersionOverride = 26;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform_views, (_) async => null);
  });

  tearDown(() {
    PlatformInfo.debugPlatformOverride = null;
    PlatformInfo.debugIOSVersionOverride = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform_views, null);
  });

  Future<TabsFixture> pumpPortrait(WidgetTester tester, {bool hidesWhenPushed = true}) async {
    tester.view.physicalSize = innerPortrait;
    tester.view.devicePixelRatio = 1;
    tester.view.padding = const FakeViewPadding(top: 84, bottom: 20);
    tester.view.viewPadding = const FakeViewPadding(top: 84, bottom: 20);
    addTearDown(tester.view.reset);
    final tabs = TabsFixture(debugFold: duo(regions: [cluster]), hidesWhenPushed: hidesWhenPushed);
    await tester.pumpWidget(tabs.app());
    await tester.pumpAndSettle();
    return tabs;
  }

  testWidgets('the tabs sit in the strip along the top, beside the status cluster, level with it', (tester) async {
    await pumpPortrait(tester);

    expect(TestChrome.lastTabSpec!.placement, AdaptiveChromePlacement.topStrip);
    expect(TestChrome.lastTabSpec!.axis, Axis.horizontal);
    final bar = tester.getRect(find.byKey(TestChrome.tabBarKey));
    expect(bar.center.dy, DuoTopStrip.barTop + kDuoTopStripBarHeight / 2);
    expect(bar.left, greaterThanOrEqualTo(16));
    expect(bar.right, lessThanOrEqualTo(cluster.bounds.left - 16));
  });

  testWidgets('the toolbar sits below the strip, and the pages below both, with no room kept at the bottom', (tester) async {
    final tabs = await pumpPortrait(tester);

    expect(tester.getCenter(find.text('title:Tab 0')).dy, 84 + kHostedToolbarHeight / 2);
    final padding = tabs.paddingOf('Tab 0');
    expect(padding.top, 84 + kHostedToolbarHeight);
    expect(padding.bottom, 20);
    expect(tabs.insetOf('Tab 0'), 0);
  });

  testWidgets('a page the tabs leave for has its bar in the strip, and goes back below it', (tester) async {
    final tabs = await pumpPortrait(tester);

    tabs.push(0, 'Detail');
    await tester.pumpAndSettle();

    expect(find.byKey(TestChrome.tabBarKey), findsNothing);
    expect(tester.getCenter(find.text('title:Detail')).dy, DuoTopStrip.barTop + kHostedToolbarHeight / 2);
    expect(tester.getCenter(find.text('back')).dy, DuoTopStrip.barTop + kHostedToolbarHeight / 2);
    expect(tabs.paddingOf('Detail').top, 84);

    await tester.tap(find.text('back'));
    await tester.pumpAndSettle();
    expect(find.byKey(TestChrome.tabBarKey), findsOneWidget);
    expect(tester.getCenter(find.text('title:Tab 0')).dy, 84 + kHostedToolbarHeight / 2);
  });

  testWidgets('a page that keeps the tabs keeps its bar below the strip, its back button too', (tester) async {
    final tabs = await pumpPortrait(tester, hidesWhenPushed: false);

    tabs.push(0, 'Detail');
    await tester.pumpAndSettle();

    expect(find.byKey(TestChrome.tabBarKey), findsOneWidget);
    expect(tester.getCenter(find.text('title:Detail')).dy, 84 + kHostedToolbarHeight / 2);
    expect(tester.getCenter(find.text('back')).dy, 84 + kHostedToolbarHeight / 2);
    expect(tabs.paddingOf('Detail').top, 84 + kHostedToolbarHeight);
  });

  testWidgets('without a hinge there is no strip: the tabs go along the bottom', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    tester.view.padding = const FakeViewPadding(top: 47, bottom: 34);
    tester.view.viewPadding = const FakeViewPadding(top: 47, bottom: 34);
    addTearDown(tester.view.reset);
    final tabs = TabsFixture(debugFold: FoldableData.unsupported);
    await tester.pumpWidget(tabs.app());
    await tester.pumpAndSettle();

    expect(TestChrome.lastTabSpec!.placement, AdaptiveChromePlacement.bottom);
    expect(tester.getRect(find.byKey(TestChrome.tabBarKey)).bottom, 844);
  });
}
