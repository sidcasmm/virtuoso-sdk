/// Closed set of playback states. No engine-specific members.
enum PlaybackState {
  idle,
  loading,
  ready,
  playing,
  paused,
  buffering,
  completed,
  error,
  disposed,
}
