import 'package:adaptive_platform_ui/adaptive_platform_ui.dart';
import 'package:adaptive_platform_ui/src/toolbar/duo_vertical_bar.dart';
import 'package:adaptive_platform_ui/src/toolbar/hosted_duo_bar.dart';
import 'package:adaptive_platform_ui/src/toolbar/hosted_top_toolbar.dart';
import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:foldable/foldable.dart';

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

final root = GlobalKey<NavigatorState>();

Route<dynamic>? detailRoute(RouteSettings settings) {
  final name = settings.arguments! as String;
  return MaterialPageRoute<void>(
    settings: settings,
    builder: (_) => AdaptiveScaffold(
      appBar: AdaptiveAppBar(
        title: 'Detail $name',
        onBack: () => root.currentState!.pop(),
        automaticallyImplyLeading: false,
      ),
      body: Center(
        child: TextButton(
          onPressed: () => AdaptiveSplitView.showDetail(
            RouteSettings(name: '/detail', arguments: '$name+'),
          ),
          child: Text('More $name'),
        ),
      ),
    ),
  );
}

Finder inBar(Finder finder) =>
    find.descendant(of: find.byType(HostedDuoBar), matching: finder);

void main() {
  testWidgets('in the iPhone Duo vertical bar pose the pages beside the list '
      'hand their back button to the vertical bar and keep their titles', (
    tester,
  ) async {
    // The inner display in landscape: the vertical bar on the right.
    tester.view.physicalSize = const Size(951, 669);
    tester.view.devicePixelRatio = 1;
    tester.view.padding = const FakeViewPadding(right: 84, bottom: 34);
    tester.view.viewPadding = const FakeViewPadding(right: 84, bottom: 34);
    addTearDown(tester.view.reset);
    var closes = 0;
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: root,
        builder: (context, child) =>
            AdaptiveToolbarHost(debugFold: duoInnerDisplay(), child: child!),
        home: const SizedBox.expand(),
      ),
    );
    root.currentState!.push(
      MaterialPageRoute<void>(
        builder: (_) => AdaptiveSplitView(
          onGenerateDetailRoute: detailRoute,
          initialDetail: const RouteSettings(name: '/detail', arguments: 'A'),
          master: AdaptiveScaffold(
            appBar: AdaptiveAppBar(
              title: 'Support',
              onBack: () => closes++,
              backButtonStyle: AdaptiveBackButtonStyle.close,
              automaticallyImplyLeading: false,
            ),
            body: const Center(child: Text('list')),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // The first page beside the list has nothing to go back to: the bar
    // holds the cross of the list's page.
    expect(inBar(find.byIcon(CupertinoIcons.xmark)), findsOneWidget);
    expect(inBar(find.byIcon(CupertinoIcons.chevron_left)), findsNothing);
    // No title of theirs at the top of the window: each keeps its own.
    expect(
      find.descendant(
        of: find.byType(HostedTopToolbar),
        matching: find.textContaining(RegExp('Support|Detail')),
      ),
      findsNothing,
    );

    await tester.tap(find.text('More A'));
    await tester.pumpAndSettle();
    expect(inBar(find.byIcon(CupertinoIcons.chevron_left)), findsOneWidget);

    await tester.tap(inBar(find.byType(DuoBarBackButton)));
    await tester.pumpAndSettle();
    expect(find.text('More A+'), findsNothing);
    expect(find.text('More A'), findsOneWidget);
    expect(find.text('list'), findsOneWidget);
    expect(inBar(find.byIcon(CupertinoIcons.xmark)), findsOneWidget);

    await tester.tap(inBar(find.byType(DuoBarBackButton)));
    expect(closes, 1);
  });
}
