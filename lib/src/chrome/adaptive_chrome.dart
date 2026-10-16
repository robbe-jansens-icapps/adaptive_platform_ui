import 'package:flutter/foundation.dart' show ValueListenable;
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

  /// The iPhone Duo inner display held upright, for a chrome that asks for it
  /// ([AdaptiveChrome.tabsInTopStrip]): the tabs in the strip along the top,
  /// beside the camera and status cluster. Without it they stay at the
  /// bottom, as the system's tab bar does there.
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
    this.minimized = const AlwaysStoppedListenable<bool>(false),
    this.data,
  });

  final AdaptiveChromePlacement placement;
  final List<AdaptiveNavigationDestination> items;
  final int selectedIndex;
  final ValueChanged<int> onTap;

  /// Whether the bar should make itself smaller for now, as the tab layout's
  /// `AdaptiveScaffold.minimizeBehavior` asks while its page scrolls. The
  /// app's bar draws that itself; the host does not shrink it.
  final ValueListenable<bool> minimized;

  /// [AdaptiveBottomNavigationBar.chromeData], for the app's own settings.
  final Object? data;

  /// Vertical in the iPhone Duo's vertical bar, horizontal anywhere else.
  Axis get axis => placement == AdaptiveChromePlacement.vertical ? Axis.vertical : Axis.horizontal;
}

/// The tabs as the app's sidebar draws them, along the leading edge of a
/// wide window.
@immutable
class AdaptiveSidebarSpec {
  const AdaptiveSidebarSpec({
    required this.items,
    required this.selectedIndex,
    required this.onTap,
    required this.expanded,
    required this.overlaid,
    required this.onToggle,
    required this.padding,
    this.accessory,
    this.data,
  });

  final List<AdaptiveNavigationDestination> items;
  final int selectedIndex;
  final ValueChanged<int> onTap;

  /// Whether the sidebar is at its full width, with room for labels, rather
  /// than a slim rail of icons. It eases between the two: draw for the
  /// width the sidebar is given.
  final bool expanded;

  /// Whether the user expanded it over the content of a window too narrow to
  /// keep it beside it. A tap outside it, or on a tab, collapses it again.
  final bool overlaid;

  /// Expands or collapses the sidebar, for a control of the app's own.
  final VoidCallback onToggle;

  /// What to keep clear of: the status bar, the home indicator, and on an
  /// iPad window the window controls in its top corner.
  final EdgeInsets padding;

  /// The tab layout's accessory ([AdaptiveBottomNavigationBar.accessory]),
  /// already framed: dock it at the bottom of the sidebar. Keep it in the
  /// tree as it is, so it keeps its state.
  final Widget? accessory;

  /// [AdaptiveBottomNavigationBar.chromeData].
  final Object? data;
}

/// Where a tab accessory goes, for the frame the app draws around it.
@immutable
class AdaptiveAccessorySpec {
  const AdaptiveAccessorySpec({
    required this.placement,
    required this.compact,
    this.room = double.infinity,
  });

  final AdaptiveChromePlacement placement;

  /// Whether there is little room for it: beside the iPhone Duo's vertical
  /// bar, or in a sidebar collapsed to a rail.
  final bool compact;

  /// How tall it may be: in the iPhone Duo's vertical bar, what the page's
  /// controls and the tabs leave of it, as the page's controls come first.
  /// An accessory taller than this takes a smaller form, or none, rather
  /// than moving the page's controls into the overflow menu. Unbounded
  /// elsewhere.
  final double room;
}

/// What a popover sits on, for the surface the app draws
/// ([AdaptiveChrome.popoverBuilder]).
@immutable
class AdaptivePopoverSpec {
  const AdaptivePopoverSpec({required this.sheet, this.data});

  /// Whether it opens as a sheet from the bottom, on a compact window,
  /// rather than anchored to its control.
  final bool sheet;

