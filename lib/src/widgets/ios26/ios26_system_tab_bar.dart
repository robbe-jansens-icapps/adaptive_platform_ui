import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import '../../platform/platform_info.dart';
import '../adaptive_scaffold.dart';
import 'ios26_glass_capsule.dart';
import 'native_chrome/adaptive_native_chrome.dart';
import 'native_chrome/native_chrome_view.dart';

/// The iPhone Duo's tabs as iOS draws them in the vertical bar, with the
/// labels it reveals on a held tab and the lens, in the place the bar keeps
/// for its tab capsule.
///
/// iOS lays out only a tab bar controller's bar vertically, so the native view
/// is a tab bar controller with empty tabs over the Flutter view: a tap only
/// tells [onTap], and the app's tab layout keeps showing the pages. This
/// widget takes no touches itself and lays the tabs' semantics over the bar,
/// which VoiceOver does not reach over the Flutter view.
///
/// iOS's bar shows only once iOS has laid the tabs out in this place. Should
/// it lay them out anywhere else for good, as a later iOS might, [fallback]
/// takes their place, here and in every bar after it until the app restarts.
class IOS26SystemTabBar extends StatefulWidget {
  const IOS26SystemTabBar({
    super.key,
    required this.destinations,
    required this.selectedIndex,
    required this.onTap,
    required this.fallback,
    this.tint,
  });

  final List<AdaptiveNavigationDestination> destinations;
  final int selectedIndex;
  final ValueChanged<int> onTap;

  /// The tabs to show where iOS's own cannot be: the bar's glass capsule.
  final Widget fallback;

  /// Tint of the selected tab.
  final Color? tint;

  /// Whether the vertical bar may show iOS's tabs rather than its glass
  /// capsule: [AdaptiveNativeChrome.systemDuoTabBar] over the Flutter view
  /// ([AdaptiveNativeChrome.enabled]) on iOS 27 and later, unless iOS laid
  /// them out elsewhere before in this run of the app.
  static bool get isAvailable =>
      AdaptiveNativeChrome.systemDuoTabBar &&
      AdaptiveNativeChrome.enabled &&
      PlatformInfo.isIOS &&
      PlatformInfo.iOSVersion >= 27 &&
      !_unavailable.value;

  /// Whether iOS can draw every one of [destinations]' icons itself: an SF
  /// Symbol or asset catalog name, or an asset. Icons Flutter draws (an
  /// [IconData], a widget, a file or network image) keep the glass capsule.
  static bool canShow(List<AdaptiveNavigationDestination> destinations) =>
      destinations.every((destination) {
        final item = GlassCapsuleItem.fromDestination(destination);
        return item.symbol != null || item.asset != null;
      });

  /// Told why, the first time iOS's tabs give way to [fallback] in a run of
  /// the app, such as for an error report: `layout` where iOS laid them out
  /// anywhere else, `unsupported` where iOS cannot tell, `noViewController`
  /// where there is no Flutter view controller to add them under.
  static void Function(String reason)? onFallback;

  static final ValueNotifier<bool> _unavailable = ValueNotifier<bool>(false);

  /// Lets iOS's tabs show again after a [fallback], for tests.
  @visibleForTesting
  static void debugReset() => _unavailable.value = false;

  @override
  State<IOS26SystemTabBar> createState() => _IOS26SystemTabBarState();
}

class _IOS26SystemTabBarState extends State<IOS26SystemTabBar> {
  /// How long the app has to answer a tap before the bar shows its selection
  /// again, when it keeps another tab.
  static const Duration _tapAnswer = Duration(milliseconds: 300);

  MethodChannel? _channel;
  Map<String, Object?>? _sent;
  int? _sentIndex;

  /// The tab iOS shows selected after a tap, until the app's selection has
  /// caught up with it.
  int? _tapped;
  Timer? _tapAnswered;

  bool get _isDark =>
      MediaQuery.platformBrightnessOf(context) == Brightness.dark;

  Map<String, Object?> get _params {
    final tint = widget.tint == null
        ? null
        : CupertinoDynamicColor.resolve(widget.tint!, context);
    return <String, Object?>{
      'items': [
        for (final destination in widget.destinations)
          GlassCapsuleItem.fromDestination(destination).toNativeMap(),
      ],
      'isDark': _isDark,
      if (tint != null) 'tint': tint.toARGB32(),
    };
  }

