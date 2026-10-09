import 'package:adaptive_platform_ui/adaptive_platform_ui.dart';
import 'package:adaptive_platform_ui/src/toolbar/duo_vertical_bar.dart';
import 'package:adaptive_platform_ui/src/toolbar/hosted_top_toolbar.dart';
import 'package:flutter/cupertino.dart';
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

const pageBackground = Color(0xFFF2F4F5);

Widget scrollingPage(
  String title, {
  Color? edge = pageBackground,
  Axis axis = Axis.vertical,
}) => AdaptiveScaffold(
  appBar: AdaptiveAppBar(
    title: title,
    useNativeToolbar: true,
    scrollEdgeColor: edge,
  ),
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

/// Opacity of the scroll edge effect of the fixed toolbar.
double effectOpacity(WidgetTester tester) => tester
    .widget<AnimatedOpacity>(
      find.descendant(
        of: find.byType(ScrollEdgeEffect),
        matching: find.byType(AnimatedOpacity),
      ),
    )
    .opacity;

/// The color at the top of the effect, where content fades furthest.
Color effectColor(WidgetTester tester) {
  final box = tester.widget<DecoratedBox>(
    find.descendant(
      of: find.byType(ScrollEdgeEffect),
      matching: find.byType(DecoratedBox),
    ),
  );
  final gradient =
      (box.decoration as BoxDecoration).gradient! as LinearGradient;
  return gradient.colors.first;
}

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

    expect(find.byType(ScrollEdgeEffect), findsOneWidget);
    expect(effectOpacity(tester), 0);
  });

  testWidgets('content scrolled under the bar blurs into the page background', (
    tester,
  ) async {
    usePhone(tester);
    await tester.pumpWidget(hostedApp(home: scrollingPage('Settings')));
    await tester.pumpAndSettle();

    await tester.drag(find.byType(ListView), const Offset(0, -300));
    await tester.pumpAndSettle();

    expect(effectOpacity(tester), 1);
    expect(effectColor(tester), pageBackground.withValues(alpha: 0.8));
    // A blur that eases off in bands, none under a mask: iOS blurs nothing
    // under one once native views are on screen.
    expect(
      find.descendant(
        of: find.byType(ScrollEdgeEffect),
        matching: find.byType(BackdropFilter),
      ),
      findsNWidgets(4),
    );
    expect(
      find.descendant(
        of: find.byType(ScrollEdgeEffect),
        matching: find.byType(ShaderMask),
      ),
      findsNothing,
    );

    // Back at the top it clears again.
    await tester.drag(find.byType(ListView), const Offset(0, 600));
    await tester.pumpAndSettle();

    expect(effectOpacity(tester), 0);
  });

  testWidgets('fades into the system background by default', (tester) async {
    usePhone(tester);
    await tester.pumpWidget(
      hostedApp(home: scrollingPage('Settings', edge: null)),
    );
    await tester.pumpAndSettle();

    expect(
      effectColor(tester),
      CupertinoColors.systemBackground.color.withValues(alpha: 0.8),
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

    expect(effectOpacity(tester), 0);
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
    expect(effectOpacity(tester), 1);

    // A new page starts at its top.
    nav.currentState!.push(
      MaterialPageRoute<void>(builder: (_) => scrollingPage('General')),
    );
    await tester.pumpAndSettle();
    expect(effectOpacity(tester), 0);

    // The page underneath is still scrolled when it comes back.
    nav.currentState!.pop();
    await tester.pumpAndSettle();
    expect(effectOpacity(tester), 1);
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

    expect(
      find.descendant(
        of: find.byType(ScrollEdgeEffect),
        matching: find.byType(DuoTitleBackdrop),
      ),
      findsOneWidget,
    );
    expect(effectOpacity(tester), 0);

    await tester.drag(find.byType(ListView), const Offset(0, -300));
    await tester.pumpAndSettle();

    expect(effectOpacity(tester), 1);
    expect(effectColor(tester), pageBackground.withValues(alpha: 0.8));
  });
}
