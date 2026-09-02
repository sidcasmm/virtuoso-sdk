import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'player_platform.dart';

/// Commercial capabilities that are not in the free player.
enum PaidFeature {
  networkResiliency,
  cache,
  spritesheet,
  chapters,
  skipSegments,
  backgroundAudio,
  pictureInPicture,
  drm,
  analytics,
  cast,
  downloads,
  ads;

  /// Stable id stored in the signed license payload.
  String get id => name;

  static PaidFeature? fromId(String id) {
    for (final feature in values) {
      if (feature.id == id) {
        return feature;
      }
    }
    return null;
  }
}

/// Thrown when Dart calls a paid API without that feature unlocked.
final class PremiumRequiredException implements Exception {
  PremiumRequiredException(this.feature);

  final PaidFeature feature;

  @override
  String toString() {
    return 'PremiumRequiredException: ${feature.name} requires a '
        'Virtuoso Player commercial license';
  }
}

/// Process-wide commercial license. Call [activate] once at app start
/// before creating players. Native code is the source of truth.
final class PlayerLicense {
  PlayerLicense._();

  static final _unlocked = <PaidFeature>{};

  static Set<PaidFeature> get features => Set.unmodifiable(_unlocked);

  static bool allows(PaidFeature feature) => _unlocked.contains(feature);

  static void ensure(PaidFeature feature) {
    if (allows(feature)) {
      return;
    }
    throw PremiumRequiredException(feature);
  }

  /// Verifies [token] on the host (signature + app id + expiry) and
  /// unlocks the listed features for this process.
  static Future<void> activate(String token, {PlayerPlatform? platform}) async {
    final trimmed = token.trim();
    if (trimmed.isEmpty) {
      throw ArgumentError.value(token, 'token', 'must not be empty');
    }
    final host = platform ?? PigeonPlayerPlatform();
    try {
      final info = await host.activateLicense(trimmed);
      _replace(info.features);
    } on PlatformException catch (error) {
      throw StateError(error.message ?? 'Invalid Virtuoso Player license');
    }
  }

  /// Unit tests only. Does not unlock native checks.
  @visibleForTesting
  static void unlockForTest([Iterable<PaidFeature>? features]) {
    _replace((features ?? PaidFeature.values).map((feature) => feature.id));
  }

  /// Unit tests only.
  @visibleForTesting
  static void resetForTest() {
    _unlocked.clear();
  }

  static void _replace(Iterable<String> ids) {
    _unlocked
      ..clear()
      ..addAll(ids.map(PaidFeature.fromId).whereType<PaidFeature>());
  }
}
