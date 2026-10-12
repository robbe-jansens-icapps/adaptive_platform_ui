import 'dart:async';

import 'package:adaptive_platform_ui/adaptive_platform_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

const _phone = Size(400, 800);

void usePhone(WidgetTester tester, {Size size = _phone}) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  tester.view.padding = const FakeViewPadding(top: 60, bottom: 34);
  tester.view.viewPadding = const FakeViewPadding(top: 60, bottom: 34);
  addTearDown(tester.view.reset);
}

Widget sheetApp({
  double contentHeight = 200,
  AdaptiveSheetController? controller,
  List<AdaptiveSheetDetent> detents = const [
    AdaptiveSheetDetent.collapsed,
    AdaptiveSheetDetent.fitContent,
  ],
  ValueChanged<EdgeInsets>? onSettled,
  ValueChanged<AdaptiveSheetDetent>? onDetentChanged,
  bool? sidePanel,
}) => MaterialApp(
  home: Stack(
    children: [
      const Positioned.fill(child: ColoredBox(color: Colors.green)),
      Positioned.fill(
        child: AdaptiveSheet(
          controller: controller,
          detents: detents,
          onSettled: onSettled,
          onDetentChanged: onDetentChanged,
          sidePanel: sidePanel,
          header: const SizedBox(height: 60, child: Text('header')),
          child: SizedBox(height: contentHeight, child: const Text('content')),
        ),
      ),
    ],
  ),
);

/// Top of the sheet's frame, measured on the grabber, which sits at its top.
double sheetTop(WidgetTester tester) => tester
    .getTopLeft(
      find.byWidgetPredicate(
        (widget) =>
            widget is Semantics && widget.properties.label == 'Sheet grabber',
      ),
    )
    .dy;

// The visible height a floating iOS sheet needs for the 60 point header and
// [content]: gap 8, grabber 16, header 60, content, and the bottom padding
// (34 - 8 + 16).
double fitExtent(double content) => 8 + 16 + 60 + content + 42;
double collapsedExtent() => 16 + 60 + 34;

