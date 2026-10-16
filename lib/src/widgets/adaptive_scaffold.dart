import 'dart:math' as math;

import 'package:adaptive_platform_ui/src/widgets/ios26/ios26_native_tab_bar.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart'
    show ValueListenable, defaultTargetPlatform, internal;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../chrome/adaptive_chrome.dart';
import '../chrome/scroll_edge_effect.dart';
import '../chrome/sidebar_room.dart';
import '../platform/platform_info.dart';
import '../style/sf_symbol.dart';
import '../toolbar/duo_top_strip.dart';
import '../toolbar/duo_vertical_bar.dart';
import 'adaptive_app_bar.dart';
import 'adaptive_app_bar_action.dart';
import 'adaptive_badge.dart';
import 'adaptive_bottom_navigation_bar.dart';
import 'adaptive_button.dart';
import 'adaptive_popover.dart';
import 'adaptive_split_view.dart';
import 'ios26/ios26_scaffold.dart';
import '../toolbar/toolbar_chrome_scope.dart';
import '../toolbar/toolbar_registry.dart';
import '../utils/size_reporter.dart';

/// Sent to the native tab bar and glass capsule in place of a badge count for
/// a dot without a count (see [AdaptiveNavigationDestination.showsBadgeDot]).
const int kBadgeDot = -1;

/// Navigation destination for bottom navigation
class AdaptiveNavigationDestination {
  const AdaptiveNavigationDestination({
    required this.icon,
    required this.label,
    this.selectedIcon,
    this.isSearch = false,
    this.badgeCount,
    this.showsBadgeDot = false,
    this.badgeText,
    this.badgeColor,
    this.badgeTextColor,
    this.addSpacerAfter = false,
  });

  /// Icon to display.
  ///
  /// Supported values include:
  /// - SF Symbol name `String` for iOS native paths
  /// - `IconData`
  /// - `Widget`
  /// - `ImageProvider` such as `AssetImage`, `FileImage`, or `NetworkImage`
  final dynamic icon;

  /// Label text for the destination
  final String label;

  /// Optional selected state icon.
  ///
  /// Accepts the same value types as [icon], including an SF Symbol name
  /// `String` (e.g. `magazine.fill`) which the iOS 26+ native tab bar applies
  /// when the destination is selected. Falls back to [icon] when null.
  final dynamic selectedIcon;

  /// Whether this is a search tab (iOS 26+)
  /// Search tabs are visually separated and transform into a search field
  final bool isSearch;

  /// Badge count to display on the tab (null means no badge)
  /// On iOS 26+: Uses native UITabBarItem.badgeValue
  /// On iOS <26 and Android: Uses AdaptiveBadge widget
  final int? badgeCount;

  /// Arbitrary badge text, such as "NEW", "!" or a glyph. Takes precedence
  /// over [badgeCount] when non-null.
  ///
  /// - iOS 26+: `UITabBarItem.badgeValue`
  /// - iOS <26 and Android: the label of the [AdaptiveBadge] drawn on the icon
  ///
  /// Tip: combine `badgeText: "●"` with a transparent [badgeColor] and a
  /// [badgeTextColor] to render a dot indicator without a pill background.
  final String? badgeText;

  /// Badge background color. Null means the platform default (system red).
  /// A transparent color removes the pill background, e.g. for a dot.
  ///
  /// - iOS 26+: `UITabBarItem.badgeColor`
  /// - iOS <26 and Android: [AdaptiveBadge.backgroundColor]
  final Color? badgeColor;

  /// Badge text color. Null means the platform default (white).
  ///
  /// - iOS 26+: the badge's text attributes
  /// - iOS <26 and Android: [AdaptiveBadge.textColor]
  final Color? badgeTextColor;

  /// Whether this destination shows a badge on any platform.
  bool get hasBadge =>
      (badgeText != null && badgeText!.isNotEmpty) ||
      (badgeCount != null && badgeCount! > 0);

  /// [child] with this destination's badge drawn on it, for the iOS <26 and
  /// Android tab bars. The native iOS 26+ bar draws its own badge.
  Widget wrapWithBadge(Widget child) => AdaptiveBadge(
    label: badgeText,
    count: badgeText == null ? badgeCount : null,
    backgroundColor: badgeColor,
    textColor: badgeTextColor,
    child: child,
  );

  /// Shows a dot without a count, for something that needs attention but
  /// cannot be counted: the system's own dot on the native tab bar, unlike a
  /// [badgeText] glyph. Ignored while [badgeCount] or [badgeText] is set.
  final bool showsBadgeDot;

  /// The badge as the native views take it: the count, or [kBadgeDot].
  @internal
  int? get nativeBadge => badgeCount ?? (showsBadgeDot ? kBadgeDot : null);

  /// Add flexible space after this tab item (iOS 26+ only)
  /// Useful for creating grouped tabs (e.g., left group and right group)
  /// Only applies to iOS 26+ native tab bar
  final bool addSpacerAfter;
}

/// Tab bar minimize behavior for iOS 26+
enum TabBarMinimizeBehavior {
  /// Never minimize the tab bar
  never,

  /// Minimize when scrolling down
  onScrollDown,

  /// Minimize when scrolling up
  onScrollUp,

  /// Let the system decide
  automatic,

  /// Minimize when scrolling down, and stay minimized until the page is
  /// back at its top. The native tab bar has no such behavior and minimizes
  /// on scrolling down instead.
  onScrollDownUntilTop,
}

/// How much of the bottom of a page the native iOS 26 tab bar of the
/// [AdaptiveScaffold] around it covers. The bar floats over the page, so a
/// page can let a map or a list run underneath it and keep its own controls
/// clear of it (the page's `MediaQuery` bottom padding already includes it).
///
/// 0 where there is no such bar, and on iPhone Duo while the tabs are shown
/// in the trailing vertical bar.
class AdaptiveBottomBarInset extends InheritedWidget {
  const AdaptiveBottomBarInset({
    super.key,
    required this.height,
    required super.child,
  });

  final double height;

  static double of(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<AdaptiveBottomBarInset>()
          ?.height ??
      0;

  @override
  bool updateShouldNotify(AdaptiveBottomBarInset oldWidget) =>
      height != oldWidget.height;
}

/// An adaptive scaffold that renders platform-specific navigation
class AdaptiveScaffold extends StatefulWidget {
  const AdaptiveScaffold({
    super.key,
    this.appBar,
    this.bottomNavigationBar,
    this.body,
    this.resizeToAvoidBottomInset,
    this.floatingActionButton,
    this.minimizeBehavior = TabBarMinimizeBehavior.automatic,
    this.enableBlur = true,
    this.enableToolbarGradient = true,
    this.extendBodyBehindAppBar = false,
    this.extendBody = false,
    this.backgroundColor,
    this.drawer,
    this.endDrawer,
    this.drawerScrimColor,
    this.onDrawerChanged,
    this.onEndDrawerChanged,
    this.drawerEnableOpenDragGesture = true,
    this.endDrawerEnableOpenDragGesture = true,
    this.scaffoldKey,
    this.useHeroBackButton = true,
    this.useFixedToolbar = true,
    this.tabBarHidden = false,
    this.extendBodyBehindVerticalBar = false,
  });

  /// App bar configuration
  /// If null, no app bar or toolbar will be shown
  final AdaptiveAppBar? appBar;

  /// Bottom navigation bar configuration
  /// If null, no bottom navigation will be shown
  final AdaptiveBottomNavigationBar? bottomNavigationBar;

  /// Body widget
  final Widget? body;

  /// Whether the scaffold should resize when the on-screen keyboard appears.
  ///
  /// When null, each platform path uses its existing default behavior.
  /// Set to `false` to keep bottom navigation pinned while the keyboard
  /// overlays content, such as on iOS tab-based layouts.
  final bool? resizeToAvoidBottomInset;

  /// Floating action button (Material only)
  final Widget? floatingActionButton;

  /// Tab bar minimize behavior (iOS 26+ only)
  /// Controls how the tab bar minimizes when scrolling
  final TabBarMinimizeBehavior minimizeBehavior;

  /// Enable Liquid Glass blur effect behind tab bar (iOS 26+ only)
  /// When enabled, content behind the tab bar will be blurred
  final bool enableBlur;

  /// @deprecated No longer used. iOS 26+ uses native scroll edge effects.
  /// This parameter is kept for backwards compatibility but has no effect.
  final bool enableToolbarGradient;

  /// Whether to extend the body behind the app bar (iOS only)
  /// When true, the body will extend behind the app bar, allowing for
  /// immersive content. When false, the body will start below the app bar.
  final bool extendBodyBehindAppBar;

  /// Whether the body extends under [bottomNavigationBar] on Android and on
  /// iOS 18 and below, like [Scaffold.extendBody]. Set it when the bar is
  /// a custom floating one with margins, so the body shows through them
  /// instead of the scaffold background (#144). On iOS 26+ the body already
  /// sits under the native tab bar.
  final bool extendBody;

  /// Background colour of the page on every platform. Null keeps the
  /// platform default: the Material or Cupertino theme's scaffold colour
  /// (#60, #95). An opaque colour also sets the status bar style to
  /// contrast with it, so a dark page in a light theme keeps a readable
  /// status bar (#77).
  final Color? backgroundColor;

  /// A panel displayed to the side of the body, often hidden on mobile.
  /// On Android, passed directly to the Material Scaffold.
  /// On iOS/iOS 26+, wrapped with a transparent Material Scaffold for drawer behavior.
  /// Open programmatically via `Scaffold.of(context).openDrawer()`.
  final Widget? drawer;

  /// A panel displayed on the opposite side of the drawer.
  /// Open programmatically via `Scaffold.of(context).openEndDrawer()`.
  final Widget? endDrawer;

  /// The color to use for the scrim that obscures the content behind the drawer.
  final Color? drawerScrimColor;

  /// Called when the drawer is opened or closed.
  final DrawerCallback? onDrawerChanged;

  /// Called when the end drawer is opened or closed.
  final DrawerCallback? onEndDrawerChanged;

  /// Whether to enable the drag gesture to open the drawer.
  final bool drawerEnableOpenDragGesture;

  /// Whether to enable the drag gesture to open the end drawer.
  final bool endDrawerEnableOpenDragGesture;

  /// A key to use for the internal [Scaffold] that provides drawer behavior.
  /// Use this to open the drawer programmatically via
  /// `scaffoldKey.currentState?.openDrawer()`.
  final GlobalKey<ScaffoldState>? scaffoldKey;