  /// What the code that opened it handed `AdaptivePopover.show` as
  /// `chromeData`, such as a dark or a light look.
  final Object? data;
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
  /// edge ([AdaptiveChrome.centerTitle]; in the iPhone Duo title band
  /// [AdaptiveChrome.centerTitleBand]).
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
    this.scrollEdge = const AlwaysStoppedListenable<double>(0),
    this.data,
  });

  final AdaptiveChromePlacement placement;

  /// A chevron, or a cross for a page shown like a dialog.
  final AdaptiveBackButtonStyle style;
  final VoidCallback onPressed;

  /// How far the page's content has scrolled under the bar (see
  /// [AdaptiveScrollEdge]), for a control that only needs a surface of its
  /// own once there is content behind it.
  final ValueListenable<double> scrollEdge;

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
    this.showOverflow,
    this.tint,
    this.scrollEdge = const AlwaysStoppedListenable<double>(0),
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

  /// For the [overflow] control: opens the menu of [actions] next to
  /// [anchor], the control pressed, and performs the one picked.
  final void Function(BuildContext anchor)? showOverflow;

  /// [AdaptiveAppBar.tintColor].
  final Color? tint;

  /// How far the page's content has scrolled under the bar (see
  /// [AdaptiveScrollEdge]).
  final ValueListenable<double> scrollEdge;

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
    this.pinned = false,
    this.hairline = true,
    this.scrollEdge = const AlwaysStoppedListenable<double>(0),
    this.data,
  });

  final AdaptiveChromePlacement placement;

  /// How far the bar reaches down from the top of the window, including
  /// what a page pins below it ([AdaptiveSafeAreaBar]).
  final double height;

  /// How far the page's content has scrolled under the bar (see
  /// [AdaptiveScrollEdge]). The host already fades the background in with
  /// it.
  final ValueListenable<double> scrollEdge;

  /// [AdaptiveAppBar.backdropColor]: the colour of the page underneath.
  final Color? color;

  /// The iPhone Duo's title band rather than a whole bar.
  final bool titleBand;

  /// Whether the page pins something below the bar that the background
  /// reaches behind, such as a search field or tabs
  /// ([AdaptiveSafeAreaBar]): a bar that holds more than its controls reads
  /// as one surface with it.
  final bool pinned;

  /// Whether it ends in a hairline along its bottom edge: off for a page
  /// whose bar runs on into something docked below it
  /// ([AdaptiveAppBar.showsHairline]).
  final bool hairline;

  /// [AdaptiveAppBar.chromeData].
  final Object? data;
}

typedef AdaptiveTabBarBuilder = Widget Function(BuildContext context, AdaptiveTabBarSpec spec);
typedef AdaptiveTitleBuilder = Widget Function(BuildContext context, AdaptiveTitleSpec spec);
typedef AdaptiveBackButtonBuilder = Widget Function(BuildContext context, AdaptiveBackButtonSpec spec);
typedef AdaptiveActionsBuilder = Widget Function(BuildContext context, AdaptiveActionsSpec spec);
typedef AdaptiveBarBackgroundBuilder = Widget Function(BuildContext context, AdaptiveBarBackgroundSpec spec);
typedef AdaptiveSidebarBuilder = Widget Function(BuildContext context, AdaptiveSidebarSpec spec);
typedef AdaptiveAccessoryBuilder = Widget Function(BuildContext context, AdaptiveAccessorySpec spec, Widget accessory);
typedef AdaptivePopoverBuilder = Widget Function(BuildContext context, AdaptivePopoverSpec spec, Widget content);

/// Sizes the custom chrome lays out with. The defaults are the system's.
@immutable
class AdaptiveChromeMetrics {
  const AdaptiveChromeMetrics({
    this.toolbarHeight = kHostedToolbarHeight,
    this.backButtonSize = kHostedToolbarHeight,
    this.sidebarMinWindowWidth = 700,
    this.sidebarExpandedWindowWidth = 1024,
    this.sidebarWidth = 300,
    this.sidebarCollapsedWidth = 88,
    this.controlInset = 16,
  });

  /// Height of the toolbar along the top, below the status bar.
  final double toolbarHeight;

