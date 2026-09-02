# player_ads

Client-side ad insertion for [`player_core`](../player_core). Bind a VAST or
VMAP URL, stack `AdsView` on `PlayerView`, and IMA plays pre / mid / post
rolls on the device. This package does not draw a skip button — IMA may
show SDK chrome on `AdsView`.

Native: Media3 `ImaAdsLoader` (Android) and Google IMA SDK (iOS) behind
**Pigeon**. Apps that never depend on this package never ship IMA.

Google IMA is licensed under the IMA SDK Terms of Service, separate from
this SDK's proprietary license.

See [`specs/09-ads/csai.md`](../../specs/09-ads/csai.md).

```dart
final ads = AdsClient();
await ads.initialized;
await ads.bind(
  controller,
  AdsRequest(
    tag: Uri.parse('https://pubads.g.doubleclick.net/gampad/ads?...'),
  ),
);
await controller.load(contentUri);
await controller.play();

// Stack on PlayerView:
Stack(
  fit: StackFit.expand,
  children: [
    PlayerView(controller: controller),
    AdsView(client: ads),
  ],
)
```

`bind` before `load`. HTTP(S) only. A `correlator` query param is appended
when missing. `skip()` is a no-op unless `current?.canSkip` is true.

Offline (`player-offline`) and file sources are not wrapped — content
plays with no ads. A 404 / empty tag sets `AdState.error` and still plays
content.

## Not in this package

SSAI / DAI, a Flutter skip widget, companion banners as a Dart API, Cast
of ads, ads inside `player_downloads` pins, consent TCF strings.

## License

Proprietary. See [`LICENSE`](LICENSE).
