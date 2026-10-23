import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// Marks where a bar frosts the content scrolled under it
/// ([AdaptiveBarBackdrop]), for the native views in that content to leave it
/// to their Flutter stand-ins ([NativeViewSettle]).
///
/// iOS blurs a native view under a `BackdropFilter` within the view's own
/// frame only: a switch scrolled under the bar showed as a grey box with hard
/// edges in the frost, rather than blurred with the rest.
class BarFrost extends SingleChildRenderObjectWidget {
  const BarFrost({super.key, super.child});

  static final Set<_RenderBarFrost> _frosts = <_RenderBarFrost>{};

  /// Whether [rect], in the logical coordinates of [box]'s view, lies at
  /// least partly under a bar's frost on screen in that view. A frost faded
  /// out (a bar with nothing scrolled under it) is not painted, and covers
  /// nothing.
  static bool covers(RenderBox box, Rect rect) {
    for (final frost in _frosts) {
      if (!identical(frost.owner, box.owner) ||
          !frost.hasSize ||
          !frost.isPainted) {
        continue;
      }
      final area = MatrixUtils.transformRect(
        frost.getTransformTo(null),
        Offset.zero & frost.size,
      );
      if (area.overlaps(rect)) return true;
    }
    return false;
  }

  @override
  RenderProxyBox createRenderObject(BuildContext context) => _RenderBarFrost();
}

class _RenderBarFrost extends RenderProxyBox {
  // A layer of its own, which is in the composited tree only while the frost
  // is painted.
  @override
  bool get isRepaintBoundary => true;

  bool get isPainted => layer?.attached ?? false;

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    BarFrost._frosts.add(this);
  }

  @override
  void detach() {
    BarFrost._frosts.remove(this);
    super.detach();
  }
}