  /// The room the back button takes, square.
  final double backButtonSize;

  /// From this window width on, the tabs are in a sidebar
  /// ([AdaptiveChrome.sidebarBuilder]): an iPad, an unfolded foldable. The
  /// iPhone Duo keeps its own placements at any width.
  final double sidebarMinWindowWidth;

  /// From this window width on, the sidebar is at its full width by default;
  /// below it, a slim rail of icons that the user can expand over the
  /// content.
  final double sidebarExpandedWindowWidth;

  /// The sidebar at its full width.
  final double sidebarWidth;

  /// The sidebar collapsed to a rail of icons.
  final double sidebarCollapsedWidth;

  /// Room between the side of a bar and the controls in it: the back button
  /// and the actions. A title with no control beside it keeps to the page's
  /// margin instead.
  final double controlInset;

  @override
  bool operator ==(Object other) =>
      other is AdaptiveChromeMetrics &&
      other.toolbarHeight == toolbarHeight &&
      other.backButtonSize == backButtonSize &&
      other.sidebarMinWindowWidth == sidebarMinWindowWidth &&
      other.sidebarExpandedWindowWidth == sidebarExpandedWindowWidth &&
      other.sidebarWidth == sidebarWidth &&
      other.sidebarCollapsedWidth == sidebarCollapsedWidth &&
      other.controlInset == controlInset;

  @override
  int get hashCode => Object.hash(
    toolbarHeight,
    backButtonSize,
    sidebarMinWindowWidth,
    sidebarExpandedWindowWidth,
    sidebarWidth,
    sidebarCollapsedWidth,
    controlInset,
  );
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
    this.sidebarBuilder,
    this.accessoryBuilder,
    this.popoverBuilder,
    this.centerTitle,
    this.centerTitleBand = false,
    this.tabsInTopStrip = false,
    this.keepsTabsInVerticalBar = false,
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

  /// Behind the toolbar along the top. [AdaptiveBarBackdrop] in the page's
  /// colour when null, as behind the native bar. Either way it fades in as
  /// soon as the page's content scrolls under it, as the system's scroll edge
  /// effect does, and is gone while nothing is underneath.
  final AdaptiveBarBackgroundBuilder? barBackgroundBuilder;

  /// The tabs in a sidebar along the leading edge of a wide window
  /// ([AdaptiveChromeMetrics.sidebarMinWindowWidth]). It stays while pages
  /// are pushed inside the tab layout, and the pages and their toolbar sit
  /// beside it. Null keeps the tab bar at the bottom at any width.
  final AdaptiveSidebarBuilder? sidebarBuilder;

  /// The frame around a tab layout's accessory
  /// ([AdaptiveBottomNavigationBar.accessory]), for each placement: a strip
  /// above the tab bar, a floating capsule, a card in a sidebar. The
  /// accessory as it is when null.
  final AdaptiveAccessoryBuilder? accessoryBuilder;

  /// The surface of every `AdaptivePopover` below the host, and of the menus
  /// of the app's actions, which open as popovers: anchored, or as a sheet
  /// on a compact window. Glass when null.
  final AdaptivePopoverBuilder? popoverBuilder;

  /// Whether titles are centred in the toolbar: on iOS when null, as the
  /// system does, and at the leading edge elsewhere.
  final bool? centerTitle;

  /// Whether the title in the iPhone Duo's title band is centred over the
  /// page, as the app's own bars centre theirs, rather than at the leading
  /// edge, where the system sets it.
  final bool centerTitleBand;

  /// Whether the tabs go in the iPhone Duo's top strip, beside the camera and
  /// status cluster, while its inner display is held upright
  /// ([AdaptiveChromePlacement.topStrip]). By default they stay along the
  /// bottom there, at full size, as the system's tab bar does, and the
  /// toolbar sits in the strip.
  final bool tabsInTopStrip;

