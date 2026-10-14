import 'package:adaptive_platform_ui/adaptive_platform_ui.dart';
import 'package:adaptive_platform_ui/src/platform/system_vertical_bar.dart';
import 'package:flutter/material.dart';
import 'package:foldable/foldable.dart';

/// Custom chrome made of plain text, so tests can find and tap every part.
abstract final class TestChrome {
  static const tabBarKey = ValueKey<String>('test tab bar');
  static const tabBarHeight = 80.0;

  static Object? lastTitleData;
  static Object? lastTabData;
  static AdaptiveTabBarSpec? lastTabSpec;
  static AdaptiveTitleSpec? lastTitleSpec;

  static const AdaptiveChrome chrome = AdaptiveChrome(
    tabBarBuilder: _tabBar,
    titleBuilder: _title,
    backButtonBuilder: _back,
    actionsBuilder: _actions,
  );

  static const sidebarKey = ValueKey<String>('test sidebar');
  static AdaptiveSidebarSpec? lastSidebarSpec;

  static const AdaptiveChrome withSidebar = AdaptiveChrome(
    tabBarBuilder: _tabBar,
    titleBuilder: _title,
    backButtonBuilder: _back,
    actionsBuilder: _actions,
    sidebarBuilder: _sidebar,
  );

  static Widget _sidebar(BuildContext context, AdaptiveSidebarSpec spec) {
    lastSidebarSpec = spec;
    return ColoredBox(
      key: sidebarKey,
      color: const Color(0xFF202020),
      child: Column(
        children: [
          GestureDetector(onTap: spec.onToggle, child: const Text('toggle', style: TextStyle(fontSize: 8))),
          for (var i = 0; i < spec.items.length; i++)
            GestureDetector(
              onTap: () => spec.onTap(i),
              child: Text('side:${spec.items[i].label}${i == spec.selectedIndex ? '*' : ''}', style: const TextStyle(fontSize: 8)),
            ),
          const Spacer(),
          ?spec.accessory,
        ],
      ),
    );
  }

  static AdaptiveAccessorySpec? lastAccessorySpec;

  static const AdaptiveChrome withFrames = AdaptiveChrome(
    tabBarBuilder: _tabBar,
    titleBuilder: _title,
    backButtonBuilder: _back,
    actionsBuilder: _actions,
    sidebarBuilder: _sidebar,
    accessoryBuilder: _frame,
  );

  static Widget _frame(BuildContext context, AdaptiveAccessorySpec spec, Widget accessory) {
    lastAccessorySpec = spec;
    return DecoratedBox(key: const ValueKey<String>('accessory frame'), decoration: const BoxDecoration(color: Color(0xFF444444)), child: accessory);
  }

  static AdaptiveChrome build({bool? centerTitle}) => AdaptiveChrome(
    tabBarBuilder: _tabBar,
    titleBuilder: _title,
    backButtonBuilder: _back,
    actionsBuilder: _actions,
    centerTitle: centerTitle,
  );

  static Widget _tabBar(BuildContext context, AdaptiveTabBarSpec spec) {
    lastTabData = spec.data;
    lastTabSpec = spec;
    final vertical = spec.axis == Axis.vertical;
    return SizedBox(
      key: tabBarKey,
      height: vertical ? null : tabBarHeight,
      width: vertical ? 48 : null,
      child: Flex(
        direction: spec.axis,
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < spec.items.length; i++)
            Flexible(
              child: GestureDetector(
                onTap: () => spec.onTap(i),
                child: Text(
                  'tab:${spec.items[i].label}${i == spec.selectedIndex ? '*' : ''}',
                  style: const TextStyle(fontSize: 8),
                ),
              ),
            ),
        ],
      ),
    );
  }

  static Widget _title(BuildContext context, AdaptiveTitleSpec spec) {
    lastTitleData = spec.data;
    lastTitleSpec = spec;
    return Text('title:${spec.title}', style: const TextStyle(fontSize: 8));
  }

  static Widget _back(BuildContext context, AdaptiveBackButtonSpec spec) => GestureDetector(
    onTap: spec.onPressed,
    child: SizedBox.square(
      dimension: 44,
      child: Center(child: Text(spec.style == AdaptiveBackButtonStyle.close ? 'close' : 'back', style: const TextStyle(fontSize: 8))),
    ),
  );

  static Widget _actions(BuildContext context, AdaptiveActionsSpec spec) => spec.overflow
      ? Builder(
          builder: (anchor) => GestureDetector(
            onTap: () => spec.showOverflow!(anchor),
            child: const SizedBox.square(dimension: 44, child: Center(child: Text('more', style: TextStyle(fontSize: 8)))),
          ),
        )
      : Flex(
    direction: spec.axis,
    mainAxisSize: MainAxisSize.min,
    children: [
      for (final action in spec.actions)
        Builder(
          builder: (anchor) => GestureDetector(
            onTap: () => spec.onPressed(action, anchor),
            child: SizedBox.square(
              dimension: 44,
              child: Center(child: Text('action:${action.title}', style: const TextStyle(fontSize: 8))),
            ),
          ),
        ),
    ],
  );
}

