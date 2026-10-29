import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../../platform/platform_info.dart';
import 'native_chrome/adaptive_native_chrome.dart';
import 'native_chrome/adaptive_native_view.dart';
import 'native_chrome/native_snapshot.dart';
import 'native_view_settle.dart';

/// How the corners of an [IOS26GlassSurface] are rounded.
enum GlassSurfaceCorners {
  /// [IOS26GlassSurface.cornerRadius] on every corner.
  fixed,

  /// Concentric with the corners of the display, never below
  /// [IOS26GlassSurface.cornerRadius]: the shape iOS 26 gives sheets and
  /// panels that float close to the edges of the screen.
  concentric,

  /// Fully rounded ends.
  capsule,
}

/// A native Liquid Glass surface (`UIGlassEffect`) with Flutter content on
/// top: [child] is laid out over the glass.
///
/// The glass rounds its own corners. A Flutter clip or opacity around a
/// platform view turns into a mask or an alpha on it, and either one breaks
/// the glass, so never wrap this widget in a clip, an `Opacity` or a fade;
/// move it with transforms instead. The glass never takes touches: they all
/// go to [child].
///
/// Where there is no UIKit (other platforms, widget tests), a frosted blur
/// stands in for the glass.
class IOS26GlassSurface extends StatefulWidget {
  const IOS26GlassSurface({
    super.key,
    this.cornerRadius = 0,
    this.corners = GlassSurfaceCorners.fixed,
    this.tint,
    this.fill,
    this.clear = false,
    this.interactive = false,
    this.clipBehavior = Clip.none,
    this.chrome = false,
    this.child,
  });

  final double cornerRadius;
  final GlassSurfaceCorners corners;

  /// Tints the glass, like `UIGlassEffect.tintColor`. The glass stays as see
  /// through: even an opaque tint lets what is behind it show.
  final Color? tint;

  /// Laid over the glass, in its shape, under [child]. A partly opaque one
  /// lets less of what is behind the glass show through, so content on it
  /// reads better over a busy page, while the glass keeps its edge and blur.
  final Color? fill;

  /// The clear glass style, for surfaces over rich content such as photos.
  final bool clear;

  /// Lets the glass respond to touches with the system's highlight. The
  /// touches still go to [child].
  final bool interactive;

  /// Clips [child] to the glass's shape, concentric corners included, so
  /// content that runs on to an edge, such as a list scrolled to the bottom
  /// of a sheet, is cut off where the glass ends. Only [child] is clipped: a
  /// clip around the glass would break it.
  final Clip clipBehavior;

  /// With [AdaptiveNativeChrome.enabled], iOS draws the glass over the
  /// Flutter view rather than as a platform view, and [child] on it, from an
  /// image Flutter takes of it after each frame it changed in. Flutter still
  /// lays [child] out, out of sight, and it takes the touches. For content
  /// that seldom changes, like a toast's message: a change shows a frame or
  /// two late, and content that keeps moving (a list scrolling, a spinner)
  /// would be taken as an image every frame.
  final bool chrome;

  final Widget? child;

  /// Takes the native path (or not) whatever the platform, for tests.
  @visibleForTesting
  static bool? debugHasUIKitOverride;

  /// The radius of [GlassSurfaceCorners.concentric] corners [inset] from the
  /// display's edges, like the bottom ones of a sheet floating [inset] above
  /// the bottom: the display's radius less [inset], never below [minimum]
  /// (the surface's [cornerRadius]). Content near such corners needs more
  /// room from them the rounder they are.
  static double concentricRadius({
    required double inset,
    required double minimum,
  }) => math.max(minimum, PlatformInfo.displayCornerRadius - inset);

  @override
  State<IOS26GlassSurface> createState() => _IOS26GlassSurfaceState();
}

