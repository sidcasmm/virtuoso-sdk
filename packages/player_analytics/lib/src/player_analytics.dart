// Initializing formals would rename public attach() arguments.
// ignore_for_file: prefer_initializing_formals

import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:player_core/player_core.dart';

import 'device_network.dart';
import 'event_machine.dart';
import 'models.dart';

final class PlayerAnalytics {
  PlayerAnalytics.attach(
    PlayerController controller, {
    AnalyticsConfig config = const AnalyticsConfig(),
    VideoDetails video = const VideoDetails(),
    String? viewerId,
    required AnalyticsEventCallback onEvent,
    AnalyticsViewEndCallback? onViewEnd,
    @visibleForTesting DeviceDetailsProvider? deviceDetailsProvider,
    @visibleForTesting NetworkDetailsProvider? networkDetailsProvider,
    @visibleForTesting DateTime Function()? now,
    @visibleForTesting
    Timer Function(Duration period, void Function() onTick)? pulseTimer,
  }) : _controller = controller,
       _config = config,
       _video = video,
       _onEvent = onEvent,
       _onViewEnd = onViewEnd,
       _deviceProvider = deviceDetailsProvider ?? collectDeviceDetails,
       _networkProvider = networkDetailsProvider ?? collectNetworkDetails,
       _now = now ?? DateTime.now,
       _pulseTimer = pulseTimer ?? _periodicPulse,
       viewId = _uuidV4(),
       viewerId = viewerId ?? _uuidV4() {
    PlayerLicense.ensure(PaidFeature.analytics);
    if (controller.snapshot.playbackState == PlaybackState.disposed) {
      throw StateError('PlayerController has been disposed');
    }
    if (config.interval < const Duration(milliseconds: 200)) {
      throw ArgumentError.value(
        config.interval,
        'interval',
        'must be >= 200ms',
      );
    }
    _attachedAt = _now();
    if (_isReadyLike(controller.snapshot.playbackState)) {
      _playerReadyAt = _attachedAt;
    }
    _lastPosition = controller.snapshot.position;
    unawaited(_start());
  }

  final PlayerController _controller;
  final AnalyticsConfig _config;
  VideoDetails _video;
  final AnalyticsEventCallback _onEvent;
  final AnalyticsViewEndCallback? _onViewEnd;
  final DeviceDetailsProvider _deviceProvider;
  final NetworkDetailsProvider _networkProvider;
  final DateTime Function() _now;
  final Timer Function(Duration period, void Function() onTick) _pulseTimer;

  final String viewId;
  final String viewerId;

  final _machine = AnalyticsEventMachine();
  final _subs = <StreamSubscription<Object?>>[];

  var _attached = true;
  var _viewEnded = false;
  var _seenVideoTracks = false;
  var _usedFullscreen = false;
  var _playAttempted = false;
  var _didPlay = false;
  var _seekCount = 0;
  var _seeked = Duration.zero;
  Duration? _seekFrom;
  var _watchTime = Duration.zero;
  var _rebufferTime = Duration.zero;
  var _rebufferCount = 0;
  DateTime? _segmentStarted;
  AnalyticsEventType? _segmentKind;
  DateTime? _playAttemptAt;
  DateTime? _firstPlayingAt;
  DateTime? _playerReadyAt;
  DateTime? _attachedAt;
  DateTime? _jumpStartedAt;
  final _jumpLatencies = <Duration>[];
  final _liveOffsets = <Duration>[];
  final _bufferAhead = <Duration>[];
  var _upscaleSum = 0.0;
  var _downscaleSum = 0.0;
  var _maxUpscale = 0.0;
  var _maxDownscale = 0.0;
  var _renderSamples = 0;
  var _bitrateTimeMs = 0;
  var _bitrateWeighted = 0.0;
  DateTime? _bitrateSince;
  int? _playerWidth;
  int? _playerHeight;
  bool? _autoplay;
  bool? _preload;
  DeviceDetails _device = const DeviceDetails();
  NetworkDetails _network = const NetworkDetails();
  PlayerError? _lastError;
  VideoTrackList _lastTracks = VideoTrackList.empty;
  Duration _lastPosition = Duration.zero;
  Timer? _pulse;

