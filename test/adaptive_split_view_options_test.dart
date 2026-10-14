import 'package:adaptive_platform_ui/adaptive_platform_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const narrow = Size(400, 800);
const wide = Size(1000, 800);

RouteSettings detail(String name) => RouteSettings(name: '/detail', arguments: name);

Route<dynamic>? onGenerateRoute(RouteSettings settings) {
  final name = settings.arguments! as String;
  return MaterialPageRoute<void>(
    settings: settings,
    builder: (context) => Scaffold(
      body: Column(
        children: [
          Text('Detail $name'),
          TextButton(onPressed: () => open(context, detail('$name+')), child: Text('More $name')),
        ],
      ),
    ),
  );
}

/// What an app's navigation code does: the split view first, else a page
/// of its own on the navigator of the page asking.
void open(BuildContext context, RouteSettings settings) {
  if (AdaptiveSplitView.showDetail(settings)) return;
  Navigator.of(context).push(onGenerateRoute(settings)!);
}

Widget master(String tab) => Scaffold(
  body: Builder(
    builder: (context) {
      final opened = AdaptiveSplitView.selectedDetailOf(context)?.arguments;
      return ListView(
        children: [
          for (final name in ['A', 'B', 'C'])
            ListTile(title: Text('$tab $name'), selected: opened == name, onTap: () => open(context, detail(name))),
        ],
      );
    },
  ),
);

/// Tabs as an app can build them without `Visibility`: every tab is laid
/// out, the ones out of sight faded out with their tickers off, each with a
/// navigator of its own.
class FadingTabs extends StatelessWidget {
  const FadingTabs({super.key, required this.selected, required this.navigators, required this.tabs});

