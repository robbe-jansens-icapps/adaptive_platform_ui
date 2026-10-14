import 'package:flutter/widgets.dart';

import '../toolbar/duo_top_strip.dart';
import '../toolbar/duo_vertical_bar.dart';
import '../toolbar/hosted_top_toolbar.dart';
import '../widgets/adaptive_app_bar.dart';
import '../widgets/adaptive_app_bar_action.dart';
import '../widgets/adaptive_glass.dart';
import '../widgets/adaptive_scaffold.dart';

/// Where the toolbar host puts the bars of an app with custom chrome.
///
/// The host decides it once, from the window and the device, and the pages
/// and the app's builders read it from [AdaptiveChromeScope].
enum AdaptiveChromePlacement {
  /// Tabs in a bar along the bottom, the toolbar along the top: phones, and
  /// any window too narrow for anything else.
  bottom,

  /// The iPhone Duo with its bars on the side (the cover display, the inner
  /// display held sideways, a Split View pane): tabs and controls in a
  /// vertical bar beside the content, the title at the top.
  vertical,

  /// The iPhone Duo inner display held upright: the tabs in the strip along
  /// the top, beside the camera and status cluster.
  topStrip,

  /// A wide window (an iPad, an unfolded foldable): the tabs in a sidebar
  /// along the leading edge, the toolbar along the top beside it.
  sidebar,
}

/// The tabs as one of the app's tab bars draws them.
@immutable
class AdaptiveTabBarSpec {
  const AdaptiveTabBarSpec({
    required this.placement,
    required this.items,
    required this.selectedIndex,
    required this.onTap,
    this.data,
  });

  final AdaptiveChromePlacement placement;
  final List<AdaptiveNavigationDestination> items;
  final int selectedIndex;
  final ValueChanged<int> onTap;

  /// [AdaptiveBottomNavigationBar.chromeData], for the app's own settings.
  final Object? data;

  /// Vertical in the iPhone Duo's vertical bar, horizontal anywhere else.
  Axis get axis => placement == AdaptiveChromePlacement.vertical ? Axis.vertical : Axis.horizontal;
}

/// A page's title, as the app's title draws it.
@immutable
class AdaptiveTitleSpec {
  const AdaptiveTitleSpec({
    required this.placement,
    this.title,
    this.subtitle,
    this.titleWidget,
    this.centered = false,
    this.data,
  });

  final AdaptiveChromePlacement placement;
  final String? title;
  final String? subtitle;

  /// [AdaptiveAppBar.titleWidget]: the page brought a title of its own.
  final Widget? titleWidget;

  /// Whether the bar centres the title, rather than putting it at the leading
  /// edge ([AdaptiveChrome.centerTitle]; never in the iPhone Duo title band).
  final bool centered;

  /// [AdaptiveAppBar.chromeData].
  final Object? data;
}

/// The back button of a page.
@immutable
class AdaptiveBackButtonSpec {
  const AdaptiveBackButtonSpec({
    required this.placement,
    required this.style,
    required this.onPressed,
    this.data,
  });

  final AdaptiveChromePlacement placement;

  /// A chevron, or a cross for a page shown like a dialog.
  final AdaptiveBackButtonStyle style;
  final VoidCallback onPressed;

  /// [AdaptiveAppBar.chromeData] of the page the button goes back from.
  final Object? data;
}

/// One group of a page's actions, as the app draws them.
@immutable
class AdaptiveActionsSpec {
  const AdaptiveActionsSpec({
    required this.placement,
    required this.actions,
    required this.axis,
    required this.onPressed,
    this.overflow = false,
    this.tint,
    this.data,
  });

  final AdaptiveChromePlacement placement;
  final List<AdaptiveAppBarAction> actions;

  /// How the group runs: along a bar at the top, or down the iPhone Duo's
  /// vertical bar.
  final Axis axis;

  /// Performs [actions]`[i]`, opening its menu next to [anchor] if it has one.
  /// Hand it the context of the control that was pressed.
  final void Function(AdaptiveAppBarAction action, BuildContext anchor) onPressed;

  /// Whether this is the one control holding the actions that did not fit,
  /// which shows a menu of all of them.
  final bool overflow;

  /// [AdaptiveAppBar.tintColor].
  final Color? tint;

  /// [AdaptiveAppBar.chromeData].
  final Object? data;
}

/// What sits behind a page's bar, so its title and controls read over
/// content that scrolls underneath.
@immutable
class AdaptiveBarBackgroundSpec {
  const AdaptiveBarBackgroundSpec({
    required this.placement,
    required this.height,
    this.color,
    this.titleBand = false,
    this.data,
  });

  final AdaptiveChromePlacement placement;

  /// How far down the bar reaches from the top of the window.
  final double height;

  /// [AdaptiveAppBar.backdropColor]: the colour of the page underneath.
  final Color? color;

  /// The iPhone Duo's title band rather than a whole bar.
  final bool titleBand;

  /// [AdaptiveAppBar.chromeData].
  final Object? data;
}

