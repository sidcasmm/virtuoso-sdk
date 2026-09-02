import 'dart:convert';

import 'package:player_core/player_core.dart';

typedef AnalyticsEventCallback = void Function(AnalyticsEvent event);
typedef AnalyticsViewEndCallback = void Function(AnalyticsViewReport report);
typedef DeviceDetailsProvider = Future<DeviceDetails> Function();
typedef NetworkDetailsProvider = Future<NetworkDetails> Function();

final class AnalyticsConfig {
  const AnalyticsConfig({this.interval = const Duration(seconds: 1)});

  factory AnalyticsConfig.fromJson(Map<String, Object?> json) {
    final ms = json['intervalMs'];
    final interval = ms is num
        ? Duration(milliseconds: ms.round())
        : const Duration(seconds: 1);
    if (interval < const Duration(milliseconds: 200)) {
      throw ArgumentError.value(interval, 'interval', 'must be >= 200ms');
    }
    return AnalyticsConfig(interval: interval);
  }

  final Duration interval;

  Map<String, Object?> toJson() => {'intervalMs': interval.inMilliseconds};
}

final class VideoDetails {
  const VideoDetails({
    this.id,
    this.title,
    this.series,
    this.producer,
    this.language,
    this.sourceType,
    this.sourceUrl,
    this.streamType,
  });

  final String? id;
  final String? title;
  final String? series;
  final String? producer;
  final String? language;
  final String? sourceType;
  final String? sourceUrl;
  final String? streamType;

  Map<String, Object?> toJson() => {
    'id': id,
    'title': title,
    'series': series,
    'producer': producer,
    'language': language,
    'sourceType': sourceType,
    'sourceUrl': sourceUrl,
    'streamType': streamType,
  };
}

final class PlayerDetails {
  const PlayerDetails({
    required this.playerVersion,
    this.playerWidth,
    this.playerHeight,
    this.autoplay,
    this.preload,
  });

  final String playerVersion;
  final int? playerWidth;
  final int? playerHeight;
  final bool? autoplay;
  final bool? preload;

  Map<String, Object?> toJson() => {
    'playerVersion': playerVersion,
    'playerWidth': playerWidth,
    'playerHeight': playerHeight,
    'autoplay': autoplay,
    'preload': preload,
  };
}

final class DeviceDetails {
  const DeviceDetails({
    this.os,
    this.osVersion,
    this.manufacturer,
    this.model,
    this.name,
    this.type,
  });

  final String? os;
  final String? osVersion;
  final String? manufacturer;
  final String? model;
  final String? name;
  final String? type;

  Map<String, Object?> toJson() => {
    'os': os,
    'osVersion': osVersion,
    'manufacturer': manufacturer,
    'model': model,
    'name': name,
    'type': type,
  };
}

final class NetworkDetails {
  const NetworkDetails({this.connectionType, this.connectionSpeed});

  final String? connectionType;
  final int? connectionSpeed;

  Map<String, Object?> toJson() => {
    'connectionType': connectionType,
    'connectionSpeed': connectionSpeed,
  };
}

enum AnalyticsEventType {
  viewstart,
  play,
  playing,
  pulse,
  pause,
  rebufferstart,
  rebufferend,
  seeking,
  seeked,
  qualityChange,
  error,
  ended,
  viewend,
}

final class QualityChangePayload {
  const QualityChangePayload({
    required this.cause,
    this.fromTrackId,
    this.toTrackId,
    this.fromWidth,
    this.fromHeight,
    this.fromBitrate,
    this.toWidth,
    this.toHeight,
    this.toBitrate,
  });

  final String cause;
  final String? fromTrackId;
  final String? toTrackId;
  final int? fromWidth;
  final int? fromHeight;
  final int? fromBitrate;
  final int? toWidth;
  final int? toHeight;
  final int? toBitrate;

  Map<String, Object?> toJson() => {
    'cause': cause,
    'fromTrackId': fromTrackId,
    'toTrackId': toTrackId,
    'fromWidth': fromWidth,
    'fromHeight': fromHeight,
    'fromBitrate': fromBitrate,
    'toWidth': toWidth,
    'toHeight': toHeight,
    'toBitrate': toBitrate,
  };
}

final class AnalyticsEvent {
  const AnalyticsEvent({
    required this.type,
    required this.viewId,
    required this.viewerId,
    required this.playhead,
    required this.wallclock,
    this.device,
    this.network,
    this.qualityChange,
    this.error,
    this.report,
  });

  final AnalyticsEventType type;
  final String viewId;
  final String viewerId;
  final Duration playhead;
  final DateTime wallclock;
  final DeviceDetails? device;
  final NetworkDetails? network;
  final QualityChangePayload? qualityChange;
  final PlayerError? error;
  final AnalyticsViewReport? report;

  Map<String, Object?> toJson() => {
    'type': type.name,
    'viewId': viewId,
    'viewerId': viewerId,
    'playheadMs': playhead.inMilliseconds,
    'wallclockMs': wallclock.millisecondsSinceEpoch,
    if (device != null) 'device': device!.toJson(),
    if (network != null) 'network': network!.toJson(),
    if (qualityChange != null) 'qualityChange': qualityChange!.toJson(),
    if (error != null)
      'error': {
        'code': error!.code.name,
        'message': error!.message,
        'nativeDetails': error!.nativeDetails,
        'isRecoverable': error!.isRecoverable,
      },
    if (report != null) 'report': report!.toJson(),
  };
}

