import 'package:adaptive_platform_ui/adaptive_platform_ui.dart';
import 'package:adaptive_platform_ui/src/toolbar/duo_vertical_bar.dart';
import 'package:adaptive_platform_ui/src/toolbar/hosted_top_toolbar.dart';
import 'package:adaptive_platform_ui/src/widgets/ios26/ios26_bar_backdrop.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:foldable/foldable.dart';

/// Forces the chrome on; the insets are those of an ordinary iPhone.
FoldableData forcedChrome() => FoldableData(
  capabilities: FoldableData.unsupported.capabilities,
  status: FoldableData.unsupported.status,
  angleDegrees: FoldableData.unsupported.angleDegrees,
  regions: const [],
  displayFeatures: const [],
);

Widget scrollingPage(String? title, {Axis axis = Axis.vertical}) =>
    AdaptiveScaffold(
      appBar: title == null
          ? null
          : AdaptiveAppBar(title: title, useNativeToolbar: true),
      body: ListView(
        key: ValueKey('list:$title'),
        scrollDirection: axis,
        children: [
          for (var i = 0; i < 60; i++)
            SizedBox(height: 60, width: 80, child: Text('$title $i')),
        ],
      ),
    );

Widget hostedApp({
  required Widget home,
  GlobalKey<NavigatorState>? navigatorKey,
}) => MaterialApp(
  navigatorKey: navigatorKey,
  builder: (context, child) =>
      AdaptiveToolbarHost(debugFold: forcedChrome(), child: child!),
  home: home,
);

void usePhone(WidgetTester tester) {
  tester.view.physicalSize = const Size(402, 874);
  tester.view.devicePixelRatio = 1;
  tester.view.padding = const FakeViewPadding(top: 62, bottom: 34);
  tester.view.viewPadding = const FakeViewPadding(top: 62, bottom: 34);
  addTearDown(tester.view.reset);
}

/// Whether the native blur behind the fixed toolbar is shown.
bool backdropVisible(WidgetTester tester) =>
    tester.widget<IOS26BarBackdrop>(find.byType(IOS26BarBackdrop)).visible;

void main() {
  setUp(() {
    // The iOS 26 path of AdaptiveScaffold; native views draw their Flutter
    // stand-ins here.
    PlatformInfo.debugPlatformOverride = TargetPlatform.iOS;
    PlatformInfo.debugIOSVersionOverride = 26;
  });

  tearDown(() {
    PlatformInfo.debugPlatformOverride = null;
    PlatformInfo.debugIOSVersionOverride = null;
  });

  testWidgets('the bar is clear while the page is at its top', (tester) async {
    usePhone(tester);
    await tester.pumpWidget(hostedApp(home: scrollingPage('Settings')));
    await tester.pumpAndSettle();

    expect(backdropVisible(tester), isFalse);
  });

  testWidgets('content scrolled under the bar brings in the native blur', (
    tester,
  ) async {
    usePhone(tester);
    await tester.pumpWidget(hostedApp(home: scrollingPage('Settings')));
    await tester.pumpAndSettle();

    await tester.drag(find.byType(ListView), const Offset(0, -300));
    await tester.pumpAndSettle();

    expect(backdropVisible(tester), isTrue);

    // Back at the top it clears again.
    await tester.drag(find.byType(ListView), const Offset(0, 600));
    await tester.pumpAndSettle();

    expect(backdropVisible(tester), isFalse);
  });

  testWidgets('the toolbar draws no blur or fade of its own', (tester) async {
    usePhone(tester);
    await tester.pumpWidget(hostedApp(home: scrollingPage('Settings')));
    await tester.pumpAndSettle();
    await tester.drag(find.byType(ListView), const Offset(0, -300));
    await tester.pumpAndSettle();

    final inToolbar = find.byType(HostedTopToolbar);
    for (final type in [BackdropFilter, ShaderMask, DecoratedBox]) {
      expect(
        find.descendant(of: inToolbar, matching: find.byType(type)),
        findsNothing,
        reason: '$type',
      );
    }
    // Nor is the blur faded with the chrome, which would break it.
    expect(
      find.ancestor(
        of: find.byType(IOS26BarBackdrop),
        matching: find.byType(FadeTransition),
      ),
      findsNothing,
    );
  });

  testWidgets('a sideways list under the bar does not count', (tester) async {
    usePhone(tester);
    await tester.pumpWidget(
      hostedApp(home: scrollingPage('Photos', axis: Axis.horizontal)),
    );
    await tester.pumpAndSettle();

    await tester.drag(find.byType(ListView), const Offset(-300, 0));
    await tester.pumpAndSettle();

    expect(backdropVisible(tester), isFalse);
  });

  testWidgets('stays clear on a page without a bar', (tester) async {
    usePhone(tester);
    await tester.pumpWidget(hostedApp(home: scrollingPage(null)));
    await tester.pumpAndSettle();

    await tester.drag(find.byType(ListView), const Offset(0, -300));
    await tester.pumpAndSettle();

    expect(backdropVisible(tester), isFalse);
  });

  testWidgets('follows the page in front', (tester) async {
    usePhone(tester);
    final nav = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      hostedApp(navigatorKey: nav, home: scrollingPage('Settings')),
    );
    await tester.pumpAndSettle();
    await tester.drag(find.byType(ListView), const Offset(0, -300));
    await tester.pumpAndSettle();
    expect(backdropVisible(tester), isTrue);

    // A new page starts at its top.
    nav.currentState!.push(
      MaterialPageRoute<void>(builder: (_) => scrollingPage('General')),
    );
    await tester.pumpAndSettle();
    expect(backdropVisible(tester), isFalse);

    // The page underneath is still scrolled when it comes back.
    nav.currentState!.pop();
    await tester.pumpAndSettle();
    expect(backdropVisible(tester), isTrue);
  });

  testWidgets('the iPhone Duo title band clears the same way', (tester) async {
    tester.view.physicalSize = const Size(466, 678);
    tester.view.devicePixelRatio = 1;
    // The strip pose of the cover display: no top inset, a strip on the right.
    tester.view.padding = const FakeViewPadding(right: 60, bottom: 20);
    tester.view.viewPadding = const FakeViewPadding(right: 60, bottom: 20);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(hostedApp(home: scrollingPage('Settings')));
    await tester.pumpAndSettle();

    expect(backdropVisible(tester), isFalse);
    expect(
      tester.getSize(find.byType(IOS26BarBackdrop)).height,
      kDuoTitleBandHeight + kBarBackdropFade,
    );

    await tester.drag(find.byType(ListView), const Offset(0, -300));
    await tester.pumpAndSettle();

    expect(backdropVisible(tester), isTrue);
  });

  testWidgets('without UIKit the backdrop draws nothing', (tester) async {
    await tester.pumpWidget(
      const Directionality(
        textDirection: TextDirection.ltr,
        child: IOS26BarBackdrop(visible: true),
      ),
    );

    expect(find.byType(UiKitView), findsNothing);
    expect(find.byType(BackdropFilter), findsNothing);
  });
}
