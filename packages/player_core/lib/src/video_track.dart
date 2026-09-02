/// One video rendition (HLS/DASH variant or progressive format).
final class VideoTrack {
  const VideoTrack({
    required this.id,
    this.width,
    this.height,
    this.bitrate,
    this.codec,
  });

  /// Opaque id for [PlayerController.setVideoTrack].
  final String id;
  final int? width;
  final int? height;

  /// Bits per second, if the engine reports it.
  final int? bitrate;
  final String? codec;

  @override
  bool operator ==(Object other) =>
      other is VideoTrack &&
      id == other.id &&
      width == other.width &&
      height == other.height &&
      bitrate == other.bitrate &&
      codec == other.codec;

  @override
  int get hashCode => Object.hash(id, width, height, bitrate, codec);
}

/// Available video renditions and whether ABR is on.
final class VideoTrackList {
  const VideoTrackList({
    required this.tracks,
    required this.isAuto,
    this.activeId,
  });

  static const empty = VideoTrackList(tracks: [], isAuto: true);

  final List<VideoTrack> tracks;
  final bool isAuto;
  final String? activeId;

  @override
  bool operator ==(Object other) =>
      other is VideoTrackList &&
      isAuto == other.isAuto &&
      activeId == other.activeId &&
      _sameTracks(tracks, other.tracks);

  @override
  int get hashCode => Object.hash(Object.hashAll(tracks), isAuto, activeId);

  static bool _sameTracks(List<VideoTrack> a, List<VideoTrack> b) {
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
