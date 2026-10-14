import 'dart:ui' show ColorFilter, ImageFilter;

import 'package:flutter/widgets.dart';

/// How [AdaptiveGlass] looks: frosted glass in an app's own colours, drawn by
/// Flutter, the same on every platform.
@immutable
class AdaptiveGlassStyle {
  const AdaptiveGlassStyle({
    this.tint = const Color(0xB8FFFFFF),
    this.blurSigma = 24,
    this.saturation = 1.4,
    this.rimColor = const Color(0x40FFFFFF),
    this.rimWidth = 1,
    this.shadows = const <BoxShadow>[
      BoxShadow(color: Color(0x1F000000), blurRadius: 24, offset: Offset(0, 8)),
    ],
    this.highContrastTint,
  });

  /// Laid over the blurred content. Its opacity decides how much of the
  /// content shows through: a dark brand colour at 85% reads as a solid bar
  /// that still hints at what scrolls underneath.
  final Color tint;

  /// How far the content underneath is blurred. 0 draws no blur at all, and
  /// costs nothing beyond the tint: for slow devices, or a [tint] that is
  /// opaque anyway.
  final double blurSigma;

  /// How much more vivid the blurred content gets, as Liquid Glass makes it:
  /// 1 leaves its colours as they are.
  final double saturation;

  /// The thin highlight along the edge that makes glass read as glass.
  final Color rimColor;
  final double rimWidth;

  /// Drawn under the glass, outside its shape.
  final List<BoxShadow> shadows;

  /// Replaces [tint] while the user asks for more contrast, with no content
  /// showing through. [tint] made opaque when null.
  final Color? highContrastTint;

  AdaptiveGlassStyle copyWith({
    Color? tint,
    double? blurSigma,
    double? saturation,
    Color? rimColor,
    double? rimWidth,
    List<BoxShadow>? shadows,
    Color? highContrastTint,
  }) => AdaptiveGlassStyle(
    tint: tint ?? this.tint,
    blurSigma: blurSigma ?? this.blurSigma,
    saturation: saturation ?? this.saturation,
    rimColor: rimColor ?? this.rimColor,
    rimWidth: rimWidth ?? this.rimWidth,
    shadows: shadows ?? this.shadows,
    highContrastTint: highContrastTint ?? this.highContrastTint,
  );

  @override
  bool operator ==(Object other) =>
      other is AdaptiveGlassStyle &&
      other.tint == tint &&
      other.blurSigma == blurSigma &&
      other.saturation == saturation &&
      other.rimColor == rimColor &&
      other.rimWidth == rimWidth &&
      _listEquals(other.shadows, shadows) &&
      other.highContrastTint == highContrastTint;

  @override
  int get hashCode => Object.hash(tint, blurSigma, saturation, rimColor, rimWidth, Object.hashAll(shadows), highContrastTint);

  static bool _listEquals(List<BoxShadow> a, List<BoxShadow> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

/// Hands an [AdaptiveGlassStyle] to the [AdaptiveGlass] surfaces below that
/// bring none of their own. The toolbar host installs the one of its custom
/// chrome.
class AdaptiveGlassTheme extends InheritedWidget {
  const AdaptiveGlassTheme({super.key, required this.style, required super.child});

  final AdaptiveGlassStyle style;

  /// The nearest style, or the default one.
  static AdaptiveGlassStyle of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AdaptiveGlassTheme>()?.style ?? const AdaptiveGlassStyle();

  @override
  bool updateShouldNotify(AdaptiveGlassTheme oldWidget) => style != oldWidget.style;
}

/// Frosted glass drawn by Flutter: the content underneath blurred and made
/// more vivid, under a tint and a thin rim, in [shape].
///
/// Unlike `IOS26GlassSurface`, which is the system's own Liquid Glass on
/// iOS, it looks the same on every platform and takes any colour, for an app
/// whose brand decides how its bars look. Several of them inside one
/// [BackdropGroup] share one read of the content underneath, which the
/// toolbar host's custom chrome sets up for its bars.
class AdaptiveGlass extends StatelessWidget {
  const AdaptiveGlass({super.key, this.style, this.shape = const StadiumBorder(), this.child});

  /// The look; the nearest [AdaptiveGlassTheme]'s when null.
  final AdaptiveGlassStyle? style;

  /// The outline, which clips the blur and the [child]. A capsule by default.
  final ShapeBorder shape;

  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final style = this.style ?? AdaptiveGlassTheme.of(context);
    final highContrast = MediaQuery.highContrastOf(context);
    final tint = highContrast ? (style.highContrastTint ?? style.tint.withValues(alpha: 1)) : style.tint;
    final rim = style.rimWidth > 0 && style.rimColor.a > 0 ? BorderSide(color: style.rimColor, width: style.rimWidth) : BorderSide.none;
    Widget glass = DecoratedBox(
      decoration: ShapeDecoration(color: tint, shape: _withSide(shape, rim)),
      child: child,
    );
    if (style.blurSigma > 0 && tint.a < 1) {
      glass = BackdropFilter.grouped(
        filter: ImageFilter.compose(
          outer: ColorFilter.matrix(_saturationMatrix(style.saturation)),
          inner: ImageFilter.blur(sigmaX: style.blurSigma, sigmaY: style.blurSigma, tileMode: TileMode.mirror),
        ),
        child: glass,
      );
    }
    glass = ClipPath(
      clipper: ShapeBorderClipper(shape: shape, textDirection: Directionality.maybeOf(context)),
      child: glass,
    );
    if (style.shadows.isEmpty) return glass;
    return DecoratedBox(
      decoration: ShapeDecoration(shape: shape, shadows: style.shadows),
      child: glass,
    );
  }

  static ShapeBorder _withSide(ShapeBorder shape, BorderSide side) => switch (shape) {
    OutlinedBorder() => shape.copyWith(side: side),
    _ => shape,
  };

  /// The standard luminance-preserving saturation matrix.
  static List<double> _saturationMatrix(double s) {
    const r = 0.2126, g = 0.7152, b = 0.0722;
    final i = 1 - s;
    return <double>[
      r * i + s, g * i, b * i, 0, 0, //
      r * i, g * i + s, b * i, 0, 0, //
      r * i, g * i, b * i + s, 0, 0, //
      0, 0, 0, 1, 0, //
    ];
  }
}
