import 'package:flutter/cupertino.dart';
import 'adaptive_scaffold.dart';

/// Configuration for an adaptive bottom navigation bar
///
/// This class holds the configuration for the bottom navigation bar in [AdaptiveScaffold].
/// The actual rendering is platform-specific:
/// - iOS 26+ with useNativeBottomBar: Native UITabBar with Liquid Glass effects
/// - iOS 26+ without useNativeBottomBar: CupertinoTabBar (custom or auto-generated)
/// - iOS <26: CupertinoTabBar (custom or auto-generated)
/// - Android: NavigationBar (custom or auto-generated)
///
/// You can provide custom bottom navigation bars using [cupertinoTabBar] or [bottomNavigationBar]:
/// - If [cupertinoTabBar] is provided: Uses custom CupertinoTabBar on iOS (when useNativeBottomBar is false or iOS <26)
/// - If [bottomNavigationBar] is provided: Uses custom NavigationBar/BottomNavigationBar on Android
/// - Otherwise: Builds bottom navigation bar from [items]
class AdaptiveBottomNavigationBar {
  /// Creates an adaptive bottom navigation bar configuration
  const AdaptiveBottomNavigationBar({
    this.items,
    this.selectedIndex,
    this.onTap,
    this.useNativeBottomBar = true,
    this.cupertinoTabBar,
    this.bottomNavigationBar,
    this.selectedItemColor,
    this.unselectedItemColor,
    this.hidesWhenPushed = false,
    this.hidesFor,
    this.chromeData,
    this.accessory,
  });

  /// Navigation items for bottom navigation bar
  /// These will be used to build the platform-specific navigation items if custom
  /// bars are not provided.
  final List<AdaptiveNavigationDestination>? items;

  /// Currently selected item index
  /// If null, no item will be selected
  final int? selectedIndex;

  /// Called when a navigation item is tapped
  /// If null, navigation will not be interactive
  final ValueChanged<int>? onTap;

  /// Use native iOS 26 bottom bar (iOS 26+ only)
  /// - When true (default): Uses native iOS 26 UITabBar with Liquid Glass effect
  /// - When false: Uses CupertinoTabBar (custom if provided, otherwise auto-generated)
  ///
  /// For iOS <26, this parameter is ignored and CupertinoTabBar is always used.
  ///
  /// If true, [cupertinoTabBar] will be ignored on iOS 26+ and native tab bar will be shown.
  /// For iOS <26, if [cupertinoTabBar] is provided, it will be used regardless of this setting.
  final bool useNativeBottomBar;

  /// Custom CupertinoTabBar for iOS
  ///
  /// When provided:
  /// - iOS 26+ with useNativeBottomBar=false: Uses this custom tab bar
  /// - iOS 26+ with useNativeBottomBar=true: Ignored, native tab bar is shown
  /// - iOS <26: Always uses this custom tab bar
  ///
  /// If not provided, a tab bar will be auto-generated from [items].
  ///
  /// Ignored on Android platforms.
  final CupertinoTabBar? cupertinoTabBar;

  /// Custom NavigationBar or BottomNavigationBar for Android
  ///
  /// When provided, this custom navigation bar will be used instead of building one
  /// from [items].
  ///
  /// Ignored on iOS platforms.
  final Widget? bottomNavigationBar;

  /// Color for the selected navigation item
  ///
  /// When provided:
  /// - iOS (native/CupertinoTabBar): Sets activeColor
  /// - Android (NavigationBar): Sets indicatorColor
  ///
  /// If null, uses platform defaults.
  final Color? selectedItemColor;

  /// Color for unselected navigation items
  ///
  /// When provided:
  /// - iOS (native/CupertinoTabBar): Sets inactiveColor
  /// - Android (NavigationBar): Not directly supported, but can affect icon colors
  ///
  /// If null, uses platform defaults.
  final Color? unselectedItemColor;

  /// Whether the tabs leave while a page pushed inside the tab layout is in
  /// front, as UIKit's `hidesBottomBarWhenPushed` does: a page opened on the
  /// navigator of a tab, rather than over the whole tab layout. They fade out
  /// with the push and back in with the pop, following a back swipe, and the
  /// page gets the room at the bottom. Only with custom chrome
  /// ([AdaptiveToolbarHost.chrome]); a sidebar stays.
  final bool hidesWhenPushed;

  /// Which of the pages pushed inside the tab layout the tabs leave for, with
  /// [hidesWhenPushed]: asked about the route of each page pushed between the
  /// tabs and the page in front, and every one of them when null. The tabs
  /// stay for the pages it says no to, unless such a page is pushed above
  /// one it picks: they stay away until that one is popped, as with UIKit.
  final RoutePredicate? hidesFor;

  /// Anything the app's custom chrome wants to know about these tabs, handed
  /// to its tab bar builder as [AdaptiveTabBarSpec.data].
  final Object? chromeData;

  /// Shown with the tabs, as the accessory of a tab bar on iOS 26 (Music's
  /// mini player): above a tab bar at the bottom, floating at the bottom of
  /// the content where the tabs are on the side or at the top, and at the
  /// bottom of a sidebar. It keeps its state as it moves between them, and
  /// comes and goes with the tabs. Only with custom chrome
  /// ([AdaptiveToolbarHost.chrome]), which frames it
  /// ([AdaptiveChrome.accessoryBuilder]).
  final Widget? accessory;

  /// Creates a copy of this bottom navigation bar with the given fields replaced
  AdaptiveBottomNavigationBar copyWith({
    List<AdaptiveNavigationDestination>? items,
    int? selectedIndex,
    ValueChanged<int>? onTap,
    bool? useNativeBottomBar,
    CupertinoTabBar? cupertinoTabBar,
    Widget? bottomNavigationBar,
    Color? selectedItemColor,
    Color? unselectedItemColor,
    bool? hidesWhenPushed,
    RoutePredicate? hidesFor,
    Object? chromeData,
    Widget? accessory,
  }) {
    return AdaptiveBottomNavigationBar(
      items: items ?? this.items,
      selectedIndex: selectedIndex ?? this.selectedIndex,
      onTap: onTap ?? this.onTap,
      useNativeBottomBar: useNativeBottomBar ?? this.useNativeBottomBar,
      cupertinoTabBar: cupertinoTabBar ?? this.cupertinoTabBar,
      bottomNavigationBar: bottomNavigationBar ?? this.bottomNavigationBar,
      selectedItemColor: selectedItemColor ?? this.selectedItemColor,
      unselectedItemColor: unselectedItemColor ?? this.unselectedItemColor,
      hidesWhenPushed: hidesWhenPushed ?? this.hidesWhenPushed,
      hidesFor: hidesFor ?? this.hidesFor,
      chromeData: chromeData ?? this.chromeData,
      accessory: accessory ?? this.accessory,
    );
  }
}
