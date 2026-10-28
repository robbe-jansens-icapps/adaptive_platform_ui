import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'native_chrome_coordinator.dart';

/// A native view shown over the Flutter view, in the place this widget takes
/// ([NativeChromeCoordinator]): the counterpart of a [UiKitView] that costs
/// the engine nothing per frame.
///
/// The view is always above the Flutter content. Where Flutter content has to
/// cover it, its widget stops painting the placeholder (a stand-in in its
/// place), and the view leaves the screen with the next frame.
class NativeChromeView extends StatefulWidget {
  const NativeChromeView({
    super.key,
    required this.viewType,
    this.creationParams,
    this.onPlatformViewCreated,
    this.interactive = true,
    this.dim,
  });

  final String viewType;
  final Object? creationParams;
  final PlatformViewCreatedCallback? onPlatformViewCreated;

  /// Whether the native view takes touches where it claims them; touches
  /// elsewhere reach the Flutter content under it.
  final bool interactive;

  /// See [NativeChromeSlot.dim].
  final ValueListenable<Color?>? dim;

  @override
  State<NativeChromeView> createState() => _NativeChromeViewState();
}

class _NativeChromeViewState extends State<NativeChromeView> {
  late final NativeChromeSlot _slot = NativeChromeCoordinator.instance.create(
    viewType: widget.viewType,
    creationParams: widget.creationParams,
    interactive: widget.interactive,
    onCreated: (id) => widget.onPlatformViewCreated?.call(id),
  )..dim = widget.dim;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _slot.route = ModalRoute.of(context);
  }

  @override
  void didUpdateWidget(NativeChromeView oldWidget) {
    super.didUpdateWidget(oldWidget);
    _slot
      ..interactive = widget.interactive
      ..dim = widget.dim;
  }

  @override
  void dispose() {
    _slot.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _NativeChromePlaceholder(slot: _slot);
}

class _NativeChromePlaceholder extends LeafRenderObjectWidget {
  const _NativeChromePlaceholder({required this.slot});

  final NativeChromeSlot slot;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderNativeChromePlaceholder(slot);

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderNativeChromePlaceholder renderObject,
  ) {
    renderObject.slot = slot;
  }
}

/// Takes all the room it is given and paints nothing, in a layer of its own:
/// that layer is found after each frame to place the native view, and the
/// layers above it (fades, slides, clips) are real layers because it is one.
class _RenderNativeChromePlaceholder extends RenderBox {
  _RenderNativeChromePlaceholder(this._slot);

  NativeChromeSlot _slot;
  set slot(NativeChromeSlot value) {
    if (value == _slot) return;
    _slot.detach(this);
    _cancelCallback();
    _slot = value;
    if (attached) _slot.attach(this);
    markNeedsPaint();
  }

  VoidCallback? _removeCallback;
  Layer? _observed;

  @override
  bool get sizedByParent => true;

  @override
  Size computeDryLayout(covariant BoxConstraints constraints) =>
      constraints.biggest;

  @override
  bool get isRepaintBoundary => true;

  @override
  bool get alwaysNeedsCompositing => true;

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _slot.attach(this);
  }

  @override
  void detach() {
    _slot.detach(this);
    super.detach();
  }

  @override
  void dispose() {
    _cancelCallback();
    super.dispose();
  }

  void _cancelCallback() {
    _removeCallback?.call();
    _removeCallback = null;
    _observed = null;
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    if (_observed != layer) {
      _cancelCallback();
      _removeCallback = context.addCompositionCallback(_slot.composited);
      _observed = layer;
    }
  }

  // Touches the native view leaves go to whatever Flutter shows under it.
  @override
  bool hitTestSelf(Offset position) => false;
}
