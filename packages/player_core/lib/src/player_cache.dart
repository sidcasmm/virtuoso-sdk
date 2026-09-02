import 'package:flutter/services.dart';

import 'player_license.dart';
import 'player_platform.dart';
import 'pigeons/player_api.g.dart' as pigeon;

/// Process-wide HTTP(S) disk cache and preload. Shared by all
/// [PlayerController] instances. Not a cache UI.
final class PlayerCache {
  PlayerCache({PlayerPlatform? platform})
    : _platform = platform ?? PigeonPlayerPlatform();

  final PlayerPlatform _platform;

  /// Default LRU cap when [configure] is called without [maxBytes].
  static const int defaultMaxBytes = 512 * 1024 * 1024;

  /// Enables or resizes the cache. [maxBytes] `0` disables writes.
  Future<void> configure({int maxBytes = defaultMaxBytes}) async {
    PlayerLicense.ensure(PaidFeature.cache);
    if (maxBytes < 0) {
      throw ArgumentError.value(maxBytes, 'maxBytes', 'must be >= 0');
    }
    await _platform.configureCache(maxBytes);
  }

  Future<void> clear() {
    PlayerLicense.ensure(PaidFeature.cache);
    return _platform.clearCache();
  }

  Future<int> get cachedBytes {
    PlayerLicense.ensure(PaidFeature.cache);
    return _platform.cacheBytes();
  }

  /// Buffers the start of a network source into the cache. Does not affect
  /// a visible [PlayerController].
  Future<void> preload(Uri uri, {Map<String, String>? headers}) async {
    PlayerLicense.ensure(PaidFeature.cache);
    final trimmed = _nonEmptyHeaders(headers);
    if (trimmed != null && uri.scheme != 'http' && uri.scheme != 'https') {
      throw ArgumentError.value(
        uri,
        'uri',
        'headers are only supported for http and https URIs',
      );
    }
    if (uri.scheme != 'http' && uri.scheme != 'https') {
      throw ArgumentError.value(
        uri,
        'uri',
        'preload only supports http and https URIs',
      );
    }
    try {
      await _platform.preload(
        pigeon.HostMediaSource(
          kind: pigeon.HostSourceKind.network,
          location: uri.toString(),
          headers: trimmed,
        ),
      );
    } on PlatformException catch (error) {
      throw StateError(error.message ?? 'preload failed');
    }
  }

  Map<String, String>? _nonEmptyHeaders(Map<String, String>? headers) {
    if (headers == null || headers.isEmpty) {
      return null;
    }
    return Map<String, String>.from(headers);
  }
}
