import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../../../toolbar/chrome_barrier.dart';
import 'native_chrome_navigator_observer.dart';

/// Tells iOS where the native views shown over the Flutter view are
/// ([NativeChromeView]), once per frame in which any of them changed.
///
/// Each view's placeholder has a layer of its own. Once the frame's layer tree
/// is composited, the layers above it give its transform, opacity and clip,
/// the same way the engine finds them for a platform view, and the order the
/// placeholders were composited in gives the order of the views. That holds
/// for a page sliding in or a bar fading out too, where only a layer above
/// the placeholder changes and the placeholder itself does not paint again.
///
/// The views are above all Flutter content. What Flutter draws over one, a
/// page sliding over its page ([NativeChromeNavigatorObserver]) or a sheet
/// rising over it ([NativeChromeOccluder]), cuts it off at its edge, or takes
/// it off the screen where it covers it otherwise; a dialog's barrier over
/// its page is laid over it by iOS.
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
  final Set<NativeChromeOccluderHandle> _occluders =
      <NativeChromeOccluderHandle>{};
  bool _started = false;
  bool _flushing = false;

  /// Whether iOS applies each frame's message with that frame's pixels
  /// (Swift: NativeChromeHost), which takes one for every frame, changes or
  /// not. Otherwise it applies them as they come, before the pixels.
  bool _frameLocked = false;
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
    channel.invokeMethod<Object?>('reset').then((reply) {
      _frameLocked = reply is Map && reply['frameLocked'] == true;
    });
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
    final occluders = [
      for (final occluder in _occluders)
        if (occluder._composited) (z: occluder._z, rect: occluder._rect),
    ];
    final changes = <double>[];
    var again = false;
    for (final slot in _slots.values) {
      slot._findCover(occluders);
      final values = slot._valuesForFrame();
      if (slot._hiding) again = true;
      if (!_listEquals(values, slot._sent)) {
        slot._sent = values;
        changes.addAll(values);
      }
      slot._composited = false;
    }
    for (final occluder in _occluders) {
      occluder._composited = false;
    }
    _z = 0;
    if (changes.isNotEmpty || _frameLocked) {
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
    _frameLocked = false;
    _slots.clear();
    _occluders.clear();
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

  /// A dialog's barrier over the view, which Flutter cannot draw over it: iOS
  /// lays it over the view's glass in this colour.
  ValueListenable<Color?>? dim;

  /// The page the view is on, whose navigator says what is over it
  /// ([NativeChromeNavigatorObserver]).
  Route<Object?>? route;

  /// What of the view nothing covers this frame, how much of it shows
  /// through pages that fade over it, and the barrier over its page
  /// ([_findCover]).
  Rect? _uncovered;
  double _showsThrough = 1;
  Color? _routeDim;

  RenderBox? _box;
  bool _disposed = false;

  bool _composited = false;
  int _z = 0;
  Rect? _bounds;
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
    _z = _coordinator._z++;
    _current = _measure(layer as OffsetLayer, box.size);
  }

  /// The values to send for this frame. Where iOS applies them before
  /// Flutter's pixels of the same frame (not frame locked), a placeholder that
  /// is no longer composited stays on screen one frame more, without taking
  /// touches: hiding the view at once would leave a frame with neither it nor
  /// the stand-in that Flutter paints in its place.
  Float64List _valuesForFrame() {
    final sent = _sent;
    if (_composited && _current != null) {
      _hiding = false;
      final values = Float64List.fromList(_current!);
      values[19] *= _showsThrough;
      final dim = this.dim?.value ?? _routeDim;
      if (dim != null && dim.a > 0) values[28] = dim.toARGB32().toDouble();
      final uncovered = _uncovered;
      if (uncovered != null && uncovered != _bounds) {
        final clip = values[20] == 0
            ? uncovered
            : Rect.fromLTRB(
                values[21],
                values[22],
                values[23],
                values[24],
              ).intersect(uncovered);
        values
          ..[20] = 1
          ..[21] = clip.left
          ..[22] = clip.top
          ..[23] = clip.right
          ..[24] = clip.bottom
          ..[25] = 0;
      }
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
    if (visible && !_hiding && !_coordinator._frameLocked) {
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

  Float64List _measure(OffsetLayer layer, Size size) {
    final (:transform, :alpha, :clip, :radius, :supported) = _walk(layer);
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
    _bounds = bounds;
    final values = Float64List(NativeChromeCoordinator.stride)
      ..[0] = id.toDouble()
      ..[1] = size.width
      ..[2] = size.height
      ..setRange(3, 19, transform.storage)
      ..[19] = alpha
      ..[26] = _z.toDouble();
    var flags = NativeChromeCoordinator.interactiveFlag;
    if (!supported || (clip != null && !clip.overlaps(bounds))) {
      flags = NativeChromeCoordinator.hiddenFlag;
    } else if (clip != null && !_contains(clip, bounds)) {
      values
        ..[20] = 1
        ..[21] = clip.left
        ..[22] = clip.top
        ..[23] = clip.right
        ..[24] = clip.bottom
        ..[25] = radius;
    }
    values[27] = flags.toDouble();
    return values;
  }

  /// Finds what Flutter draws over the view this frame: the [occluders]
  /// composited after it, the pages over its page, and the barrier of a
  /// dialog over its page. A view they cover all of, or in the middle, is
  /// taken off the screen; one they cover along a side is cut off there.
  void _findCover(List<({int z, Rect rect})> occluders) {
    _uncovered = null;
    _showsThrough = 1;
    _routeDim = null;
    final bounds = _bounds;
    if (!_composited || bounds == null) return;
    final covers = [
      for (final occluder in occluders)
        if (occluder.z > _z) occluder.rect,
    ];
    final route = this.route;
    final above = route == null
        ? null
        : NativeChromeNavigatorObserver.routesAbove(route);
    for (final page in above ?? const <Route<dynamic>>[]) {
      if (page is! ModalRoute<dynamic> || page.offstage) continue;
      if (page is PopupRoute<dynamic> ||
          (!page.opaque && (page.barrierColor?.a ?? 0) > 0)) {
        _routeDim =
            chromeBarrierOf(page, showsThrough: kGlassShowsThrough)?.value ??
            _routeDim;
        continue;
      }
      final box = page.subtreeContext?.findRenderObject();
      if (box is! RenderBox || !box.attached || !box.hasSize) continue;
      final rect = MatrixUtils.transformRect(
        box.getTransformTo(null),
        Offset.zero & box.size,
      );
      // A page that fades in or out over it: the view, above it, fades out
      // as much as the page comes in, about as it looks under the page.
      final opacity = _opacityOf(box);
      if (opacity < 0.99) {
        if (rect.overlaps(bounds)) _showsThrough *= 1 - opacity;
        continue;
      }
      covers.add(rect);
    }
    var uncovered = bounds;
    for (final cover in covers) {
      final left = _uncoveredBy(uncovered, cover);
      if (left == null) {
        _composited = false;
        return;
      }
      uncovered = left;
    }
    _uncovered = uncovered;
  }

  /// How opaque [box] is drawn, by the opacities above it, such as a page's
  /// fade transition.
  static double _opacityOf(RenderObject box) {
    var opacity = 1.0;
    for (RenderObject? node = box; node != null; node = node.parent) {
      if (node is RenderAnimatedOpacity) opacity *= node.opacity.value;
      if (node is RenderOpacity) opacity *= node.opacity;
    }
    return opacity;
  }

  /// What of [visible] [cover] leaves, where that is a rectangle: null where
  /// it covers all of it, its middle or a corner.
  static Rect? _uncoveredBy(Rect visible, Rect cover) {
    if (!cover.overlaps(visible)) return visible;
    final acrossHeight =
        cover.top <= visible.top && cover.bottom >= visible.bottom;
    final acrossWidth =
        cover.left <= visible.left && cover.right >= visible.right;
    if (acrossHeight && acrossWidth) return null;
    if (acrossHeight && cover.left <= visible.left) {
      return Rect.fromLTRB(
        cover.right,
        visible.top,
        visible.right,
        visible.bottom,
      );
    }
    if (acrossHeight && cover.right >= visible.right) {
      return Rect.fromLTRB(
        visible.left,
        visible.top,
        cover.left,
        visible.bottom,
      );
    }
    if (acrossWidth && cover.top <= visible.top) {
      return Rect.fromLTRB(
        visible.left,
        cover.bottom,
        visible.right,
        visible.bottom,
      );
    }
    if (acrossWidth && cover.bottom >= visible.bottom) {
      return Rect.fromLTRB(visible.left, visible.top, visible.right, cover.top);
    }
    return null;
  }

  static bool _contains(Rect outer, Rect inner) =>
      outer.left <= inner.left + 0.01 &&
      outer.top <= inner.top + 0.01 &&
      outer.right >= inner.right - 0.01 &&
      outer.bottom >= inner.bottom - 0.01;

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

/// Flutter content that covers the native views painted before it where it
/// overlaps them, such as a toast that comes down over the bar: they are
/// above all Flutter content, so they leave the screen while it does.
class NativeChromeOccluderHandle {
  NativeChromeOccluderHandle() {
    NativeChromeCoordinator.instance._occluders.add(this);
  }

  bool _composited = false;
  int _z = 0;
  Rect _rect = Rect.zero;
  RenderBox? box;

  void dispose() => NativeChromeCoordinator.instance._occluders.remove(this);

  /// See [NativeChromeSlot.composited].
  void composited(Layer layer) {
    if (SchedulerBinding.instance.schedulerPhase !=
        SchedulerPhase.persistentCallbacks) {
      return;
    }
    final box = this.box;
    if (!layer.attached || box == null || !box.hasSize) {
      _composited = false;
      return;
    }
    final coordinator = NativeChromeCoordinator.instance;
    _composited = true;
    _z = coordinator._z++;
    final (:transform, alpha: _, clip: _, radius: _, supported: _) = _walk(
      layer as OffsetLayer,
    );
    _rect = MatrixUtils.transformRect(transform, Offset.zero & box.size);
  }
}

/// What the layers above [layer] do to it, as the engine finds it for a
/// platform view: its transform to logical pixels, its opacity, the clip
/// around it in logical pixels with the radius of its corners where they are
/// round alike, and whether a filter that cannot apply to a native view is
/// among them.
({Matrix4 transform, double alpha, Rect? clip, double radius, bool supported})
_walk(OffsetLayer layer) {
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

  double uniformRadius(List<Radius> corners) {
    final first = corners.first;
    for (final other in corners) {
      if (other != first) return 0;
    }
    return first.x == first.y ? first.x * transform.getMaxScaleOnAxis() : 0;
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
          uniformRadius([
            clipRRect.tlRadius,
            clipRRect.trRadius,
            clipRRect.blRadius,
            clipRRect.brRadius,
          ]),
        );
      case ClipRSuperellipseLayer(:final clipRSuperellipse?):
        clipTo(
          clipRSuperellipse.outerRect,
          uniformRadius([
            clipRSuperellipse.tlRadius,
            clipRSuperellipse.trRadius,
            clipRSuperellipse.blRadius,
            clipRSuperellipse.brRadius,
          ]),
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
  return (
    transform: transform,
    alpha: alpha,
    clip: clip,
    radius: radius,
    supported: supported,
  );
}
