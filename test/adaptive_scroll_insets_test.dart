import 'package:adaptive_platform_ui/adaptive_platform_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const top = 100.0;
  const bottom = 50.0;
  const screen = Size(400, 800);

  void useScreen(WidgetTester tester) {
    tester.view.physicalSize = screen;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  Widget rows(int count) => Column(
    children: [
      for (var i = 0; i < count; i++)
        SizedBox(key: ValueKey(i), height: 100, child: Text('row $i')),
    ],
  );

  Future<void> pumpInsets(
    WidgetTester tester,
    Widget scrollView, {
    double top = top,
    double bottom = bottom,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AdaptiveScrollInsets(
            top: top,
            bottom: bottom,
            child: scrollView,
          ),
        ),
      ),
    );
  }

  double topOf(WidgetTester tester, int row) =>
      tester.getTopLeft(find.byKey(ValueKey(row))).dy;

  double bottomOf(WidgetTester tester, int row) =>
      tester.getBottomLeft(find.byKey(ValueKey(row))).dy;

  testWidgets('rests below the top bar, whatever padding the list has', (
    tester,
  ) async {
    useScreen(tester);
    await pumpInsets(
      tester,
      ListView(padding: const EdgeInsets.all(16), children: [rows(20)]),
    );

    expect(topOf(tester, 0), top + 16);
  });

  testWidgets('takes new insets on a page that was never laid out, as one '
      'that comes in covered by another', (tester) async {
    useScreen(tester);
    final insetTop = ValueNotifier(top);
    addTearDown(insetTop.dispose);
    final navigator = GlobalKey<NavigatorState>();
    Route<void> atOnce(Widget page) => PageRouteBuilder<void>(
      pageBuilder: (_, _, _) => page,
      transitionDuration: Duration.zero,
    );
    await tester.pumpWidget(
      MaterialApp(navigatorKey: navigator, home: const Text('home')),
    );
    navigator.currentState!
      ..push(
        atOnce(
          ValueListenableBuilder<double>(
            valueListenable: insetTop,
            builder: (context, top, _) => AdaptiveScrollInsets(
              top: top,
              bottom: bottom,
              child: ListView(children: [rows(20)]),
            ),
          ),
        ),
      )
      ..push(atOnce(const ColoredBox(color: Colors.white)));
    await tester.pump();

    insetTop.value = top + 20;
    await tester.pump();

    expect(tester.takeException(), isNull);
    navigator.currentState!.pop();
    await tester.pumpAndSettle();
    expect(topOf(tester, 0), top + 20);
  });

  testWidgets('scrolls its content under the top bar', (tester) async {
    useScreen(tester);
    await pumpInsets(tester, ListView(children: [rows(20)]));

    await tester.drag(find.byType(ListView), const Offset(0, -300));
    await tester.pumpAndSettle();

    expect(topOf(tester, 0), lessThan(top));
  });

  testWidgets('scrolls the end of its content clear of the bottom bar', (
    tester,
  ) async {
    useScreen(tester);
    await pumpInsets(
      tester,
      ListView(
        padding: const EdgeInsets.only(bottom: 16),
        children: [rows(20)],
      ),
    );

    await tester.fling(find.byType(ListView), const Offset(0, -5000), 5000);
    await tester.pumpAndSettle();

    expect(bottomOf(tester, 19), screen.height - bottom - 16);
  });

  testWidgets('content that fits between the bars does not scroll', (
    tester,
  ) async {
    useScreen(tester);
    await pumpInsets(tester, ListView(children: [rows(3)]));

    await tester.drag(find.byType(ListView), const Offset(0, -200));
    await tester.pumpAndSettle();

    expect(topOf(tester, 0), top);
  });

  testWidgets(
    'content that fits the screen but reaches under the bars scrolls just enough',
    (tester) async {
      useScreen(tester);
      // 700 high: under the bottom bar once moved down below the top bar.
      await pumpInsets(tester, ListView(children: [rows(7)]));
      expect(bottomOf(tester, 6), top + 700);

      await tester.drag(find.byType(ListView), const Offset(0, -400));
      await tester.pumpAndSettle();

      expect(bottomOf(tester, 6), screen.height - bottom);
    },
  );

  testWidgets('works for a shrink-wrapped list given all the room', (
    tester,
  ) async {
    useScreen(tester);
    await pumpInsets(
      tester,
      ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.all(16),
        children: [rows(20)],
      ),
    );
    expect(topOf(tester, 0), top + 16);

    await tester.drag(find.byType(ListView), const Offset(0, -300));
    await tester.pumpAndSettle();
    expect(topOf(tester, 0), lessThan(top));

    await tester.fling(find.byType(ListView), const Offset(0, -5000), 5000);
    await tester.pumpAndSettle();
    expect(bottomOf(tester, 19), screen.height - bottom - 16);
  });

  testWidgets('works for a custom scroll view', (tester) async {
    useScreen(tester);
    await pumpInsets(
      tester,
      CustomScrollView(slivers: [SliverToBoxAdapter(child: rows(7))]),
    );
    expect(topOf(tester, 0), top);

    await tester.drag(find.byType(CustomScrollView), const Offset(0, -400));
    await tester.pumpAndSettle();

    expect(bottomOf(tester, 6), screen.height - bottom);
  });

  testWidgets(
    'a page that rests at its top stays there when the insets change',
    (tester) async {
      useScreen(tester);
      await pumpInsets(tester, ListView(children: [rows(20)]));

      await pumpInsets(tester, ListView(children: [rows(20)]), top: 160);
      await tester.pump();

      expect(topOf(tester, 0), 160);
    },
  );

  test(
    'applies to vertical scroll views that scroll with the primary controller',
    () {
      expect(AdaptiveScrollInsets.appliesTo(ListView()), isTrue);
      expect(
        AdaptiveScrollInsets.appliesTo(
          ListView.builder(itemBuilder: (_, _) => null),
        ),
        isTrue,
      );
      expect(AdaptiveScrollInsets.appliesTo(const CustomScrollView()), isTrue);

      expect(
        AdaptiveScrollInsets.appliesTo(
          ListView(controller: ScrollController()),
        ),
        isFalse,
      );
      expect(AdaptiveScrollInsets.appliesTo(ListView(primary: false)), isFalse);
      expect(
        AdaptiveScrollInsets.appliesTo(
          ListView(scrollDirection: Axis.horizontal),
        ),
        isFalse,
      );
      expect(
        AdaptiveScrollInsets.appliesTo(ListView(shrinkWrap: true)),
        isTrue,
      );
      expect(
        AdaptiveScrollInsets.appliesTo(const SingleChildScrollView()),
        isFalse,
      );
      expect(AdaptiveScrollInsets.appliesTo(const Column()), isFalse);
    },
  );

  test('looks through wrappers to a scroll view at the top', () {
    final list = ListView();
    expect(AdaptiveScrollInsets.appliesTo(SafeArea(child: list)), isTrue);
    expect(
      AdaptiveScrollInsets.appliesTo(
        Padding(padding: const EdgeInsets.all(16), child: list),
      ),
      isTrue,
    );
    expect(
      AdaptiveScrollInsets.appliesTo(
        ScrollConfiguration(behavior: const ScrollBehavior(), child: list),
      ),
      isTrue,
    );
    expect(
      AdaptiveScrollInsets.appliesTo(
        Column(
          children: [
            Expanded(child: list),
            const SizedBox(height: 60),
          ],
        ),
      ),
      isTrue,
    );
    expect(
      AdaptiveScrollInsets.appliesTo(
        SafeArea(
          child: Column(
            children: [
              Expanded(
                child: Padding(padding: EdgeInsets.zero, child: list),
              ),
            ],
          ),
        ),
      ),
      isTrue,
    );

    // A header above the list, or a list that is not at the top.
    expect(
      AdaptiveScrollInsets.appliesTo(
        Column(
          children: [
            const SizedBox(height: 60),
            Expanded(child: list),
          ],
        ),
      ),
      isFalse,
    );
    expect(
      AdaptiveScrollInsets.appliesTo(
        Column(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [Expanded(child: list)],
        ),
      ),
      isFalse,
    );
    expect(AdaptiveScrollInsets.appliesTo(Center(child: list)), isFalse);
    expect(
      AdaptiveScrollInsets.appliesTo(Builder(builder: (_) => list)),
      isFalse,
    );
    expect(
      AdaptiveScrollInsets.appliesTo(
        Column(children: [Expanded(child: SingleChildScrollView())]),
      ),
      isFalse,
    );
  });

  testWidgets(
    'a list below a column header of nothing still rests below the bar',
    (tester) async {
      useScreen(tester);
      await pumpInsets(
        tester,
        Column(
          children: [
            Expanded(child: ListView(children: [rows(20)])),
            const SizedBox(height: 60),
          ],
        ),
      );

      expect(topOf(tester, 0), top);
      await tester.drag(find.byType(ListView), const Offset(0, -300));
      await tester.pump();
      // Under the bar now.
      expect(topOf(tester, 0), lessThan(top));
    },
  );
}
