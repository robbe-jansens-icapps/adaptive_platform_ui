import 'package:adaptive_platform_ui/adaptive_platform_ui.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  List<double> sample(AdaptiveSpringCurve curve) => [
    for (var i = 0; i <= 100; i++) curve.transform(i / 100),
  ];

  test('a bouncy spring passes its end a little and settles there', () {
    final values = sample(AdaptiveSpringCurve.bouncy);
    expect(values.first, 0);
    expect(values.last, 1);
    final peak = values.reduce((a, b) => a > b ? a : b);
    expect(peak, greaterThan(1));
    expect(peak, lessThan(1.05));
    expect(values[99], closeTo(1, 0.005));
  });

  test('a smooth spring never passes its end, and only ever moves on', () {
    final values = sample(AdaptiveSpringCurve.smooth);
    for (var i = 1; i < values.length; i++) {
      expect(values[i], greaterThanOrEqualTo(values[i - 1]));
      expect(values[i], lessThanOrEqualTo(1));
    }
    expect(values[99], closeTo(1, 0.005));
  });

  test('it moves quickly at first, as a spring let go does', () {
    expect(AdaptiveSpringCurve.smooth.transform(0.25), greaterThan(0.5));
  });
}
