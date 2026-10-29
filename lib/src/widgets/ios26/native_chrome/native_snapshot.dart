import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

/// [child] in a layer of its own, taken as an image at the screen's scale
/// after each frame it was painted in, while [enabled]: what a native view
/// over the Flutter view shows of Flutter content.
class NativeSnapshot extends SingleChildRenderObjectWidget {
  const NativeSnapshot({
    super.key,
    required this.enabled,
    required this.onImage,
    required super.child,
  });

  final bool enabled;
  final void Function(Uint8List bytes, double scale) onImage;

  @override
  RenderObject createRenderObject(BuildContext context) => RenderNativeSnapshot(
    enabled: enabled,
    onImage: onImage,
    scale: MediaQuery.devicePixelRatioOf(context),
  );

  @override
  void updateRenderObject(
    BuildContext context,
    RenderNativeSnapshot renderObject,
  ) {
    renderObject
      ..enabled = enabled
      ..onImage = onImage
      ..scale = MediaQuery.devicePixelRatioOf(context);
  }
}

class RenderNativeSnapshot extends RenderRepaintBoundary {
  RenderNativeSnapshot({
    required this.enabled,
    required this.onImage,
    required double scale,
  }) : _scale = scale;

  bool enabled;
  void Function(Uint8List bytes, double scale) onImage;

  double _scale;
  set scale(double value) {
    if (value == _scale) return;
    _scale = value;
    markNeedsPaint();
  }

  bool _scheduled = false;
  int _generation = 0;

  @override
  void paint(PaintingContext context, Offset offset) {
    super.paint(context, offset);
    if (!enabled || _scheduled) return;
    _scheduled = true;
    SchedulerBinding.instance.addPostFrameCallback((_) => _take());
  }

  Future<void> _take() async {
    _scheduled = false;
    if (!attached || !hasSize || size.isEmpty) return;
    final generation = ++_generation;
    final scale = _scale;
    final ui.Image image = await toImage(pixelRatio: scale);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    // A later one is on its way.
    if (data == null || generation != _generation) return;
    onImage(data.buffer.asUint8List(), scale);
  }
}

/// [child], painted or not: kept out of sight it is still laid out, painted
/// (for a [NativeSnapshot] of it) and hit tested.
class NativeOutOfSight extends SingleChildRenderObjectWidget {
  const NativeOutOfSight({super.key, required this.visible, super.child});

  final bool visible;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      RenderNativeOutOfSight(visible);

  @override
  void updateRenderObject(
    BuildContext context,
    RenderNativeOutOfSight renderObject,
  ) {
    renderObject.visible = visible;
  }
}

class RenderNativeOutOfSight extends RenderProxyBox {
  RenderNativeOutOfSight(this._visible);

  bool _visible;
  set visible(bool value) {
    if (value == _visible) return;
    _visible = value;
    markNeedsCompositingBitsUpdate();
    markNeedsPaint();
  }

  @override
  bool get alwaysNeedsCompositing => child != null && !_visible;

  @override
  void paint(PaintingContext context, Offset offset) {
    if (_visible) {
      super.paint(context, offset);
      return;
    }
    // Out of sight: the engine draws nothing for a layer at no opacity, so it
    // costs no overlay over a platform view under it.
    layer = context.pushOpacity(
      offset,
      0,
      super.paint,
      oldLayer: layer as OpacityLayer?,
    );
  }
}
