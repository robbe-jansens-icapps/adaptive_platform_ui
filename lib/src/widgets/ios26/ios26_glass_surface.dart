import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../../platform/platform_info.dart';
import '../../toolbar/toolbar_blend.dart';

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
    with SingleTickerProviderStateMixin {
  MethodChannel? _channel;
  Map<String, Object>? _sent;

  static bool get _hasUIKit =>
      IOS26GlassSurface.debugHasUIKitOverride ?? (!kIsWeb && Platform.isIOS);

  /// The animations of the page the glass is on: its own (coming and going)
  /// and the one of the page over it (being covered and uncovered).
  Animation<double>? _animation;
  Animation<double>? _secondaryAnimation;
  ModalRoute<Object?>? _route;

  /// Whether pages are being pushed, popped or dragged back (from the
  /// `AdaptiveToolbarHost`): a page that comes in or leaves as a full-screen
  /// dialog does not move the one below it, so its animations say nothing.
  ValueListenable<bool>? _routeTransition;

  /// Whether the native glass is on screen: only while its page holds still
  /// in front. A native view keeps showing above Flutter content that moves
  /// over it, so a page sliding over this one would let the glass show
  /// through; and creating native views as a page comes in costs frames. In
  /// between, a Flutter stand-in takes its place.
  bool _settled = true;

  /// Whether the native view exists. Once it does it stays, off stage while
  /// the page is not settled, so it is never created twice.
  bool _created = false;

  /// Whether the native view has had a frame to show itself, so the stand-in
  /// can make way without a gap.
  bool _nativeShown = false;

  /// The stand-in's opacity: it fades out over the glass once the glass is
  /// back, rather than leaving it at once.
  late final AnimationController _standIn;

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
    _sync();
  }

  @override
  void didUpdateWidget(IOS26GlassSurface oldWidget) {
    super.didUpdateWidget(oldWidget);
    _sync();
  }

  @override
  void dispose() {
    _routeTransition?.removeListener(_onRouteTransition);
    _listenTo(null, null);
    _standIn.dispose();
    _channel?.setMethodCallHandler(null);
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

  bool _firstSettle = true;

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
    if (settled) {
      _created = true;
      // An existing view shows in the next frame; a new one once created.
      if (_channel != null) _showNative();
    } else {
      _nativeShown = false;
      _standIn.value = 1;
    }
    if (rebuild && mounted) setState(() {});
  }

  /// The native glass is on screen again: the stand-in fades out over it.
  void _showNative() {
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_settled) return;
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
    if (_settled) _showNative();
  }

  void _sync() {
    final channel = _channel;
    if (channel == null) return;
    final params = _params;
    if (mapEquals(params, _sent)) return;
    _sent = params;
    channel.invokeMethod<void>('update', params);
  }

  @override
  Widget build(BuildContext context) {
    if (!_hasUIKit) {
      return Stack(
        alignment: Alignment.center,
        fit: StackFit.passthrough,
        children: [
          Positioned.fill(child: _Frosted(widget: widget)),
          ?widget.child,
        ],
      );
    }
    final showsStandIn = !_settled || !_nativeShown || _standIn.isAnimating;
    return Stack(
      alignment: Alignment.center,
      fit: StackFit.passthrough,
      children: [
        if (_created || _settled)
          Positioned.fill(
            child: Offstage(
              offstage: !_settled,
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
        ?widget.child,
      ],
    );
  }
}

/// What shows for the glass while its page moves: a light, translucent fill
/// in the glass's shape and tint, cheap to draw on every frame of a
/// transition.
class _StandIn extends StatelessWidget {
  const _StandIn({required this.widget});

  final IOS26GlassSurface widget;

  @override
  Widget build(BuildContext context) {
    final dark =
        MediaQuery.maybePlatformBrightnessOf(context) == Brightness.dark;
    final base = dark ? const Color(0xE6303034) : const Color(0xE6FAFAFC);
    final tint = widget.tint;
    // A tint is what the glass mostly shows; a light one lets it through.
    final tinted = tint == null
        ? base
        : Color.alphaBlend(
            tint.withValues(alpha: tint.a < 0.5 ? tint.a : 0.92),
            base,
          );
    final fill = widget.fill;
    final color = fill == null ? tinted : Color.alphaBlend(fill, tinted);
    return LayoutBuilder(
      builder: (context, constraints) {
        final radius = widget.corners == GlassSurfaceCorners.capsule
            ? constraints.biggest.shortestSide / 2
            : widget.cornerRadius;
        return DecoratedBox(
          decoration: ShapeDecoration(
            color: color,
            shape: RoundedSuperellipseBorder(
              borderRadius: BorderRadius.circular(radius),
              side: BorderSide(
                color: const Color(0xFFFFFFFF).withValues(alpha: 0.6),
                width: 0.5,
              ),
            ),
            shadows: const [
              BoxShadow(
                color: Color(0x14000000),
                blurRadius: 12,
                offset: Offset(0, 2),
              ),
            ],
          ),
        );
      },
    );
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
