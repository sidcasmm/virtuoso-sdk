import 'drm.dart';

/// One entry in a [Playlist]. Played via [PlayerController.load] + [play].
final class PlaylistItem {
  const PlaylistItem({
    required this.uri,
    this.headers,
    this.drm,
    this.id,
    this.title,
  });

  final Uri uri;
  final Map<String, String>? headers;
  final DrmConfiguration? drm;
  final String? id;
  final String? title;

  @override
  bool operator ==(Object other) =>
      other is PlaylistItem &&
      uri == other.uri &&
      id == other.id &&
      title == other.title &&
      drm == other.drm &&
      _sameHeaders(headers, other.headers);

  @override
  int get hashCode =>
      Object.hash(uri, id, title, drm, Object.hashAll(_headerPairs));

  Iterable<String> get _headerPairs {
    if (headers == null) {
      return const [];
    }
    final keys = headers!.keys.toList()..sort();
    return keys.map((key) => '$key=${headers![key]}');
  }

  static bool _sameHeaders(Map<String, String>? a, Map<String, String>? b) {
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
}

/// Current queue and which item is loaded, if any.
final class Playlist {
  const Playlist({required this.items, this.currentIndex});

  static const empty = Playlist(items: []);

  final List<PlaylistItem> items;
  final int? currentIndex;

  bool get hasPrevious => currentIndex != null && currentIndex! > 0;

  bool get hasNext => currentIndex != null && currentIndex! + 1 < items.length;

  @override
  bool operator ==(Object other) =>
      other is Playlist &&
      currentIndex == other.currentIndex &&
      _sameItems(items, other.items);

  @override
  int get hashCode => Object.hash(Object.hashAll(items), currentIndex);

  static bool _sameItems(List<PlaylistItem> a, List<PlaylistItem> b) {
    if (a.length != b.length) {
      return false;
    }
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) {
        return false;
      }
    }
    return true;
  }
}
