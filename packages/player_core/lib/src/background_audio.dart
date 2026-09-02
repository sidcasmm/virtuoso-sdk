/// Lock-screen / notification session for the current [PlayerController].
enum BackgroundAudioState {
  /// Cannot host a now-playing session (no service / disposed engine).
  unavailable,

  /// Available and this controller is not the session owner.
  inactive,

  /// This controller owns now-playing / the Android foreground service.
  active,
}

/// Optional metadata for the OS now-playing / media notification chrome.
final class NowPlaying {
  const NowPlaying({this.title, this.artist, this.album, this.artworkUri});

  final String? title;
  final String? artist;
  final String? album;

  /// Network image for the OS artwork. Null = no artwork.
  /// Non-http(s) is rejected by [PlayerController.setNowPlaying].
  final Uri? artworkUri;

  @override
  bool operator ==(Object other) =>
      other is NowPlaying &&
      title == other.title &&
      artist == other.artist &&
      album == other.album &&
      artworkUri == other.artworkUri;

  @override
  int get hashCode => Object.hash(title, artist, album, artworkUri);
}
