import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

import '../../toolbar/toolbar_blend.dart';

/// Follows whether the page a native view is on holds still in front
/// ([settled]), for the view to be on screen only then.
///
/// A native view keeps showing above Flutter content that moves over it, so a
/// page sliding over its page would let it show through. And iOS composites
/// what Flutter draws after a native view against that view: with one left on
/// screen under a dialog, the dialog's barrier and a page pushed over it only
/// showed within the clip around that view (a sheet's rounded shape), and the
/// rest of the screen stayed as it was. In between, a Flutter stand-in takes
/// its place.
///
/// Call [followRoute] from `didChangeDependencies`, and react to changes in
/// [didChangeSettled].
mixin NativeViewSettle<T extends StatefulWidget> on State<T> {
  /// The animations of the page the view is on: its own (coming and going)
  /// and the one of the page over it (being covered and uncovered).
  Animation<double>? _animation;
  Animation<double>? _secondaryAnimation;
  ModalRoute<Object?>? _route;

  /// Whether pages are being pushed, popped or dragged back (from the
  /// `AdaptiveToolbarHost`): a page that comes in or leaves as a full-screen
  /// dialog does not move the one below it, so its animations say nothing.
  ValueListenable<bool>? _routeTransition;

  bool _settled = true;
  bool _firstSettle = true;

  /// Whether the native view may be on screen: its page holds still in front,
  /// with nothing over it. Always true outside a route.
  bool get settled => _settled;

  /// [settled] changed to [settled], or was found for the first time. A
  /// build follows when [followRoute] asked for one.
  @protected
  void didChangeSettled(bool settled);

  /// Looks at the page the view is on again: from `didChangeDependencies`,
  /// as the route's status (`isCurrent`) is a dependency.
  @protected
  void followRoute() {
    final route = ModalRoute.of(context);
    _route = route;
    final transition = route == null
        ? null
        : RouteTransitionScope.maybeOf(context);
    if (!identical(transition, _routeTransition)) {
      _routeTransition?.removeListener(_onRouteTransition);
      _routeTransition = transition?..addListener(_onRouteTransition);
    }
    _listenTo(route?.animation, route?.secondaryAnimation);
    // A build follows.
    _updateSettled(rebuild: false);
  }

  @override
  void dispose() {
    _routeTransition?.removeListener(_onRouteTransition);
    _listenTo(null, null);
    super.dispose();
  }

  void _listenTo(Animation<double>? animation, Animation<double>? secondary) {
    if (identical(animation, _animation) &&
        identical(secondary, _secondaryAnimation)) {
      return;
    }
    _animation?.removeStatusListener(_onRouteStatus);
    _secondaryAnimation?.removeStatusListener(_onRouteStatus);
    _animation = animation?..addStatusListener(_onRouteStatus);
    _secondaryAnimation = secondary?..addStatusListener(_onRouteStatus);
  }

  void _onRouteStatus(AnimationStatus _) => _updateSettled();

  // May come in the middle of a build (a page registering with the toolbar):
  // looked at once it is done.
  void _onRouteTransition() {
    if (SchedulerBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      SchedulerBinding.instance.addPostFrameCallback((_) {
        if (mounted) _updateSettled();
      });
    } else {
      _updateSettled();
    }
  }

  void _updateSettled({bool rebuild = true}) {
    final animation = _animation;
    final secondary = _secondaryAnimation;
    final route = _route;
    final settled =
        (animation == null || animation.status == AnimationStatus.completed) &&
        (secondary == null || secondary.status == AnimationStatus.dismissed) &&
        // Under a dialog, a sheet or a page that slides up over it.
        (route == null || route.isCurrent) &&
        // A page that has just been pushed spends its first frame off stage,
        // its animation still reporting the end it starts from.
        (route == null || !route.offstage) &&
        !(_routeTransition?.value ?? false);
    if (settled == _settled && !_firstSettle) return;
    _firstSettle = false;
    _settled = settled;
    didChangeSettled(settled);
    if (rebuild && mounted) setState(() {});
  }
}
