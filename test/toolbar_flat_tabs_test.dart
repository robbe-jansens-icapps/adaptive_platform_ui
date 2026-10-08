import 'package:adaptive_platform_ui/adaptive_platform_ui.dart';
import 'package:adaptive_platform_ui/src/toolbar/duo_vertical_bar.dart';
import 'package:adaptive_platform_ui/src/toolbar/hosted_duo_bar.dart';
import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:foldable/foldable.dart';

const Size duoLandscape = Size(951, 669);

FoldableData duoInnerDisplay() => FoldableData(
  capabilities: FoldableData.unsupported.capabilities,
  status: FoldableData.unsupported.status,
  angleDegrees: FoldableData.unsupported.angleDegrees,
  regions: const [
    ReservedRegion(
      kind: ReservedRegionKind.occlusion,
      bounds: Rect.fromLTRB(867, 0, 951, 120),
      isActive: true,
    ),
  ],
  displayFeatures: const [],
  horizontalSizeClass: SizeClass.regular,
  verticalSizeClass: SizeClass.regular,
);

void useDuoLandscape(WidgetTester tester) {
  tester.view.physicalSize = duoLandscape;
  tester.view.devicePixelRatio = 1;
  tester.view.padding = const FakeViewPadding(right: 84, bottom: 34);
  tester.view.viewPadding = const FakeViewPadding(right: 84, bottom: 34);
  addTearDown(tester.view.reset);
}

void usePhone(WidgetTester tester) {
  tester.view.physicalSize = const Size(402, 874);
  tester.view.devicePixelRatio = 1;
  tester.view.padding = const FakeViewPadding(top: 62, bottom: 34);
  tester.view.viewPadding = const FakeViewPadding(top: 62, bottom: 34);
  addTearDown(tester.view.reset);
}

Widget page(
  String title, {
  IconData? action,
  VoidCallback? onBack,
  AdaptiveBackButtonStyle backButtonStyle = AdaptiveBackButtonStyle.back,
  bool automaticallyImplyLeading = true,
}) => AdaptiveScaffold(
  appBar: AdaptiveAppBar(
    title: title,
    useNativeToolbar: true,
    onBack: onBack,
    backButtonStyle: backButtonStyle,
    automaticallyImplyLeading: automaticallyImplyLeading,
    actions: [
      if (action != null) AdaptiveAppBarAction(icon: action, onPressed: () {}),
    ],
  ),
  body: Center(child: Text('body:$title')),
);

const destinations = [
  AdaptiveNavigationDestination(icon: Icons.home, label: 'Home'),
  AdaptiveNavigationDestination(icon: Icons.info, label: 'Info'),
];

/// Tabs the way most apps build them: an IndexedStack inside the one route
/// of the tab scaffold, without a navigator per tab.
Widget flatTabsApp({
  required ValueNotifier<int> index,
  GlobalKey<NavigatorState>? navigatorKey,
}) => MaterialApp(
  navigatorKey: navigatorKey,
  builder: (context, child) =>
      AdaptiveToolbarHost(debugFold: duoInnerDisplay(), child: child!),
  home: ValueListenableBuilder<int>(
    valueListenable: index,
    builder: (_, value, _) => AdaptiveScaffold(
      bottomNavigationBar: AdaptiveBottomNavigationBar(
        selectedIndex: value,
        onTap: (i) => index.value = i,
        items: destinations,
      ),
      body: IndexedStack(
        index: value,
        children: [
          page('Root', action: Icons.add),
          page('Info', action: Icons.share),
        ],
      ),
    ),
  ),
);

Finder get bar => find.byType(HostedDuoBar);
Finder inBar(Finder finder) => find.descendant(of: bar, matching: finder);

