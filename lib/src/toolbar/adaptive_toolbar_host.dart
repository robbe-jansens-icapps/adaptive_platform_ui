import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:foldable/foldable.dart';

import '../platform/platform_info.dart';
import '../platform/system_vertical_bar.dart';
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
class AdaptiveToolbarHost extends StatefulWidget {
  const AdaptiveToolbarHost({
    super.key,
    required this.child,
    this.hostsTabBar = true,
    @visibleForTesting this.debugFold,
    @visibleForTesting this.debugVerticalBarEdge,
  });

  /// The navigator (or whatever the app's `builder` receives).
  final Widget child;

  /// Whether the host draws the native tab bar of a tab layout at the bottom
  /// of the screen, above the navigator, on iOS 26+ (outside the iPhone Duo
  /// vertical bar, which holds the tabs anyway). It then stays put while
  /// pages are pushed over the tabs and popped, fading out and in with them,
  /// instead of sliding with the tabs page under the page that comes in,
  /// which costs frames on every step of the transition. False leaves the
  /// bar in the tab layout's page.
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

  /// The height of the hosted tab bar, once measured.
  final ValueNotifier<double> _tabBarHeight = ValueNotifier<double>(0);

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
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final fold = widget.debugFold ?? _fold;
    // The fixed chrome only exists where pages use the native iOS 26
    // toolbar; elsewhere pages keep their own Cupertino / Material bars.
    final hostsToolbar =
        widget.debugFold != null || PlatformInfo.isIOS26OrHigher();
    final edge =
        widget.debugVerticalBarEdge ??
        _edge?.value ??
        SystemVerticalBarEdge.unknown;
    // Resolved once: the bar, the title and the pages all read this decision.
    final pose = hostsToolbar
        ? DuoLayout.resolvePose(MediaQuery.viewPaddingOf(context), edge)
        : null;
    final strip = hostsToolbar && pose == null
        ? DuoTopStrip.resolve(
            viewPadding: MediaQuery.viewPaddingOf(context),
            size: MediaQuery.sizeOf(context),
            fold: fold,
          )
        : null;
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
    final hostsTabBar = widget.hostsTabBar && hostsToolbar && pose == null;

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
              hostsBottomTabBar: hostsTabBar,
              tabBarHeight: _tabBarHeight,
              child: DuoPoseScope(
                pose: pose,
                child: DuoTopStripScope(
                  strip: strip,
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
                          HostedTopToolbar(
                            blend: _blend,
                            titleOnly: pose != null,
                          ),
                        if (hostsTabBar)
                          HostedTabBar(
                            key: const ValueKey<String>('adaptive_tab_bar'),
                            blend: _blend,
                            height: _tabBarHeight,
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
                            child: HostedDuoBar(
                              blend: _blend,
                              regions:
                                  fold?.regions ?? const <ReservedRegion>[],
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
