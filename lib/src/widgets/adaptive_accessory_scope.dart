import 'package:flutter/widgets.dart';

import '../chrome/adaptive_chrome.dart';

/// Tells a tab layout's accessory ([AdaptiveBottomNavigationBar.accessory])
/// where the toolbar host shows it, so it can take the form that fits there:
/// a full capsule above the tabs along the bottom, a round control in the
/// iPhone Duo's vertical bar, where it is [AdaptiveAccessorySpec.compact]
/// and gets what the page's controls leave of the bar
/// ([AdaptiveAccessorySpec.room]).
///
/// The host puts it around the accessory with the native chrome as with an
/// app's own ([AdaptiveToolbarHost.chrome]), so an accessory adapts without
/// a frame of the app's ([AdaptiveChrome.accessoryBuilder]). It is the same
/// widget wherever it is shown, and keeps its state as it moves.
class AdaptiveAccessoryScope extends InheritedWidget {
  const AdaptiveAccessoryScope({
    super.key,
    required this.spec,
    this.expansion,
    required super.child,
  });

  /// Where the accessory is shown, and how much room it has.
  final AdaptiveAccessorySpec spec;

  /// How far the accessory's tray is open into its sheet, where it has one
  /// ([AdaptiveBottomNavigationBar.accessoryExpanded]).
  final AdaptiveTrayExpansion? expansion;

  /// How far the tray of the accessory around [context] is open, and the way
  /// to open and close it; null where it opens into nothing. Does not make
  /// [context] depend on it: listen to [AdaptiveTrayExpansion.value].
  static AdaptiveTrayExpansion? expansionOf(BuildContext context) => context
      .getInheritedWidgetOfExactType<AdaptiveAccessoryScope>()
      ?.expansion;

  /// Where the accessory around [context] is shown, or null outside one.
  static AdaptiveAccessorySpec? maybeOf(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<AdaptiveAccessoryScope>()
      ?.spec;

  /// Where the accessory around [context] is shown. Only for the accessory
  /// itself: throws anywhere else.
  static AdaptiveAccessorySpec of(BuildContext context) {
    final spec = maybeOf(context);
    if (spec == null) {
      throw FlutterError(
        'AdaptiveAccessoryScope.of() was called outside a tab accessory.\n'
        'Only the accessory of an AdaptiveBottomNavigationBar, shown by an '
        'AdaptiveToolbarHost, has one. Use maybeOf() where it may not be one.',
      );
    }
    return spec;
  }

  @override
  bool updateShouldNotify(AdaptiveAccessoryScope oldWidget) =>
      spec != oldWidget.spec || expansion != oldWidget.expansion;
}

/// How far a tab accessory's tray is open into its sheet
/// ([AdaptiveBottomNavigationBar.accessoryExpanded]), and the way to open
/// and close it, as a press on the accessory might.
abstract interface class AdaptiveTrayExpansion {
  /// 0 closed, 1 open, in between while it moves, also under the finger.
  Animation<double> get value;

  /// Whether it is open, or on its way to be.
  bool get isOpen;

  void open();

  void close();

  void toggle();
}
