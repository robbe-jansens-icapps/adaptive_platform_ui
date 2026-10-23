import 'package:adaptive_platform_ui/adaptive_platform_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'voice_over_fixture.dart';

const _tabBarType = 'adaptive_platform_ui/ios26_tab_bar';

const _destinations = [
  AdaptiveNavigationDestination(icon: 'map', label: 'Map'),
  AdaptiveNavigationDestination(icon: 'person', label: 'Account'),
];

const _barHeight = 62.0;
const _mapFrame = Rect.fromLTWH(21, 0, 180, _barHeight);
const _accountFrame = Rect.fromLTWH(201, 0, 180, _barHeight);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final created = <int>[];

  setUp(() {
    created.clear();
    IOS26NativeTabBar.debugHasUIKitOverride = true;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform_views, (call) async {
          if (call.method == 'create') {
            created.add(
              (call.arguments as Map<Object?, Object?>)['id']! as int,
            );
          }
          return null;
        });
  });

  tearDown(() {
    IOS26NativeTabBar.debugHasUIKitOverride = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform_views, null);
  });

  // Off iOS, a platform view's focus node takes a focus action, which
  // VoiceOver would stop at.
  final ios = TargetPlatformVariant.only(TargetPlatform.iOS);

  void usePhone(WidgetTester tester) {
    tester.view.physicalSize = const Size(402, 874);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  /// A labelled map under the whole screen, as VoiceOver finds a map's view,
  /// with [bar] along the bottom over it.
  Future<void> pumpOverMap(
    WidgetTester tester,
    Widget bar, {
    TextDirection direction = TextDirection.ltr,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Directionality(
          textDirection: direction,
          child: Stack(
            children: [
              Semantics(
                container: true,
                label: 'Map view',
                child: const SizedBox.expand(),
              ),
              Positioned(left: 0, right: 0, bottom: 0, child: bar),
            ],
          ),
        ),
      ),
    );
    await tester.pump();
  }

  Widget tabBar({
    List<int>? taps,
    int selectedIndex = 0,
    bool hidden = false,
    bool showNativeView = true,
  }) => IOS26NativeTabBar(
    destinations: _destinations,
    selectedIndex: selectedIndex,
    onTap: (index) => taps?.add(index),
    height: _barHeight,
    hidden: hidden,
    showNativeView: showNativeView,
  );

  /// The native bar tells Flutter something, as it does when it lays out.
  Future<void> tellFromNative(
    WidgetTester tester,
    String method,
    Object? arguments,
  ) async {
    await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
      '${_tabBarType}_${created.single}',
      const StandardMethodCodec().encodeMethodCall(
        MethodCall(method, arguments),
      ),
      (_) {},
    );
    await tester.pump();
  }

  Map<String, double> encode(Rect frame) => {
    'x': frame.left,
    'y': frame.top,
    'width': frame.width,
    'height': frame.height,
  };

  SemanticsNode tab(String label) => find.semantics
      .byPredicate(
        (node) =>
            node.label == label &&
            node.getSemanticsData().flagsCollection.isButton,
      )
      .evaluate()
      .single;

  Offset barOrigin(WidgetTester tester) =>
      tester.getTopLeft(find.byType(IOS26NativeTabBar));

  testWidgets('each tab has a node where the native bar shows it', (
    tester,
  ) async {
    usePhone(tester);
    final semantics = tester.ensureSemantics();
    final taps = <int>[];
    await pumpOverMap(tester, tabBar(taps: taps));
    await tellFromNative(tester, 'tabFramesChanged', [
      encode(_mapFrame),
      encode(_accountFrame),
    ]);

    expect(
      tab('Map'),
      isSemantics(
        label: 'Map',
        hint: 'Tab 1 of 2',
        isButton: true,
        isSelected: true,
        hasTapAction: true,
      ),
    );
    expect(
      tab('Account'),
      isSemantics(
        label: 'Account',
        hint: 'Tab 2 of 2',
        isButton: true,
        isSelected: false,
        hasTapAction: true,
      ),
    );
    final origin = barOrigin(tester);
    expect(globalRectOf(tester, tab('Map')), _mapFrame.shift(origin));
    expect(globalRectOf(tester, tab('Account')), _accountFrame.shift(origin));

    tester.semantics.tap(find.semantics.byLabel('Account'));
    expect(taps, [1]);
    semantics.dispose();
  }, variant: ios);

  testWidgets('VoiceOver finds a tab over a map rather than the map', (
    tester,
  ) async {
    usePhone(tester);
    final semantics = tester.ensureSemantics();
    await pumpOverMap(tester, tabBar());
    await tellFromNative(tester, 'tabFramesChanged', [
      encode(_mapFrame),
      encode(_accountFrame),
    ]);

    final origin = barOrigin(tester);
    expect(
      voiceOverHit(tester, _accountFrame.shift(origin).center)?.label,
      'Account',
    );
    expect(voiceOverHit(tester, _mapFrame.shift(origin).center)?.label, 'Map');
    expect(
      allSemanticsNodes(
        tester,
      ).where((node) => node.getSemanticsData().platformViewId != null),
      isEmpty,
    );
    semantics.dispose();
  }, variant: ios);

  testWidgets('a bare platform view lets VoiceOver find the map under it', (
    tester,
  ) async {
    usePhone(tester);
    final semantics = tester.ensureSemantics();
    await pumpOverMap(
      tester,
      const SizedBox(
        height: _barHeight,
        child: UiKitView(viewType: _tabBarType),
      ),
    );

    final origin = tester.getTopLeft(find.byType(UiKitView));
    expect(
      voiceOverHit(tester, _accountFrame.shift(origin).center)?.label,
      'Map view',
    );
    semantics.dispose();
  }, variant: ios);

  testWidgets('before the native bar tells where the tabs are, they share '
      'the capsule or the bar', (tester) async {
    usePhone(tester);
    final semantics = tester.ensureSemantics();
    await pumpOverMap(tester, tabBar());
    final origin = barOrigin(tester);

    expect(
      globalRectOf(tester, tab('Map')),
      const Rect.fromLTWH(0, 0, 201, _barHeight).shift(origin),
    );
    expect(
      globalRectOf(tester, tab('Account')),
      const Rect.fromLTWH(201, 0, 201, _barHeight).shift(origin),
    );

    const capsule = Rect.fromLTWH(21, 4, 360, 54);
    await tellFromNative(tester, 'capsuleChanged', encode(capsule));
    expect(
      globalRectOf(tester, tab('Map')),
      const Rect.fromLTWH(21, 4, 180, 54).shift(origin),
    );

    // A frame for one tab only is not enough.
    await tellFromNative(tester, 'tabFramesChanged', [encode(_mapFrame), null]);
    expect(
      globalRectOf(tester, tab('Account')),
      const Rect.fromLTWH(201, 4, 180, 54).shift(origin),
    );
    semantics.dispose();
  }, variant: ios);

  testWidgets('where the native buttons overlap, a touch is the nearer '
      'tab\'s', (tester) async {
    usePhone(tester);
    final semantics = tester.ensureSemantics();
    await pumpOverMap(tester, tabBar());
    // As iOS 26 lays out its buttons, wider than their share of the capsule.
    await tellFromNative(tester, 'tabFramesChanged', [
      encode(const Rect.fromLTWH(25, 4, 190, 54)),
      encode(const Rect.fromLTWH(187, 4, 190, 54)),
    ]);
    final origin = barOrigin(tester);

    expect(
      globalRectOf(tester, tab('Map')),
      const Rect.fromLTRB(25, 4, 201, 58).shift(origin),
    );
    expect(
      globalRectOf(tester, tab('Account')),
      const Rect.fromLTRB(201, 4, 377, 58).shift(origin),
    );
    expect(voiceOverHit(tester, origin + const Offset(195, 30))?.label, 'Map');
    semantics.dispose();
  }, variant: ios);

  testWidgets('right to left, the first tab is on the right', (tester) async {
    usePhone(tester);
    final semantics = tester.ensureSemantics();
    await pumpOverMap(tester, tabBar(), direction: TextDirection.rtl);
    final origin = barOrigin(tester);

    expect(
      globalRectOf(tester, tab('Map')),
      const Rect.fromLTWH(201, 0, 201, _barHeight).shift(origin),
    );
    semantics.dispose();
  }, variant: ios);

  testWidgets('a hidden or off stage bar has no tabs for VoiceOver', (
    tester,
  ) async {
    usePhone(tester);
    final semantics = tester.ensureSemantics();
    final tabs = find.semantics.byPredicate(
      (node) => node.getSemanticsData().hint.startsWith('Tab '),
    );

    await pumpOverMap(tester, tabBar(hidden: true));
    expect(tabs, findsNothing);
    expect(
      voiceOverHit(
        tester,
        _accountFrame.shift(barOrigin(tester)).center,
      )?.label,
      'Map view',
    );

    await pumpOverMap(tester, tabBar(showNativeView: false));
    expect(tabs, findsNothing);

    await pumpOverMap(tester, tabBar());
    expect(tabs, findsNWidgets(2));
    semantics.dispose();
  }, variant: ios);
}
