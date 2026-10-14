import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';

import '../chrome/adaptive_chrome.dart';
import '../platform/platform_info.dart';
import '../utils/size_reporter.dart';
import '../widgets/adaptive_bottom_navigation_bar.dart';
import 'duo_top_strip.dart';
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
  });

  /// The sidebar's state, while the tabs are in one.
  final HostedSidebar? sidebar;

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
    // As the iPhone Duo vertical bar does: the tabs of the page coming in and
    // of the one going out, which are one and the same while the pages
    // within a tab layout change.
    final upperTabs = registry.tabBarOwnerFor(blend.upper);
    final lowerTabs = registry.tabBarOwnerFor(blend.lower);
    final ownerTabs = registry.tabBarOwnerFor(blend.owner);
    return IgnorePointer(
      ignoring: blend.ownerIsCovered,
      child: FadeTransition(
        opacity: _uncovered,
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
    final sidebar = widget.sidebar;
    final chrome = widget.chrome;
    if (sidebar != null && chrome?.sidebarBuilder != null) {
      return _sidebarLayer(
        entry,
        bar,
        chrome!,
        sidebar,
        opacity: opacity,
        interactive: interactive,
      );
    }
    // Custom tabs on the iPhone Duo held upright go in the strip along the
    // top, beside the camera and status cluster, centred where the vertical
    // bar's first control is in the other poses.
    final strip = widget.chrome != null &&
            widget.placement == AdaptiveChromePlacement.topStrip
        ? DuoTopStripScope.of(context)
        : null;
    return Positioned(
      key: ValueKey<(String, Object)>(('adaptive_hosted_tabs', entry.id)),
      left: strip == null ? 0 : 16 + strip.clusterLeft,
      right: strip == null ? 0 : 16 + strip.clusterRight,
      top: strip == null ? null : DuoTopStrip.barTop,
      height: strip == null ? null : kDuoTopStripBarHeight,
      bottom: strip == null ? 0 : null,
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
                onSizeChanged: (size) {
                  if (strip == null) widget.height.value = size.height;
                },
                child: _Minimizable(
                  minimized: entry.tabBarMinimized,
                  child: widget.chrome?.tabBarBuilder(
                        context,
                        AdaptiveTabBarSpec(
                          placement: widget.placement,
                          items: bar.items!,
                          selectedIndex: bar.selectedIndex!,
                          onTap: bar.onTap!,
                          data: bar.chromeData,
                        ),
                      ) ??
                      IOS26NativeTabBar(
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

  /// The tabs of one tab layout in the sidebar along the leading edge,
  /// easing between a rail of icons and its full width.
  Widget _sidebarLayer(
    ToolbarEntry entry,
    AdaptiveBottomNavigationBar bar,
    AdaptiveChrome chrome,
    HostedSidebar sidebar, {
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
                  child: child,
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
