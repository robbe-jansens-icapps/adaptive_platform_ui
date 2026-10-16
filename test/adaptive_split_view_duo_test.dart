import 'package:adaptive_platform_ui/adaptive_platform_ui.dart';
import 'package:adaptive_platform_ui/src/toolbar/duo_vertical_bar.dart';
import 'package:adaptive_platform_ui/src/toolbar/hosted_duo_bar.dart';
import 'package:adaptive_platform_ui/src/toolbar/hosted_top_toolbar.dart';
import 'dart:ui' show DisplayFeature, DisplayFeatureState, DisplayFeatureType;

import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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

  testWidgets('in the iPhone Duo vertical bar pose the title bands of the '
      'pages in the columns have no background until their content scrolls '
      'under them, as the fixed toolbar\'s', (tester) async {
    PlatformInfo.debugPlatformOverride = TargetPlatform.iOS;
    PlatformInfo.debugIOSVersionOverride = 26;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          SystemChannels.platform_views,
          (call) async => null,
        );
    addTearDown(() {
      PlatformInfo.debugPlatformOverride = null;
      PlatformInfo.debugIOSVersionOverride = null;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform_views, null);
    });
    tester.view.physicalSize = const Size(951, 669);
    tester.view.devicePixelRatio = 1;
    tester.view.padding = const FakeViewPadding(right: 84, bottom: 34);
    tester.view.viewPadding = const FakeViewPadding(right: 84, bottom: 34);
    addTearDown(tester.view.reset);

    Widget list(String name) => AdaptiveScaffold(
      appBar: AdaptiveAppBar(useNativeToolbar: true, title: name),
      body: ListView(
        key: ValueKey('$name list'),
        children: [
          for (var i = 0; i < 40; i++)
            SizedBox(height: 60, child: Text('$name $i')),
        ],
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: root,
        builder: (context, child) =>
            AdaptiveToolbarHost(debugFold: duoInnerDisplay(), child: child!),
        home: AdaptiveSplitView(
          onGenerateDetailRoute: (settings) => MaterialPageRoute<void>(
            settings: settings,
            builder: (_) => list('Detail'),
          ),
          initialDetail: const RouteSettings(name: '/detail'),
          master: list('Support'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    Finder backdropOf(String name) => find.descendant(
      of: find.ancestor(
        of: find.byKey(ValueKey('$name list')),
        matching: find.byType(AdaptiveScaffold),
      ),
      matching: find.byType(DuoTitleBackdrop),
    );
    // Both titles in their bands, over the page as it is.
    expect(find.text('Support'), findsOneWidget);
    expect(find.text('Detail'), findsOneWidget);
    expect(backdropOf('Support'), findsNothing);
    expect(backdropOf('Detail'), findsNothing);

    await tester.drag(
      find.byKey(const ValueKey('Detail list')),
      const Offset(0, -200),
    );
    await tester.pumpAndSettle();
    expect(backdropOf('Detail'), findsOneWidget);
    expect(backdropOf('Support'), findsNothing);

    await tester.drag(
      find.byKey(const ValueKey('Detail list')),
      const Offset(0, 400),
    );
    await tester.pumpAndSettle();
    expect(backdropOf('Detail'), findsNothing);
  });

  group('on a foldable held partly open', () {
    /// The iPhone Duo inner display, partly open like a book or lying flat,
    /// with its fold at [fold].
    FoldableData duoFold(Rect fold, {required bool partlyOpen}) => FoldableData(
      capabilities: FoldableData.unsupported.capabilities,
      status: partlyOpen ? HingeStatus.partiallyOpen : HingeStatus.fullyOpen,
      angleDegrees: partlyOpen ? 120 : 180,
      regions: [
        ReservedRegion(
          kind: ReservedRegionKind.division,
          bounds: fold,
          isActive: true,
        ),
      ],
      displayFeatures: const [],
      horizontalSizeClass: SizeClass.regular,
      verticalSizeClass: SizeClass.regular,
    );

    Widget splitView(FoldableData? fold) => MaterialApp(
      builder: (context, child) => fold == null
          ? child!
          : AdaptiveToolbarHost(debugFold: fold, child: child!),
      home: AdaptiveSplitView(
        onGenerateDetailRoute: detailRoute,
        initialDetail: const RouteSettings(name: '/detail', arguments: 'A'),
        master: const SizedBox.expand(key: ValueKey('list')),
      ),
    );

    double listRight(WidgetTester tester) =>
        tester.getRect(find.byKey(const ValueKey('list'))).right;

    void useInnerPortrait(WidgetTester tester) {
      tester.view.physicalSize = const Size(764, 951);
      tester.view.devicePixelRatio = 1;
      tester.view.padding = const FakeViewPadding(top: 40, bottom: 34);
      tester.view.viewPadding = const FakeViewPadding(top: 40, bottom: 34);
      addTearDown(tester.view.reset);
    }

    testWidgets('the iPhone Duo moves the divider onto the fold, and back '
        'as it lies flat', (tester) async {
      useInnerPortrait(tester);
      // Down the middle of the inner display, held like a book.
      const fold = Rect.fromLTRB(362, 0, 402, 951);
      await tester.pumpWidget(splitView(duoFold(fold, partlyOpen: false)));
      await tester.pumpAndSettle();
      final flat = listRight(tester);
      expect(flat, 320);

      await tester.pumpWidget(splitView(duoFold(fold, partlyOpen: true)));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      // On its way.
      expect(listRight(tester), allOf(greaterThan(flat), lessThan(381)));
      await tester.pumpAndSettle();
      // The hairline of the divider centred on the fold.
      expect(listRight(tester), 381.5);
      expect(find.text('More A'), findsOneWidget);

      await tester.pumpWidget(splitView(duoFold(fold, partlyOpen: false)));
      await tester.pumpAndSettle();
      expect(listRight(tester), flat);
    });

    testWidgets('a fold across the window, held like a laptop, leaves the '
        'divider where it is', (tester) async {
      useInnerPortrait(tester);
      const fold = Rect.fromLTRB(0, 455, 764, 495);
      await tester.pumpWidget(splitView(duoFold(fold, partlyOpen: true)));
      await tester.pumpAndSettle();

      expect(listRight(tester), 320);
    });

    testWidgets('on Android a half-opened fold down the window takes the '
        'divider, and a flat one does not', (tester) async {
      PlatformInfo.debugPlatformOverride = TargetPlatform.android;
      addTearDown(() => PlatformInfo.debugPlatformOverride = null);
      tester.view.physicalSize = const Size(840, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      DisplayFeature fold(DisplayFeatureState state) => DisplayFeature(
        bounds: const Rect.fromLTRB(420, 0, 420, 900),
        type: DisplayFeatureType.fold,
        state: state,
      );
      tester.view.displayFeatures = [fold(DisplayFeatureState.postureFlat)];
      await tester.pumpWidget(splitView(null));
      await tester.pumpAndSettle();
      final flat = listRight(tester);
      expect(flat, 320);

      tester.view.displayFeatures = [
        fold(DisplayFeatureState.postureHalfOpened),
      ];
      await tester.pumpAndSettle();
      // The divider, a line a pixel wide, centred on the fold.
      expect(listRight(tester), 419.5);
    });
  });
}