final class VideoReport {
  const VideoReport({
    required this.details,
    this.duration,
    this.width,
    this.height,
  });

  final VideoDetails details;
  final Duration? duration;
  final int? width;
  final int? height;

  Map<String, Object?> toJson() => {
    ...details.toJson(),
    'durationMs': duration?.inMilliseconds,
    'width': width,
    'height': height,
  };
}

final class ViewReport {
  const ViewReport({
    required this.viewId,
    required this.viewerId,
    required this.startedAt,
    required this.endedAt,
    required this.seekCount,
    required this.seeked,
    required this.usedFullscreen,
    required this.exitedBeforeVideoPlays,
    required this.videoStartupFailed,
    this.errorCode,
    this.errorMessage,
    this.errorNativeDetails,
  });

  final String viewId;
  final String viewerId;
  final DateTime startedAt;
  final DateTime endedAt;
  final int seekCount;
  final Duration seeked;
  final bool usedFullscreen;
  final bool exitedBeforeVideoPlays;
  final bool videoStartupFailed;
  final String? errorCode;
  final String? errorMessage;
  final String? errorNativeDetails;

  Map<String, Object?> toJson() => {
    'viewId': viewId,
    'viewerId': viewerId,
    'startedAt': startedAt.toUtc().toIso8601String(),
    'endedAt': endedAt.toUtc().toIso8601String(),
    'seekCount': seekCount,
    'seekedMs': seeked.inMilliseconds,
    'usedFullscreen': usedFullscreen,
    'exitedBeforeVideoPlays': exitedBeforeVideoPlays,
    'videoStartupFailed': videoStartupFailed,
    'errorCode': errorCode,
    'errorMessage': errorMessage,
    'errorNativeDetails': errorNativeDetails,
  };
}

final class StabilityQoe {
  const StabilityQoe({
    required this.bufferRatio,
    required this.bufferFrequency,
    required this.bufferCount,
    required this.bufferFill,
    required this.droppedFrameCount,
  });

  final double bufferRatio;
  final double bufferFrequency;
  final int bufferCount;
  final Duration bufferFill;
  final int droppedFrameCount;

  Map<String, Object?> toJson() => {
    'bufferRatio': bufferRatio,
    'bufferFrequency': bufferFrequency,
    'bufferCount': bufferCount,
    'bufferFillMs': bufferFill.inMilliseconds,
    'droppedFrameCount': droppedFrameCount,
  };
}

final class RenderQualityQoe {
  const RenderQualityQoe({
    required this.upscalePercentage,
    required this.maxUpscalePercentage,
    required this.downscalePercentage,
    required this.maxDownscalePercentage,
    this.averageBitrate,
  });

  final double upscalePercentage;
  final double maxUpscalePercentage;
  final double downscalePercentage;
  final double maxDownscalePercentage;
  final double? averageBitrate;

  Map<String, Object?> toJson() => {
    'upscalePercentage': upscalePercentage,
    'maxUpscalePercentage': maxUpscalePercentage,
    'downscalePercentage': downscalePercentage,
    'maxDownscalePercentage': maxDownscalePercentage,
    'averageBitrate': averageBitrate,
  };
}

final class StartupQoe {
  const StartupQoe({
    this.videoStartupTime,
    this.playerInitializationTime,
    this.liveStreamLatency,
    this.jumpLatency,
  });

  final Duration? videoStartupTime;
  final Duration? playerInitializationTime;
  final Duration? liveStreamLatency;
  final Duration? jumpLatency;

  Map<String, Object?> toJson() => {
    'videoStartupTimeMs': videoStartupTime?.inMilliseconds,
    'playerInitializationTimeMs': playerInitializationTime?.inMilliseconds,
    'liveStreamLatencyMs': liveStreamLatency?.inMilliseconds,
    'jumpLatencyMs': jumpLatency?.inMilliseconds,
  };
}

final class QoeReport {
  const QoeReport({
    required this.stability,
    required this.renderQuality,
    required this.startup,
  });

  final StabilityQoe stability;
  final RenderQualityQoe renderQuality;
  final StartupQoe startup;

  Map<String, Object?> toJson() => {
    'stability': stability.toJson(),
    'renderQuality': renderQuality.toJson(),
    'startup': startup.toJson(),
  };
}

final class AnalyticsViewReport {
  const AnalyticsViewReport({
    required this.schemaVersion,
    required this.video,
    required this.view,
    required this.player,
    required this.device,
    required this.network,
    required this.qoe,
  });

  final int schemaVersion;
  final VideoReport video;
  final ViewReport view;
  final PlayerDetails player;
  final DeviceDetails device;
  final NetworkDetails network;
  final QoeReport qoe;

  Map<String, Object?> toJson() => {
    'schemaVersion': schemaVersion,
    'video': video.toJson(),
    'view': view.toJson(),
    'player': player.toJson(),
    'device': device.toJson(),
    'network': network.toJson(),
    'qoe': qoe.toJson(),
  };

  String toJsonString() => jsonEncode(toJson());
}
