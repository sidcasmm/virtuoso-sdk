import 'dart:async';

import 'package:flutter/services.dart';
import 'package:player_core/player_core.dart';

import 'download_platform.dart';
import 'pigeons/download_api.g.dart' as pigeon;

enum DownloadState { queued, downloading, paused, completed, failed, removing }

final class DownloadRequest {
  const DownloadRequest({
    required this.uri,
    this.headers,
    this.drm,
    this.id,
    this.title,
    this.tracks,
  });

  final Uri uri;
  final Map<String, String>? headers;
  final DrmConfiguration? drm;
  final String? id;
  final String? title;
  final DownloadTracks? tracks;
}

/// Which renditions to pin. Null fields keep engine defaults (highest
/// video, default audio, no captions).
final class DownloadTracks {
  const DownloadTracks({
    this.maxHeight,
    this.maxBitrate,
    this.audioLanguage,
    this.textLanguage,
  });

  /// Cap video height in pixels (e.g. 720). Null = highest available.
  final int? maxHeight;

  /// Cap video bitrate in bits/s. Null = no cap.
  final int? maxBitrate;

  /// BCP-47 audio language to pin. Null = engine default.
  final String? audioLanguage;

  /// BCP-47 caption language to include. Null = no captions downloaded.
  final String? textLanguage;
}

final class DownloadItem {
  const DownloadItem({
    required this.id,
    required this.uri,
    required this.state,
    required this.progress,
    required this.bytesDownloaded,
    this.title,
    this.bytesTotal,
    this.error,
    this.playbackUri,
  });

  final String id;
  final Uri uri;
  final String? title;
  final DownloadState state;
  final double progress;
  final int bytesDownloaded;
  final int? bytesTotal;
  final PlayerError? error;
  final Uri? playbackUri;

  static Uri playbackUriFor(String id) =>
      Uri(scheme: 'player-offline', path: id);

  @override
  bool operator ==(Object other) =>
      other is DownloadItem &&
      other.id == id &&
      other.uri == uri &&
      other.title == title &&
      other.state == state &&
      other.progress == progress &&
      other.bytesDownloaded == bytesDownloaded &&
      other.bytesTotal == bytesTotal &&
      other.playbackUri == playbackUri;

  @override
  int get hashCode => Object.hash(
    id,
    uri,
    title,
    state,
    progress,
    bytesDownloaded,
    bytesTotal,
    playbackUri,
  );
}

final class DownloadClient {
  DownloadClient({DownloadPlatform? platform})
    : _platform = platform ?? PigeonDownloadPlatform() {
    _ready = _initialize();
  }

  final DownloadPlatform _platform;

  late final Future<void> _ready;
  StreamSubscription<pigeon.HostDownloadEvent>? _eventsSub;
  var _disposed = false;
  var _items = const <DownloadItem>[];
  var _bytesUsed = 0;

  final _itemLists = StreamController<List<DownloadItem>>.broadcast();
  final _bytesUsedChanges = StreamController<int>.broadcast();

  List<DownloadItem> get currentItems => _items;
  int get bytesUsed => _bytesUsed;

  Stream<List<DownloadItem>> get items => _replay(_items, _itemLists.stream);
  Stream<int> get bytesUsedChanges =>
      _replay(_bytesUsed, _bytesUsedChanges.stream);

  Future<void> get initialized => _ready;

  Future<String> enqueue(DownloadRequest request) async {
    _ensureNotDisposed();
    _ensureNetwork(request.uri, request.headers);
    _validateDrm(request.drm);
    _validateTracks(request.tracks);
    PlayerLicense.ensure(PaidFeature.downloads);
    await _ready;
    final id = (request.id == null || request.id!.isEmpty)
        ? request.uri.toString()
        : request.id!;
    final tracks = request.tracks;
    return _invoke(
      () => _platform.enqueue(
        pigeon.HostDownloadRequest(
          id: id,
          uri: request.uri.toString(),
          headers: _nonEmptyHeaders(request.headers),
          title: request.title,
          drm: _hostDrm(request.drm),
          maxHeight: tracks?.maxHeight,
          maxBitrate: tracks?.maxBitrate,
          audioLanguage: _nonEmptyLanguage(tracks?.audioLanguage),
          textLanguage: _nonEmptyLanguage(tracks?.textLanguage),
        ),
      ),
    );
  }

  Future<void> pause(String id) async {
    _ensureNotDisposed();
    _ensureId(id);
    await _ready;
    await _invoke(() => _platform.pause(id));
  }

  Future<void> resume(String id) async {
    _ensureNotDisposed();
    _ensureId(id);
    await _ready;
    await _invoke(() => _platform.resume(id));
  }

  Future<void> cancel(String id) async {
    _ensureNotDisposed();
    _ensureId(id);
    await _ready;
    await _invoke(() => _platform.cancel(id));
  }

  Future<void> remove(String id) async {
    _ensureNotDisposed();
    _ensureId(id);
    await _ready;
    await _invoke(() => _platform.remove(id));
  }