  bool get isAttached => _attached && !_viewEnded;

  Future<void> _start() async {
    _device = await _deviceProvider();
    _network = await _networkProvider();
    if (!_attached || _viewEnded) {
      return;
    }
    _emit(AnalyticsEventType.viewstart, includeDevice: true);
    _listen();
  }

  void _listen() {
    _subs.add(_controller.playbackState.listen(_onPlaybackState));
    _subs.add(_controller.position.listen(_onPosition));
    _subs.add(_controller.buffered.listen((_) => _sampleBufferFill()));
    _subs.add(_controller.errors.listen((error) => _lastError = error));
    _subs.add(_controller.videoTracks.listen(_onVideoTracks));
    _subs.add(_controller.liveOffsets.listen(_onLiveOffset));
  }

  void setVideoDetails(VideoDetails video) => _video = video;

  void setPlayerSize({required int width, required int height}) {
    _playerWidth = width;
    _playerHeight = height;
  }

  void setFullscreen(bool used) {
    if (used) {
      _usedFullscreen = true;
    }
  }

  void setPlayerFlags({bool? autoplay, bool? preload}) {
    _autoplay = autoplay ?? _autoplay;
    _preload = preload ?? _preload;
  }

  Future<void> detach() async {
    if (!_attached) {
      return;
    }
    await _endView();
  }

  void _onPlaybackState(PlaybackState state) {
    if (!_attached || _viewEnded) {
      return;
    }
    _lastPosition = _controller.snapshot.position;
    switch (state) {
      case PlaybackState.disposed:
        unawaited(_endView());
      case PlaybackState.error:
        _lastError ??= _controller.snapshot.error;
        _tryEmit(AnalyticsEventType.error);
      case PlaybackState.completed:
        _tryEmit(AnalyticsEventType.ended);
      case PlaybackState.paused:
        if (_machine.current == AnalyticsEventType.seeking) {
          _completeSeek();
          return;
        }
        _tryEmit(AnalyticsEventType.pause);
      case PlaybackState.playing:
        _onPlaying();
      case PlaybackState.buffering:
        if (_machine.current == AnalyticsEventType.playing) {
          _tryEmit(AnalyticsEventType.rebufferstart);
          return;
        }
        if (_machine.current == AnalyticsEventType.seeking) {
          return;
        }
        _tryEmit(AnalyticsEventType.play);
      case PlaybackState.ready:
        _playerReadyAt ??= _now();
      case PlaybackState.loading:
      case PlaybackState.idle:
        break;
    }
  }

  void _onPlaying() {
    if (_machine.current == AnalyticsEventType.seeking) {
      final fromPause = _machine.seekFromPause;
      _completeSeek();
      if (!fromPause) {
        _tryEmit(AnalyticsEventType.playing);
      }
      return;
    }
    if (_machine.current == AnalyticsEventType.rebufferstart) {
      _tryEmit(AnalyticsEventType.rebufferend);
      _tryEmit(AnalyticsEventType.playing);
      return;
    }
    if (_machine.current != AnalyticsEventType.play) {
      _tryEmit(AnalyticsEventType.play);
    }
    _tryEmit(AnalyticsEventType.playing);
  }

  void _onPosition(Duration position) {
    if (!_attached || _viewEnded) {
      return;
    }
    final delta = (position - _lastPosition).abs();
    final current = _machine.current;
    final canSeek =
        current == AnalyticsEventType.playing ||
        current == AnalyticsEventType.pause ||
        current == AnalyticsEventType.rebufferend ||
        current == AnalyticsEventType.play;
    if (canSeek && delta > const Duration(milliseconds: 750)) {
      _seekFrom = _lastPosition;
      if (_controller.isLive &&
          position > _lastPosition &&
          current == AnalyticsEventType.playing) {
        _jumpStartedAt = _now();
      }
      _tryEmit(AnalyticsEventType.seeking);
    }
    if (_machine.current == AnalyticsEventType.seeking) {
      // Keep updating destination until seeked.
    }
    _lastPosition = position;
    if (_machine.current == AnalyticsEventType.seeking) {
      final state = _controller.snapshot.playbackState;
      if (state == PlaybackState.paused) {
        _completeSeek();
      } else if (state == PlaybackState.playing) {
        _onPlaying();
      }
    }
    _sampleBufferFill();
    _sampleRender();
  }

