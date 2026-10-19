import 'package:flutter/material.dart';

import '../chrome/adaptive_chrome.dart';
import '../toolbar/toolbar_registry.dart';
import '../utils/size_reporter.dart';
import 'accessory_makes_way.dart';
import 'adaptive_accessory_scope.dart';
import 'adaptive_keyboard_fade.dart';
import 'adaptive_scaffold.dart' show AdaptiveBottomBarInset;

/// A tab layout's accessory with the Material navigation bar (Android): on
/// the bar's own surface, in its colour, in a band just above its
/// destinations, so the two are one bar that rises over the pages with
/// rounded top corners, as a sheet at its smallest holds them.
///
/// The pages run on under the band and keep clear of it: their bottom
/// padding grows by its height, which [AdaptiveBottomBarInset.accessoryOf]
/// tells too. A page's sheet so comes up from behind the bar, the accessory
/// staying in sight above it, as with the native tab bar. A sheet that opens
/// from the accessory (`AdaptiveSheet.opensFromAccessory`, on the tab whose
/// layout is [AdaptiveTabAccessoryLayout.onSheet]) comes up into its place:
/// the accessory and the band's surface make way as its content comes up,
/// and a drag on the accessory moves the sheet.
///
/// The band takes no room while the accessory builds to nothing, and makes
/// way for the keyboard.
class MaterialTabAccessory extends StatefulWidget {
  const MaterialTabAccessory({
    super.key,
    required this.accessory,
    required this.layout,
    required this.body,
  });

  final Widget accessory;
  final AdaptiveTabAccessoryLayout layout;

  /// The pages, which run on under the band.
  final Widget body;

  /// Room the band keeps above the accessory, and at its sides.
  static const double topPadding = 12;
  static const double sidePadding = 16;

  /// The radius of the band's top corners, a Material sheet's.
  static const double cornerRadius = 28;

  @override
  State<MaterialTabAccessory> createState() => _MaterialTabAccessoryState();
}

class _MaterialTabAccessoryState extends State<MaterialTabAccessory> {
  /// How tall the band is, as last laid out: the room the pages keep.
  final ValueNotifier<double> _band = ValueNotifier<double>(0);

  /// Whether the accessory had nothing to show when last laid out.
  bool _empty = true;

  ToolbarRegistry? _registry;
  AccessorySheet? _sheet;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final registry = ToolbarRegistry.maybeOf(context);
    if (registry == _registry) return;
    _registry?.removeListener(_onRegistryChanged);
    _registry = registry?..addListener(_onRegistryChanged);
    _sheet = registry?.accessorySheet;
  }

  @override
  void dispose() {
    _registry?.removeListener(_onRegistryChanged);
    _band.dispose();
    super.dispose();
  }

  void _onRegistryChanged() {
    final sheet = _registry?.accessorySheet;
    if (sheet != _sheet && mounted) setState(() => _sheet = sheet);
  }

  /// After the frame that laid the accessory out, as the pages are built
  /// before it.
  void _onAccessorySize(Size size) {
    if (!mounted) return;
    final empty = size.isEmpty;
    if (empty != _empty) setState(() => _empty = empty);
    _band.value = empty ? 0 : size.height + MaterialTabAccessory.topPadding;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color =
        NavigationBarTheme.of(context).backgroundColor ??
        theme.colorScheme.surfaceContainer;
    // Only the sheet of the tab that holds the accessory on it.
    final sheet = widget.layout == AdaptiveTabAccessoryLayout.onSheet
        ? _sheet
        : null;
    final covered = sheet?.value ?? kAlwaysDismissedAnimation;
    final width = MediaQuery.sizeOf(context).width;
    final accessory = AdaptiveAccessoryScope(
      spec: AdaptiveAccessorySpec(
        placement: AdaptiveChromePlacement.bottom,
        compact: false,
        room: width - 2 * MaterialTabAccessory.sidePadding,
        layout: widget.layout,
      ),
      expansion: sheet,
      child: AccessoryMakesWay(
        covered: covered,
        child: AccessorySheetDrag(
          sheet: sheet,
          child: SizeReporter(
            onSizeChanged: _onAccessorySize,
            child: widget.accessory,
          ),
        ),
      ),
    );
    return Stack(
      children: [
        Positioned.fill(
          child: ValueListenableBuilder<double>(
            valueListenable: _band,
            child: widget.body,
            builder: (context, band, body) => AdaptiveBottomBarInset(
              height: band,
              accessory: band,
              child: _RaisedBottom(height: band, child: body!),
            ),
          ),
        ),
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          // The Scaffold leaves the keyboard out of its body's media query, as
          // it shrinks the body above it: the band would ride up on the
          // keyboard, the destinations under it.
          child: _WithKeyboard(
            child: AdaptiveKeyboardFade(
              child: AnimatedBuilder(
                animation: covered,
                child: Padding(
                  padding: _empty
                      ? EdgeInsets.zero
                      : const EdgeInsets.fromLTRB(
                          MaterialTabAccessory.sidePadding,
                          MaterialTabAccessory.topPadding,
                          MaterialTabAccessory.sidePadding,
                          0,
                        ),
                  child: accessory,
                ),
                builder: (context, child) {
                  // The band's surface makes way with the accessory, for the
                  // sheet's content coming up into its place; until then it
                  // keeps the touches that miss the accessory, as a sheet
                  // would.
                  final shown = _empty ? 0.0 : 1 - covered.value;
                  return IgnorePointer(
                    ignoring: covered.value > 0.05,
                    child: DecoratedBox(
                      decoration: ShapeDecoration(
                        color: color.withValues(alpha: color.a * shown),
                        shape: const RoundedRectangleBorder(
                          borderRadius: BorderRadius.vertical(
                            top: Radius.circular(
                              MaterialTabAccessory.cornerRadius,
                            ),
                          ),
                        ),
                        shadows: [
                          BoxShadow(
                            color: theme.colorScheme.shadow.withValues(
                              alpha: 0.12 * shown,
                            ),
                            blurRadius: 12,
                            offset: const Offset(0, -2),
                          ),
                        ],
                      ),
                      child: child,
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Hands [child] the keyboard's inset of the window, which the Scaffold
/// leaves out of its body's media query. Only this follows it.
class _WithKeyboard extends StatefulWidget {
  const _WithKeyboard({required this.child});

  final Widget child;

  @override
  State<_WithKeyboard> createState() => _WithKeyboardState();
}

class _WithKeyboardState extends State<_WithKeyboard>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeMetrics() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final view = View.of(context);
    final insets = EdgeInsets.fromViewPadding(
      view.viewInsets,
      view.devicePixelRatio,
    );
    final data = MediaQuery.of(context);
    return MediaQuery(
      data: data.copyWith(
        viewInsets: data.viewInsets.copyWith(
          bottom: data.viewInsets.bottom > 0
              ? data.viewInsets.bottom
              : insets.bottom,
        ),
      ),
      child: widget.child,
    );
  }
}

/// Raises the bottom padding of the media query by [height]. Only this
/// follows every change of the media query, so the pages are not built again
/// for them.
class _RaisedBottom extends StatelessWidget {
  const _RaisedBottom({required this.height, required this.child});

  final double height;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final data = MediaQuery.of(context);
    return MediaQuery(
      data: data.copyWith(
        padding: data.padding.copyWith(bottom: data.padding.bottom + height),
      ),
      child: child,
    );
  }
}
