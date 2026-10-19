import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';

import '../toolbar/toolbar_registry.dart';

/// A tab accessory on a page's sheet that opens from it, making way as the
/// sheet's content comes up over it ([covered] from 0 to 1): it is out of
/// sight by the time the content is halfway in, so the two never show at
/// once for long where they lie over each other; it takes no touches once
/// the content starts to show, which then has them, and leaves the
/// semantics tree halfway. With the native tab bar and the Material one.
class AccessoryMakesWay extends StatefulWidget {
  const AccessoryMakesWay({
    super.key,
    required this.covered,
    required this.child,
  });

  final Animation<double> covered;
  final Widget child;

  @override
  State<AccessoryMakesWay> createState() => _AccessoryMakesWayState();
}

class _AccessoryMakesWayState extends State<AccessoryMakesWay> {
  late CurvedAnimation _gone = _goneFor(widget.covered);

  static CurvedAnimation _goneFor(Animation<double> covered) =>
      CurvedAnimation(parent: covered, curve: const Interval(0, 0.5));

  @override
  void didUpdateWidget(AccessoryMakesWay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.covered == widget.covered) return;
    _gone.dispose();
    _gone = _goneFor(widget.covered);
  }

  @override
  void dispose() {
    _gone.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final covered = widget.covered;
    return FadeTransition(
      opacity: ReverseAnimation(_gone),
      child: AnimatedBuilder(
        animation: covered,
        child: widget.child,
        builder: (context, child) => IgnorePointer(
          ignoring: covered.value > 0.05,
          child: ExcludeSemantics(excluding: covered.value > 0.5, child: child),
        ),
      ),
    );
  }
}

/// [child], with vertical drags on it moving the page's [sheet] it opens
/// into, under the finger. Takes no drags without one.
class AccessorySheetDrag extends StatelessWidget {
  const AccessorySheetDrag({
    super.key,
    required this.sheet,
    required this.child,
  });

  final AccessorySheet? sheet;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final sheet = this.sheet;
    return RawGestureDetector(
      gestures: {
        VerticalDragGestureRecognizer:
            GestureRecognizerFactoryWithHandlers<VerticalDragGestureRecognizer>(
              () => VerticalDragGestureRecognizer(debugOwner: this),
              (recognizer) {
                recognizer.onlyAcceptDragOnThreshold = true;
                // From where the finger came down, so the sheet stays under
                // it.
                recognizer.dragStartBehavior = DragStartBehavior.down;
                if (sheet == null) {
                  recognizer
                    ..onStart = null
                    ..onUpdate = null
                    ..onEnd = null;
                  return;
                }
                recognizer
                  ..onStart = ((_) => sheet.dragStart())
                  ..onUpdate = ((details) =>
                      sheet.dragUpdate(-details.primaryDelta!))
                  ..onEnd = ((details) =>
                      sheet.dragEnd(-(details.primaryVelocity ?? 0)));
              },
            ),
      },
      child: child,
    );
  }
}
