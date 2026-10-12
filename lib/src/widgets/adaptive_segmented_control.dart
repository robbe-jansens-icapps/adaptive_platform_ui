import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import '../platform/platform_info.dart';
import 'ios26/ios26_segmented_control.dart';

/// An adaptive segmented control that renders platform-specific styles
///
/// On iOS 26+: Uses native iOS 26 UISegmentedControl with Liquid Glass
/// On iOS <26 (iOS 18 and below): Uses CupertinoSlidingSegmentedControl
/// On Android: a Material 3 Expressive pill: the selected segment a filled
/// pill that slides from one segment to the next, without a checkmark
class AdaptiveSegmentedControl extends StatelessWidget {
  /// Creates an adaptive segmented control
  const AdaptiveSegmentedControl({
    super.key,
    required this.labels,
    required this.selectedIndex,
    required this.onValueChanged,
    this.enabled = true,
    this.color,
    this.height = 36.0,
    this.shrinkWrap = false,
    this.sfSymbols,
    this.iconSize,
    this.iconColor,
    this.textColor,
    this.selectedTextColor,
  });

  /// Segment labels to display, in order
  final List<String> labels;

  /// The index of the selected segment
  final int selectedIndex;

  /// Called when the user selects a segment
  final ValueChanged<int> onValueChanged;

  /// Whether the control is interactive
  final bool enabled;

  /// Tint color for the selected segment
  final Color? color;

  /// Height of the control
  final double height;

  /// Whether the control should shrink to fit content
  final bool shrinkWrap;

  /// Optional SF Symbol names or IconData
  final List<dynamic>? sfSymbols;

  /// Icon size
  final double? iconSize;

  /// Icon color
  final Color? iconColor;

  /// Optional text color for unselected segments.
  final Color? textColor;

  /// Optional text color for the selected segment.
  final Color? selectedTextColor;

  @override
  Widget build(BuildContext context) {
    // iOS 26+ - Use native iOS 26 segmented control
    if (PlatformInfo.isIOS26OrHigher()) {
      return IOS26SegmentedControl(
        labels: labels,
        selectedIndex: selectedIndex,
        onValueChanged: onValueChanged,
        enabled: enabled,
        color: color,
        height: height,
        shrinkWrap: shrinkWrap,
        icons: sfSymbols,
        iconSize: iconSize,
        iconColor: iconColor,
        textColor: textColor,
        selectedTextColor: selectedTextColor,
      );
    }

    // iOS <26 (iOS 18 and below) - Use CupertinoSlidingSegmentedControl
    if (PlatformInfo.isIOS) {
      return _buildCupertinoSegmentedControl(context);
    }

    // Android - a Material 3 Expressive pill
    if (PlatformInfo.isAndroid) {
      return _MaterialSegmentedPill(control: this);
    }

    // Fallback
    return _buildCupertinoSegmentedControl(context);
  }

  Widget _buildCupertinoSegmentedControl(BuildContext context) {
    final theme = CupertinoTheme.of(context);
    final effectiveTextColor =
        textColor ??
        theme.textTheme.textStyle.color ??
        (Theme.of(context).brightness == Brightness.dark
            ? CupertinoColors.white
            : CupertinoColors.black);
    final effectiveSelectedTextColor =
        selectedTextColor ??
        (color != null ? CupertinoColors.white : effectiveTextColor);

    // Build children map from labels or icons
    final Map<int, Widget> children = {};

    // Check if using icons
    final useIcons = sfSymbols != null && sfSymbols!.isNotEmpty;
    final itemCount = useIcons ? sfSymbols!.length : labels.length;

    for (int i = 0; i < itemCount; i++) {
      if (useIcons) {
        // Icon mode
        final dynamic icon = sfSymbols![i];
        children[i] = Padding(
          padding: const EdgeInsets.all(8),
          child: icon is IconData
              ? Icon(icon, size: iconSize ?? 20, color: iconColor)
              : Text(icon.toString()),
        );
      } else {
        // Text mode
        children[i] = Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Text(
            labels[i],
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: selectedIndex == i
                  ? effectiveSelectedTextColor
                  : effectiveTextColor,
            ),
          ),
        );
      }
    }

    Widget control = color != null
        ? CupertinoSlidingSegmentedControl<int>(
            children: children,
            groupValue: selectedIndex,
            thumbColor: color!,
            onValueChanged: (int? value) {
              if (enabled && value != null) {
                onValueChanged(value);
              }
            },
          )
        : CupertinoSlidingSegmentedControl<int>(
            children: children,
            groupValue: selectedIndex,
            onValueChanged: (int? value) {
              if (enabled && value != null) {
                onValueChanged(value);
              }
            },
          );

    control = ConstrainedBox(
      constraints: BoxConstraints(minHeight: height),
      child: control,
    );

    if (shrinkWrap) {
      control = Center(child: IntrinsicWidth(child: control));
    }

    return control;
  }
}