  void _completeSeek() {
    final from = _seekFrom ?? _lastPosition;
    final to = _controller.snapshot.position;
    _seeked += (to - from).abs();
    _seekCount += 1;
    _tryEmit(AnalyticsEventType.seeked);
    _seekFrom = null;
  }

  void _onVideoTracks(VideoTrackList list) {
    if (!_seenVideoTracks) {
      _seenVideoTracks = list.tracks.isNotEmpty || list.activeId != null;
      _lastTracks = list;
      _restartBitrate();
      return;
    }
    final prev = _activeTrack(_lastTracks);
    final next = _activeTrack(list);
    final changed =
        prev?.id != next?.id ||
        prev?.bitrate != next?.bitrate ||
        prev?.width != next?.width ||
        prev?.height != next?.height ||
        _lastTracks.isAuto != list.isAuto;
    _flushBitrate();
    _lastTracks = list;
    _restartBitrate();
    if (!changed) {
      return;
    }
    _tryEmit(
      AnalyticsEventType.qualityChange,
      quality: QualityChangePayload(
        cause: list.isAuto ? 'auto' : 'manual',
        fromTrackId: prev?.id,
        toTrackId: next?.id,
        fromWidth: prev?.width,
        fromHeight: prev?.height,
        fromBitrate: prev?.bitrate,
        toWidth: next?.width,
        toHeight: next?.height,
        toBitrate: next?.bitrate,
      ),
    );
  }

  void _onLiveOffset(Duration? offset) {
    if (offset == null || _machine.current != AnalyticsEventType.playing) {
      return;
    }
    _liveOffsets.add(offset);
  }

  bool _tryEmit(
    AnalyticsEventType type, {
    QualityChangePayload? quality,
    bool includeDevice = false,
    AnalyticsViewReport? report,
  }) {
    if (!_machine.allows(type)) {
      return false;
    }
    _flushSegment();
    if (type == AnalyticsEventType.play) {
      _playAttempted = true;
      _playAttemptAt ??= _now();
    }
    if (type == AnalyticsEventType.playing) {
      _didPlay = true;
      _firstPlayingAt ??= _now();
      if (_jumpStartedAt != null) {
        _jumpLatencies.add(_now().difference(_jumpStartedAt!));
        _jumpStartedAt = null;
      }
    }
    if (type == AnalyticsEventType.rebufferstart) {
      _rebufferCount += 1;
    }
    _machine.enter(type);
    _startSegment();
    _emit(type, quality: quality, includeDevice: includeDevice, report: report);
    _syncPulse();
    return true;
  }

  void _emit(
    AnalyticsEventType type, {
    QualityChangePayload? quality,
    bool includeDevice = false,
    AnalyticsViewReport? report,
  }) {
    final event = AnalyticsEvent(
      type: type,
      viewId: viewId,
      viewerId: viewerId,
      playhead: _controller.snapshot.position,
      wallclock: _now(),
      device: includeDevice ? _device : null,
      network: includeDevice ? _network : null,
      qualityChange: quality,
      error: type == AnalyticsEventType.error ? _lastError : null,
      report: report,
    );
    _onEvent(event);
    if (type == AnalyticsEventType.viewend && report != null) {
      _onViewEnd?.call(report);
    }
  }

  void _syncPulse() {
    final playing = _machine.current == AnalyticsEventType.playing;
    if (playing && _pulse == null) {
      _pulse = _pulseTimer(_config.interval, _onPulse);
    } else if (!playing) {
      _pulse?.cancel();
      _pulse = null;
    }
  }

