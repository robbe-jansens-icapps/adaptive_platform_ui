import 'package:flutter/widgets.dart';

/// How much of what is behind it the native bars' Liquid Glass shows, as
/// measured on iOS 26.
const double kGlassShowsThrough = 0.4;

/// What the barrier of [route], a dialog or a sheet over the page, lays over
/// chrome that sits above the navigator, out of the barrier's reach, for the
/// chrome to look dimmed with the page: the barrier's colour as it comes and
/// goes, or null where [route] has no barrier to show.
///
/// [showsThrough] is how much of what is behind it the chrome shows, as glass
/// or a frost does: that is under the barrier already, so a barrier as strong
/// as the page's would leave the chrome darker than the page around it. It is
/// laid on lighter by as much, so the chrome ends up as dim.
Animation<Color?>? chromeBarrierOf(
  Route<Object?>? route, {
  double showsThrough = 0,
}) {
  if (route is! ModalRoute<Object?>) return null;
  final color = route.barrierColor;
  final animation = route.animation;
  if (color == null || color.a == 0 || animation == null) return null;
  final alpha = 1 - (1 - color.a) / (1 - showsThrough * color.a);
  return animation.drive(
    ColorTween(
      begin: color.withValues(alpha: 0),
      end: color.withValues(alpha: alpha),
    ).chain(CurveTween(curve: route.barrierCurve)),
  );
}

/// [barrier] laid over a box in [shape], such as the glass of a native
/// button, which Flutter cannot dim itself.
class ChromeBarrierBox extends StatelessWidget {
  const ChromeBarrierBox({
    super.key,
    required this.barrier,
    this.shape = const RoundedRectangleBorder(),
  });

  final Animation<Color?> barrier;
  final ShapeBorder shape;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: barrier,
        builder: (context, _) => DecoratedBox(
          decoration: ShapeDecoration(
            color: barrier.value ?? const Color(0x00000000),
            shape: shape,
          ),
        ),
      ),
    );
  }
}

/// [child], drawn by Flutter, dimmed by [barrier] on its own pixels only, as
/// the barrier dims what lies under it: what shows through around it is
/// dimmed already.
class ChromeBarrierTint extends StatelessWidget {
  const ChromeBarrierTint({
    super.key,
    required this.barrier,
    required this.child,
  });

  final Animation<Color?>? barrier;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final barrier = this.barrier;
    if (barrier == null) return child;
    return AnimatedBuilder(
      animation: barrier,
      child: child,
      builder: (context, child) => ColorFiltered(
        colorFilter: ColorFilter.mode(
          barrier.value ?? const Color(0x00000000),
          BlendMode.srcATop,
        ),
        child: child,
      ),
    );
  }
}
