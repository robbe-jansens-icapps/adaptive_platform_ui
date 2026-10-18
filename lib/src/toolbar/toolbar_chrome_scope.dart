import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

/// Tells the pages below an [AdaptiveToolbarHost] which parts of the toolbar
/// the host is drawing for them right now, so they do not draw the same parts
/// themselves.
///
/// The host is the single source of truth for the layout decision: a page
/// never has to agree with it by measuring the device a second time.
class ToolbarChromeScope extends InheritedWidget {
  const ToolbarChromeScope({
    super.key,
    required this.hostsToolbar,
    required this.hostsDuoControls,
    this.hostsBottomTabBar = false,
    this.tabBarHeight,
    this.tabAccessoryHeight,
    required super.child,
  });

  /// True while the host draws the top toolbar (title, back button, actions)
  /// for every page in one fixed bar. Pages then draw no toolbar of their own
  /// and only keep their content clear of it.
  final bool hostsToolbar;

  /// True while the host shows the page's controls (back button, actions) in
  /// the fixed vertical bar of iPhone Duo, on whichever edge the pose puts it
  /// (see `DuoPose`). Pages then keep only their title at the top.
  final bool hostsDuoControls;

  /// True while the host draws the native tab bar of a tab layout at the
  /// bottom of the screen, above the navigator: it stays put while pages are
  /// pushed over the tabs and popped, and fades out and in with them, instead
  /// of moving with the page under a page that slides over it. The scaffold
  /// with the tabs then draws no tab bar of its own.
  final bool hostsBottomTabBar;

  /// The height the hosted tab bar covers at the bottom of the screen, once
  /// measured, for the tab layout to keep its content clear of it.
  final ValueListenable<double>? tabBarHeight;

  /// How much of [tabBarHeight] the tab accessory takes on a tray with the
  /// tabs, or where a tray would put it on a page's own sheet
  /// ([AdaptiveTabAccessoryLayout.tray], [AdaptiveTabAccessoryLayout.onSheet]):
  /// the band above the tabs it and the room around it keep. 0 elsewhere.
  final ValueListenable<double>? tabAccessoryHeight;

  /// The nearest scope, or null when no host is installed and the page must
  /// draw its whole toolbar itself.
  static ToolbarChromeScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<ToolbarChromeScope>();

  @override
  bool updateShouldNotify(ToolbarChromeScope oldWidget) =>
      hostsToolbar != oldWidget.hostsToolbar ||
      hostsDuoControls != oldWidget.hostsDuoControls ||
      hostsBottomTabBar != oldWidget.hostsBottomTabBar ||
      tabBarHeight != oldWidget.tabBarHeight ||
      tabAccessoryHeight != oldWidget.tabAccessoryHeight;
}
