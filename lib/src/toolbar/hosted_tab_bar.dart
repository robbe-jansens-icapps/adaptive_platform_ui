import 'dart:math' as math;

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';

import '../chrome/adaptive_chrome.dart';
import '../platform/platform_info.dart';
import '../utils/size_reporter.dart';
import '../widgets/adaptive_bottom_navigation_bar.dart';
import 'duo_top_strip.dart';
import 'duo_vertical_bar.dart';
import 'hosted_top_toolbar.dart' show kHostedToolbarHeight;
import '../widgets/ios26/ios26_native_tab_bar.dart';
import 'toolbar_blend.dart';
import 'toolbar_registry.dart';

/// The native tab bar of the app's tab layouts, at the bottom of the screen
/// above the navigator, the way the iPhone Duo vertical bar holds the tabs on
/// its side.
///
/// Inside its page the native bar slid with the page under one that was
/// pushed over it, and Flutter had to draw that page over a moving native
/// view on every frame of the transition. Here it never moves and nothing is
/// drawn over it: it fades out while a page without the tabs comes in, and
/// back in as that page leaves, following a back swipe under the finger. It
/// stays put and at full opacity while the pages within the tabs change.
///
/// The native view is made once per tab layout and kept for as long as the
/// layout is mounted: off stage while a page covers the tabs, so it is not
/// made again at the start of every pop.
///
/// With [chrome] it is the app's own tab bar, drawn by Flutter, that sits
/// there and comes and goes the same way.
class HostedTabBar extends StatefulWidget {
  const HostedTabBar({
    super.key,
    required this.blend,
    required this.height,
    this.chrome,
    this.placement = AdaptiveChromePlacement.bottom,
    this.sidebar,
    this.accessoryHeight,
  });

  /// The sidebar's state, while the tabs are in one.
  final HostedSidebar? sidebar;

  /// Set to the room an accessory floating at the bottom of the content
  /// takes, with custom chrome where the tabs are not at the bottom.
  final ValueNotifier<double>? accessoryHeight;

  final ToolbarBlend blend;

  /// The app's own bars, if any.
  final AdaptiveChrome? chrome;

  final AdaptiveChromePlacement placement;

  /// Set to the height the bar covers at the bottom of the screen, for the
  /// tab layout to keep its content clear of it.
  final ValueNotifier<double> height;

  @override
  State<HostedTabBar> createState() => _HostedTabBarState();
}

class _HostedTabBarState extends State<HostedTabBar> {
  /// The tab layouts the last build drew a bar for.
  List<ToolbarEntry> _built = const <ToolbarEntry>[];

  /// Fully out while a dialog or sheet covers the tabs: the bar would show
  /// above them, as it sits above the navigator.
  late Animation<double> _uncovered;

  @override
  void initState() {
    super.initState();
    _listen(widget.blend);
  }

