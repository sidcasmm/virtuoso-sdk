import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'ads_client.dart';

/// Transparent IMA overlay stacked on [PlayerView]. Not a Flutter skip button.
class AdsView extends StatelessWidget {
  const AdsView({super.key, required this.client});

  final AdsClient client;

  static const viewType = 'player_ads/overlay';

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<AdState>(
      stream: client.states,
      initialData: client.state,
      builder: (context, _) {
        final id = client.boundPlayerId;
        if (id == null) {
          return const SizedBox.expand();
        }
        // Only steal hits while an ad is actually on screen. `loading` must
        // not cover the play button — IMA can paint a first frame before
        // `play()`.
        final absorbing = client.state == AdState.playing;
        return IgnorePointer(
          ignoring: !absorbing,
          child: _AdsOverlay(playerId: id, absorbing: absorbing),
        );
      },
    );
  }
}

class _AdsOverlay extends StatelessWidget {
  const _AdsOverlay({required this.playerId, required this.absorbing});

  final int playerId;
  final bool absorbing;

  @override
  Widget build(BuildContext context) {
    final params = <String, Object>{'playerId': playerId};
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return PlatformViewLink(
          viewType: AdsView.viewType,
          surfaceFactory: (context, controller) {
            return AndroidViewSurface(
              controller: controller as AndroidViewController,
              gestureRecognizers:
                  const <Factory<OneSequenceGestureRecognizer>>{},
              hitTestBehavior: absorbing
                  ? PlatformViewHitTestBehavior.opaque
                  : PlatformViewHitTestBehavior.transparent,
            );
          },
          onCreatePlatformView: (viewParams) {
            return PlatformViewsService.initExpensiveAndroidView(
                id: viewParams.id,
                viewType: AdsView.viewType,
                layoutDirection: TextDirection.ltr,
                creationParams: params,
                creationParamsCodec: const StandardMessageCodec(),
              )
              ..addOnPlatformViewCreatedListener(
                viewParams.onPlatformViewCreated,
              )
              ..create();
          },
        );
      case TargetPlatform.iOS:
        return UiKitView(
          viewType: AdsView.viewType,
          creationParams: params,
          creationParamsCodec: const StandardMessageCodec(),
        );
      default:
        return const SizedBox.expand();
    }
  }
}
