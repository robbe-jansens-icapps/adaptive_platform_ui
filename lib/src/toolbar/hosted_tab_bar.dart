import 'dart:math' as math;

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';

import '../chrome/adaptive_chrome.dart';
import '../platform/platform_info.dart';
import '../utils/size_reporter.dart';
import '../widgets/adaptive_bottom_navigation_bar.dart';
import '../widgets/adaptive_keyboard_fade.dart';
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
/// drawn over it. It stays put and at full opacity while the pages within the
/// tabs change.
///
/// A native view on screen still makes every frame dearer while pages move,
/// so the bar is out of the way for most of a transition between the tabs and
/// a page without them, and for all of its end, where a stutter shows most:
/// it fades out over the first fifth of a push, and stays away while a page
/// pops or is swiped back off the tabs, to fade in once the tabs hold still.
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

class _HostedTabBarState extends State<HostedTabBar>
    with SingleTickerProviderStateMixin {
  /// The tab layouts the last build drew a bar for.
  List<ToolbarEntry> _built = const <ToolbarEntry>[];

  /// The opacity of the bar in front: it fades in once the pages hold still
  /// after a transition that brought the tabs in.
  late final AnimationController _reveal;

  /// Whether a transition running now, or that just ended, brings a bar in.
  bool _revealPending = false;

  /// How far into a push the bar of the page going out is gone, and so off
  /// screen for the rest of it.
  static const double _leaveBy = 0.2;

  static final Animatable<double> _leaveOnPush = Tween<double>(begin: 1, end: 0)
      .chain(
        CurveTween(curve: const Interval(0, _leaveBy, curve: Curves.easeOut)),
      );

  /// The same, for a pop: the driver runs from 1 down to 0.
  static final Animatable<double> _leaveOnPop = CurveTween(
    curve: const Interval(1 - _leaveBy, 1, curve: Curves.easeIn),
  );

  /// Fully out while a sheet or a popover covers the tabs: the bar would show
  /// above them, as it sits above the navigator.
  late Animation<double> _uncovered;

  /// Where each tab layout's native bar has the capsule it floats its tabs on,
  /// as the bar last said, by the layout's id.
  final Map<Object, Rect?> _capsules = <Object, Rect?>{};

  void _onCapsuleChanged(Object id, Rect? capsule) {
    if (!mounted || _capsules[id] == capsule) return;
    setState(() => _capsules[id] = capsule);
  }

  @override
  void initState() {
    super.initState();
    _reveal = AnimationController(
      vsync: this,
      duration: kToolbarItemSwapDuration,
      value: 1,
    );
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
    _reveal.dispose();
    super.dispose();
  }

  void _listen(ToolbarBlend blend) {
    // Out of the way before a sheet or a popover coming up reaches it, and
    // back only once that has mostly gone again: drawn above every route, it
    // would otherwise show through them.
    final curved = _coverCurve = CurvedAnimation(
      parent: blend.cover,
      curve: const Interval(0, 0.5, curve: Curves.easeOut),
      reverseCurve: const Interval(0, 0.4, curve: Curves.easeIn),
    );
    _uncovered = ReverseAnimation(curved);
    blend.addListener(_rebuild);
    blend.registry.addListener(_onRegistryChanged);
  }

  CurvedAnimation? _coverCurve;

  void _unlisten(ToolbarBlend blend) {
    _coverCurve?.dispose();
    _coverCurve = null;
    blend.removeListener(_rebuild);
    blend.registry.removeListener(_onRegistryChanged);
  }

  void _rebuild() {
    _updateReveal();
    setState(() {});
  }

  /// Whether the running transition shows the upper page coming in: a push,
  /// or a crossfade between two tab layouts. Otherwise it is a pop or a back
  /// swipe, which uncover the lower page.
  bool get _bringsUpperIn {
    final blend = widget.blend;
    return blend.upperOwns && !blend.isGestureBlend;
  }

  /// While pages move between two tab layouts, or between the tabs and a page
  /// without them: the tab layout whose bar goes out, and the one whose bar
  /// comes in. Both null while the pages within one tab layout change.
  (ToolbarEntry?, ToolbarEntry?) _goingAndComing() {
    final blend = widget.blend;
    final registry = blend.registry;
    final upper = registry.tabBarOwnerFor(blend.upper);
    final lower = registry.tabBarOwnerFor(blend.lower);
    if (upper?.id == lower?.id) return (null, null);
    return _bringsUpperIn ? (lower, upper) : (upper, lower);
  }

  /// Notes a bar that a transition brings in, which waits off stage while the
  /// pages move, and fades it in once they hold still.
  void _updateReveal() {
    final blend = widget.blend;
    if (blend.isBlending) {
      if (_goingAndComing().$2 != null) _revealPending = true;
      return;
    }
    if (_revealPending && blend.registry.tabBarOwnerFor(blend.owner) != null) {
      if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) {
        _reveal.value = 1;
      } else {
        _reveal.forward(from: 0);
      }
    }
    _revealPending = false;
  }

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
    registry.keepAccessoriesOf(_built.map((entry) => entry.id));
    // No accessory floats at the bottom of the content: none of its room is
    // kept there any more. The bottom placement measures its own.
    final floats =
        widget.chrome != null &&
        widget.placement == AdaptiveChromePlacement.topStrip &&
        _built.any((entry) => entry.tabBar?.accessory != null);
    final accessoryHeight = widget.accessoryHeight;
    if (!floats && accessoryHeight != null && accessoryHeight.value != 0) {
      SchedulerBinding.instance.addPostFrameCallback(
        (_) => accessoryHeight.value = 0,
      );
    }
    final ownerTabs = registry.tabBarOwnerFor(blend.owner);
    // The bar that stays in view: the owner's, or while pages move, the one
    // of the tab layout on both sides of the transition. A bar that comes in
    // waits off stage until the pages hold still.
    final upperTabs = registry.tabBarOwnerFor(blend.upper);
    final lowerTabs = registry.tabBarOwnerFor(blend.lower);
    final driver = blend.driver;
    final shown = driver == null
        ? ownerTabs
        : upperTabs?.id == lowerTabs?.id
        ? upperTabs
        : null;
    final going = driver == null ? null : _goingAndComing().$1;
    final leave = driver?.drive(_bringsUpperIn ? _leaveOnPush : _leaveOnPop);
    _capsules.removeWhere((id, _) => !_built.any((entry) => entry.id == id));
    // Under a dialog the native bar stays in sight, under the dialog's
    // barrier as UIKit's does: the dialog comes up in the middle of the
    // screen, clear of it. The bar sits above the navigator, out of the
    // barrier's reach, so the barrier is laid over the capsule it floats its
    // tabs on here. A sheet or a popover may come up over the bar, which
    // would show above them: for those, and with no capsule to dim, it makes
    // way. The tabs it covers are the owner's, or those leaving as a page
    // without them comes up over the dialog: they leave with that page.
    final underDialog = ownerTabs ?? going;
    final dialog =
        widget.chrome == null &&
            widget.sidebar == null &&
            blend.coveredByDialog &&
            underDialog != null &&
            _capsules[underDialog.id] != null
        ? blend.coveringRoute! as ModalRoute<Object?>
        : null;
    return IgnorePointer(
      ignoring: blend.ownerIsCovered,
      child: FadeTransition(
        // A sidebar stays in sight under a dialog or popover, dimmed as the
        // toolbar is; a bar along the bottom would show above it.
        opacity: widget.sidebar != null
            ? blend.chromeOpacity
            : dialog != null
            ? kAlwaysCompleteAnimation
            : _uncovered,
        child: Stack(
          fit: StackFit.expand,
          children: [
            for (final entry in _built)
              _layer(
                entry,
                // Custom chrome draws no native view, so its bars follow the
                // pages: in as a page with the tabs comes in and out as it
                // leaves, under the finger during a back swipe.
                opacity: widget.chrome != null
                    ? tabsFollowingPages(
                        blend,
                        entry,
                        upper: upperTabs,
                        lower: lowerTabs,
                      )
                    : entry.id == shown?.id
                    ? _reveal
                    : entry.id == going?.id
                    ? leave
                    : null,
                interactive: entry.id == ownerTabs?.id,
                dialog: entry.id == underDialog?.id ? dialog : null,
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
    ModalRoute<Object?>? dialog,
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
                  // The same children whether a dialog covers the tabs or
                  // not, so the native bar stays put.
                  child: Stack(
                    children: [
                      IOS26NativeTabBar(
                        destinations: bar.items!,
                        selectedIndex: bar.selectedIndex!,
                        onTap: bar.onTap!,
                        tint:
                            bar.selectedItemColor ??
                            CupertinoTheme.of(context).primaryColor,
                        unselectedItemTint: bar.unselectedItemColor,
                        onCapsuleChanged: (capsule) =>
                            _onCapsuleChanged(entry.id, capsule),
                      ),
                      Positioned.fill(
                        child: _BarrierOverTabs(
                          route: dialog,
                          capsule: _capsules[entry.id],
                        ),
                      ),
                    ],
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
    // On the iPhone Duo held sideways the accessory is in the vertical bar,
    // above the tabs (HostedDuoBar).
    final accessory = placement == AdaptiveChromePlacement.vertical
        ? null
        : _accessory(
            entry,
            bar,
            chrome,
            placement: placement,
            compact: inSidebar && !sidebar.expanded,
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
            // Out of the way of the keyboard rather than under it.
            child: AdaptiveKeyboardFade(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [?accessory, ?tabs],
              ),
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
      key: widget.blend.registry.accessoryKey(entry.id),
      child: frame == null
          ? accessory
          : frame(
              context,
              AdaptiveAccessorySpec(placement: placement, compact: compact),
              accessory,
            ),
    );
  }

  /// The accessory floating at the bottom of the content below a page with
  /// its tabs in the iPhone Duo's top strip. Its height is the room the pages
  /// keep.
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
      child: AdaptiveKeyboardFade(
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
      ),
    );
  }

  /// An accessory with nothing to show (no height) takes no room at all,
  /// not even its margin above the bottom.
  Widget _reportingHeight(Widget accessory, double bottom) => SizeReporter(
    onSizeChanged: (size) => widget.accessoryHeight?.value = size.height > 0
        ? size.height + bottom
        : 0,
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
                      top:
                          padding.top +
                          (windowControls ? kHostedToolbarHeight : 0),
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

/// The barrier of a dialog ([route]) over the tabs, which sit above the
/// navigator, out of the reach of the barrier the dialog lays over the page:
/// in the shape of the [capsule] the native bar floats its tabs on, and only
/// there, as the rest of the bar lets the page under the barrier show
/// through. It comes and goes with the dialog, in its colour, as the route
/// draws its own barrier ([ModalRoute.buildModalBarrier]).
class _BarrierOverTabs extends StatelessWidget {
  const _BarrierOverTabs({required this.route, required this.capsule});

  final ModalRoute<Object?>? route;
  final Rect? capsule;

  /// How much of what is behind it the native bar's glass shows, as measured
  /// on iOS 26: what is behind it is under the barrier already, so a barrier
  /// as strong as the page's left the capsule a fifth darker than the page
  /// around it. Laid over it lighter by as much, it ends up as dim.
  static const double _glassShowsThrough = 0.4;

  /// The barrier's [color] as laid over the glass.
  static Color _overGlass(Color color) => color.withValues(
    alpha: 1 - (1 - color.a) / (1 - _glassShowsThrough * color.a),
  );

  @override
  Widget build(BuildContext context) {
    final route = this.route;
    final capsule = this.capsule;
    final color = route?.barrierColor;
    final animation = route?.animation;
    if (route == null ||
        capsule == null ||
        color == null ||
        color.a == 0 ||
        animation == null) {
      return const SizedBox.shrink();
    }
    final barrier = animation.drive(
      ColorTween(
        begin: color.withValues(alpha: 0),
        end: _overGlass(color),
      ).chain(CurveTween(curve: route.barrierCurve)),
    );
    return IgnorePointer(
      child: Stack(
        children: [
          Positioned.fromRect(
            rect: capsule,
            child: AnimatedBuilder(
              animation: barrier,
              builder: (context, _) => DecoratedBox(
                decoration: ShapeDecoration(
                  color: barrier.value,
                  shape: const StadiumBorder(),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
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

/// The opacity of the tabs of [entry] while the pages move with custom
/// chrome, given the tabs of the page shown at the [upper] and the [lower]
/// end of the blend; null while they are of neither.
///
/// Where only one of the two pages has tabs, they fade all through the
/// transition, as the page without them covers or uncovers them, rather
/// than in half of it: there is no second bar for them to blur with.
/// Between two tab layouts they cross as the toolbar's controls do.
Animation<double>? tabsFollowingPages(
  ToolbarBlend blend,
  ToolbarEntry entry, {
  required ToolbarEntry? upper,
  required ToolbarEntry? lower,
}) {
  final driver = blend.driver;
  if (entry.id == upper?.id) {
    if (lower?.id == upper!.id) return kAlwaysCompleteAnimation;
    if (lower == null && driver != null) return driver;
    return blend.upperOpacity;
  }
  if (entry.id == lower?.id) {
    if (upper == null && driver != null) return ReverseAnimation(driver);
    return blend.lowerOpacity;
  }
  return null;
}
