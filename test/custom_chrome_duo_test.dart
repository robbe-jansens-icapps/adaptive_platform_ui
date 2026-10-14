import 'package:adaptive_platform_ui/adaptive_platform_ui.dart';
import 'package:adaptive_platform_ui/src/platform/system_vertical_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:foldable/foldable.dart';

import 'custom_chrome_fixture.dart';

const innerLandscape = Size(951, 669);
const duoCamera = ReservedRegion(kind: ReservedRegionKind.occlusion, bounds: Rect.fromLTRB(867, 0, 951, 120), isActive: true);
const cover = Size(466, 678);
const coverCluster = ReservedRegion(kind: ReservedRegionKind.occlusion, bounds: Rect.fromLTRB(382, 0, 466, 170), isActive: true);
const splitPane = Size(469, 669);

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

  void window(WidgetTester tester, Size size, FakeViewPadding padding) {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    tester.view.padding = padding;
    tester.view.viewPadding = padding;
    addTearDown(tester.view.reset);
  }

  group('on the inner display held sideways', () {
    testWidgets('the app\'s tabs run down the vertical bar, the title sits in the band, level with the first control', (tester) async {
      window(tester, innerLandscape, const FakeViewPadding(right: 84, bottom: 34));
      final tabs = TabsFixture(debugFold: duo(regions: [duoCamera]));
      await tester.pumpWidget(tabs.app());
      await tester.pumpAndSettle();

      expect(TestChrome.lastTabSpec!.placement, AdaptiveChromePlacement.vertical);
      expect(TestChrome.lastTabSpec!.axis, Axis.vertical);
      final bar = tester.getRect(find.byKey(TestChrome.tabBarKey));
      expect(bar.center.dx, innerLandscape.width - 48);
      expect(bar.bottom, innerLandscape.height - kDuoBarEdgeMargin);
      expect(bar.height, IOS26GlassCapsule.tabsHeight(2));
      expect(tester.getCenter(find.text('title:Tab 0')).dy, 48);
    });

    testWidgets('pages keep out of the strip and below the title band', (tester) async {
      window(tester, innerLandscape, const FakeViewPadding(right: 84, bottom: 34));
      final tabs = TabsFixture(debugFold: duo(regions: [duoCamera]));
      await tester.pumpWidget(tabs.app());
      await tester.pumpAndSettle();

      final padding = tabs.paddingOf('Tab 0');
      expect(padding.top, kDuoTitleBandHeight);
      expect(padding.right, 0);
      expect(tabs.insetOf('Tab 0'), 0);
      expect(tester.getRect(find.byKey(const ValueKey('body Tab 0'))).right, innerLandscape.width - 84);
    });

    testWidgets('a pushed page\'s back button tops the bar, below the camera; the tabs leave', (tester) async {
      window(tester, innerLandscape, const FakeViewPadding(right: 84, bottom: 34));
      final tabs = TabsFixture(debugFold: duo(regions: [duoCamera]), hidesWhenPushed: true);
      await tester.pumpWidget(tabs.app());
      await tester.pumpAndSettle();

      tabs.push(0, 'Detail');
      await tester.pumpAndSettle();

      expect(find.byKey(TestChrome.tabBarKey), findsNothing);
      final back = tester.getCenter(find.text('back'));
      expect(back.dx, innerLandscape.width - 48);
      expect(back.dy, duoCamera.bounds.bottom + IOS26GlassCapsule.width / 2);
      expect(find.text('title:Detail'), findsOneWidget);

      await tester.tap(find.text('back'));
      await tester.pumpAndSettle();
      expect(find.text('title:Tab 0'), findsOneWidget);
      expect(find.byKey(TestChrome.tabBarKey), findsOneWidget);
    });
  });

  testWidgets('on the cover display, actions that do not fit move into one overflow control; the tabs stay', (tester) async {
    window(tester, cover, const FakeViewPadding(right: 84, bottom: 34));
    final tabs = TabsFixture(
      debugFold: duo(regions: [coverCluster]),
      actions: [for (var i = 0; i < 8; i++) AdaptiveAppBarAction(title: 'A$i', onPressed: () {})],
    );
    await tester.pumpWidget(tabs.app());
    await tester.pumpAndSettle();

    expect(find.byKey(TestChrome.tabBarKey), findsOneWidget);
    expect(find.text('more'), findsOneWidget);
    expect(find.text('action:A0'), findsOneWidget);
    expect(find.text('action:A7'), findsNothing);
    final first = tester.getRect(find.text('action:A0'));
    expect(first.top, greaterThanOrEqualTo(coverCluster.bounds.bottom));
    final more = tester.getRect(find.text('more'));
    expect(more.bottom, lessThan(tester.getRect(find.byKey(TestChrome.tabBarKey)).top));
  });

  testWidgets('in the leading Split View pane the bar is on the left, its first control 40 points down', (tester) async {
    window(tester, splitPane, const FakeViewPadding(bottom: 34));
    final tabs = TabsFixture(debugFold: duo(), debugVerticalBarEdge: SystemVerticalBarEdge.left, hidesWhenPushed: true);
    await tester.pumpWidget(tabs.app());
    await tester.pumpAndSettle();

    tabs.push(0, 'Detail');
    await tester.pumpAndSettle();

    final back = tester.getCenter(find.text('back'));
    expect(back.dx, 48);
    expect(back.dy, kDuoBarOnlyTopMargin + IOS26GlassCapsule.width / 2);
    expect(tester.getRect(find.byKey(const ValueKey('body Detail'))).left, kDuoVerticalBarWidth);
    expect(tabs.paddingOf('Detail').left, 0);
  });

  testWidgets('rotating in steps, as a device reports it, keeps the pages and their state', (tester) async {
    window(tester, innerLandscape, const FakeViewPadding(right: 84, bottom: 34));
    final tabs = TabsFixture(debugFold: duo(regions: [duoCamera]), hidesWhenPushed: true);
    await tester.pumpWidget(tabs.app());
    await tester.pumpAndSettle();
    tabs.push(0, 'Detail');
    await tester.pumpAndSettle();
    final navigator = tabs.navigators[0].currentState;

    tester.view.physicalSize = const Size(669, 951);
    await tester.pump();
    tester.view.padding = const FakeViewPadding(top: 84, bottom: 20);
    tester.view.viewPadding = const FakeViewPadding(top: 84, bottom: 20);
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(identical(tabs.navigators[0].currentState, navigator), isTrue);
    expect(find.text('title:Detail'), findsOneWidget);

    tester.view.padding = const FakeViewPadding(right: 84, bottom: 34);
    tester.view.viewPadding = const FakeViewPadding(right: 84, bottom: 34);
    await tester.pump();
    tester.view.physicalSize = innerLandscape;
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(identical(tabs.navigators[0].currentState, navigator), isTrue);
    expect(tester.getCenter(find.text('back')).dx, innerLandscape.width - 48);
  });
}
