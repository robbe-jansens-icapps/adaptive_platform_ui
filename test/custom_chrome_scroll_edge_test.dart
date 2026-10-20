import 'dart:math' as math;

import 'package:adaptive_platform_ui/adaptive_platform_ui.dart';
import 'package:adaptive_platform_ui/src/toolbar/duo_vertical_bar.dart'
    show DuoTitleBandTransition;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'custom_chrome_fixture.dart';

const backdrop = ValueKey<String>('backdrop');
const pageColor = Color(0xFF123456);

ValueListenable<double>? backEdge;
AdaptiveBarBackgroundSpec? lastBackground;

Widget _tabs(BuildContext context, AdaptiveTabBarSpec spec) =>
    const SizedBox(height: 60);
Widget _title(BuildContext context, AdaptiveTitleSpec spec) =>
    Text('title:${spec.title}', style: const TextStyle(fontSize: 8));
Widget _actions(BuildContext context, AdaptiveActionsSpec spec) =>
    const SizedBox.square(dimension: 44);
Widget _back(BuildContext context, AdaptiveBackButtonSpec spec) {
  if (spec.style == AdaptiveBackButtonStyle.back) backEdge = spec.scrollEdge;
  return GestureDetector(
    onTap: spec.onPressed,
    child: const SizedBox.square(dimension: 44, child: Text('back')),
  );
}

Widget _background(BuildContext context, AdaptiveBarBackgroundSpec spec) {
  lastBackground = spec;
  return ColoredBox(key: backdrop, color: spec.color!);
}

const chrome = AdaptiveChrome(
  tabBarBuilder: _tabs,
  titleBuilder: _title,
  backButtonBuilder: _back,
  actionsBuilder: _actions,
  barBackgroundBuilder: _background,
);

const plainChrome = AdaptiveChrome(
  tabBarBuilder: _tabs,
  titleBuilder: _title,
  backButtonBuilder: _back,
  actionsBuilder: _actions,
);

Widget listPage(
  String title, {
  Color color = pageColor,
  ScrollController? controller,
  int rows = 60,
}) {
  final list = ListView(
    key: ValueKey<String>('list $title'),
    controller: controller,
    children: [
      for (var i = 0; i < rows; i++)
        SizedBox(height: 60, child: Text('$title row $i')),
    ],
  );
  return AdaptiveScaffold(
    backgroundColor: color,
    appBar: AdaptiveAppBar(title: title),
    body: list,
  );
}

Widget plainPage(String title, {Color color = const Color(0xFFFFFFFF)}) =>
    AdaptiveScaffold(
      backgroundColor: color,
      appBar: AdaptiveAppBar(title: title),
      body: const SizedBox.expand(),
    );