typedef AdaptiveTabBarBuilder = Widget Function(BuildContext context, AdaptiveTabBarSpec spec);
typedef AdaptiveTitleBuilder = Widget Function(BuildContext context, AdaptiveTitleSpec spec);
typedef AdaptiveBackButtonBuilder = Widget Function(BuildContext context, AdaptiveBackButtonSpec spec);
typedef AdaptiveActionsBuilder = Widget Function(BuildContext context, AdaptiveActionsSpec spec);
typedef AdaptiveBarBackgroundBuilder = Widget Function(BuildContext context, AdaptiveBarBackgroundSpec spec);

/// Sizes the custom chrome lays out with. The defaults are the system's.
@immutable
class AdaptiveChromeMetrics {
  const AdaptiveChromeMetrics({this.toolbarHeight = kHostedToolbarHeight, this.backButtonSize = kHostedToolbarHeight});

  /// Height of the toolbar along the top, below the status bar.
  final double toolbarHeight;

  /// The room the back button takes, square.
  final double backButtonSize;

  @override
  bool operator ==(Object other) =>
      other is AdaptiveChromeMetrics && other.toolbarHeight == toolbarHeight && other.backButtonSize == backButtonSize;

  @override
  int get hashCode => Object.hash(toolbarHeight, backButtonSize);
}

/// Bars drawn by the app, placed by the toolbar host: custom chrome.
///
/// Handed to [AdaptiveToolbarHost.chrome], it replaces the native iOS 26
/// bars on every platform with the app's own widgets, for an app whose brand
/// decides how its bars look. The host still decides where everything goes,
/// the same way it does for the native bars: the tabs at the bottom, on the
/// side of the iPhone Duo, in its top strip or in a sidebar; the toolbar
/// along the top, its title in the iPhone Duo title band and its controls in
/// the vertical bar. Pages keep using [AdaptiveScaffold] with an
/// [AdaptiveAppBar] and an [AdaptiveBottomNavigationBar], and keep their
/// content clear of the bars through the media query's padding, as they do
/// with the native ones. Each builder is told where its part goes through
/// its spec.
@immutable
class AdaptiveChrome {
  const AdaptiveChrome({
    required this.tabBarBuilder,
    required this.titleBuilder,
    required this.backButtonBuilder,
    required this.actionsBuilder,
    this.barBackgroundBuilder,
    this.centerTitle,
    this.glass = const AdaptiveGlassStyle(),
    this.metrics = const AdaptiveChromeMetrics(),
  });

  /// The tab bar of a tab layout: a bar along the bottom, or a vertical one.
  /// Its size is measured, and the pages keep clear of it.
  final AdaptiveTabBarBuilder tabBarBuilder;

  /// A page's title, in the toolbar or the iPhone Duo title band.
  final AdaptiveTitleBuilder titleBuilder;

  /// The back button, which stays put while pages that both have one come
  /// and go.
  final AdaptiveBackButtonBuilder backButtonBuilder;

  /// A group of a page's actions.
  final AdaptiveActionsBuilder actionsBuilder;

  /// Behind the toolbar. A soft gradient in the page's colour when null, as
  /// behind the native bar.
  final AdaptiveBarBackgroundBuilder? barBackgroundBuilder;

  /// Whether titles are centred in the toolbar: on iOS when null, as the
  /// system does, and at the leading edge elsewhere.
  final bool? centerTitle;

  /// The glass of every [AdaptiveGlass] below the host that brings none of
  /// its own: the app's builders and its sheets.
  final AdaptiveGlassStyle glass;

  final AdaptiveChromeMetrics metrics;

  bool centersTitle(TargetPlatform platform) =>
      centerTitle ?? (platform == TargetPlatform.iOS || platform == TargetPlatform.macOS);
}

/// The placement the toolbar host settled on, and its custom chrome if it
/// has any. Always there below a host, so the tree does not change shape
/// between placements.
class AdaptiveChromeScope extends InheritedWidget {
  const AdaptiveChromeScope({super.key, required this.chrome, required this.placement, required super.child});

  /// The app's bars; null where the host draws the native ones.
  final AdaptiveChrome? chrome;

  final AdaptiveChromePlacement placement;

  static AdaptiveChromeScope? maybeOf(BuildContext context) => context.dependOnInheritedWidgetOfExactType<AdaptiveChromeScope>();

  /// The custom chrome of the host above, if any.
  static AdaptiveChrome? chromeOf(BuildContext context) => maybeOf(context)?.chrome;

  /// Where the bars are. [AdaptiveChromePlacement.bottom] without a host.
  static AdaptiveChromePlacement placementOf(BuildContext context) => maybeOf(context)?.placement ?? AdaptiveChromePlacement.bottom;

  @override
  bool updateShouldNotify(AdaptiveChromeScope oldWidget) => chrome != oldWidget.chrome || placement != oldWidget.placement;
}

/// The one placement the host settles on: the iPhone Duo's own poses first,
/// then the bottom.
AdaptiveChromePlacement resolveChromePlacement({required DuoPose? pose, required DuoTopStrip? strip}) {
  if (pose != null) return AdaptiveChromePlacement.vertical;
  if (strip != null) return AdaptiveChromePlacement.topStrip;
  return AdaptiveChromePlacement.bottom;
}
