import 'package:adaptive_platform_ui/adaptive_platform_ui.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'custom_chrome_fixture.dart';

const backdrop = ValueKey<String>('backdrop');
const pageColor = Color(0xFF123456);

ValueListenable<double>? backEdge;
AdaptiveBarBackgroundSpec? lastBackground;

Widget _tabs(BuildContext context, AdaptiveTabBarSpec spec) => const SizedBox(height: 60);
Widget _title(BuildContext context, AdaptiveTitleSpec spec) => Text('title:${spec.title}', style: const TextStyle(fontSize: 8));
Widget _actions(BuildContext context, AdaptiveActionsSpec spec) => const SizedBox.square(dimension: 44);
Widget _back(BuildContext context, AdaptiveBackButtonSpec spec) {
  if (spec.style == AdaptiveBackButtonStyle.back) backEdge = spec.scrollEdge;
  return GestureDetector(onTap: spec.onPressed, child: const SizedBox.square(dimension: 44, child: Text('back')));
}

Widget _background(BuildContext context, AdaptiveBarBackgroundSpec spec) {
  lastBackground = spec;
  return ColoredBox(key: backdrop, color: spec.color!);
}

const chrome = AdaptiveChrome(
  tabBarBuilder: _tabs,
  titleBuilder: _title,
  backButtonBuilder: _back,
  actionsBuilder: _actions,
  barBackgroundBuilder: _background,
);

Widget listPage(String title, {Color color = pageColor, ScrollController? controller}) => AdaptiveScaffold(
  backgroundColor: color,
  appBar: AdaptiveAppBar(title: title),
  body: ListView(
    key: ValueKey<String>('list $title'),
    controller: controller,
    children: [for (var i = 0; i < 60; i++) SizedBox(height: 60, child: Text('$title row $i'))],
  ),
);

Widget plainPage(String title, {Color color = const Color(0xFFFFFFFF)}) => AdaptiveScaffold(
  backgroundColor: color,
  appBar: AdaptiveAppBar(title: title),
  body: const SizedBox.expand(),
);

