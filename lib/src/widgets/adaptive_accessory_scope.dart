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
    required super.child,
  });

  /// Where the accessory is shown, and how much room it has.
  final AdaptiveAccessorySpec spec;

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
      spec != oldWidget.spec;
}
