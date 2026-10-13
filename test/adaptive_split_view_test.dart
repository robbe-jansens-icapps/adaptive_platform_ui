import 'package:adaptive_platform_ui/adaptive_platform_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const narrow = Size(400, 800);
const wide = Size(1000, 800);

final navigatorKey = GlobalKey<NavigatorState>();
var contexts = <String, BuildContext>{};

RouteSettings detail(String name) => RouteSettings(name: '/detail', arguments: name);

/// Whether the pages are adaptive scaffolds with a bar, rather than plain.
var adaptivePages = false;

Route<dynamic>? onGenerateRoute(RouteSettings settings) {
  final name = settings.arguments! as String;
  return MaterialPageRoute<void>(
    settings: settings,
    builder: (context) {
      contexts['Detail $name'] = context;
      if (adaptivePages) {
        return AdaptiveScaffold(
          appBar: AdaptiveAppBar(useNativeToolbar: true, title: 'Detail $name', onBack: goBack, automaticallyImplyLeading: false),
          // Clear of the bar over the top of the page.
          body: Center(
            child: TextButton(onPressed: () => open(detail('$name+')), child: Text('More $name')),
          ),
        );
      }
      return Scaffold(
        body: Column(
          children: [
            Text('Detail $name'),
            TextButton(onPressed: () => open(detail('$name+')), child: Text('More $name')),
          ],
        ),
      );
    },
  );
}

/// What an app's navigation code does: the split view first, else a page
/// of its own.
void open(RouteSettings settings) {
  if (AdaptiveSplitView.showDetail(settings)) return;
  navigatorKey.currentState!.push(onGenerateRoute(settings)!);
}

/// A navigation code's "go back": a pop of the app's navigator.
void goBack() => navigatorKey.currentState!.pop();

Widget master() => Scaffold(
  body: Builder(
    builder: (context) {
      contexts['master'] = context;
      final opened = AdaptiveSplitView.selectedDetailOf(context)?.arguments;
      return ListView(
        children: [
          for (final name in ['A', 'B', 'C']) ListTile(title: Text('Item $name'), selected: opened == name, onTap: () => open(detail(name))),
        ],
      );
    },
  ),
);