  void _onPulse() {
    if (!_machine.allows(AnalyticsEventType.pulse)) {
      return;
    }
    _flushSegment();
    _startSegment();
    _sampleBufferFill();
    _sampleRender();
    _emit(AnalyticsEventType.pulse);
  }

  void _flushSegment() {
    final started = _segmentStarted;
    final kind = _segmentKind;
    if (started == null || kind == null) {
      return;
    }
    final elapsed = _now().difference(started);
    if (kind == AnalyticsEventType.playing) {
      _watchTime += elapsed;
    } else if (kind == AnalyticsEventType.rebufferstart) {
      _rebufferTime += elapsed;
      _watchTime += elapsed;
    } else if (kind == AnalyticsEventType.play) {
      _watchTime += elapsed;
    }
    _segmentStarted = null;
    _segmentKind = null;
  }

  void _startSegment() {
    final kind = _machine.current;
    if (kind == AnalyticsEventType.playing ||
        kind == AnalyticsEventType.rebufferstart ||
        kind == AnalyticsEventType.play) {
      _segmentStarted = _now();
      _segmentKind = kind;
    }
  }

  void _sampleBufferFill() {
    if (_machine.current != AnalyticsEventType.playing) {
      return;
    }
    final position = _controller.snapshot.position;
    var ahead = Duration.zero;
    for (final range in _controller.snapshot.buffered) {
      if (position >= range.start && position < range.end) {
        ahead = range.end - position;
        break;
      }
      if (range.end > position) {
        ahead = range.end - position;
        break;
      }
    }
    _bufferAhead.add(ahead < Duration.zero ? Duration.zero : ahead);
  }

  void _sampleRender() {
    if (_machine.current != AnalyticsEventType.playing) {
      return;
    }
    final encoded = _activeTrack(_lastTracks)?.height;
    final player = _playerHeight;
    if (encoded == null || player == null || player <= 0) {
      return;
    }
    final scale = encoded / player;
    final up = max(0.0, 1 - scale);
    final down = max(0.0, scale - 1);
    _upscaleSum += up;
    _downscaleSum += down;
    _maxUpscale = max(_maxUpscale, up);
    _maxDownscale = max(_maxDownscale, down);
    _renderSamples += 1;
  }

  void _restartBitrate() {
    _bitrateSince = _now();
  }

  void _flushBitrate() {
    final since = _bitrateSince;
    final bitrate = _activeTrack(_lastTracks)?.bitrate;
    if (since == null || bitrate == null) {
      _bitrateSince = _now();
      return;
    }
    if (_machine.current != AnalyticsEventType.playing) {
      _bitrateSince = _now();
      return;
    }
    final ms = _now().difference(since).inMilliseconds;
    _bitrateTimeMs += ms;
    _bitrateWeighted += bitrate * ms;
    _bitrateSince = _now();
  }

  VideoTrack? _activeTrack(VideoTrackList list) {
    final id = list.activeId;
    if (id == null) {
      return list.tracks.isEmpty ? null : list.tracks.first;
    }
    for (final track in list.tracks) {
      if (track.id == id) {
        return track;
      }
    }
    return null;
  }

  Future<void> _endView() async {
    if (_viewEnded || !_attached) {
      return;
    }
    _viewEnded = true;
    _attached = false;
    _pulse?.cancel();
    _pulse = null;
    for (final sub in _subs) {
      await sub.cancel();
    }
    _subs.clear();
    _flushSegment();
    _flushBitrate();
    final report = _report();
    if (!_machine.allows(AnalyticsEventType.viewend)) {
      return;
    }
    _machine.enter(AnalyticsEventType.viewend);
    _emit(AnalyticsEventType.viewend, includeDevice: true, report: report);
  }

