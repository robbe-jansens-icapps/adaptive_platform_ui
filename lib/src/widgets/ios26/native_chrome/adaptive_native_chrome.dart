import 'package:flutter/widgets.dart';

import 'native_chrome_navigator_observer.dart';

/// Whether the bars and controls that support it show their native views over
/// the Flutter view on iOS, rather than as platform views inside it.
///
/// With a platform view on screen, iOS draws every Flutter frame through an
/// extra surface per view, presented on the main thread that Dart shares; on
/// older iPhones that costs frames on every transition. Views shown over the
/// Flutter view cost nothing per frame: Flutter keeps an empty placeholder in
/// their place and tells iOS where they are only when that changes.
///
/// Set it once, before `runApp`. Off unless the app is built with
/// `--dart-define=adaptive_native_chrome=true`.
abstract final class AdaptiveNativeChrome {
  static bool enabled = const bool.fromEnvironment('adaptive_native_chrome');

  /// Whether the iPhone Duo's vertical bar shows iOS's own tab bar, with the
  /// labels iOS reveals on a held tab, rather than the glass capsule the bar
  /// composes ([IOS26SystemTabBar]). It takes effect with [enabled] on iOS 27
  /// and later; where iOS lays its tabs out anywhere else, the capsule comes
  /// back on its own.
  ///
  /// On unless the app is built with
  /// `--dart-define=adaptive_system_duo_tab_bar=false`.
  static bool systemDuoTabBar = const bool.fromEnvironment(
    'adaptive_system_duo_tab_bar',
    defaultValue: true,
  );

  /// For the app's navigator (`navigatorObservers`): pages sliding over a
  /// page with native views on it cut them off at their edge, and the views
  /// fade out as a dialog comes up over it, rather than Flutter stand-ins
  /// taking their place while pages move or something covers them.
  static final NavigatorObserver navigatorObserver =
      NativeChromeNavigatorObserver();
}
