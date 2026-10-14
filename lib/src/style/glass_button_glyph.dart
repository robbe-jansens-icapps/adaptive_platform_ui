import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'sf_symbol.dart';

/// The glyph of a native glass button (`AdaptiveButton.sfSymbol` on iOS 26)
/// as iOS shows it, for Flutter to stand in for the button where a native
/// view would cost frames, such as while pages move.
///
/// iOS makes such a button and lays it out, and hands over what it shows:
/// the symbol at the size the button shows it (which its configuration can
/// make larger than the symbol it is given), the colour it draws it in, and
/// where in the button. An icon font would need the app to bundle one, and
/// would only come close.
///
/// iOS only: elsewhere, and for a symbol iOS lacks, there is none.
@immutable
class GlassButtonGlyph {
  const GlassButtonGlyph({
    required this.image,
    required this.color,
    this.offset = Offset.zero,
  });

  /// A mask in the glyph's shape, at its size, for [color] to tint.
  final ImageProvider image;

  /// The colour the button draws the glyph in.
  final Color color;

  /// How far the glyph's centre is off the button's.
  final Offset offset;

  static const _channel = MethodChannel('adaptive_platform_ui/symbols');

  static final Map<_Key, Future<GlassButtonGlyph?>> _loads =
      <_Key, Future<GlassButtonGlyph?>>{};
  static final Map<_Key, GlassButtonGlyph> _ready = <_Key, GlassButtonGlyph>{};

  /// The glyph of a button [side] points square with [symbol], in the dark
  /// appearance or not, once [load] has it ready to paint; null before.
  static GlassButtonGlyph? of(
    SFSymbol symbol, {
    required double side,
    required bool dark,
  }) => _ready[_keyOf(symbol, side, dark)];

  /// Has iOS show the glyph, once per symbol, size and appearance, and
  /// decodes it for [context], so it paints in the first frame that shows it.
  static Future<GlassButtonGlyph?> load(
    SFSymbol symbol,
    BuildContext context, {
    required double side,
    required bool dark,
  }) {
    final key = _keyOf(symbol, side, dark);
    return _loads[key] ??= () async {
      try {
        final reply = await _channel
            .invokeMapMethod<String, Object?>('buttonGlyph', {
              'name': symbol.name,
              'size': symbol.size,
              if (symbol.weight != null) 'weight': symbol.weight!.value,
              'side': side,
              'isDark': dark,
            });
        final bytes = reply?['bytes'];
        final color = reply?['color'];
        if (bytes is! Uint8List || color is! int) return null;
        if (!context.mounted) {
          // Asked for by a widget that has gone: the next one asks again.
          _loads.remove(key);
          return null;
        }
        final image = MemoryImage(
          bytes,
          scale: (reply?['scale'] as num?)?.toDouble() ?? 1,
        );
        if (debugDecodes) await precacheImage(image, context);
        return _ready[key] = GlassButtonGlyph(
          image: image,
          color: Color(color),
          offset: Offset(
            (reply?['dx'] as num?)?.toDouble() ?? 0,
            (reply?['dy'] as num?)?.toDouble() ?? 0,
          ),
        );
      } on MissingPluginException {
        return null;
      } on PlatformException {
        return null;
      }
    }();
  }

  /// Whether [load] decodes the image before it hands the glyph out. Widget
  /// tests turn it off: their clock never lets a decode finish.
  @visibleForTesting
  static bool debugDecodes = true;

  /// Forgets every glyph, so the next test asks iOS again.
  @visibleForTesting
  static void debugReset() {
    _loads.clear();
    _ready.clear();
    debugDecodes = true;
  }
}

typedef _Key = (String, double, int?, double, bool);

_Key _keyOf(SFSymbol symbol, double side, bool dark) =>
    (symbol.name, symbol.size, symbol.weight?.value, side, dark);