  /// Whether to use Hero animation for the back button on iOS 26+
  /// When true, the back button stays pinned during page transitions.
  /// Only affects iOS 26+. Defaults to true.
  final bool useHeroBackButton;

  /// Whether this page hands its app bar to the fixed toolbar that
  /// [AdaptiveApp] keeps above the navigator on iOS 26+ (see
  /// [AdaptiveToolbarHost]). Defaults to true.
  ///
  /// Set it to false for a scaffold that does not fill the screen from the
  /// top, such as one pane of a side by side layout: the fixed toolbar sits at
  /// the top of the app, so such a page should keep drawing a toolbar of its
  /// own, where it is. Scaffolds shown in a sheet, dialog or popup (any route
  /// that is not a page) do this automatically.
  final bool useFixedToolbar;

  /// Whether to hide the native tab bar (iOS 26+ only).
  /// Use this to hide the tab bar when showing modal bottom sheets
  /// to prevent native platform views from bleeding through.
  final bool tabBarHidden;

  /// With custom chrome on the iPhone Duo, whether the body runs under the
  /// strip of the vertical bar too, so a header's colour can reach into the
  /// bar. The strip stays in the body's media query padding, for its content
  /// to keep clear of. By default the body sits beside the strip, and the
  /// page's background alone runs under it.
  final bool extendBodyBehindVerticalBar;

  @override
  State<AdaptiveScaffold> createState() => _AdaptiveScaffoldState();
}

/// What one scrollable in a page last said about its scroll edge, with how
/// deep it is and when it said so.
typedef _ScrollEdges = ({int depth, int order, double edge});

class _AdaptiveScaffoldState extends State<AdaptiveScaffold>
    with SingleTickerProviderStateMixin {
  final GlobalKey<_MinimizableTabBarState> _tabBarKey =
      GlobalKey<_MinimizableTabBarState>();

  /// The fixed toolbar chrome this page publishes its app bar to, if an
  /// [AdaptiveToolbarHost] is installed above the navigator.
  ToolbarRegistry? _toolbarRegistry;

  /// Height the native tab bar covers at the bottom of the body, once
  /// measured, while the page draws the bar itself.
  final ValueNotifier<double> _ownTabBarHeight = ValueNotifier<double>(0);

  /// Whether the native tab bar is shrunk while the page scrolls, for the bar
  /// that the toolbar host draws (see [ToolbarEntry.tabBarMinimized]).
  final ValueNotifier<bool> _tabBarMinimized = _PageValue<bool>(false);

  /// How far the page's content has scrolled under the bars along its top
  /// (see [ToolbarEntry.scrollEdge]).
  final ValueNotifier<double> _scrollEdge = _PageValue<double>(0);

  /// How far the iPhone Duo's title band is shown: it moves out of the way
  /// while the page scrolls on, and comes back as soon as it scrolls back
  /// (see [ToolbarEntry.titleBandShown]).
  late final AnimationController _titleBand = AnimationController(
    vsync: this,
    value: 1,
    duration: const Duration(milliseconds: 240),
  );
  late final Animation<double> _titleBandShown = CurvedAnimation(
    parent: _titleBand,
    curve: Curves.easeOutCubic,
    reverseCurve: Curves.easeInCubic,
  );

  /// Whether the page shows its title in the iPhone Duo's title band, as of
  /// its last build: only then does the band move with the scrolling.
  bool _titleBandHides = false;

  /// How far the page has scrolled in the direction it is going, and that
  /// direction.
  double _travel = 0;
  bool _scrollingOn = true;

  /// The latest scroll edge of each vertical scrollable in the page, with its
  /// depth and when it was last heard of.
  final Map<BuildContext, _ScrollEdges> _edges = <BuildContext, _ScrollEdges>{};
  int _edgeOrder = 0;

  /// The outermost scrollables decide, as it is their content that runs
  /// under the bar: a list below a header pinned under the bar (a nested
  /// scroll view) scrolls under the header, not under the bar. Among those
  /// the one that scrolled last does.
  bool _trackScrollEdge(Notification notification) {
    final (metrics, depth, context) = switch (notification) {
      final ScrollNotification n => (n.metrics, n.depth, n.context),
      final ScrollMetricsNotification n => (n.metrics, n.depth, n.context),
      _ => (null, 0, null),
    };
    final edge = metrics == null ? null : AdaptiveScrollEdge.of(metrics);
    if (edge == null || context == null) return false;
    _edges[context] = (depth: depth, order: _edgeOrder++, edge: edge);
    _edges.removeWhere((context, _) => !context.mounted);
    _ScrollEdges? decides;
    for (final entry in _edges.values) {
      if (decides == null ||
          entry.depth < decides.depth ||
          (entry.depth == decides.depth && entry.order > decides.order)) {
        decides = entry;
      }
    }
    if (decides != null) _scrollEdge.value = decides.edge;
    // Any scrollable the page scrolls moves the title band, the list inside
    // a scroll view with a header (a NestedScrollView) too: once its header
    // is gone, scrolling back moves that list, not the outer scroll view.
    if (notification is ScrollUpdateNotification) {
      _followScroll(
        notification.metrics,
        notification.scrollDelta ?? 0,
        underBand: _underTitleBand(context),
      );
    }
    return false;
  }

  /// Whether the scrollable of [scrollable] runs under the iPhone Duo's
  /// title band: one that starts below it has nothing to show there.
  bool _underTitleBand(BuildContext scrollable) {
    final box = scrollable.findRenderObject();
    final page = context.findRenderObject();
    if (box is! RenderBox || page is! RenderBox) return false;
    if (!box.attached || !page.attached || !box.hasSize) return false;
    return box.localToGlobal(Offset.zero, ancestor: page).dy <
        kDuoTitleBandHeight - 0.5;
  }

  /// Moves the iPhone Duo's title band out of the way as soon as the page
  /// scrolls on, and back as soon as it scrolls back or reaches its top. The
  /// bounce at either end moves nothing, and nor does content that does not
  /// run under the band.
  void _followScroll(
    ScrollMetrics metrics,
    double delta, {
    required bool underBand,
  }) {
    if (!_titleBandHides || metrics.axis != Axis.vertical || delta == 0) {
      return;
    }
    // Content that does not run under the band has nothing to show there,
    // and leaves it be: in a scroll view with a header, its list only runs
    // under the band once the header is gone.
    if (!underBand) return;
    if (metrics.extentBefore <= 0) {
      _showTitleBand(true);
      return;
    }
    if (metrics.pixels > metrics.maxScrollExtent) return;
    final on = metrics.axisDirection == AxisDirection.up
        ? delta < 0
        : delta > 0;
    if (on != _scrollingOn) {
      _scrollingOn = on;
      _travel = 0;
    }
    _travel += delta.abs();
    if (on && _travel > 4) _showTitleBand(false);
    if (!on && _travel > 8) _showTitleBand(true);
  }

  void _showTitleBand(bool shown) {
    if (shown
        ? _titleBand.status == AnimationStatus.forward || _titleBand.value == 1
        : _titleBand.status == AnimationStatus.reverse ||
              _titleBand.value == 0) {
      return;
    }
    if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) {
      _titleBand.value = shown ? 1 : 0;
    } else if (shown) {
      _titleBand.forward();
    } else {
      _titleBand.reverse();
    }
  }

