## 0.0.1

* `CastClient`: discover Chromecast devices, connect a session, transfer
  playback from `PlayerController`, and control the Default Media Receiver.
* Remote `setPlaybackSpeed`, in-stream audio/text tracks (`setActiveMediaTracks`).
  HLS WebVTT listed in the master (`#EXT-X-MEDIA:TYPE=SUBTITLES`) is stitched
  into a single WebVTT file (the Default Media Receiver cannot play segmented
  VTT playlists as sidecar tracks) and attached as Cast `MediaTrack`s.
  Quality lock is not supported on the Default Media Receiver.
