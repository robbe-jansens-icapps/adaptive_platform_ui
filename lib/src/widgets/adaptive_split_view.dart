import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show DisplayFeatureState, DisplayFeatureType;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../platform/platform_info.dart';
import '../toolbar/duo_top_strip.dart';
import '../toolbar/duo_vertical_bar.dart';
import '../toolbar/fold_scope.dart';
import '../toolbar/toolbar_chrome_scope.dart';

/// A list and the page picked from it side by side, as `UISplitViewController`
/// shows them on iPad and on the iPhone Duo inner display, and as the
/// list-detail layout of Material 3 does on Android tablets and foldables.
///
/// On a window at least [minWidth] wide, [master] (a page with a list) keeps
/// the leading column, and the pages picked from it open in a column beside
/// it, with a navigator of their own. A page picked in the list replaces what
/// that column shows, at once, as a sidebar does; a page opened from a page in
/// the column slides in over it, and goes back with its back button or a swipe
/// from the column's edge. Each column has its own bar. Until something is
/// picked, the column shows [initialDetail], or else [placeholder].
///
/// On a narrower window only [master] shows, and the pages open over it, on
/// the navigator the split view is on, as they always would. Folding or
/// unfolding a foldable keeps the user where they were: as the window
/// narrows, the pages beside the list move over it; as it widens, the pages
/// open over the list move beside it, as deep as they were, with the list
/// showing which one is open.
///
/// Pages reach the split view through [showDetail]: navigation code calls it
/// before it opens a page the usual way, and only opens the page itself when
/// it returns false. Going back needs no change: a pop of the navigator the
/// split view is on (the back button of Android, or `Navigator.pop` from a
/// page's own back handler) first goes back in the column.
class AdaptiveSplitView extends StatefulWidget {
  const AdaptiveSplitView({
    super.key,
    required this.master,
    required this.onGenerateDetailRoute,
    this.initialDetail,
    this.placeholder,
    this.backgroundColor,
    this.minWidth = 700,
    this.showsDetailColumn = true,
    this.onPushedOver,
  });

  /// The page with the list, in the leading column. On a narrow window, the
  /// whole split view.
  final Widget master;

  /// Builds the pages that [showDetail] opens, from their name and arguments:
  /// usually the app's own route factory, so a page opens the same way beside
  /// the list as on its own.
  final RouteFactory onGenerateDetailRoute;

  /// The page the column shows while nothing has been picked in the list,
  /// such as its first item, as iPad Settings opens on General.
  final RouteSettings? initialDetail;

  /// What the column shows while nothing has been picked and there is no
  /// [initialDetail]. Empty by default.
  final Widget? placeholder;

  /// Behind the columns, and the column while it shows nothing. The system's
  /// grouped background on iOS and the surface color on Android by default.
  final Color? backgroundColor;

  /// From this width on, the columns show side by side.
  final double minWidth;

  /// Whether the column beside the list shows on a wide window. False keeps
  /// the list at the full width for now, such as while the page with the list
  /// shows a section that has nothing to open beside it (a timetable, a
  /// map). The pages open in the column wait meanwhile, rather than move over
  /// the list, and come back as the column does. Pages opened meanwhile open
  /// over the list, as on a narrow window.
  final bool showsDetailColumn;

  /// Called with every page the split view opens over its list, on the
  /// navigator it is on: a page opened on a narrow window, and the pages that
  /// move over the list as the window narrows. Lets navigation code that
  /// keeps track of the pages it opens know of these too.
  final ValueChanged<Route<dynamic>>? onPushedOver;

  /// Opens the page [settings] names from the split view in front: one on
  /// screen (on the selected tab), on the page in front or under the pages
  /// it opened. On a wide window the page opens in the column beside the
  /// list: a page picked in the list replaces what the column shows, and one
  /// opened from a page in the column goes on top of it. On a narrow window
  /// it opens over the list, as it would anyway, and the split view keeps it
  /// in mind to show it beside the list once the window widens.
  ///
  /// Returns false when no split view is in front: the caller then opens the
  /// page itself, as it always did.
  static bool showDetail(RouteSettings settings) {
    for (final state in _AdaptiveSplitViewState._mounted.reversed) {
      if (state._isInFront) return state._show(settings);
    }
    return false;
  }

