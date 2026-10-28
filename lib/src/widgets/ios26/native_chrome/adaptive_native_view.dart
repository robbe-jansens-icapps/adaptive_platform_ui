import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'adaptive_native_chrome.dart';
import 'native_chrome_view.dart';

/// A native iOS view: over the Flutter view when [chrome] is asked for and
/// [AdaptiveNativeChrome.enabled] ([NativeChromeView]), otherwise a platform
/// view ([UiKitView]). Either way the same factory makes it and
/// [onPlatformViewCreated] gets the id its channel is named with.
///
/// Only views that Flutter never draws on, and whose stand-in takes their
/// place while Flutter content covers them, can be shown over the Flutter view.
class AdaptiveNativeView extends StatelessWidget {
  const AdaptiveNativeView({
    super.key,
    required this.viewType,
    this.creationParams,
    this.onPlatformViewCreated,
    this.hitTestBehavior = PlatformViewHitTestBehavior.opaque,
    this.gestureRecognizers = const <Factory<OneSequenceGestureRecognizer>>{},
    this.chrome = false,
    this.interactive = true,
  });

  final String viewType;
  final Object? creationParams;
  final PlatformViewCreatedCallback? onPlatformViewCreated;
  final PlatformViewHitTestBehavior hitTestBehavior;
  final Set<Factory<OneSequenceGestureRecognizer>> gestureRecognizers;
  final bool chrome;

  /// See [NativeChromeView.interactive].
  final bool interactive;

  @override
  Widget build(BuildContext context) {
    if (chrome && AdaptiveNativeChrome.enabled) {
      return NativeChromeView(
        key: const ValueKey<String>('chrome'),
        viewType: viewType,
        creationParams: creationParams,
        onPlatformViewCreated: onPlatformViewCreated,
        interactive: interactive,
      );
    }
    return UiKitView(
      key: const ValueKey<String>('platform'),
      viewType: viewType,
      creationParams: creationParams,
      creationParamsCodec: const StandardMessageCodec(),
      onPlatformViewCreated: onPlatformViewCreated,
      hitTestBehavior: hitTestBehavior,
      gestureRecognizers: gestureRecognizers,
    );
  }
}