  @override
  void didUpdateWidget(IOS26SystemTabBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    _sync();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  @override
  void dispose() {
    _tapAnswered?.cancel();
    _channel?.setMethodCallHandler(null);
    super.dispose();
  }

  Future<void> _sync() async {
    final channel = _channel;
    if (channel == null) return;
    final params = _params;
    if (_sent.toString() != params.toString()) {
      _sent = params;
      await _invoke(channel, 'update', params);
    }
    final index = widget.selectedIndex;
    if (_tapped != null) {
      if (index != _tapped) return;
      _tapped = null;
      _tapAnswered?.cancel();
    }
    if (_sentIndex != index) {
      _sentIndex = index;
      await _invoke(channel, 'setSelectedIndex', {'index': index});
    }
  }

  Future<void> _invoke(
    MethodChannel channel,
    String method, [
    Object? arguments,
  ]) async {
    try {
      await channel.invokeMethod<void>(method, arguments);
    } on PlatformException {
      // The view went away mid-call.
    } on MissingPluginException {
      // Same.
    }
  }

  void _onCreated(int id) {
    _channel?.setMethodCallHandler(null);
    _channel = MethodChannel('adaptive_platform_ui/ios26_system_tab_bar_$id')
      ..setMethodCallHandler(_onCall);
    _sync();
  }

  Future<Object?> _onCall(MethodCall call) async {
    final args = call.arguments as Map?;
    switch (call.method) {
      case 'valueChanged':
        final index = (args?['index'] as num?)?.toInt();
        if (index == null || index < 0 || index >= widget.destinations.length) {
          return null;
        }
        // iOS shows the tab selected at once, before the app answers. The
        // bar may still be built with the tab before it for a frame or two
        // meanwhile, which must not take iOS's selection back: the lens went
        // back and forth. Should the app keep another tab, the bar shows it
        // again once the app has had the time to answer.
        _sentIndex = index;
        _tapped = index;
        _tapAnswered?.cancel();
        _tapAnswered = Timer(_tapAnswer, () async {
          // A slow frame after the tap, such as one that builds a page for
          // the first time, outlasts that time. The app's answer reaches the
          // bar a frame after the app's own, as the page's bar is handed to
          // the host after a frame: the two frames that follow are waited
          // for too.
          final scheduler = SchedulerBinding.instance;
          await scheduler.endOfFrame;
          await scheduler.endOfFrame;
          if (_tapped != index) return;
          _tapped = null;
          if (mounted) _sync();
        });
        widget.onTap(index);
      case 'availability':
        if (args?['available'] != false ||
            IOS26SystemTabBar._unavailable.value) {
          return null;
        }
        IOS26SystemTabBar._unavailable.value = true;
        IOS26SystemTabBar.onFallback?.call(
          args?['reason'] as String? ?? 'unknown',
        );
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: IOS26SystemTabBar._unavailable,
      builder: (context, unavailable, _) {
        if (unavailable) return widget.fallback;
        _sent ??= _params;
        _sentIndex ??= widget.selectedIndex;
        return Stack(
          fit: StackFit.expand,
          children: [
            ExcludeSemantics(
              child: NativeChromeView(
                viewType: 'adaptive_platform_ui/ios26_system_tab_bar',
                creationParams: {..._sent!, 'selectedIndex': _sentIndex},
                onPlatformViewCreated: _onCreated,
              ),
            ),
            _SystemTabSemantics(
              destinations: widget.destinations,
              selectedIndex: widget.selectedIndex,
              onTap: widget.onTap,
            ),
          ],
        );
      },
    );
  }
}

/// A node for each tab where iOS shows it in the capsule, top to bottom:
/// label, place among the tabs, whether it is selected, and a tap that
/// selects it. It takes no touches: they go on to the native bar.
class _SystemTabSemantics extends StatelessWidget {
  const _SystemTabSemantics({
    required this.destinations,
    required this.selectedIndex,
    required this.onTap,
  });

  final List<AdaptiveNavigationDestination> destinations;
  final int selectedIndex;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) {
    final count = destinations.length;
    final localizations =
        Localizations.of<CupertinoLocalizations>(
          context,
          CupertinoLocalizations,
        ) ??
        const DefaultCupertinoLocalizations();
    return Padding(
      padding: const EdgeInsets.symmetric(
        vertical: IOS26GlassCapsule.tabsInset,
      ),
      child: Column(
        children: [
          for (var i = 0; i < count; i++)
            Expanded(
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
      ),
    );
  }
}
