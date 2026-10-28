import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

import 'adaptive_native_chrome.dart';
import 'native_chrome_coordinator.dart';

/// [child], which covers the native views shown over the Flutter view that
/// Flutter painted before it ([NativeChromeView]), such as a toast coming down
/// over the bar: those are above all Flutter content, so while [child]
/// overlaps one, the view leaves the screen.
class NativeChromeOccluder extends StatelessWidget {
  const NativeChromeOccluder({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!AdaptiveNativeChrome.enabled) return child;
    return _Occluder(child: child);
  }
}

class _Occluder extends SingleChildRenderObjectWidget {
  const _Occluder({super.child});

  @override
  RenderObject createRenderObject(BuildContext context) => _RenderOccluder();
}

class _RenderOccluder extends RenderProxyBox {
  final NativeChromeOccluderHandle _handle = NativeChromeOccluderHandle();
  VoidCallback? _removeCallback;
  Layer? _observed;

  @override
  bool get isRepaintBoundary => true;

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _handle.box = this;
  }

  @override
  void detach() {
    _handle.box = null;
    super.detach();
  }

  @override
  void dispose() {
    _removeCallback?.call();
    _handle.dispose();
    super.dispose();
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    if (_observed != layer) {
      _removeCallback?.call();
      _removeCallback = context.addCompositionCallback(_handle.composited);
      _observed = layer;
    }
    super.paint(context, offset);
  }
}
