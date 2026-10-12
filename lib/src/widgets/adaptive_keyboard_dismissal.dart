import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// Closes the keyboard as iOS and Android apps do: a tap anywhere but on a
/// text field closes it. Scrolling or dragging does not, and neither does a
/// tap on a text field or on what belongs to it: whatever is in its
/// `TextFieldTapRegion`, such as its selection handles and menu, or icons an
/// app puts inside the field.
///
/// It sees every touch under it, whatever takes the touch afterwards: a tap on
/// a button closes the keyboard and still presses the button, and a tap on a
/// native view, such as a button of the fixed toolbar, counts too. So put it
/// high up, around the navigator and the toolbar host.
///
/// It also closes a keyboard that no text field holds any more, which the
/// system would otherwise leave up (see [dismiss]).
class AdaptiveKeyboardDismissal extends StatefulWidget {
  const AdaptiveKeyboardDismissal({super.key, required this.child});

  final Widget child;

  /// Closes the keyboard: the text field that has the focus loses it, and a
  /// keyboard that is still up without a text field to type in, such as one
  /// left up by a field that went away while it had the focus, is hidden.
  /// Does nothing while there is no keyboard.
  static void dismiss() {
    final focus = FocusManager.instance.primaryFocus;
    if (focus != null && _isTextField(focus)) focus.unfocus();
    if (_keyboardShows) {
      SystemChannels.textInput.invokeMethod<void>('TextInput.hide');
    }
  }

  /// Whether [node] is the focus of a text field.
  static bool _isTextField(FocusNode node) =>
      node.context?.findAncestorStateOfType<EditableTextState>() != null;

  /// Whether the keyboard takes room at the bottom of a window.
  static bool get _keyboardShows => WidgetsBinding
      .instance
      .platformDispatcher
      .views
      .any((view) => view.viewInsets.bottom > 0);

  @override
  State<AdaptiveKeyboardDismissal> createState() =>
      _AdaptiveKeyboardDismissalState();
}

class _AdaptiveKeyboardDismissalState extends State<AdaptiveKeyboardDismissal> {
  /// Where each press that may still turn out a tap outside the text fields
  /// went down. A press on a text field, or one that moves too far to be a
  /// tap, is left out.
  final _presses = <int, Offset>{};

  void _onPointerDown(PointerDownEvent event) {
    if (!_keyboardMayShow || _isOnTextField(event)) return;
    _presses[event.pointer] = event.position;
  }

  void _onPointerMove(PointerMoveEvent event) {
    final down = _presses[event.pointer];
    if (down == null) return;
    final slop = computeHitSlop(
      event.kind,
      MediaQuery.maybeGestureSettingsOf(context),
    );
    if ((event.position - down).distance > slop) {
      _presses.remove(event.pointer);
    }
  }

  void _onPointerUp(PointerUpEvent event) {
    if (_presses.remove(event.pointer) != null) {
      AdaptiveKeyboardDismissal.dismiss();
    }
  }

  void _onPointerCancel(PointerCancelEvent event) =>
      _presses.remove(event.pointer);

  /// Whether a text field has the focus or the keyboard is up: only then is a
  /// press looked at.
  bool get _keyboardMayShow {
    final focus = FocusManager.instance.primaryFocus;
    return (focus != null && AdaptiveKeyboardDismissal._isTextField(focus)) ||
        AdaptiveKeyboardDismissal._keyboardShows;
  }

  /// Whether [event] went down on a text field or on what belongs to it.
  bool _isOnTextField(PointerDownEvent event) {
    final result = HitTestResult();
    WidgetsBinding.instance.hitTestInView(result, event.position, event.viewId);
    return result.path.any((entry) {
      final target = entry.target;
      return target is RenderTapRegion && target.groupId == EditableText;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: _onPointerDown,
      onPointerMove: _onPointerMove,
      onPointerUp: _onPointerUp,
      onPointerCancel: _onPointerCancel,
      child: widget.child,
    );
  }
}
