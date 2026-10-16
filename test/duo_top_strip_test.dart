import 'package:adaptive_platform_ui/adaptive_platform_ui.dart';
import 'package:adaptive_platform_ui/src/toolbar/hosted_top_toolbar.dart';
import 'package:adaptive_platform_ui/src/widgets/ios26/ios26_native_toolbar.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:foldable/foldable.dart';

/// The iPhone Duo inner display held upright: the hardware strip along the
/// top, the camera and status cluster at its right end.
const innerPortrait = Size(764, 951);
const stripPadding = FakeViewPadding(top: 84, bottom: 20);
const cluster = Rect.fromLTRB(644, 0, 764, 84);

FoldableData duo({List<ReservedRegion>? regions}) => FoldableData(
  capabilities: const FoldableCapabilities(
    supportLevel: FoldableSupportLevel.available,
    isFoldable: true,
    hingeApiPresent: true,
    regionApiPresent: true,
    angleUnitVerified: true,
    strategy: 'test',
  ),
  status: HingeStatus.fullyOpen,
  angleDegrees: 180,
  regions:
      regions ??
      const [
        ReservedRegion(
          kind: ReservedRegionKind.occlusion,
          bounds: cluster,
          isActive: true,
        ),
      ],
  displayFeatures: const [],
);

void useInnerPortrait(WidgetTester tester) {
  tester.view.physicalSize = innerPortrait;
  tester.view.devicePixelRatio = 1;
  tester.view.padding = stripPadding;
  tester.view.viewPadding = stripPadding;
  addTearDown(tester.view.reset);
}