  AnalyticsViewReport _report() {
    final endedAt = _now();
    final watchMs = _watchTime.inMilliseconds;
    final bufferFill = _bufferAhead.isEmpty
        ? Duration.zero
        : Duration(
            microseconds:
                _bufferAhead
                    .map((item) => item.inMicroseconds)
                    .reduce((a, b) => a + b) ~/
                _bufferAhead.length,
          );
    final liveLatency = _liveOffsets.isEmpty
        ? null
        : Duration(
            microseconds:
                _liveOffsets
                    .map((item) => item.inMicroseconds)
                    .reduce((a, b) => a + b) ~/
                _liveOffsets.length,
          );
    final jump = _jumpLatencies.isEmpty
        ? null
        : Duration(
            microseconds:
                _jumpLatencies
                    .map((item) => item.inMicroseconds)
                    .reduce((a, b) => a + b) ~/
                _jumpLatencies.length,
          );
    final track = _activeTrack(_controller.videoTrackList);
    return AnalyticsViewReport(
      schemaVersion: 1,
      video: VideoReport(
        details: _video,
        duration: _controller.snapshot.duration,
        width: track?.width,
        height: track?.height,
      ),
      view: ViewReport(
        viewId: viewId,
        viewerId: viewerId,
        startedAt: _attachedAt ?? endedAt,
        endedAt: endedAt,
        seekCount: _seekCount,
        seeked: _seeked,
        usedFullscreen: _usedFullscreen,
        exitedBeforeVideoPlays: !_didPlay,
        videoStartupFailed: _playAttempted && !_didPlay,
        errorCode: _lastError?.code.name,
        errorMessage: _lastError?.message,
        errorNativeDetails: _lastError?.nativeDetails,
      ),
      player: PlayerDetails(
        playerVersion: playerCoreVersion,
        playerWidth: _playerWidth,
        playerHeight: _playerHeight,
        autoplay: _autoplay,
        preload: _preload,
      ),
      device: _device,
      network: _network,
      qoe: QoeReport(
        stability: StabilityQoe(
          bufferRatio: watchMs == 0
              ? 0
              : _rebufferTime.inMilliseconds / watchMs,
          bufferFrequency: watchMs == 0
              ? 0
              : _rebufferCount / (watchMs / 60000),
          bufferCount: _rebufferCount,
          bufferFill: bufferFill,
          droppedFrameCount: _controller.droppedFrameCount,
        ),
        renderQuality: RenderQualityQoe(
          upscalePercentage: _renderSamples == 0
              ? 0
              : _upscaleSum / _renderSamples,
          maxUpscalePercentage: _maxUpscale,
          downscalePercentage: _renderSamples == 0
              ? 0
              : _downscaleSum / _renderSamples,
          maxDownscalePercentage: _maxDownscale,
          averageBitrate: _bitrateTimeMs == 0
              ? null
              : _bitrateWeighted / _bitrateTimeMs,
        ),
        startup: StartupQoe(
          videoStartupTime: _playAttemptAt == null || _firstPlayingAt == null
              ? null
              : _firstPlayingAt!.difference(_playAttemptAt!),
          playerInitializationTime: _initTime(),
          liveStreamLatency: liveLatency,
          jumpLatency: jump,
        ),
      ),
    );
  }

  Duration? _initTime() {
    final attached = _attachedAt;
    final ready = _playerReadyAt;
    if (attached == null || ready == null) {
      return null;
    }
    return ready.difference(attached);
  }

  static Timer _periodicPulse(Duration period, void Function() onTick) {
    return Timer.periodic(period, (_) => onTick());
  }

  static bool _isReadyLike(PlaybackState state) {
    return state == PlaybackState.ready ||
        state == PlaybackState.playing ||
        state == PlaybackState.paused ||
        state == PlaybackState.buffering ||
        state == PlaybackState.completed;
  }
}

String _uuidV4() {
  final random = Random.secure();
  final bytes = List<int>.generate(16, (_) => random.nextInt(256));
  bytes[6] = (bytes[6] & 0x0f) | 0x40;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  String hex(int byte) => byte.toRadixString(16).padLeft(2, '0');
  final chars = bytes.map(hex).join();
  return '${chars.substring(0, 8)}-${chars.substring(8, 12)}-'
      '${chars.substring(12, 16)}-${chars.substring(16, 20)}-'
      '${chars.substring(20)}';
}