  /// Whether this page shows its title in the iPhone Duo's title band; a
  /// page that does not keeps the band in place.
  void _titleBandFollows(bool follows) {
    _titleBandHides = follows;
    if (follows || _titleBand.value == 1) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !_titleBandHides) _titleBand.value = 1;
    });
  }

  void _onTabBarSizeChanged(Size size) {
    if (mounted) _ownTabBarHeight.value = size.height;
  }

  /// Lets the body keep its content clear of the native tab bar floating over
  /// it: raises the bottom padding to the bar's height and publishes that
  /// height through [AdaptiveBottomBarInset]. The body still runs underneath
  /// the bar, so a map or a list can show through its glass.
  ///
  /// The height comes from the bar the host draws, from the page's own bar,
  /// or is 0 while the tabs are in the iPhone Duo trailing bar. Only the
  /// inset follows it: the body is not built again when it changes, or when
  /// the bar moves between the page and the host.
  Widget _withBottomBarInset(
    BuildContext context,
    Widget body, {
    ModalRoute<Object?>? ownerRoute,
  }) {
    final ValueListenable<double> height;
    final custom = _customChrome != null;
    final placement = AdaptiveChromeScope.placementOf(context);
    if (custom && _usesFixedToolbar(context)) {
      // Custom chrome: the tab bar and its accessory along the bottom, an
      // accessory floating at the bottom of the content, or nothing beside
      // a sidebar.
      height = switch (placement) {
        AdaptiveChromePlacement.bottom =>
          ToolbarChromeScope.maybeOf(context)?.tabBarHeight ??
              const AlwaysStoppedAnimation<double>(0),
        AdaptiveChromePlacement.vertical || AdaptiveChromePlacement.topStrip =>
          AdaptiveChromeScope.maybeOf(context)!.floatingAccessoryHeight,
        AdaptiveChromePlacement.sidebar => const AlwaysStoppedAnimation<double>(
          0,
        ),
      };
    } else if (_tabsInTrailingBar(context)) {
      height = const AlwaysStoppedAnimation<double>(0);
    } else if (_tabsHostedAtBottom(context)) {
      height =
          ToolbarChromeScope.maybeOf(context)?.tabBarHeight ?? _ownTabBarHeight;
    } else {
      height = _ownTabBarHeight;
    }
    return _BottomBarInset(
      height: height,
      hidden: widget.tabBarHidden,
      ownerRoute: ownerRoute,
      hidesWhenPushed: widget.bottomNavigationBar?.hidesWhenPushed ?? false,
      hidesFor: widget.bottomNavigationBar?.hidesFor,
      child: body,
    );
  }

  /// Shrinks or restores the tab bar that the host draws as the page scrolls,
  /// as [AdaptiveScaffold.minimizeBehavior] asks.
  bool _minimizeHostedTabBar(ScrollNotification notification) {
    // Beside a list the list decides: the page it opened scrolling on its
    // own would shrink and restore the tab bar against it.
    final source = notification.context;
    if (source != null && AdaptiveSplitView.isInDetailColumn(source)) {
      return false;
    }
    final minimized = _tabBarMinimizedAfter(
      notification,
      widget.minimizeBehavior,
      minimized: _tabBarMinimized.value,
    );
    if (minimized != null) _tabBarMinimized.value = minimized;
    return false;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncToolbarEntry();
  }

  @override
  void didUpdateWidget(AdaptiveScaffold oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.appBar != widget.appBar ||
        oldWidget.useFixedToolbar != widget.useFixedToolbar ||
        oldWidget.tabBarHidden != widget.tabBarHidden ||
        oldWidget.bottomNavigationBar != widget.bottomNavigationBar ||
        oldWidget.backgroundColor != widget.backgroundColor) {
      _syncToolbarEntry();
    }
    // Another tab shows a page of its own: the bar is back at full size.
    if (widget.minimizeBehavior == TabBarMinimizeBehavior.never ||
        oldWidget.bottomNavigationBar?.selectedIndex !=
            widget.bottomNavigationBar?.selectedIndex) {
      _tabBarMinimized.value = false;
    }
  }

  @override
  void dispose() {
    // Out of the registry first: the host stops listening to the notifiers
    // below once it sees the entry gone.
    _toolbarRegistry?.remove(this);
    _ownTabBarHeight.dispose();
    _tabBarMinimized.dispose();
    _scrollEdge.dispose();
    _titleBand.dispose();
    super.dispose();
  }

  /// Publishes this page's app bar to the fixed toolbar chrome.
  ///
  /// Reading [ModalRoute.of], `TickerMode.of` and [Visibility.of] here
  /// registers dependencies on the route's live status and on the page's
  /// visibility, so this re-runs exactly when the page stops (or starts) being
  /// the current route, or is hidden/shown by a tab switch: the moments the
  /// chrome has to pick another page's items. No-op when no host is installed.
  ///
  /// Both visibility signals are needed because tab containers hide pages
  /// differently: GoRouter's `StatefulShellRoute.indexedStack` and
  /// `CupertinoTabScaffold` use `Offstage` + a disabled [TickerMode], while a
  /// plain [IndexedStack] uses [Visibility.maintain], which keeps tickers
  /// enabled and is only observable through [Visibility.of].
  /// Whether this scaffold's toolbar belongs in the fixed chrome: it asked
  /// for it and it is a page. A sheet or dialog is not at the top of the
  /// screen, so a scaffold inside one keeps its own toolbar.
  bool _usesFixedToolbar(BuildContext context) {
    if (!widget.useFixedToolbar) return false;
    // A column of a split view has its own bar, as a column of a
    // UISplitViewController has its own navigation bar.
    if (AdaptiveSplitView.isInColumn(context)) return false;
    // So has a page in a popover, on a navigator of its own there too.
    if (AdaptivePopover.isIn(context)) return false;
    final route = ModalRoute.of(context);
    return route == null || route is PageRoute;
  }

  /// The tab bar the fixed chrome may draw, in the iPhone Duo trailing bar or
  /// at the bottom of the screen: only the native one. A custom
  /// `CupertinoTabBar` or bottom widget (`useNativeBottomBar: false`) is the
  /// app's own and stays where it is. Hidden or not
  /// ([AdaptiveScaffold.tabBarHidden]): a hidden native bar is kept, off
  /// stage, for when it shows again.
  AdaptiveBottomNavigationBar? get _nativeTabBar {
    final bar = widget.bottomNavigationBar;
    // Custom chrome draws any tab bar the page describes, and so does the
    // iPhone Duo's vertical bar: the page's own bar would have nowhere to go.
    final custom = _customChrome != null;
    if (bar == null || (!bar.useNativeBottomBar && !custom && !_tabsInDuoBar)) {
      return null;
    }
    if (bar.items == null ||
        bar.items!.isEmpty ||
        bar.selectedIndex == null ||
        bar.onTap == null) {
      return null;
    }
    return bar;
  }

  bool _tabsInTrailingBar(BuildContext context) =>
      _usesFixedToolbar(context) &&
      (ToolbarChromeScope.maybeOf(context)?.hostsDuoControls ?? false);

  /// Whether the toolbar host draws this page's native tab bar at the bottom
  /// of the screen, above the navigator (see
  /// [ToolbarChromeScope.hostsBottomTabBar]), so the page draws none.
  bool _tabsHostedAtBottom(BuildContext context) =>
      (_customChrome != null || PlatformInfo.isIOS26OrHigher()) &&
      _nativeTabBar != null &&
      _usesFixedToolbar(context) &&
      (ToolbarChromeScope.maybeOf(context)?.hostsBottomTabBar ?? false);

  /// The custom chrome of the toolbar host above, if it has any: read once
  /// per dependency change, as the registry is.
  AdaptiveChrome? _customChrome;

  /// Whether the toolbar host holds the controls and tabs in the iPhone
  /// Duo's vertical bar, as of the last dependency change.
  bool _tabsInDuoBar = false;

  void _syncToolbarEntry() {
    _customChrome = AdaptiveChromeScope.chromeOf(context);
    _tabsInDuoBar =
        _usesFixedToolbar(context) &&
        (ToolbarChromeScope.maybeOf(context)?.hostsDuoControls ?? false);
    final registry = ToolbarRegistry.maybeOf(context);
    if (registry == null) return;
    final inColumn = AdaptiveSplitView.isInColumn(context);
    final appBar = inColumn ? _controlsForBar() : widget.appBar;
    if (inColumn ? appBar == null : !_usesFixedToolbar(context)) {
      _toolbarRegistry?.remove(this);
      _toolbarRegistry = null;
      return;
    }
    _toolbarRegistry = registry;
    final navigator = Navigator.maybeOf(context);
    // Routes of the navigators around this page's own one (tabs, shell
    // routes). `Navigator.maybeOf` would hand a navigator's context straight
    // back to itself, so step to its ancestor explicitly.
    final enclosingRoutes = <ModalRoute<Object?>>[];
    var outer = navigator?.context;
    while (outer != null) {
      final route = ModalRoute.of(outer);
      if (route == null) break;
      enclosingRoutes.add(route);
      outer = outer.findAncestorStateOfType<NavigatorState>()?.context;
    }
    registry.upsert(
      ToolbarEntry(
        id: this,
        appBar: appBar,
        route: ModalRoute.of(context),
        navigator: navigator,
        enclosingRoutes: enclosingRoutes,
        titleOverlay: inColumn || _customChrome != null
            ? null
            : _buildIOS26TitleOverlay(),
        // `TickerMode.valuesOf` replaces this, but only exists in Flutter
        // releases after 3.35; `of` works on every supported version.
        // ignore: deprecated_member_use
        visible: TickerMode.of(context) && Visibility.of(context),
        shownInPlace: Visibility.of(context),
        tabBar: _nativeTabBar,
        tabBarHidden: widget.tabBarHidden,
        // Custom chrome draws the tabs of every tab layout, wherever they go.
        tabBarHosted: _customChrome != null
            ? _nativeTabBar != null && _usesFixedToolbar(context)
            : _tabsHostedAtBottom(context),
        tabBarMinimized: _tabBarMinimized,
        scrollEdge: _scrollEdge,
        titleBandShown: _titleBandShown,
        backgroundColor: widget.backgroundColor,
      ),
    );
  }

  /// A page in a column of a split view keeps its title in its column. In
  /// the iPhone Duo vertical bar pose its back button and actions go to the
  /// vertical bar, as every page's do: an app bar with only those. Null when
  /// it has none to hand over, or in any other pose.
  AdaptiveAppBar? _controlsForBar() {
    final appBar = widget.appBar;
    if (appBar == null || !AdaptiveSplitView.handsControlsToBar(context)) {
      return null;
    }
    final canPop = Navigator.maybeOf(context)?.canPop() ?? false;
    final back =
        appBar.leading == null &&
        !AdaptiveSplitView.hidesBackButton(context) &&
        (appBar.onBack != null || (appBar.automaticallyImplyLeading && canPop));
    final actions = appBar.actions ?? const <AdaptiveAppBarAction>[];
    if (!back && actions.isEmpty && appBar.leading == null) return null;
    return AdaptiveAppBar(
      actions: actions,
      leading: appBar.leading,
      tintColor: appBar.tintColor,
      onBack: back ? appBar.onBack : null,
      backButtonStyle: appBar.backButtonStyle,
      automaticallyImplyLeading: back,
    );
  }

  /// Builds the app bar title area, optionally with a subtitle below it.
  ///
  /// Returns [AdaptiveAppBar.titleWidget] verbatim when provided; otherwise a
  /// title (plus subtitle when set). When [nativeTitleFallback] is true the
  /// plain-title case returns null so the iOS 26 native toolbar can render the
  /// title itself; the other paths return a plain `Text` instead.
  Widget? _buildAppBarTitle({
    CrossAxisAlignment crossAxisAlignment = CrossAxisAlignment.center,
    TextStyle? titleStyle,
    double subtitleFontSize = 12,
    Color? subtitleColor,
    bool nativeTitleFallback = false,
  }) {
    if (widget.appBar?.titleWidget != null) return widget.appBar!.titleWidget;
    final title = widget.appBar?.title;
    if (title == null) return null;
    final subtitle = widget.appBar?.subtitle;
    if (subtitle == null || subtitle.isEmpty) {
      return nativeTitleFallback ? null : Text(title, style: titleStyle);
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: crossAxisAlignment,
      children: [
        Text(title, style: titleStyle),
        Text(
          subtitle,
          style: TextStyle(
            fontSize: subtitleFontSize,
            fontWeight: FontWeight.normal,
            color: subtitleColor,
          ),
        ),
      ],
    );
  }

  /// iOS 26+ native toolbar title overlay. The native title is a plain string,
  /// so a subtitle (or custom widget) is drawn as a Flutter overlay instead.
  /// Colors resolve from the ambient brightness so the overlay matches the
  /// native title in light and dark mode.
  Widget? _buildIOS26TitleOverlay() {
    return _buildAppBarTitle(
      nativeTitleFallback: true,
      titleStyle: TextStyle(
        fontSize: 17,
        fontWeight: FontWeight.w600,
        color: CupertinoColors.label.resolveFrom(context),
      ),
      subtitleColor: CupertinoColors.secondaryLabel.resolveFrom(context),
    );
  }

  Widget _wrapWithDrawerIfNeeded(Widget child) {
    if (widget.drawer == null && widget.endDrawer == null) {
      return child;
    }
    return Scaffold(
      key: widget.scaffoldKey,
      backgroundColor: Colors.transparent,
      resizeToAvoidBottomInset: widget.resizeToAvoidBottomInset,
      body: child,
      drawer: widget.drawer,
      endDrawer: widget.endDrawer,
      drawerScrimColor: widget.drawerScrimColor,
      onDrawerChanged: widget.onDrawerChanged,
      onEndDrawerChanged: widget.onEndDrawerChanged,
      drawerEnableOpenDragGesture: widget.drawerEnableOpenDragGesture,
      endDrawerEnableOpenDragGesture: widget.endDrawerEnableOpenDragGesture,
    );
  }

  @override
  Widget build(BuildContext context) {
    final page = _buildPage(context);
    final bg = widget.backgroundColor;
    if (bg == null || bg.a < 0.5) return page;
    // A page that sets its own background keeps the status bar legible
    // over it, whatever the app theme says: light icons on a dark page and
    // dark icons on a light one. Pages without a colour follow the theme
    // through AdaptiveApp, and an inner AnnotatedRegion still wins (#77).
    final dark = ThemeData.estimateBrightnessForColor(bg) == Brightness.dark;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: dark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
      child: page,
    );
  }

  Widget _buildPage(BuildContext context) {
    final chrome = _customChrome;
    if (chrome != null) return _buildCustomChromePage(context, chrome);

    final useNativeToolbar = widget.appBar?.useNativeToolbar ?? false;
    final useNativeBottomBar =
        widget.bottomNavigationBar?.useNativeBottomBar ?? true;

    // iOS 26+ with native toolbar enabled - Use IOS26Scaffold
    if (PlatformInfo.isIOS26OrHigher() && useNativeToolbar) {
      // The body is the app's own tab switcher (an `IndexedStack`, a
      // `StatefulNavigationShell`, `pages[index]`...), so it is mounted
      // exactly once. Earlier versions built one copy per tab, which ran
      // every page's `initState` once per destination (#76).
      List<Widget> childrenList = [widget.body ?? const SizedBox.shrink()];

      // Wrap children with Stack if floatingActionButton is provided
      if (widget.floatingActionButton != null) {
        final hasBottomNav =
            widget.bottomNavigationBar?.items != null &&
            widget.bottomNavigationBar!.items!.isNotEmpty;
        childrenList = childrenList.map((child) {
          return Stack(
            children: [
              child,
              Positioned(
                right: 16,
                bottom: hasBottomNav ? 96 : 96, // Add space for native tab bar
                child: widget.floatingActionButton!,
              ),
            ],
          );
        }).toList();
      }

      final tabsHosted = _tabsHostedAtBottom(context);
      Widget scaffold = IOS26Scaffold(
        bottomNavigationBar: widget.bottomNavigationBar,
        title: widget.appBar?.title,
        actions: widget.appBar?.actions,
        leading: widget.appBar?.leading,
        onBack: widget.appBar?.onBack,
        backButtonStyle:
            widget.appBar?.backButtonStyle ?? AdaptiveBackButtonStyle.back,
        automaticallyImplyLeading:
            widget.appBar?.automaticallyImplyLeading ?? true,
        tintColor: widget.appBar?.tintColor,
        titleWidget: _buildIOS26TitleOverlay(),
        minimizeBehavior: widget.minimizeBehavior,
        enableBlur: widget.enableBlur,
        backgroundColor: widget.backgroundColor,
        useHeroBackButton: widget.useHeroBackButton,
        // In a column of a split view the page draws its own bar, as told
        // by the column's chrome.
        useFixedToolbar:
            _usesFixedToolbar(context) || AdaptiveSplitView.isInColumn(context),
        tabBarHidden: widget.tabBarHidden,
        tabsHosted: tabsHosted,
        resizeToAvoidBottomInset: widget.resizeToAvoidBottomInset,
        children: childrenList,
      );
      if (tabsHosted &&
          widget.minimizeBehavior != TabBarMinimizeBehavior.never) {
        scaffold = NotificationListener<ScrollNotification>(
          onNotification: _minimizeHostedTabBar,
          child: scaffold,
        );
      }
      final hosted = _usesFixedToolbar(context);
      _titleBandFollows(
        hosted &&
            DuoPoseScope.of(context) != null &&
            (widget.appBar?.hidesOnScroll ?? true) &&
            (widget.appBar?.title != null ||
                widget.appBar?.titleWidget != null),
      );
      if (hosted) {
        scaffold = NotificationListener<Notification>(
          onNotification: _trackScrollEdge,
          child: scaffold,
        );
      }
      return _wrapWithDrawerIfNeeded(scaffold);
    }

    // iOS <26 (iOS 18 and below) OR iOS 26+ with useNativeToolbar: false
    // Use CupertinoPageScaffold with CupertinoTabBar if destinations provided
    if (PlatformInfo.isIOS) {
      Widget? effectiveLeading = widget.appBar?.leading;

      if (widget.bottomNavigationBar?.items != null &&
          widget.bottomNavigationBar!.items!.isNotEmpty &&
          widget.bottomNavigationBar!.selectedIndex != null &&
          widget.bottomNavigationBar!.onTap != null) {
        // Tab-based navigation

        // Determine which navigation bar to use
        ObstructingPreferredSizeWidget? navigationBar;

        // Priority 1: Custom CupertinoNavigationBar (if provided and useNativeToolbar is false)
        if (widget.appBar?.cupertinoNavigationBar != null) {
          navigationBar =
              widget.appBar!.cupertinoNavigationBar
                  as ObstructingPreferredSizeWidget;
        }
        // Priority 2: Build from title, actions, leading (if appBar has content)
        else if (widget.appBar != null &&
            (widget.appBar!.title != null ||
                (widget.appBar!.actions != null &&
                    widget.appBar!.actions!.isNotEmpty) ||
                effectiveLeading != null ||
                (Navigator.maybeOf(context)?.canPop() ?? false))) {
          navigationBar = CupertinoNavigationBar(
            automaticallyImplyLeading:
                PlatformInfo.isIOS26OrHigher() && useNativeToolbar
                ? false
                : true, // Let CupertinoNavigationBar handle back button naturally
            middle: _buildAppBarTitle(),
            trailing:
                widget.appBar!.actions != null &&
                    widget.appBar!.actions!.isNotEmpty
                ? Row(
                    mainAxisSize: MainAxisSize.min,
                    children: widget.appBar!.actions!.map((action) {
                      Widget actionChild;
                      if (action.title != null) {
                        actionChild = Text(action.title!);
                      } else if (action.iconWidget != null) {
                        actionChild = action.iconWidget!;
                      } else if (action.icon != null) {
                        actionChild = Icon(action.icon!);
                      } else {
                        actionChild = const Icon(CupertinoIcons.circle);
                      }
                      actionChild = action.wrapWithBadge(actionChild);
                      return Builder(
                        builder: (context) => CupertinoButton(
                          padding: EdgeInsets.zero,
                          onPressed: () => action.press(context),
                          child: actionChild,
                        ),
                      );
                    }).toList(),
                  )
                : null,
            leading: effectiveLeading,
          );
        }

        // Determine which tab bar to use based on platform and configuration
        Widget? tabBar;

        // iOS 26+ with useNativeBottomBar=true -> Use native tab bar
        if (PlatformInfo.isIOS26OrHigher() && useNativeBottomBar) {
          tabBar = _MinimizableTabBar(
            key: _tabBarKey,
            selectedIndex: widget.bottomNavigationBar!.selectedIndex!,
            onTap: widget.bottomNavigationBar!.onTap!,
            destinations: widget.bottomNavigationBar!.items!,
            minimizeBehavior: widget.minimizeBehavior,
            enableBlur: widget.enableBlur,
            selectedItemColor: widget.bottomNavigationBar!.selectedItemColor,
            unselectedItemColor:
                widget.bottomNavigationBar!.unselectedItemColor,
            hidden: widget.tabBarHidden,
          );
        }
        // iOS 26+ with useNativeBottomBar=false OR iOS <26
        else {
          // Priority 1: Custom CupertinoTabBar (if provided)
          if (widget.bottomNavigationBar!.cupertinoTabBar != null) {
            tabBar = widget.bottomNavigationBar!.cupertinoTabBar;
          }
          // Priority 2: Build from items
          else {
            final unselectedColor =
                widget.bottomNavigationBar!.unselectedItemColor;

            tabBar = CupertinoTabBar(
              currentIndex: widget.bottomNavigationBar!.selectedIndex!,
              onTap: widget.bottomNavigationBar!.onTap!,
              activeColor: widget.bottomNavigationBar!.selectedItemColor,
              items: widget.bottomNavigationBar!.items!.map((dest) {
                Widget iconWidget = _buildNavigationIconWidget(
                  rawIcon: dest.icon,
                  color: unselectedColor,
                  platform: TargetPlatform.iOS,
                );

                Widget activeIconWidget = _buildNavigationIconWidget(
                  rawIcon: dest.selectedIcon ?? dest.icon,
                  platform: TargetPlatform.iOS,
                );

                if (dest.hasBadge) {
                  iconWidget = dest.wrapWithBadge(iconWidget);
                  activeIconWidget = dest.wrapWithBadge(activeIconWidget);
                } else if (dest.showsBadgeDot) {
                  iconWidget = Badge(child: iconWidget);
                  activeIconWidget = Badge(child: activeIconWidget);
                }

                return BottomNavigationBarItem(
                  icon: iconWidget,
                  activeIcon: activeIconWidget,
                  label: dest.label,
                );
              }).toList(),
            );
          }
        }

        // On iPhone Duo the fixed chrome shows the tabs at the bottom of the
        // trailing bar instead, and elsewhere on iOS 26 the toolbar host
        // draws them at the bottom of the screen, above the navigator: the
        // page then draws no bar of its own.
        final tabsHosted =
            _tabsInTrailingBar(context) || _tabsHostedAtBottom(context);
        final tabsHostedAtBottom = _tabsHostedAtBottom(context);

        // Wrap body with Stack if floatingActionButton is provided
        Widget bodyWidget = Column(
          children: [
            Expanded(
              child: NotificationListener<ScrollNotification>(
                onNotification: (notification) {
                  // Forward scroll notifications to _MinimizableTabBar state (iOS 26+ native only)
                  if (PlatformInfo.isIOS26OrHigher() && useNativeBottomBar) {
                    if (tabsHostedAtBottom) {
                      _minimizeHostedTabBar(notification);
                    } else {
                      _tabBarKey.currentState?.handleScrollNotification(
                        notification,
                      );
                    }
                  }
                  return false; // Let it bubble up
                },
                child: PlatformInfo.isIOS26OrHigher() && useNativeBottomBar
                    ? Stack(
                        children: [
                          _withBottomBarInset(
                            context,
                            widget.body ?? const SizedBox.shrink(),
                          ),
                          if (!tabsHosted)
                            Positioned(
                              left: 0,
                              right: 0,
                              bottom: 0,
                              child: SizeReporter(
                                onSizeChanged: _onTabBarSizeChanged,
                                child: tabBar!,
                              ),
                            ),
                        ],
                      )
                    : widget.body ?? const SizedBox.shrink(),
              ),
            ),
            // Show tab bar at bottom for non-native cases, unless the iPhone
            // Duo's vertical bar holds the tabs.
            if ((!PlatformInfo.isIOS26OrHigher() || !useNativeBottomBar) &&
                !_tabsInTrailingBar(context))
              tabBar!,
          ],
        );

        if (widget.floatingActionButton != null) {
          bodyWidget = Stack(
            children: [
              bodyWidget,
              Positioned(
                right: 16,
                bottom: (!PlatformInfo.isIOS26OrHigher() || !useNativeBottomBar)
                    ? 96
                    : 16, // Add space for tab bar if not native
                child: widget.floatingActionButton!,
              ),
            ],
          );
        }

        // Wrap body with DefaultTextStyle to ensure proper text color based on brightness
        final brightness = MediaQuery.platformBrightnessOf(context);
        final textColor = brightness == Brightness.dark
            ? CupertinoColors.white
            : CupertinoColors.black;

        bodyWidget = DefaultTextStyle(
          style: TextStyle(
            color: textColor,
            fontSize: 17, // iOS default
          ),
          child: bodyWidget,
        );

        // When the native tab bar is rendered via Stack + Positioned(bottom:0),
        // disable resizeToAvoidBottomInset so the keyboard covers the tab bar
        // instead of pushing it above.
        final hasNativeTabBar =
            PlatformInfo.isIOS26OrHigher() &&
            useNativeBottomBar &&
            tabBar != null;

        return _wrapWithDrawerIfNeeded(
          CupertinoPageScaffold(
            resizeToAvoidBottomInset:
                widget.resizeToAvoidBottomInset ?? !hasNativeTabBar,
            navigationBar: navigationBar,
            child: bodyWidget,
          ),
        );
      }

      // Simple page without tabs

      // Determine which navigation bar to use
      ObstructingPreferredSizeWidget? navigationBar;

      // Priority 1: Custom CupertinoNavigationBar (if provided and useNativeToolbar is false)
      if (widget.appBar?.cupertinoNavigationBar != null) {
        navigationBar =
            widget.appBar!.cupertinoNavigationBar
                as ObstructingPreferredSizeWidget;
      }
      // Priority 2: Build from title, actions, leading (if appBar has content)
      else if (widget.appBar != null &&
          (widget.appBar!.title != null ||
              widget.appBar!.titleWidget != null ||
              (widget.appBar!.actions != null &&
                  widget.appBar!.actions!.isNotEmpty) ||
              effectiveLeading != null ||
              (Navigator.maybeOf(context)?.canPop() ?? false))) {
        navigationBar = CupertinoNavigationBar(
          automaticallyImplyLeading:
              PlatformInfo.isIOS26OrHigher() && useNativeToolbar
              ? false
              : true, // Let CupertinoNavigationBar handle back button naturally
          middle: _buildAppBarTitle(),
          trailing:
              widget.appBar!.actions != null &&
                  widget.appBar!.actions!.isNotEmpty
              ? Row(
                  mainAxisSize: MainAxisSize.min,
                  children: widget.appBar!.actions!.map((action) {
                    Widget actionChild;
                    if (action.title != null) {
                      actionChild = Text(action.title!);
                    } else if (action.iconWidget != null) {
                      actionChild = action.iconWidget!;
                    } else if (action.icon != null) {
                      actionChild = Icon(action.icon!);
                    } else {
                      actionChild = const Icon(CupertinoIcons.circle);
                    }
                    actionChild = action.wrapWithBadge(actionChild);
                    return Builder(
                      builder: (context) => CupertinoButton(
                        padding: EdgeInsets.zero,
                        onPressed: () => action.press(context),
                        child: actionChild,
                      ),
                    );
                  }).toList(),
                )
              : null,
          leading: effectiveLeading,
        );
      }

      // Wrap body with Stack if floatingActionButton is provided
      Widget body = widget.body ?? const SizedBox.shrink();
      if (widget.floatingActionButton != null) {
        body = Stack(
          children: [
            body,
            Positioned(
              right: 16,
              bottom: 16,
              child: widget.floatingActionButton!,
            ),
          ],
        );
      }

      // Wrap body with DefaultTextStyle to ensure proper text color based on brightness
      final brightness = MediaQuery.platformBrightnessOf(context);
      final textColor = brightness == Brightness.dark
          ? CupertinoColors.white
          : CupertinoColors.black;

      body = DefaultTextStyle(
        style: TextStyle(
          color: textColor,
          fontSize: 17, // iOS default
        ),
        child: body,
      );

      // Always use CupertinoPageScaffold to ensure proper background color
      return _wrapWithDrawerIfNeeded(
        CupertinoPageScaffold(
          resizeToAvoidBottomInset: widget.resizeToAvoidBottomInset ?? true,
          navigationBar: navigationBar,
          child: body,
        ),
      );
    }

    // Android - Use NavigationBar if destinations provided
    if (widget.bottomNavigationBar?.items != null &&
        widget.bottomNavigationBar!.items!.isNotEmpty &&
        widget.bottomNavigationBar!.selectedIndex != null &&
        widget.bottomNavigationBar!.onTap != null) {
      // Tab-based navigation

      // Determine which app bar to use
      PreferredSizeWidget? appBar;

      // Priority 1: Custom AppBar (if provided)
      if (widget.appBar?.appBar != null) {
        appBar = widget.appBar!.appBar;
      }
      // Priority 2: Build from title, actions, leading (if appBar has content)
      else if (widget.appBar != null &&
          (widget.appBar!.title != null ||
              widget.appBar!.titleWidget != null ||
              (widget.appBar!.actions != null &&
                  widget.appBar!.actions!.isNotEmpty) ||
              widget.appBar!.leading != null)) {
        appBar = AppBar(
          title: _buildAppBarTitle(
            crossAxisAlignment: CrossAxisAlignment.start,
            subtitleFontSize: 13,
            subtitleColor: Theme.of(
              context,
            ).textTheme.bodySmall?.color?.withValues(alpha: 0.7),
          ),
          centerTitle: widget.appBar!.titleWidget != null,
          actions: widget.appBar!.actions?.map((action) {
            if (action.title != null) {
              return Builder(
                builder: (context) => TextButton(
                  onPressed: () => action.press(context),
                  child: Text(action.title!),
                ),
              );
            }
            return Builder(
              builder: (context) => IconButton(
                icon: action.wrapWithBadge(
                  action.iconWidget ??
                      (action.icon != null
                          ? Icon(action.icon!)
                          : const Icon(Icons.circle)),
                ),
                tooltip: action.effectiveLabel,
                onPressed: () => action.press(context),
              ),
            );
          }).toList(),
          leading: widget.appBar!.leading,
        );
      }

      // Determine which bottom navigation bar to use
      Widget? bottomNavBar;

      // Priority 1: Custom BottomNavigationBar (if provided)
      if (widget.bottomNavigationBar!.bottomNavigationBar != null) {
        bottomNavBar = widget.bottomNavigationBar!.bottomNavigationBar;
      }
      // Priority 2: Build from items
      else {
        bottomNavBar = NavigationBar(
          selectedIndex: widget.bottomNavigationBar!.selectedIndex!,
          onDestinationSelected: widget.bottomNavigationBar!.onTap!,
          indicatorColor: widget.bottomNavigationBar!.selectedItemColor,
          destinations: widget.bottomNavigationBar!.items!.map((dest) {
            Widget iconWidget = _buildNavigationIconWidget(
              rawIcon: dest.icon,
              platform: TargetPlatform.android,
            );

            Widget selectedIconWidget = _buildNavigationIconWidget(
              rawIcon: dest.selectedIcon ?? dest.icon,
              platform: TargetPlatform.android,
            );

            if (dest.hasBadge) {
              iconWidget = dest.wrapWithBadge(iconWidget);
              selectedIconWidget = dest.wrapWithBadge(selectedIconWidget);
            } else if (dest.showsBadgeDot) {
              iconWidget = Badge(child: iconWidget);
              selectedIconWidget = Badge(child: selectedIconWidget);
            }

            return NavigationDestination(
              icon: iconWidget,
              selectedIcon: selectedIconWidget,
              label: dest.label,
            );
          }).toList(),
        );
      }

      return Scaffold(
        key: widget.scaffoldKey,
        appBar: appBar,
        body: widget.body ?? const SizedBox.shrink(),
        resizeToAvoidBottomInset: widget.resizeToAvoidBottomInset,
        bottomNavigationBar: bottomNavBar,
        floatingActionButton: widget.floatingActionButton,
        extendBodyBehindAppBar: widget.extendBodyBehindAppBar,
        extendBody: widget.extendBody,
        backgroundColor: widget.backgroundColor,
        drawer: widget.drawer,
        endDrawer: widget.endDrawer,
        drawerScrimColor: widget.drawerScrimColor,
        onDrawerChanged: widget.onDrawerChanged,
        onEndDrawerChanged: widget.onEndDrawerChanged,
        drawerEnableOpenDragGesture: widget.drawerEnableOpenDragGesture,
        endDrawerEnableOpenDragGesture: widget.endDrawerEnableOpenDragGesture,
      );
    }

    // Simple page without tabs

    // Determine which app bar to use
    PreferredSizeWidget? appBar;

    // Priority 1: Custom AppBar (if provided)
    if (widget.appBar?.appBar != null) {
      appBar = widget.appBar!.appBar;
    }
    // Priority 2: Build AppBar if widget.appBar is provided (even if empty - for automatic back button)
    else if (widget.appBar != null) {
      appBar = AppBar(
        title: _buildAppBarTitle(
          crossAxisAlignment: CrossAxisAlignment.start,
          subtitleFontSize: 13,
          subtitleColor: Theme.of(
            context,
          ).textTheme.bodySmall?.color?.withValues(alpha: 0.7),
        ),
        centerTitle: widget.appBar!.titleWidget != null,
        actions: widget.appBar!.actions?.map((action) {
          if (action.title != null) {
            return Builder(
              builder: (context) => TextButton(
                onPressed: () => action.press(context),
                child: Text(action.title!),
              ),
            );
          }
          return Builder(
            builder: (context) => IconButton(
              icon: action.wrapWithBadge(
                action.iconWidget ??
                    (action.icon != null
                        ? Icon(action.icon!)
                        : const Icon(Icons.circle)),
              ),
              tooltip: action.effectiveLabel,
              onPressed: () => action.press(context),
            ),
          );
        }).toList(),
        leading: widget.appBar!.leading,
        // automaticallyImplyLeading defaults to true, so back button will show automatically
      );
    }

    // Always use Scaffold to ensure Material context
    return Scaffold(
      key: widget.scaffoldKey,
      appBar: appBar,
      body: widget.body ?? const SizedBox.shrink(),
      resizeToAvoidBottomInset: widget.resizeToAvoidBottomInset,
      floatingActionButton: widget.floatingActionButton,
      extendBodyBehindAppBar: widget.extendBodyBehindAppBar,
      extendBody: widget.extendBody,
      backgroundColor: widget.backgroundColor,
      drawer: widget.drawer,
      endDrawer: widget.endDrawer,
      drawerScrimColor: widget.drawerScrimColor,
      onDrawerChanged: widget.onDrawerChanged,
      onEndDrawerChanged: widget.onEndDrawerChanged,
      drawerEnableOpenDragGesture: widget.drawerEnableOpenDragGesture,
      endDrawerEnableOpenDragGesture: widget.endDrawerEnableOpenDragGesture,
    );
  }

  /// A page under a toolbar host with custom chrome, the same on every
  /// platform: the host draws its bars, or the page draws its own bar with
  /// the app's builders where the host's would not reach it (a sheet, a
  /// dialog, a column of a split view). Its content runs under the bars and
  /// keeps clear of them through the media query's padding, as under the
  /// native bars of iOS 26.
  Widget _buildCustomChromePage(BuildContext context, AdaptiveChrome chrome) {
    final appBar = widget.appBar;
    final placement = AdaptiveChromeScope.placementOf(context);
    final hostChrome = ToolbarChromeScope.maybeOf(context);
    final hosted =
        _usesFixedToolbar(context) &&
        (hostChrome?.hostsToolbar ?? false) &&
        (appBar?.useNativeToolbar ?? true);
    final inColumn = AdaptiveSplitView.isInColumn(context);
    final pose = DuoPoseScope.of(context);
    final strip = DuoTopStripScope.of(context);
    final hasTitle = appBar?.title != null || appBar?.titleWidget != null;
    // In the iPhone Duo vertical bar pose the controls of every page are in
    // the vertical bar, those of the pages in a column too.
    final controlsInBar =
        pose != null &&
        (hosted || (inColumn && AdaptiveSplitView.handsControlsToBar(context)));
    final ownBar = appBar != null && !hosted;

    // In the iPhone Duo's vertical bar poses the window has no inset at the
    // top. A page there starts below the title band if it has a title, and
    // otherwise still keeps clear of the window's rounded top edge, level
    // with the bar's first control. That is a floor rather than an addition,
    // so a page inside a tab layout that already kept it adds nothing.
    final inBarPose =
        pose != null &&
        (appBar == null ? _usesFixedToolbar(context) : hosted || controlsInBar);
    final double? topFloor = !inBarPose
        ? null
        : appBar != null && hasTitle
        ? kDuoTitleBandHeight
        : kDuoBarEdgeMargin;
    final double topInset;
    if (appBar == null || inBarPose) {
      topInset = 0;
    } else if (strip != null && hosted) {
      // The bar is in the strip, or below it while the tabs are in it.
      topInset =
          placement == AdaptiveChromePlacement.topStrip &&
              (_TabLayout.showsTabs(context) || _nativeTabBar != null)
          ? chrome.metrics.toolbarHeight
          : strip.overhang;
    } else if (ownBar && AdaptivePopover.isIn(context)) {
      // In a popover the bar is as tall as its controls, which sit in its
      // rounded corners as far from the top as from the side.
      topInset = chrome.metrics.backButtonSize + AdaptivePopover.barInset;
    } else {
      topInset = chrome.metrics.toolbarHeight;
    }

    final tabs = _nativeTabBar;
    final ownsTabs = tabs != null && _usesFixedToolbar(context);
    // The iPhone Duo strip beside a page the host draws the bar for is the
    // bar's: the content keeps out of it, while the page's background runs
    // under it. A tab layout leaves that to the pages inside it, so each of
    // those has its own background there.
    // Beside a sidebar the first page under the tab layout runs under it in
    // the same way, and takes its room over from the tab layout.
    final sidebarRoom = ownsTabs ? 0.0 : SidebarRoom.of(context);
    final padding = MediaQuery.paddingOf(context);
    final double sideInset;
    if (sidebarRoom > 0) {
      sideInset = widget.extendBodyBehindVerticalBar ? 0.0 : sidebarRoom;
    } else {
      sideInset =
          pose == null ||
              !(hosted || inColumn) ||
              ownsTabs ||
              widget.extendBodyBehindVerticalBar
          ? 0.0
          : pose.onLeft
          ? padding.left
          : padding.right;
    }
    final barOnLeft = sidebarRoom > 0 || (pose?.onLeft ?? false);

    Widget body = widget.body ?? const SizedBox.shrink();
    if (ownsTabs) {
      body = _TabLayout(
        ownerRoute: ModalRoute.of(context),
        hidesWhenPushed: tabs.hidesWhenPushed,
        hidesFor: tabs.hidesFor,
        child: _withBottomBarInset(
          context,
          placement == AdaptiveChromePlacement.sidebar
              ? _BesideSidebarBody(enabled: !widget.tabBarHidden, child: body)
              : body,
          ownerRoute: ModalRoute.of(context),
        ),
      );
      if (_tabsHostedAtBottom(context) &&
          widget.minimizeBehavior != TabBarMinimizeBehavior.never) {
        body = NotificationListener<ScrollNotification>(
          onNotification: _minimizeHostedTabBar,
          child: body,
        );
      }
    } else {
      body = _TabsLeaveWhenPushed(child: body);
    }
    // On the iPhone Duo held sideways the bars along the top move out of the
    // way as the page scrolls on: the title band, and what the page pins
    // below it (AdaptiveSafeAreaBar), also on a page without a title.
    final titleBand =
        (inBarPose || (pose != null && inColumn)) &&
        (appBar?.hidesOnScroll ?? true);
    _titleBandFollows(titleBand);
    body = NotificationListener<Notification>(
      onNotification: _trackScrollEdge,
      child: body,
    );

    // The scroll edge effect of the scroll views in the page, under the bar
    // if the page has one with a background.
    final edgeAlongTop =
        appBar != null && appBar.showsBackdrop && (!inBarPose || hasTitle);
    final page = Builder(
      builder: (context) {
        final inner = MediaQuery.of(context);
        final top = topFloor != null
            ? math.max(inner.padding.top, topFloor)
            : inner.padding.top + topInset;
        return MediaQuery(
          data: inner.copyWith(
            padding: inner.padding.copyWith(
              top: top,
              left: barOnLeft
                  ? math.max(0, inner.padding.left - sideInset)
                  : inner.padding.left,
              right: barOnLeft
                  ? inner.padding.right
                  : math.max(0, inner.padding.right - sideInset),
            ),
            viewPadding: inner.viewPadding.copyWith(
              top: topFloor != null
                  ? math.max(inner.viewPadding.top, topFloor)
                  : inner.viewPadding.top + topInset,
            ),
          ),
          child: AdaptiveScrollEdgeRegion(
            chrome: chrome,
            placement: placement,
            top: edgeAlongTop ? top : null,
            titleBand: inBarPose,
            hairline: appBar?.showsHairline ?? true,
            visibility: titleBand
                ? _titleBandShown
                : const AlwaysStoppedListenable<double>(1),
            color:
                _opaqueColor(appBar?.backdropColor) ??
                _opaqueColor(widget.backgroundColor) ??
                CupertinoColors.systemBackground.resolveFrom(context),
            data: appBar?.chromeData,
            child: body,
          ),
        );
      },
    );

    return Scaffold(
      key: widget.scaffoldKey,
      backgroundColor: widget.backgroundColor,
      resizeToAvoidBottomInset: widget.resizeToAvoidBottomInset,
      floatingActionButton: widget.floatingActionButton,
      drawer: widget.drawer,
      endDrawer: widget.endDrawer,
      drawerScrimColor: widget.drawerScrimColor,
      onDrawerChanged: widget.onDrawerChanged,
      onEndDrawerChanged: widget.onEndDrawerChanged,
      drawerEnableOpenDragGesture: widget.drawerEnableOpenDragGesture,
      endDrawerEnableOpenDragGesture: widget.endDrawerEnableOpenDragGesture,
      body: Stack(
        fit: StackFit.expand,
        children: [
          Padding(
            padding: EdgeInsets.only(
              left: barOnLeft ? sideInset : 0,
              right: barOnLeft ? 0 : sideInset,
            ),
            child: sidebarRoom > 0 ? SidebarRoom(width: 0, child: page) : page,
          ),
          if (ownBar)
            Positioned(
              left: sidebarRoom,
              right: 0,
              top: 0,
              child: _CustomInlineBar(
                appBar: appBar,
                chrome: chrome,
                placement: placement,
                showsControls: !controlsInBar,
                titleBand: controlsInBar,
                titleBandShown: titleBand
                    ? _titleBandShown
                    : kAlwaysCompleteAnimation,
                hasTabs: tabs != null,
              ),
            ),
        ],
      ),
    );
  }

  IconData _sfSymbolToCupertinoIcon(String sfSymbol) {
    const iconMap = {
      'house': CupertinoIcons.house,
      'house.fill': CupertinoIcons.house_fill,
      'magnifyingglass': CupertinoIcons.search,
      'heart': CupertinoIcons.heart,
      'heart.fill': CupertinoIcons.heart_fill,
      'person': CupertinoIcons.person,
      'person.fill': CupertinoIcons.person_fill,
      'gear': CupertinoIcons.settings,
      'star': CupertinoIcons.star,
      'star.fill': CupertinoIcons.star_fill,
      'bell': CupertinoIcons.bell,
      'bell.fill': CupertinoIcons.bell_fill,
      'bag': CupertinoIcons.bag,
      'bag.fill': CupertinoIcons.bag_fill,
      'bookmark': CupertinoIcons.bookmark,
      'bookmark.fill': CupertinoIcons.bookmark_fill,
      'info.circle': CupertinoIcons.info_circle,
      'info.circle.fill': CupertinoIcons.info_circle_fill,
      'plus.circle': CupertinoIcons.add_circled,
      'plus': CupertinoIcons.add,
      'checkmark.circle': CupertinoIcons.checkmark_circle,
    };
    return iconMap[sfSymbol] ?? CupertinoIcons.circle;
  }

  Widget _buildNavigationIconWidget({
    required dynamic rawIcon,
    Color? color,
    required TargetPlatform platform,
  }) {
    if (rawIcon is Widget) {
      return color != null && rawIcon is ImageIcon
          ? ImageIcon(rawIcon.image, color: color)
          : rawIcon;
    }

    if (rawIcon is ImageProvider) {
      return _NavigationImageIcon(image: rawIcon);
    }

    final IconData iconData;
    if (rawIcon is String) {
      iconData = platform == TargetPlatform.iOS
          ? _sfSymbolToCupertinoIcon(rawIcon)
          : Icons.circle;
    } else {
      iconData = rawIcon as IconData;
    }

    return color != null ? Icon(iconData, color: color) : Icon(iconData);
  }
}

