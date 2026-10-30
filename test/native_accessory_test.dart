import 'dart:math' as math;

import 'package:adaptive_platform_ui/adaptive_platform_ui.dart';
import 'package:adaptive_platform_ui/src/widgets/ios26/native_chrome/native_chrome_coordinator.dart';
import 'package:adaptive_platform_ui/src/widgets/ios26/native_chrome/native_chrome_navigator_observer.dart';
import 'package:adaptive_platform_ui/src/toolbar/duo_vertical_bar.dart'
    show DuoVerticalBar;
import 'package:adaptive_platform_ui/src/toolbar/hosted_duo_bar.dart';
import 'package:adaptive_platform_ui/src/toolbar/hosted_tab_bar.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:foldable/foldable.dart';

import 'custom_chrome_fixture.dart' show TabsFixture, TestChrome;

/// The native chrome on (there is no iOS 26 in a widget test), on a device
/// without a hinge.
FoldableData forcedChrome() => FoldableData(
  capabilities: FoldableData.unsupported.capabilities,
  status: FoldableData.unsupported.status,
  angleDegrees: FoldableData.unsupported.angleDegrees,
  regions: const [],
  displayFeatures: const [],
);

/// An iPhone Duo, as the host sees it: a hinge, and reserved regions.
FoldableData duo([List<ReservedRegion> regions = const []]) => FoldableData(
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
  regions: regions,
  displayFeatures: const [],
);

/// The camera and status cluster of the inner display held sideways.
const innerCamera = ReservedRegion(
  kind: ReservedRegionKind.occlusion,
  bounds: Rect.fromLTRB(867, 0, 951, 120),
  isActive: true,
);

/// The status cluster of the cover display.
const coverCluster = ReservedRegion(
  kind: ReservedRegionKind.occlusion,
  bounds: Rect.fromLTRB(382, 0, 466, 170),
  isActive: true,
);

/// The camera and status cluster of the inner display held upright.
const uprightCluster = ReservedRegion(
  kind: ReservedRegionKind.occlusion,
  bounds: Rect.fromLTRB(549, 0, 669, 84),
  isActive: true,
);

const tabBarType = 'adaptive_platform_ui/ios26_tab_bar';
const glassType = 'adaptive_platform_ui/ios26_glass_surface';

void window(WidgetTester tester, Size size, FakeViewPadding padding) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  tester.view.padding = padding;
  tester.view.viewPadding = padding;
}

/// The spec the accessory was last built with.
AdaptiveAccessorySpec? lastSpec;

/// An active rental, as an app shows it over its tabs: a capsule with a
/// lock button along the bottom, only the round button in the iPhone Duo's
/// bar, where there is room for it. A tap raises a count it keeps as long as
/// its State lives.
class RentalAccessory extends StatefulWidget {
  const RentalAccessory({super.key});

  @override
  State<RentalAccessory> createState() => RentalAccessoryState();
}

class RentalAccessoryState extends State<RentalAccessory> {
  int count = 0;

  @override
  Widget build(BuildContext context) {
    final spec = lastSpec = AdaptiveAccessoryScope.of(context);
    return GestureDetector(
      onTap: () => setState(() => count++),
      child: spec.compact
          ? SizedBox.square(
              key: const ValueKey('accessory'),
              dimension: spec.room < 48 ? 0 : 48,
              child: Text('lock $count', style: const TextStyle(fontSize: 8)),
            )
          : SizedBox(
              key: const ValueKey('accessory'),
              height: 48,
              child: Text('rental $count', style: const TextStyle(fontSize: 8)),
            ),
    );
  }
}

/// An accessory as tall as the iPhone Duo's bar lets it be, up to 400.
class FitsInRoom extends StatelessWidget {
  const FitsInRoom({super.key});

  @override
  Widget build(BuildContext context) {
    final room = (lastSpec = AdaptiveAccessoryScope.of(context)).room;
    return SizedBox(
      key: const ValueKey('accessory'),
      height: room < 400 ? room : 400,
    );
  }
}

/// An accessory beside the tabs: a round control where it is compact, a
/// capsule otherwise, as tall as it may be.
class BesideAccessory extends StatelessWidget {
  const BesideAccessory({super.key});

  @override
  Widget build(BuildContext context) {
    final spec = lastSpec = AdaptiveAccessoryScope.of(context);
    return SizedBox(
      key: const ValueKey('accessory'),
      width: spec.compact ? 62 : 280,
      height: 62,
    );
  }
}

/// A tab layout with the native chrome: a navigator per tab, the pages with
/// the native toolbar.
class NativeTabs {
  NativeTabs({
    this.accessory,
    this.actions = const <AdaptiveAppBarAction>[],
    this.layout = AdaptiveTabAccessoryLayout.floating,
    this.sheetNavigatorKey,
    this.expanded,
    this.sheet,
    this.layoutOf,
    this.observers = const <NavigatorObserver>[],
    FoldableData? fold,
  }) : fold = fold ?? forcedChrome();

  /// A sheet over the first tab's page, as a map has.
  final Widget? sheet;

  /// The app navigator's observers.
  final List<NavigatorObserver> observers;

  /// The accessory's layout on each tab, where it is not [layout] on all.
  final AdaptiveTabAccessoryLayout Function(int tab)? layoutOf;

  final GlobalKey<NavigatorState>? sheetNavigatorKey;

  /// What the accessory's tray opens into.
  final Widget? expanded;

  /// The tab picked.
  final selected = ValueNotifier<int>(0);

  final Widget? accessory;
  final AdaptiveTabAccessoryLayout layout;
  final List<AdaptiveAppBarAction> actions;
  final FoldableData fold;

  final root = GlobalKey<NavigatorState>();
  final navigators = [GlobalKey<NavigatorState>(), GlobalKey<NavigatorState>()];
  final _paddings = <String, EdgeInsets>{};
  final _insets = <String, double>{};
  final _bands = <String, double>{};

  EdgeInsets paddingOf(String title) => _paddings[title]!;
  double insetOf(String title) => _insets[title]!;
  double bandOf(String title) => _bands[title]!;

  Widget page(String title) => AdaptiveScaffold(
    appBar: AdaptiveAppBar(
      title: title,
      actions: actions,
      useNativeToolbar: true,
    ),
    body: Builder(
      builder: (context) {
        _paddings[title] = MediaQuery.paddingOf(context);
        _insets[title] = AdaptiveBottomBarInset.of(context);
        _bands[title] = AdaptiveBottomBarInset.accessoryOf(context);
        final body = SizedBox.expand(key: ValueKey('body $title'));
        final sheet = this.sheet;
        if (sheet == null || title != 'Tab 0') return body;
        return Stack(
          children: [
            body,
            Positioned.fill(child: sheet),
          ],
        );
      },
    ),
  );

  Widget app() => MaterialApp(
    navigatorKey: root,
    navigatorObservers: observers,
    builder: (context, child) => AdaptiveToolbarHost(
      debugFold: fold,
      sheetNavigatorKey: sheetNavigatorKey,
      child: child!,
    ),
    home: ValueListenableBuilder<int>(
      valueListenable: selected,
      builder: (context, index, _) => AdaptiveScaffold(
        bottomNavigationBar: AdaptiveBottomNavigationBar(
          items: const [
            AdaptiveNavigationDestination(icon: 'map', label: 'Map'),
            AdaptiveNavigationDestination(icon: 'person', label: 'Account'),
          ],
          selectedIndex: index,
          onTap: (tab) => selected.value = tab,
          accessory: accessory,
          accessoryLayout: layoutOf?.call(index) ?? layout,
          accessoryExpanded: expanded,
        ),
        body: IndexedStack(
          children: [
            for (var i = 0; i < navigators.length; i++)
              Navigator(
                key: navigators[i],
                onGenerateRoute: (settings) => MaterialPageRoute<void>(
                  settings: settings,
                  builder: (_) => page('Tab $i'),
                ),
              ),
          ],
        ),
      ),
    ),
  );
}

final accessory = find.byKey(const ValueKey('accessory'), skipOffstage: false);
final nativeBar = find.byType(IOS26NativeTabBar, skipOffstage: false);

/// The opacity the accessory is drawn at: every fade around it.
double opacityOf(WidgetTester tester, Finder finder) {
  var opacity = 1.0;
  for (final fade in tester.widgetList<FadeTransition>(
    find.ancestor(
      of: finder,
      matching: find.byType(FadeTransition, skipOffstage: false),
    ),
  )) {
    opacity *= fade.opacity.value;
  }
  return opacity;
}

