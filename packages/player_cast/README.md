# player_cast

Chromecast session for [`player_core`](../player_core). Discover devices,
connect, and play an HTTP(S) stream on the **Default Media Receiver**. Local
frames stay on `PlayerView`; this package does not draw a Cast button.

Native: Google Cast SDK (Android Play Services Cast, iOS `google-cast-sdk`)
behind **Pigeon**. Apps that never depend on this package never load the SDK.

See [`specs/07-cast/chromecast.md`](../../specs/07-cast/chromecast.md).

```dart
final cast = CastClient();
await cast.startDiscovery();
cast.devices.listen((list) { /* app paints a list */ });
await cast.transfer(controller, list.first);
await cast.disconnect(resumeLocal: true);
await cast.dispose();
```

`transfer` pauses the local `PlayerController`, loads its `loadedUri` at the
current position, and plays on the receiver. `disconnect(resumeLocal: true)`
seeks the local player back and plays if it was playing when transferred.

While connected, `CastRemotePlayer.setPlaybackSpeed` / `setAudioTrack` /
`setTextTrack` talk to the TV. `setVideoTrack` fails loudly on the Default
Media Receiver (it keeps ABR). HLS WebVTT from `#EXT-X-MEDIA:TYPE=SUBTITLES`
is attached on load so captions can be switched even when the master omits
`SUBTITLES=` on the variant lines. Segmented HLS WebVTT is stitched into one
file first — Chromecast cannot play a subtitle `.m3u8` as a sidecar track.

HTTP(S) only. Media headers and DRM fail loudly (`ArgumentError`). Custom CAF
receivers can pass a different `receiverAppId`; Default Media Receiver is
`CC1AD845`.

HLS is loaded as **CMAF / fMP4** (`hlsSegmentFormat` + `hlsVideoSegmentFormat`).
That matches Mux / FastPix / Cloudflare Stream. MPEG-TS HLS is not tagged; a
custom receiver or a later spec is needed for that container.

## Host app

### Android

The plugin registers a `CastOptionsProvider` (Default Media Receiver). To use
your own App ID, set it on `CastClient(receiverAppId: …)` **and** replace the
provider in the app manifest:

```xml
<meta-data
    android:name="com.google.android.gms.cast.framework.OPTIONS_PROVIDER_CLASS_NAME"
    android:value="com.example.MyCastOptionsProvider"
    tools:replace="android:value" />
```

Play Services must be present. Missing Play Services → `CastSessionState.unavailable`.

### iOS

Bonjour + local network must be in the **app** `Info.plist` (not the plugin):

```xml
<key>NSBonjourServices</key>
<array>
  <string>_googlecast._tcp</string>
  <string>_CC1AD845._googlecast._tcp</string>
</array>
<key>NSLocalNetworkUsageDescription</key>
<string>Used to discover Cast devices on your network.</string>
```

For a custom receiver, add `_<YOUR_APP_ID>._googlecast._tcp` as well. Minimum
iOS is 15 (Cast SDK 4.8.4).

## Not in this package

Cast button, Expanded Controller, device picker widget, media headers, DRM on
the receiver, queue/playlist, AirPlay.

## License

Proprietary. See [`LICENSE`](LICENSE).
