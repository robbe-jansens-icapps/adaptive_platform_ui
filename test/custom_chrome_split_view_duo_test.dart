import 'package:adaptive_platform_ui/adaptive_platform_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:foldable/foldable.dart';

import 'custom_chrome_fixture.dart';

const _detailColor = Color(0xFFFF8800);

Route<dynamic>? _detail(RouteSettings settings) => MaterialPageRoute<void>(
  settings: settings,
  builder: (_) => const AdaptiveScaffold(
    backgroundColor: _detailColor,
    appBar: AdaptiveAppBar(title: 'Detail'),
    body: SizedBox.expand(key: ValueKey<String>('detail body')),
  ),
);

void main() {
  setUp(() {
    PlatformInfo.debugPlatformOverride = TargetPlatform.iOS;
    PlatformInfo.debugIOSVersionOverride = 26;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          SystemChannels.platform_views,
          (_) async => null,
        );
  });

  tearDown(() {
    PlatformInfo.debugPlatformOverride = null;
    PlatformInfo.debugIOSVersionOverride = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform_views, null);
  });

  void innerLandscape(WidgetTester tester) {
    tester.view.physicalSize = const Size(951, 669);
    tester.view.devicePixelRatio = 1;
    tester.view.padding = const FakeViewPadding(right: 84, bottom: 34);
    tester.view.viewPadding = const FakeViewPadding(right: 84, bottom: 34);
    addTearDown(tester.view.reset);
  }

  testWidgets(
    'on the iPhone Duo the column beside the list runs on under the vertical bar, its content clear of it',
    (tester) async {
      innerLandscape(tester);
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => AdaptiveToolbarHost(
            chrome: TestChrome.chrome,
            debugFold: duo(),
            child: child!,
          ),
          home: const AdaptiveSplitView(
            onGenerateDetailRoute: _detail,
            initialDetail: RouteSettings(name: '/detail'),
            master: AdaptiveScaffold(
              appBar: AdaptiveAppBar(title: 'List'),
              body: SizedBox.expand(key: ValueKey<String>('list body')),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final detailPage = find
          .ancestor(
            of: find.byKey(const ValueKey<String>('detail body')),
            matching: find.byType(Scaffold),
          )
          .first;
      expect(tester.getRect(detailPage).right, 951);
      expect(
        tester.getRect(find.byKey(const ValueKey<String>('detail body'))).right,
        951 - 84,
      );
      expect(
        tester.getRect(find.byKey(const ValueKey<String>('list body'))).right,
        lessThan(tester.getRect(detailPage).left),
      );
    },
  );

  testWidgets(
    'on the iPhone Duo the list\'s pinned search moves out of the way while it scrolls on, and comes back as it scrolls back',
    (tester) async {
      innerLandscape(tester);
      const pinned = ValueKey<String>('pinned');
      const list = ValueKey<String>('list');
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => AdaptiveToolbarHost(
            chrome: TestChrome.chrome,
            debugFold: duo(),
            child: child!,
          ),
          home: AdaptiveSplitView(
            onGenerateDetailRoute: _detail,
            initialDetail: const RouteSettings(name: '/detail'),
            master: AdaptiveScaffold(
              body: AdaptiveSafeAreaBar(
                bar: const SizedBox(key: pinned, height: 56),
                child: ListView(
                  key: list,
                  children: [
                    for (var i = 0; i < 60; i++) const SizedBox(height: 60),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      double shown() => tester
          .widget<Opacity>(
            find
                .ancestor(
                  of: find.byKey(pinned),
                  matching: find.byType(Opacity),
                )
                .first,
          )
          .opacity;

      await tester.drag(find.byKey(list), const Offset(0, -300));
      await tester.pumpAndSettle();
      expect(shown(), 0);

      await tester.drag(find.byKey(list), const Offset(0, 40));
      await tester.pumpAndSettle();
      expect(
        find.ancestor(of: find.byKey(pinned), matching: find.byType(Opacity)),
        findsNothing,
      );
    },
  );

  testWidgets('the controls of a bar keep the chrome\'s inset from its sides', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    tester.view.padding = const FakeViewPadding(top: 47, bottom: 34);
    tester.view.viewPadding = const FakeViewPadding(top: 47, bottom: 34);
    addTearDown(tester.view.reset);
    final navigator = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigator,
        builder: (context, child) => AdaptiveToolbarHost(
          chrome: TestChrome.chrome.copyWithMetrics(
            const AdaptiveChromeMetrics(controlInset: 24),
          ),
          debugFold: FoldableData.unsupported,
          child: child!,
        ),
        home: const AdaptiveScaffold(
          appBar: AdaptiveAppBar(title: 'Root'),
          body: SizedBox.expand(),
        ),
      ),
    );
    navigator.currentState!.push(
      MaterialPageRoute<void>(
        builder: (_) => const AdaptiveScaffold(
          appBar: AdaptiveAppBar(title: 'Pushed'),
          body: SizedBox.expand(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.getRect(find.text('back')).center.dx, 24 + 22);
  });
}
