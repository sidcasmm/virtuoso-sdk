## 0.0.1

* `DownloadClient`: enqueue, pause, resume, cancel, remove, and play
  completed HTTP(S) media offline on a `PlayerController`.
* Progressive MP4 and HLS on Android and iOS; DASH on Android.
  Persistable Widevine / FairPlay / ClearKey licenses at enqueue.
* `DownloadTracks` on enqueue: cap video height/bitrate, pin audio and
  caption languages.
* Prefer a completed pin over the network URI
  (`loadPreferringOffline` / `preferringOffline`).
