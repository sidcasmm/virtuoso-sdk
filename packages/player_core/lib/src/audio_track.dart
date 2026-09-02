/// One audio rendition (HLS/DASH language track or progressive audio).
final class AudioTrack {
  const AudioTrack({
    required this.id,
    this.language,
    this.label,
    this.channels,
    this.codec,
  });

  /// Opaque id for [PlayerController.setAudioTrack].
  final String id;

  /// BCP-47 language tag, if the engine reports it.
  final String? language;
  final String? label;
  final int? channels;
  final String? codec;

  @override
  bool operator ==(Object other) =>
      other is AudioTrack &&
      id == other.id &&
      language == other.language &&
      label == other.label &&
      channels == other.channels &&
      codec == other.codec;

  @override
  int get hashCode => Object.hash(id, language, label, channels, codec);
}

/// Available audio renditions and whether the engine default is on.
final class AudioTrackList {
  const AudioTrackList({
    required this.tracks,
    required this.isAuto,
    this.activeId,
  });

  static const empty = AudioTrackList(tracks: [], isAuto: true);

  final List<AudioTrack> tracks;
  final bool isAuto;
  final String? activeId;

  @override
  bool operator ==(Object other) =>
      other is AudioTrackList &&
      isAuto == other.isAuto &&
      activeId == other.activeId &&
      _sameTracks(tracks, other.tracks);

  @override
  int get hashCode => Object.hash(Object.hashAll(tracks), isAuto, activeId);

  static bool _sameTracks(List<AudioTrack> a, List<AudioTrack> b) {
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