class _IOS26GlassSurfaceState extends State<IOS26GlassSurface>
    with SingleTickerProviderStateMixin, NativeViewSettle<IOS26GlassSurface> {
  MethodChannel? _channel;
  Map<String, Object>? _sent;

  static bool get _hasUIKit =>
      IOS26GlassSurface.debugHasUIKitOverride ?? (!kIsWeb && Platform.isIOS);

  // The native glass is on screen only while its page holds still in front
  // ([settled]); creating native views as a page comes in costs frames too.

  /// Whether the native view exists. Once it does it stays, off stage while
  /// the page is not settled, so it is never created twice.
  bool _created = false;

  /// Whether the native view has had a frame to show itself, so the stand-in
  /// can make way without a gap.
  bool _nativeShown = false;

  /// The stand-in's opacity: it fades out over the glass once the glass is
  /// back, rather than leaving it at once.
  late final AnimationController _standIn;

  bool get _chrome =>
      _hasUIKit && widget.chrome && AdaptiveNativeChrome.enabled;

  /// The last image taken of the child, for the glass over the Flutter view.
  (Uint8List, double)? _contentImage;

  /// Whether the glass over the Flutter view has had an image of the child.
  bool _contentSent = false;

  // Gone once faded out.
  void _onStandInStatus(AnimationStatus status) {
    if (status == AnimationStatus.dismissed && mounted) setState(() {});
  }

  Map<String, Object> get _params => <String, Object>{
    'isDark': MediaQuery.maybePlatformBrightnessOf(context) == Brightness.dark,
    'cornerRadius': widget.cornerRadius,
    'corners': widget.corners.name,
    'style': widget.clear ? 'clear' : 'regular',
    'interactive': widget.interactive,
    if (widget.tint != null) 'tint': widget.tint!.toARGB32(),
    if (widget.fill != null) 'fill': widget.fill!.toARGB32(),
  };

  @override
  void initState() {
    super.initState();
    _standIn = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 180),
      value: 1,
    )..addStatusListener(_onStandInStatus);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    followRoute();
    _sync();
  }

  @override
  void didUpdateWidget(IOS26GlassSurface oldWidget) {
    super.didUpdateWidget(oldWidget);
    _sync();
  }

  @override
  void dispose() {
    _standIn.dispose();
    _channel?.setMethodCallHandler(null);
    super.dispose();
  }

  @override
  bool get followsRouteOverFlutter => _chrome && routeIsFollowed;

  @override
  void didChangeSettled(bool settled) {
    if (_chrome) {
      setState(() {});
      return;
    }
    if (settled) {
      _created = true;
      // An existing view shows in the next frame; a new one once created.
      if (_channel != null) _showNative();
    } else {
      _nativeShown = false;
      _standIn.value = 1;
    }
  }

  /// The native glass is on screen again: the stand-in fades out over it.
  void _showNative() {
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !settled) return;
      setState(() => _nativeShown = true);
      if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) {
        _standIn.value = 0;
      } else {
        _standIn.reverse(from: 1);
      }
    });
  }

  void _onCreated(int id) {
    _channel = MethodChannel('adaptive_platform_ui/ios26_glass_surface_$id');
    _sync();
    if (_chrome) {
      _sendContent();
    } else if (settled) {
      _showNative();
    }
  }

  void _onContentImage(Uint8List bytes, double scale) {
    _contentImage = (bytes, scale);
    _sendContent();
  }

  void _sendContent() {
    final channel = _channel;
    final image = _contentImage;
    if (channel == null || image == null || !mounted) return;
    channel.invokeMethod<void>('setContent', {
      'bytes': image.$1,
      'scale': image.$2,
    });
    if (!_contentSent) setState(() => _contentSent = true);
  }

  void _sync() {
    final channel = _channel;
    if (channel == null) return;
    final params = _params;
    if (mapEquals(params, _sent)) return;
    _sent = params;
    channel.invokeMethod<void>('update', params);
  }

  Widget? get _content {
    final child = widget.child;
    if (child == null) return null;
    return _ShapeClip(
      corners: widget.corners,
      cornerRadius: widget.cornerRadius,
      window: widget.corners == GlassSurfaceCorners.concentric
          ? MediaQuery.sizeOf(context)
          : Size.zero,
      clipBehavior: widget.clipBehavior,
      child: child,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!_hasUIKit) {
      return Stack(
        alignment: Alignment.center,
        fit: StackFit.passthrough,
        children: [
          Positioned.fill(child: _Frosted(widget: widget)),
          ?_content,
        ],
      );
    }
    if (_chrome) return _buildChrome();
    final showsStandIn = !settled || !_nativeShown || _standIn.isAnimating;
    return Stack(
      alignment: Alignment.center,
      fit: StackFit.passthrough,
      children: [
        if (_created || settled)
          Positioned.fill(
            child: Offstage(
              offstage: !settled,
              child: IgnorePointer(
                child: UiKitView(
                  viewType: 'adaptive_platform_ui/ios26_glass_surface',
                  // What the view is created with; later changes go through
                  // `update`.
                  creationParams: _sent ??= _params,
                  creationParamsCodec: const StandardMessageCodec(),
                  onPlatformViewCreated: _onCreated,
                ),
              ),
            ),
          ),
        if (showsStandIn)
          Positioned.fill(
            child: FadeTransition(
              opacity: _standIn,
              child: _StandIn(widget: widget),
            ),
          ),
        ?_content,
      ],
    );
  }

  Widget _buildChrome() {
    final content = _content;
    final shown = settled && (content == null || _contentSent);
    return Stack(
      alignment: Alignment.center,
      fit: StackFit.passthrough,
      children: [
        Positioned.fill(
          // Painted once iOS has the image of the child: until then, and
          // while something covers it, the stand-in and the child take its
          // place.
          child: Opacity(
            opacity: shown ? 1 : 0,
            child: IgnorePointer(
              child: AdaptiveNativeView(
                viewType: 'adaptive_platform_ui/ios26_glass_surface',
                chrome: true,
                interactive: false,
                creationParams: _sent ??= _params,
                onPlatformViewCreated: _onCreated,
              ),
            ),
          ),
        ),
        if (!shown) Positioned.fill(child: _StandIn(widget: widget)),
        if (content != null)
          NativeOutOfSight(
            visible: !shown,
            child: NativeSnapshot(
              enabled: true,
              onImage: _onContentImage,
              child: content,
            ),
          ),
      ],
    );
  }
}