  @override
  void didUpdateWidget(HostedTabBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.blend, widget.blend)) {
      _unlisten(oldWidget.blend);
      _listen(widget.blend);
    }
  }

  @override
  void dispose() {
    _unlisten(widget.blend);
    super.dispose();
  }

  void _listen(ToolbarBlend blend) {
    _uncovered = ReverseAnimation(blend.cover);
    blend.addListener(_rebuild);
    blend.registry.addListener(_onRegistryChanged);
  }

  void _unlisten(ToolbarBlend blend) {
    blend.removeListener(_rebuild);
    blend.registry.removeListener(_onRegistryChanged);
  }

  void _rebuild() => setState(() {});

  /// The blend only tells of the pages in front. A tab layout that is
  /// covered or comes and goes is only seen here.
  void _onRegistryChanged() {
    if (listEquals(_hosted(), _built)) return;
    setState(() {});
  }

  List<ToolbarEntry> _hosted() => [
    for (final entry in widget.blend.registry.entries)
      if (entry.tabBarHosted && (entry.tabBar?.items?.isNotEmpty ?? false))
        entry,
  ];

  @override
  Widget build(BuildContext context) {
    final blend = widget.blend;
    final registry = blend.registry;
    _built = _hosted();
    _accessoryKeys.removeWhere(
      (id, _) => !_built.any((entry) => entry.id == id),
    );
    // No accessory floats at the bottom of the content: none of its room is
    // kept there any more. The bottom placement measures its own.
    final floats =
        widget.chrome != null &&
        (widget.placement == AdaptiveChromePlacement.vertical ||
            widget.placement == AdaptiveChromePlacement.topStrip) &&
        _built.any((entry) => entry.tabBar?.accessory != null);
    final accessoryHeight = widget.accessoryHeight;
    if (!floats && accessoryHeight != null && accessoryHeight.value != 0) {
      SchedulerBinding.instance.addPostFrameCallback(
        (_) => accessoryHeight.value = 0,
      );
    }
    // As the iPhone Duo vertical bar does: the tabs of the page coming in and
    // of the one going out, which are one and the same while the pages
    // within a tab layout change.
    final upperTabs = registry.tabBarOwnerFor(blend.upper);
    final lowerTabs = registry.tabBarOwnerFor(blend.lower);
    final ownerTabs = registry.tabBarOwnerFor(blend.owner);
    return IgnorePointer(
      ignoring: blend.ownerIsCovered,
      child: FadeTransition(
        // A sidebar stays in sight under a dialog or popover, dimmed as the
        // toolbar is; a bar along the bottom would show above it.
        opacity: widget.sidebar != null ? blend.chromeOpacity : _uncovered,
        child: Stack(
          fit: StackFit.expand,
          children: [
            for (final entry in _built)
              _layer(
                entry,
                opacity: entry.id == upperTabs?.id
                    ? lowerTabs?.id == upperTabs!.id
                          ? kAlwaysCompleteAnimation
                          : blend.upperOpacity
                    : entry.id == lowerTabs?.id
                    ? blend.lowerOpacity
                    : null,
                interactive: entry.id == ownerTabs?.id,
              ),
          ],
        ),
      ),
    );
  }

  /// The bar of one tab layout; off stage while no [opacity] shows it. The
  /// widgets around the native bar are the same in every state, so it is
  /// never made again.
  Widget _layer(
    ToolbarEntry entry, {
    required Animation<double>? opacity,
    required bool interactive,
  }) {
    final bar = entry.tabBar!;
    final chrome = widget.chrome;
    if (chrome != null) {
      return _customLayer(
        entry,
        bar,
        chrome,
        opacity: opacity,
        interactive: interactive,
      );
    }
    return Positioned(
      key: ValueKey<(String, Object)>(('adaptive_hosted_tabs', entry.id)),
      left: 0,
      right: 0,
      bottom: 0,
      child: Offstage(
        offstage: opacity == null,
        child: IgnorePointer(
          ignoring: !interactive,
          // See HostedTopToolbar._layer: in the semantics tree at every
          // opacity, left out while it is not the tabs of the page in front.
          child: FadeTransition(
            opacity: opacity ?? kAlwaysDismissedAnimation,
            alwaysIncludeSemantics: true,
            child: ExcludeSemantics(
              excluding: !interactive,
              // Laid out off stage too, so the height holds while a page
              // covers the tabs, and the tabs are not laid out again for it.
              child: SizeReporter(
                onSizeChanged: (size) => widget.height.value = size.height,
                child: _Minimizable(
                  minimized: entry.tabBarMinimized,
                  child: IOS26NativeTabBar(
                    destinations: bar.items!,
                    selectedIndex: bar.selectedIndex!,
                    onTap: bar.onTap!,
                    tint:
                        bar.selectedItemColor ??
                        CupertinoTheme.of(context).primaryColor,
                    unselectedItemTint: bar.unselectedItemColor,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// One tab layout's tabs and accessory with custom chrome, wherever the
  /// placement puts them: both along the bottom; the tabs in the iPhone Duo's
  /// top strip; the tabs in its vertical bar, drawn there by the host, with
  /// the accessory floating at the bottom of the content; or both in a
  /// sidebar.
  Widget _customLayer(
    ToolbarEntry entry,
    AdaptiveBottomNavigationBar bar,
    AdaptiveChrome chrome, {
    required Animation<double>? opacity,
    required bool interactive,
  }) {
    final placement = widget.placement;
    final sidebar = widget.sidebar;
    final inSidebar = sidebar != null && chrome.sidebarBuilder != null;
    final accessory = _accessory(
      entry,
      bar,
      chrome,
      placement: placement,
      compact:
          placement == AdaptiveChromePlacement.vertical ||
          (inSidebar && !sidebar.expanded),
    );
    if (inSidebar) {
      return _sidebarLayer(
        entry,
        bar,
        chrome,
        sidebar,
        accessory: accessory,
        opacity: opacity,
        interactive: interactive,
      );
    }
    final tabs = placement == AdaptiveChromePlacement.vertical
        ? null
        : chrome.tabBarBuilder(
            context,
            AdaptiveTabBarSpec(
              placement: placement,
              items: bar.items!,
              selectedIndex: bar.selectedIndex!,
              onTap: bar.onTap!,
              minimized:
                  entry.tabBarMinimized ??
                  const AlwaysStoppedListenable<bool>(false),
              data: bar.chromeData,
            ),
          );
    final children = <Widget>[];
    if (placement == AdaptiveChromePlacement.topStrip ||
        placement == AdaptiveChromePlacement.vertical) {
      // Custom tabs on the iPhone Duo held upright go in the strip along the
      // top, beside the camera and status cluster, centred where the vertical
      // bar's first control is in the other poses.
      final strip = DuoTopStripScope.of(context);
      if (tabs != null && strip != null) {
        children.add(
          Positioned(
            left: 16 + strip.clusterLeft,
            right: 16 + strip.clusterRight,
            top: DuoTopStrip.barTop,
            height: kDuoTopStripBarHeight,
            child: tabs,
          ),
        );
      }
      if (accessory != null) {
        children.add(
          _floating(accessory, framed: chrome.accessoryBuilder != null),
        );
      }
    } else {
      children.add(
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          // Laid out off stage too, so the height holds while a page
          // covers the tabs.
          child: SizeReporter(
            onSizeChanged: (size) => widget.height.value = size.height,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [?accessory, ?tabs],
            ),
          ),
        ),
      );
    }
    return Positioned.fill(
      key: ValueKey<(String, Object)>(('adaptive_hosted_tabs', entry.id)),
      child: Offstage(
        offstage: opacity == null,
        child: IgnorePointer(
          ignoring: !interactive,
          child: FadeTransition(
            opacity: opacity ?? kAlwaysDismissedAnimation,
            alwaysIncludeSemantics: true,
            child: ExcludeSemantics(
              excluding: !interactive,
              child: Stack(children: children),
            ),
          ),
        ),
      ),
    );
  }

  /// One [GlobalKey] per tab layout, so its accessory keeps its state (a
  /// video playing) as it moves between placements.
  final Map<Object, GlobalKey> _accessoryKeys = <Object, GlobalKey>{};

  /// The tab layout's accessory in the app's frame for [placement], or null
  /// when it has none.
  Widget? _accessory(
    ToolbarEntry entry,
    AdaptiveBottomNavigationBar bar,
    AdaptiveChrome chrome, {
    required AdaptiveChromePlacement placement,
    required bool compact,
  }) {
    final accessory = bar.accessory;
    if (accessory == null) return null;
    final frame = chrome.accessoryBuilder;
    return KeyedSubtree(
      key: _accessoryKeys.putIfAbsent(
        entry.id,
        () => GlobalKey(debugLabel: 'adaptive tab accessory'),
      ),
      child: frame == null
          ? accessory
          : frame(
              context,
              AdaptiveAccessorySpec(placement: placement, compact: compact),
              accessory,
            ),
    );
  }

  /// The accessory floating at the bottom of the content, where the tabs are
  /// not at the bottom: beside the iPhone Duo's vertical bar, or below a page
  /// with its tabs in the top strip. Its height is the room the pages keep.
  ///
  /// A [framed] accessory gets the whole width of the content and its frame
  /// places it there; one without a frame is centred, at most
  /// [kFloatingAccessoryMaxWidth] wide.
  Widget _floating(Widget accessory, {required bool framed}) {
    final pose = DuoPoseScope.of(context);
    final band = pose?.bandWidth ?? 0;
    final onLeft = pose?.onLeft ?? false;
    final bottom = math.max(
      MediaQuery.viewPaddingOf(context).bottom,
      kFloatingAccessoryMargin,
    );
    return Positioned(
      left: kFloatingAccessoryMargin + (onLeft ? band : 0),
      right: kFloatingAccessoryMargin + (onLeft ? 0 : band),
      bottom: bottom,
      child: framed
          ? _reportingHeight(accessory, bottom)
          : Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  maxWidth: kFloatingAccessoryMaxWidth,
                ),
                child: _reportingHeight(accessory, bottom),
              ),
            ),
    );
  }

  Widget _reportingHeight(Widget accessory, double bottom) => SizeReporter(
    onSizeChanged: (size) =>
        widget.accessoryHeight?.value = size.height + bottom,
    child: accessory,
  );

  /// The tabs of one tab layout in the sidebar along the leading edge,
  /// easing between a rail of icons and its full width.
  Widget _sidebarLayer(
    ToolbarEntry entry,
    AdaptiveBottomNavigationBar bar,
    AdaptiveChrome chrome,
    HostedSidebar sidebar, {
    required Widget? accessory,
    required Animation<double>? opacity,
    required bool interactive,
  }) {
    final metrics = chrome.metrics;
    final padding = MediaQuery.viewPaddingOf(context);
    // An iPad window has its controls in the top corner, over the sidebar.
    final windowControls = PlatformInfo.isIPad && _isWindowed(context);
    return Positioned(
      key: ValueKey<(String, Object)>(('adaptive_hosted_sidebar', entry.id)),
      left: 0,
      top: 0,
      bottom: 0,
      child: Offstage(
        offstage: opacity == null,
        child: IgnorePointer(
          ignoring: !interactive,
          child: FadeTransition(
            opacity: opacity ?? kAlwaysDismissedAnimation,
            alwaysIncludeSemantics: true,
            child: ExcludeSemantics(
              excluding: !interactive,
              child: AnimatedBuilder(
                animation: sidebar.progress,
                builder: (context, child) => SizedBox(
                  width:
                      metrics.sidebarCollapsedWidth +
                      (metrics.sidebarWidth - metrics.sidebarCollapsedWidth) *
                          sidebar.progress.value,
                  child: sidebar.overlaid
                      ? child
                      : Stack(
                          fit: StackFit.expand,
                          children: [
                            _SidebarBackdrop(blend: widget.blend, owner: entry),
                            child!,
                          ],
                        ),
                ),
                child: chrome.sidebarBuilder!(
                  context,
                  AdaptiveSidebarSpec(
                    items: bar.items!,
                    selectedIndex: bar.selectedIndex!,
                    onTap: (index) {
                      bar.onTap!(index);
                      sidebar.onTabTapped();
                    },
                    expanded: sidebar.expanded,
                    overlaid: sidebar.overlaid,
                    onToggle: sidebar.onToggle,
                    padding: padding.copyWith(
                      top: padding.top + (windowControls ? kHostedToolbarHeight : 0),
                    ),
                    accessory: accessory,
                    data: bar.chromeData,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Whether the app runs in a window smaller than the display.
  static bool _isWindowed(BuildContext context) {
    final display = View.of(context).display.size;
    final viewport =
        MediaQuery.sizeOf(context) * MediaQuery.devicePixelRatioOf(context);
    return (display.longestSide - viewport.longestSide).abs() > 1 ||
        (display.shortestSide - viewport.shortestSide).abs() > 1;
  }
}

/// Behind a sidebar beside the pages: the colour of the page in front, so
/// the page runs on behind the sidebar instead of ending in an edge against
/// the tab layout's own background. Blended from one page's to the next's
/// as the pages are.
class _SidebarBackdrop extends StatelessWidget {
  const _SidebarBackdrop({required this.blend, required this.owner});

  final ToolbarBlend blend;
  final ToolbarEntry owner;

  @override
  Widget build(BuildContext context) {
    final fallback =
        _opaque(owner.backgroundColor) ??
        CupertinoColors.systemBackground.resolveFrom(context);
    Color colorOf(ToolbarEntry? entry) =>
        _opaque(entry?.backgroundColor) ?? fallback;
    return ListenableBuilder(
      listenable: blend,
      builder: (context, _) {
        final upper = colorOf(blend.upper ?? owner);
        final lower = blend.lower;
        final driver = blend.driver;
        if (lower == null || driver == null) return ColoredBox(color: upper);
        final from = colorOf(lower);
        return AnimatedBuilder(
          animation: driver,
          builder: (context, _) =>
              ColoredBox(color: Color.lerp(from, upper, driver.value)!),
        );
      },
    );
  }

  static Color? _opaque(Color? color) =>
      color == null || color.a < 1 ? null : color;
}

/// How far a floating tab accessory keeps from the edges of the content.
const double kFloatingAccessoryMargin = 12;

/// The widest a floating tab accessory gets.
const double kFloatingAccessoryMaxWidth = 420;

/// The state of the sidebar the toolbar host keeps for custom chrome.
@immutable
class HostedSidebar {
  const HostedSidebar({
    required this.progress,
    required this.expanded,
    required this.overlaid,
    required this.onToggle,
    required this.onTabTapped,
  });

  /// 0 collapsed to a rail, 1 at its full width.
  final Animation<double> progress;
  final bool expanded;
  final bool overlaid;
  final VoidCallback onToggle;

  /// Called after a tab is picked in the sidebar: one expanded over the
  /// content closes.
  final VoidCallback onTabTapped;
}

/// Shrinks the bar while its tab layout scrolls, as `minimizeBehavior` asks.
class _Minimizable extends StatelessWidget {
  const _Minimizable({required this.minimized, required this.child});

  final ValueListenable<bool>? minimized;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: minimized ?? const AlwaysStoppedAnimation<bool>(false),
      child: child,
      builder: (context, minimized, child) => TweenAnimationBuilder<double>(
        tween: Tween<double>(end: minimized ? 1 : 0),
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeInOut,
        child: child,
        // As the bar in the page does: 70% of its size and half its opacity.
        builder: (context, progress, child) => Transform.scale(
          scale: 1 - progress * 0.3,
          alignment: Alignment.bottomCenter,
          child: Opacity(opacity: 1 - progress * 0.5, child: child),
        ),
      ),
    );
  }
}