  /// Whether the tabs in the iPhone Duo's vertical bar stay while a page is
  /// pushed inside the tab layout, as they do in a sidebar, rather than
  /// leaving as [AdaptiveBottomNavigationBar.hidesWhenPushed] has them leave
  /// a bar along the bottom. The page's controls keep above them.
  final bool keepsTabsInVerticalBar;

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
  const AdaptiveChromeScope({
    super.key,
    required this.chrome,
    required this.placement,
    this.sidebarInset = const AlwaysStoppedListenable(0),
    this.floatingAccessoryHeight = const AlwaysStoppedListenable(0),
    required super.child,
  });

  /// The app's bars; null where the host draws the native ones.
  final AdaptiveChrome? chrome;

  final AdaptiveChromePlacement placement;

  /// How much room the sidebar takes at the leading edge of the pages in the
  /// tab layout, as it eases between its widths; 0 without one.
  final ValueListenable<double> sidebarInset;

  /// The room a tab accessory floating at the bottom of the content takes
  /// there, where the tabs are on the side or at the top; 0 without one.
  final ValueListenable<double> floatingAccessoryHeight;

  /// [sidebarInset] of the host above; 0 without one.
  static ValueListenable<double> sidebarInsetOf(BuildContext context) =>
      maybeOf(context)?.sidebarInset ?? const AlwaysStoppedListenable(0);

  static AdaptiveChromeScope? maybeOf(BuildContext context) => context.dependOnInheritedWidgetOfExactType<AdaptiveChromeScope>();

  /// The custom chrome of the host above, if any.
  static AdaptiveChrome? chromeOf(BuildContext context) => maybeOf(context)?.chrome;

  /// Where the bars are. [AdaptiveChromePlacement.bottom] without a host.
  static AdaptiveChromePlacement placementOf(BuildContext context) => maybeOf(context)?.placement ?? AdaptiveChromePlacement.bottom;

  @override
  bool updateShouldNotify(AdaptiveChromeScope oldWidget) =>
      chrome != oldWidget.chrome ||
      placement != oldWidget.placement ||
      sidebarInset != oldWidget.sidebarInset ||
      floatingAccessoryHeight != oldWidget.floatingAccessoryHeight;
}

/// A [ValueListenable] that never changes.
class AlwaysStoppedListenable<T> implements ValueListenable<T> {
  const AlwaysStoppedListenable(this.value);

  @override
  final T value;

  @override
  void addListener(VoidCallback listener) {}

  @override
  void removeListener(VoidCallback listener) {}
}

/// The one placement the host settles on: the iPhone Duo's own poses first,
/// then a sidebar on a wide window, then the bottom.
AdaptiveChromePlacement resolveChromePlacement({
  required DuoPose? pose,
  required DuoTopStrip? strip,
  double width = 0,
  AdaptiveChrome? chrome,
}) {
  if (pose != null) return AdaptiveChromePlacement.vertical;
  if (strip != null && (chrome?.tabsInTopStrip ?? true)) return AdaptiveChromePlacement.topStrip;
  if (chrome?.sidebarBuilder != null && width >= chrome!.metrics.sidebarMinWindowWidth) {
    return AdaptiveChromePlacement.sidebar;
  }
  return AdaptiveChromePlacement.bottom;
}

/// How far a page's content has scrolled under the bars along its top: 0 at
/// rest, 1 once it has scrolled [distance] under them. Custom chrome fades the
/// bar's background in with it and hands it to the app's controls.
abstract final class AdaptiveScrollEdge {
  /// How far content scrolls under the bar before the scroll edge is fully
  /// in.
  static const double distance = 24;

  /// The scroll edge along the top of a scrollable with [metrics], or null
  /// for one that does not run vertically.
  static double? of(ScrollMetrics metrics) {
    if (metrics.axis != Axis.vertical) return null;
    final under = metrics.axisDirection == AxisDirection.up ? metrics.extentAfter : metrics.extentBefore;
    return (under / distance).clamp(0.0, 1.0);
  }
}

/// The room between a custom bar's title and the controls beside it. A
/// title with no control beside it keeps to the bar's margin instead, in line
/// with the page's content.
const double kToolbarTitleSpacing = 12;
