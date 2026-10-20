import 'package:flutter/material.dart';

import '../chrome/adaptive_chrome.dart';
import '../toolbar/toolbar_registry.dart';
import '../utils/outside_layout.dart';
import '../utils/size_reporter.dart';
import 'accessory_makes_way.dart';
import 'adaptive_accessory_scope.dart';
import 'adaptive_keyboard_fade.dart';
import 'adaptive_scaffold.dart' show AdaptiveBottomBarInset;

/// A tab layout's accessory with the Material navigation bar (Android): on a
/// card of the lowest surface container colour, in a band just above the
/// bar's destinations, rising over the pages with rounded top corners as a
/// sheet at its smallest. The bar's top corners round in while the card
/// shows, or a page's sheet is up ([MaterialTabAccessoryBar]), what meets
/// the bar showing around them, so the two stay together and still stand
/// apart.
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
    this.link,
  });

  final Widget accessory;
  final AdaptiveTabAccessoryLayout layout;

  /// The pages, which run on under the band.
  final Widget body;

  /// Tells the navigation bar below whether the band shows and how far a
  /// page's sheet covers it.
  final MaterialTabAccessoryLink? link;

  /// Room the band keeps above the accessory, below it, and at its sides.
  static const double topPadding = 12;
  static const double bottomPadding = 12;
  static const double sidePadding = 16;

  /// The radius of the band's top corners, a Material sheet's, and of the
  /// navigation bar's in front of it.
  static const double cornerRadius = 28;

  /// The band, as the accessory sits on it.
  static const surface = AdaptiveAccessorySurface(
    outsets: EdgeInsets.fromLTRB(
      sidePadding,
      topPadding,
      sidePadding,
      bottomPadding,
    ),
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(cornerRadius)),
    ),
  );

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
    _band.value = empty
        ? 0
        : size.height +
              MaterialTabAccessory.topPadding +
              MaterialTabAccessory.bottomPadding;
    widget.link?.shown = !empty;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = theme.colorScheme.surfaceContainerLowest;
    // Only the sheet of the tab that holds the accessory on it.
    final sheet = widget.layout == AdaptiveTabAccessoryLayout.onSheet
        ? _sheet
        : null;
    final covered = sheet?.value ?? kAlwaysDismissedAnimation;
    final link = widget.link;
    if (link != null && link.covered != covered) {
      runOutsideLayout(() => link.covered = covered, mounted: () => mounted);
    }
    final width = MediaQuery.sizeOf(context).width;
    final accessory = AdaptiveAccessoryScope(
      spec: AdaptiveAccessorySpec(
        placement: AdaptiveChromePlacement.bottom,
        compact: false,
        room: width - 2 * MaterialTabAccessory.sidePadding,
        layout: widget.layout,
      ),
      expansion: sheet,
      surface: MaterialTabAccessory.surface,
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
            child: _LinkScope(link: link, child: widget.body),
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
                          MaterialTabAccessory.bottomPadding,
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

/// What the navigation bar under a [MaterialTabAccessory] follows: whether
/// the band shows anything, how far a page's sheet that opens from the
/// accessory covers it, and whether a page's sheet is up behind the bar.
class MaterialTabAccessoryLink extends ChangeNotifier {
  bool _shown = false;
  Animation<double> _covered = kAlwaysDismissedAnimation;
  final Set<Object> _sheetsUp = <Object>{};
  bool _disposed = false;

  /// The link of the [MaterialTabAccessory] the pages of [context] are on.
  static MaterialTabAccessoryLink? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_LinkScope>()?.link;

  /// Whether the band shows the accessory.
  bool get shown => _shown;

  set shown(bool value) {
    if (value == _shown) return;
    _shown = value;
    notifyListeners();
  }

  /// How far a page's sheet has come up into the band's place, from 0 to 1.
  Animation<double> get covered => _covered;

  set covered(Animation<double> value) {
    if (value == _covered) return;
    _covered = value;
    notifyListeners();
  }

  /// Whether a page's sheet is up, its bottom along the bar.
  bool get sheetUp => _sheetsUp.isNotEmpty;

  /// Tells whether the sheet [sheet] is up. Ignored once the link is gone,
  /// as a sheet that goes with it tells of that after the frame.
  void setSheetUp(Object sheet, {required bool up}) {
    if (_disposed) return;
    final changed = up ? _sheetsUp.add(sheet) : _sheetsUp.remove(sheet);
    if (changed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

class _LinkScope extends InheritedWidget {
  const _LinkScope({required this.link, required super.child});

  final MaterialTabAccessoryLink? link;

  @override
  bool updateShouldNotify(_LinkScope oldWidget) => link != oldWidget.link;
}

/// The navigation bar under a [MaterialTabAccessory]: its top corners round
/// in while the band's card shows or a page's sheet is up, and flatten again
/// as they go, the card's or the sheet's colour showing around them.
class MaterialTabAccessoryBar extends StatefulWidget {
  const MaterialTabAccessoryBar({
    super.key,
    required this.link,
    required this.child,
  });

  final MaterialTabAccessoryLink link;
  final Widget child;

  @override
  State<MaterialTabAccessoryBar> createState() =>
      _MaterialTabAccessoryBarState();
}

class _MaterialTabAccessoryBarState extends State<MaterialTabAccessoryBar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _shown = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 300),
    value: widget.link.shown || widget.link.sheetUp ? 1 : 0,
  );

  @override
  void initState() {
    super.initState();
    widget.link.addListener(_onLinkChanged);
  }

  @override
  void didUpdateWidget(MaterialTabAccessoryBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.link == widget.link) return;
    oldWidget.link.removeListener(_onLinkChanged);
    widget.link.addListener(_onLinkChanged);
    _onLinkChanged();
  }

  @override
  void dispose() {
    widget.link.removeListener(_onLinkChanged);
    _shown.dispose();
    super.dispose();
  }

  void _onLinkChanged() {
    if (!mounted) return;
    final shown = widget.link.shown || widget.link.sheetUp;
    if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) {
      _shown.value = shown ? 1 : 0;
    } else if (shown) {
      _shown.forward();
    } else {
      _shown.reverse();
    }
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final link = widget.link;
    final covered = link.covered;
    final scheme = Theme.of(context).colorScheme;
    return AnimatedBuilder(
      animation: Listenable.merge([_shown, covered]),
      child: widget.child,
      builder: (context, child) {
        final rounding = Curves.easeOutCubic.transform(_shown.value);
        // What meets the bar: the band's card, or the sheet that came up
        // into its place or stands above the bar.
        final behind = link.shown
            ? Color.lerp(
                scheme.surfaceContainerLowest,
                scheme.surfaceContainerLow,
                covered.value.clamp(0.0, 1.0),
              )!
            : scheme.surfaceContainerLow;
        return Stack(
          children: [
            Positioned(
              left: 0,
              right: 0,
              top: 0,
              height: MaterialTabAccessory.cornerRadius,
              child: ColoredBox(color: behind),
            ),
            ClipRRect(
              borderRadius: BorderRadius.vertical(
                top: Radius.circular(
                  MaterialTabAccessory.cornerRadius * rounding,
                ),
              ),
              clipBehavior: rounding > 0 ? Clip.antiAlias : Clip.none,
              child: child,
            ),
          ],
        );
      },
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
