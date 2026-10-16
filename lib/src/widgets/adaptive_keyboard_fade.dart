import 'dart:math' as math;

import 'package:flutter/widgets.dart';

/// Fades [child] out as the keyboard comes up and back in as it goes down,
/// rather than having the keyboard slide over it: what sits along the bottom
/// of the window, such as the tabs and a control floating over a page.
///
/// Custom chrome ([AdaptiveToolbarHost.chrome]) does this for its tabs and
/// their accessory wherever the keyboard would cover them; an app wraps what
/// it floats along the bottom itself, so the two go together.
///
/// Only this widget follows each frame of the keyboard sliding in, not
/// [child]. While the keyboard is up, [child] takes no touches.
class AdaptiveKeyboardFade extends StatefulWidget {
  const AdaptiveKeyboardFade({
    super.key,
    this.enabled = true,
    required this.child,
  });

  /// Whether [child] fades for the keyboard at all.
  final bool enabled;

  final Widget child;

  /// How long [child] takes to fade out as the keyboard comes up: done
  /// before the keyboard covers much of the bottom of the window.
  static const Duration fadeOutDuration = Duration(milliseconds: 150);

  /// How long [child] takes to fade back in as the keyboard goes down.
  static const Duration fadeInDuration = Duration(milliseconds: 250);

  /// How far below its height when fully up the keyboard has gone down
  /// before [child] comes back, without waiting for the keyboard to be gone,
  /// which the system only reports a while after it is out of sight. A
  /// keyboard that changes height while it is up (another layout, its
  /// suggestions) moves less than this. Sooner still, [child] comes back as
  /// the text field the keyboard came up for loses the focus, which is when
  /// the keyboard starts to go down.
  static const double returnsBelow = 0.5;

  @override
  State<AdaptiveKeyboardFade> createState() => _AdaptiveKeyboardFadeState();
}

class _AdaptiveKeyboardFadeState extends State<AdaptiveKeyboardFade>
    with SingleTickerProviderStateMixin {
  late final AnimationController _shown = AnimationController(
    vsync: this,
    duration: AdaptiveKeyboardFade.fadeInDuration,
    reverseDuration: AdaptiveKeyboardFade.fadeOutDuration,
  );

  late final CurvedAnimation _opacity = CurvedAnimation(
    parent: _shown,
    curve: Curves.easeIn,
    reverseCurve: Curves.easeOut,
  );

  bool? _keyboard;

  /// The height of the keyboard, once fully up, since it came up.
  double _peak = 0;

  /// Whether a text field had the focus as the keyboard came up; not so for
  /// a keyboard of a web view.
  bool _forField = false;

  /// Whether that text field has lost the focus since, so the keyboard is on
  /// its way down.
  bool _left = false;

  @override
  void initState() {
    super.initState();
    FocusManager.instance.addListener(_onFocusChanged);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _update();
  }

  @override
  void didUpdateWidget(AdaptiveKeyboardFade oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.enabled != widget.enabled) _update();
  }

  void _onFocusChanged() {
    if (mounted && _update()) setState(() {});
  }

  static bool get _fieldHasFocus =>
      FocusManager.instance.primaryFocus?.context
          ?.findAncestorStateOfType<EditableTextState>() !=
      null;

  /// Fades [AdaptiveKeyboardFade.child] for the keyboard as it is now, and
  /// says whether that changed.
  bool _update() {
    final inset = widget.enabled
        ? MediaQuery.viewInsetsOf(context).bottom
        : 0.0;
    _peak = inset <= 0 ? 0 : math.max(_peak, inset);
    final up = inset > 0 && inset >= _peak * AdaptiveKeyboardFade.returnsBelow;
    final field = _fieldHasFocus;
    if (!up) {
      _forField = false;
      _left = false;
    } else if (!(_keyboard ?? false) && !_left) {
      _forField = field;
    }
    if (field) {
      _left = false;
    } else if (up && _forField) {
      _left = true;
    }
    final keyboard = up && !_left;
    if (keyboard == _keyboard) return false;
    final first = _keyboard == null;
    _keyboard = keyboard;
    if (first || (MediaQuery.maybeDisableAnimationsOf(context) ?? false)) {
      _shown.value = keyboard ? 0 : 1;
    } else if (keyboard) {
      _shown.reverse();
    } else {
      _shown.forward();
    }
    return true;
  }

  @override
  void dispose() {
    FocusManager.instance.removeListener(_onFocusChanged);
    _opacity.dispose();
    _shown.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      ignoring: _keyboard ?? false,
      child: FadeTransition(opacity: _opacity, child: widget.child),
    );
  }
}