  final int selected;
  final List<GlobalKey<NavigatorState>> navigators;
  final List<Widget> tabs;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        for (var i = 0; i < tabs.length; i++)
          Opacity(
            opacity: i == selected ? 1 : 0,
            child: IgnorePointer(
              ignoring: i != selected,
              child: TickerMode(
                enabled: i == selected,
                child: Navigator(
                  key: navigators[i],
                  onGenerateRoute: (settings) => MaterialPageRoute<void>(settings: settings, builder: (_) => tabs[i]),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

void main() {
  void setSize(WidgetTester tester, Size size) {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  group('a tab hidden by its tickers', () {
    late List<GlobalKey<NavigatorState>> navigators;
    late ValueNotifier<int> tab;

    Future<void> pumpTabs(WidgetTester tester) async {
      navigators = [GlobalKey<NavigatorState>(), GlobalKey<NavigatorState>()];
      tab = ValueNotifier(1);
      addTearDown(tab.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: ValueListenableBuilder<int>(
            valueListenable: tab,
            builder: (context, index, _) => FadingTabs(
              selected: index,
              navigators: navigators,
              tabs: [
                AdaptiveSplitView(onGenerateDetailRoute: onGenerateRoute, master: master('Zero')),
                AdaptiveSplitView(onGenerateDetailRoute: onGenerateRoute, initialDetail: detail('A'), master: master('One')),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('keeps the pages a fold moves over its list until it is selected again', (tester) async {
      setSize(tester, wide);
      await pumpTabs(tester);
      await tester.tap(find.text('More A'));
      await tester.pumpAndSettle();

      tab.value = 0;
      await tester.pumpAndSettle();
      tester.view.physicalSize = narrow;
      await tester.pumpAndSettle();
      expect(navigators[1].currentState!.canPop(), isFalse);

      tab.value = 1;
      await tester.pumpAndSettle();
      expect(navigators[1].currentState!.canPop(), isTrue);
      expect(find.text('Detail A+'), findsOneWidget);
    });

    testWidgets('takes no pages: the split view of the tab in sight does', (tester) async {
      setSize(tester, narrow);
      await pumpTabs(tester);
      await tester.tap(find.text('One B'));
      await tester.pumpAndSettle();
      expect(navigators[1].currentState!.canPop(), isTrue);

      tab.value = 0;
      await tester.pumpAndSettle();
      await tester.tap(find.text('Zero C'));
      await tester.pumpAndSettle();

      expect(navigators[0].currentState!.canPop(), isTrue);
      navigators[1].currentState!.pop();
      await tester.pumpAndSettle();
      expect(navigators[1].currentState!.canPop(), isFalse);
    });
  });

  group('showsDetailColumn', () {
    final navigatorKey = GlobalKey<NavigatorState>();
    late ValueNotifier<bool> showsColumn;

    Future<void> pumpSplit(WidgetTester tester, Size size) async {
      setSize(tester, size);
      showsColumn = ValueNotifier(true);
      addTearDown(showsColumn.dispose);
      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: navigatorKey,
          home: ValueListenableBuilder<bool>(
            valueListenable: showsColumn,
            builder: (context, shows, _) => AdaptiveSplitView(
              onGenerateDetailRoute: onGenerateRoute,
              initialDetail: detail('A'),
              showsDetailColumn: shows,
              master: master('List'),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('false keeps the list at the full width of a wide window, and pages open over it', (tester) async {
      await pumpSplit(tester, wide);
      showsColumn.value = false;
      await tester.pumpAndSettle();

      expect(find.text('Detail A'), findsNothing);
      expect(tester.getSize(find.byType(ListView)).width, wide.width);

      await tester.tap(find.text('List B'));
      await tester.pumpAndSettle();
      expect(find.text('Detail B'), findsOneWidget);
      expect(find.text('List B'), findsNothing);
      expect(navigatorKey.currentState!.canPop(), isTrue);
    });

    testWidgets('puts the pages of the column away and brings them back with it, never over the list', (tester) async {
      await pumpSplit(tester, wide);
      await tester.tap(find.text('List B'));
      await tester.pump();
      await tester.tap(find.text('More B'));
      await tester.pumpAndSettle();

      showsColumn.value = false;
      await tester.pumpAndSettle();
      expect(find.text('Detail B+'), findsNothing);
      expect(navigatorKey.currentState!.canPop(), isFalse);

      showsColumn.value = true;
      await tester.pumpAndSettle();
      expect(find.text('Detail B+'), findsOneWidget);
      expect(find.text('List A'), findsOneWidget);
      final opened = tester.widget<ListTile>(find.widgetWithText(ListTile, 'List B'));
      expect(opened.selected, isTrue);
    });

    testWidgets('a page opened while the column is away replaces the pages put away', (tester) async {
      await pumpSplit(tester, wide);
      await tester.tap(find.text('List B'));
      await tester.pump();

      showsColumn.value = false;
      await tester.pumpAndSettle();
      await tester.tap(find.text('List C'));
      await tester.pumpAndSettle();
      expect(find.text('Detail C'), findsOneWidget);

      showsColumn.value = true;
      await tester.pumpAndSettle();
      expect(find.text('Detail C'), findsOneWidget);
      expect(find.text('Detail B'), findsNothing);
      expect(navigatorKey.currentState!.canPop(), isFalse);
    });
  });

  group('onPushedOver', () {
    final navigatorKey = GlobalKey<NavigatorState>();
    late List<Route<dynamic>> pushed;

    Future<void> pumpSplit(WidgetTester tester, Size size) async {
      setSize(tester, size);
      pushed = [];
      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: navigatorKey,
          home: AdaptiveSplitView(
            onGenerateDetailRoute: onGenerateRoute,
            initialDetail: detail('A'),
            onPushedOver: pushed.add,
            master: master('List'),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('hears of a page opened over the list on a narrow window', (tester) async {
      await pumpSplit(tester, narrow);
      await tester.tap(find.text('List B'));
      await tester.pumpAndSettle();

      expect(pushed, hasLength(1));
      expect(pushed.single.settings.arguments, 'B');
      expect(pushed.single.isCurrent, isTrue);
    });

    testWidgets('hears of the pages that move over the list as the window narrows', (tester) async {
      await pumpSplit(tester, wide);
      await tester.tap(find.text('List B'));
      await tester.pump();
      await tester.tap(find.text('More B'));
      await tester.pumpAndSettle();
      expect(pushed, isEmpty);

      tester.view.physicalSize = narrow;
      await tester.pumpAndSettle();

      expect([for (final route in pushed) route.settings.arguments], ['B', 'B+']);
      expect(pushed.last.isCurrent, isTrue);
    });

    testWidgets('hears of nothing that opens in the column', (tester) async {
      await pumpSplit(tester, wide);
      await tester.tap(find.text('List C'));
      await tester.pump();
      await tester.tap(find.text('More C'));
      await tester.pumpAndSettle();

      expect(pushed, isEmpty);
    });
  });
}
