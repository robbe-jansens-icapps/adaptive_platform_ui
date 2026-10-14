import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show Material, MaterialType;
import 'package:flutter/widgets.dart';
import 'package:foldable/foldable.dart';

import '../chrome/adaptive_chrome.dart';
import '../platform/platform_info.dart';
import '../platform/system_vertical_bar.dart';
import '../widgets/adaptive_glass.dart';
import '../widgets/adaptive_toast.dart';
import 'duo_top_strip.dart';
import 'duo_vertical_bar.dart';
import 'fold_scope.dart';
import 'hosted_duo_bar.dart';
import 'hosted_tab_bar.dart';
import 'hosted_top_toolbar.dart';
import 'toolbar_blend.dart';
import 'toolbar_chrome_scope.dart';
import 'toolbar_registry.dart';

/// Fixed toolbar chrome that lives above the navigator.
///
/// Install it once around the navigator (an app `builder` is the right
/// place; [AdaptiveApp] does this for you). It owns a [ToolbarRegistry] that
/// every [AdaptiveScaffold] below publishes its app bar to, and it draws one
/// persistent bar whose items change as routes come and go. Because the bar
/// is not part of any route it stays put during page transitions, exactly
/// like the system bars on iOS 26 and the vertical bar on the iPhone Duo
/// inner display.
///
/// Works with any router: it depends on nothing but the widget tree.
///
/// With [chrome] the bars are the app's own, drawn by Flutter on every
/// platform, and the host places them the same way.
class AdaptiveToolbarHost extends StatefulWidget {
  const AdaptiveToolbarHost({
    super.key,
    required this.child,
    this.chrome,
    this.hostsTabBar = true,
    @visibleForTesting this.debugFold,
    @visibleForTesting this.debugVerticalBarEdge,
  });

  /// The navigator (or whatever the app's `builder` receives).
  final Widget child;

  /// The app's own bars, in place of the native iOS 26 ones. The host then
  /// draws the chrome on every platform, not only on iOS 26 and later. Keep
  /// one instance: a new one rebuilds every page that reads it.
  final AdaptiveChrome? chrome;

  /// Whether the host draws the native tab bar of a tab layout at the bottom
  /// of the screen, above the navigator, on iOS 26+ (outside the iPhone Duo
  /// vertical bar, which holds the tabs anyway). It then stays put while
  /// pages are pushed over the tabs and popped, fading out and in with them,
  /// instead of sliding with the tabs page under the page that comes in,
  /// which costs frames on every step of the transition. False leaves the
  /// bar in the tab layout's page. The tabs of a [chrome] are always the
  /// host's.
  final bool hostsTabBar;

  /// Replaces the platform's fold readings (the reserved regions) and the
  /// iOS 26 check, so the chrome can be exercised in widget tests anywhere.
  @visibleForTesting
  final FoldableData? debugFold;

  /// Replaces the system's vertical bar edge in widget tests, where the
  /// platform channel it comes from does not exist.
  @visibleForTesting
  final SystemVerticalBarEdge? debugVerticalBarEdge;

  @override
  State<AdaptiveToolbarHost> createState() => _AdaptiveToolbarHostState();
}

