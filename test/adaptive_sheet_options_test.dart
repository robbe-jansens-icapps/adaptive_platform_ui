import 'package:adaptive_platform_ui/adaptive_platform_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
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

  testWidgets('at its collapsed detent only its header is in sight where it '
      'keeps its content clear of the bars: the content fades in as it is '
      'pulled up; as it always was otherwise', (tester) async {
    usePhone(tester);
    Widget sheet({required bool keepsClear}) => MaterialApp(
      home: Stack(
        children: [
          const Positioned.fill(child: ColoredBox(color: Colors.green)),
          Positioned.fill(
            child: AdaptiveSheet(
              detents: const [
                AdaptiveSheetDetent.collapsed,
                AdaptiveSheetDetent.fitContent,
              ],
              initialDetent: AdaptiveSheetDetent.collapsed,
              keepsContentClearOfBars: keepsClear,
              header: const SizedBox(height: 40, child: Text('header')),
              child: const SizedBox(height: 200, child: Text('content')),
            ),
          ),
        ],
      ),
    );
    final fade = find.ancestor(
      of: find.text('content'),
      matching: find.byType(Opacity),
    );

    await tester.pumpWidget(sheet(keepsClear: false));
    await tester.pumpAndSettle();
    // Wrapped all the same, so the content keeps its state as the sheet
    // starts or stops fading it, but in sight.
    expect(tester.widget<Opacity>(fade).opacity, 1);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpWidget(sheet(keepsClear: true));
    await tester.pumpAndSettle();
    expect(tester.widget<Opacity>(fade).opacity, 0);

    await tester.drag(find.text('header'), const Offset(0, -150));
    await tester.pumpAndSettle();
    expect(tester.widget<Opacity>(fade).opacity, 1);
  });

  testWidgets('content kept clear of the bars fades out as it runs on under '
      'the tabs alone, on glass of their own, but ends at a clean edge above an '
      'accessory on the sheet, which has none', (tester) async {
    usePhone(tester);
    // Tabs along the bottom, 100 points tall with the room below them.
    tester.view.padding = const FakeViewPadding(top: 60, bottom: 100);
    tester.view.viewPadding = const FakeViewPadding(top: 60, bottom: 100);
    PlatformInfo.debugPlatformOverride = TargetPlatform.iOS;
    PlatformInfo.debugIOSVersionOverride = 26;
    addTearDown(() {
      PlatformInfo.debugPlatformOverride = null;
      PlatformInfo.debugIOSVersionOverride = null;
    });
    final boundary = GlobalKey();
    const tabsTop = 800.0 - 100;

    /// Whether the content, red, shows at [y] on the screen, with an
    /// accessory of [accessory] on the sheet.
    Future<List<bool>> redAt(
      List<double> ys, {
      required double accessory,
    }) async {
      await tester.pumpWidget(
        RepaintBoundary(
          key: boundary,
          child: MaterialApp(
            home: AdaptiveBottomBarInset(
              height: 100,
              accessory: accessory,
              child: const Stack(
                children: [
                  Positioned.fill(child: ColoredBox(color: Colors.white)),
                  Positioned.fill(
                    child: AdaptiveSheet(
                      detents: [AdaptiveSheetDetent.large],
                      keepsContentClearOfBars: true,
                      header: SizedBox(height: 40),
                      child: ColoredBox(
                        color: Color(0xFFFF0000),
                        child: SizedBox(height: 2000),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final bytes = await tester.runAsync(() async {
        final image =
            await (boundary.currentContext!.findRenderObject()!
                    as RenderRepaintBoundary)
                .toImage();
        return image.toByteData();
      });
      return [
        for (final y in ys)
          () {
            final offset = (y.round() * 400 + 200) * 4;
            final red = bytes!.getUint8(offset);
            final green = bytes.getUint8(offset + 1);
            return red > 200 && green < 160;
          }(),
      ];
    }

    // Above the tabs, partly into them, and down by their bottom.
    expect(
      await redAt([tabsTop - 20, tabsTop + 5, tabsTop + 80], accessory: 0),
      [true, true, false],
    );
    expect(await redAt([tabsTop - 20, tabsTop + 5], accessory: 50), [
      true,
      false,
    ]);
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

  group('with a header backdrop', () {
    const fill = Color(0xB3F2F8F3);

    Widget sheet({required bool backdrop}) => MaterialApp(
      home: Stack(
        children: [
          const Positioned.fill(child: ColoredBox(color: Colors.green)),
          Positioned.fill(
            child: AdaptiveSheet(
              detents: const [AdaptiveSheetDetent.large],
              initialDetent: AdaptiveSheetDetent.large,
              showsHeaderBackdrop: backdrop,
              glassFill: fill,
              header: const SizedBox(height: 40, child: Text('header')),
              child: Column(
                children: [
                  for (var i = 0; i < 30; i++)
                    SizedBox(height: 60, child: Text('row $i')),
                ],
              ),
            ),
          ),
        ],
      ),
    );

    Finder background() => find.descendant(
      of: find.byType(AdaptiveSheet),
      matching: find.byWidgetPredicate(
        (widget) =>
            widget is AdaptiveBarBackdrop ||
            (widget is ColoredBox && widget.color == _surfaceContainer),
      ),
    );
    double opacity(WidgetTester tester) => tester
        .widget<AnimatedOpacity>(
          find.ancestor(
            of: background(),
            matching: find.byType(AnimatedOpacity),
          ),
        )
        .opacity;
    Clip clip(WidgetTester tester) => tester
        .widget<SingleChildScrollView>(find.byType(SingleChildScrollView))
        .clipBehavior;

    testWidgets('the content scrolls on under the header, which is frosted '
        'in the fill\'s colour once it does; as it always was otherwise', (
      tester,
    ) async {
      usePhone(tester);
      await tester.pumpWidget(sheet(backdrop: false));
      await tester.pumpAndSettle();
      expect(background(), findsNothing);
      expect(clip(tester), Clip.hardEdge);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpWidget(sheet(backdrop: true));
      await tester.pumpAndSettle();
      expect(clip(tester), Clip.none);
      expect(opacity(tester), 0);
      expect(tester.widget<AdaptiveBarBackdrop>(background()).color, fill);

      final headerBottom = tester.getBottomLeft(find.text('header')).dy;
      await tester.drag(find.text('row 4'), const Offset(0, -150));
      await tester.pumpAndSettle();

      expect(opacity(tester), 1);
      // Scrolled under the header, and painted under it: a tap there is the
      // header's.
      final point = Offset(_phone.width / 2, headerBottom - 10);
      final under = [
        for (var i = 0; i < 6; i++)
          if (tester.getRect(find.text('row $i')).top < point.dy &&
              tester.getRect(find.text('row $i')).bottom > point.dy)
            tester.renderObject(find.text('row $i')),
      ];
      expect(under, isNotEmpty);
      final hit = tester.hitTestOnBinding(point).path.map((e) => e.target);
      expect(hit, isNot(contains(under.single)));
      // Fading out under it, which a blur over native views would not do.
      bool fadesUnderHeader() => tester.layers.whereType<ShaderMaskLayer>().any(
        (layer) =>
            layer.maskRect!.top <= tester.getTopLeft(find.text('header')).dy &&
            layer.maskRect!.bottom > headerBottom,
      );
      expect(fadesUnderHeader(), isTrue);

      await tester.drag(find.text('row 6'), const Offset(0, 400));
      await tester.pumpAndSettle();
      expect(opacity(tester), 0);
      expect(fadesUnderHeader(), isFalse);
    });

    testWidgets('on Android the header takes the colour of an app bar '
        'scrolled under', (tester) async {
      usePhone(tester);
      PlatformInfo.debugPlatformOverride = TargetPlatform.android;
      addTearDown(() => PlatformInfo.debugPlatformOverride = null);
      await tester.pumpWidget(sheet(backdrop: true));
      await tester.pumpAndSettle();
      expect(background(), findsOneWidget);
      expect(find.byType(AdaptiveBarBackdrop), findsNothing);

      await tester.drag(find.text('row 4'), const Offset(0, -150));
      await tester.pumpAndSettle();
      expect(opacity(tester), 1);
    });
  });
}

/// The default Material 3 theme's colour of an app bar scrolled under.
final _surfaceContainer = ThemeData().colorScheme.surfaceContainer;
