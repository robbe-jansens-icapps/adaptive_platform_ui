import 'package:adaptive_platform_ui/adaptive_platform_ui.dart';
import 'package:adaptive_platform_ui/src/toolbar/hosted_top_toolbar.dart';
import 'package:flutter/material.dart';
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

void main() {
  tearDown(() {
    PlatformInfo.debugPlatformOverride = null;
    PlatformInfo.debugIOSVersionOverride = null;
  });

  late GlobalKey<NavigatorState> navigator;

  Future<void> pumpApp(WidgetTester tester, {bool host = true}) async {
    navigator = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigator,
        builder: host
            ? (context, child) =>
                  AdaptiveToolbarHost(debugFold: forcedChrome(), child: child!)
            : null,
        home: const AdaptiveScaffold(
          appBar: AdaptiveAppBar(title: 'Debug', useNativeToolbar: true),
          body: SizedBox.expand(),
        ),
      ),
    );
    await tester.pump();
  }

  Future<void> show(
    WidgetTester tester,
    String text, {
    Duration duration = const Duration(seconds: 3),
  }) async {
    AdaptiveToast.show(
      navigator.currentContext!,
      duration: duration,
      builder: (dismiss) =>
          Padding(padding: const EdgeInsets.all(16), child: Text(text)),
    );
    await tester.pump();
  }

  testWidgets('shows above the fixed toolbar, not in the navigator under it', (
    tester,
  ) async {
    PlatformInfo.debugPlatformOverride = TargetPlatform.iOS;
    PlatformInfo.debugIOSVersionOverride = 26;
    await pumpApp(tester);

    await show(tester, 'Toast');
    await tester.pump(const Duration(milliseconds: 600));

    final toast = find.text('Toast');
    expect(toast, findsOneWidget);
    expect(
      find.ancestor(of: toast, matching: find.byType(Navigator)),
      findsNothing,
    );
    // Over the bar, on glass.
    final bar = tester.getRect(find.byType(HostedTopToolbar));
    expect(tester.getRect(toast).overlaps(bar), isTrue);
    expect(
      find.ancestor(of: toast, matching: find.byType(IOS26GlassSurface)),
      findsOneWidget,
    );
    final hit = tester.hitTestOnBinding(tester.getCenter(toast));
    expect(
      hit.path.any((entry) => entry.target == tester.renderObject(toast)),
      isTrue,
    );
    AdaptiveToast.clear();
    await tester.pumpAndSettle();
  });

  testWidgets('leaves the page below touchable while there is none', (
    tester,
  ) async {
    var taps = 0;
    navigator = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigator,
        builder: (context, child) =>
            AdaptiveToolbarHost(debugFold: forcedChrome(), child: child!),
        home: Scaffold(
          body: Center(
            child: TextButton(
              onPressed: () => taps++,
              child: const Text('Tap'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Tap'));
    expect(taps, 1);
  });

  testWidgets('slides in at the top and stays for its duration', (
    tester,
  ) async {
    await pumpApp(tester);

    await show(tester, 'Toast');
    await tester.pump(const Duration(seconds: 2));

    expect(find.text('Toast'), findsOneWidget);
    expect(tester.getTopLeft(find.text('Toast')).dy, lessThan(100));

    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();

    expect(find.text('Toast'), findsNothing);
  });

  testWidgets('a new toast replaces the one on screen', (tester) async {
    await pumpApp(tester);

    await show(tester, 'First');
    await show(tester, 'Second');
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.text('First'), findsNothing);
    expect(find.text('Second'), findsOneWidget);
    AdaptiveToast.clear();
    await tester.pumpAndSettle();
  });

  testWidgets('a tap takes it away, twice does no harm', (tester) async {
    await pumpApp(tester);
    await show(tester, 'Toast');
    await tester.pump(const Duration(milliseconds: 500));

    await tester.tap(find.text('Toast'));
    await tester.pump();
    await tester.tap(find.text('Toast'), warnIfMissed: false);
    await tester.pumpAndSettle();

    expect(find.text('Toast'), findsNothing);
  });

  testWidgets('can be swiped away', (tester) async {
    await pumpApp(tester);
    await show(tester, 'Toast');
    await tester.pump(const Duration(milliseconds: 500));

    await tester.fling(find.text('Toast'), const Offset(0, -200), 1000);
    await tester.pumpAndSettle();

    expect(find.text('Toast'), findsNothing);
    // Its timer was stopped with it.
    await tester.pump(const Duration(seconds: 3));
  });

  testWidgets('without a toolbar host, it goes in the root overlay', (
    tester,
  ) async {
    await pumpApp(tester, host: false);

    await show(tester, 'Toast');

    expect(find.text('Toast'), findsOneWidget);
    // A Material card where there is no glass.
    expect(
      find.ancestor(of: find.text('Toast'), matching: find.byType(Material)),
      findsWidgets,
    );
    AdaptiveToast.clear();
    await tester.pumpAndSettle();
  });

  testWidgets('the iOS snack bar shows above the fixed toolbar too', (
    tester,
  ) async {
    PlatformInfo.debugPlatformOverride = TargetPlatform.iOS;
    await pumpApp(tester);

    AdaptiveSnackBar.show(navigator.currentContext!, message: 'Saved');
    await tester.pump();

    expect(
      find.ancestor(of: find.text('Saved'), matching: find.byType(Navigator)),
      findsNothing,
    );
    await tester.pumpAndSettle(const Duration(seconds: 5));
  });
}