void main() {
  testWidgets('slides in and rests where the content fits', (tester) async {
    usePhone(tester);
    final settled = <EdgeInsets>[];
    await tester.pumpWidget(sheetApp(onSettled: settled.add));
    await tester.pumpAndSettle();

    expect(sheetTop(tester), closeTo(_phone.height - fitExtent(200), 0.5));
    expect(find.text('content'), findsOneWidget);
    expect(settled.last, EdgeInsets.only(bottom: fitExtent(200)));
  });

  testWidgets('floats inset from the edges below the large detent', (
    tester,
  ) async {
    usePhone(tester);
    await tester.pumpWidget(sheetApp());
    await tester.pumpAndSettle();

    final glass = tester.getRect(find.byType(IOS26GlassSurface));
    expect(glass.left, 8);
    expect(glass.right, _phone.width - 8);
    expect(glass.bottom, _phone.height - 8);
  });

  testWidgets('keeps clear of the iPhone Duo vertical bar', (tester) async {
    usePhone(tester);
    // The strip pose: no top inset, the system strip on one side only.
    tester.view.padding = const FakeViewPadding(right: 60, bottom: 20);
    tester.view.viewPadding = const FakeViewPadding(right: 60, bottom: 20);
    await tester.pumpWidget(sheetApp());
    await tester.pumpAndSettle();

    final glass = tester.getRect(find.byType(IOS26GlassSurface));
    final band = DuoLayout.bandWidth(const EdgeInsets.only(right: 60));
    expect(glass.left, 8);
    expect(glass.right, _phone.width - band - 8);
  });

  testWidgets('keeps clear of the iPhone Duo vertical bar on the left', (
    tester,
  ) async {
    usePhone(tester);
    tester.view.padding = const FakeViewPadding(left: 60, bottom: 20);
    tester.view.viewPadding = const FakeViewPadding(left: 60, bottom: 20);
    await tester.pumpWidget(sheetApp());
    await tester.pumpAndSettle();

    final glass = tester.getRect(find.byType(IOS26GlassSurface));
    final band = DuoLayout.bandWidth(const EdgeInsets.only(left: 60));
    expect(glass.left, band + 8);
    expect(glass.right, _phone.width - 8);
  });

  testWidgets('ignores a one-sided cutout on Android', (tester) async {
    PlatformInfo.debugPlatformOverride = TargetPlatform.android;
    addTearDown(() => PlatformInfo.debugPlatformOverride = null);
    usePhone(tester);
    tester.view.padding = const FakeViewPadding(right: 60, bottom: 20);
    tester.view.viewPadding = const FakeViewPadding(right: 60, bottom: 20);
    await tester.pumpWidget(sheetApp());
    await tester.pumpAndSettle();

    final sheet = tester.getRect(find.byType(Material).last);
    expect(sheet.left, 0);
    expect(sheet.right, _phone.width);
  });

  testWidgets('a fling down collapses it and a fling up brings it back', (
    tester,
  ) async {
    usePhone(tester);
    final detents = <AdaptiveSheetDetent>[];
    await tester.pumpWidget(sheetApp(onDetentChanged: detents.add));
    await tester.pumpAndSettle();

    await tester.fling(find.text('header'), const Offset(0, 80), 1500);
    await tester.pumpAndSettle();
    expect(sheetTop(tester), closeTo(_phone.height - collapsedExtent(), 0.5));

    await tester.fling(find.text('header'), const Offset(0, -80), 1500);
    await tester.pumpAndSettle();
    expect(sheetTop(tester), closeTo(_phone.height - fitExtent(200), 0.5));
    expect(detents, [
      AdaptiveSheetDetent.fitContent,
      AdaptiveSheetDetent.collapsed,
      AdaptiveSheetDetent.fitContent,
    ]);
  });

  testWidgets('a slow drag rests at the nearest detent', (tester) async {
    usePhone(tester);
    await tester.pumpWidget(sheetApp());
    await tester.pumpAndSettle();

    await tester.drag(find.text('header'), const Offset(0, 40));
    await tester.pumpAndSettle();

    expect(sheetTop(tester), closeTo(_phone.height - fitExtent(200), 0.5));
  });

  testWidgets('dragging the content moves the sheet while it is at its top', (
    tester,
  ) async {
    usePhone(tester);
    await tester.pumpWidget(sheetApp());
    await tester.pumpAndSettle();
    final top = sheetTop(tester);

    final gesture = await tester.startGesture(
      tester.getCenter(find.text('content')),
    );
    await gesture.moveBy(const Offset(0, 30));
    await gesture.moveBy(const Offset(0, 30));
    await tester.pump();
    expect(sheetTop(tester), greaterThan(top + 20));

    await gesture.up();
    await tester.pumpAndSettle();
  });

  testWidgets('long content scrolls inside the large detent', (tester) async {
    usePhone(tester);
    await tester.pumpWidget(
      sheetApp(
        contentHeight: 2000,
        detents: const [
          AdaptiveSheetDetent.collapsed,
          AdaptiveSheetDetent.large,
        ],
      ),
    );
    await tester.pumpAndSettle();
    await tester.fling(find.text('header'), const Offset(0, -100), 2000);
    await tester.pumpAndSettle();

    // At the large detent the sheet is edge to edge, just below the top.
    expect(sheetTop(tester), closeTo(60 + 8, 0.5));
    final glass = tester.getRect(find.byType(IOS26GlassSurface));
    expect(glass.left, 0);
    expect(glass.right, _phone.width);
  });

  testWidgets('the controller hides it and shows it again', (tester) async {
    usePhone(tester);
    final controller = AdaptiveSheetController();
    final settled = <EdgeInsets>[];
    await tester.pumpWidget(
      sheetApp(controller: controller, onSettled: settled.add),
    );
    await tester.pumpAndSettle();
    expect(controller.detent, AdaptiveSheetDetent.fitContent);

    // The future completes with the animation, which needs pumped frames.
    unawaited(controller.animateTo(AdaptiveSheetDetent.hidden));
    await tester.pumpAndSettle();
    expect(controller.extent.value, closeTo(0, 0.5));
    expect(settled.last, EdgeInsets.zero);

    unawaited(controller.animateTo(AdaptiveSheetDetent.collapsed));
    await tester.pumpAndSettle();
    expect(controller.extent.value, closeTo(collapsedExtent(), 0.5));
  });

  testWidgets('follows new content while resting at its size', (tester) async {
    usePhone(tester);
    await tester.pumpWidget(sheetApp());
    await tester.pumpAndSettle();

    await tester.pumpWidget(sheetApp(contentHeight: 300));
    await tester.pumpAndSettle();

    expect(sheetTop(tester), closeTo(_phone.height - fitExtent(300), 0.5));
  });

  testWidgets('becomes a side panel on a wide window', (tester) async {
    usePhone(tester, size: const Size(951, 669));
    final settled = <EdgeInsets>[];
    await tester.pumpWidget(sheetApp(onSettled: settled.add));
    await tester.pumpAndSettle();

    final panel = tester.getRect(find.byType(IOS26GlassSurface));
    expect(panel.left, 16);
    expect(panel.width, 380);
    expect(panel.top, 60 + 8);
    expect(settled.last, const EdgeInsets.only(left: 16 + 380 + 8));
  });

  testWidgets('a side panel comes in at its size, then follows its content', (
    tester,
  ) async {
    usePhone(tester, size: const Size(951, 669));
    // Grabber 16, header 60, content and the bottom padding 16.
    double panelHeight() =>
        tester.getRect(find.byType(IOS26GlassSurface)).height;
    await tester.pumpWidget(sheetApp());
    // Measured: it slides in as tall as it needs to be.
    await tester.pump();
    expect(panelHeight(), 16 + 60 + 200 + 16);
    await tester.pumpAndSettle();

    // Content that loads: it grows to fit it, on screen.
    await tester.pumpWidget(sheetApp(contentHeight: 300));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(
      panelHeight(),
      inExclusiveRange(16 + 60 + 200 + 16, 16 + 60 + 300 + 16),
    );
    await tester.pumpAndSettle();
    expect(panelHeight(), 16 + 60 + 300 + 16);
  });

  testWidgets('a hidden side panel leaves the window, also from beside a '
      'vertical bar on the left', (tester) async {
    usePhone(tester, size: const Size(951, 669));
    // The iPhone Duo vertical bar on the left.
    tester.view.padding = const FakeViewPadding(left: 84, top: 24);
    tester.view.viewPadding = const FakeViewPadding(left: 84, top: 24);
    final controller = AdaptiveSheetController();
    await tester.pumpWidget(sheetApp(controller: controller));
    await tester.pumpAndSettle();
    expect(tester.getRect(find.byType(IOS26GlassSurface)).left, 84 + 16);

    unawaited(controller.animateTo(AdaptiveSheetDetent.hidden));
    await tester.pumpAndSettle();

    expect(
      tester.getRect(find.byType(IOS26GlassSurface)).right,
      lessThanOrEqualTo(0),
    );
  });

  group('on Android', () {
    setUp(() => PlatformInfo.debugPlatformOverride = TargetPlatform.android);
    tearDown(() => PlatformInfo.debugPlatformOverride = null);

    testWidgets('a hidden side panel goes out of sight beside a navigation '
        'rail, not over it', (tester) async {
      usePhone(tester, size: const Size(951, 669));
      final controller = AdaptiveSheetController();
      await tester.pumpWidget(
        MaterialApp(
          home: Row(
            children: [
              const SizedBox(width: 80, child: ColoredBox(color: Colors.red)),
              Expanded(
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: AdaptiveSheet(
                        controller: controller,
                        detents: const [AdaptiveSheetDetent.fitContent],
                        header: const SizedBox(
                          height: 60,
                          child: Text('header'),
                        ),
                        child: const SizedBox(height: 200),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();
      Rect panel() => tester.getRect(
        find
            .ancestor(of: find.text('header'), matching: find.byType(Material))
            .first,
      );
      expect(panel().left, 80 + 16);

      unawaited(controller.animateTo(AdaptiveSheetDetent.hidden));
      await tester.pumpAndSettle();

      // Out of the sheet's area, and cut off at its edge.
      expect(panel().right, lessThanOrEqualTo(80));
      final area = tester.renderObject<RenderStack>(
        find
            .descendant(
              of: find.byType(AdaptiveSheet),
              matching: find.byType(Stack),
            )
            .first,
      );
      expect(area.clipBehavior, Clip.hardEdge);
    });

    testWidgets('is a Material 3 sheet with a drag handle', (tester) async {
      usePhone(tester);
      await tester.pumpWidget(sheetApp());
      await tester.pumpAndSettle();

      expect(find.byType(IOS26GlassSurface), findsNothing);
      final sheet = tester.getRect(
        find
            .ancestor(of: find.text('header'), matching: find.byType(Material))
            .first,
      );
      expect(sheet.left, 0);
      expect(sheet.right, _phone.width);
      // Grabber 36, header 60, content 200, bottom padding 34 + 16.
      expect(sheet.top, closeTo(_phone.height - (36 + 60 + 200 + 50), 0.5));
    });
  });
}
