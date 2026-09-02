# player_core

Engine-agnostic Flutter video player. Dart talks to Media3 (Android) and
AVPlayer (iOS) through **Pigeon** only.

This package is **API-first**: `PlayerController` methods and streams, plus
`PlayerView` for frames. There is no bundled play button, seek bar, or
fullscreen widget — the app builds those.

| Format | Android | iOS |
|---|---|---|
| MP4 | yes | yes |
| HLS (`.m3u8`) | yes | yes |
| DASH (`.mpd`) | yes | no — `sourceUnsupported` |

AVPlayer cannot demux MPEG-DASH. Use HLS or MP4 on iOS.

Bind your spinner to `playbackState == buffering`. After `play()`, turning
the network off should stay on `buffering` and resume when you are online
again — the app does not call `load` a second time. A URL that never works
(404 / DNS) still fires `errors` once.

Specs:

- [`specs/00-foundation/architecture.md`](../../specs/00-foundation/architecture.md)
- [`specs/01-core/player-controller.md`](../../specs/01-core/player-controller.md)
- [`specs/01-core/media-sources.md`](../../specs/01-core/media-sources.md)
- [`specs/01-core/http-headers.md`](../../specs/01-core/http-headers.md)
- [`specs/01-core/network-resiliency.md`](../../specs/01-core/network-resiliency.md)
- [`specs/02-tracks/quality-switching.md`](../../specs/02-tracks/quality-switching.md)
- [`specs/02-tracks/audio-switching.md`](../../specs/02-tracks/audio-switching.md)
- [`specs/02-tracks/subtitle-switching.md`](../../specs/02-tracks/subtitle-switching.md)
- [`specs/02-tracks/preload-cache.md`](../../specs/02-tracks/preload-cache.md)
- [`specs/03-dart-features/playlist.md`](../../specs/03-dart-features/playlist.md)
- [`specs/03-dart-features/chapters.md`](../../specs/03-dart-features/chapters.md)
- [`specs/03-dart-features/skip-segment.md`](../../specs/03-dart-features/skip-segment.md)
- [`specs/03-dart-features/spritesheet.md`](../../specs/03-dart-features/spritesheet.md)
- [`specs/03-dart-features/analytics.md`](../../specs/03-dart-features/analytics.md)
- [`specs/04-lifecycle/picture-in-picture.md`](../../specs/04-lifecycle/picture-in-picture.md)
- [`specs/04-lifecycle/background-audio.md`](../../specs/04-lifecycle/background-audio.md)
- [`specs/08-downloads/offline-downloads.md`](../../specs/08-downloads/offline-downloads.md)
- [`specs/09-ads/csai.md`](../../specs/09-ads/csai.md)

Last loaded source: `loadedUri` / `loadedHeaders` / `loadedDrm` (used by `player_cast` handoff).

Host app (required for PiP and background audio):

```xml
<!-- AndroidManifest.xml activity -->
android:supportsPictureInPicture="true"
```

Android 13+ should request `POST_NOTIFICATIONS` at runtime so the media
notification is visible. The plugin already merges `FOREGROUND_SERVICE`,
`FOREGROUND_SERVICE_MEDIA_PLAYBACK`, `POST_NOTIFICATIONS`, and a
`mediaPlayback` `MediaSessionService`.

Extend `PipAwareFlutterActivity` (or call `PlayerCorePip.onPictureInPictureModeChanged`
from your activity).

```xml
<!-- ios Info.plist — required for PiP and background audio -->
<key>UIBackgroundModes</key>
<array><string>audio</string></array>
```

## Usage

