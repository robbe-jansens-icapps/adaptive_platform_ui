import 'dart:async';

import 'package:flutter/material.dart';

import '../platform/platform_info.dart';
import 'ios26/ios26_glass_surface.dart';

/// A short message that slides in at the top of the screen and goes again by
/// itself, like a system banner: on Liquid Glass on iOS 26, a Material 3 card
/// elsewhere. A tap or an upward swipe takes it away sooner.
///
/// It shows above everything the app draws, the fixed toolbar and the iPhone
/// Duo vertical bar of an [AdaptiveToolbarHost] included, and it is not a
/// route: the page under it stays the page in front, its toolbar undimmed.
class AdaptiveToast {
  AdaptiveToast._();

  static final _dismissers = <VoidCallback>{};

  /// The overlay toasts and banners go in: the one [AdaptiveToastLayer] puts
  /// above the app's chrome, or else the root overlay (that of the root
  /// navigator, also from the navigator's own context).
  static OverlayState overlayOf(BuildContext context) =>
      context
          .getInheritedWidgetOfExactType<_ToastLayerScope>()
          ?.overlay
          .currentState ??
      Overlay.maybeOf(context, rootOverlay: true) ??
      Navigator.of(context, rootNavigator: true).overlay!;

  /// Shows what [builder] makes, which gets the callback that dismisses it,
  /// for [duration]. One toast at a time: a new one replaces the one on
  /// screen. [color] fills the Material card, and tints the glass on iOS 26.
  static void show(
    BuildContext context, {
    required Widget Function(VoidCallback dismiss) builder,
    Duration duration = const Duration(seconds: 4),
    Color? color,
  }) {
    clear();
    final overlay = overlayOf(context);
    late final OverlayEntry entry;
    var removed = false;
    void remove() {
      if (removed) return;
      removed = true;
      entry.remove();
    }

    entry = OverlayEntry(
      builder: (context) => _Toast(
        color: color,
        duration: duration,
        builder: builder,
        onRegister: _dismissers.add,
        onUnregister: _dismissers.remove,
        onDismissed: remove,
      ),
    );
    overlay.insert(entry);
  }

  /// Takes away the toast on screen, if any.
  static void clear() {
    for (final dismiss in {..._dismissers}) {
      dismiss();
    }
  }
}

/// Where [AdaptiveToast]s go: an overlay above [child]. [AdaptiveToolbarHost]
/// puts one above its bars; an app without one can put one above its
/// navigator.
class AdaptiveToastLayer extends StatefulWidget {
  const AdaptiveToastLayer({super.key, required this.child});

  final Widget child;

  @override
  State<AdaptiveToastLayer> createState() => _AdaptiveToastLayerState();
}

class _AdaptiveToastLayerState extends State<AdaptiveToastLayer> {
  final _overlay = GlobalKey<OverlayState>();

  @override
  Widget build(BuildContext context) {
    return _ToastLayerScope(
      overlay: _overlay,
      child: Stack(
        fit: StackFit.expand,
        children: [
          widget.child,
          // Takes no touches while empty. No clip: one around a toast's glass
          // would break it.
          Overlay(key: _overlay, clipBehavior: Clip.none),
        ],
      ),
    );
  }
}

class _ToastLayerScope extends InheritedWidget {
  const _ToastLayerScope({required this.overlay, required super.child});

  final GlobalKey<OverlayState> overlay;

  @override
  bool updateShouldNotify(_ToastLayerScope oldWidget) =>
      overlay != oldWidget.overlay;
}

class _Toast extends StatefulWidget {
  const _Toast({
    required this.color,
    required this.duration,
    required this.builder,
    required this.onRegister,
    required this.onUnregister,
    required this.onDismissed,
  });

  final Color? color;
  final Duration duration;
  final Widget Function(VoidCallback dismiss) builder;
  final ValueChanged<VoidCallback> onRegister;
  final ValueChanged<VoidCallback> onUnregister;
  final VoidCallback onDismissed;

  @override
  State<_Toast> createState() => _ToastState();
}

class _ToastState extends State<_Toast> with SingleTickerProviderStateMixin {
  late final _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 500),
    reverseDuration: const Duration(milliseconds: 250),
  );
  late final _slide =
      Tween<Offset>(begin: const Offset(0, -1.5), end: Offset.zero).animate(
        CurvedAnimation(
          parent: _controller,
          curve: Curves.easeOutBack,
          reverseCurve: Curves.easeIn,
        ),
      );
  Timer? _timer;
  var _dismissing = false;

  @override
  void initState() {
    super.initState();
    widget.onRegister(_dismiss);
    _controller.forward();
    _timer = Timer(widget.duration, _dismiss);
  }

  @override
  void dispose() {
    widget.onUnregister(_dismiss);
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _dismiss() {
    if (_dismissing || !mounted) return;
    _dismissing = true;
    _timer?.cancel();
    _controller.reverse().whenComplete(widget.onDismissed);
  }

  @override
  Widget build(BuildContext context) {
    final content = Material(
      type: MaterialType.transparency,
      child: widget.builder(_dismiss),
    );
    final Widget card;
    if (PlatformInfo.isIOS26OrHigher()) {
      card = IOS26GlassSurface(
        cornerRadius: 26,
        // Light enough to read on whatever is behind it, and still glass.
        tint: (widget.color ?? Colors.white).withValues(alpha: 0.85),
        child: content,
      );
    } else {
      card = Material(
        color:
            widget.color ?? Theme.of(context).colorScheme.surfaceContainerHigh,
        elevation: 3,
        shadowColor: Colors.black38,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        clipBehavior: Clip.antiAlias,
        child: content,
      );
    }
    return Align(
      alignment: Alignment.topCenter,
      child: SafeArea(
        minimum: const EdgeInsets.fromLTRB(12, 8, 12, 0),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          // Moves by transforms only, never fades or clips: either would
          // break the glass.
          child: SlideTransition(
            position: _slide,
            child: Dismissible(
              key: const ValueKey<String>('adaptive_toast'),
              direction: DismissDirection.up,
              resizeDuration: null,
              onDismissed: (_) {
                _timer?.cancel();
                widget.onDismissed();
              },
              child: Semantics(
                container: true,
                liveRegion: true,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: _dismiss,
                  child: card,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
