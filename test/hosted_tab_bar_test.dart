import 'package:adaptive_platform_ui/adaptive_platform_ui.dart';
import 'package:adaptive_platform_ui/src/toolbar/hosted_duo_bar.dart';
import 'package:adaptive_platform_ui/src/toolbar/duo_vertical_bar.dart';
import 'package:adaptive_platform_ui/src/toolbar/toolbar_blend.dart';
import 'package:adaptive_platform_ui/src/toolbar/hosted_tab_bar.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:foldable/foldable.dart';

/// Forces the chrome on (there is no iOS 26 in a widget test).
FoldableData forcedChrome({List<ReservedRegion> regions = const []}) =>
    FoldableData(
      capabilities: FoldableData.unsupported.capabilities,
      status: FoldableData.unsupported.status,
      angleDegrees: FoldableData.unsupported.angleDegrees,
      regions: regions,
      displayFeatures: const [],
    );

const tabBarType = 'adaptive_platform_ui/ios26_tab_bar';

const destinations = [
  AdaptiveNavigationDestination(icon: 'map', label: 'Map'),
  AdaptiveNavigationDestination(icon: 'person', label: 'Account'),
];

void usePhone(WidgetTester tester) {
  tester.view.physicalSize = const Size(402, 874);
  tester.view.devicePixelRatio = 1;
  tester.view.padding = const FakeViewPadding(top: 62, bottom: 34);
  tester.view.viewPadding = const FakeViewPadding(top: 62, bottom: 34);
  addTearDown(tester.view.reset);
}

/// The iPhone Duo inner display in landscape: the vertical bar on the right.
void useDuoLandscape(WidgetTester tester) {
  tester.view.physicalSize = const Size(951, 669);
  tester.view.devicePixelRatio = 1;
  tester.view.padding = const FakeViewPadding(right: 84, bottom: 34);
  tester.view.viewPadding = const FakeViewPadding(right: 84, bottom: 34);
  addTearDown(tester.view.reset);
}

/// The iPhone Duo inner display held upright: the strip along the top.
void useDuoUpright(WidgetTester tester) {
  tester.view.physicalSize = const Size(764, 951);
  tester.view.devicePixelRatio = 1;
  tester.view.padding = const FakeViewPadding(top: 84, bottom: 20);
  tester.view.viewPadding = const FakeViewPadding(top: 84, bottom: 20);
  addTearDown(tester.view.reset);
}

FoldableData duoUpright() => FoldableData(
  capabilities: const FoldableCapabilities(
    supportLevel: FoldableSupportLevel.available,
    isFoldable: true,
    hingeApiPresent: true,
    regionApiPresent: true,
    angleUnitVerified: true,
    strategy: 'test',
  ),
  status: HingeStatus.fullyOpen,
  angleDegrees: 180,
  regions: const [
    ReservedRegion(
      kind: ReservedRegionKind.occlusion,
      bounds: Rect.fromLTRB(644, 0, 764, 84),
      isActive: true,
    ),
  ],
  displayFeatures: const [],
);

/// A page of the tabs, or one pushed over them, as most apps build them:
/// its own app bar, with a Flutter title.
Widget page(String title, {Widget? body, ValueChanged<BuildContext>? onBody}) =>
    AdaptiveScaffold(
      appBar: AdaptiveAppBar(useNativeToolbar: true, titleWidget: Text(title)),
      body:
          body ??
          Builder(
            builder: (context) {
              onBody?.call(context);
              return Center(child: Text('body:$title'));
            },
          ),
    );

/// What the tests change on the tabs page.
class Tabs {
  final index = ValueNotifier<int>(0);
  final dot = ValueNotifier<bool>(false);
  final hidden = ValueNotifier<bool>(false);
  late BuildContext body;

  void dispose() {
    index.dispose();
    dot.dispose();
    hidden.dispose();
  }
}

