import 'dart:math' as math;

import 'package:adaptive_platform_ui/adaptive_platform_ui.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// The tab accessory with the Material navigation bar, as an Android phone
/// shows it: in a band on the bar's surface, the pages running on under it.
void main() {
  const size = Size(412, 915);

  final accessory = find.byKey(const ValueKey('accessory'));
  final card = find.byKey(const ValueKey('card'));
  final navigationBar = find.byType(NavigationBar);

  /// The band: the surface under the accessory.
  Finder band() => find.ancestor(
    of: accessory,
    matching: find.byWidgetPredicate(
      (widget) =>
          widget is DecoratedBox && widget.decoration is ShapeDecoration,
    ),
  );

  Color bandColor(WidgetTester tester) =>
      (tester.widget<DecoratedBox>(band().first).decoration as ShapeDecoration)
          .color!;

  /// The opacity [finder] is drawn at: every fade around it.
  double opacityOf(WidgetTester tester, Finder finder) {
    var opacity = 1.0;
    for (final fade in tester.widgetList<FadeTransition>(
      find.ancestor(of: finder, matching: find.byType(FadeTransition)),
    )) {
      opacity *= fade.opacity.value;
    }
    return opacity;
  }

  /// The radius of the navigation bar's top corners.
  double barCorner(WidgetTester tester) {
    final clip = tester.widget<ClipRRect>(
      find.ancestor(of: navigationBar, matching: find.byType(ClipRRect)).first,
    );
    return (clip.borderRadius as BorderRadius).topLeft.x;
  }

  /// The colour that shows around the navigation bar's round corners.
  Color behindBar(WidgetTester tester) => tester
      .widget<ColoredBox>(
        find
            .descendant(
              of: find.byType(MaterialTabAccessoryBar),
              matching: find.byType(ColoredBox),
            )
            .first,
      )
      .color;

  bool hits(WidgetTester tester, Finder finder, Offset at) {
    final box = tester.renderObject(finder);
    return tester.hitTestOnBinding(at).path.any((e) => e.target == box);
  }

  late double padding;
  late double accessoryBand;
  late int taps;

  setUp(() => PlatformInfo.debugPlatformOverride = TargetPlatform.android);
  tearDown(() => PlatformInfo.debugPlatformOverride = null);

  Future<AdaptiveSheetController> pumpTabs(
    WidgetTester tester, {
    Widget? accessoryWidget,
    bool sheet = false,
    ValueListenable<bool>? opens,
    bool settle = true,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    tester.view.padding = const FakeViewPadding(top: 24, bottom: 24);
    tester.view.viewPadding = const FakeViewPadding(top: 24, bottom: 24);
    addTearDown(tester.view.reset);
    taps = 0;
    final controller = AdaptiveSheetController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => AdaptiveToolbarHost(child: child!),
        home: AdaptiveScaffold(
          bottomNavigationBar: AdaptiveBottomNavigationBar(
            items: const [
              AdaptiveNavigationDestination(icon: Icons.map, label: 'Map'),
              AdaptiveNavigationDestination(
                icon: Icons.person,
                label: 'Account',
              ),
            ],
            selectedIndex: 0,
            onTap: (_) {},
            accessory:
                accessoryWidget ??
                GestureDetector(
                  onTap: () => taps++,
                  child: const SizedBox(
                    key: ValueKey('accessory'),
                    height: 48,
                    child: Text('ride'),
                  ),
                ),
            accessoryLayout: AdaptiveTabAccessoryLayout.onSheet,
          ),
          body: Builder(
            builder: (context) {
              padding = MediaQuery.paddingOf(context).bottom;
              accessoryBand = AdaptiveBottomBarInset.accessoryOf(context);
              return Stack(
                children: [
                  const SizedBox.expand(),
                  if (sheet)
                    Positioned.fill(
                      child: ValueListenableBuilder<bool>(
                        valueListenable: opens ?? ValueNotifier<bool>(true),
                        builder: (context, opens, _) => AdaptiveSheet(
                          controller: controller,
                          opensFromAccessory: opens,
                          // The band holds the accessory apart already.
                          liftsAccessory: !opens,
                          detents: opens
                              ? const [
                                  AdaptiveSheetDetent.collapsed,
                                  AdaptiveSheetDetent.fitContent,
                                ]
                              : const [AdaptiveSheetDetent.fitContent],
                          initialDetent: opens
                              ? AdaptiveSheetDetent.collapsed
                              : AdaptiveSheetDetent.fitContent,
                          showsGrabber: false,
                          scrollable: false,
                          padding: EdgeInsets.zero,
                          child: const ColoredBox(
                            key: ValueKey('card'),
                            color: Color(0x00000000),
                            child: SizedBox(
                              width: double.infinity,
                              height: 300,
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
        ),
      ),
    );
    if (settle) await tester.pumpAndSettle();
    return controller;
  }

  testWidgets('the accessory sits on a card in a band just above the '
      'navigation bar\'s destinations, in its middle, which the pages run on '
      'under and keep clear of', (tester) async {
    await pumpTabs(tester);

    final bar = tester.getRect(navigationBar);
    final rect = tester.getRect(accessory);
    expect(rect.bottom, bar.top - MaterialTabAccessory.bottomPadding);
    expect(rect.left, MaterialTabAccessory.sidePadding);
    expect(rect.right, size.width - MaterialTabAccessory.sidePadding);
    final context = tester.element(navigationBar);
    expect(
      bandColor(tester),
      Theme.of(context).colorScheme.surfaceContainerLowest,
    );
    expect(tester.getRect(band().first).top, rect.top - 12);
    expect(tester.getRect(band().first).bottom, bar.top);
    // Told it sits on the band, which reaches the window's sides.
    final surface = AdaptiveAccessoryScope.surfaceOf(
      tester.element(accessory),
    )!;
    expect(surface, MaterialTabAccessory.surface);
    final outline = surface.outline(rect.size).getBounds().shift(rect.topLeft);
    expect(outline.left, 0);
    expect(outline.right, size.width);
    expect(outline.top, tester.getRect(band().first).top);
    expect(
      accessoryBand,
      48 + MaterialTabAccessory.topPadding + MaterialTabAccessory.bottomPadding,
    );
    expect(
      padding,
      48 + MaterialTabAccessory.topPadding + MaterialTabAccessory.bottomPadding,
    );

    await tester.tap(accessory);
    expect(taps, 1);
  });

  testWidgets('the navigation bar rounds its top corners in front of the '
      'card as it comes, and squares them again as it goes', (tester) async {
    final shown = ValueNotifier<bool>(true);
    addTearDown(shown.dispose);
    await pumpTabs(
      tester,
      settle: false,
      accessoryWidget: ValueListenableBuilder<bool>(
        valueListenable: shown,
        builder: (context, shown, _) =>
            SizedBox(key: const ValueKey('accessory'), height: shown ? 48 : 0),
      ),
    );
    await tester.pump();
    expect(barCorner(tester), 0);
    await tester.pump(const Duration(milliseconds: 150));
    expect(
      barCorner(tester),
      inExclusiveRange(0, MaterialTabAccessory.cornerRadius),
    );
    await tester.pumpAndSettle();
    expect(barCorner(tester), MaterialTabAccessory.cornerRadius);
    expect(
      behindBar(tester),
      Theme.of(
        tester.element(navigationBar),
      ).colorScheme.surfaceContainerLowest,
    );

    shown.value = false;
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 150));
    expect(
      barCorner(tester),
      inExclusiveRange(0, MaterialTabAccessory.cornerRadius),
    );
    await tester.pumpAndSettle();
    expect(barCorner(tester), 0);
  });

  testWidgets('a page\'s sheet up along the bar rounds its corners too, '
      'without an accessory', (tester) async {
    await pumpTabs(
      tester,
      accessoryWidget: const SizedBox.shrink(key: ValueKey('accessory')),
    );
    expect(barCorner(tester), 0);

    await pumpTabs(
      tester,
      sheet: true,
      opens: ValueNotifier<bool>(false),
      accessoryWidget: const SizedBox.shrink(key: ValueKey('accessory')),
    );
    expect(barCorner(tester), MaterialTabAccessory.cornerRadius);
    expect(
      behindBar(tester),
      Theme.of(tester.element(navigationBar)).colorScheme.surfaceContainerLow,
    );
  });

  testWidgets('the pages get the band\'s room in the frame after the '
      'accessory is first laid out', (tester) async {
    await pumpTabs(tester, settle: false);
    expect(padding, 0);

    await tester.pump();
    expect(
      padding,
      48 + MaterialTabAccessory.topPadding + MaterialTabAccessory.bottomPadding,
    );
    expect(
      accessoryBand,
      48 + MaterialTabAccessory.topPadding + MaterialTabAccessory.bottomPadding,
    );
  });

  testWidgets('one with nothing to show takes no band', (tester) async {
    await pumpTabs(
      tester,
      accessoryWidget: const SizedBox.shrink(key: ValueKey('accessory')),
    );

    expect(padding, 0);
    expect(accessoryBand, 0);
    expect(bandColor(tester).a, 0);
  });

  testWidgets('a page\'s sheet that opens from the accessory lies behind the '
      'bar while collapsed, comes up into the accessory\'s place, which makes '
      'way with the band, and ends where the destinations begin', (
    tester,
  ) async {
    final controller = await pumpTabs(tester, sheet: true);
    final bar = tester.getRect(navigationBar);
    final at = tester.getCenter(accessory);
    // Behind the band, all of it: the sheet starts where the band does.
    expect(
      tester.getRect(card).top,
      closeTo(
        bar.top -
            48 -
            MaterialTabAccessory.topPadding -
            MaterialTabAccessory.bottomPadding,
        0.5,
      ),
    );
    expect(opacityOf(tester, accessory), 1);
    expect(barCorner(tester), MaterialTabAccessory.cornerRadius);

    controller.animateTo(AdaptiveSheetDetent.fitContent);
    await tester.pumpAndSettle();
    expect(tester.getRect(card).bottom, closeTo(bar.top, 0.5));
    expect(opacityOf(tester, accessory), 0);
    expect(bandColor(tester).a, closeTo(0, 0.001));
    // Up along the bar, the sheet keeps its corners round.
    expect(barCorner(tester), MaterialTabAccessory.cornerRadius);
    expect(
      behindBar(tester),
      Theme.of(tester.element(navigationBar)).colorScheme.surfaceContainerLow,
    );
    expect(hits(tester, card, at), isTrue);
    // The pages keep their room.
    expect(
      padding,
      48 + MaterialTabAccessory.topPadding + MaterialTabAccessory.bottomPadding,
    );
  });

  testWidgets('a drag up on the accessory pulls the sheet up', (tester) async {
    await pumpTabs(tester, sheet: true);
    final bar = tester.getRect(navigationBar);

    await tester.fling(accessory, const Offset(0, -80), 1500);
    await tester.pumpAndSettle();

    expect(tester.getRect(card).bottom, closeTo(bar.top, 0.5));
    expect(opacityOf(tester, accessory), 0);
  });

  testWidgets('a sheet with other content comes up from behind the bar and '
      'ends above the band, the accessory in sight and taking its touches', (
    tester,
  ) async {
    await pumpTabs(tester, sheet: true, opens: ValueNotifier<bool>(false));

    expect(
      tester.getRect(card).bottom,
      closeTo(tester.getRect(band().first).top, 0.5),
    );
    expect(opacityOf(tester, accessory), 1);
    expect(bandColor(tester).a, 1);
    await tester.tap(accessory);
    expect(taps, 1);
  });

  testWidgets('as other content comes up from the accessory, a station above '
      'a folded ride, the accessory and the band stay in sight all the way', (
    tester,
  ) async {
    final opens = ValueNotifier<bool>(true);
    addTearDown(opens.dispose);
    final controller = await pumpTabs(tester, sheet: true, opens: opens);

    opens.value = false;
    await tester.pump();
    controller.animateTo(AdaptiveSheetDetent.fitContent);
    var least = 1.0;
    for (var i = 0; i < 30; i++) {
      await tester.pump(const Duration(milliseconds: 16));
      least = math.min(
        least,
        math.min(opacityOf(tester, accessory), bandColor(tester).a),
      );
    }
    await tester.pumpAndSettle();
    expect(least, greaterThan(0.99));
    expect(
      tester.getRect(card).bottom,
      closeTo(tester.getRect(band().first).top, 0.5),
    );
  });

  testWidgets('the band makes way for the keyboard, which the Scaffold leaves '
      'out of its body', (tester) async {
    await pumpTabs(tester);
    expect(opacityOf(tester, accessory), 1);

    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    await tester.pumpAndSettle();
    expect(opacityOf(tester, accessory), 0);

    tester.view.resetViewInsets();
    await tester.pumpAndSettle();
    expect(opacityOf(tester, accessory), 1);
  });
}
