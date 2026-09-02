## 0.0.1

* Initial `PlayerController`: load/play/pause/seek, four architecture streams,
  Media3 + AVPlayer via Pigeon, `PlayerView`.
* HLS and DASH (DASH on Android; iOS DASH fails with `sourceUnsupported`).
* File, Flutter asset, and Android `content://` sources (`load` / `loadAsset`).
* Optional HTTP headers on network `load` (Authorization, CDN tokens).
* Buffering vs terminal error mapping; mid-play network loss retries until resume.
* Video quality switching: `videoTracks` + `setVideoTrack` (Android lock, iOS 15+ ABR cap).
* Audio track switching: `audioTracks` + `setAudioTrack` (HLS/DASH language tracks).
* Subtitle switching: `textTracks` + `setTextTrack` + `subtitleCues` (in-stream WebVTT/HLS; app paints cues).
* Disk cache + preload: `PlayerCache` (Media3 `SimpleCache` on Android; iOS progressive files).
* Playlist queue: `PlaylistItem` / `Playlist`, `playAt` / `playNext` / `playPrevious` (Dart-only; auto-advance on complete unless looping).
* Chapters: `Chapter`, `setChapters` / `setChaptersFromVtt`, `seekToChapter`, `currentChapters` (Dart-only from position).
* Spritesheet seek preview: `SpriteSheet` / `SpriteCue`, `setSpriteSheet` / `setSpriteSheetFromUrl` / `setSpriteCues`, `spriteCueAt` (app paints the crop).
* Dropped-frame count and live offset streams (`droppedFrames`, `liveOffsets`) for QoE collectors.
* Picture-in-Picture: `enterPictureInPicture` / `exitPictureInPicture`, `pictureInPictureStates`, restore vs dismiss (`pictureInPictureExits`).
* Skip segments: `SkipSegment`, `setSkipSegments`, playthrough auto-seek, `skipCurrentSegment` (Dart-only).
* Protected playback: `DrmConfiguration` on `load` / `PlaylistItem` (Widevine + ClearKey on Android, FairPlay on iOS).
* Last-source getters: `loadedUri` / `loadedHeaders` / `loadedDrm` (for Cast handoff).
* `playbackSpeed` getter (last `setPlaybackSpeed`, default 1.0).
* Background audio: `setBackgroundAudioEnabled` / `NowPlaying` (Android MediaSession + media FGS; iOS lock screen / Control Center).
