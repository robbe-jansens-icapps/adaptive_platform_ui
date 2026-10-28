import 'dart:io';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import '../adaptive_scaffold.dart';
import 'native_chrome/adaptive_native_chrome.dart';
import 'native_chrome/adaptive_native_view.dart';

/// Native iOS 26 tab bar using UITabBar platform view
class IOS26NativeTabBar extends StatefulWidget {
  const IOS26NativeTabBar({
    super.key,
    required this.destinations,
    required this.selectedIndex,
    required this.onTap,
    this.tint,
    this.unselectedItemTint,
    this.backgroundColor,
    this.height,
    this.minimizeBehavior = TabBarMinimizeBehavior.automatic,
    this.showNativeView = true,
    this.hidden = false,
    this.onCapsuleChanged,
    this.chrome = false,
    this.dim,
  });

  final List<AdaptiveNavigationDestination> destinations;
  final int selectedIndex;
  final ValueChanged<int> onTap;
  final Color? tint;
  final Color? unselectedItemTint;
  final Color? backgroundColor;
  final double? height;

  /// Whether the native bar is on screen. While it is not, the native view is
  /// kept off stage rather than thrown away: made again, it would cost frames
  /// right as it comes back, such as at the start of a pop.
  final bool showNativeView;

  /// Whether the native tab bar is hidden.
  /// Use this to hide the tab bar when showing modal bottom sheets
  /// to prevent native platform views from bleeding through.
  final bool hidden;

  /// Tab bar minimize behavior (iOS 26+)
  /// Controls how the tab bar minimizes when scrolling
  final TabBarMinimizeBehavior minimizeBehavior;

  /// Told where in the bar the capsule is that iOS 26 floats the tabs on,
  /// whenever that changes; null where it has none. It is what the bar
  /// shows of itself: the rest of it lets the page show through.
  final ValueChanged<Rect?>? onCapsuleChanged;

  /// Whether the native bar is shown over the Flutter view rather than as a
  /// platform view, with [AdaptiveNativeChrome.enabled]: only for a bar that
  /// stays in place while pages slide under it, as the hosted one does.
  final bool chrome;

  /// A dialog's barrier over the bar shown over the Flutter view ([chrome]),
  /// which Flutter cannot draw over it: iOS dims the capsule in this colour.
  final ValueListenable<Color?>? dim;

  /// Takes the native path (or not) whatever the platform, for tests.
  @visibleForTesting
  static bool? debugHasUIKitOverride;

  @override
  State<IOS26NativeTabBar> createState() => _IOS26NativeTabBarState();
}

class _IOS26NativeTabBarState extends State<IOS26NativeTabBar> {
  /// UIKit has no behavior that waits for the top: it minimizes on
  /// scrolling down.
  int get _nativeMinimizeBehavior =>
      widget.minimizeBehavior == TabBarMinimizeBehavior.onScrollDownUntilTop
      ? TabBarMinimizeBehavior.onScrollDown.index
      : widget.minimizeBehavior.index;

  static bool get _hasUIKit =>
      IOS26NativeTabBar.debugHasUIKitOverride ?? (!kIsWeb && Platform.isIOS);

  MethodChannel? _channel;

  /// What the native view was made with. It reads its creation params once,
  /// when it is made; every change after that goes through the channel.
  Map<String, Object?>? _createdWith;
  int? _lastIndex;
  int? _lastTint;
  int? _lastUnselectedTint;
  int? _lastBg;
  bool? _lastIsDark;
  bool? _lastIsRtl;
  double? _intrinsicHeight;
  List<String>? _lastLabels;
  List<String>? _lastSymbols;
  List<String>? _lastSelectedSymbols;
  List<String>? _lastAssetIcons;
  List<String>? _lastSelectedAssetIcons;
  List<String>? _lastFileIcons;
  List<String>? _lastSelectedFileIcons;
  List<String>? _lastNetworkIcons;
  List<String>? _lastSelectedNetworkIcons;
  List<int?>? _lastBadgeCounts;
  List<String?>? _lastBadgeTexts;
  List<int?>? _lastBadgeColors;
  List<int?>? _lastBadgeTextColors;
  TabBarMinimizeBehavior? _lastMinimizeBehavior;
  bool? _lastHidden;

