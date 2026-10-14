import 'package:adaptive_platform_ui/adaptive_platform_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _phone = Size(400, 800);

void usePhone(WidgetTester tester) {
  tester.view.physicalSize = _phone;
  tester.view.devicePixelRatio = 1;
  tester.view.padding = const FakeViewPadding(top: 60, bottom: 34);
  tester.view.viewPadding = const FakeViewPadding(top: 60, bottom: 34);
  addTearDown(tester.view.reset);
}

Widget sheetApp({
  List<AdaptiveSheetDetent> detents = const [AdaptiveSheetDetent.fitContent],
  bool showsGrabber = true,
  bool scrollable = true,
  EdgeInsets? floatingMargin,
  VoidCallback? onDismissed,
  double contentHeight = 200,
  Color? glassFill,
}) => MaterialApp(
  home: Stack(
    children: [
      const Positioned.fill(child: ColoredBox(color: Colors.green)),
      Positioned.fill(
        child: AdaptiveSheet(
          detents: detents,
          showsGrabber: showsGrabber,
          scrollable: scrollable,
          floatingMargin: floatingMargin,
          onDismissed: onDismissed,
          glassFill: glassFill,
          child: SizedBox(
            height: contentHeight,
            child: const Align(
              alignment: Alignment.topCenter,
              child: Text('content'),
            ),
          ),
        ),
      ),
    ],
  ),
);

/// Top of the sheet, on the glass it floats on.
double sheetTop(WidgetTester tester) =>
    tester.getTopLeft(find.byType(IOS26GlassSurface)).dy;

Finder get grabber => find.byWidgetPredicate(
  (widget) => widget is Semantics && widget.properties.label == 'Sheet grabber',
);