void main() {
  final navigator = GlobalKey<NavigatorState>();

  setUp(() {
    backEdge = null;
    lastBackground = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          SystemChannels.platform_views,
          (_) async => null,
        );
  });

  tearDown(() {
    PlatformInfo.debugPlatformOverride = null;
    PlatformInfo.debugIOSVersionOverride = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform_views, null);
  });

  void phone(WidgetTester tester) {
    PlatformInfo.debugPlatformOverride = TargetPlatform.android;
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    tester.view.padding = const FakeViewPadding(top: 47, bottom: 34);
    tester.view.viewPadding = const FakeViewPadding(top: 47, bottom: 34);
    addTearDown(tester.view.reset);
  }

  Future<void> pumpApp(
    WidgetTester tester,
    Widget home, {
    AdaptiveChrome chrome = chrome,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigator,
        builder: (context, child) =>
            AdaptiveToolbarHost(chrome: chrome, child: child!),
        home: home,
      ),
    );
    await tester.pumpAndSettle();
  }

  /// How far the background along the top is in where a scroll view draws
  /// it, 0 where none does.
  double backdropOpacity(WidgetTester tester) =>
      debugScrollEdgesOnScreen().fold(0, math.max);

  testWidgets(
    'the bar\'s background is only there as far as content has scrolled under the bar, in the page\'s colour',
    (tester) async {
      phone(tester);
      final controller = ScrollController();
      addTearDown(controller.dispose);
      await pumpApp(tester, listPage('List', controller: controller));

      expect(backdropOpacity(tester), 0);
      expect(lastBackground!.color, pageColor);

      controller.jumpTo(12);
      await tester.pump();
      expect(
        backdropOpacity(tester),
        closeTo(12 / AdaptiveScrollEdge.distance, 0.01),
      );
      expect(
        lastBackground!.scrollEdge.value,
        closeTo(12 / AdaptiveScrollEdge.distance, 0.01),
      );

      await tester.drag(
        find.byKey(const ValueKey<String>('list List')),
        const Offset(0, -200),
      );
      await tester.pumpAndSettle();
      expect(backdropOpacity(tester), 1);

      await tester.drag(
        find.byKey(const ValueKey<String>('list List')),
        const Offset(0, 2000),
      );
      await tester.pumpAndSettle();
      expect(backdropOpacity(tester), 0);
    },
  );

  testWidgets(
    'a list that springs back into place as the window changes, a device turned, takes the bar\'s background along after that frame',
    (tester) async {
      phone(tester);
      // Sideways first: upright, the window shows all of the list.
      tester.view.physicalSize = const Size(844, 390);
      final controller = ScrollController();
      addTearDown(controller.dispose);
      await pumpApp(tester, listPage('List', controller: controller, rows: 8));
      expect(backdropOpacity(tester), 0);

      // Turned quickly, the list is left a little down from its top as the
      // next turn lays it out: it springs back, a scroll that starts while
      // the page is laid out.
      final position = controller.position;
      position.correctPixels(position.pixels + 12);
      tester.view.physicalSize = const Size(390, 844);
      await tester.pump();
      expect(tester.takeException(), isNull);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(position.pixels, position.minScrollExtent);
      expect(backdropOpacity(tester), 0);
    },
    // iOS's scroll physics: a list out of place springs back rather than
    // being clamped.
    variant: TargetPlatformVariant.only(TargetPlatform.iOS),
  );

  testWidgets(
    'each page brings its own: a page pushed over a scrolled list has none until it scrolls, and the list has it again on the way back',
    (tester) async {
      phone(tester);
      await pumpApp(tester, listPage('List'));
      await tester.drag(
        find.byKey(const ValueKey<String>('list List')),
        const Offset(0, -300),
      );
      await tester.pumpAndSettle();
      expect(backdropOpacity(tester), 1);

      navigator.currentState!.push(
        MaterialPageRoute<void>(
          builder: (_) => listPage('Detail', color: const Color(0xFF654321)),
        ),
      );
      await tester.pumpAndSettle();
      expect(backdropOpacity(tester), 0);
      expect(lastBackground!.color, const Color(0xFF654321));
      expect(backEdge!.value, 0);

      await tester.drag(
        find.byKey(const ValueKey<String>('list Detail')),
        const Offset(0, -300),
      );
      await tester.pumpAndSettle();
      expect(backEdge!.value, 1);

      await tester.tap(find.text('back'));
      await tester.pumpAndSettle();
      expect(backdropOpacity(tester), 1);
      expect(lastBackground!.color, pageColor);
    },
  );

  testWidgets(
    'the outermost scroll view decides: a list below a header that stays under the bar does not bring the background back',
    (tester) async {
      phone(tester);
      final outer = ScrollController();
      final inner = ScrollController();
      addTearDown(outer.dispose);
      addTearDown(inner.dispose);
      await pumpApp(
        tester,
        AdaptiveScaffold(
          appBar: const AdaptiveAppBar(title: 'Nested'),
          body: CustomScrollView(
            controller: outer,
            slivers: [
              const SliverToBoxAdapter(child: SizedBox(height: 200)),
              SliverToBoxAdapter(
                child: SizedBox(
                  height: 400,
                  child: ListView(
                    controller: inner,
                    children: [
                      for (var i = 0; i < 40; i++) const SizedBox(height: 60),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      );

      inner.jumpTo(300);
      await tester.pump();
      expect(backdropOpacity(tester), 0);

      outer.jumpTo(100);
      await tester.pump();
      expect(backdropOpacity(tester), 1);

      inner.jumpTo(0);
      await tester.pump();
      expect(backdropOpacity(tester), 1);

      outer.jumpTo(0);
      await tester.pump();
      expect(backdropOpacity(tester), 0);
    },
  );

  testWidgets(
    'a page replaced where it stands fades out with the background it had',
    (tester) async {
      phone(tester);
      final controller = ScrollController();
      addTearDown(controller.dispose);
      var second = false;
      late StateSetter swap;
      await pumpApp(
        tester,
        StatefulBuilder(
          builder: (context, setState) {
            swap = setState;
            return second
                ? KeyedSubtree(
                    key: const ValueKey<int>(2),
                    child: plainPage('Second'),
                  )
                : listPage('First', controller: controller);
          },
        ),
      );
      controller.jumpTo(48);
      await tester.pump();

      swap(() => second = true);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 16));
      await tester.pump(const Duration(milliseconds: 16));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('title:Second'), findsOneWidget);
      expect(backdropOpacity(tester), 0);
    },
  );

  testWidgets(
    'a header pinned above a list stays clear: the list does not run under the bar, so nothing is drawn over the header',
    (tester) async {
      phone(tester);
      const header = ValueKey<String>('pinned header');
      final controller = ScrollController();
      addTearDown(controller.dispose);
      await pumpApp(
        tester,
        AdaptiveScaffold(
          appBar: const AdaptiveAppBar(title: 'Pinned'),
          body: Builder(
            builder: (context) => Column(
              children: [
                SizedBox(height: MediaQuery.paddingOf(context).top),
                const SizedBox(key: header, height: 120),
                Expanded(
                  child: MediaQuery.removePadding(
                    context: context,
                    removeTop: true,
                    child: ListView(
                      controller: controller,
                      children: [
                        for (var i = 0; i < 60; i++) const SizedBox(height: 60),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );

      controller.jumpTo(600);
      await tester.pump();

      expect(backdropOpacity(tester), 0);
      expect(
        find.descendant(of: find.byKey(header), matching: find.byKey(backdrop)),
        findsNothing,
      );
    },
  );

  testWidgets(
    'without a background of the app\'s own the bar is the content blurred and tinted in the page\'s colour, ending at the bottom of the bar',
    (tester) async {
      phone(tester);
      final controller = ScrollController();
      addTearDown(controller.dispose);
      await pumpApp(
        tester,
        listPage('List', controller: controller),
        chrome: plainChrome,
      );
      controller.jumpTo(300);
      await tester.pump();

      final frost = find.byType(AdaptiveBarBackdrop);
      expect(frost, findsOneWidget);
      expect(tester.widget<AdaptiveBarBackdrop>(frost).color, pageColor);
      expect(tester.getRect(frost).top, 0);
      expect(tester.getRect(frost).bottom, 47 + kHostedToolbarHeight);
      expect(backdropOpacity(tester), 1);
      final hairline = find.descendant(
        of: frost,
        matching: find.byWidgetPredicate(
          (widget) =>
              widget is ColoredBox &&
              widget.color == AdaptiveBarBackdrop.defaultHairline,
        ),
      );
      expect(tester.getRect(hairline).bottom, 47 + kHostedToolbarHeight);
      expect(tester.getRect(hairline).height, 1);
    },
  );

  testWidgets(
    'content pinned below the bar joins it: the list runs under both, starts below both, and the bar\'s background reaches below what is pinned',
    (tester) async {
      phone(tester);
      const pinned = ValueKey<String>('pinned');
      const list = ValueKey<String>('list');
      final controller = ScrollController();
      addTearDown(controller.dispose);
      late double paddingTop;
      await pumpApp(
        tester,
        AdaptiveScaffold(
          backgroundColor: pageColor,
          appBar: const AdaptiveAppBar(title: 'Search'),
          body: AdaptiveSafeAreaBar(
            bar: const SizedBox(key: pinned, height: 56),
            child: Builder(
              builder: (context) {
                paddingTop = MediaQuery.paddingOf(context).top;
                return ListView(
                  key: list,
                  controller: controller,
                  children: [
                    for (var i = 0; i < 60; i++)
                      SizedBox(height: 60, child: Text('row $i')),
                  ],
                );
              },
            ),
          ),
        ),
      );

      const bar = 47 + kHostedToolbarHeight;
      expect(tester.getRect(find.byKey(pinned)).top, bar);
      expect(paddingTop, bar + 56);
      expect(tester.getRect(find.byKey(list)).top, 0);
      expect(tester.getRect(find.text('row 0')).top, bar + 56);
      expect(backdropOpacity(tester), 0);

      controller.jumpTo(300);
      await tester.pump();
      expect(backdropOpacity(tester), 1);
      expect(lastBackground!.height, bar + 56);
      expect(
        find.descendant(of: find.byKey(pinned), matching: find.byKey(backdrop)),
        findsNothing,
      );
    },
  );

  testWidgets(
    'what is pinned below the bar knows it has the bar\'s background behind it, and the page below does not',
    (tester) async {
      phone(tester);
      bool? inBar;
      bool? inPage;
      await pumpApp(
        tester,
        AdaptiveScaffold(
          backgroundColor: pageColor,
          appBar: const AdaptiveAppBar(title: 'Search'),
          body: AdaptiveSafeAreaBar(
            bar: Builder(
              builder: (context) {
                inBar = AdaptiveSafeAreaBar.isIn(context);
                return const SizedBox(height: 56);
              },
            ),
            child: Builder(
              builder: (context) {
                inPage = AdaptiveSafeAreaBar.isIn(context);
                return ListView(children: const [SizedBox(height: 2000)]);
              },
            ),
          ),
        ),
      );

      expect(inBar, isTrue);
      expect(inPage, isFalse);
    },
  );

  testWidgets(
    'a list running under the bar from below a docked header, with something pinned under the bar, draws the one background for both, and the outer scroll view none',
    (tester) async {
      phone(tester);
      const pinned = ValueKey<String>('pinned');
      const inner = ValueKey<String>('inner');
      const bar = 47 + kHostedToolbarHeight;
      await pumpApp(
        tester,
        AdaptiveScaffold(
          backgroundColor: pageColor,
          appBar: const AdaptiveAppBar(title: 'Docked'),
          body: NestedScrollView(
            headerSliverBuilder: (context, _) => const [
              SliverToBoxAdapter(child: SizedBox(height: 300)),
            ],
            // The body runs on under the bar, as a page that docks its
            // header there lays it out, and keeps clear of it by padding.
            body: AdaptiveSafeAreaBar(
              bar: const SizedBox(key: pinned, height: 56),
              child: Builder(
                builder: (context) => ListView(
                  key: inner,
                  padding: EdgeInsets.only(
                    top: MediaQuery.paddingOf(context).top,
                  ),
                  children: [
                    for (var i = 0; i < 60; i++) const SizedBox(height: 60),
                  ],
                ),
              ),
            ),
          ),
        ),
      );

      await tester.drag(find.byKey(inner), const Offset(0, -900));
      await tester.pumpAndSettle();

      expect(tester.getRect(find.byKey(inner)).top, lessThanOrEqualTo(0.5));
      expect(debugScrollEdgesOnScreen(), [1]);
      expect(debugScrollEdgeHeightsOnScreen(), [bar + 56]);
    },
  );

  testWidgets(
    'a page without scroll views, such as a map, has no background under the bar',
    (tester) async {
      phone(tester);
      await pumpApp(tester, plainPage('Map'));

      expect(debugScrollEdgesOnScreen(), isEmpty);
    },
  );

  testWidgets('content that only scrolls sideways leaves the bar clear', (
    tester,
  ) async {
    phone(tester);
    await pumpApp(
      tester,
      AdaptiveScaffold(
        appBar: const AdaptiveAppBar(title: 'Carousel'),
        body: ListView(
          key: const ValueKey<String>('carousel'),
          scrollDirection: Axis.horizontal,
          children: [for (var i = 0; i < 20; i++) const SizedBox(width: 200)],
        ),
      ),
    );

    await tester.drag(
      find.byKey(const ValueKey<String>('carousel')),
      const Offset(-400, 0),
    );
    await tester.pumpAndSettle();
    expect(backdropOpacity(tester), 0);
  });

  group('beside the iPhone Duo\'s vertical bar', () {
    void cover(WidgetTester tester) {
      PlatformInfo.debugPlatformOverride = TargetPlatform.iOS;
      PlatformInfo.debugIOSVersionOverride = 26;
      tester.view.physicalSize = const Size(466, 678);
      tester.view.devicePixelRatio = 1;
      tester.view.padding = const FakeViewPadding(right: 84);
      tester.view.viewPadding = const FakeViewPadding(right: 84);
      addTearDown(tester.view.reset);
    }

    Rect scaffoldOf(WidgetTester tester, String body) => tester.getRect(
      find
          .ancestor(
            of: find.byKey(ValueKey<String>(body)),
            matching: find.byType(Scaffold),
          )
          .first,
    );

    double titleBandShown(WidgetTester tester) => tester
        .widget<DuoTitleBandTransition>(
          find.byType(DuoTitleBandTransition).first,
        )
        .shown
        .value;

    testWidgets(
      'the title band moves out of the way while content scrolls on, and comes back with its background as soon as it scrolls back',
      (tester) async {
        cover(tester);
        final controller = ScrollController();
        addTearDown(controller.dispose);
        await tester.pumpWidget(
          MaterialApp(
            builder: (context, child) => AdaptiveToolbarHost(
              chrome: chrome,
              debugFold: duo(),
              child: child!,
            ),
            home: listPage('List', controller: controller),
          ),
        );
        await tester.pumpAndSettle();
        final list = find.byKey(const ValueKey<String>('list List'));
        expect(titleBandShown(tester), 1);

        await tester.drag(list, const Offset(0, -300));
        await tester.pumpAndSettle();
        expect(titleBandShown(tester), 0);
        expect(backdropOpacity(tester), 0);

        await tester.drag(list, const Offset(0, 40));
        await tester.pumpAndSettle();
        expect(titleBandShown(tester), 1);
        expect(backdropOpacity(tester), 1);

        await tester.drag(list, const Offset(0, -300));
        await tester.pumpAndSettle();
        expect(titleBandShown(tester), 0);
        controller.jumpTo(0);
        await tester.pumpAndSettle();
        expect(titleBandShown(tester), 1);
      },
    );

    testWidgets(
      'a page that keeps its bar has its title band stay as it scrolls on',
      (tester) async {
        cover(tester);
        await tester.pumpWidget(
          MaterialApp(
            builder: (context, child) => AdaptiveToolbarHost(
              chrome: chrome,
              debugFold: duo(),
              child: child!,
            ),
            home: AdaptiveScaffold(
              appBar: const AdaptiveAppBar(
                title: 'Docks',
                hidesOnScroll: false,
              ),
              body: ListView(
                key: const ValueKey<String>('docks'),
                children: [
                  for (var i = 0; i < 60; i++) const SizedBox(height: 60),
                ],
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        await tester.drag(
          find.byKey(const ValueKey<String>('docks')),
          const Offset(0, -300),
        );
        await tester.pumpAndSettle();
        expect(titleBandShown(tester), 1);
      },
    );

    testWidgets(
      'scrolling back the list of a scroll view with a header brings the title band back, also once the header is gone',
      (tester) async {
        cover(tester);
        await tester.pumpWidget(
          MaterialApp(
            builder: (context, child) => AdaptiveToolbarHost(
              chrome: chrome,
              debugFold: duo(),
              child: child!,
            ),
            home: AdaptiveScaffold(
              appBar: const AdaptiveAppBar(title: 'Nested'),
              body: NestedScrollView(
                headerSliverBuilder: (context, _) => const [
                  SliverToBoxAdapter(child: SizedBox(height: 200)),
                ],
                body: ListView(
                  key: const ValueKey<String>('inner'),
                  children: [
                    for (var i = 0; i < 60; i++) const SizedBox(height: 60),
                  ],
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final inner = find.byKey(const ValueKey<String>('inner'));

        await tester.drag(inner, const Offset(0, -600));
        await tester.pumpAndSettle();
        expect(titleBandShown(tester), 0);

        await tester.drag(inner, const Offset(0, 40));
        await tester.pumpAndSettle();
        expect(titleBandShown(tester), 1);
      },
    );

    testWidgets(
      'the title band stays where the page\'s content starts below it, with nothing of it to show there',
      (tester) async {
        cover(tester);
        await tester.pumpWidget(
          MaterialApp(
            builder: (context, child) => AdaptiveToolbarHost(
              chrome: chrome,
              debugFold: duo(),
              child: child!,
            ),
            home: AdaptiveScaffold(
              appBar: const AdaptiveAppBar(title: 'Below'),
              body: Padding(
                padding: const EdgeInsets.only(top: 120),
                child: ListView(
                  key: const ValueKey<String>('below'),
                  children: [
                    for (var i = 0; i < 60; i++) const SizedBox(height: 60),
                  ],
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        await tester.drag(
          find.byKey(const ValueKey<String>('below')),
          const Offset(0, -300),
        );
        await tester.pumpAndSettle();
        expect(titleBandShown(tester), 1);
      },
    );

    testWidgets(
      'a page inside a tab layout has its own background under the strip, with its content beside it',
      (tester) async {
        cover(tester);
        await tester.pumpWidget(
          MaterialApp(
            builder: (context, child) => AdaptiveToolbarHost(
              chrome: chrome,
              debugFold: duo(),
              child: child!,
            ),
            home: AdaptiveScaffold(
              backgroundColor: const Color(0xFF999999),
              bottomNavigationBar: AdaptiveBottomNavigationBar(
                items: const [
                  AdaptiveNavigationDestination(icon: Icons.circle, label: 'A'),
                  AdaptiveNavigationDestination(icon: Icons.circle, label: 'B'),
                ],
                selectedIndex: 0,
                onTap: (_) {},
              ),
              body: Navigator(
                onGenerateRoute: (_) => MaterialPageRoute<void>(
                  builder: (_) => AdaptiveScaffold(
                    backgroundColor: const Color(0xFFFFFFFF),
                    appBar: const AdaptiveAppBar(title: 'Tab'),
                    body: const SizedBox.expand(
                      key: ValueKey<String>('tab body'),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(scaffoldOf(tester, 'tab body').right, 466);
        expect(
          tester.getRect(find.byKey(const ValueKey<String>('tab body'))).right,
          466 - 84,
        );
      },
    );

    testWidgets(
      'a page that extends behind the bar runs under the strip, with the strip in its padding',
      (tester) async {
        cover(tester);
        late EdgeInsets padding;
        await tester.pumpWidget(
          MaterialApp(
            builder: (context, child) => AdaptiveToolbarHost(
              chrome: chrome,
              debugFold: duo(),
              child: child!,
            ),
            home: AdaptiveScaffold(
              extendBodyBehindVerticalBar: true,
              appBar: const AdaptiveAppBar(title: 'Header'),
              body: Builder(
                builder: (context) {
                  padding = MediaQuery.paddingOf(context);
                  return const SizedBox.expand(
                    key: ValueKey<String>('header body'),
                  );
                },
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(
          tester
              .getRect(find.byKey(const ValueKey<String>('header body')))
              .right,
          466,
        );
        expect(padding.right, 84);
      },
    );
  });
}