/// What shows for glass while its page moves: a light, translucent fill in
/// the glass's [tint] (and [fill]) with corners of [borderRadius], cheap to
/// draw on every frame of a transition.
ShapeDecoration glassStandInDecoration(
  BuildContext context, {
  required BorderRadius borderRadius,
  Color? tint,
  Color? fill,
}) {
  final dark = MediaQuery.maybePlatformBrightnessOf(context) == Brightness.dark;
  final base = dark ? const Color(0xE6303034) : const Color(0xE6FAFAFC);
  // A tint is what the glass mostly shows; a light one lets it through.
  final tinted = tint == null
      ? base
      : Color.alphaBlend(
          tint.withValues(alpha: tint.a < 0.5 ? tint.a : 0.92),
          base,
        );
  return ShapeDecoration(
    color: fill == null ? tinted : Color.alphaBlend(fill, tinted),
    shape: RoundedSuperellipseBorder(
      borderRadius: borderRadius,
      side: BorderSide(
        color: const Color(0xFFFFFFFF).withValues(alpha: 0.6),
        width: 0.5,
      ),
    ),
    shadows: const [
      BoxShadow(color: Color(0x14000000), blurRadius: 12, offset: Offset(0, 2)),
    ],
  );
}

/// What shows for the glass while its page moves ([glassStandInDecoration]),
/// in its shape.
class _StandIn extends StatelessWidget {
  const _StandIn({required this.widget});

