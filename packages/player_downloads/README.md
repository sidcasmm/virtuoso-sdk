# player_downloads

Offline pin for [`player_core`](../player_core). Enqueue an HTTP(S) stream,
watch progress, and `play` it with the radio off. This package does not draw
a download button.

Native: Media3 `DownloadManager` (Android) and `AVAssetDownloadURLSession` /
`URLSession` (iOS) behind **Pigeon**. Apps that never depend on this package
never ship the download foreground service.

See [`specs/08-downloads/offline-downloads.md`](../../specs/08-downloads/offline-downloads.md).

```dart
final downloads = DownloadClient();
await downloads.initialized;
final id = await downloads.enqueue(
  DownloadRequest(
    uri: Uri.parse('https://cdn.example.com/ep1.m3u8'),
    title: 'Episode 1',
    tracks: DownloadTracks(
      maxHeight: 720,
      audioLanguage: 'hi',
      textLanguage: 'en',
    ),
  ),
);
downloads.items.listen((list) { /* app paints */ });
await downloads.play(controller, id);
await downloads.loadPreferringOffline(controller, Uri.parse('https://cdn.example.com/ep1.m3u8'));
await downloads.remove(id);
```

`DownloadTracks` is optional. Null fields keep engine defaults: highest
video, default audio, **no** captions. Progressive MP4 ignores the video
cap (one file). iOS 13–14 ignores the video cap; audio and captions still
apply.

Completed items load through `player-offline:<id>` on `PlayerController`.
`loadPreferringOffline` / `preferringOffline` use that pin when the
source URI already has a completed download; otherwise they stream.
HTTP(S) only. Live playlists and DASH-on-iOS fail loudly.

See [`specs/08-downloads/download-tracks.md`](../../specs/08-downloads/download-tracks.md)
and [`specs/08-downloads/prefer-offline.md`](../../specs/08-downloads/prefer-offline.md).

## Host app

### Android

The plugin declares a `dataSync` foreground service and
`POST_NOTIFICATIONS`. Android 13+ should request that permission at
runtime so the download notification is visible.

### iOS

No extra plist keys beyond what `player_core` already needs for background
audio. Downloaded files live in Application Support and are excluded from
iCloud backup.

## Not in this package

Download button, progress widget, Wi-Fi-only toggle, a quality/language
picker widget, Cast of downloads, mixing with `PlayerCache`.

## License

Proprietary. See [`LICENSE`](LICENSE).