/// The glass of the tray the accessory and the tabs share.
final trayGlass = find.byWidgetPredicate(
  (widget) =>
      widget is IOS26GlassSurface &&
      widget.corners == GlassSurfaceCorners.concentric,
  skipOffstage: false,
);

/// The glass the accessory floats on.
Finder glassOf(Finder finder) => find.descendant(
  of: find.ancestor(
    of: finder,
    matching: find.byType(NativeAccessoryGlass, skipOffstage: false),
  ),
  matching: find.byType(IOS26GlassSurface, skipOffstage: false),
);

/// Whether the native glass under the accessory is on screen, rather than
/// its stand-in.
bool showsNativeGlass(WidgetTester tester) {
  final offstage = find.descendant(
    of: glassOf(accessory),
    matching: find.byType(Offstage, skipOffstage: false),
  );
  return offstage.evaluate().isNotEmpty &&
      !tester.widget<Offstage>(offstage.first).offstage;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  /// The native views made, by id and type.
  final created = <(int, String)>[];

  /// How tall the native tab bar says it is, as on an iPhone held upright:
  /// its capsule 22 above the bottom of the screen. The bar's own 50 where
  /// null.
  double? barHeight;

  setUp(() {
    created.clear();
    lastSpec = null;
    barHeight = null;
    PlatformInfo.debugPlatformOverride = TargetPlatform.iOS;
    PlatformInfo.debugIOSVersionOverride = 26;
  });

  tearDown(() {
    PlatformInfo.debugPlatformOverride = null;
    PlatformInfo.debugIOSVersionOverride = null;
    IOS26NativeTabBar.debugHasUIKitOverride = null;
    IOS26GlassSurface.debugHasUIKitOverride = null;
  });

  /// Platform views answer, as on iOS; set back inside each test.
  void mockPlatformViews() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform_views, (call) async {
          if (call.method == 'create') {
            final args = call.arguments as Map<Object?, Object?>;
            final id = args['id']! as int;
            final type = args['viewType']! as String;
            created.add((id, type));
            if (type == tabBarType) {
              TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
                  .setMockMethodCallHandler(
                    MethodChannel('${tabBarType}_$id'),
                    (call) async => call.method == 'getIntrinsicSize'
                        ? {'height': barHeight}
                        : null,
                  );
            }
          }
          return null;
        });
  }

  void unmockPlatformViews() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform_views, null);
  }

  /// The native bar tells where its capsule is, as iOS 26 does as it lays
  /// the bar out.
  Future<void> reportCapsule(WidgetTester tester, Rect capsule) async {
    final id = [
      for (final (id, type) in created)
        if (type == tabBarType) id,
    ].single;
    await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
      '${tabBarType}_$id',
      const StandardMethodCodec().encodeMethodCall(
        MethodCall('capsuleChanged', {
          'x': capsule.left,
          'y': capsule.top,
          'width': capsule.width,
          'height': capsule.height,
        }),
      ),
      (_) {},
    );
    await tester.pump();
  }

  testWidgets('on a phone it floats on glass above the native tab bar, and '
      'the pages keep clear of both', (tester) async {
    mockPlatformViews();
    window(
      tester,
      const Size(402, 874),
      const FakeViewPadding(top: 62, bottom: 34),
    );
    addTearDown(tester.view.reset);
    final tabs = NativeTabs(accessory: const RentalAccessory());
    await tester.pumpWidget(tabs.app());
    await tester.pumpAndSettle();

    final bar = tester.getRect(nativeBar);
    final rect = tester.getRect(accessory);
    expect(bar.bottom, 874);
    // Until the bar tells where its capsule is: where it is on an iPhone.
    expect(
      rect,
      Rect.fromLTRB(
        kNativeTabCapsuleInset,
        bar.top - kNativeAccessoryGap - 48,
        402 - kNativeTabCapsuleInset,
        bar.top - kNativeAccessoryGap,
      ),
    );
    expect(tester.getRect(glassOf(accessory)), rect);
    expect(
      find.descendant(of: find.byType(HostedTabBar), matching: accessory),
      findsOneWidget,
    );
    expect(lastSpec!.placement, AdaptiveChromePlacement.bottom);
    expect(lastSpec!.compact, isFalse);
    expect(lastSpec!.room, double.infinity);
    // On its capsule, which it fills.
    expect(
      AdaptiveAccessoryScope.surfaceOf(tester.element(accessory)),
      const AdaptiveAccessorySurface(shape: StadiumBorder()),
    );

    const room = 50 + kNativeAccessoryGap + 48;
    expect(tabs.insetOf('Tab 0'), room);
    expect(tabs.paddingOf('Tab 0').bottom, room);

    await tester.tap(find.text('rental 0'));
    await tester.pump();
    expect(find.text('rental 1'), findsOneWidget);
    unmockPlatformViews();
  });

  testWidgets('on a wide window it is as wide as the capsule of the tabs, at '
      'most kFloatingAccessoryMaxWidth and centred over it', (tester) async {
    mockPlatformViews();
    IOS26NativeTabBar.debugHasUIKitOverride = true;
    window(
      tester,
      const Size(1194, 834),
      const FakeViewPadding(top: 24, bottom: 20),
    );
    addTearDown(tester.view.reset);
    final tabs = NativeTabs(accessory: const RentalAccessory());
    await tester.pumpWidget(tabs.app());
    await tester.pumpAndSettle();

    var rect = tester.getRect(accessory);
    expect(rect.width, kFloatingAccessoryMaxWidth);
    expect(rect.center.dx, 1194 / 2);

    // The bar tells of its capsule: the accessory takes its width, above it.
    await reportCapsule(tester, const Rect.fromLTWH(397, 4, 400, 42));
    await tester.pumpAndSettle();
    final bar = tester.getRect(nativeBar);
    rect = tester.getRect(accessory);
    expect(rect.left, 397);
    expect(rect.width, 400);
    expect(rect.bottom, bar.top + 4 - kNativeAccessoryGap);
    expect(tabs.insetOf('Tab 0'), 50 + 48 + kNativeAccessoryGap - 4);

    // One wider than that: centred over it, at most 420.
    await reportCapsule(tester, const Rect.fromLTWH(97, 4, 1000, 42));
    await tester.pumpAndSettle();
    rect = tester.getRect(accessory);
    expect(rect.width, kFloatingAccessoryMaxWidth);
    expect(rect.center.dx, 97 + 500);
    unmockPlatformViews();
  });

  testWidgets(
    'beside the tabs on a phone it is a round control at the end of the '
    'tabs, which make room for it, and the pages keep clear of the tabs '
    'alone',
    (tester) async {
      mockPlatformViews();
      IOS26NativeTabBar.debugHasUIKitOverride = true;
      window(
        tester,
        const Size(402, 874),
        const FakeViewPadding(top: 62, bottom: 34),
      );
      addTearDown(tester.view.reset);
      final tabs = NativeTabs(
        accessory: const BesideAccessory(),
        layout: AdaptiveTabAccessoryLayout.beside,
      );
      await tester.pumpWidget(tabs.app());
      await tester.pumpAndSettle();

      expect(lastSpec!.layout, AdaptiveTabAccessoryLayout.beside);
      expect(lastSpec!.compact, isTrue);
      expect(lastSpec!.room, kBesideAccessoryMinRoom);
      // The tabs make room: the bar is narrower by the control and the gap.
      expect(tester.getSize(nativeBar).width, 402 - 62 - kNativeAccessoryGap);

      // The bar tells where its capsule is: the control goes right after it,
      // centred on it.
      await reportCapsule(tester, const Rect.fromLTWH(21, 4, 290, 62));
      await tester.pumpAndSettle();
      final bar = tester.getRect(nativeBar);
      final rect = tester.getRect(accessory);
      expect(rect.left, 21 + 290 + kNativeAccessoryGap);
      expect(rect.center.dy, bar.top + 4 + 31);
      expect(rect.right, lessThanOrEqualTo(402 - kNativeTabCapsuleInset));
      // No taller than the tabs.
      expect(tabs.insetOf('Tab 0'), bar.height);
      unmockPlatformViews();
    },
  );

  testWidgets(
    'beside the tabs on a wide window it is a capsule beside the tabs, the '
    'two centred together',
    (tester) async {
      mockPlatformViews();
      IOS26NativeTabBar.debugHasUIKitOverride = true;
      window(
        tester,
        const Size(1194, 834),
        const FakeViewPadding(top: 24, bottom: 20),
      );
      addTearDown(tester.view.reset);
      final tabs = NativeTabs(
        accessory: const BesideAccessory(),
        layout: AdaptiveTabAccessoryLayout.beside,
      );
      await tester.pumpWidget(tabs.app());
      await tester.pumpAndSettle();
      // The capsule of the tabs as the bar lays it out, in the middle of it.
      final barWidth = 1194 - 280 - kNativeAccessoryGap;
      await reportCapsule(
        tester,
        Rect.fromLTWH((barWidth - 400) / 2, 4, 400, 62),
      );
      await tester.pumpAndSettle();

      expect(lastSpec!.compact, isFalse);
      expect(
        lastSpec!.room,
        1194 - 2 * kNativeTabCapsuleInset - 400 - kNativeAccessoryGap,
      );
      final rect = tester.getRect(accessory);
      expect(rect.width, 280);
      // Tabs and capsule together in the middle of the window.
      final left = (barWidth - 400) / 2;
      expect((left + rect.right) / 2, closeTo(1194 / 2, 0.5));
      unmockPlatformViews();
    },
  );

  testWidgets('on a tray it sits above the tabs, which keep their whole '
      'width, on one glass with them that floats as a sheet does; the pages '
      'keep clear of the tray, and touches on it stay on it', (tester) async {
    mockPlatformViews();
    IOS26NativeTabBar.debugHasUIKitOverride = true;
    window(
      tester,
      const Size(402, 874),
      const FakeViewPadding(top: 62, bottom: 34),
    );
    addTearDown(tester.view.reset);
    barHeight = 84;
    final tabs = NativeTabs(
      accessory: const RentalAccessory(),
      layout: AdaptiveTabAccessoryLayout.tray,
    );
    await tester.pumpWidget(tabs.app());
    await tester.pumpAndSettle();
    await reportCapsule(tester, const Rect.fromLTWH(21, 0, 360, 62));
    await tester.pumpAndSettle();

    expect(lastSpec!.layout, AdaptiveTabAccessoryLayout.tray);
    expect(lastSpec!.compact, isFalse);
    expect(lastSpec!.room, 360);
    final bar = tester.getRect(nativeBar);
    expect(bar.width, 402);
    expect(bar.height, 84);
    expect(bar.bottom, 874);
    // Over the capsule, as wide, the gap above it.
    final rect = tester.getRect(accessory);
    expect(rect.left, 21);
    expect(rect.width, 360);
    expect(rect.bottom, bar.top - kNativeAccessoryGap);
    // On the tray's glass, with none of its own.
    expect(glassOf(accessory), findsNothing);
    // The tray around both, as far from them as it keeps the capsule from
    // its bottom, which is the tray's inset from the window's.
    const padding = 22 - kAccessoryTrayInset;
    final tray = tester.getRect(trayGlass);
    expect(tray.bottom, 874 - kAccessoryTrayInset);
    expect(
      tray,
      Rect.fromLTRB(21 - padding, rect.top - padding, 381 + padding, 866),
    );
    expect(
      tester.widget<IOS26GlassSurface>(trayGlass).cornerRadius,
      kAccessoryTrayCornerRadius,
    );
    // The accessory is told how far the tray's glass reaches around it, and
    // its shape.
    final surface = AdaptiveAccessoryScope.surfaceOf(
      tester.element(accessory),
    )!;
    expect(surface.outline(rect.size).getBounds().shift(rect.topLeft), tray);
    expect(
      (surface.shape as RoundedSuperellipseBorder).borderRadius,
      isA<BorderRadius>().having(
        (radius) => radius.topLeft,
        'top left',
        const Radius.circular(kAccessoryTrayCornerRadius),
      ),
    );
    // The pages keep clear of all of it.
    expect(tabs.insetOf('Tab 0'), 874 - tray.top);
    // A touch on the tray beside the accessory does not reach the page.
    final body = tester.renderObject(
      find.byKey(const ValueKey('body Tab 0'), skipOffstage: false),
    );
    final hits = tester.hitTestOnBinding(Offset(tray.left + 3, rect.center.dy));
    expect(hits.path.map((entry) => entry.target), isNot(contains(body)));
    unmockPlatformViews();
  });

  testWidgets('on a tray on a wide window it is as wide as one floating, '
      'centred on the tabs, the tray around both', (tester) async {
    mockPlatformViews();
    IOS26NativeTabBar.debugHasUIKitOverride = true;
    window(
      tester,
      const Size(1194, 834),
      const FakeViewPadding(top: 24, bottom: 20),
    );
    addTearDown(tester.view.reset);
    barHeight = 80;
    final tabs = NativeTabs(
      accessory: const RentalAccessory(),
      layout: AdaptiveTabAccessoryLayout.tray,
    );
    await tester.pumpWidget(tabs.app());
    await tester.pumpAndSettle();
    await reportCapsule(tester, const Rect.fromLTWH(447, 0, 300, 62));
    await tester.pumpAndSettle();

    expect(lastSpec!.room, kFloatingAccessoryMaxWidth);
    final rect = tester.getRect(accessory);
    expect(rect.width, kFloatingAccessoryMaxWidth);
    expect(rect.center.dx, 597);
    const padding = 80 - 62 - kAccessoryTrayInset;
    expect(
      tester.getRect(trayGlass),
      Rect.fromLTRB(
        rect.left - padding,
        rect.top - padding,
        rect.right + padding,
        834 - kAccessoryTrayInset,
      ),
    );
    unmockPlatformViews();
  });

  testWidgets('on a tray one with nothing to show takes no tray and no room', (
    tester,
  ) async {
    mockPlatformViews();
    window(
      tester,
      const Size(402, 874),
      const FakeViewPadding(top: 62, bottom: 34),
    );
    addTearDown(tester.view.reset);
    final tabs = NativeTabs(
      accessory: const SizedBox.shrink(key: ValueKey('accessory')),
      layout: AdaptiveTabAccessoryLayout.tray,
    );
    await tester.pumpWidget(tabs.app());
    await tester.pumpAndSettle();

    expect(tester.getSize(trayGlass), Size.zero);
    expect(tabs.insetOf('Tab 0'), 50);
    expect(tester.getBottomLeft(nativeBar), const Offset(0, 874));
    unmockPlatformViews();
  });

  test('concentric corners follow the display\'s where they are near them, '
      'and keep their least radius elsewhere', () {
    PlatformInfo.debugDisplayCornerRadiusOverride = 55;
    addTearDown(() => PlatformInfo.debugDisplayCornerRadiusOverride = null);
    final corners = concentricCornersAt(
      const Rect.fromLTRB(8, 700, 394, 866),
      window: const Size(402, 874),
      minimum: kAccessoryTrayCornerRadius,
    );
    expect(corners.topLeft, const Radius.circular(28));
    expect(corners.topRight, const Radius.circular(28));
    expect(corners.bottomLeft, const Radius.circular(47));
    expect(corners.bottomRight, const Radius.circular(47));
  });

  testWidgets('it leaves with the tabs when a page without them is pushed, '
      'its native glass off screen while it fades, and comes back with them', (
    tester,
  ) async {
    mockPlatformViews();
    IOS26GlassSurface.debugHasUIKitOverride = true;
    window(
      tester,
      const Size(402, 874),
      const FakeViewPadding(top: 62, bottom: 34),
    );
    addTearDown(tester.view.reset);
    final tabs = NativeTabs(accessory: const RentalAccessory());
    await tester.pumpWidget(tabs.app());
    await tester.pumpAndSettle();
    expect(opacityOf(tester, accessory), 1);
    expect(showsNativeGlass(tester), isTrue);
    final state = tester.state<RentalAccessoryState>(
      find.byType(RentalAccessory),
    );

    final route = tabs.page('Detail');
    final pushed = MaterialPageRoute<void>(builder: (_) => route);
    tabs.root.currentState!.push(pushed);
    await tester.pump();
    var fading = false;
    while (pushed.animation!.status != AnimationStatus.completed) {
      await tester.pump(const Duration(milliseconds: 8));
      final opacity = opacityOf(tester, accessory);
      // With the tabs, never on its own.
      expect(opacity, closeTo(opacityOf(tester, nativeBar), 1e-9));
      if (opacity > 0 && opacity < 1) {
        fading = true;
        expect(showsNativeGlass(tester), isFalse);
      }
      if (pushed.animation!.value >= 0.2) expect(opacity, 0);
    }
    expect(fading, isTrue);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('accessory')), findsNothing);
    expect(tabs.paddingOf('Detail').bottom, 34);

    tabs.root.currentState!.pop();
    await tester.pumpAndSettle();
    expect(opacityOf(tester, accessory), 1);
    expect(showsNativeGlass(tester), isTrue);
    expect(
      tester.state<RentalAccessoryState>(find.byType(RentalAccessory)),
      same(state),
    );
    unmockPlatformViews();
  });

  testWidgets('it fades for the keyboard, its native glass off screen '
      'meanwhile, while the native tab bar stays', (tester) async {
    mockPlatformViews();
    IOS26GlassSurface.debugHasUIKitOverride = true;
    window(
      tester,
      const Size(402, 874),
      const FakeViewPadding(top: 62, bottom: 34),
    );
    addTearDown(tester.view.reset);
    final tabs = NativeTabs(accessory: const RentalAccessory());
    await tester.pumpWidget(tabs.app());
    await tester.pumpAndSettle();
    final inset = tabs.insetOf('Tab 0');

    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(opacityOf(tester, accessory), allOf(greaterThan(0), lessThan(1)));
    expect(showsNativeGlass(tester), isFalse);
    await tester.pumpAndSettle();
    expect(opacityOf(tester, accessory), 0);
    expect(opacityOf(tester, nativeBar), 1);
    expect(tabs.insetOf('Tab 0'), inset);

    tester.view.resetViewInsets();
    await tester.pumpAndSettle();
    expect(opacityOf(tester, accessory), 1);
    expect(showsNativeGlass(tester), isTrue);
    unmockPlatformViews();
  });

  testWidgets('under a dialog it stays with the tabs, under the dialog\'s '
      'barrier', (tester) async {
    mockPlatformViews();
    IOS26NativeTabBar.debugHasUIKitOverride = true;
    window(
      tester,
      const Size(402, 874),
      const FakeViewPadding(top: 62, bottom: 34),
    );
    addTearDown(tester.view.reset);
    final tabs = NativeTabs(accessory: const RentalAccessory());
    await tester.pumpWidget(tabs.app());
    await tester.pumpAndSettle();
    await reportCapsule(tester, const Rect.fromLTWH(21, 0, 360, 50));

    final barriers = find.descendant(
      of: find.byType(HostedTabBar),
      matching: find.byWidgetPredicate(
        (widget) =>
            widget is DecoratedBox &&
            widget.decoration is ShapeDecoration &&
            (widget.decoration as ShapeDecoration).shape is StadiumBorder,
      ),
    );
    showDialog<void>(
      context: tabs.root.currentContext!,
      builder: (_) => const Center(child: Text('Sure?')),
    );
    await tester.pumpAndSettle();
    expect(opacityOf(tester, accessory), 1);
    expect(barriers, findsNWidgets(2));
    // One over the tabs' capsule, one over the accessory's.
    final dimmed = [
      for (final element in barriers.evaluate())
        tester.getRect(find.byElementPredicate((e) => e == element)),
    ];
    expect(dimmed, contains(tester.getRect(glassOf(accessory))));

    tabs.root.currentState!.pop();
    await tester.pumpAndSettle();
    expect(barriers, findsNothing);
    unmockPlatformViews();
  });

  testWidgets('on a tray under a dialog one barrier dims the tray, its '
      'accessory and the tabs together', (tester) async {
    mockPlatformViews();
    IOS26NativeTabBar.debugHasUIKitOverride = true;
    window(
      tester,
      const Size(402, 874),
      const FakeViewPadding(top: 62, bottom: 34),
    );
    addTearDown(tester.view.reset);
    barHeight = 84;
    final tabs = NativeTabs(
      accessory: const RentalAccessory(),
      layout: AdaptiveTabAccessoryLayout.tray,
    );
    await tester.pumpWidget(tabs.app());
    await tester.pumpAndSettle();
    await reportCapsule(tester, const Rect.fromLTWH(21, 0, 360, 62));
    await tester.pumpAndSettle();

    Finder barriers(Type shape) => find.descendant(
      of: find.byType(HostedTabBar),
      matching: find.byWidgetPredicate(
        (widget) =>
            widget is DecoratedBox &&
            widget.decoration is ShapeDecoration &&
            (widget.decoration as ShapeDecoration).shape.runtimeType == shape,
      ),
    );
    showDialog<void>(
      context: tabs.root.currentContext!,
      builder: (_) => const Center(child: Text('Sure?')),
    );
    await tester.pumpAndSettle();
    expect(barriers(StadiumBorder), findsNothing);
    expect(barriers(RoundedSuperellipseBorder), findsOneWidget);
    expect(
      tester.getRect(barriers(RoundedSuperellipseBorder)),
      tester.getRect(trayGlass),
    );
    unmockPlatformViews();
  });

  testWidgets('sheets on the host\'s sheet navigator come up over the bars, '
      'which stay in sight under them; empty, it takes no touches', (
    tester,
  ) async {
    mockPlatformViews();
    IOS26NativeTabBar.debugHasUIKitOverride = true;
    window(
      tester,
      const Size(402, 874),
      const FakeViewPadding(top: 62, bottom: 34),
    );
    addTearDown(tester.view.reset);
    final sheets = GlobalKey<NavigatorState>();
    final tabs = NativeTabs(
      accessory: const RentalAccessory(),
      sheetNavigatorKey: sheets,
    );
    await tester.pumpWidget(tabs.app());
    await tester.pumpAndSettle();
    final bar = tester.getRect(nativeBar);
    final tabsBox = tester.renderObject(nativeBar);
    bool hitsTabs() => tester
        .hitTestOnBinding(bar.center)
        .path
        .any((entry) => entry.target == tabsBox);
    expect(hitsTabs(), isTrue);

    sheets.currentState!.push(
      PageRouteBuilder<void>(
        opaque: false,
        barrierColor: const Color(0x33000000),
        pageBuilder: (_, _, _) => const Align(
          alignment: Alignment.bottomCenter,
          child: SizedBox(
            key: ValueKey('sheet'),
            width: double.infinity,
            height: 300,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    // Over the tabs, which stay in sight.
    expect(hitsTabs(), isFalse);
    expect(opacityOf(tester, accessory), 1);

    sheets.currentState!.pop();
    await tester.pumpAndSettle();
    expect(hitsTabs(), isTrue);
    unmockPlatformViews();
  });

  testWidgets('on a page\'s sheet the accessory and the tabs keep the place '
      'and the room of the tray, with no glass of their own', (tester) async {
    mockPlatformViews();
    IOS26NativeTabBar.debugHasUIKitOverride = true;
    window(
      tester,
      const Size(402, 874),
      const FakeViewPadding(top: 62, bottom: 34),
    );
    addTearDown(tester.view.reset);
    barHeight = 84;
    final tabs = NativeTabs(
      accessory: const RentalAccessory(),
      layout: AdaptiveTabAccessoryLayout.onSheet,
    );
    await tester.pumpWidget(tabs.app());
    await tester.pumpAndSettle();
    await reportCapsule(tester, const Rect.fromLTWH(21, 0, 360, 62));
    await tester.pumpAndSettle();

    expect(lastSpec!.layout, AdaptiveTabAccessoryLayout.onSheet);
    // As on the tray: over the capsule, as wide, the gap above it.
    final bar = tester.getRect(nativeBar);
    final rect = tester.getRect(accessory);
    expect(rect.left, 21);
    expect(rect.width, 360);
    expect(rect.bottom, bar.top - kNativeAccessoryGap);
    // The room of the tray: the tabs, the accessory, the gap, and the tray's
    // padding above it (what it keeps below the capsule, less its inset).
    const padding = 22 - kAccessoryTrayInset;
    expect(tabs.insetOf('Tab 0'), 84 + padding + 48 + kNativeAccessoryGap);
    expect(trayGlass, findsNothing);
    unmockPlatformViews();
  });

  group('a tray that opens into a sheet', () {
    const opened = 200.0;
    final expanded = find.byKey(
      const ValueKey('expanded'),
      skipOffstage: false,
    );

    Future<NativeTabs> pumpTray(WidgetTester tester) async {
      mockPlatformViews();
      IOS26NativeTabBar.debugHasUIKitOverride = true;
      window(
        tester,
        const Size(402, 874),
        const FakeViewPadding(top: 62, bottom: 34),
      );
      addTearDown(tester.view.reset);
      barHeight = 84;
      final tabs = NativeTabs(
        accessory: const RentalAccessory(),
        layout: AdaptiveTabAccessoryLayout.tray,
        // Takes touches where it is in sight.
        expanded: const ColoredBox(
          key: ValueKey('expanded'),
          color: Color(0x00000000),
          child: SizedBox(width: double.infinity, height: opened),
        ),
      );
      await tester.pumpWidget(tabs.app());
      await tester.pumpAndSettle();
      await reportCapsule(tester, const Rect.fromLTWH(21, 0, 360, 62));
      await tester.pumpAndSettle();
      return tabs;
    }

    bool hits(WidgetTester tester, Finder finder) {
      final box = tester.renderObject(finder);
      return tester
          .hitTestOnBinding(tester.getCenter(finder))
          .path
          .any((entry) => entry.target == box);
    }

    testWidgets('it opens under the finger as it is dragged up and springs '
        'open; the pages keep clear of it closed only; a tap on the page '
        'closes it', (tester) async {
      final tabs = await pumpTray(tester);
      final closed = tester.getRect(trayGlass);
      final inset = tabs.insetOf('Tab 0');
      // Closed, what it opens into is out of sight and takes no touches.
      expect(hits(tester, expanded), isFalse);

      final gesture = await tester.startGesture(tester.getCenter(accessory));
      await gesture.moveBy(const Offset(0, -20));
      for (var i = 0; i < 5; i++) {
        await gesture.moveBy(const Offset(0, -20));
        await tester.pump(const Duration(milliseconds: 16));
      }
      // Under the finger: up by as much as it moved, past halfway.
      expect(tester.getRect(trayGlass).top, closeTo(closed.top - 120, 1));
      expect(tester.getRect(trayGlass).bottom, closed.bottom);
      expect(tabs.insetOf('Tab 0'), inset);

      await gesture.up();
      await tester.pumpAndSettle();
      expect(tester.getRect(trayGlass).top, closeTo(closed.top - opened, 1));
      expect(hits(tester, expanded), isTrue);
      // Still kept clear of closed.
      expect(tabs.insetOf('Tab 0'), inset);

      await tester.tapAt(const Offset(200, 200));
      await tester.pumpAndSettle();
      expect(tester.getRect(trayGlass).top, closeTo(closed.top, 0.5));
      expect(hits(tester, expanded), isFalse);
      unmockPlatformViews();
    });

    testWidgets('open, it closes once there is nothing left to open into', (
      tester,
    ) async {
      mockPlatformViews();
      IOS26NativeTabBar.debugHasUIKitOverride = true;
      window(
        tester,
        const Size(402, 874),
        const FakeViewPadding(top: 62, bottom: 34),
      );
      addTearDown(tester.view.reset);
      barHeight = 84;
      final content = ValueNotifier<double>(opened);
      final tabs = NativeTabs(
        accessory: const RentalAccessory(),
        layout: AdaptiveTabAccessoryLayout.tray,
        expanded: ValueListenableBuilder<double>(
          valueListenable: content,
          builder: (context, height, _) =>
              SizedBox(width: double.infinity, height: height),
        ),
      );
      await tester.pumpWidget(tabs.app());
      await tester.pumpAndSettle();
      await reportCapsule(tester, const Rect.fromLTWH(21, 0, 360, 62));
      await tester.pumpAndSettle();
      final expansion = AdaptiveAccessoryScope.expansionOf(
        tester.element(accessory),
      )!;
      expansion.open();
      await tester.pumpAndSettle();
      expect(expansion.isOpen, isTrue);

      content.value = 0;
      await tester.pumpAndSettle();
      expect(expansion.isOpen, isFalse);
      expect(expansion.value.value, closeTo(0, 0.001));
      unmockPlatformViews();
    });

    testWidgets('opened through the accessory\'s scope, it closes as '
        'another tab is picked', (tester) async {
      final tabs = await pumpTray(tester);
      final closed = tester.getRect(trayGlass);
      final expansion = AdaptiveAccessoryScope.expansionOf(
        tester.element(accessory),
      )!;
      expect(expansion.isOpen, isFalse);

      expansion.open();
      await tester.pumpAndSettle();
      expect(expansion.isOpen, isTrue);
      expect(expansion.value.value, closeTo(1, 0.001));
      expect(tester.getRect(trayGlass).top, closeTo(closed.top - opened, 1));

      tabs.selected.value = 1;
      await tester.pumpAndSettle();
      expect(expansion.isOpen, isFalse);
      expect(tester.getRect(trayGlass).top, closeTo(closed.top, 1));
      unmockPlatformViews();
    });
  });

  group('a page\'s sheet that opens from the accessory on it', () {
    final card = find.byKey(const ValueKey('card'), skipOffstage: false);

    /// The glass of the page's sheet: the one with the sheet's corners.
    final sheetGlass = find.byWidgetPredicate(
      (widget) =>
          widget is IOS26GlassSurface &&
          widget.corners == GlassSurfaceCorners.concentric &&
          widget.cornerRadius == 30,
      skipOffstage: false,
    );

    /// The opacity the card is drawn at: every fade around it.
    double shownOf(WidgetTester tester) {
      var opacity = 1.0;
      for (final fade in tester.widgetList<Opacity>(
        find.ancestor(
          of: card,
          matching: find.byType(Opacity, skipOffstage: false),
        ),
      )) {
        opacity *= fade.opacity;
      }
      return opacity * opacityOf(tester, card);
    }

    bool hits(WidgetTester tester, Finder finder, Offset at) {
      final box = tester.renderObject(finder);
      return tester
          .hitTestOnBinding(at)
          .path
          .any((entry) => entry.target == box);
    }

    Future<(NativeTabs, AdaptiveSheetController)> pumpSheet(
      WidgetTester tester, {
      ValueListenable<bool>? opens,
      bool lifts = false,
      AdaptiveTabAccessoryLayout Function(int tab)? layoutOf,
      Widget accessory = const RentalAccessory(),
      List<NavigatorObserver> observers = const <NavigatorObserver>[],
    }) async {
      mockPlatformViews();
      IOS26NativeTabBar.debugHasUIKitOverride = true;
      IOS26GlassSurface.debugHasUIKitOverride = true;
      window(
        tester,
        const Size(402, 874),
        const FakeViewPadding(top: 62, bottom: 34),
      );
      addTearDown(tester.view.reset);
      barHeight = 84;
      final controller = AdaptiveSheetController();
      addTearDown(controller.dispose);
      final tabs = NativeTabs(
        accessory: accessory,
        layout: AdaptiveTabAccessoryLayout.onSheet,
        layoutOf: layoutOf,
        observers: observers,
        sheet: ValueListenableBuilder<bool>(
          valueListenable: opens ?? ValueNotifier<bool>(true),
          builder: (context, opens, _) => AdaptiveSheet(
            controller: controller,
            opensFromAccessory: opens,
            liftsAccessory: lifts,
            detents: opens
                ? const [
                    AdaptiveSheetDetent.collapsed,
                    AdaptiveSheetDetent.fitContent,
                  ]
                : const [AdaptiveSheetDetent.fitContent],
            initialDetent: opens
                ? AdaptiveSheetDetent.collapsed
                : AdaptiveSheetDetent.fitContent,
            showsGrabber: false,
            scrollable: false,
            padding: EdgeInsets.zero,
            child: const ColoredBox(
              key: ValueKey('card'),
              color: Color(0x00000000),
              child: SizedBox(width: double.infinity, height: 300),
            ),
          ),
        ),
      );
      await tester.pumpWidget(tabs.app());
      await tester.pumpAndSettle();
      await reportCapsule(tester, const Rect.fromLTWH(21, 0, 360, 62));
      await tester.pumpAndSettle();
      return (tabs, controller);
    }

    // The tray's padding above the accessory (what the bar keeps below the
    // capsule, less the tray's inset), the accessory and the gap below it.
    const band = 22 - kAccessoryTrayInset + 48 + kNativeAccessoryGap;

    testWidgets('at its collapsed detent only the accessory shows on its '
        'glass, where a tray would be; the page learns how much of the '
        'room is the accessory\'s', (tester) async {
      final (tabs, _) = await pumpSheet(tester);

      expect(tabs.insetOf('Tab 0'), 84 + band);
      expect(tabs.bandOf('Tab 0'), band);
      expect(tester.getRect(sheetGlass).top, closeTo(874 - 84 - band, 0.5));
      expect(opacityOf(tester, accessory), 1);
      expect(shownOf(tester), 0);
      expect(hits(tester, accessory, tester.getCenter(accessory)), isTrue);
      unmockPlatformViews();
    });

    testWidgets('opened, its content runs on into the accessory\'s room and '
        'ends where the tabs begin, as with no accessory; the accessory '
        'makes way and its touches go to the content, while the pages keep '
        'their room', (tester) async {
      final (tabs, controller) = await pumpSheet(tester);
      final at = tester.getCenter(accessory);

      controller.animateTo(AdaptiveSheetDetent.fitContent);
      await tester.pumpAndSettle();

      expect(tester.getRect(card).bottom, closeTo(874 - 84, 0.5));
      expect(tester.getRect(sheetGlass).top, closeTo(874 - 84 - 300, 0.5));
      expect(shownOf(tester), 1);
      expect(opacityOf(tester, accessory), 0);
      expect(hits(tester, card, at), isTrue);
      expect(tabs.insetOf('Tab 0'), 84 + band);
      unmockPlatformViews();
    });

    testWidgets('dragged up on the accessory, the sheet follows the finger, '
        'the accessory fading out as the content fades in; a fling opens it', (
      tester,
    ) async {
      await pumpSheet(tester);
      final collapsed = tester.getRect(sheetGlass).top;

      final gesture = await tester.startGesture(tester.getCenter(accessory));
      await gesture.moveBy(const Offset(0, -20));
      await tester.pump();
      // A quarter of the way in: the accessory half gone.
      await gesture.moveBy(const Offset(0, 6));
      await tester.pump();
      expect(shownOf(tester), closeTo(14 / 56, 0.01));
      expect(opacityOf(tester, accessory), closeTo(0.5, 0.01));
      await gesture.moveBy(const Offset(0, -14));
      await tester.pump();
      expect(tester.getRect(sheetGlass).top, closeTo(collapsed - 28, 0.5));
      // The content halfway in; the accessory out of sight by then, so the
      // two hardly show at once where they lie over each other.
      expect(shownOf(tester), closeTo(28 / 56, 0.01));
      expect(opacityOf(tester, accessory), closeTo(0, 0.01));
      await gesture.up();
      await tester.pumpAndSettle();

      await tester.fling(accessory, const Offset(0, -80), 1500);
      await tester.pumpAndSettle();
      expect(tester.getRect(card).bottom, closeTo(874 - 84, 0.5));
      expect(opacityOf(tester, accessory), 0);
      unmockPlatformViews();
    });

    testWidgets('the accessory\'s scope opens and closes the sheet', (
      tester,
    ) async {
      await pumpSheet(tester);
      final expansion = AdaptiveAccessoryScope.expansionOf(
        tester.element(accessory),
      )!;
      expect(expansion.isOpen, isFalse);
      expect(expansion.value.value, 0);

      expansion.open();
      await tester.pumpAndSettle();
      expect(expansion.isOpen, isTrue);
      expect(expansion.value.value, 1);
      expect(tester.getRect(card).bottom, closeTo(874 - 84, 0.5));

      expansion.close();
      await tester.pumpAndSettle();
      expect(expansion.isOpen, isFalse);
      expect(shownOf(tester), closeTo(0, 0.001));
      expect(opacityOf(tester, accessory), closeTo(1, 0.001));
      unmockPlatformViews();
    });

    testWidgets('one that does not open from it ends above the accessory, '
        'which stays in sight and takes its touches; switched over, the '
        'accessory eases in and out', (tester) async {
      final opens = ValueNotifier<bool>(false);
      addTearDown(opens.dispose);
      await pumpSheet(tester, opens: opens);
      expect(tester.getRect(card).bottom, closeTo(874 - 84 - band, 0.5));
      expect(opacityOf(tester, accessory), 1);
      // Not asked to lift it apart: on the sheet's glass as it is.
      expect(glassOf(accessory), findsNothing);
      await tester.tap(accessory);
      await tester.pump();
      expect(find.text('rental 1'), findsOneWidget);

      // Opening from it at its tallest: the accessory eases out.
      opens.value = true;
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      final between = opacityOf(tester, accessory);
      expect(between, greaterThan(0));
      expect(between, lessThan(1));
      await tester.pumpAndSettle();
      expect(opacityOf(tester, accessory), 0);

      opens.value = false;
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 170));
      expect(opacityOf(tester, accessory), greaterThan(0));
      expect(opacityOf(tester, accessory), lessThan(1));
      await tester.pumpAndSettle();
      expect(opacityOf(tester, accessory), 1);
      unmockPlatformViews();
    });

    testWidgets('one that lifts the accessory sets it apart on native glass '
        'of its own while its content lies above it, and lets it go as the '
        'content comes up into its place instead', (tester) async {
      final opens = ValueNotifier<bool>(false);
      addTearDown(opens.dispose);
      await pumpSheet(tester, opens: opens, lifts: true);
      // A station above it: its own capsule, the native glass once all in.
      expect(glassOf(accessory), findsOneWidget);
      expect(opacityOf(tester, glassOf(accessory)), closeTo(1, 0.001));
      expect(showsNativeGlass(tester), isTrue);
      expect(tester.getRect(glassOf(accessory)), tester.getRect(accessory));

      // The ride the accessory opens into, at its tallest: no capsule.
      opens.value = true;
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(showsNativeGlass(tester), isFalse);
      await tester.pumpAndSettle();
      expect(opacityOf(tester, glassOf(accessory)), closeTo(0, 0.001));
      unmockPlatformViews();
    });

    testWidgets('shrinking onto the accessory from other content, as a '
        'station gives way to a folded ride, the sheet keeps the accessory in '
        'sight all the way', (tester) async {
      final opens = ValueNotifier<bool>(false);
      addTearDown(opens.dispose);
      final (_, controller) = await pumpSheet(tester, opens: opens);
      expect(opacityOf(tester, accessory), 1);

      opens.value = true;
      await tester.pump();
      controller.animateTo(AdaptiveSheetDetent.collapsed);
      var least = 1.0;
      for (var i = 0; i < 30; i++) {
        await tester.pump(const Duration(milliseconds: 16));
        least = math.min(least, opacityOf(tester, accessory));
      }
      await tester.pumpAndSettle();
      expect(least, greaterThan(0.99));
      expect(tester.getRect(sheetGlass).top, closeTo(874 - 84 - band, 0.5));
      unmockPlatformViews();
    });

    testWidgets('rising from the accessory to other content, as a station '
        'comes up above a folded ride, the sheet keeps the accessory in sight '
        'all the way', (tester) async {
      final opens = ValueNotifier<bool>(true);
      addTearDown(opens.dispose);
      final (_, controller) = await pumpSheet(
        tester,
        opens: opens,
        lifts: true,
      );
      expect(opacityOf(tester, accessory), 1);

      opens.value = false;
      await tester.pump();
      controller.animateTo(AdaptiveSheetDetent.fitContent);
      var least = 1.0;
      for (var i = 0; i < 30; i++) {
        await tester.pump(const Duration(milliseconds: 16));
        least = math.min(least, opacityOf(tester, accessory));
      }
      await tester.pumpAndSettle();
      expect(least, greaterThan(0.99));
      expect(tester.getRect(card).bottom, closeTo(874 - 84 - band, 0.5));
      unmockPlatformViews();
    });

    /// How far down the content of [finder] is painted at most, in the
    /// window: the clips around it.
    double paintedDownTo(WidgetTester tester, Finder finder) {
      RenderObject child = tester.renderObject(finder);
      var bottom = double.infinity;
      for (var parent = child.parent; parent != null; parent = parent.parent) {
        final clip = parent.describeApproximatePaintClip(child);
        if (clip != null) {
          bottom = math.min(
            bottom,
            MatrixUtils.transformRect(parent.getTransformTo(null), clip).bottom,
          );
        }
        child = parent;
      }
      return bottom;
    }

    testWidgets('the accessory is told it sits on the sheet\'s glass where a '
        'tray would be, with the sheet\'s corners, and on its own capsule '
        'where the sheet lifts it', (tester) async {
      final opens = ValueNotifier<bool>(true);
      addTearDown(opens.dispose);
      final (_, controller) = await pumpSheet(
        tester,
        opens: opens,
        lifts: true,
      );
      final rect = tester.getRect(accessory);
      final folded = AdaptiveAccessoryScope.surfaceOf(
        tester.element(accessory),
      )!;
      const padding = 22 - kAccessoryTrayInset;
      expect(
        folded.outline(rect.size).getBounds().shift(rect.topLeft),
        Rect.fromLTRB(
          rect.left - padding,
          rect.top - padding,
          rect.right + padding,
          874 - kAccessoryTrayInset,
        ),
      );
      expect(
        (folded.shape as RoundedSuperellipseBorder).borderRadius,
        isA<BorderRadius>().having(
          (radius) => radius.topLeft,
          'top left',
          const Radius.circular(kAdaptiveSheetCornerRadius),
        ),
      );

      // A station above it: on its capsule.
      opens.value = false;
      await tester.pump();
      controller.animateTo(AdaptiveSheetDetent.fitContent);
      await tester.pumpAndSettle();
      expect(
        AdaptiveAccessoryScope.surfaceOf(tester.element(accessory)),
        const AdaptiveAccessorySurface(shape: StadiumBorder()),
      );
      unmockPlatformViews();
    });

    testWidgets('content that does not open from the accessory ends where the '
        'accessory\'s band begins, wherever the sheet is: coming up from '
        'behind it, it never shows around it', (tester) async {
      final opens = ValueNotifier<bool>(true);
      addTearDown(opens.dispose);
      final (_, controller) = await pumpSheet(
        tester,
        opens: opens,
        lifts: true,
      );
      const edge = 874 - 84 - band;

      // From the first frame on its way up, the content runs on below the
      // band, cut off there.
      opens.value = false;
      controller.animateTo(AdaptiveSheetDetent.fitContent);
      await tester.pump();
      expect(tester.getRect(card).bottom, greaterThan(edge + 20));
      expect(paintedDownTo(tester, card), closeTo(edge, 0.5));
      await tester.pump(const Duration(milliseconds: 16));
      await tester.pump(const Duration(milliseconds: 16));
      expect(tester.getRect(card).bottom, greaterThan(edge + 20));
      expect(paintedDownTo(tester, card), closeTo(edge, 0.5));
      await tester.pumpAndSettle();
      expect(tester.getRect(card).bottom, closeTo(edge, 0.5));
      expect(paintedDownTo(tester, card), closeTo(edge, 0.5));

      // What opens from the accessory runs on into its room, open.
      opens.value = true;
      await tester.pumpAndSettle();
      controller.animateTo(AdaptiveSheetDetent.fitContent);
      await tester.pumpAndSettle();
      expect(tester.getRect(card).bottom, closeTo(874 - 84, 0.5));
      expect(paintedDownTo(tester, card), greaterThan(874 - 84));
      unmockPlatformViews();
    });

    testWidgets('at its collapsed detent the sheet leaves with the accessory '
        'as a dialog comes up, rather than stay empty; open above it, the '
        'sheet stays under the dialog', (tester) async {
      final (tabs, controller) = await pumpSheet(
        tester,
        observers: [NativeChromeNavigatorObserver()],
      );
      double sheetOpacity() => tester
          .widget<FadeTransition>(
            find
                .descendant(
                  of: find.byType(AdaptiveSheet),
                  matching: find.byType(FadeTransition),
                )
                .first,
          )
          .opacity
          .value;
      expect(sheetOpacity(), 1);

      showDialog<void>(
        context: tabs.root.currentContext!,
        builder: (_) => const Center(child: Text('Sure?')),
      );
      await tester.pumpAndSettle();
      expect(sheetOpacity(), 0);

      Navigator.of(tabs.root.currentContext!).pop();
      await tester.pumpAndSettle();
      expect(sheetOpacity(), 1);

      controller.animateTo(AdaptiveSheetDetent.fitContent);
      await tester.pumpAndSettle();
      showDialog<void>(
        context: tabs.root.currentContext!,
        builder: (_) => const Center(child: Text('Sure?')),
      );
      await tester.pumpAndSettle();
      expect(sheetOpacity(), 1);
      unmockPlatformViews();
    });

    testWidgets('lifted onto a sheet, it leaves with the glass it is lifted '
        'onto as a dialog comes in, which would show under it, and comes '
        'back as the dialog goes', (tester) async {
      final (tabs, _) = await pumpSheet(
        tester,
        opens: ValueNotifier<bool>(false),
        lifts: true,
      );
      expect(showsNativeGlass(tester), isTrue);

      showDialog<void>(
        context: tabs.root.currentContext!,
        builder: (_) => const Center(child: Text('Sure?')),
      );
      await tester.pumpAndSettle();
      expect(showsNativeGlass(tester), isFalse);
      expect(opacityOf(tester, accessory), 0);

      Navigator.of(tabs.root.currentContext!).pop();
      await tester.pumpAndSettle();
      expect(opacityOf(tester, accessory), 1);
      expect(showsNativeGlass(tester), isTrue);
      unmockPlatformViews();
    });

    testWidgets('on another tab, on a tray, the accessory shows in full '
        'while the sheet is open', (tester) async {
      final (tabs, controller) = await pumpSheet(
        tester,
        layoutOf: (tab) => tab == 0
            ? AdaptiveTabAccessoryLayout.onSheet
            : AdaptiveTabAccessoryLayout.tray,
      );
      controller.animateTo(AdaptiveSheetDetent.fitContent);
      await tester.pumpAndSettle();
      expect(opacityOf(tester, accessory), 0);

      tabs.selected.value = 1;
      await tester.pumpAndSettle();
      expect(opacityOf(tester, accessory), 1);
      expect(trayGlass, findsWidgets);
      // The tray keeps the same band, so the sheet stays where it is.
      expect(tabs.bandOf('Tab 1'), band);
      unmockPlatformViews();
    });

    testWidgets('one with nothing to show leaves no band', (tester) async {
      final (tabs, _) = await pumpSheet(
        tester,
        accessory: const SizedBox.shrink(key: ValueKey('accessory')),
      );
      expect(tabs.insetOf('Tab 0'), 84);
      expect(tabs.bandOf('Tab 0'), 0);
      unmockPlatformViews();
    });

    testWidgets('under a dialog the sheet\'s glass is dimmed once, by the '
        'page\'s barrier: no barrier over the tray\'s place, the tabs\' '
        'capsule dimmed on its own and the accessory gone', (tester) async {
      final (tabs, _) = await pumpSheet(tester);
      // The barriers laid over the bars, not the stand-ins of their glass.
      Finder barriers(Type shape) => find.descendant(
        of: find.byWidgetPredicate(
          (widget) => widget.runtimeType.toString() == '_BarrierOverTabs',
        ),
        matching: find.byWidgetPredicate(
          (widget) =>
              widget is DecoratedBox &&
              widget.decoration is ShapeDecoration &&
              (widget.decoration as ShapeDecoration).shape.runtimeType == shape,
        ),
      );
      expect(opacityOf(tester, accessory), 1);

      showDialog<void>(
        context: tabs.root.currentContext!,
        builder: (_) => const Center(child: Text('Sure?')),
      );
      await tester.pumpAndSettle();
      expect(barriers(RoundedSuperellipseBorder), findsNothing);
      expect(barriers(StadiumBorder), findsOneWidget);
      expect(opacityOf(tester, accessory), 0);
      unmockPlatformViews();
    });
  });

  testWidgets('one with nothing to show draws no glass and takes no room', (
    tester,
  ) async {
    mockPlatformViews();
    window(
      tester,
      const Size(402, 874),
      const FakeViewPadding(top: 62, bottom: 34),
    );
    addTearDown(tester.view.reset);
    final tabs = NativeTabs(
      accessory: const SizedBox.shrink(key: ValueKey('accessory')),
    );
    await tester.pumpWidget(tabs.app());
    await tester.pumpAndSettle();

    expect(accessory, findsOneWidget);
    expect(glassOf(accessory), findsNothing);
    expect(tabs.insetOf('Tab 0'), 50);
    expect(tabs.paddingOf('Tab 0').bottom, 50);
    expect(tester.getBottomLeft(nativeBar), const Offset(0, 874));
    unmockPlatformViews();
  });

  testWidgets('with native chrome, its glass is drawn by Flutter, as no '
      'platform view, and hands the touches on it to Flutter', (tester) async {
    mockPlatformViews();
    AdaptiveNativeChrome.enabled = true;
    NativeChromeCoordinator.instance.debugReset();
    final touchRegions = <Float64List>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(NativeChromeCoordinator.channel, (
          call,
        ) async {
          if (call.method == 'touchRegions') {
            touchRegions.add(call.arguments as Float64List);
          }
          return null;
        });
    addTearDown(() {
      AdaptiveNativeChrome.enabled = false;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(NativeChromeCoordinator.channel, null);
    });
    window(
      tester,
      const Size(402, 874),
      const FakeViewPadding(top: 62, bottom: 34),
    );
    addTearDown(tester.view.reset);
    final tabs = NativeTabs(accessory: const RentalAccessory());
    await tester.pumpWidget(tabs.app());
    await tester.pumpAndSettle();

    final glass = tester.widget<IOS26GlassSurface>(glassOf(accessory));
    expect(glass.drawnByFlutter, isTrue);
    expect(
      created.where((view) => view.$2.endsWith('ios26_glass_surface')),
      isEmpty,
    );
    final rect = tester.getRect(glassOf(accessory));
    expect(touchRegions.last, [rect.left, rect.top, rect.right, rect.bottom]);
    unmockPlatformViews();
  }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));

  group('on the iPhone Duo', () {
    Finder tabCapsule() => find.byWidgetPredicate(
      (widget) =>
          widget is IOS26GlassCapsule &&
          widget.inset == IOS26GlassCapsule.tabsInset,
    );
    final overflow = find.byWidgetPredicate(
      (widget) =>
          widget is IOS26GlassCapsule &&
          widget.items.any((item) => item.symbol == 'ellipsis'),
    );
    final actions = [
      for (var i = 0; i < 4; i++)
        AdaptiveAppBarAction(iosSymbol: 'star', label: '$i', onPressed: () {}),
    ];

    testWidgets('held sideways it is a round control in the vertical bar, '
        'above the tabs, and the pages keep no room for it', (tester) async {
      mockPlatformViews();
      window(
        tester,
        const Size(951, 669),
        const FakeViewPadding(right: 84, bottom: 34),
      );
      addTearDown(tester.view.reset);
      final tabs = NativeTabs(
        accessory: const RentalAccessory(),
        actions: actions,
        fold: duo([innerCamera]),
      );
      await tester.pumpWidget(tabs.app());
      await tester.pumpAndSettle();

      expect(
        find.descendant(of: find.byType(HostedDuoBar), matching: accessory),
        findsOneWidget,
      );
      expect(find.byType(HostedTabBar), findsNothing);
      final rect = tester.getRect(accessory);
      const band = 84 + kDuoVerticalBarBezelInset;
      expect(rect.size, const Size.square(48));
      expect(rect.center.dx, closeTo(951 - band / 2, 0.5));
      expect(
        rect.bottom,
        tester.getRect(tabCapsule()).top - kDuoBarGroupSpacing,
      );
      expect(tester.getRect(glassOf(accessory)), rect);
      expect(lastSpec!.placement, AdaptiveChromePlacement.vertical);
      expect(lastSpec!.compact, isTrue);
      expect(lastSpec!.room, greaterThan(48));
      // The page's controls are all in sight.
      expect(overflow, findsNothing);
      expect(tabs.paddingOf('Tab 0').bottom, 34);
      expect(tabs.insetOf('Tab 0'), 0);
      unmockPlatformViews();
    });

    testWidgets('on the cover display it gets what the page\'s controls '
        'leave of the bar, so one that fits in that keeps them all in sight', (
      tester,
    ) async {
      mockPlatformViews();
      window(
        tester,
        const Size(466, 678),
        const FakeViewPadding(right: 84, bottom: 34),
      );
      addTearDown(tester.view.reset);
      Future<double> roomWith(List<AdaptiveAppBarAction> actions) async {
        final tabs = NativeTabs(
          accessory: const FitsInRoom(),
          actions: actions,
          fold: duo([coverCluster]),
        );
        await tester.pumpWidget(tabs.app());
        await tester.pumpAndSettle();
        return lastSpec!.room;
      }

      final alone = await roomWith(const []);
      final shared = await roomWith(actions);

      expect(lastSpec!.compact, isTrue);
      expect(
        alone - shared,
        DuoVerticalBar.controlsExtent(leading: false, actions: actions) +
            kDuoBarGroupSpacing,
      );
      expect(tester.getSize(accessory).height, shared);
      expect(overflow, findsNothing);
      unmockPlatformViews();
    });

    testWidgets('it keeps its state as the inner display turns from upright, '
        'with the tabs along the bottom, to sideways, with them in the bar, '
        'and back', (tester) async {
      mockPlatformViews();
      window(
        tester,
        const Size(669, 951),
        const FakeViewPadding(top: 84, bottom: 20),
      );
      addTearDown(tester.view.reset);
      final tabs = NativeTabs(
        accessory: const RentalAccessory(),
        fold: duo([uprightCluster]),
      );
      await tester.pumpWidget(tabs.app());
      await tester.pumpAndSettle();
      expect(lastSpec!.placement, AdaptiveChromePlacement.bottom);
      expect(
        find.descendant(of: find.byType(HostedTabBar), matching: accessory),
        findsOneWidget,
      );
      await tester.tap(find.text('rental 0'));
      await tester.pump();
      await tester.tap(find.text('rental 1'));
      await tester.pump();
      final state = tester.state<RentalAccessoryState>(
        find.byType(RentalAccessory),
      );
      expect(state.count, 2);

      // The size first, then the insets, as a device reports them.
      tester.view.physicalSize = const Size(951, 669);
      await tester.pump();
      tester.view.padding = const FakeViewPadding(right: 84, bottom: 34);
      tester.view.viewPadding = const FakeViewPadding(right: 84, bottom: 34);
      await tester.pumpAndSettle();
      expect(lastSpec!.placement, AdaptiveChromePlacement.vertical);
      expect(
        find.descendant(of: find.byType(HostedDuoBar), matching: accessory),
        findsOneWidget,
      );
      expect(
        tester.state<RentalAccessoryState>(find.byType(RentalAccessory)),
        same(state),
      );
      expect(find.text('lock 2'), findsOneWidget);

      // Back: the insets first this time.
      tester.view.padding = const FakeViewPadding(top: 84, bottom: 20);
      tester.view.viewPadding = const FakeViewPadding(top: 84, bottom: 20);
      await tester.pump();
      tester.view.physicalSize = const Size(669, 951);
      await tester.pumpAndSettle();
      expect(lastSpec!.placement, AdaptiveChromePlacement.bottom);
      expect(
        tester.state<RentalAccessoryState>(find.byType(RentalAccessory)),
        same(state),
      );
      expect(find.text('rental 2'), findsOneWidget);
      expect(tester.takeException(), isNull);
      unmockPlatformViews();
    });

    testWidgets('one with nothing to show keeps no room in the bar, nor one '
        'that has gone', (tester) async {
      mockPlatformViews();
      window(
        tester,
        const Size(951, 669),
        const FakeViewPadding(right: 84, bottom: 34),
      );
      addTearDown(tester.view.reset);
      Future<double> roomKept(Widget? accessory) async {
        final tabs = NativeTabs(accessory: accessory, fold: duo([innerCamera]));
        await tester.pumpWidget(tabs.app());
        await tester.pumpAndSettle();
        expect(tabs.paddingOf('Tab 0').bottom, 34);
        final bar = find.byType(HostedDuoBar);
        return ToolbarRegistry.maybeOf(
          tester.element(bar),
        )!.barAccessoryHeight.value;
      }

      expect(
        await roomKept(const SizedBox.shrink(key: ValueKey('accessory'))),
        0,
      );
      expect(glassOf(accessory), findsNothing);
      expect(await roomKept(const RentalAccessory()), 48);
      expect(await roomKept(null), 0);
      unmockPlatformViews();
    });
  });

  testWidgets('with custom chrome the accessory reads where it is shown too', (
    tester,
  ) async {
    mockPlatformViews();
    window(
      tester,
      const Size(390, 844),
      const FakeViewPadding(top: 47, bottom: 34),
    );
    addTearDown(tester.view.reset);
    final tabs = TabsFixture(
      debugFold: FoldableData.unsupported,
      accessory: const RentalAccessory(),
      chrome: TestChrome.withFrames,
    );
    await tester.pumpWidget(tabs.app());
    await tester.pumpAndSettle();

    expect(lastSpec, TestChrome.lastAccessorySpec);
    expect(lastSpec!.placement, AdaptiveChromePlacement.bottom);
    unmockPlatformViews();
  });
}
