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
///
/// Outside a page's route, such as in the chrome above the navigator, a
/// [NativeViewSettleScope] says when the view holds still instead.
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

  /// What fades the view as a whole, from a [NativeViewSettleScope] around
  /// it: it holds still only while that is fully in.
  ValueListenable<bool>? _scope;

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
    _scope = NativeViewSettleScope.maybeOf(context);
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
        !(_routeTransition?.value ?? false) &&
        // Faded as a whole, as the tab accessory over the native tab bar is.
        (_scope?.value ?? true);
    if (settled == _settled && !_firstSettle) return;
    _firstSettle = false;
    _settled = settled;
    didChangeSettled(settled);
    if (rebuild && mounted) setState(() {});
  }
}

/// Holds the native views below it ([NativeViewSettle]: glass surfaces,
/// native buttons) off screen while [fade] is not fully in or still moves,
/// and while a scope around it does, their Flutter stand-ins taking their
/// place: a fade turns into an alpha on a native view, which breaks its
/// glass. For native views that something fades as a whole outside a page's
/// route, such as the tab accessory the toolbar host lays above the native
/// tab bar.
class NativeViewSettleScope extends StatefulWidget {
  const NativeViewSettleScope({
    super.key,
    required this.fade,
    required this.child,
  });

  /// The opacity of what holds the native views.
  final Animation<double> fade;

  final Widget child;

  /// Whether the native views at [context] may be on screen, by the scopes
  /// around it; null where there is none. [context] is built again when it
  /// changes.
  static ValueListenable<bool>? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_SettleScope>()?.notifier;

  @override
  State<NativeViewSettleScope> createState() => _NativeViewSettleScopeState();
}

class _NativeViewSettleScopeState extends State<NativeViewSettleScope> {
  final ValueNotifier<bool> _settled = ValueNotifier<bool>(true);

  /// The scope around this one.
  ValueListenable<bool>? _outer;

  @override
  void initState() {
    super.initState();
    _listen(widget.fade);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _outer = NativeViewSettleScope.maybeOf(context);
    _update();
  }

  @override
  void didUpdateWidget(NativeViewSettleScope oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.fade, widget.fade)) {
      _unlisten(oldWidget.fade);
      _listen(widget.fade);
      _update();
    }
  }

  @override
  void dispose() {
    _unlisten(widget.fade);
    _settled.dispose();
    super.dispose();
  }

  void _listen(Animation<double> fade) {
    fade
      ..addListener(_update)
      ..addStatusListener(_onStatus);
  }

  void _unlisten(Animation<double> fade) {
    fade
      ..removeListener(_update)
      ..removeStatusListener(_onStatus);
  }

  void _onStatus(AnimationStatus _) => _update();

  void _update() {
    final fade = widget.fade;
    _settled.value =
        (_outer?.value ?? true) && fade.value >= 1 && !fade.isAnimating;
  }

  @override
  Widget build(BuildContext context) =>
      _SettleScope(settled: _settled, child: widget.child);
}

class _SettleScope extends InheritedNotifier<ValueListenable<bool>> {
  const _SettleScope({
    required ValueListenable<bool> settled,
    required super.child,
  }) : super(notifier: settled);
}