void main() {
  final navigator = GlobalKey<NavigatorState>();

  setUp(() {
    backEdge = null;
    lastBackground = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform_views, (_) async => null);
  });

  tearDown(() {
    PlatformInfo.debugPlatformOverride = null;
    PlatformInfo.debugIOSVersionOverride = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform_views, null);
  });

  void phone(WidgetTester tester) {
    PlatformInfo.debugPlatformOverride = TargetPlatform.android;
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    tester.view.padding = const FakeViewPadding(top: 47, bottom: 34);
    tester.view.viewPadding = const FakeViewPadding(top: 47, bottom: 34);
    addTearDown(tester.view.reset);
  }

  Future<void> pumpApp(WidgetTester tester, Widget home) async {
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigator,
        builder: (context, child) => AdaptiveToolbarHost(chrome: chrome, child: child!),
        home: home,
      ),
    );
    await tester.pumpAndSettle();
  }

  double backdropOpacity(WidgetTester tester) => tester.widget<Opacity>(find.ancestor(of: find.byKey(backdrop), matching: find.byType(Opacity)).first).opacity;

  testWidgets('the bar\'s background is only there as far as content has scrolled under the bar, in the page\'s colour', (tester) async {
    phone(tester);
    final controller = ScrollController();
    addTearDown(controller.dispose);
    await pumpApp(tester, listPage('List', controller: controller));

    expect(backdropOpacity(tester), 0);
    expect(lastBackground!.color, pageColor);

    controller.jumpTo(12);
    await tester.pump();
    expect(backdropOpacity(tester), closeTo(12 / AdaptiveScrollEdge.distance, 0.01));
    expect(lastBackground!.scrollEdge.value, closeTo(12 / AdaptiveScrollEdge.distance, 0.01));

    await tester.drag(find.byKey(const ValueKey<String>('list List')), const Offset(0, -200));
    await tester.pumpAndSettle();
    expect(backdropOpacity(tester), 1);

    await tester.drag(find.byKey(const ValueKey<String>('list List')), const Offset(0, 2000));
    await tester.pumpAndSettle();
    expect(backdropOpacity(tester), 0);
  });

  testWidgets('each page brings its own: a page pushed over a scrolled list has none until it scrolls, and the list has it again on the way back', (tester) async {
    phone(tester);
    await pumpApp(tester, listPage('List'));
    await tester.drag(find.byKey(const ValueKey<String>('list List')), const Offset(0, -300));
    await tester.pumpAndSettle();
    expect(backdropOpacity(tester), 1);

    navigator.currentState!.push(MaterialPageRoute<void>(builder: (_) => listPage('Detail', color: const Color(0xFF654321))));
    await tester.pumpAndSettle();
    expect(backdropOpacity(tester), 0);
    expect(lastBackground!.color, const Color(0xFF654321));
    expect(backEdge!.value, 0);

    await tester.drag(find.byKey(const ValueKey<String>('list Detail')), const Offset(0, -300));
    await tester.pumpAndSettle();
    expect(backEdge!.value, 1);

    await tester.tap(find.text('back'));
    await tester.pumpAndSettle();
    expect(backdropOpacity(tester), 1);
    expect(lastBackground!.color, pageColor);
  });

  testWidgets('the outermost scroll view decides: a list below a header that stays under the bar does not bring the background back', (tester) async {
    phone(tester);
    final outer = ScrollController();
    final inner = ScrollController();
    addTearDown(outer.dispose);
    addTearDown(inner.dispose);
    await pumpApp(
      tester,
      AdaptiveScaffold(
        appBar: const AdaptiveAppBar(title: 'Nested'),
        body: CustomScrollView(
          controller: outer,
          slivers: [
            const SliverToBoxAdapter(child: SizedBox(height: 200)),
            SliverToBoxAdapter(
              child: SizedBox(
                height: 400,
                child: ListView(controller: inner, children: [for (var i = 0; i < 40; i++) const SizedBox(height: 60)]),
              ),
            ),
          ],
        ),
      ),
    );

    inner.jumpTo(300);
    await tester.pump();
    expect(backdropOpacity(tester), 0);

    outer.jumpTo(100);
    await tester.pump();
    expect(backdropOpacity(tester), 1);

    inner.jumpTo(0);
    await tester.pump();
    expect(backdropOpacity(tester), 1);

    outer.jumpTo(0);
    await tester.pump();
    expect(backdropOpacity(tester), 0);
  });

  testWidgets('content that only scrolls sideways leaves the bar clear', (tester) async {
    phone(tester);
    await pumpApp(
      tester,
      AdaptiveScaffold(
        appBar: const AdaptiveAppBar(title: 'Carousel'),
        body: ListView(
          key: const ValueKey<String>('carousel'),
          scrollDirection: Axis.horizontal,
          children: [for (var i = 0; i < 20; i++) const SizedBox(width: 200)],
        ),
      ),
    );

    await tester.drag(find.byKey(const ValueKey<String>('carousel')), const Offset(-400, 0));
    await tester.pumpAndSettle();
    expect(backdropOpacity(tester), 0);
  });

  testWidgets('beside the iPhone Duo\'s vertical bar the strip takes the colour of the page in front, so the bar reads as part of the page', (tester) async {
    PlatformInfo.debugPlatformOverride = TargetPlatform.iOS;
    PlatformInfo.debugIOSVersionOverride = 26;
    tester.view.physicalSize = const Size(466, 678);
    tester.view.devicePixelRatio = 1;
    tester.view.padding = const FakeViewPadding(right: 84);
    tester.view.viewPadding = const FakeViewPadding(right: 84);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigator,
        builder: (context, child) => AdaptiveToolbarHost(chrome: chrome, debugFold: duo(), child: child!),
        home: plainPage('First', color: const Color(0xFFAA0000)),
      ),
    );
    await tester.pumpAndSettle();

    Color band() => tester.widget<ColoredBox>(find.descendant(of: find.byKey(const ValueKey<String>('adaptive_duo_band')), matching: find.byType(ColoredBox))).color;
    expect(tester.getRect(find.byKey(const ValueKey<String>('adaptive_duo_band'))), const Rect.fromLTRB(382, 0, 466, 678));
    expect(band(), const Color(0xFFAA0000));

    navigator.currentState!.push(MaterialPageRoute<void>(builder: (_) => plainPage('Second', color: const Color(0xFF0000AA))));
    await tester.pumpAndSettle();
    expect(band(), const Color(0xFF0000AA));

    await tester.tap(find.text('back'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 150));
    expect(band(), isNot(anyOf(const Color(0xFFAA0000), const Color(0xFF0000AA))));
    await tester.pumpAndSettle();
    expect(band(), const Color(0xFFAA0000));
  });
}
