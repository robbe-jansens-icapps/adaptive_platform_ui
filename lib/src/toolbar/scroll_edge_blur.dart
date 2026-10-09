import 'dart:ui' show ImageFilter;

import 'package:flutter/cupertino.dart';

/// The scroll edge effect of the iOS 26 bars: content underneath blurs and
/// fades into [color], strongest at the top of the screen and gone [fade]
/// points below the bar, so the bar's title and controls stay legible.
///
/// The blur eases off in bands, each a plain blur in a plain rectangle: the
/// only backdrop filter that iOS also applies to native views underneath. A
/// blur under a mask would blur nothing there.
class ScrollEdgeBlur extends StatelessWidget {
  const ScrollEdgeBlur({
    super.key,
    required this.height,
    this.fade = 24,
    required this.color,
  });

  /// Where the bar ends, from the top of the screen.
  final double height;

  /// How far the effect runs on below the bar.
  final double fade;

  /// The background the content fades into.
  final Color color;

  @override
  Widget build(BuildContext context) {
    final total = height + fade;
    return IgnorePointer(
      child: SizedBox(
        height: total,
        child: Stack(
          fit: StackFit.expand,
          children: [
            _band(0, height - 16, sigma: 10),
            _band(height - 16, height, sigma: 6),
            _band(height, height + fade / 2, sigma: 3),
            _band(height + fade / 2, total, sigma: 1.2),
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  stops: [0, height * 0.6 / total, height / total, 1],
                  colors: [
                    color.withValues(alpha: 0.8),
                    color.withValues(alpha: 0.6),
                    color.withValues(alpha: 0.3),
                    color.withValues(alpha: 0),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  static Widget _band(double top, double bottom, {required double sigma}) {
    if (bottom <= top) return const SizedBox.shrink();
    return Positioned(
      top: top,
      height: bottom - top,
      left: 0,
      right: 0,
      child: ClipRect(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: sigma, sigmaY: sigma),
          child: const SizedBox.expand(),
        ),
      ),
    );
  }
}
