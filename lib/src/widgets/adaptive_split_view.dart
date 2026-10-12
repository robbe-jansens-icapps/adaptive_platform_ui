import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../platform/platform_info.dart';
import '../toolbar/duo_vertical_bar.dart';

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
/// On a narrower window only [master] shows, and pages open over it as they
/// always do. When the window narrows, such as when an iPhone Duo or an
/// Android foldable is folded, the pages picked in the list stay on screen:
/// they move onto the navigator the split view is on.
///
/// Pages reach the column through [showDetail]: navigation code calls it
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

  /// Opens the page [settings] names in the column beside the list of the
  /// split view in front, when it shows one: a split view that is wide, on
  /// the page in front, and on screen (on the selected tab). A page picked in
  /// the list replaces what the column shows; one opened from a page in the
  /// column goes on top of it.
  ///
  /// Returns false when no split view in front shows a column beside its
  /// list: the caller then opens the page itself, as it always did.
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

  /// Whether [context] is in a column of a split view that shows its columns
  /// side by side. A page there keeps its own bar instead of handing it to a
  /// fixed toolbar that spans the window.
  static bool isInColumn(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_ColumnScope>() != null;

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

class _AdaptiveSplitViewState extends State<AdaptiveSplitView> {
  static final _mounted = <_AdaptiveSplitViewState>[];

  final _masterKey = GlobalKey(debugLabel: 'AdaptiveSplitView master');
  final _detailKey = GlobalKey<NavigatorState>(
    debugLabel: 'AdaptiveSplitView detail',
  );
  late final _observer = _DetailObserver(this);

  /// Whether the columns show side by side.
  bool _wide = false;

  /// The pages of the column, from its first one up.
  final _details = <Route<dynamic>>[];

  /// The page picked in the list, or the [AdaptiveSplitView.initialDetail]
  /// shown before anything was.
  RouteSettings? _selected;

  /// Whether the page beside the list was picked, rather than shown first.
  bool _picked = false;

  /// Whether the last press went down in the list rather than in the column.
  bool _pressInMaster = false;

  /// Whether the column shows [AdaptiveSplitView.placeholder], for want of a
  /// page to show.
  bool _showsPlaceholder = false;

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
    super.dispose();
  }

  /// Whether this split view shows a column beside its list right now, on the
  /// page in front, on screen.
  bool get _isInFront {
    if (!mounted || !_wide || _detailKey.currentState == null) return false;
    if (!(_route?.isCurrent ?? true)) return false;
    // A tab that is not selected keeps its page, out of sight.
    return TickerMode.getValuesNotifier(context).value.enabled &&
        Visibility.of(context);
  }

  bool _show(RouteSettings settings) {
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

  Route<dynamic> _placeholderRoute() => PageRouteBuilder<void>(
    pageBuilder: (context, _, _) =>
        widget.placeholder ?? ColoredBox(color: _backgroundOf(context)),
    transitionDuration: Duration.zero,
    reverseTransitionDuration: Duration.zero,
  );

  List<Route<dynamic>> _initialRoutes(NavigatorState _, String _) {
    final selected = _selected;
    _showsPlaceholder = selected == null;
    return [selected == null ? _placeholderRoute() : _shownAtOnce(selected)];
  }

  /// Shows [AdaptiveSplitView.initialDetail] in the column, which arrives
  /// with the list once that has loaded.
  void _showInitialDetail() {
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

  void _onDetailsChanged() => scheduleMicrotask(_syncHistory);

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
  /// move onto the navigator the split view is on, so they stay on screen.
  /// Called as the column goes, during layout: the rest waits for the frame.
  void _collapse() {
    final pages = _picked
        ? [for (final page in _details) page.settings]
        : const <RouteSettings>[];
    _details.clear();
    _selected = null;
    _picked = false;
    _showsPlaceholder = false;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _forgetHistory();
      final navigator = _route?.navigator;
      if (_wide || navigator == null) return;
      for (final settings in pages) {
        final route = widget.onGenerateDetailRoute(settings);
        if (route != null) navigator.push(route);
      }
    });
  }

  // Layout -------------------------------------------------------------------

  Color _backgroundOf(BuildContext context) =>
      widget.backgroundColor ??
      (PlatformInfo.isAndroid
          ? Theme.of(context).colorScheme.surface
          : CupertinoColors.systemGroupedBackground.resolveFrom(context));

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= widget.minWidth;
        if (wide != _wide) {
          _wide = wide;
          if (!wide) _collapse();
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
    final masterWidth = (width * 0.38).clamp(320.0, 420.0);
    final android = PlatformInfo.isAndroid;
    final divider = android ? 1.0 : 1 / MediaQuery.devicePixelRatioOf(context);
    final dividerColor = android
        ? Theme.of(context).colorScheme.outlineVariant
        : CupertinoColors.separator.resolveFrom(context);
    return ColoredBox(
      color: _backgroundOf(context),
      child: Padding(
        padding: EdgeInsets.only(left: left, right: right),
        child: Stack(
          children: [
            Positioned(
              left: masterWidth + divider,
              top: 0,
              right: 0,
              bottom: 0,
              child: _column(
                context,
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
              ),
            ),
            // Over the column beside it: a page there that moves aside as
            // another comes in goes under the list, not over it.
            Positioned(
              left: 0,
              top: 0,
              bottom: 0,
              width: masterWidth,
              child: _column(
                context,
                isDetail: false,
                removeLeft: bar == DuoBarSide.left,
                removeRight: true,
                child: master,
              ),
            ),
            Positioned(
              left: masterWidth,
              top: 0,
              bottom: 0,
              width: divider,
              child: ColoredBox(color: dividerColor),
            ),
          ],
        ),
      ),
    );
  }

  Widget _column(
    BuildContext context, {
    required bool isDetail,
    required bool removeLeft,
    required bool removeRight,
    required Widget child,
  }) {
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (_) => _pressInMaster = !isDetail,
      child: _ColumnScope(
        state: this,
        isDetail: isDetail,
        child: MediaQuery.removePadding(
          context: context,
          removeLeft: removeLeft,
          removeRight: removeRight,
          child: child,
        ),
      ),
    );
  }
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
    required super.child,
  });

  final _AdaptiveSplitViewState state;

  /// The column beside the list, rather than the list's.
  final bool isDetail;

  @override
  bool updateShouldNotify(_ColumnScope oldWidget) =>
      isDetail != oldWidget.isDetail || state != oldWidget.state;
}
