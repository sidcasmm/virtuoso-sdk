import 'pigeons/download_api.g.dart' as pigeon;

/// Host operations [DownloadClient] talks to. Production uses Pigeon; tests inject a fake.
abstract class DownloadPlatform {
  Future<List<pigeon.HostDownloadItem>> initialize();
  Future<String> enqueue(pigeon.HostDownloadRequest request);
  Future<void> pause(String id);
  Future<void> resume(String id);
  Future<void> cancel(String id);
  Future<void> remove(String id);
  Future<void> removeAll();
  Future<int> bytesUsed();
  Stream<pigeon.HostDownloadEvent> events();
}

class PigeonDownloadPlatform implements DownloadPlatform {
  PigeonDownloadPlatform({pigeon.DownloadHostApi? api, this._eventStream})
    : _api = api ?? pigeon.DownloadHostApi();

  final pigeon.DownloadHostApi _api;
  final Stream<pigeon.HostDownloadEvent>? _eventStream;

  @override
  Future<List<pigeon.HostDownloadItem>> initialize() => _api.initialize();

  @override
  Future<String> enqueue(pigeon.HostDownloadRequest request) =>
      _api.enqueue(request);

  @override
  Future<void> pause(String id) => _api.pause(id);

  @override
  Future<void> resume(String id) => _api.resume(id);

  @override
  Future<void> cancel(String id) => _api.cancel(id);

  @override
  Future<void> remove(String id) => _api.remove(id);

  @override
  Future<void> removeAll() => _api.removeAll();

  @override
  Future<int> bytesUsed() => _api.bytesUsed();

  @override
  Stream<pigeon.HostDownloadEvent> events() => _eventStream ?? pigeon.events();
}
