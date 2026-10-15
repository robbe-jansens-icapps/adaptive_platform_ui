import 'dart:ui' show DisplayFeature, DisplayFeatureState, DisplayFeatureType;

import 'package:adaptive_platform_ui/adaptive_platform_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:foldable/foldable.dart';

import 'custom_chrome_fixture.dart';

const content = ValueKey('popover content');

void main() {
  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform_views, (_) async => null);
  });

  tearDown(() {
    PlatformInfo.debugPlatformOverride = null;
    PlatformInfo.debugIOSVersionOverride = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform_views, null);
  });

  void window(WidgetTester tester, Size size) {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  /// A button at [at], which opens a 200 by 120 popover.
  Future<void> pumpButton(WidgetTester tester, Offset at) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Stack(
            children: [
              Positioned(
                left: at.dx,
                top: at.dy,
                child: Builder(
                  builder: (context) => GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => AdaptivePopover.show<void>(
                      anchor: context,
                      builder: (_) => const SizedBox(key: content, width: 200, height: 120),
                    ),
                    child: const SizedBox(key: ValueKey('button'), width: 44, height: 44),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<Rect> open(WidgetTester tester) async {
    await tester.tap(find.byKey(const ValueKey('button')));
    await tester.pumpAndSettle();
    return tester.getRect(find.byKey(content));
  }

  testWidgets('opens below its control, centred on it', (tester) async {
    window(tester, const Size(1000, 800));
    await pumpButton(tester, const Offset(400, 100));

    final rect = await open(tester);
    expect(rect.top, 144 + AdaptivePopover.gap);
    expect(rect.center.dx, 422);
  });

  testWidgets('opens above a control near the bottom, and stays on screen at the edge', (tester) async {
    window(tester, const Size(1000, 800));
    await pumpButton(tester, const Offset(0, 700));

    final rect = await open(tester);
    expect(rect.bottom, 700 - AdaptivePopover.gap);
    expect(rect.left, AdaptivePopover.gap);
  });

  testWidgets('too tall for above or below its control, it opens beside it, on the side with more room', (tester) async {
    window(tester, const Size(1000, 280));
    await pumpButton(tester, const Offset(800, 120));

    final rect = await open(tester);
    expect(rect.right, 800 - AdaptivePopover.gap);
    expect(rect.center.dy, 142);
  });

  testWidgets('its content keeps none of the window\'s padding, as it sits inside the safe area', (tester) async {
    window(tester, const Size(1000, 800));
    tester.view.padding = const FakeViewPadding(top: 24, bottom: 20, left: 10, right: 10);
    EdgeInsets? padding;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => AdaptivePopover.show<void>(
              anchor: context,
              anchorRect: const Rect.fromLTWH(400, 100, 44, 44),
              builder: (context) {
                padding = MediaQuery.paddingOf(context);
                return const SizedBox(width: 200, height: 120);
              },
            ),
            child: const SizedBox.expand(key: ValueKey('button')),
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('button')));
    await tester.pumpAndSettle();
    expect(padding, EdgeInsets.zero);
  });

  testWidgets('opens as a sheet from the bottom on a compact window', (tester) async {
    window(tester, const Size(390, 844));
    await pumpButton(tester, const Offset(100, 100));

    await open(tester);
    expect(find.byType(BottomSheet), findsOneWidget);
    expect(tester.getRect(find.byKey(content)).bottom, 844);
  });

  testWidgets('keeps to the side of an Android hinge that holds its control', (tester) async {
    window(tester, const Size(1000, 800));
    tester.view.displayFeatures = const [
      DisplayFeature(bounds: Rect.fromLTWH(495, 0, 10, 800), type: DisplayFeatureType.hinge, state: DisplayFeatureState.unknown),
    ];
    await pumpButton(tester, const Offset(520, 100));

    final rect = await open(tester);
    expect(rect.left, greaterThanOrEqualTo(505 + AdaptivePopover.gap));
  });

  testWidgets('its surface grows out of its control and shrinks back into it, and the content only takes taps once open', (tester) async {
    window(tester, const Size(1000, 800));
    var taps = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Stack(
            children: [
              Positioned(
                left: 400,
                top: 100,
                child: Builder(
                  builder: (context) => GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => AdaptivePopover.show<void>(
                      anchor: context,
                      builder: (_) => GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () => taps++,
                        child: const SizedBox(key: content, width: 200, height: 120),
                      ),
                    ),
                    child: const SizedBox(key: ValueKey('button'), width: 44, height: 44),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    final button = tester.getRect(find.byKey(const ValueKey('button')));
    await tester.tap(find.byKey(const ValueKey('button')), warnIfMissed: false);
    await tester.pump();
    expect(tester.getRect(find.byType(AdaptiveGlass)), button);

    await tester.pump(const Duration(milliseconds: 100));
    await tester.tapAt(tester.getCenter(find.byKey(content)));
    expect(taps, 0);
    expect(find.byKey(content), findsOneWidget);

    await tester.pumpAndSettle();
    final open = tester.getRect(find.byKey(content));
    expect(tester.getRect(find.byType(AdaptiveGlass)), open);
    await tester.tapAt(open.center);
    expect(taps, 1);

    Navigator.of(tester.element(find.byKey(content))).pop();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(tester.getRect(find.byType(AdaptiveGlass)).width, lessThan(open.width));
    await tester.pumpAndSettle();
    expect(find.byType(AdaptiveGlass), findsNothing);
  });

  testWidgets('over its control, it grows out of a bar along the bottom and covers it, on a compact window too', (tester) async {
    window(tester, const Size(390, 844));
    tester.view.padding = const FakeViewPadding(top: 47, bottom: 34);
    tester.view.viewPadding = const FakeViewPadding(top: 47, bottom: 34);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Stack(
            children: [
              Positioned(
                left: 16,
                right: 16,
                bottom: 20,
                height: 64,
                child: Builder(
                  builder: (context) => GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => AdaptivePopover.show<void>(
                      anchor: context,
                      placement: AdaptivePopoverPlacement.over,
                      maxSize: const Size(358, 600),
                      builder: (_) => const SizedBox(key: content, width: 358, height: 400),
                    ),
                    child: const SizedBox.expand(key: ValueKey('bar')),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    final bar = tester.getRect(find.byKey(const ValueKey('bar')));
    await tester.tap(find.byKey(const ValueKey('bar')));
    await tester.pump();
    expect(tester.getRect(find.byType(AdaptiveGlass)), bar);
    await tester.pump(const Duration(milliseconds: 60));
    final growing = tester.getRect(find.byType(AdaptiveGlass));
    expect(growing.bottom, closeTo(bar.bottom, 1));
    expect(growing.height, greaterThan(bar.height));

    await tester.pumpAndSettle();
    expect(find.byType(BottomSheet), findsNothing);
    final rect = tester.getRect(find.byKey(content));
    expect(rect.bottom, bar.bottom);
    expect(rect.center.dx, bar.center.dx);
    expect(rect.height, 400);
  });

  testWidgets('over a control in the iPhone Duo\'s vertical bar, it grows beside the bar, from the control\'s bottom', (tester) async {
    PlatformInfo.debugPlatformOverride = TargetPlatform.iOS;
    PlatformInfo.debugIOSVersionOverride = 26;
    window(tester, const Size(466, 678));
    tester.view.padding = const FakeViewPadding(right: 84);
    tester.view.viewPadding = const FakeViewPadding(right: 84);
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => AdaptiveToolbarHost(debugFold: duo(), child: child!),
        home: Stack(
          children: [
            Positioned(
              right: 18,
              bottom: 24,
              width: 48,
              height: 260,
              child: Builder(
                builder: (context) => GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => AdaptivePopover.show<void>(
                    anchor: context,
                    placement: AdaptivePopoverPlacement.over,
                    builder: (_) => const SizedBox(key: content, width: 300, height: 400),
                  ),
                  child: const SizedBox.expand(key: ValueKey('tabs')),
                ),
              ),
            ),
          ],
        ),
      ),
    );
    final tabs = tester.getRect(find.byKey(const ValueKey('tabs')));
    await tester.tap(find.byKey(const ValueKey('tabs')));
    await tester.pumpAndSettle();

    final rect = tester.getRect(find.byKey(content));
    expect(rect.bottom, tabs.bottom);
    expect(rect.right, lessThanOrEqualTo(466 - 84 - kDuoVerticalBarBezelInset - AdaptivePopover.gap));
  });

  testWidgets('showMenu resolves to the item picked; a tap outside closes it with nothing', (tester) async {
    window(tester, const Size(1000, 800));
    int? picked = -1;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: Builder(
              builder: (context) => TextButton(
                onPressed: () async => picked = await AdaptivePopover.showMenu(
                  anchor: context,
                  items: const [
                    AdaptivePopupMenuItem<void>(label: 'Newest'),
                    AdaptivePopupMenuDivider(),
                    AdaptivePopupMenuItem<void>(label: 'Gone', enabled: false),
                    AdaptivePopupMenuItem<void>(label: 'Oldest', selected: true),
                  ],
                ),
                child: const Text('Sort'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Sort'));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.check), findsOneWidget);
    await tester.tap(find.text('Gone'));
    await tester.pumpAndSettle();
    expect(find.text('Gone'), findsOneWidget);
    await tester.tap(find.text('Oldest'));
    await tester.pumpAndSettle();
    expect(picked, 3);

    await tester.tap(find.text('Sort'));
    await tester.pumpAndSettle();
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();
    expect(picked, isNull);
  });

  testWidgets('a menu of an action in the app\'s own bar opens as a popover next to it', (tester) async {
    PlatformInfo.debugPlatformOverride = TargetPlatform.android;
    window(tester, const Size(1000, 800));
    final selected = <int>[];
    final tabs = TabsFixture(
      actions: [
        AdaptiveAppBarAction(
          title: 'Sort',
          menuItems: const [AdaptivePopupMenuItem<void>(label: 'Newest'), AdaptivePopupMenuItem<void>(label: 'Oldest')],
          onMenuItemSelected: (index, _) => selected.add(index),
        ),
      ],
    );
    await tester.pumpWidget(tabs.app());
    await tester.pumpAndSettle();

    await tester.tap(find.text('action:Sort'));
    await tester.pumpAndSettle();
    expect(find.byType(BottomSheet), findsNothing);
    final action = tester.getRect(find.text('action:Sort'));
    expect(tester.getRect(find.text('Oldest')).top, greaterThan(action.bottom));
    await tester.tap(find.text('Oldest'));
    await tester.pumpAndSettle();
    expect(selected, [1]);
  });

  testWidgets('a page in a popover keeps its bar clear of the popover\'s rounded top, its content below the bar', (tester) async {
    PlatformInfo.debugPlatformOverride = TargetPlatform.android;
    window(tester, const Size(1000, 800));
    tester.view.padding = const FakeViewPadding(top: 24);
    final tabs = TabsFixture();
    await tester.pumpWidget(tabs.app());
    await tester.pumpAndSettle();

    AdaptivePopover.show<void>(
      anchor: tabs.navigators[0].currentContext!,
      anchorRect: const Rect.fromLTWH(400, 100, 44, 44),
      builder: (_) => SizedBox(key: content, width: 300, height: 300, child: tabs.pageWidget('Pop')),
    );
    await tester.pumpAndSettle();

    final surface = tester.getRect(find.byKey(content));
    final title = tester.getRect(find.text('title:Pop'));
    expect(title.center.dy - surface.top, AdaptivePopover.barInset + TestChrome.chrome.metrics.toolbarHeight / 2);
    expect(tabs.paddingOf('Pop').top, AdaptivePopover.barInset + TestChrome.chrome.metrics.toolbarHeight);
  });

  testWidgets('a page\'s back button in a popover sits in its corner, as far from the side as from the top', (tester) async {
    PlatformInfo.debugPlatformOverride = TargetPlatform.android;
    window(tester, const Size(1000, 800));
    final tabs = TabsFixture();
    await tester.pumpWidget(tabs.app());
    await tester.pumpAndSettle();

    AdaptivePopover.show<void>(
      anchor: tabs.navigators[0].currentContext!,
      anchorRect: const Rect.fromLTWH(400, 100, 44, 44),
      builder: (_) => SizedBox(key: content, width: 300, height: 300, child: tabs.pageWidget('Pop')),
    );
    await tester.pumpAndSettle();

    final surface = tester.getRect(find.byKey(content));
    final back = tester.getRect(find.ancestor(of: find.text('back'), matching: find.byType(SizedBox)).first);
    expect(back.left - surface.left, AdaptivePopover.barInset);
    expect(back.top - surface.top, AdaptivePopover.barInset);
  });

  testWidgets('the overflow control of the iPhone Duo bar opens its menu beside the bar', (tester) async {
    PlatformInfo.debugPlatformOverride = TargetPlatform.iOS;
    PlatformInfo.debugIOSVersionOverride = 26;
    window(tester, const Size(951, 669));
    tester.view.padding = const FakeViewPadding(right: 84, bottom: 34);
    tester.view.viewPadding = const FakeViewPadding(right: 84, bottom: 34);
    final pressed = <String>[];
    final tabs = TabsFixture(
      debugFold: duo(regions: const [ReservedRegion(kind: ReservedRegionKind.occlusion, bounds: Rect.fromLTRB(867, 0, 951, 300), isActive: true)]),
      actions: [for (var i = 0; i < 8; i++) AdaptiveAppBarAction(title: 'A$i', onPressed: () => pressed.add('A$i'))],
    );
    await tester.pumpWidget(tabs.app());
    await tester.pumpAndSettle();

    await tester.tap(find.text('more'));
    await tester.pumpAndSettle();
    final item = tester.getRect(find.text('A7'));
    expect(item.right, lessThanOrEqualTo(951 - 84 - kDuoVerticalBarBezelInset - AdaptivePopover.gap));
    await tester.tap(find.text('A7'));
    await tester.pumpAndSettle();
    expect(pressed, ['A7']);
  });

  testWidgets('the app\'s surface gets the chromeData the popover was opened with', (tester) async {
    PlatformInfo.debugPlatformOverride = TargetPlatform.android;
    window(tester, const Size(1000, 800));
    Object? seen;
    const chrome = AdaptiveChrome(
      tabBarBuilder: _none,
      titleBuilder: _noneTitle,
      backButtonBuilder: _noneBack,
      actionsBuilder: _noneActions,
      popoverBuilder: _surface,
    );
    _seen = (data) => seen = data;
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => AdaptiveToolbarHost(chrome: chrome, child: child!),
        home: Center(
          child: Builder(
            builder: (context) => TextButton(
              onPressed: () => AdaptivePopover.show<void>(anchor: context, chromeData: 'dark', builder: (_) => const Text('inside')),
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    expect(find.text('inside'), findsOneWidget);
    expect(seen, 'dark');
  });
}

void Function(Object?) _seen = (_) {};
Widget _none(BuildContext context, AdaptiveTabBarSpec spec) => const SizedBox();
Widget _noneTitle(BuildContext context, AdaptiveTitleSpec spec) => const SizedBox();
Widget _noneBack(BuildContext context, AdaptiveBackButtonSpec spec) => const SizedBox();
Widget _noneActions(BuildContext context, AdaptiveActionsSpec spec) => const SizedBox();
Widget _surface(BuildContext context, AdaptivePopoverSpec spec, Widget content) {
  _seen(spec.data);
  return content;
}