void main() {
  testWidgets('lays its glass fill over the glass', (tester) async {
    usePhone(tester);
    await tester.pumpWidget(sheetApp());
    await tester.pumpAndSettle();
    IOS26GlassSurface glass() =>
        tester.widget<IOS26GlassSurface>(find.byType(IOS26GlassSurface));
    expect(glass().fill, isNull);

    const fill = Color(0x80FFFFFF);
    await tester.pumpWidget(sheetApp(glassFill: fill));
    await tester.pumpAndSettle();

    expect(glass().fill, fill);
  });

  testWidgets('without a grabber its content starts at the top', (
    tester,
  ) async {
    usePhone(tester);
    await tester.pumpWidget(sheetApp());
    await tester.pumpAndSettle();
    expect(grabber, findsOneWidget);
    expect(
      tester.getTopLeft(find.text('content')).dy,
      greaterThan(sheetTop(tester)),
    );

    await tester.pumpWidget(sheetApp(showsGrabber: false));
    await tester.pumpAndSettle();

    expect(grabber, findsNothing);
    expect(tester.getTopLeft(find.text('content')).dy, sheetTop(tester));
  });

  testWidgets('content that does not scroll moves the sheet when dragged', (
    tester,
  ) async {
    usePhone(tester);
    await tester.pumpWidget(sheetApp(scrollable: false));
    await tester.pumpAndSettle();
    final top = sheetTop(tester);

    expect(find.byType(SingleChildScrollView), findsNothing);

    final gesture = await tester.startGesture(
      tester.getCenter(find.text('content')),
    );
    await gesture.moveBy(const Offset(0, 40));
    await gesture.moveBy(const Offset(0, 40));
    await tester.pump();
    expect(sheetTop(tester), greaterThan(top));

    // With one detent and nowhere to go, it springs back.
    await gesture.up();
    await tester.pumpAndSettle();
    expect(sheetTop(tester), closeTo(top, 0.5));
  });

  testWidgets('a dismissible sheet slides out when dragged down', (
    tester,
  ) async {
    usePhone(tester);
    var dismissed = 0;
    await tester.pumpWidget(
      sheetApp(scrollable: false, onDismissed: () => dismissed++),
    );
    await tester.pumpAndSettle();

    await tester.drag(find.text('content'), const Offset(0, 250));
    await tester.pumpAndSettle();

    expect(dismissed, 1);
    expect(sheetTop(tester), greaterThanOrEqualTo(_phone.height - 1));
  });

  testWidgets('a dismissible sheet slides out when flung down', (tester) async {
    usePhone(tester);
    var dismissed = 0;
    await tester.pumpWidget(
      sheetApp(scrollable: false, onDismissed: () => dismissed++),
    );
    await tester.pumpAndSettle();

    await tester.fling(find.text('content'), const Offset(0, 60), 1500);
    await tester.pumpAndSettle();

    expect(dismissed, 1);
  });

  testWidgets('a fling down stops at a lower detent before it dismisses', (
    tester,
  ) async {
    usePhone(tester);
    var dismissed = 0;
    await tester.pumpWidget(
      sheetApp(
        detents: const [
          AdaptiveSheetDetent.collapsed,
          AdaptiveSheetDetent.fitContent,
        ],
        scrollable: false,
        contentHeight: 400,
        onDismissed: () => dismissed++,
      ),
    );
    await tester.pumpAndSettle();
    final top = sheetTop(tester);

    await tester.fling(find.text('content'), const Offset(0, 60), 1500);
    await tester.pumpAndSettle();

    expect(dismissed, 0);
    expect(sheetTop(tester), greaterThan(top + 100));
    expect(sheetTop(tester), lessThan(_phone.height - 1));
  });

  testWidgets('floats 8 points from the edges, or where it is told', (
    tester,
  ) async {
    double contentBottom() => tester
        .getBottomLeft(
          find
              .ancestor(
                of: find.text('content'),
                matching: find.byType(SizedBox),
              )
              .first,
        )
        .dy;
    usePhone(tester);
    await tester.pumpWidget(sheetApp());
    await tester.pumpAndSettle();
    var frame = tester.getRect(find.byType(IOS26GlassSurface));
    expect(frame.left, 8);
    expect(frame.right, _phone.width - 8);
    expect(frame.bottom, closeTo(_phone.height - 8, 0.01));
    // Its content clear of the home indicator (34), and its padding (16).
    expect(frame.bottom - contentBottom(), closeTo(34 - 8 + 16, 0.01));

    await tester.pumpWidget(
      sheetApp(floatingMargin: const EdgeInsets.fromLTRB(16, 0, 24, 12)),
    );
    await tester.pumpAndSettle();
    frame = tester.getRect(find.byType(IOS26GlassSurface));
    expect(frame.left, closeTo(16, 0.01));
    expect(frame.right, closeTo(_phone.width - 24, 0.01));
    expect(frame.bottom, closeTo(_phone.height - 12, 0.01));
    // Placed by hand, it keeps no further room: only its padding.
    expect(frame.bottom - contentBottom(), closeTo(16, 0.01));
  });

  testWidgets('content that grows while it comes up keeps it at its speed', (
    tester,
  ) async {
    usePhone(tester);
    await tester.pumpWidget(sheetApp(contentHeight: 100));
    // Measured: it starts to come up.
    await tester.pump();
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    final before = sheetTop(tester);
    await tester.pump(const Duration(milliseconds: 16));
    final speed = before - sheetTop(tester);

    final from = sheetTop(tester);
    await tester.pumpWidget(sheetApp(contentHeight: 300));
    await tester.pump(const Duration(milliseconds: 16));

    // Starting over from rest, it would move less than it just did.
    expect(from - sheetTop(tester), greaterThan(speed));
    await tester.pumpAndSettle();
    final settled = sheetTop(tester);

    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(sheetApp(contentHeight: 300));
    await tester.pumpAndSettle();
    expect(settled, closeTo(sheetTop(tester), 0.5));
  });

  for (final scrollable in [false, true]) {
    testWidgets('a tap on it while it comes up leaves it on its way'
        '${scrollable ? ', also on content that scrolls' : ''}', (
      tester,
    ) async {
      usePhone(tester);
      var dismissed = 0;
      await tester.pumpWidget(
        sheetApp(scrollable: scrollable, onDismissed: () => dismissed++),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 32));
      expect(sheetTop(tester), lessThan(_phone.height - 30));

      // On the content, below the grabber.
      await tester.tapAt(Offset(_phone.width / 2, sheetTop(tester) + 24));
      await tester.pumpAndSettle();

      expect(dismissed, 0);
      final settled = sheetTop(tester);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(sheetApp(scrollable: scrollable));
      await tester.pumpAndSettle();
      expect(settled, closeTo(sheetTop(tester), 0.5));
    });
  }

  testWidgets('a small drag down does not dismiss it', (tester) async {
    usePhone(tester);
    var dismissed = 0;
    await tester.pumpWidget(
      sheetApp(scrollable: false, onDismissed: () => dismissed++),
    );
    await tester.pumpAndSettle();
    final top = sheetTop(tester);

    await tester.drag(find.text('content'), const Offset(0, 30));
    await tester.pumpAndSettle();

    expect(dismissed, 0);
    expect(sheetTop(tester), closeTo(top, 0.5));
  });
}
