import 'buffered_range.dart';
import 'playback_state.dart';
import 'player_error.dart';

/// Point-in-time snapshot. Safe to read synchronously.
final class PlayerSnapshot {
  const PlayerSnapshot({
    required this.playbackState,
    required this.position,
    required this.buffered,
    this.duration,
    this.error,
  });

  static const initial = PlayerSnapshot(
    playbackState: PlaybackState.idle,
    position: Duration.zero,
    buffered: [],
  );

  final PlaybackState playbackState;
  final Duration position;
  final Duration? duration;
  final List<BufferedRange> buffered;
  final PlayerError? error;

  PlayerSnapshot copyWith({
    PlaybackState? playbackState,
    Duration? position,
    Duration? duration,
    List<BufferedRange>? buffered,
    PlayerError? error,
    bool clearError = false,
    bool clearDuration = false,
  }) {
    return PlayerSnapshot(
      playbackState: playbackState ?? this.playbackState,
      position: position ?? this.position,
      duration: clearDuration ? null : (duration ?? this.duration),
      buffered: buffered ?? this.buffered,
      error: clearError ? null : (error ?? this.error),
    );
  }
}
