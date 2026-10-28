import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

/// Tells iOS where the native views shown over the Flutter view are
/// ([NativeChromeView]), once per frame in which any of them changed.
///
/// Each view's placeholder has a layer of its own. Once the frame's layer tree
/// is composited, the layers above it give its transform, opacity and clip,
/// the same way the engine finds them for a platform view, and the order the
/// placeholders were composited in gives the order of the views. That holds
/// for a page sliding in or a bar fading out too, where only a layer above
/// the placeholder changes and the placeholder itself does not paint again.
class NativeChromeCoordinator {
  NativeChromeCoordinator._();

  static final NativeChromeCoordinator instance = NativeChromeCoordinator._();

  @visibleForTesting
  static const MethodChannel channel = MethodChannel(
    'adaptive_platform_ui/native_chrome',
  );

  /// Values per view in a `layout` batch (Swift: NativeChromeHost).
  static const int stride = 29;
  static const int hiddenFlag = 1;
  static const int interactiveFlag = 2;

  final Map<int, NativeChromeSlot> _slots = <int, NativeChromeSlot>{};
  bool _started = false;
  bool _flushing = false;
  int _z = 0;

  /// Makes the native view of [viewType] for a placeholder, through the same
  /// factory as its platform view; [onCreated] is called with its id once iOS
  /// made it.
  NativeChromeSlot create({
    required String viewType,
    Object? creationParams,
    bool interactive = true,
    PlatformViewCreatedCallback? onCreated,
  }) {
    _start();
    final id = platformViewsRegistry.getNextPlatformViewId();
    final slot = NativeChromeSlot._(this, id, interactive: interactive);
    _slots[id] = slot;
    channel
        .invokeMethod<void>('create', <String, Object?>{
          'id': id,
          'viewType': viewType,
          'params': creationParams,
        })
        .then((_) {
          if (!slot._disposed) onCreated?.call(id);
        });
    return slot;
  }

  void _dispose(NativeChromeSlot slot) {
    _slots.remove(slot.id);
    unawaited(
      channel.invokeMethod<void>('dispose', <String, Object?>{'id': slot.id}),
    );
  }

  void _start() {
    if (_started) return;
    _started = true;
    // Views made before a hot restart are still on screen.
    unawaited(channel.invokeMethod<void>('reset'));
    if (_flushing) return;
    _flushing = true;
    final scheduler = SchedulerBinding.instance;
    scheduler.addPersistentFrameCallback(_flush);
    // Added while a frame builds, the callback first runs with the next one:
    // this frame's views are placed after it all the same.
    if (scheduler.schedulerPhase == SchedulerPhase.persistentCallbacks) {
      scheduler.addPostFrameCallback(_flush);
    }
  }

  /// Runs after the binding drew the frame, as it was registered later.
  void _flush(Duration _) {
    if (_slots.isEmpty) {
      _z = 0;
      return;
    }
    final changes = <double>[];
    var again = false;
    for (final slot in _slots.values) {
      final values = slot._valuesForFrame();
      if (slot._hiding) again = true;
      if (!_listEquals(values, slot._sent)) {
        slot._sent = values;
        changes.addAll(values);
      }
      slot._composited = false;
    }
    _z = 0;
    if (changes.isNotEmpty) {
      unawaited(
        channel.invokeMethod<void>('layout', Float64List.fromList(changes)),
      );
    }
    // Hidden one frame later, see [NativeChromeSlot._valuesForFrame].
    if (again) SchedulerBinding.instance.scheduleFrame();
  }