  /// Where the capsule and each tab's button are in the bar, as the native
  /// view last told, for the tabs' semantics over it.
  final _layout = ValueNotifier<({Rect? capsule, List<Rect?>? tabs})>((
    capsule: null,
    tabs: null,
  ));

  bool get _isDark =>
      MediaQuery.platformBrightnessOf(context) == Brightness.dark;
  bool get _isRtl => Directionality.of(context) == TextDirection.rtl;
  Color? get _effectiveTint =>
      widget.tint ?? CupertinoTheme.of(context).primaryColor;

  @override
  void didUpdateWidget(covariant IOS26NativeTabBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncPropsToNativeIfNeeded();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncBrightnessIfNeeded();
    _syncDirectionalityIfNeeded();
    _syncPropsToNativeIfNeeded();
  }

  @override
  void dispose() {
    _channel?.setMethodCallHandler(null);
    _layout.dispose();
    super.dispose();
  }

  int _colorToARGB(Color color) {
    // Resolve CupertinoDynamicColor if needed
    Color resolvedColor = color;
    if (color is CupertinoDynamicColor) {
      // Resolve based on current brightness
      final brightness = MediaQuery.platformBrightnessOf(context);
      resolvedColor = brightness == Brightness.dark
          ? color.darkColor
          : color.color;
    }

    return ((resolvedColor.a * 255.0).round() & 0xff) << 24 |
        ((resolvedColor.r * 255.0).round() & 0xff) << 16 |
        ((resolvedColor.g * 255.0).round() & 0xff) << 8 |
        ((resolvedColor.b * 255.0).round() & 0xff);
  }

  /// Extract SF Symbol name from an icon value.
  /// Returns empty string for non-SF-Symbol icons (asset paths, IconData, widgets).
  String _extractSymbol(Object? icon) {
    if (icon is String && !icon.contains('/')) return icon;
    return '';
  }

  /// Extract asset path from an icon value.
  /// Supports AssetImage, ImageIcon(AssetImage), and string paths containing '/'.
  /// Returns empty string for SF Symbols or other icon types.
  String _extractAssetPath(Object? icon) {
    if (icon is AssetImage) return icon.assetName;
    if (icon is ImageIcon && icon.image is AssetImage) {
      return (icon.image as AssetImage).assetName;
    }
    if (icon is String && icon.contains('/')) return icon;
    return '';
  }

  String _extractFilePath(Object? icon) {
    if (icon is FileImage) return icon.file.path;
    if (icon is ImageIcon && icon.image is FileImage) {
      return (icon.image as FileImage).file.path;
    }
    return '';
  }

  String _extractNetworkUrl(Object? icon) {
    if (icon is NetworkImage) return icon.url;
    if (icon is ImageIcon && icon.image is NetworkImage) {
      return (icon.image as NetworkImage).url;
    }
    return '';
  }

  List<String> _mapSymbols() =>
      widget.destinations.map((e) => _extractSymbol(e.icon)).toList();

  List<String> _mapSelectedSymbols() => widget.destinations
      .map((e) => _extractSymbol(e.selectedIcon ?? e.icon))
      .toList();

  List<String> _mapAssetIcons() =>
      widget.destinations.map((e) => _extractAssetPath(e.icon)).toList();

  List<String> _mapSelectedAssetIcons() => widget.destinations
      .map((e) => _extractAssetPath(e.selectedIcon ?? e.icon))
      .toList();

  List<String> _mapFileIcons() =>
      widget.destinations.map((e) => _extractFilePath(e.icon)).toList();

  List<String> _mapSelectedFileIcons() => widget.destinations
      .map((e) => _extractFilePath(e.selectedIcon ?? e.icon))
      .toList();

  List<String> _mapNetworkIcons() =>
      widget.destinations.map((e) => _extractNetworkUrl(e.icon)).toList();

  List<String> _mapSelectedNetworkIcons() => widget.destinations
      .map((e) => _extractNetworkUrl(e.selectedIcon ?? e.icon))
      .toList();

