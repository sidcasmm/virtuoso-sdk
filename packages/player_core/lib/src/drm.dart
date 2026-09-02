import 'dart:typed_data';

/// CDM used for a protected [DrmConfiguration].
enum DrmScheme { widevine, fairPlay, clearKey }

/// License / key config for one [PlayerController.load].
final class DrmConfiguration {
  const DrmConfiguration({
    required this.scheme,
    this.licenseUrl,
    this.licenseHeaders,
    this.clearKeys,
    this.certificate,
    this.contentId,
  });

  final DrmScheme scheme;
  final Uri? licenseUrl;
  final Map<String, String>? licenseHeaders;
  final Map<String, String>? clearKeys;
  final Uint8List? certificate;
  final String? contentId;

  @override
  bool operator ==(Object other) =>
      other is DrmConfiguration &&
      scheme == other.scheme &&
      licenseUrl == other.licenseUrl &&
      contentId == other.contentId &&
      _sameBytes(certificate, other.certificate) &&
      _sameStringMap(licenseHeaders, other.licenseHeaders) &&
      _sameStringMap(clearKeys, other.clearKeys);

  @override
  int get hashCode => Object.hash(
    scheme,
    licenseUrl,
    contentId,
    Object.hashAll(certificate ?? const []),
    Object.hashAll(_pairs(licenseHeaders)),
    Object.hashAll(_pairs(clearKeys)),
  );

  static bool _sameBytes(Uint8List? a, Uint8List? b) {
    if (identical(a, b)) {
      return true;
    }
    if (a == null || b == null || a.length != b.length) {
      return a == b;
    }
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) {
        return false;
      }
    }
    return true;
  }

  static bool _sameStringMap(Map<String, String>? a, Map<String, String>? b) {
    if (identical(a, b)) {
      return true;
    }
    if (a == null || b == null || a.length != b.length) {
      return a == b;
    }
    for (final entry in a.entries) {
      if (b[entry.key] != entry.value) {
        return false;
      }
    }
    return true;
  }

  static Iterable<String> _pairs(Map<String, String>? map) {
    if (map == null) {
      return const [];
    }
    final keys = map.keys.toList()..sort();
    return keys.map((key) => '$key=${map[key]}');
  }
}