class _NavigationImageIcon extends StatelessWidget {
  const _NavigationImageIcon({required this.image});

  final ImageProvider image;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 26,
      height: 26,
      child: ClipOval(
        child: Image(
          image: image,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) =>
              const Icon(CupertinoIcons.person_crop_circle),
        ),
      ),
    );
  }
}

/// Minimizable tab bar wrapper for iOS 26+ (used when useNativeToolbar: false)
/// Just handles animation, scroll notification is handled by parent
class _MinimizableTabBar extends StatefulWidget {
  const _MinimizableTabBar({
    super.key,
    required this.selectedIndex,
    required this.onTap,
    required this.destinations,
    required this.minimizeBehavior,
    required this.enableBlur,
    this.selectedItemColor,
    this.unselectedItemColor,
    this.hidden = false,
  });

  final int selectedIndex;
  final ValueChanged<int> onTap;
  final List<AdaptiveNavigationDestination> destinations;
  final TabBarMinimizeBehavior minimizeBehavior;
  final bool enableBlur;
  final Color? selectedItemColor;
  final Color? unselectedItemColor;
  final bool hidden;

  @override
  State<_MinimizableTabBar> createState() => _MinimizableTabBarState();
}

class _MinimizableTabBarState extends State<_MinimizableTabBar>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;
  bool _isMinimized = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 200),
      vsync: this,
    );
    _animation = CurvedAnimation(parent: _controller, curve: Curves.easeInOut);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  // Called from parent's NotificationListener
  void handleScrollNotification(ScrollNotification notification) {
    final minimized = _tabBarMinimizedAfter(
      notification,
      widget.minimizeBehavior,
      minimized: _isMinimized,
    );
    if (minimized == true) {
      _minimizeTabBar();
    } else if (minimized == false) {
      _expandTabBar();
    }
  }

  void _minimizeTabBar() {
    if (!_isMinimized && mounted) {
      _isMinimized = true;
      _controller.forward();
    }
  }

  void _expandTabBar() {
    if (_isMinimized && mounted) {
      _isMinimized = false;
      _controller.reverse();
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) {
        // Calculate minimized state
        // value: 0.0 = expanded (full size), 1.0 = minimized (70% size, 50% opacity)
        final minimizeProgress = _animation.value;
        final scale = 1.0 - (minimizeProgress * 0.3); // 1.0 → 0.7
        final opacity = 1.0 - (minimizeProgress * 0.5); // 1.0 → 0.5

        return Transform.scale(
          scale: scale,
          alignment: Alignment.bottomCenter,
          child: Opacity(opacity: opacity, child: child),
        );
      },
      child: IOS26NativeTabBar(
        destinations: widget.destinations,
        selectedIndex: widget.selectedIndex,
        onTap: widget.onTap,
        tint:
            widget.selectedItemColor ?? CupertinoTheme.of(context).primaryColor,
        unselectedItemTint: widget.unselectedItemColor,
        minimizeBehavior: widget.minimizeBehavior,
        hidden: widget.hidden,
      ),
    );
  }
}