class _AdaptiveToolbarHostState extends State<AdaptiveToolbarHost>
    with TickerProviderStateMixin {
  final ToolbarRegistry _registry = ToolbarRegistry();
  late final ToolbarBlend _blend;

  /// The bars read the content underneath once, together.
  final BackdropKey _chromeBackdrop = BackdropKey();

  /// The height of the hosted tab bar, once measured.
  final ValueNotifier<double> _tabBarHeight = ValueNotifier<double>(0);

  /// The room a tab accessory floating at the bottom of the content takes.
  final ValueNotifier<double> _accessoryHeight = ValueNotifier<double>(0);

  /// The sidebar of custom chrome on a wide window: 0 collapsed to a rail,
  /// 1 at its full width.
  late final AnimationController _sidebar = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 250),
  )..addListener(_updateSidebarInset);

  /// Whether the user switched the sidebar from the width the window gives
  /// it by default.
  bool _sidebarToggled = false;

  /// Whether the window is wide enough for the full sidebar by default.
  bool? _sidebarWide;
  bool _hasSidebar = false;

  /// The room the sidebar takes beside the pages of the tab layout.
  final ValueNotifier<double> _sidebarInset = ValueNotifier<double>(0);

  bool get _sidebarExpanded => (_sidebarWide ?? false) != _sidebarToggled;

  /// Expanded over the content of a window too narrow to keep it beside it.
  bool get _sidebarOverlaid => !(_sidebarWide ?? false) && _sidebarToggled;

  void _updateSidebarInset() {
    final metrics = widget.chrome?.metrics;
    if (!_hasSidebar || metrics == null) {
      _sidebarInset.value = 0;
      return;
    }
    final collapsed = metrics.sidebarCollapsedWidth;
    _sidebarInset.value = _sidebarOverlaid
        ? collapsed
        : collapsed + (metrics.sidebarWidth - collapsed) * _sidebar.value;
  }

  void _toggleSidebar() {
    setState(() => _sidebarToggled = !_sidebarToggled);
    _updateSidebarInset();
    _sidebar.animateTo(_sidebarExpanded ? 1 : 0, curve: Curves.easeInOutCubic);
  }

  void _collapseOverlaidSidebar() {
    if (_sidebarOverlaid) _toggleSidebar();
  }

  /// Latest fold / size-class reading; null until the first one arrives and
  /// on platforms where the chrome is never drawn.
  FoldableData? _fold;
  StreamSubscription<FoldableData>? _foldSub;

  /// The system's vertical bar edge; null wherever the chrome is never drawn
  /// and in tests, where no platform channel answers.
  ValueListenable<SystemVerticalBarEdge>? _edge;

  /// What the debug log last reported, to print only the changes.
  SystemVerticalBarEdge _loggedEdge = SystemVerticalBarEdge.unknown;
  DuoPose? _loggedPose;
  DuoTopStrip? _loggedStrip;

  @override
  void initState() {
    super.initState();
    _blend = ToolbarBlend(registry: _registry, vsync: this);
    // Whether windows have window controls to keep clear of (iPad).
    PlatformInfo.loadDevice().then((_) {
      if (mounted) setState(() {});
    });
    // Fold readings are only needed for the camera clearance of the bar, and
    // for pages that lay themselves out around the fold.
    if (widget.debugFold == null && PlatformInfo.isIOS26OrHigher()) {
      Foldable.snapshot.then(_onFoldChanged).catchError((Object _) {});
      _foldSub = Foldable.changes.listen(
        _onFoldChanged,
        onError: (Object _) {},
      );
      // The side the bar belongs on comes from the system, not from insets:
      // the leading Split View pane has none to read.
      _edge = SystemVerticalBar.edge..addListener(_onEdgeChanged);
    }
  }

  Size? _windowSize;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // A window that changes size may have moved to another display (the
    // iPhone Duo, folded or unfolded), with rounder corners or less round
    // ones.
    final size = MediaQuery.sizeOf(context);
    if (_windowSize != null && size != _windowSize) {
      PlatformInfo.loadDisplayCornerRadius();
    }
    _windowSize = size;
    // A window that changes width class starts from its own default width
    // of the sidebar, at once.
    final metrics = widget.chrome?.metrics;
    if (metrics != null) {
      final wide = size.width >= metrics.sidebarExpandedWindowWidth;
      if (wide != _sidebarWide) {
        _sidebarWide = wide;
        _sidebarToggled = false;
        _sidebar.value = wide ? 1 : 0;
      }
    }
  }

  void _onFoldChanged(FoldableData data) {
    if (!mounted) return;
    setState(() => _fold = data);
  }

  void _onEdgeChanged() {
    if (!mounted) return;
    setState(() {});
  }

  @override
  void dispose() {
    _edge?.removeListener(_onEdgeChanged);
    _foldSub?.cancel();
    _blend.dispose();
    _registry.dispose();
    _tabBarHeight.dispose();
    _accessoryHeight.dispose();
    _sidebar.dispose();
    _sidebarInset.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final fold = widget.debugFold ?? _fold;
    final chrome = widget.chrome;
    // The iPhone Duo's poses only exist on iOS 26 and later: an Android
    // window with a cutout on one side is no vertical bar pose.
    final resolvesDuo =
        widget.debugFold != null || PlatformInfo.isIOS26OrHigher();
    // The fixed chrome exists where pages use the native iOS 26 toolbar, and
    // everywhere for custom chrome; elsewhere pages keep their own Cupertino
    // / Material bars.
    final hostsToolbar = chrome != null || resolvesDuo;
    final edge =
        widget.debugVerticalBarEdge ??
        _edge?.value ??
        SystemVerticalBarEdge.unknown;
    // Resolved once: the bar, the title and the pages all read this decision.
    final pose = resolvesDuo
        ? DuoLayout.resolvePose(MediaQuery.viewPaddingOf(context), edge)
        : null;
    final strip = resolvesDuo && pose == null
        ? DuoTopStrip.resolve(
            viewPadding: MediaQuery.viewPaddingOf(context),
            size: MediaQuery.sizeOf(context),
            fold: fold,
          )
        : null;
    final placement = resolveChromePlacement(
      pose: pose,
      strip: strip,
      width: MediaQuery.sizeOf(context).width,
      chrome: chrome,
    );
    final sidebar = placement == AdaptiveChromePlacement.sidebar;
    // Tabs in a sidebar stay while pages are pushed inside the tab layout.
    _registry.keepsTabsOnPush = sidebar;
    if (sidebar != _hasSidebar) {
      _hasSidebar = sidebar;
      _updateSidebarInset();
    }
    assert(() {
      // Pose bugs only reproduce on a Duo; this makes a report actionable.
      if (edge != _loggedEdge || pose != _loggedPose || strip != _loggedStrip) {
        _loggedEdge = edge;
        _loggedPose = pose;
        _loggedStrip = strip;
        debugPrint(
          'AdaptiveToolbarHost: Duo pose ${pose ?? strip ?? 'none'} '
          '(edge: ${edge.name})',
        );
      }
      return true;
    }());

    // A window that is only part of the display (iPhone Duo split view, an
    // iPad window) can come without any room at the top: there is no status
    // bar above it. The bar and the pages then still keep clear of the
    // window's rounded top edge.
    final noRoomAtTop =
        hostsToolbar &&
        pose == null &&
        MediaQuery.viewPaddingOf(context).top == 0;
    // In the iPhone Duo vertical bar poses the tabs are in that bar.
    // Custom chrome keeps its tab layer in every placement: in the vertical
    // bar pose for the accessory, which floats beside the bar.
    final hostsTabBar = chrome != null
        ? true
        : widget.hostsTabBar && hostsToolbar && pose == null;

    return FoldScope(
      hinge: FoldScope.hingeFrom(fold),
      child: _WindowTopMargin(
        enabled: noRoomAtTop,
        child: RouteTransitionScope(
          routeTransition: _blend.routeTransition,
          child: ToolbarRegistryScope(
            registry: _registry,
            child: ToolbarChromeScope(
              hostsToolbar: hostsToolbar,
              hostsDuoControls: pose != null,
              // Custom tabs in the iPhone Duo's top strip take no room at
              // the bottom.
              hostsBottomTabBar:
                  hostsTabBar &&
                  (chrome == null ||
                      placement == AdaptiveChromePlacement.bottom),
              tabBarHeight: _tabBarHeight,
              child: DuoPoseScope(
                pose: pose,
                child: DuoTopStripScope(
                  strip: strip,
                  child: AdaptiveChromeScope(
                    chrome: chrome,
                    placement: placement,
                    sidebarInset: _sidebarInset,
                    floatingAccessoryHeight: _accessoryHeight,
                    child: AdaptiveGlassTheme(
                      style: chrome?.glass ?? const AdaptiveGlassStyle(),
                  // Toasts show above the bars.
                  child: AdaptiveToastLayer(
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        // Always the first child at a stable position, so
                        // toggling the chrome never rebuilds the navigator from
                        // scratch. The MediaQuery in it is always here too, even
                        // when it changes nothing: adding it only in some poses
                        // would move the navigator in the element tree whenever
                        // the pose changes (moving between Split View panes),
                        // and rebuild every route.
                        _BarInset(pose: pose, child: widget.child),
                        if (hostsToolbar)
                          BackdropGroup(
                            backdropKey: _chromeBackdrop,
                            child: _ChromeMaterial(
                              custom: chrome != null,
                              child: HostedTopToolbar(
                                blend: _blend,
                                titleOnly: pose != null,
                                chrome: chrome,
                                placement: placement,
                                sidebarInset: _sidebarInset,
                              ),
                            ),
                          ),
                        // A sidebar expanded over the content closes with a
                        // tap outside it.
                        if (sidebar)
                          Positioned.fill(
                            key: const ValueKey<String>('adaptive_sidebar_scrim'),
                            child: IgnorePointer(
                              ignoring: !_sidebarOverlaid,
                              child: GestureDetector(
                                behavior: HitTestBehavior.opaque,
                                onTap: _collapseOverlaidSidebar,
                                child: FadeTransition(
                                  opacity: _sidebarOverlaid
                                      ? _sidebar
                                      : kAlwaysDismissedAnimation,
                                  child: const ColoredBox(
                                    color: Color(0x33000000),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        if (hostsTabBar)
                          BackdropGroup(
                            key: const ValueKey<String>('adaptive_tab_bar'),
                            backdropKey: _chromeBackdrop,
                            child: _ChromeMaterial(
                              custom: chrome != null,
                              child: HostedTabBar(
                                blend: _blend,
                                height: _tabBarHeight,
                                chrome: chrome,
                                placement: placement,
                                accessoryHeight: _accessoryHeight,
                                sidebar: sidebar
                                    ? HostedSidebar(
                                        progress: _sidebar,
                                        expanded: _sidebarExpanded,
                                        overlaid: _sidebarOverlaid,
                                        onToggle: _toggleSidebar,
                                        onTabTapped: _collapseOverlaidSidebar,
                                      )
                                    : null,
                              ),
                            ),
                          ),
                        if (pose != null)
                          // The bar sits on whichever edge the pose names: the
                          // right in most poses, the left in the leading Split
                          // View pane.
                          Positioned(
                            key: const ValueKey<String>('adaptive_duo_bar'),
                            top: 0,
                            bottom: 0,
                            left: pose.onLeft ? 0 : null,
                            right: pose.onLeft ? null : 0,
                            width: pose.bandWidth,
                            child: BackdropGroup(
                              backdropKey: _chromeBackdrop,
                              child: _ChromeMaterial(
                                custom: chrome != null,
                                child: HostedDuoBar(
                                  blend: _blend,
                                  chrome: chrome,
                                  regions:
                                      fold?.regions ?? const <ReservedRegion>[],
                                ),
                              ),
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
        ),
      ),
    );
  }
}

/// The app's own bars sit above the navigator, outside any page: give them
/// what a page gives its content, a Material for ink and text styles.
/// Native chrome is left as it is.
class _ChromeMaterial extends StatelessWidget {
  const _ChromeMaterial({required this.custom, required this.child});

  final bool custom;
  final Widget child;

  @override
  Widget build(BuildContext context) => custom
      ? Material(type: MaterialType.transparency, child: child)
      : child;
}

/// Room kept above the fixed toolbar in a window without any at its top.
const double kWindowTopMargin = 12.0;

/// Hands the pages the window's media query, with [kWindowTopMargin] at the
/// top when [enabled]. Always in the tree, so the navigator below keeps its
/// place when the window changes.
///
/// Only this follows every change of the media query, such as each frame of
/// the keyboard sliding in: the bars beside the navigator are built by the
/// host, which only reads what it needs.
class _WindowTopMargin extends StatelessWidget {
  const _WindowTopMargin({required this.enabled, required this.child});

  final bool enabled;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    return MediaQuery(
      data: enabled
          ? mediaQuery.copyWith(
              padding: mediaQuery.padding.copyWith(
                top: math.max(mediaQuery.padding.top, kWindowTopMargin),
              ),
              viewPadding: mediaQuery.viewPadding.copyWith(
                top: kWindowTopMargin,
              ),
            )
          : mediaQuery,
      child: child,
    );
  }
}

/// Gives the pages the inset the system would have added for a vertical bar
/// it does not draw: in the leading Split View pane the system wants a bar
/// there but reserves no strip for it, since UIKit only insets for bars it
/// draws itself. Add that inset here, as UIKit does for a native app, so a
/// page's SafeArea and the scaffold's body inset keep clear of the bar.
///
/// Always builds a [MediaQuery], with the data unchanged when there is nothing
/// to add, and is a widget of its own so the host does not depend on the whole
/// [MediaQueryData] (every keyboard frame would rebuild the chrome).
class _BarInset extends StatelessWidget {
  const _BarInset({required this.pose, required this.child});

  final DuoPose? pose;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final pose = this.pose;
    return MediaQuery(
      data: pose == null || pose.reservedBySystem
          ? mq
          : mq.copyWith(
              padding: pose.addStrip(mq.padding),
              viewPadding: pose.addStrip(mq.viewPadding),
            ),
      child: child,
    );
  }
}