void main() {
  setUp(() {
    contexts = {};
    adaptivePages = false;
  });

  Future<void> pumpSplit(WidgetTester tester, Size size) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigatorKey,
        home: AdaptiveSplitView(onGenerateDetailRoute: onGenerateRoute, initialDetail: detail('A'), master: master()),
      ),
    );
    await tester.pumpAndSettle();
  }

  bool isSelected(WidgetTester tester, String name) => tester.widget<ListTile>(find.widgetWithText(ListTile, 'Item $name')).selected;

  testWidgets('on a narrow window only the list shows, and pages open over '
      'it', (tester) async {
    await pumpSplit(tester, narrow);
    expect(find.text('Detail A'), findsNothing);

    await tester.tap(find.text('Item B'));
    await tester.pumpAndSettle();

    expect(find.text('Detail B'), findsOneWidget);
    expect(find.text('Item B'), findsNothing);
  });

  testWidgets('on a wide window the first page shows beside the list, '
      'which shows it open', (tester) async {
    await pumpSplit(tester, wide);

    final list = tester.getRect(find.text('Item A'));
    final page = tester.getRect(find.text('Detail A'));
    expect(page.left, greaterThan(list.right));
    expect(isSelected(tester, 'A'), isTrue);
  });

  testWidgets('a page picked in the list replaces the one beside it at once', (tester) async {
    await pumpSplit(tester, wide);

    await tester.tap(find.text('Item B'));
    await tester.pump();

    expect(find.text('Detail B'), findsOneWidget);
    expect(find.text('Detail A'), findsNothing);
    expect(isSelected(tester, 'B'), isTrue);
    expect(isSelected(tester, 'A'), isFalse);
  });

  testWidgets('a page opened from the column goes on top of it, and going '
      'back goes back in the column', (tester) async {
    await pumpSplit(tester, wide);
    await tester.tap(find.text('Item B'));
    await tester.pump();

    await tester.tap(find.text('More B'));
    await tester.pumpAndSettle();
    expect(find.text('Detail B+'), findsOneWidget);
    expect(find.text('Item A'), findsOneWidget);

    goBack();
    await tester.pumpAndSettle();

    expect(find.text('Detail B+'), findsNothing);
    expect(find.text('Detail B'), findsOneWidget);
    expect(find.text('Item A'), findsOneWidget);
  });

  testWidgets('only the first page beside the list goes without a back '
      'button', (tester) async {
    await pumpSplit(tester, wide);
    expect(AdaptiveSplitView.hidesBackButton(contexts['Detail A']!), isTrue);

    await tester.tap(find.text('More A'));
    await tester.pumpAndSettle();

    expect(AdaptiveSplitView.hidesBackButton(contexts['Detail A+']!), isFalse);
    expect(AdaptiveSplitView.hidesBackButton(contexts['master']!), isFalse);
  });

  testWidgets('pages in its columns keep their own bars', (tester) async {
    await pumpSplit(tester, wide);

    expect(AdaptiveSplitView.isInColumn(contexts['master']!), isTrue);
    expect(AdaptiveSplitView.isInColumn(contexts['Detail A']!), isTrue);
  });

  testWidgets('a narrowing window keeps the pages picked in the list on '
      'screen', (tester) async {
    await pumpSplit(tester, wide);
    await tester.tap(find.text('Item B'));
    await tester.pump();
    await tester.tap(find.text('More B'));
    await tester.pumpAndSettle();

    tester.view.physicalSize = narrow;
    await tester.pumpAndSettle();

    expect(find.text('Detail B+'), findsOneWidget);
    goBack();
    await tester.pumpAndSettle();
    expect(find.text('Detail B'), findsOneWidget);
    goBack();
    await tester.pumpAndSettle();
    expect(find.text('Item B'), findsOneWidget);
  });

  testWidgets('a widening window lands where the user was: the pages open '
      'over the list move beside it, as deep as they were', (tester) async {
    await pumpSplit(tester, narrow);
    await tester.tap(find.text('Item B'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('More B'));
    await tester.pumpAndSettle();

    tester.view.physicalSize = wide;
    await tester.pumpAndSettle();

    expect(find.text('Detail B+'), findsOneWidget);
    expect(find.text('Item A'), findsOneWidget);
    // ignore: avoid_print
    print(
      'DEBUG selected=${AdaptiveSplitView.selectedDetailOf(contexts['master']!)?.arguments} tiles=${tester.widgetList<ListTile>(find.byType(ListTile)).map((t) => t.selected).toList()}',
    );
    expect(isSelected(tester, 'B'), isTrue);
    expect(AdaptiveSplitView.isInColumn(contexts['Detail B+']!), isTrue, reason: 'in the column, not over the list');

    goBack();
    await tester.pumpAndSettle();
    expect(find.text('Detail B'), findsOneWidget);
    expect(find.text('Item A'), findsOneWidget);
  });

  testWidgets('folding and unfolding again lands where the user was', (tester) async {
    await pumpSplit(tester, wide);
    await tester.tap(find.text('Item C'));
    await tester.pump();
    await tester.tap(find.text('More C'));
    await tester.pumpAndSettle();

    tester.view.physicalSize = narrow;
    await tester.pumpAndSettle();
    expect(find.text('Detail C+'), findsOneWidget);
    expect(find.text('Item C'), findsNothing);

    tester.view.physicalSize = wide;
    await tester.pumpAndSettle();
    expect(find.text('Detail C+'), findsOneWidget);
    expect(find.text('Item A'), findsOneWidget);
    expect(isSelected(tester, 'C'), isTrue);
  });

  testWidgets('a window that narrows again on its way, as a fold can, still '
      'lands where the user was, the list showing it', (tester) async {
    await pumpSplit(tester, narrow);
    await tester.tap(find.text('Item B'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('More B'));
    await tester.pumpAndSettle();

    tester.view.physicalSize = wide;
    await tester.pump();
    tester.view.physicalSize = const Size(600, 800);
    await tester.pump();
    tester.view.physicalSize = wide;
    await tester.pumpAndSettle();

    expect(find.text('Detail B+'), findsOneWidget);
    expect(find.text('Item A'), findsOneWidget);
    expect(isSelected(tester, 'B'), isTrue);
    expect(isSelected(tester, 'A'), isFalse);
  });

  testWidgets('folding keeps the pages opened from the page shown first', (tester) async {
    await pumpSplit(tester, wide);
    await tester.tap(find.text('More A'));
    await tester.pumpAndSettle();

    tester.view.physicalSize = narrow;
    await tester.pumpAndSettle();
    expect(find.text('Detail A+'), findsOneWidget);

    tester.view.physicalSize = wide;
    await tester.pumpAndSettle();
    expect(find.text('Detail A+'), findsOneWidget);
    expect(isSelected(tester, 'A'), isTrue);
  });

  testWidgets('a page the user left on the narrow window does not come back '
      'as the window widens: the page shown first does', (tester) async {
    await pumpSplit(tester, narrow);
    await tester.tap(find.text('Item B'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('More B'));
    await tester.pumpAndSettle();
    goBack();
    await tester.pumpAndSettle();
    goBack();
    await tester.pumpAndSettle();
    expect(find.text('Item B'), findsOneWidget);

    tester.view.physicalSize = wide;
    await tester.pumpAndSettle();

    expect(find.text('Detail A'), findsOneWidget);
    expect(find.text('Detail B'), findsNothing);
    expect(find.text('Detail B+'), findsNothing);
    expect(isSelected(tester, 'A'), isTrue);
    expect(isSelected(tester, 'B'), isFalse);
  });

  testWidgets('shows the page shown first as open, also when it arrives with '
      'the list after the column', (tester) async {
    tester.view.physicalSize = wide;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    Widget app(RouteSettings? initial) => MaterialApp(
      navigatorKey: navigatorKey,
      home: AdaptiveSplitView(onGenerateDetailRoute: onGenerateRoute, initialDetail: initial, master: master()),
    );
    await tester.pumpWidget(app(null));
    await tester.pumpAndSettle();
    expect(find.text('Detail A'), findsNothing);

    await tester.pumpWidget(app(detail('A')));
    await tester.pumpAndSettle();

    expect(find.text('Detail A'), findsOneWidget);
    expect(isSelected(tester, 'A'), isTrue);
  });

  testWidgets('tells its list apart from the column beside it', (tester) async {
    await pumpSplit(tester, wide);
    expect(AdaptiveSplitView.isInList(contexts['master']!), isTrue);
    expect(AdaptiveSplitView.isInList(contexts['Detail A']!), isFalse);

    tester.view.physicalSize = narrow;
    await tester.pumpAndSettle();
    expect(AdaptiveSplitView.isInList(contexts['master']!), isFalse);
  });

  testWidgets('takes no pages while another page covers it', (tester) async {
    await pumpSplit(tester, wide);
    navigatorKey.currentState!.push(MaterialPageRoute<void>(builder: (_) => const Text('Over it')));
    await tester.pumpAndSettle();

    expect(AdaptiveSplitView.showDetail(detail('C')), isFalse);
  });

  testWidgets('folding on another tab leaves that tab in view; the pages wait '
      'over the list until its tab is selected again', (tester) async {
    tester.view.physicalSize = wide;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final tab = ValueNotifier(1);
    addTearDown(tab.dispose);
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigatorKey,
        home: ValueListenableBuilder<int>(
          valueListenable: tab,
          builder: (context, index, _) => IndexedStack(
            index: index,
            children: [
              const Center(child: Text('Map')),
              AdaptiveSplitView(onGenerateDetailRoute: onGenerateRoute, initialDetail: detail('A'), master: master()),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('More A'));
    await tester.pumpAndSettle();

    tab.value = 0;
    await tester.pumpAndSettle();
    tester.view.physicalSize = narrow;
    await tester.pumpAndSettle();
    expect(navigatorKey.currentState!.canPop(), isFalse);
    expect(find.text('Map'), findsOneWidget);

    tab.value = 1;
    await tester.pumpAndSettle();
    expect(find.text('Detail A+'), findsOneWidget);
    goBack();
    await tester.pumpAndSettle();
    expect(find.text('Detail A'), findsOneWidget);
    goBack();
    await tester.pumpAndSettle();
    expect(find.text('Item A'), findsOneWidget);
  });

  testWidgets('going back from the list closes its page, also with a page '
      'open on top in the column', (tester) async {
    tester.view.physicalSize = wide;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(navigatorKey: navigatorKey, home: const Text('Home')));
    navigatorKey.currentState!.push(
      MaterialPageRoute<void>(
        builder: (_) => AdaptiveSplitView(onGenerateDetailRoute: onGenerateRoute, initialDetail: detail('A'), master: master()),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('More A'));
    await tester.pumpAndSettle();

    AdaptiveSplitView.willGoBackFrom(contexts['master']!);
    goBack();
    await tester.pumpAndSettle();

    expect(find.text('Home'), findsOneWidget);
    expect(find.text('Item A'), findsNothing);
  });

  group('on iOS 26', () {
    setUp(() {
      PlatformInfo.debugPlatformOverride = TargetPlatform.iOS;
      PlatformInfo.debugIOSVersionOverride = 26;
      // Its native views are created as if there were UIKit.
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform_views, (call) async => null);
      adaptivePages = true;
    });
    tearDown(() {
      PlatformInfo.debugPlatformOverride = null;
      PlatformInfo.debugIOSVersionOverride = null;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform_views, null);
    });

    Finder backIn(String page) => find.descendant(
      of: find.byWidgetPredicate((widget) => widget is AdaptiveScaffold && widget.appBar?.title == 'Detail $page'),
      matching: find.byWidgetPredicate((widget) => widget is AdaptiveButton && widget.sfSymbol?.name == 'chevron.left'),
    );

    testWidgets('the first page beside the list has no back button; a page '
        'opened from it has its own, which goes back in the column', (tester) async {
      await pumpSplit(tester, wide);
      expect(backIn('A'), findsNothing);

      await tester.tap(find.text('More A'));
      await tester.pumpAndSettle();
      // ignore: avoid_print
      print(
        'DEBUG buttons: ${tester.widgetList<AdaptiveButton>(find.byType(AdaptiveButton)).map((b) => b.sfSymbol?.name).toList()} scaffolds: ${tester.widgetList<AdaptiveScaffold>(find.byType(AdaptiveScaffold)).map((s) => s.appBar?.title).toList()}',
      );
      expect(backIn('A+'), findsOneWidget);

      await tester.tap(backIn('A+'));
      await tester.pumpAndSettle();
      expect(find.text('More A+'), findsNothing);
      expect(find.text('More A'), findsOneWidget);
    }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));

    testWidgets('a page shown like a dialog has a cross that calls its '
        'handler', (tester) async {
      tester.view.physicalSize = narrow;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      var closed = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: AdaptiveScaffold(
            useFixedToolbar: false,
            appBar: AdaptiveAppBar(
              useNativeToolbar: true,
              title: 'Support',
              onBack: () => closed++,
              backButtonStyle: AdaptiveBackButtonStyle.close,
              automaticallyImplyLeading: false,
            ),
            body: const SizedBox.expand(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final cross = find.byWidgetPredicate((widget) => widget is AdaptiveButton && widget.sfSymbol?.name == 'xmark');
      expect(cross, findsOneWidget);
      await tester.tap(cross);
      expect(closed, 1);
    }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));
  });
}
