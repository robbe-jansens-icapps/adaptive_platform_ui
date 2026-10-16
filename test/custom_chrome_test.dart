import 'package:adaptive_platform_ui/adaptive_platform_ui.dart';
import 'package:flutter/cupertino.dart' show CupertinoNavigationBar;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'custom_chrome_fixture.dart';

void main() {
  late List<MethodCall> platformViews;

  setUp(() {
    PlatformInfo.debugPlatformOverride = TargetPlatform.android;
    platformViews = [];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform_views, (call) async {
      platformViews.add(call);
      return null;
    });
  });

  tearDown(() {
    PlatformInfo.debugPlatformOverride = null;
    PlatformInfo.debugIOSVersionOverride = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform_views, null);
  });

  void phone(WidgetTester tester) {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    tester.view.padding = const FakeViewPadding(top: 47, bottom: 34);
    tester.view.viewPadding = const FakeViewPadding(top: 47, bottom: 34);
    addTearDown(tester.view.reset);
  }

  testWidgets('draws the app\'s tab bar and toolbar on Android, without a platform view', (tester) async {
    phone(tester);
    final tabs = TabsFixture();
    await tester.pumpWidget(tabs.app());
    await tester.pumpAndSettle();

    expect(find.text('title:Tab 0'), findsOneWidget);
    expect(find.byKey(TestChrome.tabBarKey), findsOneWidget);
    expect(find.text('tab:Tab 0*'), findsOneWidget);
    expect(find.text('tab:Tab 1'), findsOneWidget);
    expect(tester.getRect(find.byKey(TestChrome.tabBarKey)).bottom, 844);
    expect(platformViews.where((call) => call.method == 'create'), isEmpty);
  });

  testWidgets('also on iOS 18, where there would be no native bars', (tester) async {
    phone(tester);
    PlatformInfo.debugPlatformOverride = TargetPlatform.iOS;
    PlatformInfo.debugIOSVersionOverride = 18;
    final tabs = TabsFixture();
    await tester.pumpWidget(tabs.app());
    await tester.pumpAndSettle();

    expect(find.text('title:Tab 0'), findsOneWidget);
    expect(find.byKey(TestChrome.tabBarKey), findsOneWidget);
    expect(find.byType(CupertinoNavigationBar), findsNothing);
  });

  testWidgets('pages keep their content clear of the bars, and run underneath them', (tester) async {
    phone(tester);
    final tabs = TabsFixture();
    await tester.pumpWidget(tabs.app());
    await tester.pumpAndSettle();

    final padding = tabs.paddingOf('Tab 0');
    expect(padding.top, 47 + kHostedToolbarHeight);
    expect(padding.bottom, TestChrome.tabBarHeight);
    expect(tabs.insetOf('Tab 0'), TestChrome.tabBarHeight);
    expect(tester.getTopLeft(find.byKey(const ValueKey('body Tab 0'))).dy, 0);
  });

  testWidgets('switching tabs keeps the bar and shows the new tab\'s title', (tester) async {
    phone(tester);
    final tabs = TabsFixture();
    await tester.pumpWidget(tabs.app());
    await tester.pumpAndSettle();

    await tester.tap(find.text('tab:Tab 1'));
    await tester.pumpAndSettle();

    expect(find.text('title:Tab 1'), findsOneWidget);
    expect(find.text('title:Tab 0'), findsNothing);
    expect(find.text('tab:Tab 1*'), findsOneWidget);
  });

  group('hidesWhenPushed', () {
    testWidgets('the tabs leave for a page pushed on a tab, which gets their room back', (tester) async {
      phone(tester);
      final tabs = TabsFixture(hidesWhenPushed: true);
      await tester.pumpWidget(tabs.app());
      await tester.pumpAndSettle();

      tabs.push(0, 'Detail');
      await tester.pumpAndSettle();

      expect(find.text('title:Detail'), findsOneWidget);
      expect(find.byKey(TestChrome.tabBarKey), findsNothing);
      expect(tabs.paddingOf('Detail').bottom, 34);
      expect(tabs.insetOf('Detail'), 0);
      expect(find.text('back'), findsOneWidget);

      await tester.tap(find.text('back'));
      await tester.pumpAndSettle();
      expect(find.text('title:Tab 0'), findsOneWidget);
      expect(find.byKey(TestChrome.tabBarKey), findsOneWidget);
      expect(find.text('back'), findsNothing);
    });

    testWidgets('the tabs fade out with the push, in step with it', (tester) async {
      phone(tester);
      final tabs = TabsFixture(hidesWhenPushed: true);
      await tester.pumpWidget(tabs.app());
      await tester.pumpAndSettle();

      tabs.push(0, 'Detail');
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 75));
      final opacity = tester
          .widgetList<FadeTransition>(find.ancestor(of: find.byKey(TestChrome.tabBarKey), matching: find.byType(FadeTransition)))
          .fold<double>(1, (value, fade) => value * fade.opacity.value);
      expect(opacity, inExclusiveRange(0, 1));
    });

    testWidgets('the tabs come back all through the pop, as the page uncovers them, rather than at its end', (tester) async {
      phone(tester);
      final tabs = TabsFixture(hidesWhenPushed: true);
      await tester.pumpWidget(tabs.app());
      await tester.pumpAndSettle();
      final detail = tabs.page('Detail') as ModalRoute<void>;
      tabs.navigators[0].currentState!.push(detail);
      await tester.pumpAndSettle();

      await tester.tap(find.text('back'));
      await tester.pump();
      for (var i = 0; i < 120 && detail.animation!.value > 0.5; i++) {
        await tester.pump(const Duration(milliseconds: 8));
      }
      final opacity = tester
          .widgetList<FadeTransition>(find.ancestor(of: find.byKey(TestChrome.tabBarKey), matching: find.byType(FadeTransition)))
          .fold<double>(1, (value, fade) => value * fade.opacity.value);

      expect(opacity, closeTo(1 - detail.animation!.value, 0.05));
    });

    testWidgets('the tabs fade out as the keyboard comes up and back in as it goes down', (tester) async {
      phone(tester);
      final tabs = TabsFixture();
      await tester.pumpWidget(tabs.app());
      await tester.pumpAndSettle();
      double opacity() => tester
          .widgetList<FadeTransition>(find.ancestor(of: find.byKey(TestChrome.tabBarKey), matching: find.byType(FadeTransition)))
          .fold<double>(1, (value, fade) => value * fade.opacity.value);

      tester.view.viewInsets = const FakeViewPadding(bottom: 120);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 60));
      expect(opacity(), inExclusiveRange(0, 1));
      tester.view.viewInsets = const FakeViewPadding(bottom: 336);
      await tester.pumpAndSettle();
      expect(opacity(), 0);
      await tester.tap(find.text('tab:Tab 1'), warnIfMissed: false);
      await tester.pumpAndSettle();
      expect(tabs.selected.value, 0);

      tester.view.viewInsets = const FakeViewPadding(bottom: 290);
      await tester.pumpAndSettle();
      expect(opacity(), 0, reason: 'a keyboard that only changes height stays up');
      tester.view.viewInsets = const FakeViewPadding(bottom: 120);
      await tester.pump();
      await tester.pump(AdaptiveKeyboardFade.fadeInDuration ~/ 2);
      expect(opacity(), inExclusiveRange(0, 1));
      tester.view.viewInsets = FakeViewPadding.zero;
      await tester.pumpAndSettle();
      expect(opacity(), 1);
    });

    testWidgets('with hidesFor, the tabs only leave for the pages it picks', (tester) async {
      phone(tester);
      final tabs = TabsFixture(hidesWhenPushed: true, hidesFor: (route) => route.settings.name == 'detail');
      await tester.pumpWidget(tabs.app());
      await tester.pumpAndSettle();

      tabs.push(0, 'Other', name: 'other');
      await tester.pumpAndSettle();
      expect(find.text('title:Other'), findsOneWidget);
      expect(find.byKey(TestChrome.tabBarKey), findsOneWidget);
      expect(tabs.paddingOf('Other').bottom, TestChrome.tabBarHeight);

      tabs.push(0, 'Detail', name: 'detail');
      await tester.pumpAndSettle();
      expect(find.text('title:Detail'), findsOneWidget);
      expect(find.byKey(TestChrome.tabBarKey), findsNothing);
      expect(tabs.paddingOf('Detail').bottom, 34);
      expect(tabs.insetOf('Detail'), 0);

      tabs.push(0, 'Deeper', name: 'other');
      await tester.pumpAndSettle();
      expect(find.byKey(TestChrome.tabBarKey), findsNothing);
      expect(tabs.paddingOf('Deeper').bottom, 34);
    });

    testWidgets('without it, the tabs stay for a page pushed on a tab', (tester) async {
      phone(tester);
      final tabs = TabsFixture();
      await tester.pumpWidget(tabs.app());
      await tester.pumpAndSettle();

      tabs.push(0, 'Detail');
      await tester.pumpAndSettle();

      expect(find.text('title:Detail'), findsOneWidget);
      expect(find.byKey(TestChrome.tabBarKey), findsOneWidget);
      expect(tabs.paddingOf('Detail').bottom, TestChrome.tabBarHeight);
    });

    testWidgets('a page that replaces the first page of a tab is that tab, and keeps the tabs', (tester) async {
      phone(tester);
      final tabs = TabsFixture(hidesWhenPushed: true);
      await tester.pumpWidget(tabs.app());
      await tester.pumpAndSettle();

      tabs.navigators[0].currentState!.pushReplacement(tabs.page('Other'));
      await tester.pumpAndSettle();

      expect(find.text('title:Other'), findsOneWidget);
      expect(find.byKey(TestChrome.tabBarKey), findsOneWidget);
      expect(tabs.paddingOf('Other').bottom, TestChrome.tabBarHeight);
    });

    testWidgets('a page over the whole tab layout takes the tabs away too', (tester) async {
      phone(tester);
      final tabs = TabsFixture(hidesWhenPushed: true);
      await tester.pumpWidget(tabs.app());
      await tester.pumpAndSettle();

      tabs.root.currentState!.push(tabs.page('Over'));
      await tester.pumpAndSettle();

      expect(find.text('title:Over'), findsOneWidget);
      expect(find.byKey(TestChrome.tabBarKey), findsNothing);
      expect(tabs.paddingOf('Over').bottom, 34);
    });
  });

  testWidgets('the app\'s actions perform with the context of the control pressed', (tester) async {
    phone(tester);
    final pressed = <String>[];
    final tabs = TabsFixture(
      actions: [AdaptiveAppBarAction(title: 'Share', onPressed: () => pressed.add('Share'))],
    );
    await tester.pumpWidget(tabs.app());
    await tester.pumpAndSettle();

    await tester.tap(find.text('action:Share'));
    expect(pressed, ['Share']);
  });

  testWidgets('a page shown like a dialog gets a close button', (tester) async {
    phone(tester);
    final tabs = TabsFixture(hidesWhenPushed: true);
    await tester.pumpWidget(tabs.app());
    await tester.pumpAndSettle();

    tabs.root.currentState!.push(tabs.page('Modal', fullscreenDialog: true, style: AdaptiveBackButtonStyle.close));
    await tester.pumpAndSettle();

    expect(find.text('close'), findsOneWidget);
    await tester.tap(find.text('close'));
    await tester.pumpAndSettle();
    expect(find.text('title:Tab 0'), findsOneWidget);
  });

  testWidgets('a page in a dialog draws its own bar with the app\'s builders', (tester) async {
    phone(tester);
    final tabs = TabsFixture();
    await tester.pumpWidget(tabs.app());
    await tester.pumpAndSettle();

    showDialog<void>(
      context: tabs.root.currentContext!,
      builder: (_) => const Center(
        child: SizedBox(
          width: 300,
          height: 300,
          child: AdaptiveScaffold(appBar: AdaptiveAppBar(title: 'Dialog'), body: SizedBox.expand()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final dialog = find.byWidgetPredicate((widget) => widget is SizedBox && widget.width == 300 && widget.height == 300);
    expect(find.descendant(of: dialog, matching: find.text('title:Dialog')), findsOneWidget);
    expect(find.text('title:Tab 0'), findsOneWidget);
  });

  testWidgets('chromeData reaches the builders', (tester) async {
    phone(tester);
    final tabs = TabsFixture(chromeData: 'dark');
    await tester.pumpWidget(tabs.app());
    await tester.pumpAndSettle();

    expect(TestChrome.lastTitleData, 'dark');
    expect(TestChrome.lastTabData, 'tabs');
  });

  test('centres titles on iOS and keeps them at the leading edge elsewhere, unless told', () {
    final chrome = TestChrome.build();
    expect(chrome.centersTitle(TargetPlatform.iOS), isTrue);
    expect(chrome.centersTitle(TargetPlatform.android), isFalse);
    final leading = TestChrome.build(centerTitle: false);
    expect(leading.centersTitle(TargetPlatform.iOS), isFalse);
  });

  testWidgets('a title at the leading edge with nothing beside it lines up with the page\'s 16 point margin', (tester) async {
    phone(tester);
    final tabs = TabsFixture(chrome: TestChrome.build(centerTitle: false));
    await tester.pumpWidget(tabs.app());
    await tester.pumpAndSettle();
    expect(tester.getRect(find.text('title:Tab 0')).left, 16);

    tabs.push(0, 'Detail');
    await tester.pumpAndSettle();
    expect(tester.getRect(find.text('title:Detail')).left, greaterThan(16 + 44));
  });

  testWidgets('the app\'s bars get a Material, as a page gives its content, for ink and text styles', (tester) async {
    phone(tester);
    final tabs = TabsFixture();
    await tester.pumpWidget(tabs.app());
    await tester.pumpAndSettle();

    for (final part in [find.byKey(TestChrome.tabBarKey), find.text('title:Tab 0')]) {
      final material = find.ancestor(of: part, matching: find.byType(Material));
      expect(material, findsWidgets);
      expect(tester.widget<Material>(material.first).type, MaterialType.transparency);
    }
  });

  testWidgets('each of the app\'s controls is in the semantics tree in its own place', (tester) async {
    phone(tester);
    final handle = tester.ensureSemantics();
    final tabs = TabsFixture(actions: [AdaptiveAppBarAction(title: 'Share', onPressed: () {})]);
    await tester.pumpWidget(tabs.app());
    await tester.pumpAndSettle();

    final action = tester.getSemantics(find.text('action:Share'));
    expect(action.rect.width, lessThan(100));
    final tab = tester.getSemantics(find.text('tab:Tab 1'));
    expect(tab.rect.width, lessThan(200));
    handle.dispose();
  });
}