/// An app with custom chrome: a tab layout of [tabCount] tabs, each with a
/// navigator of its own, under a toolbar host.
class TabsFixture {
  TabsFixture({
    this.hidesWhenPushed = false,
    this.actions = const <AdaptiveAppBarAction>[],
    this.chromeData,
    this.tabCount = 2,
    this.chrome = TestChrome.chrome,
    this.debugFold,
    this.debugVerticalBarEdge,
    this.accessory,
  });

  final Widget? accessory;

  final bool hidesWhenPushed;
  final List<AdaptiveAppBarAction> actions;
  final Object? chromeData;
  final int tabCount;
  final AdaptiveChrome chrome;
  final FoldableData? debugFold;
  final SystemVerticalBarEdge? debugVerticalBarEdge;

  final root = GlobalKey<NavigatorState>();
  late final navigators = List.generate(tabCount, (_) => GlobalKey<NavigatorState>());
  final selected = ValueNotifier<int>(0);
  final _paddings = <String, EdgeInsets>{};
  final _insets = <String, double>{};

  EdgeInsets paddingOf(String title) => _paddings[title]!;
  double insetOf(String title) => _insets[title]!;

  Widget pageWidget(String title, {AdaptiveBackButtonStyle style = AdaptiveBackButtonStyle.back}) => AdaptiveScaffold(
    appBar: AdaptiveAppBar(title: title, actions: actions, chromeData: chromeData, backButtonStyle: style),
    body: Builder(
      builder: (context) {
        _paddings[title] = MediaQuery.paddingOf(context);
        _insets[title] = AdaptiveBottomBarInset.of(context);
        return SizedBox.expand(key: ValueKey<String>('body $title'));
      },
    ),
  );

  Route<void> page(String title, {bool fullscreenDialog = false, AdaptiveBackButtonStyle style = AdaptiveBackButtonStyle.back}) =>
      MaterialPageRoute<void>(fullscreenDialog: fullscreenDialog, builder: (_) => pageWidget(title, style: style));

  void push(int tab, String title) => navigators[tab].currentState!.push(page(title));

  Widget app() => MaterialApp(
    navigatorKey: root,
    builder: (context, child) => AdaptiveToolbarHost(
      chrome: chrome,
      debugFold: debugFold,
      debugVerticalBarEdge: debugVerticalBarEdge,
      child: child!,
    ),
    home: ValueListenableBuilder<int>(
      valueListenable: selected,
      builder: (context, index, _) => AdaptiveScaffold(
        bottomNavigationBar: AdaptiveBottomNavigationBar(
          items: [for (var i = 0; i < tabCount; i++) AdaptiveNavigationDestination(icon: Icons.circle, label: 'Tab $i')],
          selectedIndex: index,
          onTap: (i) => selected.value = i,
          hidesWhenPushed: hidesWhenPushed,
          chromeData: 'tabs',
          accessory: accessory,
        ),
        body: IndexedStack(
          index: index,
          children: [
            for (var i = 0; i < tabCount; i++)
              Navigator(
                key: navigators[i],
                onGenerateRoute: (settings) => MaterialPageRoute<void>(settings: settings, builder: (_) => pageWidget('Tab $i')),
              ),
          ],
        ),
      ),
    ),
  );
}

/// An iPhone Duo as the host sees it: a hinge, and reserved regions.
FoldableData duo({List<ReservedRegion> regions = const <ReservedRegion>[]}) => FoldableData(
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

/// A tab accessory with state of its own, like a mini player: a count that
/// a tap raises, kept as long as its State lives.
class CountingAccessory extends StatefulWidget {
  const CountingAccessory({super.key, this.height = 50});

  final double height;

  @override
  State<CountingAccessory> createState() => CountingAccessoryState();
}

class CountingAccessoryState extends State<CountingAccessory> {
  int count = 0;

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: () => setState(() => count++),
    child: SizedBox(
      key: const ValueKey<String>('accessory'),
      height: widget.height,
      child: Text('accessory $count', style: const TextStyle(fontSize: 8)),
    ),
  );
}

extension CopyWithGlass on AdaptiveChrome {
  /// This chrome with another glass, for tests of surfaces that take it.
  AdaptiveChrome copyWithGlass(AdaptiveGlassStyle glass) => AdaptiveChrome(
    tabBarBuilder: tabBarBuilder,
    titleBuilder: titleBuilder,
    backButtonBuilder: backButtonBuilder,
    actionsBuilder: actionsBuilder,
    barBackgroundBuilder: barBackgroundBuilder,
    sidebarBuilder: sidebarBuilder,
    accessoryBuilder: accessoryBuilder,
    popoverBuilder: popoverBuilder,
    centerTitle: centerTitle,
    glass: glass,
    metrics: metrics,
  );
}