  final IOS26GlassSurface widget;

  @override
  Widget build(BuildContext context) {
    ShapeDecoration decorationFor(BorderRadius radius) =>
        glassStandInDecoration(
          context,
          tint: widget.tint,
          fill: widget.fill,
          borderRadius: radius,
        );
    // In the glass's shape where it is on the screen, as the glass's own
    // corners follow the display's: they would change as the stand-in makes
    // way for it otherwise, the tray's and a sheet's along the bottom.
    if (widget.corners == GlassSurfaceCorners.concentric) {
      return _ConcentricShape(
        window: MediaQuery.sizeOf(context),
        minimum: widget.cornerRadius,
        decorationFor: decorationFor,
      );
    }
    return LayoutBuilder(
      builder: (context, constraints) => DecoratedBox(
        decoration: decorationFor(
          BorderRadius.circular(
            widget.corners == GlassSurfaceCorners.capsule
                ? constraints.biggest.shortestSide / 2
                : widget.cornerRadius,
          ),
        ),
      ),
    );
  }
}

/// The corners concentric with the display's ([GlassSurfaceCorners.concentric])
/// of a box at [rect] in a [window] that size: each one the display's radius
/// less how far the corner is from the display's edges, never below
/// [minimum], as UIKit rounds container-concentric corners.
@visibleForTesting
BorderRadius concentricCornersAt(
  Rect rect, {
  required Size window,
  required double minimum,
}) {
  final display = PlatformInfo.displayCornerRadius;
  Radius at(double fromSide, double fromEnd) =>
      Radius.circular(math.max(minimum, display - math.max(fromSide, fromEnd)));
  final right = window.width - rect.right;
  final bottom = window.height - rect.bottom;
  return BorderRadius.only(
    topLeft: at(rect.left, rect.top),
    topRight: at(right, rect.top),
    bottomLeft: at(rect.left, bottom),
    bottomRight: at(right, bottom),
  );
}

/// Paints the decoration [decorationFor] makes for the corners concentric
/// with the display's, where the box is on the screen when painted.
class _ConcentricShape extends LeafRenderObjectWidget {
  const _ConcentricShape({
    required this.window,
    required this.minimum,
    required this.decorationFor,
  });

  final Size window;
  final double minimum;
  final ShapeDecoration Function(BorderRadius radius) decorationFor;

  @override
  _RenderConcentricShape createRenderObject(BuildContext context) =>
      _RenderConcentricShape(window, minimum, decorationFor);

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderConcentricShape renderObject,
  ) {
    renderObject
      ..window = window
      ..minimum = minimum
      ..decorationFor = decorationFor;
  }
}

class _RenderConcentricShape extends RenderBox {
  _RenderConcentricShape(this._window, this._minimum, this._decorationFor);

  Size _window;
  set window(Size value) {
    if (value == _window) return;
    _window = value;
    markNeedsPaint();
  }

  double _minimum;
  set minimum(double value) {
    if (value == _minimum) return;
    _minimum = value;
    markNeedsPaint();
  }

  ShapeDecoration Function(BorderRadius radius) _decorationFor;
  set decorationFor(ShapeDecoration Function(BorderRadius radius) value) {
    _decorationFor = value;
    markNeedsPaint();
  }

  @override
  bool get sizedByParent => true;

  @override
  Size computeDryLayout(BoxConstraints constraints) => constraints.biggest;

  @override
  void paint(PaintingContext context, Offset offset) {
    final radius = concentricCornersAt(
      localToGlobal(Offset.zero) & size,
      window: _window,
      minimum: _minimum,
    );
    final painter = _decorationFor(radius).createBoxPainter(markNeedsPaint);
    painter.paint(context.canvas, offset, ImageConfiguration(size: size));
    painter.dispose();
  }
}

