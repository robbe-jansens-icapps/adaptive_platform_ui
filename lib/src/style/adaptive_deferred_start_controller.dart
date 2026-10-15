import 'package:flutter/animation.dart';
import 'package:flutter/scheduler.dart';

/// An animation controller for a route coming in that only starts moving
/// once the route's first frame has been built ([settlingFrames]).
///
/// A sheet, a popover or a menu that takes a while to build would otherwise
/// lose the start of its motion to that first frame and appear nearly in
/// place at once; this way all of its motion shows. The route counts as
/// pushed, and coming in, at once. Going away from fully in, it holds for
/// the frame the page underneath takes to come back, in the same way.
class AdaptiveDeferredStartController extends AnimationController {
  AdaptiveDeferredStartController({
    required super.vsync,
    super.duration,
    super.reverseDuration,
    super.debugLabel,
    this.settlingFrames = 1,
  });

  /// How many frames to wait for before the first forward run starts; it
  /// moves from the frame after those.
  final int settlingFrames;

  bool _deferred = false;
  bool _pending = false;
  bool _pendingBack = false;
  bool _disposed = false;

  @override
  TickerFuture forward({double? from}) {
    _pendingBack = false;
    if (_deferred || !isDismissed) return super.forward(from: from);
    _deferred = true;
    // Under way at once, so the route treats itself as coming in (its
    // barrier takes taps), but held at its start until the frames are built.
    final started = super.forward(from: from);
    super.stop(canceled: false);
    _pending = true;
    _afterFrames(settlingFrames, () {
      if (!_pending || _disposed) return;
      _pending = false;
      super.forward();
    });
    return started;
  }

  @override
  TickerFuture reverse({double? from}) {
    _pending = false;
    if (_pendingBack || !isCompleted || (from != null && from != value)) {
      return super.reverse(from: from);
    }
    final started = super.reverse(from: from);
    super.stop(canceled: false);
    _pendingBack = true;
    _afterFrames(settlingFrames, () {
      if (!_pendingBack || _disposed) return;
      _pendingBack = false;
      super.reverse();
    });
    return started;
  }

  @override
  void stop({bool canceled = true}) {
    if (canceled) {
      _pending = false;
      _pendingBack = false;
    }
    super.stop(canceled: canceled);
  }

  void _afterFrames(int frames, VoidCallback callback) {
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (frames <= 1) {
        callback();
      } else {
        _afterFrames(frames - 1, callback);
      }
    });
    SchedulerBinding.instance.ensureVisualUpdate();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