/// Tabs as most apps build them: an `IndexedStack` of pages inside the one
/// route of the tab scaffold, without a navigator per tab.
Widget tabsPage(
  Tabs tabs, {
  List<Widget>? children,
  bool useFixedToolbar = true,
  TabBarMinimizeBehavior minimizeBehavior = TabBarMinimizeBehavior.never,
}) => ListenableBuilder(
  listenable: Listenable.merge([tabs.index, tabs.dot, tabs.hidden]),
  builder: (context, _) => AdaptiveScaffold(
    useFixedToolbar: useFixedToolbar,
    minimizeBehavior: minimizeBehavior,
    tabBarHidden: tabs.hidden.value,
    bottomNavigationBar: AdaptiveBottomNavigationBar(
      selectedIndex: tabs.index.value,
      onTap: (index) => tabs.index.value = index,
      items: [
        destinations[0],
        AdaptiveNavigationDestination(
          icon: 'person',
          label: 'Account',
          showsBadgeDot: tabs.dot.value,
        ),
      ],
    ),
    body: Builder(
      builder: (context) {
        tabs.body = context;
        return IndexedStack(
          index: tabs.index.value,
          children: children ?? [page('Map'), page('Account')],
        );
      },
    ),
  ),
);

Widget hostedApp(
  GlobalKey<NavigatorState> navigator,
  Widget home, {
  FoldableData? fold,
}) => MaterialApp(
  navigatorKey: navigator,
  builder: (context, child) =>
      AdaptiveToolbarHost(debugFold: fold ?? forcedChrome(), child: child!),
  home: home,
);

Route<void> pageRoute(String title, {ValueChanged<BuildContext>? onBody}) =>
    MaterialPageRoute<void>(builder: (_) => page(title, onBody: onBody));

final nativeBar = find.byType(IOS26NativeTabBar, skipOffstage: false);

/// The opacity of the hosted bar's own layer, which follows the pages.
double layerOpacity(WidgetTester tester) => tester
    .widget<FadeTransition>(
      find
          .ancestor(
            of: nativeBar,
            matching: find.byType(FadeTransition, skipOffstage: false),
          )
          .first,
    )
    .opacity
    .value;

