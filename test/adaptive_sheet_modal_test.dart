import 'package:adaptive_platform_ui/adaptive_platform_ui.dart';
import 'package:adaptive_platform_ui/src/toolbar/hosted_top_toolbar.dart'
    show kHostedToolbarBottomPadding;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// A modal sheet: an [AdaptiveSheet] as the page of a popup route.
class SheetRoute<T> extends PopupRoute<T> {
  SheetRoute({
    this.detent = AdaptiveSheetDetent.fitContent,
    this.contentHeight = 200,
    this.optsIn = true,
  });

  final AdaptiveSheetDetent detent;
  final double contentHeight;

  /// Whether the sheet asks for what a modal sheet does
  /// ([AdaptiveSheet.modal], [AdaptiveSheet.contentDragsSheet]); without,
  /// it is as it always was.
  final bool optsIn;

  @override
  Color? get barrierColor => const Color(0x33000000);

  @override
  bool get barrierDismissible => true;

  @override
  String? get barrierLabel => 'Dismiss';

  @override
  Duration get transitionDuration => const Duration(milliseconds: 250);

  @override
  Duration get reverseTransitionDuration => const Duration(milliseconds: 300);

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) => AdaptiveSheet(
    detents: [detent],
    initialDetent: detent,
    sidePanel: false,
    modal: optsIn,
    contentDragsSheet: optsIn,
    onDismissed: () {
      if (isCurrent) navigator?.pop();
    },
    child: SizedBox(
      height: contentHeight,
      child: const Align(
        alignment: Alignment.topCenter,
        child: Text('content'),
      ),
    ),
  );
}

void usePhone(WidgetTester tester) {
  tester.view.physicalSize = const Size(400, 800);
  tester.view.devicePixelRatio = 1;
  tester.view.padding = const FakeViewPadding(top: 60, bottom: 34);
  tester.view.viewPadding = const FakeViewPadding(top: 60, bottom: 34);
  addTearDown(tester.view.reset);
}

final navigatorKey = GlobalKey<NavigatorState>();

/// An app whose host draws the toolbar when [hostsToolbar].
Widget app({bool hostsToolbar = false}) => MaterialApp(
  navigatorKey: navigatorKey,
  builder: (context, child) => ToolbarChromeScope(
    hostsToolbar: hostsToolbar,
    hostsDuoControls: false,
    child: child!,
  ),
  home: const ColoredBox(color: Colors.green),
);

Rect sheetRect(WidgetTester tester) =>
    tester.getRect(find.byType(IOS26GlassSurface));

void main() {
  setUp(() => PlatformInfo.debugPlatformOverride = TargetPlatform.iOS);
  tearDown(() => PlatformInfo.debugPlatformOverride = null);

  testWidgets('content with nothing to scroll leaves every drag to the '
      'sheet: it follows the finger down at once', (tester) async {
    usePhone(tester);
    await tester.pumpWidget(app());
    navigatorKey.currentState!.push(SheetRoute<void>());
    await tester.pumpAndSettle();
    final rest = sheetRect(tester).top;
    final offset = tester.getTopLeft(find.text('content')).dy - rest;

    final gesture = await tester.startGesture(
      tester.getCenter(find.text('content')),
    );
    // Past the drag's slop, then on in small steps, as a finger moves.
    await gesture.moveBy(const Offset(0, 20));
    for (var i = 0; i < 6; i++) {
      await gesture.moveBy(const Offset(0, 10));
      await tester.pump(const Duration(milliseconds: 16));
    }
    // Every step moved the sheet, the first one's way past the slop too, and
    // the content with it.
    expect(sheetRect(tester).top, closeTo(rest + 80, 1));
    expect(
      tester.getTopLeft(find.text('content')).dy - sheetRect(tester).top,
      closeTo(offset, 1),
    );

    // Far enough down, let go, it slides out and its route goes.
    await gesture.moveBy(const Offset(0, 120));
    await tester.pump(const Duration(milliseconds: 16));
    await gesture.up();
    await tester.pumpAndSettle();
    expect(find.text('content'), findsNothing);
  });

  testWidgets('as its route goes, a modal sheet slides down out of view '
      'with it, however it is popped', (tester) async {
    usePhone(tester);
    await tester.pumpWidget(app());
    navigatorKey.currentState!.push(SheetRoute<void>());
    await tester.pumpAndSettle();
    final rest = sheetRect(tester).top;

    // The barrier tapped.
    await tester.tapAt(const Offset(200, 120));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    final midway = sheetRect(tester).top;
    expect(midway, greaterThan(rest + 20));
    expect(midway, lessThan(800));
    await tester.pump(const Duration(milliseconds: 150));
    expect(sheetRect(tester).top, greaterThan(midway));
    await tester.pumpAndSettle();
    expect(find.byType(AdaptiveSheet), findsNothing);
  });

  testWidgets('at its tallest a modal sheet stops below the toolbar the host '
      'draws over the page, which stays in sight above it', (tester) async {
    usePhone(tester);
    await tester.pumpWidget(app(hostsToolbar: true));
    navigatorKey.currentState!.push(
      SheetRoute<void>(detent: AdaptiveSheetDetent.large),
    );
    await tester.pumpAndSettle();

    expect(
      sheetRect(tester).top,
      closeTo(
        60 + kHostedToolbarHeight + kHostedToolbarBottomPadding + 8,
        0.01,
      ),
    );
  });

  testWidgets('a sheet that does not ask for it is as it always was: '
      'at its tallest under the toolbar, still as its route goes, and its '
      'content taking a drag that the sheet cannot follow', (tester) async {
    usePhone(tester);
    await tester.pumpWidget(app(hostsToolbar: true));
    navigatorKey.currentState!.push(
      SheetRoute<void>(detent: AdaptiveSheetDetent.large, optsIn: false),
    );
    await tester.pumpAndSettle();
    final rest = sheetRect(tester).top;
    expect(rest, closeTo(60 + 8, 0.01));

    // Its single detent is its largest: a drag down on content that fits
    // moves it a step at most.
    final gesture = await tester.startGesture(
      tester.getCenter(find.text('content')),
    );
    await gesture.moveBy(const Offset(0, 20));
    for (var i = 0; i < 6; i++) {
      await gesture.moveBy(const Offset(0, 10));
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(sheetRect(tester).top, lessThan(rest + 80));
    await gesture.up();
    await tester.pumpAndSettle();
    expect(sheetRect(tester).top, closeTo(rest, 0.5));

    navigatorKey.currentState!.pop();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(sheetRect(tester).top, closeTo(rest, 0.5));
    await tester.pumpAndSettle();
  });
}
