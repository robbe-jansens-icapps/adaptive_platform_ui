import 'package:adaptive_platform_ui/adaptive_platform_ui.dart';
import 'package:adaptive_platform_ui/src/toolbar/hosted_top_toolbar.dart';
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

void main() {
  tearDown(() => PlatformInfo.debugIPadOverride = null);

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