/// The opacity of all the hosted bars, which follows a dialog or sheet.
double coverOpacity(WidgetTester tester) => tester
    .widget<FadeTransition>(
      find
          .descendant(
            of: find.byType(HostedTabBar),
            matching: find.byType(FadeTransition, skipOffstage: false),
            skipOffstage: false,
          )
          .first,
    )
    .opacity
    .value;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  /// The native views made and thrown away, by id.
  final created = <(int, String)>[];
  final disposed = <int>[];

  setUp(() {
    created.clear();
    disposed.clear();
    PlatformInfo.debugPlatformOverride = TargetPlatform.iOS;
    PlatformInfo.debugIOSVersionOverride = 26;
    IOS26NativeTabBar.debugHasUIKitOverride = true;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform_views, (call) async {
          if (call.method == 'create') {
            final args = call.arguments as Map<Object?, Object?>;
            created.add((args['id']! as int, args['viewType']! as String));
          } else if (call.method == 'dispose') {
            disposed.add(call.arguments as int);
          }
          return null;
        });
  });

  tearDown(() {
    PlatformInfo.debugPlatformOverride = null;
    PlatformInfo.debugIOSVersionOverride = null;
    IOS26NativeTabBar.debugHasUIKitOverride = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform_views, null);
  });

  List<int> tabBarsMade() => [
    for (final (id, type) in created)
      if (type == tabBarType) id,
  ];

  List<int> tabBarsThrownAway() => [
    for (final id in disposed)
      if (tabBarsMade().contains(id)) id,
  ];

  final ios = TargetPlatformVariant.only(TargetPlatform.iOS);

  testWidgets('the native tab bar is made once, above the navigator, and kept '
      'through pushes, pops and back swipes', (tester) async {
    usePhone(tester);
    final tabs = Tabs();
    addTearDown(tabs.dispose);
    final navigator = GlobalKey<NavigatorState>();
    await tester.pumpWidget(hostedApp(navigator, tabsPage(tabs)));
    await tester.pumpAndSettle();

    expect(tabBarsMade(), hasLength(1));
    expect(
      find.descendant(
        of: find.byType(HostedTabBar),
        matching: nativeBar,
        skipOffstage: false,
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byType(Navigator),
        matching: nativeBar,
        skipOffstage: false,
      ),
      findsNothing,
    );
    final element = nativeBar.evaluate().single;

    // Pushed and popped.
    navigator.currentState!.push(pageRoute('Detail'));
    await tester.pumpAndSettle();
    navigator.currentState!.pop();
    await tester.pumpAndSettle();

    // Swiped back all the way.
    navigator.currentState!.push(pageRoute('Detail'));
    await tester.pumpAndSettle();
    var swipe = await tester.startGesture(const Offset(5, 400));
    for (var i = 0; i < 10; i++) {
      await swipe.moveBy(const Offset(30, 0));
      await tester.pump(const Duration(milliseconds: 16));
    }
    await swipe.up();
    await tester.pumpAndSettle();
    expect(find.text('body:Detail'), findsNothing);

    // A swipe let go of early: the page stays.
    navigator.currentState!.push(pageRoute('Detail'));
    await tester.pumpAndSettle();
    swipe = await tester.startGesture(const Offset(5, 400));
    await swipe.moveBy(const Offset(20, 0));
    await tester.pump(const Duration(milliseconds: 16));
    await swipe.moveBy(const Offset(20, 0));
    await tester.pump(const Duration(milliseconds: 500));
    await swipe.up();
    await tester.pumpAndSettle();
    expect(find.text('body:Detail'), findsOneWidget);
    navigator.currentState!.pop();
    await tester.pumpAndSettle();

    expect(tabBarsMade(), hasLength(1));
    expect(tabBarsThrownAway(), isEmpty);
    expect(nativeBar.evaluate().single, same(element));
    expect(layerOpacity(tester), 1);
  }, variant: ios);

  testWidgets('it fades out in place over the first fifth of a push, stays '
      'away while the page pops, and fades in once the tabs hold still', (
    tester,
  ) async {
    usePhone(tester);
    final tabs = Tabs();
    addTearDown(tabs.dispose);
    final navigator = GlobalKey<NavigatorState>();
    await tester.pumpWidget(hostedApp(navigator, tabsPage(tabs)));
    await tester.pumpAndSettle();
    expect(find.byType(IOS26NativeTabBar), findsOneWidget);
    expect(layerOpacity(tester), 1);

    /// What the bar shows: nothing while off stage.
    double shown() => find.byType(IOS26NativeTabBar).evaluate().isEmpty
        ? 0
        : layerOpacity(tester);

    final route = pageRoute('Detail') as PageRoute<void>;
    navigator.currentState!.push(route);
    // A pushed page spends its first frame off stage, its animation
    // reporting the end it starts from.
    await tester.pump();
    var fading = false;
    while (route.animation!.status != AnimationStatus.completed) {
      await tester.pump(const Duration(milliseconds: 8));
      final progress = route.animation!.value;
      final opacity = shown();
      if (opacity > 0 && opacity < 1) {
        fading = true;
        // In place: the bar does not move with the tabs page.
        expect(tester.getBottomLeft(nativeBar), const Offset(0, 874));
      }
      // Gone, and so off screen, for the rest of the push.
      if (progress >= 0.2) expect(opacity, 0, reason: 'at $progress');
    }
    expect(fading, isTrue);

    await tester.pumpAndSettle();
    // Off stage while the page covers the tabs.
    expect(find.byType(IOS26NativeTabBar), findsNothing);
    expect(nativeBar, findsOneWidget);

    navigator.currentState!.pop();
    while (route.animation!.status != AnimationStatus.dismissed) {
      await tester.pump(const Duration(milliseconds: 8));
      if (route.animation!.status == AnimationStatus.dismissed) break;
      expect(shown(), 0, reason: 'at ${route.animation!.value}');
    }

    // The tabs hold still: the bar fades in.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(shown(), greaterThan(0));
    expect(shown(), lessThan(1));
    await tester.pumpAndSettle();
    expect(shown(), 1);
    expect(tabBarsMade(), hasLength(1));
  }, variant: ios);

  testWidgets('it stays away during a back swipe, also one that is let go '
      'of early, and fades in once the tabs hold still', (tester) async {
    usePhone(tester);
    final tabs = Tabs();
    addTearDown(tabs.dispose);
    final navigator = GlobalKey<NavigatorState>();
    await tester.pumpWidget(hostedApp(navigator, tabsPage(tabs)));
    await tester.pumpAndSettle();
    double shown() => find.byType(IOS26NativeTabBar).evaluate().isEmpty
        ? 0
        : layerOpacity(tester);

    navigator.currentState!.push(pageRoute('Detail'));
    await tester.pumpAndSettle();

    // Let go of early: the page stays, and so does the bar's absence.
    var swipe = await tester.startGesture(const Offset(5, 400));
    for (var i = 0; i < 3; i++) {
      await swipe.moveBy(const Offset(20, 0));
      await tester.pump(const Duration(milliseconds: 16));
      expect(shown(), 0);
    }
    await tester.pump(const Duration(milliseconds: 500));
    await swipe.up();
    for (var i = 0; i < 40; i++) {
      await tester.pump(const Duration(milliseconds: 16));
      expect(shown(), 0);
    }
    await tester.pumpAndSettle();
    expect(find.text('body:Detail'), findsOneWidget);
    expect(shown(), 0);

    // All the way.
    swipe = await tester.startGesture(const Offset(5, 400));
    for (var i = 0; i < 10; i++) {
      await swipe.moveBy(const Offset(30, 0));
      await tester.pump(const Duration(milliseconds: 16));
      expect(shown(), 0);
    }
    await swipe.up();
    await tester.pumpAndSettle();
    expect(find.text('body:Detail'), findsNothing);
    expect(shown(), 1);
  }, variant: ios);

  testWidgets('it stays at full opacity while the pages within the tabs '
      'change: a tab switch, or a push inside a tab', (tester) async {
    usePhone(tester);
    final tabs = Tabs();
    addTearDown(tabs.dispose);
    final inner = GlobalKey<NavigatorState>();
    final navigator = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      hostedApp(
        navigator,
        tabsPage(
          tabs,
          children: [
            Navigator(
              key: inner,
              onGenerateRoute: (_) =>
                  MaterialPageRoute<void>(builder: (_) => page('Map')),
            ),
            page('Account'),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();

    tabs.index.value = 1;
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 30));
      expect(layerOpacity(tester), 1);
      expect(find.byType(IOS26NativeTabBar), findsOneWidget);
    }
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<IOS26NativeTabBar>(find.byType(IOS26NativeTabBar))
          .selectedIndex,
      1,
    );

    tabs.index.value = 0;
    await tester.pumpAndSettle();
    inner.currentState!.push(pageRoute('Inner detail'));
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 60));
      expect(layerOpacity(tester), 1);
      expect(find.byType(IOS26NativeTabBar), findsOneWidget);
    }
    await tester.pumpAndSettle();
    expect(find.text('body:Inner detail'), findsOneWidget);
    expect(find.byType(IOS26NativeTabBar), findsOneWidget);
    expect(tabBarsMade(), hasLength(1));
  }, variant: ios);

  testWidgets('the tabs keep their content clear of the bar while covered; '
      'a page pushed over them does not', (tester) async {
    usePhone(tester);
    final tabs = Tabs();
    addTearDown(tabs.dispose);
    final navigator = GlobalKey<NavigatorState>();
    await tester.pumpWidget(hostedApp(navigator, tabsPage(tabs)));
    await tester.pumpAndSettle();

    // The native bar measures 50 points where there is no UIKit to ask.
    expect(AdaptiveBottomBarInset.of(tabs.body), 50);
    expect(MediaQuery.paddingOf(tabs.body).bottom, 50);
    expect(MediaQuery.viewPaddingOf(tabs.body).bottom, 50);

    late BuildContext detail;
    navigator.currentState!.push(
      pageRoute('Detail', onBody: (context) => detail = context),
    );
    await tester.pumpAndSettle();
    expect(AdaptiveBottomBarInset.of(detail), 0);
    expect(MediaQuery.paddingOf(detail).bottom, 34);
    expect(AdaptiveBottomBarInset.of(tabs.body), 50);

    navigator.currentState!.pop();
    await tester.pumpAndSettle();
    expect(AdaptiveBottomBarInset.of(tabs.body), 50);
    expect(MediaQuery.paddingOf(tabs.body).bottom, 50);
  }, variant: ios);

  testWidgets('tabBarHidden takes it off stage and the inset away, and '
      'brings back the same bar', (tester) async {
    usePhone(tester);
    final tabs = Tabs();
    addTearDown(tabs.dispose);
    final navigator = GlobalKey<NavigatorState>();
    await tester.pumpWidget(hostedApp(navigator, tabsPage(tabs)));
    await tester.pumpAndSettle();
    final element = nativeBar.evaluate().single;

    tabs.hidden.value = true;
    await tester.pumpAndSettle();
    expect(find.byType(IOS26NativeTabBar), findsNothing);
    expect(AdaptiveBottomBarInset.of(tabs.body), 0);
    expect(MediaQuery.paddingOf(tabs.body).bottom, 34);

    tabs.hidden.value = false;
    await tester.pumpAndSettle();
    expect(find.byType(IOS26NativeTabBar), findsOneWidget);
    expect(AdaptiveBottomBarInset.of(tabs.body), 50);
    expect(nativeBar.evaluate().single, same(element));
    expect(tabBarsMade(), hasLength(1));
  }, variant: ios);

  testWidgets('a dialog over the tabs fades the bar out and makes it inert', (
    tester,
  ) async {
    usePhone(tester);
    final tabs = Tabs();
    addTearDown(tabs.dispose);
    final navigator = GlobalKey<NavigatorState>();
    await tester.pumpWidget(hostedApp(navigator, tabsPage(tabs)));
    await tester.pumpAndSettle();
    expect(coverOpacity(tester), 1);

    showCupertinoDialog<void>(
      context: navigator.currentContext!,
      builder: (_) => const CupertinoAlertDialog(title: Text('Sure?')),
    );
    await tester.pumpAndSettle();
    expect(coverOpacity(tester), 0);
    expect(
      tester
          .widget<IgnorePointer>(
            find
                .descendant(
                  of: find.byType(HostedTabBar),
                  matching: find.byType(IgnorePointer, skipOffstage: false),
                  skipOffstage: false,
                )
                .first,
          )
          .ignoring,
      isTrue,
    );

    navigator.currentState!.pop();
    await tester.pumpAndSettle();
    expect(coverOpacity(tester), 1);
    expect(tabBarsMade(), hasLength(1));
  }, variant: ios);

  testWidgets('a tab picked on the native bar selects it, on the same bar', (
    tester,
  ) async {
    usePhone(tester);
    final tabs = Tabs();
    addTearDown(tabs.dispose);
    final navigator = GlobalKey<NavigatorState>();
    await tester.pumpWidget(hostedApp(navigator, tabsPage(tabs)));
    await tester.pumpAndSettle();

    await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
      '$tabBarType${'_'}${tabBarsMade().single}',
      const StandardMethodCodec().encodeMethodCall(
        const MethodCall('valueChanged', {'index': 1}),
      ),
      (_) {},
    );
    await tester.pumpAndSettle();

    expect(tabs.index.value, 1);
    expect(find.text('body:Account'), findsOneWidget);
    expect(tester.widget<IOS26NativeTabBar>(nativeBar).selectedIndex, 1);
    expect(tabBarsMade(), hasLength(1));
  }, variant: ios);

  testWidgets('a badge dot set on the tabs reaches the bar while a tab page '
      'is in front', (tester) async {
    usePhone(tester);
    final tabs = Tabs();
    addTearDown(tabs.dispose);
    final navigator = GlobalKey<NavigatorState>();
    await tester.pumpWidget(hostedApp(navigator, tabsPage(tabs)));
    await tester.pumpAndSettle();
    expect(
      tester.widget<IOS26NativeTabBar>(nativeBar).destinations[1].showsBadgeDot,
      isFalse,
    );

    tabs.dot.value = true;
    await tester.pumpAndSettle();
    expect(
      tester.widget<IOS26NativeTabBar>(nativeBar).destinations[1].showsBadgeDot,
      isTrue,
    );
  }, variant: ios);

  testWidgets('minimizeBehavior shrinks the hosted bar as a tab scrolls', (
    tester,
  ) async {
    usePhone(tester);
    final tabs = Tabs();
    addTearDown(tabs.dispose);
    final navigator = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      hostedApp(
        navigator,
        tabsPage(
          tabs,
          minimizeBehavior: TabBarMinimizeBehavior.onScrollDown,
          children: [
            page(
              'List',
              body: ListView.builder(
                itemCount: 100,
                itemBuilder: (_, i) =>
                    SizedBox(height: 50, child: Text('row $i')),
              ),
            ),
            page('Account'),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();

    double scale() => tester
        .widget<Transform>(
          find
              .ancestor(
                of: nativeBar,
                matching: find.byType(Transform, skipOffstage: false),
              )
              .first,
        )
        .transform
        .entry(0, 0);
    expect(scale(), 1);

    await tester.drag(find.byType(ListView), const Offset(0, -400));
    await tester.pumpAndSettle();
    expect(scale(), closeTo(0.7, 0.001));

    await tester.drag(find.byType(ListView), const Offset(0, 100));
    await tester.pumpAndSettle();
    expect(scale(), 1);
  }, variant: ios);

  testWidgets('a tab layout that keeps its own bar is left alone: '
      'useFixedToolbar false, or one in a sheet', (tester) async {
    usePhone(tester);
    final tabs = Tabs();
    addTearDown(tabs.dispose);
    final navigator = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      hostedApp(navigator, tabsPage(tabs, useFixedToolbar: false)),
    );
    await tester.pumpAndSettle();
    expect(
      find.descendant(
        of: find.byType(Navigator),
        matching: nativeBar,
        skipOffstage: false,
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byType(HostedTabBar),
        matching: nativeBar,
        skipOffstage: false,
      ),
      findsNothing,
    );
    expect(AdaptiveBottomBarInset.of(tabs.body), 50);

    final sheetTabs = Tabs();
    addTearDown(sheetTabs.dispose);
    showCupertinoModalPopup<void>(
      context: navigator.currentContext!,
      builder: (_) => SizedBox(height: 500, child: tabsPage(sheetTabs)),
    );
    await tester.pumpAndSettle();
    expect(
      find.descendant(
        of: find.byType(HostedTabBar),
        matching: nativeBar,
        skipOffstage: false,
      ),
      findsNothing,
    );
    expect(nativeBar, findsNWidgets(2));
  }, variant: ios);

  testWidgets('on the iPhone Duo the tabs stay in the vertical bar; held '
      'upright they are hosted at the bottom', (tester) async {
    useDuoLandscape(tester);
    final tabs = Tabs();
    addTearDown(tabs.dispose);
    final navigator = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      hostedApp(
        navigator,
        tabsPage(tabs),
        fold: forcedChrome(
          regions: const [
            ReservedRegion(
              kind: ReservedRegionKind.occlusion,
              bounds: Rect.fromLTRB(867, 0, 951, 120),
              isActive: true,
            ),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(HostedTabBar), findsNothing);
    expect(find.byType(HostedDuoBar), findsOneWidget);
    expect(nativeBar, findsNothing);
    expect(AdaptiveBottomBarInset.of(tabs.body), 0);

    useDuoUpright(tester);
    await tester.pumpWidget(
      hostedApp(navigator, tabsPage(tabs), fold: duoUpright()),
    );
    await tester.pumpAndSettle();
    expect(find.byType(HostedDuoBar), findsNothing);
    expect(
      find.descendant(
        of: find.byType(HostedTabBar),
        matching: find.byType(IOS26NativeTabBar),
      ),
      findsOneWidget,
    );
    expect(tester.getBottomLeft(nativeBar).dy, 951);
    expect(AdaptiveBottomBarInset.of(tabs.body), 50);
  }, variant: ios);

  testWidgets('on the iPhone Duo, a badge dot set on the tabs reaches the '
      'vertical bar while a tab page is in front', (tester) async {
    useDuoLandscape(tester);
    final tabs = Tabs();
    addTearDown(tabs.dispose);
    final navigator = GlobalKey<NavigatorState>();
    // Made once, as by an app that keeps its pages' app bars: only the tabs
    // page publishes itself again when the dot changes.
    final pages = [page('Map'), page('Account')];
    await tester.pumpWidget(
      hostedApp(
        navigator,
        tabsPage(tabs, children: pages),
        fold: forcedChrome(
          regions: const [
            ReservedRegion(
              kind: ReservedRegionKind.occlusion,
              bounds: Rect.fromLTRB(867, 0, 951, 120),
              isActive: true,
            ),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();

    bool dotShown() => tester
        .widgetList<DuoVerticalBar>(
          find.descendant(
            of: find.byType(HostedDuoBar),
            matching: find.byType(DuoVerticalBar),
          ),
        )
        .any((bar) => bar.tabBar?.items?[1].showsBadgeDot ?? false);
    expect(dotShown(), isFalse);

    // Only the tabs page republishes itself; the page in front does not.
    tabs.dot.value = true;
    await tester.pumpAndSettle();
    expect(dotShown(), isTrue);
  }, variant: ios);

  testWidgets('the blend tells its listeners only when there is something '
      'new to show', (tester) async {
    final registry = ToolbarRegistry();
    final blend = ToolbarBlend(registry: registry, vsync: const TestVSync());
    addTearDown(() {
      blend.dispose();
      registry.dispose();
    });
    var told = 0;
    blend.addListener(() => told++);

    final entry = ToolbarEntry(
      id: 'page',
      appBar: null,
      route: null,
      navigator: null,
      visible: true,
    );
    registry.upsert(entry);
    await tester.pump();
    expect(blend.owner, same(entry));
    expect(told, 1);

    // The page republishing itself unchanged, as pages do on every push and
    // pop around them.
    registry.upsert(entry);
    await tester.pump();
    expect(told, 1);

    final changed = ToolbarEntry(
      id: 'page',
      appBar: const AdaptiveAppBar(title: 'Page'),
      route: null,
      navigator: null,
      visible: true,
    );
    registry.upsert(changed);
    await tester.pump();
    expect(blend.owner, same(changed));
    expect(told, 2);
  });

  testWidgets('without a host, a page with its own toolbar and tabs makes its '
      'bar once and keeps it off stage while covered', (tester) async {
    usePhone(tester);
    final navigator = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigator,
        home: AdaptiveScaffold(
          appBar: const AdaptiveAppBar(useNativeToolbar: true, title: 'Home'),
          bottomNavigationBar: AdaptiveBottomNavigationBar(
            selectedIndex: 0,
            onTap: (_) {},
            items: destinations,
          ),
          body: const SizedBox.expand(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tabBarsMade(), hasLength(1));
    expect(find.byType(IOS26NativeTabBar), findsOneWidget);

    navigator.currentState!.push(pageRoute('Detail'));
    await tester.pumpAndSettle();
    expect(find.byType(IOS26NativeTabBar), findsNothing);
    expect(nativeBar, findsOneWidget);

    navigator.currentState!.pop();
    await tester.pumpAndSettle();
    expect(find.byType(IOS26NativeTabBar), findsOneWidget);
    expect(tabBarsMade(), hasLength(1));
    expect(tabBarsThrownAway(), isEmpty);
  }, variant: ios);
}
