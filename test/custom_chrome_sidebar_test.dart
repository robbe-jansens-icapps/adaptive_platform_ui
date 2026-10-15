import 'package:adaptive_platform_ui/adaptive_platform_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:adaptive_platform_ui/src/toolbar/toolbar_blend.dart' show kToolbarCoveredOpacity;

import 'custom_chrome_fixture.dart';

const landscape = Size(1180, 820);
const portrait = Size(834, 1194);

void main() {
  setUp(() {
    PlatformInfo.debugPlatformOverride = TargetPlatform.android;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform_views, (_) async => null);
  });

  tearDown(() {
    PlatformInfo.debugPlatformOverride = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform_views, null);
  });

  Future<TabsFixture> pumpTabs(
    WidgetTester tester,
    Size size, {
    bool hidesWhenPushed = true,
    AdaptiveChrome chrome = TestChrome.withSidebar,
    Color? pageColor,
    bool extendBody = false,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    tester.view.padding = const FakeViewPadding(top: 24, bottom: 20);
    tester.view.viewPadding = const FakeViewPadding(top: 24, bottom: 20);
    addTearDown(tester.view.reset);
    final tabs = TabsFixture(chrome: chrome, hidesWhenPushed: hidesWhenPushed, pageColor: pageColor, extendBody: extendBody);
    await tester.pumpWidget(tabs.app());
    await tester.pumpAndSettle();
    return tabs;
  }

  Rect body(WidgetTester tester, String title) => tester.getRect(find.byKey(ValueKey('body $title')));

  testWidgets('a wide window has the tabs in a sidebar at its full width, the pages and their bar beside it', (tester) async {
    final tabs = await pumpTabs(tester, landscape);

    expect(find.byKey(TestChrome.tabBarKey), findsNothing);
    expect(tester.getRect(find.byKey(TestChrome.sidebarKey)), const Rect.fromLTWH(0, 0, 300, 820));
    expect(TestChrome.lastSidebarSpec!.expanded, isTrue);
    expect(TestChrome.lastSidebarSpec!.padding.top, 24);
    expect(body(tester, 'Tab 0').left, 300);
    expect(tabs.paddingOf('Tab 0').bottom, 20);
    expect(tabs.insetOf('Tab 0'), 0);
    expect(tester.getRect(find.text('title:Tab 0')).left, greaterThan(300));
  });

  testWidgets('under a dialog the sidebar stays in sight, dimmed as the toolbar is', (tester) async {
    final tabs = await pumpTabs(tester, landscape);

    showDialog<void>(context: tabs.navigators[0].currentContext!, builder: (_) => const Text('dialog'));
    await tester.pumpAndSettle();

    final fades = tester.widgetList<FadeTransition>(find.ancestor(of: find.byKey(TestChrome.sidebarKey), matching: find.byType(FadeTransition)));
    final opacity = fades.fold<double>(1, (opacity, fade) => opacity * fade.opacity.value);
    expect(opacity, closeTo(kToolbarCoveredOpacity, 0.01));
  });

  testWidgets('a narrower one has a rail of icons, which the user can expand over the content', (tester) async {
    await pumpTabs(tester, portrait);

    expect(tester.getSize(find.byKey(TestChrome.sidebarKey)).width, 88);
    expect(TestChrome.lastSidebarSpec!.expanded, isFalse);
    expect(body(tester, 'Tab 0').left, 88);

    await tester.tap(find.text('toggle'));
    await tester.pumpAndSettle();
    expect(tester.getSize(find.byKey(TestChrome.sidebarKey)).width, 300);
    expect(TestChrome.lastSidebarSpec!.overlaid, isTrue);
    expect(body(tester, 'Tab 0').left, 88);

    await tester.tapAt(const Offset(600, 600));
    await tester.pumpAndSettle();
    expect(tester.getSize(find.byKey(TestChrome.sidebarKey)).width, 88);
    expect(TestChrome.lastSidebarSpec!.overlaid, isFalse);
  });

  testWidgets('picking a tab in a sidebar expanded over the content closes it', (tester) async {
    final tabs = await pumpTabs(tester, portrait);
    await tester.tap(find.text('toggle'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('side:Tab 1'));
    await tester.pumpAndSettle();

    expect(tabs.selected.value, 1);
    expect(tester.getSize(find.byKey(TestChrome.sidebarKey)).width, 88);
  });

  testWidgets('collapsing the full sidebar gives the pages its room', (tester) async {
    await pumpTabs(tester, landscape);

    await tester.tap(find.text('toggle'));
    await tester.pumpAndSettle();

    expect(tester.getSize(find.byKey(TestChrome.sidebarKey)).width, 88);
    expect(body(tester, 'Tab 0').left, 88);
  });

  testWidgets('the sidebar stays for a page pushed on a tab, even with hidesWhenPushed; the back button sits beside it', (tester) async {
    final tabs = await pumpTabs(tester, landscape);

    tabs.push(0, 'Detail');
    await tester.pumpAndSettle();

    expect(find.byKey(TestChrome.sidebarKey), findsOneWidget);
    expect(body(tester, 'Detail').left, 300);
    expect(tester.getRect(find.text('back')).left, greaterThanOrEqualTo(300 + 16));
    expect(tabs.paddingOf('Detail').bottom, 20);
  });

  testWidgets('a tab layout that hides its tabs hides the sidebar, and its pages take the room instead of keeping it empty', (tester) async {
    final tabs = await pumpTabs(tester, landscape);

    tabs.push(0, 'Detail');
    tabs.tabBarHidden.value = true;
    await tester.pumpAndSettle();

    expect(find.byKey(TestChrome.sidebarKey), findsNothing);
    expect(body(tester, 'Detail').left, 0);
    expect(tester.getRect(find.text('back')).left, lessThan(300));

    tabs.tabBarHidden.value = false;
    await tester.pumpAndSettle();

    expect(find.byKey(TestChrome.sidebarKey), findsOneWidget);
    expect(body(tester, 'Detail').left, 300);
  });

  testWidgets('the page runs on under the sidebar in its own colour, so no edge shows between them; its content keeps beside it', (tester) async {
    const pageColor = Color(0xFF123456);
    final tabs = await pumpTabs(tester, landscape, pageColor: pageColor);

    final background = find.byWidgetPredicate((widget) => widget is Scaffold && widget.backgroundColor == pageColor);
    expect(tester.getRect(background.first).left, 0);
    expect(body(tester, 'Tab 0').left, 300);
    expect(tabs.paddingOf('Tab 0').left, 0);
  });

  testWidgets('a page that runs its body under the sidebar lays it out there, and keeps clear through the padding', (tester) async {
    final tabs = await pumpTabs(tester, landscape, extendBody: true);

    expect(body(tester, 'Tab 0').left, 0);
    expect(tabs.paddingOf('Tab 0').left, 300);
  });

  testWidgets('a page pushed on a tab takes the room the same way; the pages inside it get none of it', (tester) async {
    final tabs = await pumpTabs(tester, landscape);
    double? innerLeft;
    tabs.navigators[0].currentState!.push(
      MaterialPageRoute<void>(
        builder: (_) => AdaptiveScaffold(
          appBar: const AdaptiveAppBar(title: 'Outer'),
          body: AdaptiveScaffold(
            body: Builder(
              builder: (context) {
                innerLeft = MediaQuery.paddingOf(context).left;
                return const SizedBox.expand(key: ValueKey('inner'));
              },
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.getRect(find.byKey(const ValueKey('inner'))).left, 300);
    expect(innerLeft, 0);
  });

  testWidgets('beside the sidebar a split view hands the room to its list, which runs under it; the column beside the list gets none', (tester) async {
    tester.view.physicalSize = const Size(1366, 1024);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final tabs = TabsFixture(chrome: TestChrome.withSidebar);
    await tester.pumpWidget(tabs.app());
    await tester.pumpAndSettle();
    EdgeInsets? detailPadding;
    tabs.navigators[0].currentState!.push(
      MaterialPageRoute<void>(
        builder: (_) => AdaptiveSplitView(
          initialDetail: const RouteSettings(name: '/detail'),
          onGenerateDetailRoute: (settings) => MaterialPageRoute<void>(
            settings: settings,
            builder: (_) => AdaptiveScaffold(
              body: Builder(
                builder: (context) {
                  detailPadding = MediaQuery.paddingOf(context);
                  return const SizedBox.expand(key: ValueKey('detail'));
                },
              ),
            ),
          ),
          master: const AdaptiveScaffold(backgroundColor: Color(0xFFABCDEF), body: SizedBox.expand(key: ValueKey('list'))),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final listBackground = find.byWidgetPredicate((widget) => widget is Scaffold && widget.backgroundColor == const Color(0xFFABCDEF));
    expect(tester.getRect(listBackground).left, 0);
    final list = tester.getRect(find.byKey(const ValueKey('list')));
    expect(list.left, 300);
    expect(list.width, greaterThanOrEqualTo(320));
    expect(tester.getRect(find.byKey(const ValueKey('detail'))).left, greaterThan(list.right));
    expect(detailPadding!.left, 0);
    final listSize = MediaQuery.sizeOf(tester.element(find.byKey(const ValueKey('list'))));
    expect(listSize.width, list.width);
  });

  testWidgets('a page over the whole tab layout has the window to itself', (tester) async {
    final tabs = await pumpTabs(tester, landscape);

    tabs.root.currentState!.push(tabs.page('Over'));
    await tester.pumpAndSettle();

    expect(find.byKey(TestChrome.sidebarKey), findsNothing);
    expect(body(tester, 'Over').left, 0);
    expect(tester.getRect(find.text('back')).left, lessThan(300));
  });

  testWidgets('narrowing the window moves the tabs to the bottom and back, keeping the pages', (tester) async {
    final tabs = await pumpTabs(tester, landscape);
    tabs.push(0, 'Detail');
    await tester.pumpAndSettle();
    final navigator = tabs.navigators[0].currentState;

    tester.view.physicalSize = const Size(600, 820);
    await tester.pumpAndSettle();
    expect(find.byKey(TestChrome.sidebarKey), findsNothing);
    expect(body(tester, 'Detail').left, 0);
    expect(identical(tabs.navigators[0].currentState, navigator), isTrue);

    tester.view.physicalSize = landscape;
    await tester.pumpAndSettle();
    expect(find.byKey(TestChrome.sidebarKey), findsOneWidget);
    expect(body(tester, 'Detail').left, 300);
    expect(identical(tabs.navigators[0].currentState, navigator), isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('without a sidebar builder the tabs stay at the bottom at any width', (tester) async {
    await pumpTabs(tester, landscape, chrome: TestChrome.chrome);

    expect(find.byKey(TestChrome.sidebarKey), findsNothing);
    expect(tester.getRect(find.byKey(TestChrome.tabBarKey)).bottom, 820);
  });
}