/// Clips the content of an [IOS26GlassSurface] to the surface's shape, with
/// concentric corners where the surface is on the screen when painted, as
/// [_ConcentricShape] draws them.
class _ShapeClip extends SingleChildRenderObjectWidget {
  const _ShapeClip({
    required this.corners,
    required this.cornerRadius,
    required this.window,
    required this.clipBehavior,
    super.child,
  });

  final GlassSurfaceCorners corners;
  final double cornerRadius;
  final Size window;
  final Clip clipBehavior;

  @override
  _RenderShapeClip createRenderObject(BuildContext context) =>
      _RenderShapeClip(corners, cornerRadius, window, clipBehavior);

  @override
  void updateRenderObject(BuildContext context, _RenderShapeClip renderObject) {
    renderObject
      ..corners = corners
      ..cornerRadius = cornerRadius
      ..window = window
      ..clipBehavior = clipBehavior;
  }
}

class _RenderShapeClip extends RenderProxyBox {
  _RenderShapeClip(
    this._corners,
    this._cornerRadius,
    this._window,
    this._clipBehavior,
  );

  GlassSurfaceCorners _corners;
  set corners(GlassSurfaceCorners value) {
    if (value == _corners) return;
    _corners = value;
    markNeedsPaint();
  }

  double _cornerRadius;
  set cornerRadius(double value) {
    if (value == _cornerRadius) return;
    _cornerRadius = value;
    markNeedsPaint();
  }

  Size _window;
  set window(Size value) {
    if (value == _window) return;
    _window = value;
    markNeedsPaint();
  }

  Clip _clipBehavior;
  set clipBehavior(Clip value) {
    if (value == _clipBehavior) return;
    _clipBehavior = value;
    markNeedsPaint();
  }

  final LayerHandle<ClipRSuperellipseLayer> _clipLayer =
      LayerHandle<ClipRSuperellipseLayer>();

  BorderRadius get _radius => switch (_corners) {
    GlassSurfaceCorners.fixed => BorderRadius.circular(_cornerRadius),
    GlassSurfaceCorners.capsule => BorderRadius.circular(size.shortestSide / 2),
    GlassSurfaceCorners.concentric => concentricCornersAt(
      localToGlobal(Offset.zero) & size,
      window: _window,
      minimum: _cornerRadius,
    ),
  };

  @override
  void paint(PaintingContext context, Offset offset) {
    if (child == null || _clipBehavior == Clip.none) {
      _clipLayer.layer = null;
      super.paint(context, offset);
      return;
    }
    final bounds = Offset.zero & size;
    _clipLayer.layer = context.pushClipRSuperellipse(
      needsCompositing,
      offset,
      bounds,
      _radius.toRSuperellipse(bounds),
      super.paint,
      clipBehavior: _clipBehavior,
      oldLayer: _clipLayer.layer,
    );
  }

  @override
  void dispose() {
    _clipLayer.layer = null;
    super.dispose();
  }
}

/// Stand-in for the glass where there is no UIKit.
class _Frosted extends StatelessWidget {
  const _Frosted({required this.widget});

  final IOS26GlassSurface widget;

  @override
  Widget build(BuildContext context) {
    final dark =
        MediaQuery.maybePlatformBrightnessOf(context) == Brightness.dark;
    final base = dark ? const Color(0x99202124) : const Color(0xB3FFFFFF);
    final tint = widget.tint;
    return LayoutBuilder(
      builder: (context, constraints) {
        final radius = widget.corners == GlassSurfaceCorners.capsule
            ? constraints.biggest.shortestSide / 2
            : widget.cornerRadius;
        return ClipRSuperellipse(
          borderRadius: BorderRadius.circular(radius),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
            child: ColoredBox(
              color: Color.alphaBlend(
                widget.fill ?? const Color(0x00000000),
                tint == null
                    ? base
                    : Color.alphaBlend(tint.withValues(alpha: 0.35), base),
              ),
            ),
          ),
        );
      },
    );
  }
}