void main() {
  group('DuoTopStrip.resolve', () {
    const viewPadding = EdgeInsets.only(top: 84, bottom: 20);

    test('puts the bar in the strip, clear of the cluster at its end', () {
      final strip = DuoTopStrip.resolve(
        viewPadding: viewPadding,
        size: innerPortrait,
        fold: duo(),
      )!;
      expect(strip.height, 84);
      expect(strip.clusterRight, 120);
      expect(strip.clusterLeft, 0);
      // Centred 48 points down, as the system sets it, inside the strip.
      expect(DuoTopStrip.barTop + kDuoTopStripBarHeight / 2, 48);
      expect(strip.overhang, 0);
    });

    test('keeps the bar below the status bar on a device without a hinge', () {
      expect(
        DuoTopStrip.resolve(
          viewPadding: viewPadding,
          size: innerPortrait,
          fold: duo().copyWith(capabilities: FoldableCapabilities.unsupported),
        ),
        isNull,
      );
      expect(
        DuoTopStrip.resolve(
          viewPadding: viewPadding,
          size: innerPortrait,
          fold: null,
        ),
        isNull,
      );
    });

    test('has no strip where the strip is at a side', () {
      expect(
        DuoTopStrip.resolve(
          viewPadding: const EdgeInsets.only(right: 84, bottom: 34),
          size: const Size(951, 669),
          fold: duo(),
        ),
        isNull,
      );
    });

    test('keeps room for the cluster until the system reports it, and leaves '
        'out a reading from the pose before', () {
      final unknown = DuoTopStrip.resolve(
        viewPadding: viewPadding,
        size: innerPortrait,
        fold: duo(regions: const []),
      )!;
      expect(unknown.clusterRight, kDuoStatusClusterFallbackWidth);

      // Where the cluster was in landscape: outside this window.
      final stale = DuoTopStrip.resolve(
        viewPadding: viewPadding,
        size: innerPortrait,
        fold: duo(
          regions: const [
            ReservedRegion(
              kind: ReservedRegionKind.occlusion,
              bounds: Rect.fromLTRB(867, 0, 951, 120),
              isActive: true,
            ),
          ],
        ),
      )!;
      expect(stale.clusterRight, kDuoStatusClusterFallbackWidth);
    });

    test('a strip shorter than the bar has the page clear what reaches '
        'below it', () {
      const strip = DuoTopStrip(height: 40);
      expect(strip.overhang, DuoTopStrip.barBottom - 40);
    });
  });

  group('in the top strip', () {
    final root = GlobalKey<NavigatorState>();

    // The iOS 26 scaffold, which insets the body for the bar.
    setUp(() {
      PlatformInfo.debugPlatformOverride = TargetPlatform.iOS;
      PlatformInfo.debugIOSVersionOverride = 26;
    });
    tearDown(() {
      PlatformInfo.debugPlatformOverride = null;
      PlatformInfo.debugIOSVersionOverride = null;
    });

    Widget page(
      String title, {
      IconData? action,
      ValueSetter<EdgeInsets>? body,
    }) => AdaptiveScaffold(
      appBar: AdaptiveAppBar(
        title: title,
        useNativeToolbar: true,
        actions: [
          if (action != null)
            AdaptiveAppBarAction(icon: action, onPressed: () {}),
        ],
      ),
      body: Builder(
        builder: (context) {
          body?.call(MediaQuery.paddingOf(context));
          return Center(child: Text('body:$title'));
        },
      ),
    );

    Widget hosted(Widget home) => MaterialApp(
      navigatorKey: root,
      builder: (context, child) =>
          AdaptiveToolbarHost(debugFold: duo(), child: child!),
      home: home,
    );

    Finder inBar(Finder finder) =>
        find.descendant(of: find.byType(HostedTopToolbar), matching: finder);

    testWidgets('the fixed toolbar sits in the strip, level with the status '
        'cluster, and the page starts below the strip', (tester) async {
      useInnerPortrait(tester);
      EdgeInsets? padding;
      await tester.pumpWidget(hosted(page('Home')));
      await tester.pump();
      root.currentState!.push(
        MaterialPageRoute<void>(
          builder: (_) => page(
            'About',
            action: Icons.share,
            body: (value) => padding = value,
          ),
        ),
      );
      await tester.pumpAndSettle();

      final back = tester.getRect(inBar(find.byType(AdaptiveButton)));
      expect(back.center.dy, 48);
      expect(back.left, 16);
      expect(tester.getCenter(inBar(find.text('About'))).dy, 48);
      // The action keeps clear of the cluster.
      expect(
        tester.getRect(inBar(find.byIcon(Icons.share))).right,
        lessThanOrEqualTo(cluster.left),
      );
      // Nothing to clear below the strip: the bar is in it.
      expect(padding!.top, 84);
    });

    testWidgets('a page on an ordinary iPhone keeps the bar below the status '
        'bar', (tester) async {
      tester.view.physicalSize = const Size(402, 874);
      tester.view.devicePixelRatio = 1;
      tester.view.padding = const FakeViewPadding(top: 62, bottom: 34);
      tester.view.viewPadding = const FakeViewPadding(top: 62, bottom: 34);
      addTearDown(tester.view.reset);
      EdgeInsets? padding;
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => AdaptiveToolbarHost(
            debugFold: duo().copyWith(
              capabilities: FoldableCapabilities.unsupported,
            ),
            child: child!,
          ),
          home: page('Home', body: (value) => padding = value),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.getCenter(inBar(find.text('Home'))).dy, 62 + 22);
      expect(padding!.top, 62 + 44 + kHostedToolbarBottomPadding);
    });

    testWidgets('a page\'s own bar keeps clear of the cluster and stays '
        'centred', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      useInnerPortrait(tester);
      await tester.pumpWidget(
        const MaterialApp(
          home: DuoTopStripScope(
            strip: DuoTopStrip(height: 84, clusterRight: 120),
            child: Align(
              alignment: Alignment.topCenter,
              child: IOS26NativeToolbar(
                showNativeView: false,
                leading: SizedBox.square(key: ValueKey('back'), dimension: 44),
                titleWidget: Text('About'),
              ),
            ),
          ),
        ),
      );
      debugDefaultTargetPlatformOverride = null;

      final back = tester.getRect(find.byKey(const ValueKey('back')));
      expect(back.center.dy, 48);
      expect(back.left, 16);
      final title = tester.getRect(find.text('About'));
      expect(title.center.dy, 48);
      expect(title.center.dx, closeTo(innerPortrait.width / 2, 0.5));
    });

    testWidgets('a split view keeps the cluster to the column under it', (
      tester,
    ) async {
      useInnerPortrait(tester);
      DuoTopStrip? list;
      DuoTopStrip? detail;
      await tester.pumpWidget(
        hosted(
          AdaptiveSplitView(
            minWidth: 600,
            initialDetail: const RouteSettings(name: '/detail'),
            onGenerateDetailRoute: (settings) => MaterialPageRoute<void>(
              settings: settings,
              builder: (context) {
                detail = DuoTopStripScope.of(context);
                return const SizedBox.expand();
              },
            ),
            master: Builder(
              builder: (context) {
                list = DuoTopStripScope.of(context);
                return const SizedBox.expand();
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(list, const DuoTopStrip(height: 84));
      expect(detail, const DuoTopStrip(height: 84, clusterRight: 120));
    });
  });
}
