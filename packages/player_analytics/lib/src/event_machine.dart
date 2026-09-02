import 'models.dart';

/// Closed playback-event FSM. Pulse / qualityChange / view* do not become
/// [current]. Illegal candidates are rejected.
final class AnalyticsEventMachine {
  AnalyticsEventType? current;
  var seekFromPause = false;

  static const allowed = <AnalyticsEventType?, Set<AnalyticsEventType>>{
    null: {AnalyticsEventType.play, AnalyticsEventType.error},
    AnalyticsEventType.play: {
      AnalyticsEventType.playing,
      AnalyticsEventType.ended,
      AnalyticsEventType.pause,
      AnalyticsEventType.qualityChange,
      AnalyticsEventType.seeking,
      AnalyticsEventType.error,
    },
    AnalyticsEventType.playing: {
      AnalyticsEventType.rebufferstart,
      AnalyticsEventType.pause,
      AnalyticsEventType.ended,
      AnalyticsEventType.seeking,
      AnalyticsEventType.qualityChange,
      AnalyticsEventType.error,
    },
    AnalyticsEventType.rebufferstart: {
      AnalyticsEventType.rebufferend,
      AnalyticsEventType.error,
      AnalyticsEventType.qualityChange,
    },
    AnalyticsEventType.rebufferend: {
      AnalyticsEventType.pause,
      AnalyticsEventType.seeking,
      AnalyticsEventType.playing,
      AnalyticsEventType.ended,
      AnalyticsEventType.error,
      AnalyticsEventType.qualityChange,
    },
    AnalyticsEventType.pause: {
      AnalyticsEventType.seeking,
      AnalyticsEventType.play,
      AnalyticsEventType.ended,
      AnalyticsEventType.error,
      AnalyticsEventType.qualityChange,
    },
    AnalyticsEventType.seeked: {
      AnalyticsEventType.play,
      AnalyticsEventType.ended,
      AnalyticsEventType.error,
      AnalyticsEventType.qualityChange,
      AnalyticsEventType.playing,
      AnalyticsEventType.seeking,
    },
    AnalyticsEventType.seeking: {
      AnalyticsEventType.seeked,
      AnalyticsEventType.ended,
      AnalyticsEventType.error,
      AnalyticsEventType.qualityChange,
    },
    AnalyticsEventType.ended: {
      AnalyticsEventType.play,
      AnalyticsEventType.pause,
      AnalyticsEventType.error,
      AnalyticsEventType.qualityChange,
    },
    AnalyticsEventType.error: {
      AnalyticsEventType.playing,
      AnalyticsEventType.play,
      AnalyticsEventType.pause,
      AnalyticsEventType.rebufferend,
    },
  };

  bool allows(AnalyticsEventType type) {
    if (type == AnalyticsEventType.pulse) {
      return current == AnalyticsEventType.playing;
    }
    if (type == AnalyticsEventType.viewstart ||
        type == AnalyticsEventType.viewend) {
      return true;
    }
    return allowed[current]?.contains(type) ?? false;
  }

  void enter(AnalyticsEventType type) {
    if (type == AnalyticsEventType.pulse ||
        type == AnalyticsEventType.qualityChange ||
        type == AnalyticsEventType.viewstart ||
        type == AnalyticsEventType.viewend) {
      return;
    }
    if (type == AnalyticsEventType.seeking) {
      seekFromPause = current == AnalyticsEventType.pause;
    }
    current = type;
  }
}