  Future<void> removeAll() async {
    _ensureNotDisposed();
    await _ready;
    await _invoke(() => _platform.removeAll());
  }

  /// First completed pin whose source [uri] equals the argument.
  DownloadItem? completedItemFor(Uri uri) {
    for (final item in _items) {
      if (item.state == DownloadState.completed && item.uri == uri) {
        return item;
      }
    }
    return null;
  }

  /// [uri] if nothing is pinned; otherwise `player-offline:<id>`.
  Uri playbackUriPreferringOffline(Uri uri) {
    if (uri.scheme == 'player-offline') {
      return uri;
    }
    final item = completedItemFor(uri);
    if (item == null) {
      return uri;
    }
    return item.playbackUri ?? DownloadItem.playbackUriFor(item.id);
  }

  /// Rewrite a queue entry to the pin. Drops headers and DRM — those
  /// belong to the download, not a second network `load`.
  PlaylistItem preferringOffline(PlaylistItem item) {
    final completed = completedItemFor(item.uri);
    if (completed == null) {
      return item;
    }
    return PlaylistItem(
      uri: completed.playbackUri ?? DownloadItem.playbackUriFor(completed.id),
      id: item.id,
      title: item.title,
    );
  }

  Future<void> play(PlayerController controller, String id) async {
    _ensureId(id);
    PlayerLicense.ensure(PaidFeature.downloads);
    await _ready;
    final item = _itemById(id);
    if (item == null) {
      throw ArgumentError.value(id, 'id', 'unknown download');
    }
    if (item.state != DownloadState.completed) {
      throw StateError('Download is not completed');
    }
    final uri = item.playbackUri ?? DownloadItem.playbackUriFor(id);
    await controller.load(uri);
  }

  /// Load the completed pin for [uri] when one exists; otherwise stream.
  Future<void> loadPreferringOffline(
    PlayerController controller,
    Uri uri, {
    Map<String, String>? headers,
    DrmConfiguration? drm,
  }) async {
    _ensureNotDisposed();
    PlayerLicense.ensure(PaidFeature.downloads);
    await _ready;
    if (uri.scheme == 'player-offline') {
      await controller.load(uri);
      return;
    }
    final item = completedItemFor(uri);
    if (item != null) {
      await play(controller, item.id);
      return;
    }
    await controller.load(uri, headers: headers, drm: drm);
  }

  Future<void> dispose() async {
    if (_disposed) {
      return;
    }
    _disposed = true;
    await _eventsSub?.cancel();
    await _itemLists.close();
    await _bytesUsedChanges.close();
  }

  Future<void> _initialize() async {
    try {
      final items = await _platform.initialize();
      _replaceItems(items);
      _eventsSub = _platform.events().listen(_onEvent);
      _bytesUsed = await _platform.bytesUsed();
    } catch (_) {
      if (_disposed) {
        return;
      }
    }
  }

  void _onEvent(pigeon.HostDownloadEvent event) {
    if (_disposed) {
      return;
    }
    switch (event.kind) {
      case pigeon.HostDownloadEventKind.items:
        _replaceItems(event.items ?? const []);
      case pigeon.HostDownloadEventKind.bytesUsed:
        final used = event.bytesUsed;
        if (used != null) {
          _setBytesUsed(used);
        }
    }
  }

  void _replaceItems(List<pigeon.HostDownloadItem> host) {
    _items = [for (final item in host) _mapItem(item)];
    if (!_itemLists.isClosed) {
      _itemLists.add(_items);
    }
  }

  void _setBytesUsed(int used) {
    if (_bytesUsed == used) {
      return;
    }
    _bytesUsed = used;
    if (!_bytesUsedChanges.isClosed) {
      _bytesUsedChanges.add(used);
    }
  }

  void _ensureNotDisposed() {
    if (_disposed) {
      throw StateError('DownloadClient has been disposed');
    }
  }

  void _ensureId(String id) {
    if (id.isEmpty) {
      throw ArgumentError.value(id, 'id', 'must not be empty');
    }
  }

  DownloadItem? _itemById(String id) {
    for (final item in _items) {
      if (item.id == id) {
        return item;
      }
    }
    return null;
  }

  void _ensureNetwork(Uri uri, Map<String, String>? headers) {
    if (uri.scheme != 'http' && uri.scheme != 'https') {
      throw ArgumentError.value(
        uri,
        'uri',
        'only http and https URIs can be downloaded',
      );
    }
    if (headers != null && headers.isEmpty) {
      return;
    }
  }

  Future<T> _invoke<T>(Future<T> Function() call) async {
    try {
      return await call();
    } on PlatformException catch (error) {
      if (error.code == 'argument-error') {
        throw ArgumentError(error.message);
      }
      throw StateError(error.message ?? error.code);
    }
  }

