import 'package:flutter/widgets.dart';

/// Keeps the order of a navigator's routes, the ones on their way out too,
/// for native views shown over the Flutter view ([NativeChromeView]) to know
/// which pages are over theirs: those are above all Flutter content, so a
/// page sliding over theirs cuts them off at its edge, and they fade out as a
/// dialog or a sheet with a barrier comes up over theirs.
///
/// Add one to each navigator whose pages hold such views
/// ([AdaptiveNativeChrome.navigatorObserver] for the app's own). On pages of
/// a navigator without one, the views leave it to their Flutter stand-ins
/// while pages move or something covers them.
class NativeChromeNavigatorObserver extends NavigatorObserver {
  NativeChromeNavigatorObserver() {
    _all.add(this);
  }

  static final List<NativeChromeNavigatorObserver> _all = [];

  final List<Route<dynamic>> _routes = [];

  /// The routes over [route], nearest first; null where no observer keeps
  /// [route]'s navigator.
  static List<Route<dynamic>>? routesAbove(Route<dynamic> route) {
    for (final observer in _all) {
      final index = observer._routes.indexOf(route);
      if (index >= 0) return observer._routes.sublist(index + 1);
    }
    return null;
  }

  /// Whether an observer keeps the navigator [route] is on.
  static bool tracks(Route<dynamic>? route) =>
      route != null && routesAbove(route) != null;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _routes
      ..remove(route)
      ..add(route);
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    // It covers the page under it until it is all the way out.
    final animation = route is TransitionRoute ? route.animation : null;
    if (animation == null || animation.isDismissed) {
      _routes.remove(route);
      return;
    }
    void gone(AnimationStatus status) {
      if (!status.isDismissed) return;
      animation.removeStatusListener(gone);
      _routes.remove(route);
    }

    animation.addStatusListener(gone);
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _routes.remove(route);
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    final index = oldRoute == null ? -1 : _routes.indexOf(oldRoute);
    if (newRoute == null) {
      if (index >= 0) _routes.removeAt(index);
    } else if (index >= 0) {
      _routes[index] = newRoute;
    } else {
      _routes.add(newRoute);
    }
  }
}