/// Animated back button for iOS 26+
/// Fades out when pressed
class _AnimatedBackButton extends StatefulWidget {
  const _AnimatedBackButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  State<_AnimatedBackButton> createState() => _AnimatedBackButtonState();
}

class _AnimatedBackButtonState extends State<_AnimatedBackButton>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _opacityAnimation;
  bool _isPopping = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 400),
      vsync: this,
    );
    _opacityAnimation = Tween<double>(
      begin: 1.0,
      end: 0.0,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOut));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _handlePressed() {
    if (_isPopping) return;

    setState(() {
      _isPopping = true;
    });

    // Start animation and pop immediately (parallel)
    _controller.forward();
    widget.onPressed();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _opacityAnimation,
      builder: (context, child) {
        return Opacity(
          opacity: _isPopping ? 0.0 : _opacityAnimation.value,
          child: IgnorePointer(ignoring: _isPopping, child: child),
        );
      },
      child: SizedBox(
        height: 38,
        width: 38,
        child: AdaptiveButton.sfSymbol(
          onPressed: _handlePressed,
          sfSymbol: SFSymbol("chevron.left", size: 20),
        ),
      ),
    );
  }
}

/// Whether a native tab bar that [behavior] shrinks while the page scrolls
/// should be minimized after [notification]: true or false when that
/// changes, null when it stays as it is.
bool? _tabBarMinimizedAfter(
  ScrollNotification notification,
  TabBarMinimizeBehavior behavior, {
  required bool minimized,
}) {
  if (behavior == TabBarMinimizeBehavior.never) return null;
  if (notification is! ScrollUpdateNotification) return null;
  final delta = notification.scrollDelta ?? 0;
  final metrics = notification.metrics;
  // A carousel or a pager scrolling sideways says nothing about the page.
  if (metrics.axis != Axis.vertical) return null;
  if (behavior == TabBarMinimizeBehavior.onScrollDownUntilTop &&
      AdaptiveScrollEdge.of(metrics) == 0) {
    return minimized ? false : null;
  }

  // Check if we're in overscroll territory (pull-to-refresh or bottom bounce)
  // When pixels < minScrollExtent, user is pulling down beyond top (overscroll)
  // When pixels > maxScrollExtent, user is pulling up beyond bottom (overscroll)
  // Add tolerance (50px) to make it more stable - ignore scroll events near boundaries
  const overscrollTolerance = 50.0;
  final isOverscrolling =
      metrics.pixels < (metrics.minScrollExtent + overscrollTolerance) ||
      metrics.pixels > (metrics.maxScrollExtent - overscrollTolerance);

  // Ignore scroll events during overscroll to prevent tab bar animation during bounce
  if (isOverscrolling) return null;

  if (behavior == TabBarMinimizeBehavior.onScrollDownUntilTop) {
    if (delta > 0 && !minimized) return true;
  } else if (behavior == TabBarMinimizeBehavior.onScrollDown ||
      behavior == TabBarMinimizeBehavior.automatic) {
    // Minimize when scrolling down (positive delta)
    if (delta > 0 && !minimized) return true;
    if (delta < 0 && minimized) return false;
  } else if (behavior == TabBarMinimizeBehavior.onScrollUp) {
    // Minimize when scrolling up (negative delta)
    if (delta < 0 && !minimized) return true;
    if (delta > 0 && minimized) return false;
  }
  return null;
}

