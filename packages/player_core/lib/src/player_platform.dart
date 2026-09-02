import 'pigeons/player_api.g.dart' as pigeon;

/// Host operations the Dart controller talks to.
///
/// Production uses Pigeon; tests inject a fake.
abstract class PlayerPlatform {
  Future<pigeon.HostLicenseInfo> activateLicense(String token);
  Future<pigeon.CreatePlayerResult> create();
  Future<void> load(int playerId, pigeon.HostMediaSource source);
  Future<void> play(int playerId);
  Future<void> pause(int playerId);
  Future<void> seek(int playerId, int positionMs);
  Future<void> setVolume(int playerId, double volume);
  Future<void> setPlaybackSpeed(int playerId, double speed);
  Future<void> setLooping(int playerId, bool looping);
  Future<void> setVideoTrack(int playerId, String? trackId);
  Future<void> setAudioTrack(int playerId, String? trackId);
  Future<void> setTextTrack(int playerId, String? trackId);
  Future<void> disposePlayer(int playerId);
  Future<void> configureCache(int maxBytes);
  Future<int> cacheBytes();
  Future<void> clearCache();
  Future<void> preload(pigeon.HostMediaSource source);
  Future<void> setPictureInPictureAutomatic(int playerId, bool enabled);
  Future<void> enterPictureInPicture(
    int playerId,
    int? aspectWidth,
    int? aspectHeight,
    pigeon.HostPipSourceRect? sourceRect,
  );
  Future<void> exitPictureInPicture(int playerId);
  Future<void> setBackgroundAudioEnabled(int playerId, bool enabled);
  Future<void> setNowPlaying(
    int playerId,
    String? title,
    String? artist,
    String? album,
    String? artworkUri,
  );
  Stream<pigeon.HostPlayerEvent> events();
}

class PigeonPlayerPlatform implements PlayerPlatform {
  PigeonPlayerPlatform({pigeon.PlayerHostApi? api, this._eventStream})
    : _api = api ?? pigeon.PlayerHostApi();

  final pigeon.PlayerHostApi _api;
  final Stream<pigeon.HostPlayerEvent>? _eventStream;

  @override
  Future<pigeon.HostLicenseInfo> activateLicense(String token) =>
      _api.activateLicense(token);

  @override
  Future<pigeon.CreatePlayerResult> create() => _api.create();

  @override
  Future<void> load(int playerId, pigeon.HostMediaSource source) =>
      _api.load(playerId, source);

  @override
  Future<void> play(int playerId) => _api.play(playerId);

  @override
  Future<void> pause(int playerId) => _api.pause(playerId);

  @override
  Future<void> seek(int playerId, int positionMs) =>
      _api.seek(playerId, positionMs);

  @override
  Future<void> setVolume(int playerId, double volume) =>
      _api.setVolume(playerId, volume);

  @override
  Future<void> setPlaybackSpeed(int playerId, double speed) =>
      _api.setPlaybackSpeed(playerId, speed);

  @override
  Future<void> setLooping(int playerId, bool looping) =>
      _api.setLooping(playerId, looping);

  @override
  Future<void> setVideoTrack(int playerId, String? trackId) =>
      _api.setVideoTrack(playerId, trackId);

  @override
  Future<void> setAudioTrack(int playerId, String? trackId) =>
      _api.setAudioTrack(playerId, trackId);

  @override
  Future<void> setTextTrack(int playerId, String? trackId) =>
      _api.setTextTrack(playerId, trackId);

  @override
  Future<void> disposePlayer(int playerId) => _api.disposePlayer(playerId);

  @override
  Future<void> configureCache(int maxBytes) => _api.configureCache(maxBytes);

  @override
  Future<int> cacheBytes() => _api.cacheBytes();

  @override
  Future<void> clearCache() => _api.clearCache();

  @override
  Future<void> preload(pigeon.HostMediaSource source) => _api.preload(source);

  @override
  Future<void> setPictureInPictureAutomatic(int playerId, bool enabled) =>
      _api.setPictureInPictureAutomatic(playerId, enabled);

  @override
  Future<void> enterPictureInPicture(
    int playerId,
    int? aspectWidth,
    int? aspectHeight,
    pigeon.HostPipSourceRect? sourceRect,
  ) => _api.enterPictureInPicture(
    playerId,
    aspectWidth,
    aspectHeight,
    sourceRect,
  );

  @override
  Future<void> exitPictureInPicture(int playerId) =>
      _api.exitPictureInPicture(playerId);

  @override
  Future<void> setBackgroundAudioEnabled(int playerId, bool enabled) =>
      _api.setBackgroundAudioEnabled(playerId, enabled);

  @override
  Future<void> setNowPlaying(
    int playerId,
    String? title,
    String? artist,
    String? album,
    String? artworkUri,
  ) => _api.setNowPlaying(playerId, title, artist, album, artworkUri);

  @override
  Stream<pigeon.HostPlayerEvent> events() => _eventStream ?? pigeon.events();
}