  /// The page picked in the list of the split view around [context] (or
  /// shown first, [initialDetail]), while that split view shows its columns
  /// side by side; null otherwise. Lets the list show which item is open.
  static RouteSettings? selectedDetailOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_SplitScope>()?.selected;

  /// Whether [context] is in the list of a split view that shows its columns
  /// side by side. Its rows open a page beside the list rather than over it,
  /// so they go without the chevron of a row that opens a page.
  static bool isInList(BuildContext context) {
    final column = context.dependOnInheritedWidgetOfExactType<_ColumnScope>();
    return column != null && !column.isDetail;
  }

  /// Whether [context] is in the column beside the list of a split view that
  /// shows its columns side by side. Does not rebuild [context] when that
  /// changes, so it can be asked while handling a notification.
  static bool isInDetailColumn(BuildContext context) =>
      context.getInheritedWidgetOfExactType<_ColumnScope>()?.isDetail ?? false;

  /// Whether [context] is in a column of a split view that shows its columns
  /// side by side. A page there keeps its own bar instead of handing it to a
  /// fixed toolbar that spans the window.
  static bool isInColumn(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_ColumnScope>() != null;

  /// Whether the page at [context], in a column of a split view, hands its
  /// back button and actions to the iPhone Duo vertical bar of the fixed
  /// toolbar, as every page does in that pose, and keeps only its title in
  /// its column.
  static bool handsControlsToBar(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_ColumnScope>()?.duoControls ??
      false;

  /// Whether the page at [context] goes without a back button: it is the
  /// first page of the column beside the list, which has nothing to go back
  /// to. On its own, on a narrow window, it keeps it.
  static bool hidesBackButton(BuildContext context) {
    final column = context.dependOnInheritedWidgetOfExactType<_ColumnScope>();
    if (column == null || !column.isDetail) return false;
    return ModalRoute.of(context)?.isFirst ?? false;
  }

  /// Call before the page at [context] goes back with a pop of its navigator.
  /// From the list's page, that closes the page with the split view on it,
  /// and not the page open beside the list. Does nothing elsewhere.
  static void willGoBackFrom(BuildContext context) {
    final column = context.getInheritedWidgetOfExactType<_ColumnScope>();
    if (column == null || column.isDetail) return;
    column.state._forgetHistory();
  }

  @override
  State<AdaptiveSplitView> createState() => _AdaptiveSplitViewState();
}

class _AdaptiveSplitViewState extends State<AdaptiveSplitView>
    with SingleTickerProviderStateMixin {
  static final _mounted = <_AdaptiveSplitViewState>[];

  /// How far the divider has moved onto the fold of a half-opened foldable:
  /// 0 where it stands on a flat window, 1 on the fold.
  late final AnimationController _onFold;
  late final CurvedAnimation _toFold;

  /// The fold the divider is on or moving onto, and the one it moves off as
  /// the foldable lies flat again, across the window.
  double? _foldX;
  bool _hasFold = false;

  final _masterKey = GlobalKey(debugLabel: 'AdaptiveSplitView master');

  /// The navigator of the column. A new one for every column that comes, so
  /// that it starts from where the user is, not from what an earlier column
  /// showed.
  var _detailKey = GlobalKey<NavigatorState>(
    debugLabel: 'AdaptiveSplitView detail',
  );
  late final _observer = _DetailObserver(this);

  /// Whether the columns show side by side.
  bool _wide = false;

  /// The pages of the column, from its first one up.
  final _details = <Route<dynamic>>[];

  /// While the columns show side by side: the page picked in the list, or
  /// the [AdaptiveSplitView.initialDetail] shown before anything was.
  RouteSettings? _selected;

  /// Whether the page beside the list was picked, rather than shown first.
  bool _picked = false;

  /// Whether the last press went down in the list rather than in the column.
  bool _pressInMaster = false;

  /// Whether the column shows [AdaptiveSplitView.placeholder], for want of a
  /// page to show.
  bool _showsPlaceholder = false;

  /// The pages opened over the list on a narrow window, from the one picked
  /// in the list up: they move beside it once the window widens.
  final _pagesOver = <Route<dynamic>>[];

  /// The pages the user is on, waiting for a place: in the column that
  /// comes next, or else over the list.
  List<RouteSettings>? _restored;

  /// The pages of a column that [AdaptiveSplitView.showsDetailColumn] put
  /// away for now: they come back with the column, and never over the list.
  List<RouteSettings>? _parked;

  /// One entry on the split view's own route for every page of the column
  /// above its first: a pop of the navigator the split view is on then goes
  /// back in the column first.
  final _history = <Route<dynamic>, LocalHistoryEntry>{};
  bool _forgetting = false;

  ModalRoute<Object?>? _route;

  @override
  void initState() {
    super.initState();
    _mounted.add(this);
    _onFold = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _toFold = CurvedAnimation(parent: _onFold, curve: Curves.easeInOutCubic);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _route = ModalRoute.of(context);
  }

  @override
  void dispose() {
    _mounted.remove(this);
    _forgetHistory();
    _toFold.dispose();
    _onFold.dispose();
    super.dispose();
  }

  /// The smallest a column gets as the divider moves onto a fold. A fold
  /// closer to an edge than this is left alone.
  static const _minColumnOnFold = 280.0;

  /// Where a fold of a half-opened foldable runs down the window, from the
  /// left of the window: the columns then meet on it, as on the iPhone Duo
  /// and in the list-detail layout of Material 3. Null for a foldable that
  /// lies flat and for a fold that runs across the window.
  double? _foldAcross(BuildContext context) {
    final folds = <Rect>[
      for (final feature in MediaQuery.displayFeaturesOf(context))
        if (feature.type == DisplayFeatureType.hinge ||
            (feature.type == DisplayFeatureType.fold &&
                feature.state == DisplayFeatureState.postureHalfOpened))
          feature.bounds,
      ?FoldScope.hingeOf(context),
    ];
    for (final fold in folds) {
      if (fold.height > fold.width) return fold.center.dx;
    }
    return null;
  }

  /// Moves the divider onto the fold, or off it, after this frame: a fold
  /// that comes or goes is noticed as the split view builds.
  void _followFold(bool hasFold) {
    if (hasFold == _hasFold) return;
    _hasFold = hasFold;
    if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) {
      _onFold.value = hasFold ? 1 : 0;
      return;
    }
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_hasFold) {
        _onFold.forward();
      } else {
        _onFold.reverse();
      }
    });
  }

  /// Whether the tab the split view is on is the one in sight. A tab out of
  /// sight is hidden with `Visibility` (an `IndexedStack`), or only has its
  /// tickers turned off (`Offstage`, or a stack that fades its tabs): it is
  /// laid out all the same, so neither alone tells.
  static bool _inSight(BuildContext context) =>
      Visibility.of(context) &&
      TickerMode.getValuesNotifier(context).value.enabled;

  /// Whether this split view shows a column beside its list right now, on the
  /// page in front, on screen.
  bool get _isInFront {
    if (!mounted) return false;
    _pagesOver.removeWhere((page) => !page.isActive);
    // A tab that is not selected keeps its page, out of sight.
    if (!Visibility.of(context)) return false;
    // Under the pages it opened over the list on a narrow window. Covered,
    // the split view has its tickers off; the page over it has them on,
    // unless its tab is out of sight too.
    if (!_wide && _pagesOver.isNotEmpty && _pagesOver.last.isCurrent) {
      final page = _pagesOver.last;
      final pageContext = page is ModalRoute ? page.subtreeContext : null;
      return pageContext == null || _inSight(pageContext);
    }
    if (_wide && _detailKey.currentState == null) return false;
    return (_route?.isCurrent ?? true) &&
        TickerMode.getValuesNotifier(context).value.enabled;
  }

  bool _show(RouteSettings settings) {
    if (!_wide) return _showOver(settings);
    final navigator = _detailKey.currentState;
    if (navigator == null) return false;
    if (_pressInMaster) {
      setState(() {
        _selected = settings;
        _picked = true;
      });
      navigator.pushAndRemoveUntil(_shownAtOnce(settings), (_) => false);
    } else {
      final route = widget.onGenerateDetailRoute(settings);
      if (route == null) return false;
      navigator.push(route);
    }
    return true;
  }

  /// On a narrow window: opens the page over the list, and keeps it in mind.
  bool _showOver(RouteSettings settings) {
    final navigator = _route?.navigator;
    final route = widget.onGenerateDetailRoute(settings);
    if (navigator == null || route == null) return false;
    // What the user opens now is where they are; a column put away goes.
    _parked = null;
    _pagesOver.add(route);
    navigator.push(route);
    widget.onPushedOver?.call(route);
    return true;
  }

  /// The page [settings] names, without a transition: what a sidebar does
  /// when another item is picked.
  Route<dynamic> _shownAtOnce(RouteSettings settings) {
    final route = widget.onGenerateDetailRoute(settings);
    final builder = switch (route) {
      MaterialPageRoute<dynamic>(:final builder) => builder,
      CupertinoPageRoute<dynamic>(:final builder) => builder,
      _ => null,
    };
    if (route == null || builder == null) {
      return route ?? _placeholderRoute();
    }
    return PageRouteBuilder<dynamic>(
      settings: route.settings,
      pageBuilder: (context, _, _) => builder(context),
      transitionDuration: Duration.zero,
      reverseTransitionDuration: Duration.zero,
    );
  }

  static const _placeholderName = 'AdaptiveSplitView.placeholder';

  Route<dynamic> _placeholderRoute() => PageRouteBuilder<void>(
    settings: const RouteSettings(name: _placeholderName),
    pageBuilder: (context, _, _) =>
        widget.placeholder ?? ColoredBox(color: _backgroundOf(context)),
    transitionDuration: Duration.zero,
    reverseTransitionDuration: Duration.zero,
  );

  List<Route<dynamic>> _initialRoutes(NavigatorState _, String _) {
    final restored = _restored;
    _restored = null;
    if (restored != null && restored.isNotEmpty) {
      _showsPlaceholder = false;
      return [
        _shownAtOnce(restored.first),
        for (final settings in restored.skip(1))
          ?widget.onGenerateDetailRoute(settings),
      ];
    }
    final selected = _selected;
    _showsPlaceholder = selected == null;
    return [selected == null ? _placeholderRoute() : _shownAtOnce(selected)];
  }

  /// Shows [AdaptiveSplitView.initialDetail] in the column, which arrives
  /// with the list once that has loaded.
  void _showInitialDetail() {
    // The column comes back with the pages that were open over the list.
    final restored = _restored;
    if (restored != null && restored.isNotEmpty) {
      _selected = restored.first;
      _picked = true;
      return;
    }
    final initial = _selected ??= widget.initialDetail;
    if (!_showsPlaceholder || initial == null) return;
    _showsPlaceholder = false;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _picked || _selected != initial) return;
      _detailKey.currentState?.pushAndRemoveUntil(
        _shownAtOnce(initial),
        (_) => false,
      );
    });
  }

  // The pages of the column ------------------------------------------------

  void _onDetailsChanged() => scheduleMicrotask(() {
    _syncHistory();
    _syncSelection();
  });

  /// The list shows the page the column starts with as the one open,
  /// whatever brought it there.
  void _syncSelection() {
    if (!mounted || !_wide || _details.isEmpty) return;
    final first = _details.first.settings;
    if (first.name == _placeholderName || identical(first, _selected)) return;
    setState(() => _selected = first);
  }

  void _syncHistory() {
    if (!mounted) return;
    final route = _route;
    if (route == null) return;
    final above = _details.skip(1).toSet();
    for (final page in [..._history.keys]) {
      if (!above.contains(page)) _removeEntry(page);
    }
    for (final page in above) {
      if (_history.containsKey(page)) continue;
      final entry = LocalHistoryEntry(onRemove: () => _onEntryRemoved(page));
      _history[page] = entry;
      route.addLocalHistoryEntry(entry);
    }
  }

  void _removeEntry(Route<dynamic> page) {
    final entry = _history.remove(page);
    if (entry == null) return;
    _forgetting = true;
    try {
      entry.remove();
    } finally {
      _forgetting = false;
    }
  }

  /// Takes the entries off the split view's route without going back in the
  /// column: its page itself goes, or the column does.
  void _forgetHistory() {
    for (final page in [..._history.keys]) {
      _removeEntry(page);
    }
  }

  /// A pop of the navigator the split view is on took [page]'s entry: the
  /// column goes back from it.
  void _onEntryRemoved(Route<dynamic> page) {
    if (_forgetting) return;
    _history.remove(page);
    final navigator = _detailKey.currentState;
    if (navigator == null || !page.isActive) return;
    if (page.isCurrent) {
      navigator.pop();
    } else {
      navigator.removeRoute(page);
    }
  }

  // Narrowing ----------------------------------------------------------------

  /// The window got too narrow for the columns: the pages picked in the list
  /// move over it, onto the navigator the split view is on, so they stay on
  /// screen. They are there at once, and go back as pages do. Called as the
  /// column goes, during layout: the rest waits for the frame.
  ///
  /// With [park] the column only goes for now
  /// ([AdaptiveSplitView.showsDetailColumn]): its pages wait for it to come
  /// back instead.
  void _collapse({bool park = false}) {
    // Pages picked in the list, or opened from the page shown first; or
    // those still on their way into a column that is gone again.
    final pages =
        _restored ??
        (_picked || _details.length > 1
            ? [
                for (final page in _details)
                  if (page.settings.name != _placeholderName) page.settings,
              ]
            : const <RouteSettings>[]);
    if (park) {
      _parked = pages.isEmpty ? null : pages;
      _restored = null;
    } else {
      _restored = pages.isEmpty ? null : pages;
    }
    _details.clear();
    _selected = null;
    _picked = false;
    _showsPlaceholder = false;
    // The column goes; one that comes back starts from where the user is.
    _detailKey = GlobalKey<NavigatorState>(
      debugLabel: 'AdaptiveSplitView detail',
    );
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _syncHistory();
      _restoreOver();
    });
  }

  /// Puts the pages waiting for a place over the list. On a tab out of sight
  /// they wait until it is selected again, rather than cover the tab in view.
  void _restoreOver() {
    // A column that came back in the meantime took the pages.
    final pages = _restored;
    if (!mounted || _wide || pages == null || !_inSight(context)) return;
    _restored = null;
    final navigator = _route?.navigator;
    // Not over another page that covers the list.
    if (navigator == null || !(_route?.isCurrent ?? false)) return;
    for (final settings in pages) {
      final route = _arrivedAt(widget.onGenerateDetailRoute(settings));
      if (route == null) continue;
      _pagesOver.add(route);
      navigator.push(route);
      widget.onPushedOver?.call(route);
    }
  }

  /// The window got wide enough for the columns: the pages open over the
  /// list move beside it, as deep as they were, the list showing which one
  /// is open, so the user lands where they left off. Only when they are the
  /// pages in front: under another page they stay where they are. Called as
  /// the column comes, during layout: the pages over the list go after it.
  void _expand() {
    _pagesOver.removeWhere((page) => !page.isActive);
    final pages = [..._pagesOver];
    _pagesOver.clear();
    final parked = _parked;
    _parked = null;
    if (pages.isNotEmpty && pages.last.isCurrent) {
      _restored = [for (final page in pages) page.settings];
      _moving
        ..clear()
        ..addAll(pages);
      SchedulerBinding.instance.addPostFrameCallback((_) {
        for (final page in pages.reversed) {
          if (page.isActive) page.navigator?.removeRoute(page);
        }
      });
    } else if (_restored == null && parked != null) {
      // The column put away comes back as it was.
      _restored = parked;
    }
    // The column starts with what the user is on, or else with the page
    // shown first: nothing picked on the narrow window counts once the user
    // went back to the list.
    final restored = _restored;
    _selected = restored?.first;
    _picked = restored != null;
  }

  /// [route] there at once, as if it had been open all along, and leaving
  /// as it would.
  Route<dynamic>? _arrivedAt(Route<dynamic>? route) => switch (route) {
    MaterialPageRoute<dynamic>(:final builder, :final settings) =>
      _ArrivedPageRoute<dynamic>(builder: builder, settings: settings),
    _ => route,
  };

  // Layout -------------------------------------------------------------------

  Color _backgroundOf(BuildContext context) =>
      widget.backgroundColor ??
      (PlatformInfo.isAndroid
          ? Theme.of(context).colorScheme.surface
          : CupertinoColors.systemGroupedBackground.resolveFrom(context));

  /// How much narrower than the window the split view was at its last
  /// layout, such as beside a navigation rail.
  double _inset = 0;

  /// The pages on their way from over the list into the column. Until they
  /// are gone from over it, the split view is out of view, and what its
  /// layout says of the window is out of date.
  final _moving = <Route<dynamic>>[];

  @override
  Widget build(BuildContext context) {
    // Under the pages it opened over the list, the split view is not laid
    // out, so it learns of a window that widens here: by the width it had to
    // spare at its last layout, it can show the pages beside the list.
    final window = MediaQuery.sizeOf(context).width;
    if (!_wide &&
        widget.showsDetailColumn &&
        _pagesOver.isNotEmpty &&
        window - _inset >= widget.minWidth) {
      _wide = true;
      _expand();
    }
    // Its tab, selected again, shows the pages that waited for it.
    // `TickerMode.valuesOf` replaces this, but only exists in Flutter
    // releases after 3.35; `of` works on every supported version.
    // ignore: deprecated_member_use
    final visible = Visibility.of(context) && TickerMode.of(context);
    if (!_wide && _restored != null && visible) {
      SchedulerBinding.instance.addPostFrameCallback((_) => _restoreOver());
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        // Rebuilt while still out of view, it is handed the width of its
        // last layout, on the narrow window, or of a window on its way: that
        // width says nothing new.
        _moving.removeWhere((page) => !page.isActive);
        final stale = _moving.isNotEmpty;
        if (!stale) _inset = window - constraints.maxWidth;
        final roomy = constraints.maxWidth >= widget.minWidth;
        final wide = stale ? _wide : roomy && widget.showsDetailColumn;
        if (wide != _wide) {
          _wide = wide;
          if (wide) {
            _expand();
          } else {
            _collapse(park: roomy);
          }
        }
        final master = KeyedSubtree(key: _masterKey, child: widget.master);
        if (!wide) return master;
        _showInitialDetail();
        return _SplitScope(
          selected: _selected,
          child: _columns(context, constraints, master),
        );
      },
    );
  }

  Widget _columns(
    BuildContext context,
    BoxConstraints constraints,
    Widget master,
  ) {
    final padding = MediaQuery.paddingOf(context);
    // The iPhone Duo vertical bar keeps its strip: the columns lie beside it.
    final bar = DuoLayout.barSide(MediaQuery.viewPaddingOf(context));
    final left = bar == DuoBarSide.left ? padding.left : 0.0;
    final right = bar == DuoBarSide.right ? padding.right : 0.0;
    final width = constraints.maxWidth - left - right;
    final android = PlatformInfo.isAndroid;
    // In the iPhone Duo vertical bar pose, the fixed toolbar holds the
    // controls of every page, those in the columns included: each column
    // keeps its title.
    final duoControls =
        ToolbarChromeScope.maybeOf(context)?.hostsDuoControls ?? false;
    final divider = android ? 1.0 : 1 / MediaQuery.devicePixelRatioOf(context);
    final dividerColor = android
        ? Theme.of(context).colorScheme.outlineVariant
        : CupertinoColors.separator.resolveFrom(context);
    // The split view reaches the right edge of the window: beside a
    // navigation rail, it leaves out room on the left.
    final start =
        MediaQuery.sizeOf(context).width - constraints.maxWidth + left;
    final fold = _foldAcross(context);
    final onFold =
        fold != null &&
        fold - start >= _minColumnOnFold &&
        fold - start <= width - _minColumnOnFold;
    if (onFold) _foldX = fold;
    _followFold(onFold);
    final detail = _column(
      context,
      duoControls: duoControls,
      isDetail: true,
      removeLeft: true,
      removeRight: bar == DuoBarSide.right,
      child: HeroControllerScope.none(
        child: Navigator(
          key: _detailKey,
          observers: [_observer],
          onGenerateInitialRoutes: _initialRoutes,
          onGenerateRoute: widget.onGenerateDetailRoute,
        ),
      ),
    );
    final list = _column(
      context,
      duoControls: duoControls,
      isDetail: false,
      removeLeft: bar == DuoBarSide.left,
      removeRight: true,
      child: master,
    );
    final line = ColoredBox(color: dividerColor);
    return ColoredBox(
      color: _backgroundOf(context),
      child: Padding(
        padding: EdgeInsets.only(left: left, right: right),
        child: AnimatedBuilder(
          animation: _toFold,
          builder: (context, _) {
            final flat = (width * 0.38).clamp(320.0, 420.0);
            final foldX = _foldX;
            // Centred on the fold.
            final masterWidth = foldX == null
                ? flat
                : flat + (foldX - start - divider / 2 - flat) * _toFold.value;
            return Stack(
              children: [
                Positioned(
                  left: masterWidth + divider,
                  top: 0,
                  right: 0,
                  bottom: 0,
                  child: detail,
                ),
                // Over the column beside it: a page there that moves aside as
                // another comes in goes under the list, not over it.
                Positioned(
                  left: 0,
                  top: 0,
                  bottom: 0,
                  width: masterWidth,
                  child: list,
                ),
                Positioned(
                  left: masterWidth,
                  top: 0,
                  bottom: 0,
                  width: divider,
                  child: line,
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _column(
    BuildContext context, {
    required bool duoControls,
    required bool isDetail,
    required bool removeLeft,
    required bool removeRight,
    required Widget child,
  }) {
    // The iPhone Duo's status cluster is only over the column at its side.
    final strip = DuoTopStripScope.of(
      context,
    )?.within(left: !isDetail, right: isDetail);
    // A column with nothing of the strip over it has the strip to itself:
    // its pages start level with the bar the system sets in the strip.
    final freeStrip =
        strip != null && strip.clusterLeft == 0 && strip.clusterRight == 0;
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (_) => _pressInMaster = !isDetail,
      child: _ColumnScope(
        state: this,
        isDetail: isDetail,
        duoControls: duoControls,
        child: DuoTopStripScope(
          strip: strip,
          // The pages draw their own bars, or only their titles while the
          // vertical bar holds their controls.
          child: ToolbarChromeScope(
            hostsToolbar: false,
            hostsDuoControls: duoControls,
            // A column is the window its pages have: they lay out for its
            // width, as a column of a split view controller has a compact
            // width of its own.
            child: LayoutBuilder(
              builder: (context, constraints) => MediaQuery.removePadding(
                context: context,
                removeLeft: removeLeft,
                removeRight: removeRight,
                child: Builder(
                  builder: (context) {
                    final mediaQuery = MediaQuery.of(context);
                    final top = freeStrip
                        ? math.min(mediaQuery.padding.top, DuoTopStrip.barTop)
                        : mediaQuery.padding.top;
                    return MediaQuery(
                      data: mediaQuery.copyWith(
                        size: constraints.biggest,
                        padding: mediaQuery.padding.copyWith(top: top),
                        viewPadding: mediaQuery.viewPadding.copyWith(
                          top: freeStrip
                              ? math.min(
                                  mediaQuery.viewPadding.top,
                                  DuoTopStrip.barTop,
                                )
                              : mediaQuery.viewPadding.top,
                        ),
                      ),
                      child: child,
                    );
                  },
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A page that is there at once, as if it had been open all along, and that
/// leaves as the page it stands for would.
class _ArrivedPageRoute<T> extends MaterialPageRoute<T> {
  _ArrivedPageRoute({required super.builder, super.settings});

  @override
  Duration get transitionDuration => Duration.zero;

  @override
  Duration get reverseTransitionDuration => super.transitionDuration;
}

/// Follows the pages of the column.
class _DetailObserver extends NavigatorObserver {
  _DetailObserver(this._state);

  final _AdaptiveSplitViewState _state;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _state._details.add(route);
    _state._onDetailsChanged();
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _state._details.remove(route);
    _state._onDetailsChanged();
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _state._details.remove(route);
    _state._onDetailsChanged();
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    final index = oldRoute == null ? -1 : _state._details.indexOf(oldRoute);
    if (index >= 0 && newRoute != null) {
      _state._details[index] = newRoute;
    } else if (newRoute != null) {
      _state._details.add(newRoute);
    }
    _state._onDetailsChanged();
  }
}

class _SplitScope extends InheritedWidget {
  const _SplitScope({required this.selected, required super.child});

  final RouteSettings? selected;

  @override
  bool updateShouldNotify(_SplitScope oldWidget) =>
      selected != oldWidget.selected;
}

class _ColumnScope extends InheritedWidget {
  const _ColumnScope({
    required this.state,
    required this.isDetail,
    required this.duoControls,
    required super.child,
  });

  final _AdaptiveSplitViewState state;

  /// The column beside the list, rather than the list's.
  final bool isDetail;

  /// Whether the iPhone Duo vertical bar holds the controls of its pages.
  final bool duoControls;

  @override
  bool updateShouldNotify(_ColumnScope oldWidget) =>
      isDetail != oldWidget.isDetail ||
      duoControls != oldWidget.duoControls ||
      state != oldWidget.state;
}
