import 'package:adaptive_platform_ui/adaptive_platform_ui.dart';
import 'package:adaptive_platform_ui/src/toolbar/duo_vertical_bar.dart';
import 'package:adaptive_platform_ui/src/widgets/ios26/ios26_system_tab_bar.dart';
import 'package:adaptive_platform_ui/src/widgets/ios26/native_chrome/native_chrome_coordinator.dart';
import 'package:adaptive_platform_ui/src/widgets/ios26/native_chrome/native_chrome_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'custom_chrome_fixture.dart';

/// The iPhone Duo's cover display, folded.
const Size _cover = Size(466, 678);
const EdgeInsets _coverPadding = EdgeInsets.only(right: 84, bottom: 34);
const String _viewType = 'adaptive_platform_ui/ios26_system_tab_bar';

const List<AdaptiveNavigationDestination> _tabs = [
  AdaptiveNavigationDestination(icon: 'map', label: 'Map'),
  AdaptiveNavigationDestination(icon: 'person', label: 'Account', showsBadgeDot: true),
  AdaptiveNavigationDestination(icon: 'questionmark.circle', label: 'Support'),
  AdaptiveNavigationDestination(icon: 'ellipsis', label: 'More'),
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final created = <Map<Object?, Object?>>[];
  final toIOS = <MethodCall>[];
  final fallbacks = <String>[];

  String channelOf(int id) => '${_viewType}_$id';

  setUp(() {
    created.clear();
    toIOS.clear();
    fallbacks.clear();
    // Pinned: unpinned, the version comes from the machine the tests run on.
    PlatformInfo.debugPlatformOverride = TargetPlatform.iOS;
    PlatformInfo.debugIOSVersionOverride = 27;
    AdaptiveNativeChrome.enabled = true;
    IOS26SystemTabBar.onFallback = fallbacks.add;
    NativeChromeCoordinator.instance.debugReset();
    messenger.setMockMethodCallHandler(NativeChromeCoordinator.channel, (call) async {
      if (call.method == 'create') {
        final args = call.arguments as Map<Object?, Object?>;
        if (args['viewType'] == _viewType) {
          created.add(args);
          messenger.setMockMethodCallHandler(MethodChannel(channelOf(args['id']! as int)), (call) async {
            toIOS.add(call);
            return null;
          });
        }
      }
      return null;
    });
  });

  tearDown(() {
    for (final view in created) {
      messenger.setMockMethodCallHandler(MethodChannel(channelOf(view['id']! as int)), null);
    }
    messenger.setMockMethodCallHandler(NativeChromeCoordinator.channel, null);
    PlatformInfo.debugPlatformOverride = null;
    PlatformInfo.debugIOSVersionOverride = null;
    AdaptiveNativeChrome.enabled = false;
    AdaptiveNativeChrome.systemDuoTabBar = true;
    IOS26SystemTabBar.onFallback = null;
    IOS26SystemTabBar.debugReset();
  });

  /// The vertical bar on the cover display with [tabs]; [keeps] is a tab the
  /// app keeps selected whatever is tapped. With [late] the app builds the bar
  /// once more with the tab before it, and selects the tapped one a frame or
  /// two later, as an app whose tab bar comes from a registry does.
  Future<List<int>> pumpBar(
    WidgetTester tester, {
    List<AdaptiveNavigationDestination> tabs = _tabs,
    int? keeps,
    bool late = false,
    AdaptiveChrome? chrome,
    Key? key,
  }) async {
    tester.view.physicalSize = _cover;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final taps = <int>[];
    var selected = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(size: _cover, padding: _coverPadding, viewPadding: _coverPadding),
          child: Align(
            alignment: Alignment.topRight,
            child: SizedBox(
              width: 96,
              height: _cover.height,
              child: StatefulBuilder(
                key: key,
                builder: (context, setState) => DuoVerticalBar(
                  chrome: chrome,
                  tabBar: AdaptiveBottomNavigationBar(
                    items: tabs,
                    selectedIndex: selected,
                    onTap: (index) {
                      taps.add(index);
                      if (!late) return setState(() => selected = keeps ?? index);
                      setState(() {});
                      Future<void>.delayed(const Duration(milliseconds: 32), () => setState(() => selected = index));
                    },
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    return taps;
  }

  Future<void> fromIOS(int id, String method, Object? arguments) async {
    await messenger.handlePlatformMessage(
      channelOf(id),
      const StandardMethodCodec().encodeMethodCall(MethodCall(method, arguments)),
      (_) {},
    );
  }

  testWidgets('is on by default, with native chrome, on iOS 27 and later', (tester) async {
    expect(AdaptiveNativeChrome.systemDuoTabBar, isTrue);
    await pumpBar(tester);
    expect(find.byType(IOS26SystemTabBar), findsOneWidget);

    // No allowlist: a later iOS gets iOS's tabs too, as long as iOS lays them out in place.
    PlatformInfo.debugIOSVersionOverride = 28;
    await pumpBar(tester, key: const ValueKey<String>('28'));
    expect(find.byType(IOS26SystemTabBar), findsOneWidget);
  });

  testWidgets('keeps the glass capsule where iOS\'s tab bar is not asked for or cannot be', (tester) async {
    // Before iOS 27 there is no vertical bar of iOS's to put the tabs in.
    PlatformInfo.debugIOSVersionOverride = 26;
    await pumpBar(tester);
    expect(find.byType(IOS26GlassCapsule), findsOneWidget);
    expect(find.byType(IOS26SystemTabBar), findsNothing);

    // Without native chrome iOS's views are platform views, which would
    // clip the tab bar controller to the slot.
    PlatformInfo.debugIOSVersionOverride = 27;
    AdaptiveNativeChrome.enabled = false;
    await pumpBar(tester, key: const ValueKey<String>('no chrome'));
    expect(find.byType(IOS26SystemTabBar), findsNothing);

    // Turned off by the app.
    AdaptiveNativeChrome.enabled = true;
    AdaptiveNativeChrome.systemDuoTabBar = false;
    await pumpBar(tester, key: const ValueKey<String>('off'));
    expect(find.byType(IOS26SystemTabBar), findsNothing);
    expect(created, isEmpty);
  });

  testWidgets('keeps the glass capsule for icons iOS cannot draw itself', (tester) async {
    await pumpBar(
      tester,
      tabs: const [
        AdaptiveNavigationDestination(icon: Icons.map, label: 'Map'),
        AdaptiveNavigationDestination(icon: 'person', label: 'Account'),
      ],
    );
    expect(find.byType(IOS26SystemTabBar), findsNothing);
    expect(find.byType(IOS26GlassCapsule), findsOneWidget);

    // An asset is one iOS draws.
    await pumpBar(
      tester,
      tabs: const [
        AdaptiveNavigationDestination(icon: 'assets/map.png', label: 'Map'),
        AdaptiveNavigationDestination(icon: AssetImage('assets/person.png'), label: 'Account'),
      ],
      key: const ValueKey<String>('assets'),
    );
    expect(find.byType(IOS26SystemTabBar), findsOneWidget);
  });

  testWidgets('custom chrome keeps its own tabs in the vertical bar', (tester) async {
    await pumpBar(tester, chrome: TestChrome.chrome);
    expect(find.byKey(TestChrome.tabBarKey), findsOneWidget);
    expect(find.text('tab:Map*'), findsOneWidget);
    expect(find.byType(IOS26SystemTabBar), findsNothing);
    expect(created, isEmpty);
  });

  testWidgets('the tabs are iOS\'s, in the capsule\'s place, with a node per tab', (tester) async {
    final semantics = tester.ensureSemantics();
    await pumpBar(tester);

    expect(find.byType(IOS26GlassCapsule), findsNothing);
    final rect = tester.getRect(find.byType(IOS26SystemTabBar));
    expect(rect.size, Size(IOS26GlassCapsule.width, IOS26GlassCapsule.tabsHeight(_tabs.length)));
    expect(rect.bottom, _cover.height - kDuoBarBottomMargin);

    final params = created.single['params']! as Map<Object?, Object?>;
    final items = (params['items']! as List<Object?>).cast<Map<Object?, Object?>>();
    expect(items.map((item) => item['label']), ['Map', 'Account', 'Support', 'More']);
    expect(items[1]['badge'], kBadgeDot);
    expect(params['selectedIndex'], 0);

    expect(tester.getSemantics(find.bySemanticsLabel('Map')), matchesSemantics(label: 'Map', hint: 'Tab 1 of 4', isButton: true, hasSelectedState: true, isSelected: true, hasTapAction: true));
    expect(tester.getSemantics(find.bySemanticsLabel('Support')), matchesSemantics(label: 'Support', hint: 'Tab 3 of 4', isButton: true, hasSelectedState: true, hasTapAction: true));
    expect(tester.getRect(find.bySemanticsLabel('Support')).top, rect.top + IOS26GlassCapsule.tabsInset + 2 * 50);
    semantics.dispose();
  });

  testWidgets('where iOS lays its tabs out elsewhere, the glass capsule takes their place for the rest of the run', (tester) async {
    await pumpBar(tester);
    final id = created.single['id']! as int;

    await fromIOS(id, 'availability', {'available': true});
    await tester.pump();
    expect(find.byType(IOS26GlassCapsule), findsNothing);

    await fromIOS(id, 'availability', {'available': false, 'reason': 'layout'});
    await tester.pump();
    expect(find.byType(IOS26GlassCapsule), findsOneWidget);
    expect(find.byType(NativeChromeView), findsNothing);
    expect(fallbacks, ['layout']);

    // The next bar starts with the capsule rather than trying again.
    await pumpBar(tester, key: const ValueKey<String>('again'));
    expect(find.byType(IOS26SystemTabBar), findsNothing);
    expect(find.byType(IOS26GlassCapsule), findsOneWidget);
    expect(created, hasLength(1));
    expect(fallbacks, ['layout']);
  });

  testWidgets('a tap iOS reports selects the tab, and a tab the app keeps is set back on the bar', (tester) async {
    final taps = await pumpBar(tester, keeps: 0);
    final id = created.single['id']! as int;

    // iOS shows the tab selected as it is tapped; the app keeps the map, and
    // the bar shows the map again once the app has had the time to answer.
    await fromIOS(id, 'valueChanged', {'index': 2});
    await tester.pump();
    expect(taps, [2]);
    expect(toIOS.where((call) => call.method == 'setSelectedIndex'), isEmpty);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump();
    expect(
      toIOS.where((call) => call.method == 'setSelectedIndex').map((call) => (call.arguments as Map<Object?, Object?>)['index']),
      [0],
    );
  });

  testWidgets('a slow frame after a tap does not take iOS\'s selection back before the app\'s answer reaches the bar', (tester) async {
    final taps = await pumpBar(tester);
    final id = created.single['id']! as int;

    // The frame after the tap comes 400 ms late, as one that builds a page
    // for the first time can: the time to answer is up before the bar is
    // built with the tab the app selected. The lens went back and forth.
    await fromIOS(id, 'valueChanged', {'index': 2});
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump();
    await tester.pump();
    expect(taps, [2]);
    expect(toIOS.where((call) => call.method == 'setSelectedIndex'), isEmpty);
  });

  testWidgets('an app that answers a tap a frame late does not take iOS\'s selection back', (tester) async {
    final taps = await pumpBar(tester, late: true);
    final id = created.single['id']! as int;

    // The bar is built with the map once more before the app selects the
    // account: sending the map back made iOS's lens go back and forth.
    await fromIOS(id, 'valueChanged', {'index': 1});
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 32));
    await tester.pump(const Duration(milliseconds: 300));
    expect(taps, [1]);
    expect(toIOS.where((call) => call.method == 'setSelectedIndex'), isEmpty);
  });

  testWidgets('a tap on the selected tab reaches the app too, and no selection goes back to iOS', (tester) async {
    final taps = await pumpBar(tester);
    final id = created.single['id']! as int;

    await fromIOS(id, 'valueChanged', {'index': 1});
    await tester.pump();
    await fromIOS(id, 'valueChanged', {'index': 1});
    await tester.pump();
    expect(taps, [1, 1]);
    expect(toIOS.where((call) => call.method == 'setSelectedIndex'), isEmpty);
  });
}
