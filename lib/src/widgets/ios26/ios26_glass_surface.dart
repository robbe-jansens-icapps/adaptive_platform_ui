import 'dart:io';
import 'dart:ui' show ImageFilter;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

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
    this.clear = false,
    this.interactive = false,
    this.child,
  });

  final double cornerRadius;
  final GlassSurfaceCorners corners;

  /// Tints the glass, like `UIGlassEffect.tintColor`.
  final Color? tint;

  /// The clear glass style, for surfaces over rich content such as photos.
  final bool clear;

  /// Lets the glass respond to touches with the system's highlight. The
  /// touches still go to [child].
  final bool interactive;

  final Widget? child;

  @override
  State<IOS26GlassSurface> createState() => _IOS26GlassSurfaceState();
}

class _IOS26GlassSurfaceState extends State<IOS26GlassSurface> {
  MethodChannel? _channel;
  Map<String, Object>? _sent;

  static bool get _hasUIKit => !kIsWeb && Platform.isIOS;

  Map<String, Object> get _params => <String, Object>{
    'isDark': MediaQuery.maybePlatformBrightnessOf(context) == Brightness.dark,
    'cornerRadius': widget.cornerRadius,
    'corners': widget.corners.name,
    'style': widget.clear ? 'clear' : 'regular',
    'interactive': widget.interactive,
    if (widget.tint != null) 'tint': widget.tint!.toARGB32(),
  };

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  @override
  void didUpdateWidget(IOS26GlassSurface oldWidget) {
    super.didUpdateWidget(oldWidget);
    _sync();
  }

  @override
  void dispose() {
    _channel?.setMethodCallHandler(null);
    super.dispose();
  }

  void _onCreated(int id) {
    _channel = MethodChannel('adaptive_platform_ui/ios26_glass_surface_$id');
    _sync();
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
    final glass = _hasUIKit
        ? IgnorePointer(
            child: UiKitView(
              viewType: 'adaptive_platform_ui/ios26_glass_surface',
              // What the view is created with; later changes go through `update`.
              creationParams: _sent ??= _params,
              creationParamsCodec: const StandardMessageCodec(),
              onPlatformViewCreated: _onCreated,
            ),
          )
        : _Frosted(widget: widget);
    return Stack(
      alignment: Alignment.center,
      fit: StackFit.passthrough,
      children: [
        Positioned.fill(child: glass),
        ?widget.child,
      ],
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
              color: tint == null
                  ? base
                  : Color.alphaBlend(tint.withValues(alpha: 0.35), base),
            ),
          ),
        );
      },
    );
  }
}
