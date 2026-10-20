import 'package:flutter/scheduler.dart';

/// Runs [update] at once, or once the frame is done when it comes while the
/// frame builds or lays out the widgets.
///
/// A scroll can start while a page is laid out: its list springs back into
/// place as the window changes, the device turned. What follows the scroll may
/// not be built anew until the frame is done. [mounted] is asked then, and
/// [update] is left undone for a widget that has gone.
void runOutsideLayout(VoidCallback update, {required bool Function() mounted}) {
  if (SchedulerBinding.instance.schedulerPhase !=
      SchedulerPhase.persistentCallbacks) {
    update();
    return;
  }
  SchedulerBinding.instance.addPostFrameCallback((_) {
    if (mounted()) update();
  });
}