/// Raises the body's bottom padding to the native tab bar's [height] and
/// publishes it through [AdaptiveBottomBarInset], following the height as it
/// is measured: only this is built again when it changes, not the body.
class _BottomBarInset extends StatelessWidget {
  const _BottomBarInset({
    required this.height,
    required this.hidden,
    required this.child,
    this.ownerRoute,
    this.hidesWhenPushed = false,
    this.hidesFor,
  });

  final ValueListenable<double> height;

  /// The bar is hidden for now ([AdaptiveScaffold.tabBarHidden]): no inset.
  final bool hidden;
  final Widget child;

  /// The route of the page with the tabs, and whether its tabs leave while a
  /// page is pushed inside them: such a page takes the room back.
  final ModalRoute<Object?>? ownerRoute;
  final bool hidesWhenPushed;

  /// Which of those pages the tabs leave for
  /// ([AdaptiveBottomNavigationBar.hidesFor]).
  final RoutePredicate? hidesFor;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<double>(
      valueListenable: height,
      child: child,
      builder: (context, height, child) {
        final inset = hidden ? 0.0 : height;
        return AdaptiveBottomBarInset(
          height: inset,
          child: _BottomBarPadding(
            height: inset,
            ownerRoute: hidesWhenPushed ? ownerRoute : null,
            hidesFor: hidesFor,
            child: child!,
          ),
        );
      },
    );
  }
}

