import 'package:adaptive_platform_ui/adaptive_platform_ui.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// A sheet that holds an accessory of its own at its bottom
/// (`AdaptiveSheet.accessory`), where no tab bar along the bottom holds the
/// tab accessory on it: a ride's row on the map's sheet in the iPhone Duo's
/// vertical bar pose, floating 16 points from the window's sides and bottom.
void main() {
  const size = Size(402, 874);
  const margin = EdgeInsets.fromLTRB(16, 0, 16, 16);

  final accessory = find.byKey(const ValueKey('accessory'));
  final card = find.byKey(const ValueKey('card'), skipOffstage: false);

  /// The sheet's glass: the one with the sheet's corners.
  final sheetGlass = find.byWidgetPredicate(
    (widget) =>
        widget is IOS26GlassSurface &&
        widget.corners == GlassSurfaceCorners.concentric,
    skipOffstage: false,
  );

  /// The capsule the accessory is lifted onto.
  final capsule = find.byWidgetPredicate(
    (widget) =>
        widget is IOS26GlassSurface &&
        widget.corners == GlassSurfaceCorners.capsule,
    skipOffstage: false,
  );

  /// The opacity [finder] is drawn at: every fade around it.
  double opacityOf(WidgetTester tester, Finder finder) {
    var opacity = 1.0;
    for (final fade in tester.widgetList<FadeTransition>(
      find.ancestor(of: finder, matching: find.byType(FadeTransition)),
    )) {
      opacity *= fade.opacity.value;
    }
    for (final fade in tester.widgetList<Opacity>(
      find.ancestor(of: finder, matching: find.byType(Opacity)),
    )) {
      opacity *= fade.opacity;
    }
    return opacity;
  }

  void expectRect(Rect actual, Rect expected) {
    expect(actual.left, closeTo(expected.left, 0.5));
    expect(actual.top, closeTo(expected.top, 0.5));
    expect(actual.right, closeTo(expected.right, 0.5));
    expect(actual.bottom, closeTo(expected.bottom, 0.5));
  }

  bool hits(WidgetTester tester, Finder finder, Offset at) {
    final box = tester.renderObject(finder);
    return tester.hitTestOnBinding(at).path.any((e) => e.target == box);
  }

  late int taps;

  Future<AdaptiveSheetController> pumpSheet(
    WidgetTester tester, {
    ValueListenable<bool>? opens,
    Size window = size,
    Widget? accessoryWidget,
    ValueChanged<EdgeInsets>? onSettled,
  }) async {
    tester.view.physicalSize = window;
    tester.view.devicePixelRatio = 1;
    tester.view.padding = const FakeViewPadding(top: 62, bottom: 34);
    tester.view.viewPadding = const FakeViewPadding(top: 62, bottom: 34);
    addTearDown(tester.view.reset);
    taps = 0;
    final controller = AdaptiveSheetController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Stack(
          children: [
            const Positioned.fill(child: ColoredBox(color: Colors.green)),
            Positioned.fill(
              // A page that builds again for every settle of its sheet.
              child: StatefulBuilder(
                builder: (context, setState) => ValueListenableBuilder<bool>(
                  valueListenable: opens ?? ValueNotifier<bool>(true),
                  builder: (context, opens, _) => AdaptiveSheet(
                    controller: controller,
                    onSettled: onSettled == null
                        ? null
                        : (obstruction) {
                            onSettled(obstruction);
                            setState(() {});
                          },
                    floatingMargin: margin,
                    opensFromAccessory: opens,
                    liftsAccessory: true,
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
                    accessory:
                        accessoryWidget ??
                        GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () => taps++,
                          child: const SizedBox(
                            key: ValueKey('accessory'),
                            height: 48,
                          ),
                        ),
                    child: const ColoredBox(
                      key: ValueKey('card'),
                      color: Color(0x00000000),
                      child: SizedBox(width: double.infinity, height: 300),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();
    return controller;
  }

  // Round with the sheet's corners: 30 less half the accessory's height.
  const inset = kAdaptiveSheetCornerRadius - 48 / 2;
  const band = 48 + 2 * inset;
  const bottom = 874.0 - 16;

  testWidgets('at its collapsed detent the sheet is the accessory\'s, round '
      'with its corners, only the accessory in sight; the accessory is told it '
      'is on the sheet, along the bottom', (tester) async {
    await pumpSheet(tester);

    final glass = tester.getRect(sheetGlass);
    expectRect(glass, const Rect.fromLTRB(16, bottom - band, 402 - 16, bottom));
    expectRect(tester.getRect(accessory), glass.deflate(inset));
    expect(opacityOf(tester, accessory), 1);
    expect(opacityOf(tester, card), 0);
    await tester.tap(accessory);
    expect(taps, 1);

    final context = tester.element(accessory);
    final spec = AdaptiveAccessoryScope.maybeOf(context)!;
    expect(spec.placement, AdaptiveChromePlacement.bottom);
    expect(spec.layout, AdaptiveTabAccessoryLayout.onSheet);
    expect(spec.room, 402 - 32 - 2 * inset);
    expect(
      AdaptiveAccessoryScope.surfaceOf(context)!.outsets,
      const EdgeInsets.all(inset),
    );
    expect(AdaptiveAccessoryScope.expansionOf(context), isNotNull);
  });

  testWidgets('opened, the content comes up into the accessory\'s place and '
      'ends at the sheet\'s bottom; the accessory makes way, its touches going '
      'to the content', (tester) async {
    final controller = await pumpSheet(tester);
    final at = tester.getCenter(accessory);

    controller.animateTo(AdaptiveSheetDetent.fitContent);
    await tester.pumpAndSettle();

    expect(tester.getRect(card).bottom, closeTo(bottom, 0.5));
    expect(opacityOf(tester, card), 1);
    expect(opacityOf(tester, accessory), 0);
    expect(hits(tester, card, at), isTrue);
  });

  testWidgets('a drag up on the accessory pulls the sheet open, and its scope '
      'closes it again', (tester) async {
    await pumpSheet(tester);

    await tester.fling(accessory, const Offset(0, -80), 1500);
    await tester.pumpAndSettle();
    expect(tester.getRect(card).bottom, closeTo(bottom, 0.5));
    expect(opacityOf(tester, accessory), 0);

    final expansion = AdaptiveAccessoryScope.expansionOf(
      tester.element(accessory),
    )!;
    expect(expansion.isOpen, isTrue);
    expansion.close();
    await tester.pumpAndSettle();
    expect(tester.getRect(sheetGlass).height, closeTo(band, 0.5));
    expect(opacityOf(tester, accessory), closeTo(1, 0.001));
  });

  testWidgets('other content ends above the accessory, which stays in sight '
      'and takes its touches, on a capsule of its own', (tester) async {
    await pumpSheet(tester, opens: ValueNotifier<bool>(false));

    final glass = tester.getRect(sheetGlass);
    expect(glass.bottom, bottom);
    expect(tester.getRect(card).bottom, closeTo(bottom - band, 0.5));
    expect(tester.getRect(accessory).bottom, closeTo(bottom - inset, 0.5));
    expect(opacityOf(tester, accessory), 1);
    expectRect(tester.getRect(capsule), tester.getRect(accessory));
    expect(opacityOf(tester, capsule), closeTo(1, 0.001));
    expect(
      AdaptiveAccessoryScope.surfaceOf(tester.element(accessory)),
      const AdaptiveAccessorySurface(shape: StadiumBorder()),
    );
    await tester.tap(accessory);
    expect(taps, 1);
  });

  testWidgets('one with nothing to show takes no room', (tester) async {
    await pumpSheet(
      tester,
      opens: ValueNotifier<bool>(false),
      accessoryWidget: const SizedBox.shrink(key: ValueKey('accessory')),
    );

    expect(tester.getRect(card).bottom, closeTo(bottom, 0.5));
  });

  testWidgets('a side panel holds none', (tester) async {
    await pumpSheet(
      tester,
      opens: ValueNotifier<bool>(false),
      window: const Size(1000, 700),
    );

    expect(accessory, findsNothing);
  });

  testWidgets('content that gives way to content opening from the accessory, '
      'a station to a ride, tells the page of the new extent after the frame, '
      'as the page builds again for it', (tester) async {
    final opens = ValueNotifier<bool>(false);
    addTearDown(opens.dispose);
    final settled = <EdgeInsets>[];
    await pumpSheet(tester, opens: opens, onSettled: settled.add);
    settled.clear();

    opens.value = true;
    await tester.pump();
    expect(tester.takeException(), isNull);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    // Its content now running on into the accessory's place.
    expect(tester.getRect(card).bottom, closeTo(bottom, 0.5));
    expect(
      settled.last.bottom,
      closeTo(874 - tester.getRect(sheetGlass).top, 0.5),
    );
  });
}
