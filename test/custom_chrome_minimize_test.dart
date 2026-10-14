import 'package:adaptive_platform_ui/adaptive_platform_ui.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

ValueListenable<bool>? minimized;

Widget _tabs(BuildContext context, AdaptiveTabBarSpec spec) {
  minimized = spec.minimized;
  return const SizedBox(key: ValueKey<String>('tabs'), height: 64);
}

Widget _title(BuildContext context, AdaptiveTitleSpec spec) => const SizedBox();
Widget _back(BuildContext context, AdaptiveBackButtonSpec spec) => const SizedBox();
Widget _actions(BuildContext context, AdaptiveActionsSpec spec) => const SizedBox();

const chrome = AdaptiveChrome(tabBarBuilder: _tabs, titleBuilder: _title, backButtonBuilder: _back, actionsBuilder: _actions);

void main() {
  final selected = ValueNotifier<int>(0);

  setUp(() {
    minimized = null;
    selected.value = 0;
    PlatformInfo.debugPlatformOverride = TargetPlatform.android;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform_views, (_) async => null);
  });

  tearDown(() {
    PlatformInfo.debugPlatformOverride = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform_views, null);
  });

  Future<void> pumpTabs(WidgetTester tester, {TabBarMinimizeBehavior behavior = TabBarMinimizeBehavior.onScrollDown}) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    tester.view.padding = const FakeViewPadding(top: 47, bottom: 34);
    tester.view.viewPadding = const FakeViewPadding(top: 47, bottom: 34);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => AdaptiveToolbarHost(chrome: chrome, child: child!),
        home: ValueListenableBuilder<int>(
          valueListenable: selected,
          builder: (context, index, _) => AdaptiveScaffold(
            minimizeBehavior: behavior,
            bottomNavigationBar: AdaptiveBottomNavigationBar(
              items: const [
                AdaptiveNavigationDestination(icon: Icons.circle, label: 'A'),
                AdaptiveNavigationDestination(icon: Icons.circle, label: 'B'),
              ],
              selectedIndex: index,
              onTap: (i) => selected.value = i,
            ),
            body: Column(
              children: [
                SizedBox(
                  height: 120,
                  child: ListView(key: const ValueKey<String>('carousel'), scrollDirection: Axis.horizontal, children: [for (var i = 0; i < 20; i++) const SizedBox(width: 200)]),
                ),
                Expanded(
                  child: ListView(key: const ValueKey<String>('list'), children: [for (var i = 0; i < 80; i++) const SizedBox(height: 60)]),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('the app\'s tab bar is told to make itself smaller as the page scrolls down, and back as it scrolls up; the host leaves its size alone', (tester) async {
    await pumpTabs(tester);
    final size = tester.getSize(find.byKey(const ValueKey<String>('tabs')));
    expect(minimized!.value, isFalse);

    await tester.drag(find.byKey(const ValueKey<String>('list')), const Offset(0, -400));
    await tester.pumpAndSettle();
    expect(minimized!.value, isTrue);
    expect(tester.getSize(find.byKey(const ValueKey<String>('tabs'))), size);
    expect(find.ancestor(of: find.byKey(const ValueKey<String>('tabs')), matching: find.byType(Transform)), findsNothing);

    await tester.drag(find.byKey(const ValueKey<String>('list')), const Offset(0, 200));
    await tester.pumpAndSettle();
    expect(minimized!.value, isFalse);
  });

  testWidgets('picking another tab brings the bar back at full size', (tester) async {
    await pumpTabs(tester);
    await tester.drag(find.byKey(const ValueKey<String>('list')), const Offset(0, -400));
    await tester.pumpAndSettle();
    expect(minimized!.value, isTrue);

    selected.value = 1;
    await tester.pumpAndSettle();
    expect(minimized!.value, isFalse);
  });

  testWidgets('until the top: scrolling up a little keeps the bar small, and it is back only at the top', (tester) async {
    await pumpTabs(tester, behavior: TabBarMinimizeBehavior.onScrollDownUntilTop);
    final list = find.byKey(const ValueKey<String>('list'));

    await tester.drag(list, const Offset(0, -800));
    await tester.pumpAndSettle();
    expect(minimized!.value, isTrue);

    await tester.drag(list, const Offset(0, 300));
    await tester.pumpAndSettle();
    expect(minimized!.value, isTrue);

    await tester.drag(list, const Offset(0, 2000));
    await tester.pumpAndSettle();
    expect(minimized!.value, isFalse);
  });

  testWidgets('a carousel scrolling sideways leaves the tab bar as it is', (tester) async {
    await pumpTabs(tester);

    await tester.drag(find.byKey(const ValueKey<String>('carousel')), const Offset(-600, 0));
    await tester.pumpAndSettle();
    expect(minimized!.value, isFalse);
  });
  testWidgets(
    'beside a list only the list shrinks the tab bar: the page it opened scrolls without making it flicker',
    (tester) async {
      tester.view.physicalSize = const Size(900, 700);
      tester.view.devicePixelRatio = 1;
      tester.view.padding = const FakeViewPadding(top: 24, bottom: 20);
      tester.view.viewPadding = const FakeViewPadding(top: 24, bottom: 20);
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) =>
              AdaptiveToolbarHost(chrome: chrome, child: child!),
          home: AdaptiveScaffold(
            minimizeBehavior: TabBarMinimizeBehavior.onScrollDownUntilTop,
            bottomNavigationBar: AdaptiveBottomNavigationBar(
              items: const [
                AdaptiveNavigationDestination(icon: Icons.circle, label: 'A'),
                AdaptiveNavigationDestination(icon: Icons.circle, label: 'B'),
              ],
              selectedIndex: 0,
              onTap: (_) {},
            ),
            body: AdaptiveSplitView(
              initialDetail: const RouteSettings(name: 'detail'),
              onGenerateDetailRoute: (settings) => MaterialPageRoute<void>(
                settings: settings,
                builder: (_) => AdaptiveScaffold(
                  appBar: const AdaptiveAppBar(title: 'Detail'),
                  body: ListView(
                    key: const ValueKey<String>('detail list'),
                    children: [
                      for (var i = 0; i < 80; i++) const SizedBox(height: 60),
                    ],
                  ),
                ),
              ),
              master: AdaptiveScaffold(
                appBar: const AdaptiveAppBar(title: 'List'),
                body: ListView(
                  key: const ValueKey<String>('master list'),
                  children: [
                    for (var i = 0; i < 80; i++) const SizedBox(height: 60),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(minimized!.value, isFalse);

      await tester.drag(
        find.byKey(const ValueKey<String>('detail list')),
        const Offset(0, -600),
      );
      await tester.pumpAndSettle();
      expect(minimized!.value, isFalse);

      await tester.drag(
        find.byKey(const ValueKey<String>('master list')),
        const Offset(0, -600),
      );
      await tester.pumpAndSettle();
      expect(minimized!.value, isTrue);

      await tester.drag(
        find.byKey(const ValueKey<String>('detail list')),
        const Offset(0, 2000),
      );
      await tester.pumpAndSettle();
      expect(minimized!.value, isTrue);
    },
  );
}