  // Native badge styling: badge content + colors mapped to the
  // native side (UITabBarItem.badgeValue / .badgeColor / badge text attrs).
  List<String?> _mapBadgeTexts() =>
      widget.destinations.map((e) => e.badgeText).toList();

  List<int?> _mapBadgeColors() => widget.destinations
      .map((e) => e.badgeColor != null ? _colorToARGB(e.badgeColor!) : null)
      .toList();

  List<int?> _mapBadgeTextColors() => widget.destinations
      .map(
        (e) =>
            e.badgeTextColor != null ? _colorToARGB(e.badgeTextColor!) : null,
      )
      .toList();

  @override
  Widget build(BuildContext context) {
    if (_hasUIKit) {
      final labels = widget.destinations.map((e) => e.label).toList();
      final symbols = _mapSymbols();
      final selectedSymbols = _mapSelectedSymbols();
      final assetIcons = _mapAssetIcons();
      final selectedAssetIcons = _mapSelectedAssetIcons();
      final fileIcons = _mapFileIcons();
      final selectedFileIcons = _mapSelectedFileIcons();
      final networkIcons = _mapNetworkIcons();
      final selectedNetworkIcons = _mapSelectedNetworkIcons();

      final searchFlags = widget.destinations.map((e) => e.isSearch).toList();
      final badgeCounts = widget.destinations
          .map((e) => e.nativeBadge)
          .toList();
      final badgeTexts = _mapBadgeTexts();
      final badgeColors = _mapBadgeColors();
      final badgeTextColors = _mapBadgeTextColors();
      final spacerFlags = widget.destinations
          .map((e) => e.addSpacerAfter)
          .toList();

      final creationParams = <String, Object?>{
        'labels': labels,
        'sfSymbols': symbols,
        'selectedSfSymbols': selectedSymbols,
        'assetIcons': assetIcons,
        'selectedAssetIcons': selectedAssetIcons,
        'fileIcons': fileIcons,
        'selectedFileIcons': selectedFileIcons,
        'networkIcons': networkIcons,
        'selectedNetworkIcons': selectedNetworkIcons,
        'searchFlags': searchFlags,
        'badgeCounts': badgeCounts,
        'badgeTexts': badgeTexts,
        'badgeColors': badgeColors,
        'badgeTextColors': badgeTextColors,
        'spacerFlags': spacerFlags,
        'selectedIndex': widget.selectedIndex,
        'isDark': _isDark,
        'isRtl': _isRtl,
        'minimizeBehavior': _nativeMinimizeBehavior,
        'hidden': widget.hidden,
        if (_effectiveTint != null) 'tint': _colorToARGB(_effectiveTint!),
        if (widget.unselectedItemTint != null)
          'unselectedItemTint': _colorToARGB(widget.unselectedItemTint!),
        if (widget.backgroundColor != null)
          'backgroundColor': _colorToARGB(widget.backgroundColor!),
      };
      // The view below is made from the params of its first build, and only
      // ever made once: it is always in the tree, off stage or not.
      _createdWith ??= creationParams;

      final h = widget.height ?? _intrinsicHeight ?? 50.0;
      return SizedBox(
        height: h,
        child: Offstage(
          offstage: !widget.showNativeView,
          child: Stack(
            fit: StackFit.expand,
            children: [
              // VoiceOver passes over a platform view, which has no label or
              // action of its own, to what lies under it: over a map it found
              // the map rather than the tabs. The tabs' own nodes take the
              // native bar's place.
              ExcludeSemantics(
                child: AdaptiveNativeView(
                  viewType: 'adaptive_platform_ui/ios26_tab_bar',
                  creationParams: creationParams,
                  onPlatformViewCreated: _onCreated,
                  chrome: widget.chrome,
                  dim: widget.dim,
                  // Every touch on the bar is the bar's, at once: with a tap
                  // recognizer it only got them when the finger lifted, so a
                  // finger held on a tab (the large content viewer of the
                  // accessibility text sizes) or sliding across the tabs did
                  // nothing.
                  gestureRecognizers: <Factory<OneSequenceGestureRecognizer>>{
                    Factory<OneSequenceGestureRecognizer>(
                      EagerGestureRecognizer.new,
                    ),
                  },
                ),
              ),
              ExcludeSemantics(
                excluding: widget.hidden,
                child: ValueListenableBuilder(
                  valueListenable: _layout,
                  builder: (context, layout, _) => _TabSemantics(
                    destinations: widget.destinations,
                    selectedIndex: widget.selectedIndex,
                    onTap: widget.onTap,
                    capsule: layout.capsule,
                    tabs: layout.tabs,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    // Fallback for non-iOS
    return SizedBox(
      height: widget.height ?? 50,
      child: Container(
        color:
            widget.backgroundColor ??
            CupertinoColors.systemBackground.resolveFrom(context),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: List.generate(
            widget.destinations.length,
            (index) => CupertinoButton(
              padding: EdgeInsets.zero,
              onPressed: () => widget.onTap(index),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    CupertinoIcons.circle,
                    color: index == widget.selectedIndex
                        ? CupertinoColors.activeBlue
                        : CupertinoColors.systemGrey,
                  ),
                  Text(
                    widget.destinations[index].label,
                    style: TextStyle(
                      fontSize: 10,
                      color: index == widget.selectedIndex
                          ? CupertinoColors.activeBlue
                          : CupertinoColors.systemGrey,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _onCreated(int id) {
    final ch = MethodChannel('adaptive_platform_ui/ios26_tab_bar_$id');
    _channel = ch;
    ch.setMethodCallHandler(_onMethodCall);
    // The view shows what it was made with: only what changed since is sent.
    // Sending it all again rebuilt every item, more than once, right after
    // the view was made.
    final made = _createdWith ?? const <String, Object?>{};
    List<T> list<T>(String key) => [...?made[key] as List<Object?>?].cast<T>();
    _lastIndex = made['selectedIndex'] as int?;
    _lastTint = made['tint'] as int?;
    _lastUnselectedTint = made['unselectedItemTint'] as int?;
    _lastBg = made['backgroundColor'] as int?;
    _lastIsDark = made['isDark'] as bool?;
    _lastIsRtl = made['isRtl'] as bool?;
    final minimize = made['minimizeBehavior'] as int?;
    _lastMinimizeBehavior = minimize == null
        ? null
        : TabBarMinimizeBehavior.values[minimize];
    _lastHidden = made['hidden'] as bool?;
    _lastLabels = list<String>('labels');
    _lastSymbols = list<String>('sfSymbols');
    _lastSelectedSymbols = list<String>('selectedSfSymbols');
    _lastAssetIcons = list<String>('assetIcons');
    _lastSelectedAssetIcons = list<String>('selectedAssetIcons');
    _lastFileIcons = list<String>('fileIcons');
    _lastSelectedFileIcons = list<String>('selectedFileIcons');
    _lastNetworkIcons = list<String>('networkIcons');
    _lastSelectedNetworkIcons = list<String>('selectedNetworkIcons');
    _lastBadgeCounts = list<int?>('badgeCounts');
    _lastBadgeTexts = list<String?>('badgeTexts');
    _lastBadgeColors = list<int?>('badgeColors');
    _lastBadgeTextColors = list<int?>('badgeTextColors');
    // Cheap, and makes sure the selected tab shows as such from the first
    // frame the bar is on screen.
    _invoke<void>(ch, 'setSelectedIndex', {'index': _lastIndex ?? 0});
    _requestIntrinsicSize();
    _syncBrightnessIfNeeded();
    _syncDirectionalityIfNeeded();
    _syncPropsToNativeIfNeeded();
    // Told of every change after this, but maybe laid out before it listened.
    _invoke<Map<Object?, Object?>>(ch, 'getCapsule').then((frame) {
      if (mounted && identical(ch, _channel)) _onCapsule(_rectOf(frame));
    });
    _invoke<List<Object?>>(ch, 'getTabFrames').then((frames) {
      if (mounted && identical(ch, _channel)) _onTabFrames(frames);
    });
  }

  void _onCapsule(Rect? capsule) {
    _layout.value = (capsule: capsule, tabs: _layout.value.tabs);
    widget.onCapsuleChanged?.call(capsule);
  }

  void _onTabFrames(Object? frames) {
    _layout.value = (
      capsule: _layout.value.capsule,
      tabs: frames is List
          ? [for (final frame in frames) _rectOf(frame)]
          : null,
    );
  }

  static Rect? _rectOf(Object? frame) {
    if (frame is! Map) return null;
    final x = frame['x'], y = frame['y'];
    final width = frame['width'], height = frame['height'];
    if (x is! num || y is! num || width is! num || height is! num) return null;
    return Rect.fromLTWH(
      x.toDouble(),
      y.toDouble(),
      width.toDouble(),
      height.toDouble(),
    );
  }

  /// Calls [method] on the native view, if it still listens: one that is gone
  /// (the app torn down, or a test without UIKit) answers nothing.
  Future<T?> _invoke<T>(
    MethodChannel ch,
    String method, [
    Object? arguments,
  ]) async {
    try {
      return await ch.invokeMethod<T>(method, arguments);
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    }
  }

  Future<dynamic> _onMethodCall(MethodCall call) async {
    if (call.method == 'capsuleChanged') {
      _onCapsule(_rectOf(call.arguments));
      return null;
    }
    if (call.method == 'tabFramesChanged') {
      _onTabFrames(call.arguments);
      return null;
    }
    if (call.method == 'valueChanged') {
      final args = call.arguments as Map?;
      final idx = (args?['index'] as num?)?.toInt();
      if (idx != null) {
        widget.onTap(idx);
        _lastIndex = idx;
      }
    }
    return null;
  }

  // Each value is noted as sent before the call goes out, so a rebuild while
  // a call is under way does not send it again.
  Future<void> _syncPropsToNativeIfNeeded() async {
    final ch = _channel;
    if (ch == null) return;

    final idx = widget.selectedIndex;
    final tint = _effectiveTint != null ? _colorToARGB(_effectiveTint!) : null;
    final unselectedTint = widget.unselectedItemTint != null
        ? _colorToARGB(widget.unselectedItemTint!)
        : null;
    final bg = widget.backgroundColor != null
        ? _colorToARGB(widget.backgroundColor!)
        : null;

    if (_lastIndex != idx) {
      _lastIndex = idx;
      await _invoke<void>(ch, 'setSelectedIndex', {'index': idx});
    }

    final style = <String, dynamic>{};
    if (_lastTint != tint && tint != null) {
      style['tint'] = tint;
      _lastTint = tint;
    }
    if (_lastUnselectedTint != unselectedTint && unselectedTint != null) {
      style['unselectedItemTint'] = unselectedTint;
      _lastUnselectedTint = unselectedTint;
    }
    if (_lastBg != bg && bg != null) {
      style['backgroundColor'] = bg;
      _lastBg = bg;
    }
    if (style.isNotEmpty) {
      await _invoke<void>(ch, 'setStyle', style);
    }

    // Items update (for hot reload or dynamic changes)
    final labels = widget.destinations.map((e) => e.label).toList();
    final symbols = _mapSymbols();
    final selectedSymbols = _mapSelectedSymbols();
    final assetIcons = _mapAssetIcons();
    final selectedAssetIcons = _mapSelectedAssetIcons();
    final fileIcons = _mapFileIcons();
    final selectedFileIcons = _mapSelectedFileIcons();
    final networkIcons = _mapNetworkIcons();
    final selectedNetworkIcons = _mapSelectedNetworkIcons();
    final searchFlags = widget.destinations.map((e) => e.isSearch).toList();
    final badgeCounts = widget.destinations.map((e) => e.nativeBadge).toList();

    if (_lastLabels?.join('|') != labels.join('|') ||
        _lastSymbols?.join('|') != symbols.join('|') ||
        _lastSelectedSymbols?.join('|') != selectedSymbols.join('|') ||
        _lastAssetIcons?.join('|') != assetIcons.join('|') ||
        _lastSelectedAssetIcons?.join('|') != selectedAssetIcons.join('|') ||
        _lastFileIcons?.join('|') != fileIcons.join('|') ||
        _lastSelectedFileIcons?.join('|') != selectedFileIcons.join('|') ||
        _lastNetworkIcons?.join('|') != networkIcons.join('|') ||
        _lastSelectedNetworkIcons?.join('|') !=
            selectedNetworkIcons.join('|')) {
      _lastLabels = labels;
      _lastSymbols = symbols;
      _lastSelectedSymbols = selectedSymbols;
      _lastAssetIcons = assetIcons;
      _lastSelectedAssetIcons = selectedAssetIcons;
      _lastFileIcons = fileIcons;
      _lastSelectedFileIcons = selectedFileIcons;
      _lastNetworkIcons = networkIcons;
      _lastSelectedNetworkIcons = selectedNetworkIcons;
      // The items carry their badges.
      _lastBadgeCounts = badgeCounts;
      _lastBadgeTexts = _mapBadgeTexts();
      _lastBadgeColors = _mapBadgeColors();
      _lastBadgeTextColors = _mapBadgeTextColors();
      await _invoke<void>(ch, 'setItems', {
        'labels': labels,
        'sfSymbols': symbols,
        'selectedSfSymbols': selectedSymbols,
        'assetIcons': assetIcons,
        'selectedAssetIcons': selectedAssetIcons,
        'fileIcons': fileIcons,
        'selectedFileIcons': selectedFileIcons,
        'networkIcons': networkIcons,
        'selectedNetworkIcons': selectedNetworkIcons,
        'searchFlags': searchFlags,
        'badgeCounts': badgeCounts,
        'badgeTexts': _lastBadgeTexts,
        'badgeColors': _lastBadgeColors,
        'badgeTextColors': _lastBadgeTextColors,
        'selectedIndex': widget.selectedIndex,
      });
      _requestIntrinsicSize();
    }

    // Badge update (count + text + colors). Re-push when any badge input changes.
    final currentBadgeCounts = widget.destinations
        .map((e) => e.nativeBadge)
        .toList();
    final currentBadgeTexts = _mapBadgeTexts();
    final currentBadgeColors = _mapBadgeColors();
    final currentBadgeTextColors = _mapBadgeTextColors();
    if (_lastBadgeCounts?.join('|') != currentBadgeCounts.join('|') ||
        _lastBadgeTexts?.join('|') != currentBadgeTexts.join('|') ||
        _lastBadgeColors?.join('|') != currentBadgeColors.join('|') ||
        _lastBadgeTextColors?.join('|') != currentBadgeTextColors.join('|')) {
      _lastBadgeCounts = currentBadgeCounts;
      _lastBadgeTexts = currentBadgeTexts;
      _lastBadgeColors = currentBadgeColors;
      _lastBadgeTextColors = currentBadgeTextColors;
      await _invoke<void>(ch, 'setBadgeCounts', {
        'badgeCounts': currentBadgeCounts,
        'badgeTexts': currentBadgeTexts,
        'badgeColors': currentBadgeColors,
        'badgeTextColors': currentBadgeTextColors,
      });
    }

    // Minimize behavior update
    if (_lastMinimizeBehavior != widget.minimizeBehavior) {
      _lastMinimizeBehavior = widget.minimizeBehavior;
      await _invoke<void>(ch, 'setMinimizeBehavior', {
        'behavior': _nativeMinimizeBehavior,
      });
    }

    // Hidden state update
    await _syncHiddenIfNeeded();
  }

  Future<void> _syncBrightnessIfNeeded() async {
    final ch = _channel;
    if (ch == null) return;
    final isDark = _isDark;
    if (_lastIsDark != isDark) {
      _lastIsDark = isDark;
      await _invoke<void>(ch, 'setBrightness', {'isDark': isDark});
    }
  }

  Future<void> _syncDirectionalityIfNeeded() async {
    final ch = _channel;
    if (ch == null) return;
    final isRtl = _isRtl;
    if (_lastIsRtl != isRtl) {
      _lastIsRtl = isRtl;
      await _invoke<void>(ch, 'setDirectionality', {'isRtl': isRtl});
    }
  }

  Future<void> _syncHiddenIfNeeded() async {
    final ch = _channel;
    if (ch == null) return;
    final hidden = widget.hidden;
    if (_lastHidden == hidden) return;
    _lastHidden = hidden;
    await _invoke<void>(ch, 'setHidden', {'hidden': hidden});
  }

  Future<void> _requestIntrinsicSize() async {
    if (widget.height != null) return;
    final ch = _channel;
    if (ch == null) return;
    final size = await _invoke<Map<Object?, Object?>>(ch, 'getIntrinsicSize');
    final h = (size?['height'] as num?)?.toDouble();
    if (!mounted || h == null || h <= 0 || h == _intrinsicHeight) return;
    setState(() => _intrinsicHeight = h);
  }
}

/// A node for each tab where the native bar shows it: label, place among the
/// tabs as [CupertinoTabBar] gives it, whether it is selected, and a tap that
/// selects it. It takes no touches: they go on to the native bar.
class _TabSemantics extends StatelessWidget {
  const _TabSemantics({
    required this.destinations,
    required this.selectedIndex,
    required this.onTap,
    required this.capsule,
    required this.tabs,
  });

  final List<AdaptiveNavigationDestination> destinations;
  final int selectedIndex;
  final ValueChanged<int> onTap;

  /// The capsule the tabs are on, if the native bar told it.
  final Rect? capsule;

  /// Where each tab's button is, if the native bar told it.
  final List<Rect?>? tabs;

  @override
  Widget build(BuildContext context) {
    final count = destinations.length;
    final localizations =
        Localizations.of<CupertinoLocalizations>(
          context,
          CupertinoLocalizations,
        ) ??
        const DefaultCupertinoLocalizations();
    return LayoutBuilder(
      builder: (context, constraints) {
        final rects = _rects(constraints.biggest, Directionality.of(context));
        return Stack(
          children: [
            for (var i = 0; i < count; i++)
              Positioned.fromRect(
                rect: rects[i],
                child: Semantics(
                  container: true,
                  button: true,
                  selected: i == selectedIndex,
                  identifier: destinations[i].identifier,
                  label: destinations[i].label,
                  hint: localizations.tabSemanticsLabel(
                    tabIndex: i + 1,
                    tabCount: count,
                  ),
                  onTap: () => onTap(i),
                  child: const SizedBox.expand(),
                ),
              ),
          ],
        );
      },
    );
  }

  /// The native bar's frames once it told one for every tab, which overlap:
  /// a touch where two do is the nearer one's. Until then the capsule, or the
  /// bar, shared out evenly: the whole bar with a search tab, which sits apart
  /// from the capsule.
  List<Rect> _rects(Size size, TextDirection direction) {
    final frames = tabs;
    if (frames != null &&
        frames.length == destinations.length &&
        !frames.contains(null)) {
      final rects = frames.cast<Rect>().toList();
      final order = [for (var i = 0; i < rects.length; i++) i]
        ..sort((a, b) => rects[a].left.compareTo(rects[b].left));
      for (var k = 1; k < order.length; k++) {
        final before = rects[order[k - 1]];
        final after = rects[order[k]];
        if (before.right <= after.left) continue;
        final middle = (before.right + after.left) / 2;
        rects[order[k - 1]] = Rect.fromLTRB(
          before.left,
          before.top,
          middle,
          before.bottom,
        );
        rects[order[k]] = Rect.fromLTRB(
          middle,
          after.top,
          after.right,
          after.bottom,
        );
      }
      return rects;
    }
    final searches = destinations.any((destination) => destination.isSearch);
    final area = searches ? Offset.zero & size : capsule ?? Offset.zero & size;
    final width = area.width / destinations.length;
    return [
      for (var i = 0; i < destinations.length; i++)
        Rect.fromLTWH(
          direction == TextDirection.rtl
              ? area.right - width * (i + 1)
              : area.left + width * i,
          area.top,
          width,
          area.height,
        ),
    ];
  }
}
