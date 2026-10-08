import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

/// Reports the size of its child whenever a layout changes it.
///
/// Layout cannot trigger a build, so the size arrives after the frame that
/// produced it.
class SizeReporter extends SingleChildRenderObjectWidget {
  const SizeReporter({super.key, required this.onSizeChanged, super.child});

  final ValueChanged<Size> onSizeChanged;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderSizeReporter(onSizeChanged);

  @override
  void updateRenderObject(BuildContext context, RenderObject renderObject) {
    (renderObject as _RenderSizeReporter).onSizeChanged = onSizeChanged;
  }
}

class _RenderSizeReporter extends RenderProxyBox {
  _RenderSizeReporter(this.onSizeChanged);

  ValueChanged<Size> onSizeChanged;
  Size? _reported;

  @override
  void performLayout() {
    super.performLayout();
    final size = this.size;
    if (size == _reported) return;
    _reported = size;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (attached) onSizeChanged(size);
    });
  }
}