```dart
final controller = PlayerController();
await controller.load(
  Uri.parse('https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/BigBuckBunny.mp4'),
);
await controller.load(
  Uri.parse('https://cdn.example.com/live/master.m3u8'),
  headers: {'Authorization': 'Bearer token'},
);
await controller.load(
  Uri.parse('https://cdn.example.com/movie.mpd'),
  drm: DrmConfiguration(
    scheme: DrmScheme.widevine,
    licenseUrl: Uri.parse('https://license.example.com/widevine'),
    licenseHeaders: {'Authorization': 'Bearer license-token'},
  ),
);
await controller.play(); // autoplay is the app calling play() after load
await controller.setLooping(true);

// Local file or Flutter asset:
await controller.load(Uri.file('/data/clip.mp4'));
await controller.loadAsset('assets/clip.mp4');

controller.videoTracks.listen((list) {
  // App builds its own quality menu from list.tracks.
});
await controller.setVideoTrack(controller.videoTrackList.tracks.first.id);
await controller.setVideoTrack(null); // ABR

controller.audioTracks.listen((list) {
  // App builds its own audio menu from list.tracks.
});
await controller.setAudioTrack(controller.audioTrackList.tracks.first.id);
await controller.setAudioTrack(null); // engine default

controller.textTracks.listen((list) {
  // App builds its own CC menu from list.tracks.
});
await controller.setTextTrack(controller.textTrackList.tracks.first.id);
controller.subtitleCues.listen((cues) {
  // App paints cue text over PlayerView.
});
await controller.setTextTrack(null); // Off

final cache = PlayerCache();
await cache.configure(); // 512 MiB disk cache
await cache.preload(Uri.parse('https://cdn.example.com/clip.mp4'));
print(await cache.cachedBytes);
await cache.clear();

await controller.setPlaylist([
  PlaylistItem(uri: Uri.parse('https://cdn.example.com/a.m3u8'), title: 'A'),
  PlaylistItem(uri: Uri.parse('https://cdn.example.com/b.m3u8'), title: 'B'),
]);
await controller.playAt(0);
await controller.playNext();
controller.playlists.listen((list) {
  // App builds next/prev from list.hasPrevious / list.hasNext.
});

await controller.setChapters([
  Chapter(start: Duration.zero, title: 'Intro'),
  Chapter(start: Duration(minutes: 1, seconds: 30), title: 'Scene 2'),
]);
controller.currentChapters.listen((chapter) {
  // App paints chapter title / seek-bar marks.
});
await controller.seekToChapter(1);

await controller.setSkipSegments([
  SkipSegment(
    start: Duration.zero,
    end: Duration(seconds: 8),
    label: 'intro',
  ),
]);
controller.currentSkipSegments.listen((segment) {
  // App paints a Skip chip while segment != null.
});
await controller.skipCurrentSegment();

await controller.setSpriteSheet(SpriteSheet(
  spriteUrl: Uri.parse('https://cdn.example.com/sprite.jpg'),
  metadataUrl: Uri.parse('https://cdn.example.com/sprite.json'),
));
await controller.setSpriteSheetFromUrl(
  Uri.parse('https://cdn.example.com/thumbnails.vtt'),
);
final cue = controller.spriteCueAt(const Duration(seconds: 12));
// App crops cue.image to cue.x/y/width/height (e.g. on scrub).

controller.droppedFrames.listen((count) { /* QoE */ });
controller.liveOffsets.listen((offset) { /* live latency */ });

if (controller.isPictureInPictureAvailable) {
  await controller.enterPictureInPicture();
}
controller.pictureInPictureStates.listen((state) {
  // Hide app chrome when state == PictureInPictureState.active.
});
controller.pictureInPictureExits.listen((kind) {
  // restored = user came back; dismissed = user closed PiP (core paused).
});
await controller.setPictureInPictureAutomatic(true); // Home → PiP while playing

await controller.setNowPlaying(
  NowPlaying(title: 'Episode 1', artist: 'Show'),
);
await controller.setBackgroundAudioEnabled(true);
// Default is off: Home / lock pauses. When on, audio keeps going and
// the OS draws the notification / lock-screen controls.
controller.backgroundAudioStates.listen((state) {
  // active = this controller owns lock-screen / notification chrome.
});

// In a widget:
PlayerView(controller: controller)

await controller.dispose();
```

Regenerate Pigeon bindings after editing `pigeons/player_api.dart`:

```sh
cd packages/player_core
dart run pigeon --input pigeons/player_api.dart
```

## License

Proprietary. See [`LICENSE`](LICENSE).