/// Raises the bottom padding of the media query to [height]. Only this
/// follows every change of the media query, such as each frame of the
/// keyboard sliding in, so the scaffold around it is not rebuilt for them and
/// does not publish its app bar again.
class _BottomBarPadding extends StatelessWidget {
  const _BottomBarPadding({
    required this.height,
    required this.child,
    this.ownerRoute,
    this.hidesFor,
  });

  final double height;
  final Widget child;

  /// The route of the page with the tabs, when they leave while a page is
  /// pushed inside them.
  final ModalRoute<Object?>? ownerRoute;

  /// Which of those pages the tabs leave for.
  final RoutePredicate? hidesFor;

  @override
  Widget build(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    final bottom = math.max(mediaQuery.padding.bottom, height);
    final viewBottom = math.max(mediaQuery.viewPadding.bottom, height);
    return MediaQuery(
      data: mediaQuery.copyWith(
        padding: mediaQuery.padding.copyWith(bottom: bottom),
        viewPadding: mediaQuery.viewPadding.copyWith(bottom: viewBottom),
      ),
      child: _RaisedForTabs(
        ownerRoute: ownerRoute,
        hidesFor: hidesFor,
        padding: bottom - mediaQuery.padding.bottom,
        viewPadding: viewBottom - mediaQuery.viewPadding.bottom,
        child: child,
      ),
    );
  }
}

/// How far the page with the tabs raised the bottom padding for them, for
/// the pages pushed inside its tab layout, which the tabs leave
/// ([AdaptiveBottomNavigationBar.hidesWhenPushed]): they take it back.
class _RaisedForTabs extends InheritedWidget {
  const _RaisedForTabs({
    required this.ownerRoute,
    required this.padding,
    required this.viewPadding,
    required super.child,
    this.hidesFor,
  });

  /// Null when the tabs stay while pages are pushed inside them.
  final ModalRoute<Object?>? ownerRoute;

  /// Which of those pages the tabs leave for; all of them when null.
  final RoutePredicate? hidesFor;
  final double padding;
  final double viewPadding;

