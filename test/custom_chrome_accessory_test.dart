import 'package:adaptive_platform_ui/adaptive_platform_ui.dart';
import 'package:adaptive_platform_ui/src/toolbar/hosted_tab_bar.dart' show kFloatingAccessoryMaxWidth;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:foldable/foldable.dart';

import 'custom_chrome_fixture.dart';

const phone = Size(390, 844);
const innerLandscape = Size(951, 669);
const duoCamera = ReservedRegion(kind: ReservedRegionKind.occlusion, bounds: Rect.fromLTRB(867, 0, 951, 120), isActive: true);
const tablet = Size(1180, 820);

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
  }

  Finder accessory() => find.byKey(const ValueKey('accessory'));

  testWidgets('along the bottom it sits on the tab bar, and the pages keep clear of both', (tester) async {
    window(tester, phone, const FakeViewPadding(top: 47, bottom: 34));
    addTearDown(tester.view.reset);
    final tabs = TabsFixture(debugFold: FoldableData.unsupported, accessory: const CountingAccessory());
    await tester.pumpWidget(tabs.app());
    await tester.pumpAndSettle();

    final bar = tester.getRect(find.byKey(TestChrome.tabBarKey));
    expect(tester.getRect(accessory()).bottom, bar.top);
    expect(bar.bottom, phone.height);
    expect(tabs.paddingOf('Tab 0').bottom, TestChrome.tabBarHeight + 50);
    expect(tabs.insetOf('Tab 0'), TestChrome.tabBarHeight + 50);
  });

  testWidgets('it leaves with the tabs', (tester) async {
    window(tester, phone, const FakeViewPadding(top: 47, bottom: 34));
    addTearDown(tester.view.reset);
    final tabs = TabsFixture(debugFold: FoldableData.unsupported, accessory: const CountingAccessory(), hidesWhenPushed: true);
    await tester.pumpWidget(tabs.app());
    await tester.pumpAndSettle();

    tabs.push(0, 'Detail');
    await tester.pumpAndSettle();

    expect(accessory(), findsNothing);
    expect(tabs.paddingOf('Detail').bottom, 34);
  });

  testWidgets('beside the iPhone Duo\'s vertical bar it floats at the bottom of the content', (tester) async {
    window(tester, innerLandscape, const FakeViewPadding(right: 84, bottom: 34));
    addTearDown(tester.view.reset);
    final tabs = TabsFixture(debugFold: duo(regions: [duoCamera]), accessory: const CountingAccessory(), chrome: TestChrome.withFrames);
    await tester.pumpWidget(tabs.app());
    await tester.pumpAndSettle();

    final rect = tester.getRect(accessory());
    expect(rect.bottom, innerLandscape.height - 34);
    expect(rect.left, 12);
    expect(rect.right, innerLandscape.width - (84 + kDuoVerticalBarBezelInset) - 12);
    expect(tabs.paddingOf('Tab 0').bottom, 50 + 34);
    expect(TestChrome.lastAccessorySpec!.placement, AdaptiveChromePlacement.vertical);
    expect(TestChrome.lastAccessorySpec!.compact, isTrue);
  });

  testWidgets('without a frame it floats centred in the content, at most kFloatingAccessoryMaxWidth wide', (tester) async {
    window(tester, innerLandscape, const FakeViewPadding(right: 84, bottom: 34));
    addTearDown(tester.view.reset);
    final tabs = TabsFixture(debugFold: duo(regions: [duoCamera]), accessory: const CountingAccessory());
    await tester.pumpWidget(tabs.app());
    await tester.pumpAndSettle();

    final rect = tester.getRect(accessory());
    final contentRight = innerLandscape.width - (84 + kDuoVerticalBarBezelInset) - 12;
    expect(rect.width, lessThanOrEqualTo(kFloatingAccessoryMaxWidth));
    expect(rect.center.dx, closeTo((12 + contentRight) / 2, 0.5));
    expect(rect.bottom, innerLandscape.height - 34);
    expect(tabs.paddingOf('Tab 0').bottom, 50 + 34);
  });

  testWidgets('in a sidebar it is handed to the sidebar, framed, and the pages keep nothing at the bottom', (tester) async {
    PlatformInfo.debugPlatformOverride = TargetPlatform.android;
    window(tester, tablet, const FakeViewPadding(top: 24, bottom: 20));
    addTearDown(tester.view.reset);
    final tabs = TabsFixture(accessory: const CountingAccessory(), chrome: TestChrome.withFrames);
    await tester.pumpWidget(tabs.app());
    await tester.pumpAndSettle();

    expect(find.descendant(of: find.byKey(TestChrome.sidebarKey), matching: accessory()), findsOneWidget);
    expect(TestChrome.lastSidebarSpec!.accessory, isNotNull);
    expect(TestChrome.lastAccessorySpec!.placement, AdaptiveChromePlacement.sidebar);
    expect(TestChrome.lastAccessorySpec!.compact, isFalse);
    expect(tabs.paddingOf('Tab 0').bottom, 20);
  });

  testWidgets('it keeps its state through every placement: the top strip, the vertical bar, a sidebar, the bottom', (tester) async {
    window(tester, const Size(669, 951), const FakeViewPadding(top: 84, bottom: 20));
    addTearDown(tester.view.reset);
    final tabs = TabsFixture(debugFold: duo(regions: [duoCamera]), accessory: const CountingAccessory(), chrome: TestChrome.withFramesInTopStrip);
    await tester.pumpWidget(tabs.app());
    await tester.pumpAndSettle();
    expect(TestChrome.lastAccessorySpec!.placement, AdaptiveChromePlacement.topStrip);
    await tester.tap(accessory());
    await tester.tap(accessory());
    await tester.pump();
    final state = tester.state<CountingAccessoryState>(find.byType(CountingAccessory));
    expect(state.count, 2);

    final steps = <(Size, FakeViewPadding, AdaptiveChromePlacement)>[
      (innerLandscape, const FakeViewPadding(right: 84, bottom: 34), AdaptiveChromePlacement.vertical),
      (tablet, const FakeViewPadding(bottom: 20), AdaptiveChromePlacement.sidebar),
      (phone, const FakeViewPadding(bottom: 34), AdaptiveChromePlacement.bottom),
      (const Size(669, 951), const FakeViewPadding(top: 84, bottom: 20), AdaptiveChromePlacement.topStrip),
    ];
    for (final (size, padding, placement) in steps) {
      window(tester, size, padding);
      await tester.pumpAndSettle();
      expect(TestChrome.lastAccessorySpec!.placement, placement);
      expect(identical(tester.state<CountingAccessoryState>(find.byType(CountingAccessory)), state), isTrue, reason: '$placement');
    }
    expect(find.text('accessory 2'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('one with nothing to show for now keeps no room at the bottom beside the vertical bar, not even its margin', (tester) async {
    window(tester, innerLandscape, const FakeViewPadding(right: 84, bottom: 34));
    addTearDown(tester.view.reset);
    final tabs = TabsFixture(debugFold: duo(regions: [duoCamera]), accessory: const CountingAccessory(height: 0), chrome: TestChrome.withFrames);
    await tester.pumpWidget(tabs.app());
    await tester.pumpAndSettle();

    expect(tabs.insetOf('Tab 0'), 0);
    expect(tabs.paddingOf('Tab 0').bottom, 34);
  });

  testWidgets('without one, a vertical bar pose keeps no room at the bottom', (tester) async {
    window(tester, phone, const FakeViewPadding(top: 47, bottom: 34));
    addTearDown(tester.view.reset);
    final tabs = TabsFixture(debugFold: duo(regions: [duoCamera]));
    await tester.pumpWidget(tabs.app());
    await tester.pumpAndSettle();

    window(tester, innerLandscape, const FakeViewPadding(right: 84, bottom: 34));
    await tester.pumpAndSettle();

    expect(tabs.paddingOf('Tab 0').bottom, 34);
    expect(tabs.insetOf('Tab 0'), 0);
  });
}
