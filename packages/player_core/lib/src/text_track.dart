/// One in-stream text rendition (HLS/DASH/WebVTT/TTML captions).
final class TextTrack {
  const TextTrack({required this.id, this.language, this.label, this.codec});

  /// Opaque id for [PlayerController.setTextTrack].
  final String id;

  /// BCP-47 language tag, if the engine reports it.
  final String? language;
  final String? label;
  final String? codec;

  @override
  bool operator ==(Object other) =>
      other is TextTrack &&
      id == other.id &&
      language == other.language &&
      label == other.label &&
      codec == other.codec;

  @override
  int get hashCode => Object.hash(id, language, label, codec);
}

/// Available text tracks and whether captions are Off (no override).
final class TextTrackList {
  const TextTrackList({
    required this.tracks,
    required this.isAuto,
    this.activeId,
  });

  static const empty = TextTrackList(tracks: [], isAuto: true);

  final List<TextTrack> tracks;

  /// `true` = Off (default after load).
  final bool isAuto;
  final String? activeId;

  @override
  bool operator ==(Object other) =>
      other is TextTrackList &&
      isAuto == other.isAuto &&
      activeId == other.activeId &&
      _sameTracks(tracks, other.tracks);

  @override
  int get hashCode => Object.hash(Object.hashAll(tracks), isAuto, activeId);

  static bool _sameTracks(List<TextTrack> a, List<TextTrack> b) {
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

/// Currently visible caption text. The app paints this over [PlayerView].
final class SubtitleCue {
  const SubtitleCue({required this.text});

  final String text;

  @override
  bool operator ==(Object other) => other is SubtitleCue && text == other.text;

  @override
  int get hashCode => text.hashCode;
}
