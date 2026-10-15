import 'dart:math' as math;

import 'package:flutter/animation.dart';

/// A curve that moves as a spring does, the way the system animates sheets,
/// popovers and menus coming in, rather than along a fixed easing.
///
/// [response] is how long one swing of the spring takes, so how quick it
/// feels; [dampingRatio] 1 settles without passing its end, a little lower
/// passes it slightly and settles back. The animation it drives should last
/// [duration], long enough for the spring to settle: the curve maps that
/// animation's progress onto the spring over that time.
class AdaptiveSpringCurve extends Curve {
  const AdaptiveSpringCurve({
    this.response = 0.4,
    this.dampingRatio = 0.85,
    this.duration = const Duration(milliseconds: 600),
  }) : assert(response > 0),
       assert(dampingRatio > 0);

  /// Comes in with a slight overshoot, as a popover or a menu does.
  static const AdaptiveSpringCurve bouncy = AdaptiveSpringCurve(
    response: 0.42,
    dampingRatio: 0.78,
    duration: Duration(milliseconds: 620),
  );

  /// Settles without overshoot, as a sheet does.
  static const AdaptiveSpringCurve smooth = AdaptiveSpringCurve(
    response: 0.45,
    dampingRatio: 1,
    duration: Duration(milliseconds: 650),
  );

  /// Quick and without overshoot, for something going away.
  static const AdaptiveSpringCurve snappy = AdaptiveSpringCurve(
    response: 0.3,
    dampingRatio: 1,
    duration: Duration(milliseconds: 380),
  );

  final double response;
  final double dampingRatio;
  final Duration duration;

  @override
  double transformInternal(double t) {
    final time = t * duration.inMicroseconds / Duration.microsecondsPerSecond;
    final omega = 2 * math.pi / response;
    final zeta = dampingRatio;
    if (zeta < 1) {
      final damped = omega * math.sqrt(1 - zeta * zeta);
      return 1 -
          math.exp(-zeta * omega * time) *
              (math.cos(damped * time) +
                  zeta * omega / damped * math.sin(damped * time));
    }
    return 1 - math.exp(-omega * time) * (1 + omega * time);
  }

  @override
  String toString() =>
      'AdaptiveSpringCurve(response: $response, dampingRatio: $dampingRatio)';
}
