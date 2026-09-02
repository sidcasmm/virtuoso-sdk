import 'pigeons/cast_api.g.dart' as pigeon;

/// Host operations [CastClient] talks to. Production uses Pigeon; tests inject a fake.
abstract class CastPlatform {
  Future<pigeon.HostCastSessionState> initialize(String receiverAppId);
  Future<void> startDiscovery();
  Future<void> stopDiscovery();
  Future<void> connect(String deviceId);
  Future<void> disconnect();
  Future<void> load(
    String uri,
    int? positionMs,
    String? title,
    String? contentType,
  );
  Future<void> play();
  Future<void> pause();
  Future<void> seek(int positionMs);
  Future<void> setVolume(double volume);
  Future<void> setMute(bool mute);
  Future<void> setPlaybackSpeed(double speed);
  Future<void> setActiveTracks(List<String> trackIds);
  Stream<pigeon.HostCastEvent> events();
}

class PigeonCastPlatform implements CastPlatform {
  PigeonCastPlatform({pigeon.CastHostApi? api, this._eventStream})
    : _api = api ?? pigeon.CastHostApi();

  final pigeon.CastHostApi _api;
  final Stream<pigeon.HostCastEvent>? _eventStream;

  @override
  Future<pigeon.HostCastSessionState> initialize(String receiverAppId) =>
      _api.initialize(receiverAppId);

  @override
  Future<void> startDiscovery() => _api.startDiscovery();

  @override
  Future<void> stopDiscovery() => _api.stopDiscovery();

  @override
  Future<void> connect(String deviceId) => _api.connect(deviceId);

  @override
  Future<void> disconnect() => _api.disconnect();

  @override
  Future<void> load(
    String uri,
    int? positionMs,
    String? title,
    String? contentType,
  ) => _api.load(uri, positionMs, title, contentType);

  @override
  Future<void> play() => _api.play();

  @override
  Future<void> pause() => _api.pause();

  @override
  Future<void> seek(int positionMs) => _api.seek(positionMs);

  @override
  Future<void> setVolume(double volume) => _api.setVolume(volume);

  @override
  Future<void> setMute(bool mute) => _api.setMute(mute);

  @override
  Future<void> setPlaybackSpeed(double speed) => _api.setPlaybackSpeed(speed);

  @override
  Future<void> setActiveTracks(List<String> trackIds) =>
      _api.setActiveTracks(trackIds);

  @override
  Stream<pigeon.HostCastEvent> events() => _eventStream ?? pigeon.events();
}
