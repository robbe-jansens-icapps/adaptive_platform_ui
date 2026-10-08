import 'package:flutter/foundation.dart';

enum _DetentKind { hidden, collapsed, fitContent, height, fraction, large }

/// A height an [AdaptiveSheet] comes to rest at.
@immutable
class AdaptiveSheetDetent {
  const AdaptiveSheetDetent._(this._kind, [this._value = 0]);

  /// Out of view. Always available to [AdaptiveSheetController.animateTo],
  /// whatever the sheet's detents are, but never chosen by a drag.
  static const hidden = AdaptiveSheetDetent._(_DetentKind.hidden);

  /// Just the grabber and the header, above the bottom bar.
  static const collapsed = AdaptiveSheetDetent._(_DetentKind.collapsed);

  /// Tall enough for the header and the whole content, as far as it fits.
  static const fitContent = AdaptiveSheetDetent._(_DetentKind.fitContent);

  /// Nearly the full height. A floating sheet becomes edge to edge here.
  static const large = AdaptiveSheetDetent._(_DetentKind.large);

  /// A fixed height in logical pixels, measured from the bottom.
  const AdaptiveSheetDetent.height(double height)
    : this._(_DetentKind.height, height);

  /// A share of the available height, from 0 to 1.
  const AdaptiveSheetDetent.fraction(double fraction)
    : assert(fraction >= 0 && fraction <= 1),
      _kind = _DetentKind.fraction,
      _value = fraction;

  final _DetentKind _kind;
  final double _value;

  bool get isHidden => _kind == _DetentKind.hidden;
  bool get isLarge => _kind == _DetentKind.large;

  /// The extent (visible height, from the bottom of the sheet's area) of this
  /// detent.
  double resolve({
    required double collapsed,
    required double fitContent,
    required double large,
    required double available,
  }) {
    final extent = switch (_kind) {
      _DetentKind.hidden => 0.0,
      _DetentKind.collapsed => collapsed,
      _DetentKind.fitContent => fitContent,
      _DetentKind.height => _value,
      _DetentKind.fraction => _value * available,
      _DetentKind.large => large,
    };
    return isHidden ? 0 : extent.clamp(collapsed, large);
  }

  @override
  bool operator ==(Object other) =>
      other is AdaptiveSheetDetent &&
      other._kind == _kind &&
      other._value == _value;

  @override
  int get hashCode => Object.hash(_kind, _value);

  @override
  String toString() => switch (_kind) {
    _DetentKind.height => 'AdaptiveSheetDetent.height($_value)',
    _DetentKind.fraction => 'AdaptiveSheetDetent.fraction($_value)',
    _ => 'AdaptiveSheetDetent.${_kind.name}',
  };
}