void main() {
  group('flat tabs in one route', () {
    testWidgets('keep their tab bar in the trailing bar on every tab', (
      tester,
    ) async {
      useDuoLandscape(tester);
      final index = ValueNotifier<int>(0);
      await tester.pumpWidget(flatTabsApp(index: index));
      await tester.pump();

      expect(inBar(find.byIcon(Icons.add)), findsOneWidget);
      expect(inBar(find.byIcon(Icons.home)), findsOneWidget);
      expect(inBar(find.byIcon(Icons.info)), findsOneWidget);

      await tester.tap(inBar(find.byIcon(Icons.info)));
      await tester.pumpAndSettle();

      expect(index.value, 1);
      expect(inBar(find.byIcon(Icons.share)), findsOneWidget);
      expect(inBar(find.byIcon(Icons.home)), findsOneWidget);
    });

    testWidgets('leave with the tabs when a page covers them', (tester) async {
      useDuoLandscape(tester);
      final root = GlobalKey<NavigatorState>();
      await tester.pumpWidget(
        flatTabsApp(index: ValueNotifier<int>(0), navigatorKey: root),
      );
      await tester.pump();

      root.currentState!.push(
        MaterialPageRoute<void>(builder: (_) => page('Detail')),
      );
      await tester.pumpAndSettle();

      expect(inBar(find.byIcon(Icons.home)), findsNothing);
    });

    testWidgets('a page leaving uncovers the selected tab, not a hidden one', (
      tester,
    ) async {
      useDuoLandscape(tester);
      final root = GlobalKey<NavigatorState>();
      await tester.pumpWidget(
        flatTabsApp(index: ValueNotifier<int>(0), navigatorKey: root),
      );
      await tester.pump();

      root.currentState!.push(
        MaterialPageRoute<void>(builder: (_) => page('Detail')),
      );
      await tester.pumpAndSettle();

      final registry = ToolbarRegistry.maybeOf(
        tester.element(find.text('body:Detail')),
      )!;
      final below = registry.below(registry.active!);
      expect(below?.appBar?.title, 'Root');
    });
  });

  group('back button', () {
    testWidgets('calls the page handler instead of popping', (tester) async {
      useDuoLandscape(tester);
      final root = GlobalKey<NavigatorState>();
      var backs = 0;
      await tester.pumpWidget(
        flatTabsApp(index: ValueNotifier<int>(0), navigatorKey: root),
      );
      root.currentState!.push(
        MaterialPageRoute<void>(
          builder: (_) => page('Detail', onBack: () => backs++),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(inBar(find.byType(DuoBarBackButton)));
      await tester.pumpAndSettle();

      expect(backs, 1);
      expect(find.text('body:Detail'), findsOneWidget);
    });

    testWidgets('shows a cross for the close style', (tester) async {
      useDuoLandscape(tester);
      final root = GlobalKey<NavigatorState>();
      await tester.pumpWidget(
        flatTabsApp(index: ValueNotifier<int>(0), navigatorKey: root),
      );
      root.currentState!.push(
        MaterialPageRoute<void>(
          builder: (_) => page(
            'Detail',
            onBack: () {},
            backButtonStyle: AdaptiveBackButtonStyle.close,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(inBar(find.byIcon(CupertinoIcons.xmark)), findsOneWidget);
      expect(inBar(find.byIcon(CupertinoIcons.chevron_left)), findsNothing);
    });

    testWidgets('is left out for a page that does not imply one', (
      tester,
    ) async {
      useDuoLandscape(tester);
      final root = GlobalKey<NavigatorState>();
      await tester.pumpWidget(
        flatTabsApp(index: ValueNotifier<int>(0), navigatorKey: root),
      );
      root.currentState!.push(
        MaterialPageRoute<void>(
          builder: (_) => page('Detail', automaticallyImplyLeading: false),
        ),
      );
      await tester.pumpAndSettle();

      expect(inBar(find.byType(DuoBarBackButton)), findsNothing);
    });
  });

  group('bottom bar inset', () {
    setUp(() {
      PlatformInfo.debugPlatformOverride = TargetPlatform.iOS;
      PlatformInfo.debugIOSVersionOverride = 26;
    });

    tearDown(() {
      PlatformInfo.debugPlatformOverride = null;
      PlatformInfo.debugIOSVersionOverride = null;
    });

    Widget tabs({required ValueChanged<BuildContext> onBody}) =>
        AdaptiveScaffold(
          bottomNavigationBar: AdaptiveBottomNavigationBar(
            selectedIndex: 0,
            onTap: (_) {},
            items: destinations,
          ),
          body: Builder(
            builder: (context) {
              onBody(context);
              return const SizedBox.expand();
            },
          ),
        );

    testWidgets('raises the body padding to the native tab bar', (
      tester,
    ) async {
      usePhone(tester);
      late BuildContext body;
      await tester.pumpWidget(
        MaterialApp(home: tabs(onBody: (context) => body = context)),
      );
      await tester.pump();

      // Off device the native bar draws its 50 point Flutter stand-in.
      expect(AdaptiveBottomBarInset.of(body), 50);
      expect(MediaQuery.paddingOf(body).bottom, 50);
      expect(MediaQuery.viewPaddingOf(body).bottom, 50);
    });

    testWidgets('is 0 while the tabs are in the iPhone Duo trailing bar', (
      tester,
    ) async {
      useDuoLandscape(tester);
      late BuildContext body;
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) =>
              AdaptiveToolbarHost(debugFold: duoInnerDisplay(), child: child!),
          home: tabs(onBody: (context) => body = context),
        ),
      );
      await tester.pump();

      expect(AdaptiveBottomBarInset.of(body), 0);
      expect(MediaQuery.paddingOf(body).bottom, 34);
    });
  });
}
