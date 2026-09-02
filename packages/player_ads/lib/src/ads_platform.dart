import 'pigeons/ads_api.g.dart' as pigeon;

/// Host operations [AdsClient] talks to. Production uses Pigeon; tests inject a fake.
abstract class AdsPlatform {
  Future<void> initialize();
  Future<void> bind(int playerId, String tag);
  Future<void> clear(int playerId);
  Future<void> skip(int playerId);
  Stream<pigeon.HostAdEvent> events();
}

class PigeonAdsPlatform implements AdsPlatform {
  PigeonAdsPlatform({pigeon.AdsHostApi? api, this._eventStream})
    : _api = api ?? pigeon.AdsHostApi();

  final pigeon.AdsHostApi _api;
  final Stream<pigeon.HostAdEvent>? _eventStream;

  @override
  Future<void> initialize() => _api.initialize();

  @override
  Future<void> bind(int playerId, String tag) => _api.bind(playerId, tag);

  @override
  Future<void> clear(int playerId) => _api.clear(playerId);

  @override
  Future<void> skip(int playerId) => _api.skip(playerId);

  @override
  Stream<pigeon.HostAdEvent> events() => _eventStream ?? pigeon.events();
}
