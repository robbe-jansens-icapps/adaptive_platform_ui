import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:foldable/foldable.dart';

import '../platform/platform_info.dart';
import '../widgets/adaptive_toast.dart';
import 'duo_vertical_bar.dart';
import 'fold_scope.dart';
import 'hosted_duo_bar.dart';
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
    @visibleForTesting this.debugFold,
  });

  /// The navigator (or whatever the app's `builder` receives).
  final Widget child;

  /// Replaces the platform's fold readings (the reserved regions) and the
  /// iOS 26 check, so the chrome can be exercised in widget tests anywhere.
  @visibleForTesting
  final FoldableData? debugFold;

  @override
  State<AdaptiveToolbarHost> createState() => _AdaptiveToolbarHostState();
}

class _AdaptiveToolbarHostState extends State<AdaptiveToolbarHost>
    with TickerProviderStateMixin {
  final ToolbarRegistry _registry = ToolbarRegistry();
  late final ToolbarBlend _blend;

  /// Latest fold / size-class reading; null until the first one arrives and
  /// on platforms where the chrome is never drawn.
  FoldableData? _fold;
  StreamSubscription<FoldableData>? _foldSub;

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

  @override
  void dispose() {
    _foldSub?.cancel();
    _blend.dispose();
    _registry.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final fold = widget.debugFold ?? _fold;
    // The fixed chrome only exists where pages use the native iOS 26
    // toolbar; elsewhere pages keep their own Cupertino / Material bars.
    final hostsToolbar =
        widget.debugFold != null || PlatformInfo.isIOS26OrHigher();
    final hostsDuoControls =
        hostsToolbar &&
        DuoLayout.isVerticalBarPose(MediaQuery.viewPaddingOf(context));

    final barOnLeft =
        DuoLayout.barSide(MediaQuery.viewPaddingOf(context)) == DuoBarSide.left;

    // A window that is only part of the display (iPhone Duo split view, an
    // iPad window) can come without any room at the top: there is no status
    // bar above it. The bar and the pages then still keep clear of the
    // window's rounded top edge.
    final noRoomAtTop =
        hostsToolbar &&
        !hostsDuoControls &&
        MediaQuery.viewPaddingOf(context).top == 0;

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
              hostsDuoControls: hostsDuoControls,
              // Toasts show above the bars.
              child: AdaptiveToastLayer(
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    // Always the first child at a stable position, so toggling the
                    // chrome never rebuilds the navigator from scratch.
                    widget.child,
                    if (hostsToolbar)
                      HostedTopToolbar(
                        blend: _blend,
                        titleOnly: hostsDuoControls,
                      ),
                    if (hostsDuoControls)
                      // The bar follows the hardware: the strip is on the right in
                      // most poses and on the left in one landscape rotation.
                      Positioned(
                        top: 0,
                        bottom: 0,
                        left: barOnLeft ? 0 : null,
                        right: barOnLeft ? null : 0,
                        width: DuoLayout.bandWidth(
                          MediaQuery.viewPaddingOf(context),
                        ),
                        child: HostedDuoBar(
                          blend: _blend,
                          regions: fold?.regions ?? const <ReservedRegion>[],
                        ),
                      ),
                  ],
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
