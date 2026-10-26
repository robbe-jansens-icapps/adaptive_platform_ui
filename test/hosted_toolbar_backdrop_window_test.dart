import 'package:adaptive_platform_ui/adaptive_platform_ui.dart';
import 'package:adaptive_platform_ui/src/toolbar/hosted_top_toolbar.dart';
import 'package:flutter/cupertino.dart' show CupertinoPageRoute;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:foldable/foldable.dart';

/// Forces the chrome on (there is no iOS 26 in a widget test).
FoldableData forcedChrome() => FoldableData(
  capabilities: FoldableData.unsupported.capabilities,
  status: FoldableData.unsupported.status,
  angleDegrees: FoldableData.unsupported.angleDegrees,
  regions: const [],
  displayFeatures: const [],
);

const _grey = Color(0xFFF2F2F7);

Widget hostedApp({
  required Widget home,
  GlobalKey<NavigatorState>? navigatorKey,
}) => MaterialApp(
  navigatorKey: navigatorKey,
  builder: (context, child) =>
      AdaptiveToolbarHost(debugFold: forcedChrome(), child: child!),
  home: home,
);

Widget page(String title, {Color? backdropColor, Widget? body}) =>
    AdaptiveScaffold(
      appBar: AdaptiveAppBar(
        title: title,
        useNativeToolbar: true,
        backdropColor: backdropColor,
      ),
      body: body ?? Center(child: Text('body:$title')),
    );

/// A window [size] large, on a display [display] large, without any room at
/// its top: the left half of an iPhone Duo in split view.
void useWindow(
  WidgetTester tester, {
  Size size = const Size(402, 874),
  Size? display,
}) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  tester.view.padding = FakeViewPadding.zero;
  tester.view.viewPadding = FakeViewPadding.zero;
  tester.view.display.size = display ?? size;
  addTearDown(tester.view.reset);
  addTearDown(tester.view.display.resetSize);
}

Finder get bar => find.byType(HostedTopToolbar);

/// The bar's backdrop.
Finder get frost =>
    find.descendant(of: bar, matching: find.byType(AdaptiveBarBackdrop));

/// How far the backdrop is in as the page's content scrolls under it.
double frostShown(WidgetTester tester) => tester
    .widget<Opacity>(
      find.ancestor(of: frost, matching: find.byType(Opacity)).first,
    )
    .opacity;

/// The opacity the backdrop is drawn at, all fades around it together.
double backdropOpacity(WidgetTester tester) {
  final backdrop = find.descendant(
    of: bar,
    matching: find.byKey(const ValueKey<String>('adaptive_toolbar_backdrop')),
  );
  return tester
      .widgetList<FadeTransition>(
        find.descendant(
          of: backdrop,
          matching: find.byType(FadeTransition),
          matchRoot: true,
        ),
      )
      .fold<double>(1, (opacity, fade) => opacity * fade.opacity.value);
}

/// The iOS 26 scaffold, which tells the bar how far its page has scrolled,
/// in a 402 by 874 window below a 62 point status bar.
void useIOS26Phone(WidgetTester tester) {
  PlatformInfo.debugPlatformOverride = TargetPlatform.iOS;
  PlatformInfo.debugIOSVersionOverride = 26;
  final views =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  views.setMockMethodCallHandler(
    SystemChannels.platform_views,
    (_) async => null,
  );
  addTearDown(() {
    PlatformInfo.debugPlatformOverride = null;
    PlatformInfo.debugIOSVersionOverride = null;
    views.setMockMethodCallHandler(SystemChannels.platform_views, null);
  });
  useWindow(tester);
  tester.view.padding = const FakeViewPadding(top: 62);
  tester.view.viewPadding = const FakeViewPadding(top: 62);
}