  static bool _listEquals(Float64List a, Float64List? b) {
    if (b == null || a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  @visibleForTesting
  void debugReset() {
    _slots.clear();
    _started = false;
    _z = 0;
  }
}

/// One native view over the Flutter view, and what its placeholder last
/// looked like.
class NativeChromeSlot {
  NativeChromeSlot._(this._coordinator, this.id, {required bool interactive})
    : _interactive = interactive;

  final NativeChromeCoordinator _coordinator;
  final int id;

  bool _interactive;
  set interactive(bool value) => _interactive = value;

  RenderBox? _box;
  bool _disposed = false;

  bool _composited = false;
  Float64List? _current;
  Float64List? _sent;
  bool _hiding = false;

  void attach(RenderBox box) => _box = box;

  void detach(RenderBox box) {
    if (_box == box) _box = null;
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _coordinator._dispose(this);
  }

  /// Called when the layer tree with the placeholder's [layer] was
  /// composited, or when the layer left it.
  void composited(Layer layer) {
    // The same callbacks run for a scene made by `toImage`.
    if (SchedulerBinding.instance.schedulerPhase !=
        SchedulerPhase.persistentCallbacks) {
      return;
    }
    final box = _box;
    if (!layer.attached || box == null || !box.hasSize) {
      _composited = false;
      return;
    }
    _composited = true;
    _current = _measure(layer as OffsetLayer, box.size, _coordinator._z++);
  }

  /// The values to send for this frame. A placeholder that is no longer
  /// composited stays on screen one frame more, without taking touches: iOS
  /// gets the message before Flutter's pixels of the same frame, so hiding
  /// the view at once would leave a frame with neither it nor the stand-in
  /// that Flutter paints in its place.
  Float64List _valuesForFrame() {
    final sent = _sent;
    if (_composited && _current != null) {
      _hiding = false;
      final values = Float64List.fromList(_current!);
      if (!_interactive || _ignoresPointer(_box)) {
        values[27] =
            (values[27].toInt() & ~NativeChromeCoordinator.interactiveFlag)
                .toDouble();
      }
      return values;
    }
    final visible =
        sent != null &&
        sent[27].toInt() & NativeChromeCoordinator.hiddenFlag == 0;
    if (visible && !_hiding) {
      _hiding = true;
      return Float64List.fromList(sent)
        ..[27] = (sent[27].toInt() & ~NativeChromeCoordinator.interactiveFlag)
            .toDouble();
    }
    _hiding = false;
    return Float64List(NativeChromeCoordinator.stride)
      ..[0] = id.toDouble()
      ..[27] = NativeChromeCoordinator.hiddenFlag.toDouble();
  }

  Float64List _measure(OffsetLayer layer, Size size, int z) {
    final path = <Layer>[layer];
    while (path.last.parent != null) {
      path.add(path.last.parent!);
    }
    final transform = Matrix4.identity();
    var alpha = 1.0;
    Rect? clip;
    var radius = 0.0;
    var supported = true;
    void clipTo(Rect rect, double rectRadius) {
      final global = MatrixUtils.transformRect(transform, rect);
      if (clip == null) {
        clip = global;
        radius = rectRadius;
        return;
      }
      final next = clip!.intersect(global);
      radius = next == global
          ? rectRadius
          : next == clip
          ? radius
          : 0;
      clip = next;
    }

    // The topmost layer scales to physical pixels; the views are placed in
    // logical ones, which are points on iOS.
    for (var i = path.length - 2; i > 0; i--) {
      final ancestor = path[i] as ContainerLayer;
      switch (ancestor) {
        case OpacityLayer(alpha: final layerAlpha?):
          alpha *= layerAlpha / 255;
        case ClipRectLayer(:final clipRect?):
          clipTo(clipRect, 0);
        case ClipRRectLayer(:final clipRRect?):
          clipTo(
            clipRRect.outerRect,
            _uniformRadius(clipRRect.tlRadius, [
                  clipRRect.trRadius,
                  clipRRect.blRadius,
                  clipRRect.brRadius,
                ]) *
                _scaleOf(transform),
          );
        case ClipRSuperellipseLayer(:final clipRSuperellipse?):
          clipTo(
            clipRSuperellipse.outerRect,
            _uniformRadius(clipRSuperellipse.tlRadius, [
                  clipRSuperellipse.trRadius,
                  clipRSuperellipse.blRadius,
                  clipRSuperellipse.brRadius,
                ]) *
                _scaleOf(transform),
          );
        case ClipPathLayer(:final clipPath?):
          clipTo(clipPath.getBounds(), 0);
        case ColorFilterLayer() || ImageFilterLayer() || ShaderMaskLayer():
          supported = false;
        default:
          break;
      }
      ancestor.applyTransform(path[i - 1], transform);
    }
    transform.translateByDouble(layer.offset.dx, layer.offset.dy, 0, 1);

    assert(() {
      if (!supported) {
        debugPrint(
          'NativeChromeView: a color, image or shader filter above a native '
          'view cannot be applied to it; the view is hidden.',
        );
      }
      return true;
    }());

    final bounds = MatrixUtils.transformRect(transform, Offset.zero & size);
    final values = Float64List(NativeChromeCoordinator.stride)
      ..[0] = id.toDouble()
      ..[1] = size.width
      ..[2] = size.height
      ..setRange(3, 19, transform.storage)
      ..[19] = alpha
      ..[26] = z.toDouble();
    final clipped = clip;
    var flags = NativeChromeCoordinator.interactiveFlag;
    if (!supported || (clipped != null && !clipped.overlaps(bounds))) {
      flags = NativeChromeCoordinator.hiddenFlag;
    } else if (clipped != null && !_contains(clipped, bounds)) {
      values
        ..[20] = 1
        ..[21] = clipped.left
        ..[22] = clipped.top
        ..[23] = clipped.right
        ..[24] = clipped.bottom
        ..[25] = radius;
    }
    values[27] = flags.toDouble();
    return values;
  }

  static bool _contains(Rect outer, Rect inner) =>
      outer.left <= inner.left + 0.01 &&
      outer.top <= inner.top + 0.01 &&
      outer.right >= inner.right - 0.01 &&
      outer.bottom >= inner.bottom - 0.01;

  static double _uniformRadius(Radius first, List<Radius> others) {
    for (final other in others) {
      if (other != first) return 0;
    }
    return first.x == first.y ? first.x : 0;
  }

  static double _scaleOf(Matrix4 transform) => transform.getMaxScaleOnAxis();

  /// Whether an `IgnorePointer` or `AbsorbPointer` above the placeholder keeps
  /// touches from the content there, which then holds for the native view.
  static bool _ignoresPointer(RenderObject? object) {
    var node = object?.parent;
    while (node != null) {
      if (node is RenderIgnorePointer && node.ignoring) return true;
      if (node is RenderAbsorbPointer && node.absorbing) return true;
      node = node.parent;
    }
    return false;
  }
}
