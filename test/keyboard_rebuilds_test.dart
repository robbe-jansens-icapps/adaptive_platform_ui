import 'package:adaptive_platform_ui/adaptive_platform_ui.dart';
import 'package:adaptive_platform_ui/src/toolbar/hosted_top_toolbar.dart';
import 'package:adaptive_platform_ui/src/widgets/ios26/ios26_scaffold.dart';
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
  setUp(() {
    PlatformInfo.debugPlatformOverride = TargetPlatform.iOS;
    PlatformInfo.debugIOSVersionOverride = 26;
  });

  tearDown(() {
    PlatformInfo.debugPlatformOverride = null;
    PlatformInfo.debugIOSVersionOverride = null;
    debugOnRebuildDirtyWidget = null;
  });

  testWidgets('the keyboard sliding in rebuilds neither the bars nor the '
      'scaffolds of the pages, only what hands them the new insets', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(402, 874);
    tester.view.devicePixelRatio = 1;
    tester.view.padding = const FakeViewPadding(top: 62, bottom: 34);
    tester.view.viewPadding = const FakeViewPadding(top: 62, bottom: 34);
    addTearDown(tester.view.reset);

    final navigator = GlobalKey<NavigatorState>();
    Widget page(String title) => AdaptiveScaffold(
      appBar: AdaptiveAppBar(title: title, useNativeToolbar: true),
      body: const Scaffold(body: TextField()),
    );
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigator,
        builder: (context, child) =>
            AdaptiveToolbarHost(debugFold: forcedChrome(), child: child!),
        home: page('Home'),
      ),
    );
    navigator.currentState!.push(
      MaterialPageRoute<void>(builder: (_) => page('Form')),
    );
    await tester.pumpAndSettle();

    final rebuilt = <Type>{};
    debugOnRebuildDirtyWidget = (element, _) =>
        rebuilt.add(element.widget.runtimeType);
    // A few frames of the keyboard on its way up.
    for (final inset in [40.0, 120.0, 230.0, 336.0]) {
      tester.view.viewInsets = FakeViewPadding(bottom: inset);
      await tester.pump();
    }

    expect(rebuilt, isNot(contains(AdaptiveToolbarHost)));
    expect(rebuilt, isNot(contains(HostedTopToolbar)));
    expect(rebuilt, isNot(contains(AdaptiveScaffold)));
    expect(rebuilt, isNot(contains(IOS26Scaffold)));
    // The page itself still makes room for the keyboard.
    expect(
      tester.getBottomLeft(find.byType(TextField)).dy,
      lessThanOrEqualTo(874 - 336),
    );
  });
}