/// An overview scrolled under the bar.
Future<void> pumpScrolledOverview(
  WidgetTester tester,
  GlobalKey<NavigatorState> nav,
) async {
  final controller = ScrollController();
  addTearDown(controller.dispose);
  await tester.pumpWidget(
    hostedApp(
      navigatorKey: nav,
      home: page(
        'Overview',
        backdropColor: _grey,
        body: ListView(
          controller: controller,
          children: [for (var i = 0; i < 40; i++) const SizedBox(height: 60)],
        ),
      ),
    ),
  );
  await tester.pump();
  controller.jumpTo(200);
  await tester.pump();
  expect(frostShown(tester), 1);
}

/// Pushes a detail page that has not scrolled; returns its route.
CupertinoPageRoute<void> pushDetail(GlobalKey<NavigatorState> nav) {
  final detail = CupertinoPageRoute<void>(
    builder: (_) => page('Detail', backdropColor: _grey),
  );
  nav.currentState!.push(detail);
  return detail;
}

void main() {
  tearDown(() => PlatformInfo.debugIPadOverride = null);

  group('between a scrolled page and one that is not', () {
    testWidgets('the backdrop goes as the scrolled page slides away', (
      tester,
    ) async {
      useIOS26Phone(tester);
      final nav = GlobalKey<NavigatorState>();
      await pumpScrolledOverview(tester, nav);

      final detail = pushDetail(nav);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 100));
      final slid = Curves.fastEaseInToSlowEaseOut.transform(
        detail.animation!.value,
      );
      expect(frostShown(tester), moreOrLessEquals(1 - slid, epsilon: 0.01));
      expect(frostShown(tester), inExclusiveRange(0, 1));

      await tester.pumpAndSettle();
      expect(frostShown(tester), 0);
    });

    testWidgets('the backdrop comes back with the scrolled page', (
      tester,
    ) async {
      useIOS26Phone(tester);
      final nav = GlobalKey<NavigatorState>();
      await pumpScrolledOverview(tester, nav);
      final detail = pushDetail(nav);
      await tester.pumpAndSettle();
      expect(frostShown(tester), 0);

      nav.currentState!.pop();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      // A fifth of the way into the pop, the overview is about half in.
      expect(frostShown(tester), greaterThan(0.3));
      await tester.pump(const Duration(milliseconds: 100));
      final slid = Curves.fastEaseInToSlowEaseOut.flipped.transform(
        detail.animation!.value,
      );
      expect(frostShown(tester), moreOrLessEquals(1 - slid, epsilon: 0.01));
      expect(frostShown(tester), inExclusiveRange(0, 1));

      await tester.pumpAndSettle();
      expect(frostShown(tester), 1);
    });

    testWidgets('the backdrop follows a back swipe, and goes when it is let '
        'go', (tester) async {
      useIOS26Phone(tester);
      final nav = GlobalKey<NavigatorState>();
      await pumpScrolledOverview(tester, nav);
      final detail = pushDetail(nav);
      await tester.pumpAndSettle();
      expect(frostShown(tester), 0);

      final gesture = await tester.startGesture(const Offset(4, 400));
      await gesture.moveBy(const Offset(40, 0));
      await tester.pump();
      await gesture.moveBy(const Offset(120, 0));
      await tester.pump();
      expect(detail.animation!.value, inExclusiveRange(0, 1));
      // Under the finger, without easing.
      expect(
        frostShown(tester),
        moreOrLessEquals(1 - detail.animation!.value, epsilon: 0.01),
      );

      // Back to the start, and let go: the detail page stays.
      await gesture.moveBy(const Offset(-160, 0));
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle();
      expect(find.text('body:Detail'), findsOneWidget);
      expect(frostShown(tester), 0);
    });
  });

  testWidgets(
    'the backdrop is the content blurred in the colour of the page it sits on, down to the bottom of the bar, once content scrolls under it',
    (tester) async {
      PlatformInfo.debugPlatformOverride = TargetPlatform.iOS;
      PlatformInfo.debugIOSVersionOverride = 26;
      final views = TestDefaultBinaryMessengerBinding
          .instance
          .defaultBinaryMessenger;
      views.setMockMethodCallHandler(
        SystemChannels.platform_views,
        (_) async => null,
      );
      addTearDown(() {
        PlatformInfo.debugPlatformOverride = null;
        PlatformInfo.debugIOSVersionOverride = null;
        views.setMockMethodCallHandler(SystemChannels.platform_views, null);
      });
      useWindow(tester);
      tester.view.padding = const FakeViewPadding(top: 62);
      tester.view.viewPadding = const FakeViewPadding(top: 62);
      final controller = ScrollController();
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        hostedApp(
          home: page(
            'Grey',
            backdropColor: _grey,
            body: ListView(
              controller: controller,
              children: [
                for (var i = 0; i < 40; i++) const SizedBox(height: 60),
              ],
            ),
          ),
        ),
      );
      await tester.pump();

      expect(tester.widget<AdaptiveBarBackdrop>(frost).color, _grey);
      // Some room below the controls, clear of the back button.
      expect(
        tester.getRect(frost).bottom,
        62 + kHostedToolbarHeight + kHostedToolbarBottomPadding,
      );
      expect(frostShown(tester), 0);

      controller.jumpTo(200);
      await tester.pump();
      expect(frostShown(tester), 1);
    },
  );

  testWidgets('the backdrop fades out while a sheet covers the page', (
    tester,
  ) async {
    useWindow(tester);
    tester.view.padding = const FakeViewPadding(top: 62);
    tester.view.viewPadding = const FakeViewPadding(top: 62);
    final nav = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      hostedApp(
        navigatorKey: nav,
        home: page('Grey', backdropColor: _grey),
      ),
    );
    await tester.pump();
    expect(backdropOpacity(tester), 1);

    showModalBottomSheet<void>(
      context: nav.currentContext!,
      builder: (_) => const SizedBox(height: 200),
    );
    await tester.pumpAndSettle();
    expect(backdropOpacity(tester), 0);

    nav.currentState!.pop();
    await tester.pumpAndSettle();
    expect(backdropOpacity(tester), 1);
  });

  testWidgets(
    'a window without room at its top keeps a margin above the bar and the page',
    (tester) async {
      // The iOS 26 scaffold, which insets its page below the hosted bar.
      PlatformInfo.debugPlatformOverride = TargetPlatform.iOS;
      PlatformInfo.debugIOSVersionOverride = 26;
      addTearDown(() {
        PlatformInfo.debugPlatformOverride = null;
        PlatformInfo.debugIOSVersionOverride = null;
      });
      useWindow(tester, display: const Size(804, 874));
      late EdgeInsets pagePadding;
      await tester.pumpWidget(
        hostedApp(
          home: page(
            'Split',
            body: Builder(
              builder: (context) {
                pagePadding = MediaQuery.paddingOf(context);
                return const SizedBox.expand();
              },
            ),
          ),
        ),
      );
      await tester.pump();

      // The bar fills its band: the margin and the toolbar.
      expect(
        tester
            .getSize(
              find.descendant(of: bar, matching: find.byType(Stack)).first,
            )
            .height,
        kHostedToolbarHeight + kHostedToolbarBottomPadding + kWindowTopMargin,
      );
      // The page starts below the bar, margin and all.
      expect(
        pagePadding.top,
        kWindowTopMargin + kHostedToolbarHeight + kHostedToolbarBottomPadding,
      );
    },
  );

  testWidgets(
    'the back button keeps clear of window controls on an iPad only',
    (tester) async {
      useWindow(tester, display: const Size(804, 874));
      final nav = GlobalKey<NavigatorState>();
      await tester.pumpWidget(hostedApp(navigatorKey: nav, home: page('Root')));
      await tester.pump();
      nav.currentState!.push(
        MaterialPageRoute<void>(builder: (_) => page('Detail')),
      );
      await tester.pumpAndSettle();
      final back = find.descendant(
        of: bar,
        matching: find.byType(AdaptiveButton),
      );

      // An iPhone Duo window in split view: no window controls.
      expect(tester.getTopLeft(back).dx, 16);

      PlatformInfo.debugIPadOverride = true;
      await tester.pumpWidget(hostedApp(navigatorKey: nav, home: page('Root')));
      await tester.pump();
      expect(tester.getTopLeft(back).dx, 16 + 62);
    },
  );
}