/// The segmented control of Android: a pill-shaped track with the selected
/// segment a filled pill on it, in [AdaptiveSegmentedControl.color], that
/// slides to the segment picked, the way Material 3 Expressive draws a
/// connected button group. No outline and no checkmark: the fill says which
/// segment is selected.
class _MaterialSegmentedPill extends StatelessWidget {
  const _MaterialSegmentedPill({required this.control});

  final AdaptiveSegmentedControl control;

  static const _inset = 4.0;
  static const _duration = Duration(milliseconds: 250);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final c = control;
    final icons = c.sfSymbols;
    final useIcons = icons != null && icons.isNotEmpty;
    final count = useIcons ? icons.length : c.labels.length;
    final thumbColor = c.color ?? scheme.primary;
    final selectedColor =
        c.selectedTextColor ??
        (c.color != null ? Colors.white : scheme.onPrimary);
    final color = c.textColor ?? scheme.onSurface;
    // Never lower than Material's smallest touch target.
    final height = c.height < 40 ? 40.0 : c.height;
    final reduceMotion = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    final duration = reduceMotion ? Duration.zero : _duration;
    final selected = c.selectedIndex.clamp(0, count < 1 ? 0 : count - 1);

    Widget segment(int index) {
      final isSelected = index == selected;
      final foreground = isSelected ? selectedColor : color;
      final Widget content;
      if (useIcons) {
        final icon = icons[index];
        content = Icon(
          icon is IconData ? icon : Icons.circle,
          size: c.iconSize ?? 20,
          color: isSelected ? foreground : (c.iconColor ?? foreground),
        );
      } else {
        content = AnimatedDefaultTextStyle(
          duration: duration,
          style: (theme.textTheme.labelLarge ?? const TextStyle()).copyWith(
            color: foreground,
            fontWeight: FontWeight.w600,
          ),
          child: Text(
            c.labels[index],
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
          ),
        );
      }
      return Semantics(
        button: true,
        selected: isSelected,
        inMutuallyExclusiveGroup: true,
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: c.enabled && !isSelected
              ? () => c.onValueChanged(index)
              : null,
          child: SizedBox(
            height: height - 2 * _inset,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Center(child: content),
            ),
          ),
        ),
      );
    }

    Widget pill = DecoratedBox(
      decoration: ShapeDecoration(
        color: scheme.surfaceContainerHigh,
        shape: const StadiumBorder(),
      ),
      child: Padding(
        padding: const EdgeInsets.all(_inset),
        child: Stack(
          children: [
            if (count > 0)
              Positioned.fill(
                child: AnimatedAlign(
                  duration: duration,
                  curve: Curves.easeOutCubic,
                  alignment: Alignment(
                    count < 2 ? 0 : -1 + 2 * selected / (count - 1),
                    0,
                  ),
                  child: FractionallySizedBox(
                    widthFactor: 1 / count,
                    heightFactor: 1,
                    child: DecoratedBox(
                      decoration: ShapeDecoration(
                        color: thumbColor,
                        shape: const StadiumBorder(),
                      ),
                    ),
                  ),
                ),
              ),
            Material(
              type: MaterialType.transparency,
              child: Row(
                children: [
                  for (var i = 0; i < count; i++) Expanded(child: segment(i)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
    if (!c.enabled) pill = Opacity(opacity: 0.38, child: pill);
    if (c.shrinkWrap) pill = Center(child: IntrinsicWidth(child: pill));
    return pill;
  }
}