  @override
  bool updateShouldNotify(_RaisedForTabs oldWidget) =>
      ownerRoute != oldWidget.ownerRoute ||
      hidesFor != oldWidget.hidesFor ||
      padding != oldWidget.padding ||
      viewPadding != oldWidget.viewPadding;
}

/// The pages of a tab layout beside the sidebar of custom chrome, following
/// its width as it eases between a rail and its full width. What the sidebar
/// covers of the window's padding at that edge is taken from it.
class _BesideSidebarBody extends StatelessWidget {
  const _BesideSidebarBody({required this.enabled, required this.child});

  /// Whether the sidebar is there: a tab layout that hides its tabs
  /// (`AdaptiveScaffold.tabBarHidden`) hides it, and its pages take the room.
  final bool enabled;

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<double>(
      valueListenable: AdaptiveChromeScope.sidebarInsetOf(context),
      child: child,
      builder: (context, sidebarInset, child) {
        final inset = enabled ? sidebarInset : 0.0;
        final mediaQuery = MediaQuery.of(context);
        // The pages run on under the sidebar, and the first of them keeps
        // its content clear of it (SidebarRoom).
        return MediaQuery(
          data: mediaQuery.copyWith(
            padding: mediaQuery.padding.copyWith(
              left: math.max(mediaQuery.padding.left, inset),
            ),
            viewPadding: mediaQuery.viewPadding.copyWith(
              left: math.max(mediaQuery.viewPadding.left, inset),
            ),
          ),
          child: SidebarRoom(width: inset, child: child!),
        );
      },
    );
  }
}

/// The tab layout a page is in, from the scaffold that owns the tabs: the
/// route of that scaffold, and whether its tabs leave for pages pushed
/// inside it.
class _TabLayout extends InheritedWidget {
  const _TabLayout({
    required this.ownerRoute,
    required this.hidesWhenPushed,
    required super.child,
    this.hidesFor,
  });

  final ModalRoute<Object?>? ownerRoute;
  final bool hidesWhenPushed;
  final RoutePredicate? hidesFor;

  /// Whether the tabs show while the page at [context] is in front: it is
  /// in a tab layout, and is not a page pushed inside one whose tabs leave
  /// for it. The same rule the toolbar registry follows.
  static bool showsTabs(BuildContext context) {
    final layout = context.dependOnInheritedWidgetOfExactType<_TabLayout>();
    if (layout == null) return false;
    final ownerRoute = layout.ownerRoute;
    if (!layout.hidesWhenPushed || ownerRoute == null) return true;
    if (ToolbarRegistry.maybeOf(context)?.keepsTabsOnPush ?? false) {
      return true;
    }
    return !_TabsLeaveWhenPushed._pushedWithin(
      context,
      ownerRoute,
      layout.hidesFor,
    );
  }

  @override
  bool updateShouldNotify(_TabLayout oldWidget) =>
      ownerRoute != oldWidget.ownerRoute ||
      hidesWhenPushed != oldWidget.hidesWhenPushed ||
      hidesFor != oldWidget.hidesFor;
}

/// Gives a page pushed inside a tab layout whose tabs leave for it
/// ([AdaptiveBottomNavigationBar.hidesWhenPushed]) back the room the tabs
/// took at the bottom, as UIKit does for `hidesBottomBarWhenPushed`. The tab
/// pages themselves keep it, and so does every page while the tabs stay (in
/// a sidebar).
class _TabsLeaveWhenPushed extends StatelessWidget {
  const _TabsLeaveWhenPushed({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final raised = context.dependOnInheritedWidgetOfExactType<_RaisedForTabs>();
    final ownerRoute = raised?.ownerRoute;
    final keepsTabs =
        ToolbarRegistry.maybeOf(context)?.keepsTabsOnPush ?? false;
    if (ownerRoute == null ||
        keepsTabs ||
        !_pushedWithin(context, ownerRoute, raised?.hidesFor)) {
      return child;
    }
    final mediaQuery = MediaQuery.of(context);
    return MediaQuery(
      data: mediaQuery.copyWith(
        padding: mediaQuery.padding.copyWith(
          bottom: math.max(0, mediaQuery.padding.bottom - raised!.padding),
        ),
        viewPadding: mediaQuery.viewPadding.copyWith(
          bottom: math.max(
            0,
            mediaQuery.viewPadding.bottom - raised.viewPadding,
          ),
        ),
      ),
      child: AdaptiveBottomBarInset(
        height: 0,
        child: _RaisedForTabs(
          ownerRoute: null,
          padding: 0,
          viewPadding: 0,
          child: child,
        ),
      ),
    );
  }

  /// Whether the page at [context] was pushed on a navigator inside
  /// [ownerRoute], rather than being the first page of each navigator in
  /// between, by a route that [hidesFor] the tabs leave for: the same rule
  /// the toolbar registry hides the tabs by.
  static bool _pushedWithin(
    BuildContext context,
    ModalRoute<Object?> ownerRoute, [
    RoutePredicate? hidesFor,
  ]) {
    var route = ModalRoute.of(context);
    var navigator = Navigator.maybeOf(context);
    final registry = ToolbarRegistry.maybeOf(context);
    while (route != null && route != ownerRoute) {
      if (!route.isFirst &&
          (hidesFor == null ||
              (registry?.hidesTabsFor(route, hidesFor) ?? hidesFor(route)))) {
        return true;
      }
      final outer = navigator?.context;
      if (outer == null) return false;
      route = ModalRoute.of(outer);
      navigator = outer.findAncestorStateOfType<NavigatorState>();
    }
    return false;
  }
}

/// The bar a page draws itself with custom chrome, where the host's bar
/// does not reach it: in a sheet, a dialog, or a column of a split view. In
/// the iPhone Duo vertical bar pose it shows only the title, in the title
/// band, as the host does: the controls are in the vertical bar.
class _CustomInlineBar extends StatelessWidget {
  const _CustomInlineBar({
    required this.appBar,
    required this.chrome,
    required this.placement,
    required this.showsControls,
    required this.titleBand,
    required this.titleBandShown,
    required this.hasTabs,
  });

  final AdaptiveAppBar appBar;
  final AdaptiveChrome chrome;
  final AdaptiveChromePlacement placement;
  final bool showsControls;
  final bool titleBand;
  final Animation<double> titleBandShown;
  final bool hasTabs;

  @override
  Widget build(BuildContext context) {
    final top =
        MediaQuery.paddingOf(context).top +
        (!titleBand && AdaptivePopover.isIn(context)
            ? AdaptivePopover.barInset
            : 0);
    final metrics = chrome.metrics;
    final inPopover = !titleBand && AdaptivePopover.isIn(context);
    final height = titleBand
        ? kDuoTitleBandHeight
        : top + (inPopover ? metrics.backButtonSize : metrics.toolbarHeight);
    final centered = titleBand
        ? chrome.centerTitleBand
        : chrome.centersTitle(defaultTargetPlatform);
    final title = chrome.titleBuilder(
      context,
      AdaptiveTitleSpec(
        placement: placement,
        title: appBar.title,
        subtitle: appBar.subtitle,
        titleWidget: appBar.titleWidget,
        centered: centered,
        data: appBar.chromeData,
      ),
    );
    // The background under the bar is the scroll edge of the page's scroll
    // views (AdaptiveScrollEdgeRegion), as under the host's bar.
    if (titleBand) {
      return DuoTitleBandTransition(
        shown: titleBandShown,
        child: SizedBox(
          height: height,
          child: DuoToolbarTitle(titleWidget: title, centered: centered),
        ),
      );
    }

    final canPop = Navigator.maybeOf(context)?.canPop() ?? false;
    final impliesBack =
        showsControls &&
        appBar.leading == null &&
        !hasTabs &&
        (appBar.onBack != null ||
            (appBar.automaticallyImplyLeading && canPop)) &&
        !AdaptiveSplitView.hidesBackButton(context);
    final actions = showsControls
        ? appBar.actions ?? const <AdaptiveAppBarAction>[]
        : const <AdaptiveAppBarAction>[];
    final leading = showsControls ? appBar.leading : null;
    // In a popover the controls sit in its rounded corners, as far from the
    // side as from the top.
    final side = !titleBand && AdaptivePopover.isIn(context)
        ? AdaptivePopover.barInset
        : metrics.controlInset;
    return SizedBox(
      height: height,
      child: Stack(
        fit: StackFit.expand,
        clipBehavior: Clip.none,
        children: [
          Padding(
            padding: EdgeInsets.only(top: top),
            child: NavigationToolbar(
              leading: Padding(
                padding: EdgeInsetsDirectional.only(
                  start: leading != null || impliesBack
                      ? side
                      : 16 - kToolbarTitleSpacing,
                ),
                child:
                    leading ??
                    (impliesBack
                        ? chrome.backButtonBuilder(
                            context,
                            AdaptiveBackButtonSpec(
                              placement: placement,
                              style: appBar.backButtonStyle,
                              data: appBar.chromeData,
                              onPressed: () {
                                AdaptiveSplitView.willGoBackFrom(context);
                                final onBack = appBar.onBack;
                                if (onBack != null) {
                                  onBack();
                                } else {
                                  Navigator.of(context).maybePop();
                                }
                              },
                            ),
                          )
                        : null),
              ),
              middle: title,
              trailing: actions.isEmpty
                  ? const SizedBox(width: 16 - kToolbarTitleSpacing)
                  : Padding(
                      padding: EdgeInsetsDirectional.only(end: side),
                      child: chrome.actionsBuilder(
                        context,
                        AdaptiveActionsSpec(
                          placement: placement,
                          actions: actions,
                          axis: Axis.horizontal,
                          tint: appBar.tintColor,
                          data: appBar.chromeData,
                          onPressed: (action, anchor) => action.press(anchor),
                        ),
                      ),
                    ),
              centerMiddle: centered,
              middleSpacing: kToolbarTitleSpacing,
            ),
          ),
        ],
      ),
    );
  }
}

/// A value a page hands the toolbar host in its [ToolbarEntry]. The host
/// keeps showing a page for a moment after it has gone (its items fade out
/// as the next page's fade in), so it may still listen once the page has
/// disposed the value: it then keeps its last value.
class _PageValue<T> extends ValueNotifier<T> {
  _PageValue(super.value);

  bool _disposed = false;

  @override
  void addListener(VoidCallback listener) {
    if (!_disposed) super.addListener(listener);
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

/// [color] when it covers what is under it, so a see-through colour asks for
/// the page's own instead of a black backdrop.
Color? _opaqueColor(Color? color) =>
    color == null || color.a < 1 ? null : color;
