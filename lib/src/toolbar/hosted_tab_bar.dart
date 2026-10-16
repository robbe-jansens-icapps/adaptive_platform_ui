import 'dart:math' as math;

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';

import '../chrome/adaptive_chrome.dart';
import '../platform/platform_info.dart';
import '../utils/size_reporter.dart';
import '../widgets/adaptive_accessory_scope.dart';
import '../widgets/adaptive_bottom_navigation_bar.dart';
import '../widgets/adaptive_keyboard_fade.dart';
import '../widgets/ios26/ios26_glass_surface.dart';
import '../widgets/ios26/native_view_settle.dart';
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
///
/// The tab layout's accessory ([AdaptiveBottomNavigationBar.accessory]) goes
/// with the tabs: above the native bar on a glass capsule of its own, as
/// iOS 26 shows a tab bar's bottom accessory, or in the app's frame with
/// [chrome].
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
    // A sidebar stays in sight under a dialog or popover, dimmed as the
    // toolbar is; a bar along the bottom would show above it.
    final uncovered = widget.sidebar != null
        ? blend.chromeOpacity
        : dialog != null
        ? kAlwaysCompleteAnimation
        : _uncovered;
    return IgnorePointer(
      ignoring: blend.ownerIsCovered,
      child: FadeTransition(
        opacity: uncovered,
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
                uncovered: uncovered,
              ),
          ],
        ),
      ),
    );
  }

  /// The bar of one tab layout; off stage while no [opacity] shows it. The
  /// widgets around the native bar are the same in every state, so it is
  /// never made again, also as an accessory comes and goes above it.
  ///
  /// [uncovered] is the opacity of all the bars, as a sheet or a popover
  /// covers them.
  Widget _layer(
    ToolbarEntry entry, {
    required Animation<double>? opacity,
    required bool interactive,
    required Animation<double> uncovered,
    ModalRoute<Object?>? dialog,
  }) {
    final bar = entry.tabBar!;
    final chrome = widget.chrome;
    // The native views of the accessory and its tray leave the screen while
    // they fade.
    final fade = AnimationMin<double>(
      opacity ?? kAlwaysDismissedAnimation,
      uncovered,
    );
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
              // The accessory is part of it, so the pages keep clear of both.
              child: SizeReporter(
                onSizeChanged: (size) => widget.height.value = size.height,
                child: _AccessoryOverTabs(
                  capsule: _capsules[entry.id],
                  layout: bar.accessoryLayout,
                  accessory: _nativeAccessory(
                    entry,
                    bar,
                    fade: fade,
                    dialog: dialog,
                  ),
                  tray:
                      bar.accessory == null ||
                          bar.accessoryLayout != AdaptiveTabAccessoryLayout.tray
                      ? null
                      : _tray(fade: fade, dialog: dialog),
                  tabs: _Minimizable(
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
      ),
    );
  }

  /// The tab layout's accessory with the native bar, or null when it has
  /// none: on its glass capsule, or on the tray's glass, out of the
  /// keyboard's way rather than under it, and under a dialog's barrier with
  /// the tabs. While [fade] is not fully in, its native views leave the
  /// screen and their stand-ins fade.
  Widget? _nativeAccessory(
    ToolbarEntry entry,
    AdaptiveBottomNavigationBar bar, {
    required Animation<double> fade,
    required ModalRoute<Object?>? dialog,
  }) {
    final accessory = bar.accessory;
    if (accessory == null) return null;
    final width = MediaQuery.sizeOf(context).width;
    final capsule = _capsules[entry.id];
    final layout = bar.accessoryLayout;
    final spec = switch (layout) {
      AdaptiveTabAccessoryLayout.beside => besideAccessorySpec(
        width: width,
        capsule: capsule,
      ),
      AdaptiveTabAccessoryLayout.tray => trayAccessorySpec(
        width: width,
        capsule: capsule,
      ),
      AdaptiveTabAccessoryLayout.floating => const AdaptiveAccessorySpec(
        placement: AdaptiveChromePlacement.bottom,
        compact: false,
      ),
    };
    final onTray = layout == AdaptiveTabAccessoryLayout.tray;
    return NativeViewSettleScope(
      fade: fade,
      child: AdaptiveKeyboardFade(
        holdsNativeViews: true,
        child: Stack(
          fit: StackFit.passthrough,
          children: [
            nativeAccessory(
              widget.blend.registry,
              entry,
              accessory,
              spec,
              glass: !onTray,
            ),
            // On the tray, the tray's barrier dims it.
            if (!onTray)
              Positioned.fill(
                child: _BarrierOverTabs(route: dialog, fills: true),
              ),
          ],
        ),
      ),
    );
  }

  /// The glass tray the accessory and the tabs share
  /// ([AdaptiveTabAccessoryLayout.tray]), under a dialog's barrier with them.
  /// It takes the touches that miss them, as a sheet would, rather than
  /// letting them through to the page. While [fade] is not fully in, its
  /// native glass leaves the screen and its stand-in fades.
  Widget _tray({
    required Animation<double> fade,
    required ModalRoute<Object?>? dialog,
  }) {
    return NativeViewSettleScope(
      fade: fade,
      child: AdaptiveKeyboardFade(
        holdsNativeViews: true,
        child: AbsorbPointer(
          child: Stack(
            fit: StackFit.expand,
            children: [
              const IOS26GlassSurface(
                corners: GlassSurfaceCorners.concentric,
                cornerRadius: kAccessoryTrayCornerRadius,
              ),
              _BarrierOverTabs(
                route: dialog,
                fills: true,
                borderRadius: BorderRadius.vertical(
                  top: const Radius.circular(kAccessoryTrayCornerRadius),
                  bottom: Radius.circular(
                    IOS26GlassSurface.concentricRadius(
                      inset: kAccessoryTrayInset,
                      minimum: kAccessoryTrayCornerRadius,
                    ),
                  ),
                ),
              ),
            ],
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
    final spec = AdaptiveAccessorySpec(placement: placement, compact: compact);
    return KeyedSubtree(
      key: widget.blend.registry.accessoryKey(entry.id),
      child: AdaptiveAccessoryScope(
        spec: spec,
        child: frame == null ? accessory : frame(context, spec, accessory),
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

/// The widest a floating tab accessory gets, and one above the native tab
/// bar.
const double kFloatingAccessoryMaxWidth = 420;

/// The room between a tab accessory and the capsule the native tab bar
/// floats its tabs on, below it.
const double kNativeAccessoryGap = 8;

/// How far in from the sides of the window the native tab bar has the
/// capsule it floats its tabs on, on an iPhone held upright: where the
/// accessory goes until the bar has said where its capsule is.
const double kNativeTabCapsuleInset = 21;

/// How tall the capsule of the native tab bar is: what an inline accessory is
/// laid out in until the bar has said where its capsule is.
const double kNativeTabCapsuleHeight = 62;

/// The room the tabs of a phone spare for an accessory beside them
/// ([AdaptiveTabAccessoryLayout.beside]) and still show their labels in full.
const double kBesideAccessoryMinRoom = 80;

/// Below this much room an accessory beside the tabs is
/// [AdaptiveAccessorySpec.compact].
const double kBesideAccessoryCompactRoom = 200;

/// Where an accessory beside the tabs goes: in the room the native bar
/// leaves beside the capsule of its tabs in a window [width] wide, at least
/// [kBesideAccessoryMinRoom], which the tabs make room for where they fill
/// the width.
AdaptiveAccessorySpec besideAccessorySpec({
  required double width,
  required Rect? capsule,
}) {
  final beside = capsule == null
      ? 0.0
      : width -
            2 * kNativeTabCapsuleInset -
            capsule.width -
            kNativeAccessoryGap;
  final room = math.max(kBesideAccessoryMinRoom, beside);
  return AdaptiveAccessorySpec(
    placement: AdaptiveChromePlacement.bottom,
    compact: room < kBesideAccessoryCompactRoom,
    room: room,
    layout: AdaptiveTabAccessoryLayout.beside,
  );
}

/// How far the tray of the accessory and the tabs
/// ([AdaptiveTabAccessoryLayout.tray]) keeps from the sides and the bottom
/// of the window, as a sheet floats at its smallest.
const double kAccessoryTrayInset = 8;

/// The radius of the tray's corners away from the display's: its top ones.
/// Those along the bottom follow the display's.
const double kAccessoryTrayCornerRadius = 28;

/// The room the tray keeps around the capsule of the tabs and above the
/// accessory: what the native bar keeps below the capsule, less the tray's
/// inset, so the capsule sits in the tray as the tray sits in the window.
double _trayPadding(double tabsHeight, Rect capsule) =>
    (tabsHeight - capsule.bottom - kAccessoryTrayInset).clamp(8.0, 20.0);

/// Where the native bar has the capsule of its tabs in a window [width]
/// wide, until it has said so itself.
Rect _capsuleOr(Rect? capsule, double width) =>
    capsule ??
    Rect.fromLTRB(
      kNativeTabCapsuleInset,
      0,
      math.max(kNativeTabCapsuleInset, width - kNativeTabCapsuleInset),
      kNativeTabCapsuleHeight,
    );

/// How wide an accessory on the tray goes in a window [width] wide
/// ([AdaptiveAccessorySpec.room]): as wide as the tabs' capsule, or where
/// that is narrower, as wide as one floating above them gets at most
/// ([kFloatingAccessoryMaxWidth]) and the window lets it.
double _trayAccessoryWidth(double width, Rect capsule) => math.max(
  capsule.width,
  math.min(kFloatingAccessoryMaxWidth, width - 2 * kNativeTabCapsuleInset),
);

/// What an accessory on the tray with the tabs is told: how wide it goes in
/// a window [width] wide.
AdaptiveAccessorySpec trayAccessorySpec({
  required double width,
  required Rect? capsule,
}) => AdaptiveAccessorySpec(
  placement: AdaptiveChromePlacement.bottom,
  compact: false,
  room: _trayAccessoryWidth(width, _capsuleOr(capsule, width)),
  layout: AdaptiveTabAccessoryLayout.tray,
);

/// A tab layout's [accessory] with the native chrome: in [spec]'s
/// [AdaptiveAccessoryScope], on its glass capsule ([NativeAccessoryGlass])
/// unless it has other [glass] under it, in the key that keeps its state
/// wherever the host shows it.
Widget nativeAccessory(
  ToolbarRegistry registry,
  ToolbarEntry tabs,
  Widget accessory,
  AdaptiveAccessorySpec spec, {
  bool glass = true,
}) => KeyedSubtree(
  key: registry.accessoryKey(tabs.id),
  child: AdaptiveAccessoryScope(
    spec: spec,
    // The same element either way, so the accessory keeps its state as it
    // moves on or off the tray.
    child: NativeAccessoryGlass(glass: glass, child: accessory),
  ),
);

/// The Liquid Glass capsule the native chrome floats a tab accessory on, as
/// iOS 26 floats the bottom accessory of its tab bar: the accessory's size,
/// with the accessory on it. An accessory with nothing to show (no size)
/// gets no glass.
class NativeAccessoryGlass extends StatefulWidget {
  const NativeAccessoryGlass({
    super.key,
    this.glass = true,
    required this.child,
  });

  /// Whether it shows its glass: not where it sits on other glass.
  final bool glass;

  final Widget child;

  @override
  State<NativeAccessoryGlass> createState() => _NativeAccessoryGlassState();
}

class _NativeAccessoryGlassState extends State<NativeAccessoryGlass> {
  /// Whether the accessory had no size when last laid out.
  bool _empty = false;

  void _onSize(Size size) {
    final empty = size.isEmpty;
    if (mounted && empty != _empty) setState(() => _empty = empty);
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.passthrough,
      children: [
        // In the same place either way, so the accessory keeps its own.
        Positioned.fill(
          child: _empty || !widget.glass
              ? const SizedBox.shrink()
              : const IOS26GlassSurface(
                  corners: GlassSurfaceCorners.capsule,
                  interactive: true,
                ),
        ),
        SizeReporter(onSizeChanged: _onSize, child: widget.child),
      ],
    );
  }
}

enum _TabsSlot { tray, accessory, tabs }

/// Where [_RenderAccessoryOverTabs] puts its children: its size, where the
/// tabs and the accessory go, and the tray under both, if it shows.
typedef _Placed = ({Size size, Offset tabs, Offset accessory, Rect? tray});

/// The native tab bar ([tabs]) with the tab layout's [accessory], as
/// [layout] sets them:
///
/// - floating: above the bar, as wide as the [capsule] the bar floats its
///   tabs on (in the bar's coordinates), at most [kFloatingAccessoryMaxWidth]
///   wide and centred over it, and [kNativeAccessoryGap] above it;
/// - beside: at the trailing end of the capsule, as tall as it;
/// - tray: above the capsule as when floating, with the [tray] under both
///   and the tabs at their whole width.
///
/// It is as tall as all of them together, for the pages to keep clear of
/// them; an accessory with nothing to show takes no room, and no tray. The
/// bar keeps its place at the bottom, and its element, as the accessory
/// comes and goes.
class _AccessoryOverTabs
    extends SlottedMultiChildRenderObjectWidget<_TabsSlot, RenderBox> {
  const _AccessoryOverTabs({
    required this.capsule,
    required this.accessory,
    required this.tabs,
    this.tray,
    this.layout = AdaptiveTabAccessoryLayout.floating,
  });

  final AdaptiveTabAccessoryLayout layout;

  final Rect? capsule;
  final Widget? accessory;
  final Widget tabs;

  /// The glass under the accessory and the tabs on a tray.
  final Widget? tray;

  @override
  Iterable<_TabsSlot> get slots => _TabsSlot.values;

  @override
  Widget? childForSlot(_TabsSlot slot) => switch (slot) {
    _TabsSlot.tray => tray,
    _TabsSlot.accessory => accessory,
    _TabsSlot.tabs => tabs,
  };

  @override
  _RenderAccessoryOverTabs createRenderObject(BuildContext context) =>
      _RenderAccessoryOverTabs(capsule, layout: layout);

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderAccessoryOverTabs renderObject,
  ) {
    renderObject
      ..capsule = capsule
      ..accessoryLayout = layout;
  }
}

class _RenderAccessoryOverTabs extends RenderBox
    with SlottedContainerRenderObjectMixin<_TabsSlot, RenderBox> {
  _RenderAccessoryOverTabs(
    this._capsule, {
    required AdaptiveTabAccessoryLayout layout,
  }) : _layout = layout;

  Rect? _capsule;
  set capsule(Rect? value) {
    if (value == _capsule) return;
    _capsule = value;
    markNeedsLayout();
  }

  AdaptiveTabAccessoryLayout _layout;
  set accessoryLayout(AdaptiveTabAccessoryLayout value) {
    if (value == _layout) return;
    _layout = value;
    markNeedsLayout();
  }

  /// Whether the tray shows, as last laid out.
  bool _trayShown = false;

  RenderBox? get _tray => childForSlot(_TabsSlot.tray);
  RenderBox? get _accessory => childForSlot(_TabsSlot.accessory);
  RenderBox? get _tabs => childForSlot(_TabsSlot.tabs);

  // Painted and hit in this order: the tray under the bar, the accessory
  // over it.
  Iterable<RenderBox> get _painted => [
    if (_trayShown) ?_tray,
    ?_tabs,
    ?_accessory,
  ];

  /// Where the accessory goes across: over the capsule, at most
  /// [kFloatingAccessoryMaxWidth] wide.
  (double, double) _across(double width) {
    final capsule = _capsule;
    var left = capsule?.left ?? kNativeTabCapsuleInset;
    var right = capsule?.right ?? width - kNativeTabCapsuleInset;
    if (right - left > kFloatingAccessoryMaxWidth) {
      final centre = (left + right) / 2;
      left = centre - kFloatingAccessoryMaxWidth / 2;
      right = centre + kFloatingAccessoryMaxWidth / 2;
    }
    left = left.clamp(0.0, width);
    return (left, right.clamp(left, width));
  }

  /// Lays the children out with [layoutChild], and says where each goes.
  _Placed _layOut(
    BoxConstraints constraints,
    Size Function(RenderBox child, BoxConstraints constraints) layoutChild,
  ) {
    final placed = _accessory == null
        ? _layOutFloating(constraints, layoutChild)
        : switch (_layout) {
            AdaptiveTabAccessoryLayout.beside => _layOutBeside(
              constraints,
              layoutChild,
            ),
            AdaptiveTabAccessoryLayout.tray => _layOutTray(
              constraints,
              layoutChild,
            ),
            AdaptiveTabAccessoryLayout.floating => _layOutFloating(
              constraints,
              layoutChild,
            ),
          };
    // A tray that does not show is laid out all the same, to no size.
    if (placed.tray == null && _tray != null) {
      layoutChild(_tray!, BoxConstraints.tight(Size.zero));
    }
    return placed;
  }

  _Placed _layOutFloating(
    BoxConstraints constraints,
    Size Function(RenderBox child, BoxConstraints constraints) layoutChild,
  ) {
    final tabs = _tabs;
    final tabsSize = tabs == null ? Size.zero : layoutChild(tabs, constraints);
    final width = constraints.hasBoundedWidth
        ? constraints.maxWidth
        : tabsSize.width;
    final accessory = _accessory;
    var above = 0.0;
    var at = Offset.zero;
    if (accessory != null) {
      final (left, right) = _across(width);
      final capsuleTop = _capsule?.top ?? 0;
      final size = layoutChild(
        accessory,
        BoxConstraints.tightFor(width: right - left).copyWith(
          maxHeight: math.max(
            0.0,
            constraints.maxHeight - tabsSize.height - kNativeAccessoryGap,
          ),
        ),
      );
      if (!size.isEmpty) {
        above = math.max(0, size.height + kNativeAccessoryGap - capsuleTop);
      }
      at = Offset(left, above + capsuleTop - kNativeAccessoryGap - size.height);
    }
    return (
      size: constraints.constrain(Size(width, tabsSize.height + above)),
      tabs: Offset(0, above),
      accessory: at,
      tray: null,
    );
  }

  /// The accessory beside the tabs: laid out first, as tall as their capsule,
  /// its width taken from the tabs where they fill the width; then at the
  /// trailing end of the capsule, centred on it. No taller than the tabs.
  _Placed _layOutBeside(
    BoxConstraints constraints,
    Size Function(RenderBox child, BoxConstraints constraints) layoutChild,
  ) {
    final capsule = _capsule;
    final width = constraints.maxWidth;
    final accessory = layoutChild(
      _accessory!,
      BoxConstraints(
        maxWidth: width / 2,
        maxHeight: capsule?.height ?? kNativeTabCapsuleHeight,
      ),
    );
    final room = accessory.isEmpty
        ? 0.0
        : accessory.width + kNativeAccessoryGap;
    final tabs = _tabs;
    final tabsSize = tabs == null
        ? Size.zero
        : layoutChild(
            tabs,
            constraints.copyWith(
              minWidth: 0,
              maxWidth: math.max(0.0, width - room),
            ),
          );
    final left =
        (capsule?.right ?? width - room - kNativeTabCapsuleInset) +
        kNativeAccessoryGap;
    final centre = capsule?.center.dy ?? tabsSize.height / 2;
    return (
      size: constraints.constrain(Size(width, tabsSize.height)),
      tabs: Offset.zero,
      accessory: Offset(left, centre - accessory.height / 2),
      tray: null,
    );
  }

  /// The accessory and the tabs on the tray: the tabs at their whole width,
  /// the accessory [kNativeAccessoryGap] above their capsule and centred on
  /// it, and the tray around both, as far from them as it keeps the capsule
  /// from its bottom ([_trayPadding]).
  _Placed _layOutTray(
    BoxConstraints constraints,
    Size Function(RenderBox child, BoxConstraints constraints) layoutChild,
  ) {
    final tabs = _tabs;
    final tabsSize = tabs == null ? Size.zero : layoutChild(tabs, constraints);
    final width = constraints.hasBoundedWidth
        ? constraints.maxWidth
        : tabsSize.width;
    final capsule = _capsuleOr(_capsule, width);
    final padding = _trayPadding(tabsSize.height, capsule);
    final accessoryWidth = _trayAccessoryWidth(width, capsule);
    final accessory = layoutChild(
      _accessory!,
      BoxConstraints.tightFor(width: accessoryWidth).copyWith(
        maxHeight: math.max(
          0.0,
          constraints.maxHeight -
              tabsSize.height -
              kNativeAccessoryGap -
              padding,
        ),
      ),
    );
    if (accessory.isEmpty) {
      return (
        size: constraints.constrain(Size(width, tabsSize.height)),
        tabs: Offset.zero,
        accessory: Offset.zero,
        tray: null,
      );
    }
    final above = math.max(
      0.0,
      padding + accessory.height + kNativeAccessoryGap - capsule.top,
    );
    final left = (capsule.center.dx - accessoryWidth / 2)
        .clamp(0.0, math.max(0.0, width - accessoryWidth))
        .toDouble();
    final top = above + capsule.top - kNativeAccessoryGap - accessory.height;
    final tray = Rect.fromLTRB(
      math.min(left, capsule.left) - padding,
      top - padding,
      math.max(left + accessoryWidth, capsule.right) + padding,
      above + capsule.bottom + padding,
    );
    if (_tray case final trayBox?) {
      layoutChild(trayBox, BoxConstraints.tight(tray.size));
    }
    return (
      size: constraints.constrain(Size(width, tabsSize.height + above)),
      tabs: Offset(0, above),
      accessory: Offset(left, top),
      tray: tray,
    );
  }

  @override
  Size computeDryLayout(BoxConstraints constraints) =>
      _layOut(constraints, (child, c) => child.getDryLayout(c)).size;

  @override
  void performLayout() {
    final placed = _layOut(constraints, (child, c) {
      child.layout(c, parentUsesSize: true);
      return child.size;
    });
    size = placed.size;
    _trayShown = placed.tray != null;
    if (_tabs case final tabs?) {
      (tabs.parentData! as BoxParentData).offset = placed.tabs;
    }
    if (_accessory case final accessory?) {
      (accessory.parentData! as BoxParentData).offset = placed.accessory;
    }
    if (_tray case final tray?) {
      (tray.parentData! as BoxParentData).offset =
          placed.tray?.topLeft ?? Offset.zero;
    }
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    for (final child in _painted) {
      context.paintChild(
        child,
        offset + (child.parentData! as BoxParentData).offset,
      );
    }
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) {
    for (final child in _painted.toList().reversed) {
      final offset = (child.parentData! as BoxParentData).offset;
      final hit = result.addWithPaintOffset(
        offset: offset,
        position: position,
        hitTest: (result, transformed) =>
            child.hitTest(result, position: transformed),
      );
      if (hit) return true;
    }
    return false;
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

/// The barrier of a dialog ([route]) over the tabs, which sit above the
/// navigator, out of the reach of the barrier the dialog lays over the page:
/// in the shape of the [capsule] the native bar floats its tabs on, and only
/// there, as the rest of the bar lets the page under the barrier show
/// through. It comes and goes with the dialog, in its colour, as the route
/// draws its own barrier ([ModalRoute.buildModalBarrier]).
class _BarrierOverTabs extends StatelessWidget {
  const _BarrierOverTabs({
    required this.route,
    this.capsule,
    this.fills = false,
    this.borderRadius,
  });

  final ModalRoute<Object?>? route;
  final Rect? capsule;

  /// Whether the capsule is all of it: the glass of the tab accessory, or
  /// the tray.
  final bool fills;

  /// The corners of what it covers, where that is no capsule: the tray's.
  final BorderRadius? borderRadius;

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
        (capsule == null && !fills) ||
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
    final dim = AnimatedBuilder(
      animation: barrier,
      builder: (context, _) => DecoratedBox(
        decoration: ShapeDecoration(
          color: barrier.value,
          shape: borderRadius == null
              ? const StadiumBorder()
              : RoundedSuperellipseBorder(borderRadius: borderRadius!),
        ),
      ),
    );
    return IgnorePointer(
      child: Stack(
        children: [
          if (fills)
            Positioned.fill(child: dim)
          else
            Positioned.fromRect(rect: capsule!, child: dim),
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