  static DownloadItem _mapItem(pigeon.HostDownloadItem item) {
    final state = _mapState(item.state);
    return DownloadItem(
      id: item.id,
      uri: Uri.parse(item.uri),
      title: item.title,
      state: state,
      progress: item.progress,
      bytesDownloaded: item.bytesDownloaded,
      bytesTotal: item.bytesTotal,
      error: item.errorMessage == null
          ? null
          : PlayerError(
              code: _mapError(item.errorCode),
              message: item.errorMessage!,
              isRecoverable:
                  item.errorCode == 'sourceUnreachable' ||
                  item.errorCode == 'timedOut',
            ),
      playbackUri: state == DownloadState.completed
          ? (item.playbackUri == null
                ? DownloadItem.playbackUriFor(item.id)
                : Uri.parse(item.playbackUri!))
          : null,
    );
  }

  static DownloadState _mapState(pigeon.HostDownloadState state) {
    return switch (state) {
      pigeon.HostDownloadState.queued => DownloadState.queued,
      pigeon.HostDownloadState.downloading => DownloadState.downloading,
      pigeon.HostDownloadState.paused => DownloadState.paused,
      pigeon.HostDownloadState.completed => DownloadState.completed,
      pigeon.HostDownloadState.failed => DownloadState.failed,
      pigeon.HostDownloadState.removing => DownloadState.removing,
    };
  }

  static PlayerErrorCode _mapError(String? code) {
    return switch (code) {
      'sourceUnreachable' => PlayerErrorCode.sourceUnreachable,
      'sourceUnsupported' => PlayerErrorCode.sourceUnsupported,
      'decodeFailed' => PlayerErrorCode.decodeFailed,
      'timedOut' => PlayerErrorCode.timedOut,
      'licenseDenied' => PlayerErrorCode.licenseDenied,
      _ => PlayerErrorCode.unknown,
    };
  }

  static pigeon.HostDrmConfiguration? _hostDrm(DrmConfiguration? drm) {
    if (drm == null) {
      return null;
    }
    return pigeon.HostDrmConfiguration(
      scheme: switch (drm.scheme) {
        DrmScheme.widevine => pigeon.HostDrmScheme.widevine,
        DrmScheme.fairPlay => pigeon.HostDrmScheme.fairPlay,
        DrmScheme.clearKey => pigeon.HostDrmScheme.clearKey,
      },
      licenseUrl: drm.licenseUrl?.toString(),
      licenseHeaders: _nonEmptyHeaders(drm.licenseHeaders),
      clearKeys: _nonEmptyHeaders(drm.clearKeys),
      certificate: drm.certificate,
      contentId: drm.contentId,
    );
  }

  static void _validateDrm(DrmConfiguration? drm) {
    if (drm == null) {
      return;
    }
    switch (drm.scheme) {
      case DrmScheme.widevine:
        if (drm.licenseUrl == null) {
          throw ArgumentError.value(
            drm.licenseUrl,
            'licenseUrl',
            'is required for Widevine',
          );
        }
      case DrmScheme.fairPlay:
        if (drm.licenseUrl == null) {
          throw ArgumentError.value(
            drm.licenseUrl,
            'licenseUrl',
            'is required for FairPlay',
          );
        }
        final certificate = drm.certificate;
        if (certificate == null || certificate.isEmpty) {
          throw ArgumentError.value(
            certificate,
            'certificate',
            'is required for FairPlay',
          );
        }
      case DrmScheme.clearKey:
        final keys = drm.clearKeys;
        if ((keys == null || keys.isEmpty) && drm.licenseUrl == null) {
          throw ArgumentError('ClearKey requires clearKeys or licenseUrl');
        }
        if (keys != null) {
          for (final entry in keys.entries) {
            _validateClearKeyHex(entry.key, 'kid');
            _validateClearKeyHex(entry.value, 'key');
          }
        }
    }
  }

  static void _validateTracks(DownloadTracks? tracks) {
    if (tracks == null) {
      return;
    }
    final height = tracks.maxHeight;
    if (height != null && height <= 0) {
      throw ArgumentError.value(height, 'maxHeight', 'must be positive');
    }
    final bitrate = tracks.maxBitrate;
    if (bitrate != null && bitrate <= 0) {
      throw ArgumentError.value(bitrate, 'maxBitrate', 'must be positive');
    }
  }

  static String? _nonEmptyLanguage(String? language) {
    if (language == null || language.trim().isEmpty) {
      return null;
    }
    return language.trim();
  }

  static void _validateClearKeyHex(String value, String name) {
    if (!RegExp(r'^[0-9a-fA-F]{32}$').hasMatch(value)) {
      throw ArgumentError.value(value, name, 'must be 32 hex characters');
    }
  }

  static Map<String, String>? _nonEmptyHeaders(Map<String, String>? headers) {
    if (headers == null || headers.isEmpty) {
      return null;
    }
    return Map<String, String>.from(headers);
  }

  static Stream<T> _replay<T>(T current, Stream<T> inner) async* {
    yield current;
    yield* inner;
  }
}
