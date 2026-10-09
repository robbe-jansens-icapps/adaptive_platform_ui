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
  VoidCallback? onDismissed,
  double contentHeight = 200,
}) => MaterialApp(
  home: Stack(
    children: [
      const Positioned.fill(child: ColoredBox(color: Colors.green)),
      Positioned.fill(
        child: AdaptiveSheet(
          detents: detents,
          showsGrabber: showsGrabber,
          scrollable: scrollable,
          onDismissed: onDismissed,
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
  testWidgets('without a grabber it keeps the room the grabber takes', (
    tester,
  ) async {
    usePhone(tester);
    await tester.pumpWidget(sheetApp());
    await tester.pumpAndSettle();
    final withGrabber = tester.getTopLeft(find.text('content')).dy;

    await tester.pumpWidget(sheetApp(showsGrabber: false));
    await tester.pumpAndSettle();

    expect(grabber, findsNothing);
    expect(tester.getTopLeft(find.text('content')).dy, withGrabber);
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
