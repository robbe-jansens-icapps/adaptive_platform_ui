import 'dart:ui' show DisplayFeature, DisplayFeatureState, DisplayFeatureType;

import 'package:adaptive_platform_ui/adaptive_platform_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:foldable/foldable.dart';

/// An iPhone Duo as the host sees it, lying flat unless [status] says
/// otherwise.
FoldableData duo(
  List<ReservedRegion> regions, {
  HingeStatus status = HingeStatus.fullyOpen,
  bool foldable = true,
}) => FoldableData(
  capabilities: FoldableCapabilities(
    supportLevel: FoldableSupportLevel.available,
    isFoldable: foldable,
    hingeApiPresent: true,
    regionApiPresent: true,
    angleUnitVerified: true,
    strategy: 'test',
  ),
  status: status,
  angleDegrees: status == HingeStatus.partiallyOpen ? 110 : 180,
  regions: regions,
  displayFeatures: const [],
);

/// The fold of the inner display held sideways, as the system reports it:
/// inactive while the device lies flat.
ReservedRegion division({bool active = false}) => ReservedRegion(
  kind: ReservedRegionKind.division,
  bounds: const Rect.fromLTWH(475, 0, 1, 669),
  isActive: active,
);

const camera = ReservedRegion(
  kind: ReservedRegionKind.occlusion,
  bounds: Rect.fromLTRB(867, 0, 951, 120),
  isActive: true,
);

void main() {
  setUp(() {
    PlatformInfo.debugPlatformOverride = TargetPlatform.iOS;
    PlatformInfo.debugIOSVersionOverride = 26;
  });

  tearDown(() {
    PlatformInfo.debugPlatformOverride = null;
    PlatformInfo.debugIOSVersionOverride = null;
  });

  void window(WidgetTester tester, Size size, FakeViewPadding padding) {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    tester.view.padding = padding;
    tester.view.viewPadding = padding;
    addTearDown(tester.view.reset);
  }

  /// What a page under the toolbar host reads, by the last build.
  late Rect? fold;
  late Rect? crease;

  Widget hosted(FoldableData data) => MaterialApp(
    builder: (context, child) =>
        AdaptiveToolbarHost(debugFold: data, child: child!),
    home: Builder(
      builder: (context) {
        fold = FoldScope.foldOf(context);
        crease = FoldScope.creaseOf(context);
        return const SizedBox.expand();
      },
    ),
  );

  testWidgets('the iPhone Duo lying flat has no fold to lay out around, '
      'but a crease down the middle of the inner display', (tester) async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform_views, (_) async {
          return null;
        });
    window(
      tester,
      const Size(951, 669),
      const FakeViewPadding(right: 84, bottom: 34),
    );
    await tester.pumpWidget(hosted(duo([camera, division()])));

    expect(fold, isNull);
    expect(crease, const Rect.fromLTWH(475, 0, 1, 669));

    // Partly open, the fold is both.
    await tester.pumpWidget(
      hosted(
        duo([
          camera,
          division(active: true),
        ], status: HingeStatus.partiallyOpen),
      ),
    );
    expect(fold, const Rect.fromLTWH(475, 0, 1, 669));
    expect(crease, fold);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform_views, null);
  });

  testWidgets('a device without a hinge, a division from the previous pose '
      'and one along the edge of a Split View pane are no crease', (
    tester,
  ) async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform_views, (_) async {
          return null;
        });
    window(
      tester,
      const Size(951, 669),
      const FakeViewPadding(right: 84, bottom: 34),
    );
    await tester.pumpWidget(hosted(duo([division()], foldable: false)));
    expect(crease, isNull);

    // Held upright a moment ago: its fold ran across, 669 points long.
    await tester.pumpWidget(
      hosted(
        duo(const [
          ReservedRegion(
            kind: ReservedRegionKind.division,
            bounds: Rect.fromLTWH(0, 475, 669, 1),
            isActive: false,
          ),
        ]),
      ),
    );
    expect(crease, isNull);

    // The leading pane of Split View ends at the fold.
    window(tester, const Size(475, 669), const FakeViewPadding(bottom: 34));
    await tester.pumpWidget(
      hosted(
        duo(const [
          ReservedRegion(
            kind: ReservedRegionKind.division,
            bounds: Rect.fromLTWH(475, 0, 1, 669),
            isActive: false,
          ),
        ]),
      ),
    );
    expect(crease, isNull);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform_views, null);
  });

  testWidgets('on Android it is a fold in any state, or a hinge', (
    tester,
  ) async {
    PlatformInfo.debugPlatformOverride = TargetPlatform.android;
    Future<Rect?> creaseWith(List<DisplayFeature> features) async {
      Rect? found;
      await tester.pumpWidget(
        MediaQuery(
          data: MediaQueryData(
            size: const Size(840, 900),
            displayFeatures: features,
          ),
          child: Builder(
            builder: (context) {
              found = FoldScope.creaseOf(context);
              return const SizedBox();
            },
          ),
        ),
      );
      return found;
    }

    const flat = DisplayFeature(
      bounds: Rect.fromLTWH(420, 0, 0, 900),
      type: DisplayFeatureType.fold,
      state: DisplayFeatureState.postureFlat,
    );
    expect(await creaseWith([flat]), flat.bounds);
    const hinge = DisplayFeature(
      bounds: Rect.fromLTWH(410, 0, 20, 900),
      type: DisplayFeatureType.hinge,
      state: DisplayFeatureState.unknown,
    );
    expect(await creaseWith([hinge]), hinge.bounds);
    const cutout = DisplayFeature(
      bounds: Rect.fromLTWH(400, 0, 40, 30),
      type: DisplayFeatureType.cutout,
      state: DisplayFeatureState.unknown,
    );
    expect(await creaseWith([cutout]), isNull);
  });
}
