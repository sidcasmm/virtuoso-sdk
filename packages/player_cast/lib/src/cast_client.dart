import 'dart:async';

import 'package:flutter/services.dart';
import 'package:player_core/player_core.dart';

import 'cast_platform.dart';
import 'pigeons/cast_api.g.dart' as pigeon;

enum CastSessionState { unavailable, idle, connecting, connected }

final class CastDevice {
  const CastDevice({required this.id, required this.name, this.model});

  final String id;
  final String name;
  final String? model;

  @override
  bool operator ==(Object other) =>
      other is CastDevice &&
      other.id == id &&
      other.name == name &&
      other.model == model;

  @override
  int get hashCode => Object.hash(id, name, model);
}

final class CastClient {
  CastClient({
    this.receiverAppId = defaultMediaReceiverId,
    CastPlatform? platform,
  }) : _platform = platform ?? PigeonCastPlatform() {
    _remote = CastRemotePlayer._(this);
    _ready = _initialize();
  }

  /// Default Media Receiver.
  static const defaultMediaReceiverId = 'CC1AD845';

  final String receiverAppId;
  final CastPlatform _platform;

  late final CastRemotePlayer _remote;
  late final Future<void> _ready;
  StreamSubscription<pigeon.HostCastEvent>? _eventsSub;
  var _disposed = false;
  var _discovering = false;

  var _sessionState = CastSessionState.unavailable;
  CastDevice? _connectedDevice;
  var _devices = const <CastDevice>[];

  PlayerController? _transferLocal;
  var _resumeWasPlaying = false;

  final _sessionStates = StreamController<CastSessionState>.broadcast();
  final _deviceLists = StreamController<List<CastDevice>>.broadcast();
  final _errors = StreamController<PlayerError>.broadcast();

  CastSessionState get sessionState => _sessionState;
  CastDevice? get connectedDevice => _connectedDevice;
  CastRemotePlayer get remote => _remote;
  List<CastDevice> get currentDevices => _devices;

  Stream<CastSessionState> get sessionStates =>
      _replay(_sessionState, _sessionStates.stream);
  Stream<List<CastDevice>> get devices =>
      _replay(_devices, _deviceLists.stream);
  Stream<PlayerError> get errors => _errors.stream;

  /// Completes when the host Cast SDK has been probed.
  Future<void> get initialized => _ready;

  Future<void> startDiscovery() async {
    _ensureNotDisposed();
    await _ready;
    _ensureAvailable();
    PlayerLicense.ensure(PaidFeature.cast);
    _discovering = true;
    await _invoke(() => _platform.startDiscovery());
  }

  Future<void> stopDiscovery() async {
    _ensureNotDisposed();
    await _ready;
    _discovering = false;
    if (_sessionState == CastSessionState.unavailable) {
      return;
    }
    await _invoke(() => _platform.stopDiscovery());
  }

  Future<void> connect(CastDevice device) async {
    _ensureNotDisposed();
    await _ready;
    _ensureAvailable();
    PlayerLicense.ensure(PaidFeature.cast);
    if (_sessionState == CastSessionState.connected ||
        _sessionState == CastSessionState.connecting) {
      throw StateError('cast-busy');
    }
    _connectedDevice = device;
    _setSession(CastSessionState.connecting);
    try {
      await _invoke(() => _platform.connect(device.id));
    } catch (error) {
      _connectedDevice = null;
      _setSession(CastSessionState.idle);
      rethrow;
    }
    if (_sessionState == CastSessionState.connecting) {
      _setSession(CastSessionState.connected);
    }
  }

  Future<void> disconnect({bool resumeLocal = false}) async {
    _ensureNotDisposed();
    await _ready;
    final local = _transferLocal;
    final wasPlaying = _resumeWasPlaying;
    final position = _remote.position;
    if (_sessionState == CastSessionState.connected ||
        _sessionState == CastSessionState.connecting) {
      await _invoke(() => _platform.disconnect());
    }
    _setSession(CastSessionState.idle);
    _connectedDevice = null;
    _remote._reset();
    if (resumeLocal && local != null) {
      await _resumeLocal(local, position: position, play: wasPlaying);
    }
    _transferLocal = null;
    _resumeWasPlaying = false;
  }

  /// Pause [local], load its HTTP(S) source at the current position, play remote.
  Future<void> transfer(PlayerController local, CastDevice device) async {
    _ensureNotDisposed();
    await _ready;
    _ensureAvailable();
    PlayerLicense.ensure(PaidFeature.cast);
    final uri = local.loadedUri;
    if (uri == null || (uri.scheme != 'http' && uri.scheme != 'https')) {
      throw ArgumentError.value(
        uri,
        'loadedUri',
        'Cast transfer requires an http or https source',
      );
    }
    final headers = local.loadedHeaders;
    if (headers != null && headers.isNotEmpty) {
      throw ArgumentError(
        'Cast Default Media Receiver does not support media headers',
      );
    }
    if (local.loadedDrm != null) {
      throw ArgumentError('DRM is not supported on Cast');
    }
    if (local.snapshot.playbackState == PlaybackState.disposed) {
      throw StateError('PlayerController has been disposed');
    }
    _transferLocal = local;
    _resumeWasPlaying =
        local.snapshot.playbackState == PlaybackState.playing ||
        local.snapshot.playbackState == PlaybackState.buffering;
    final position = local.snapshot.position;
    await local.pause();
    if (_sessionState != CastSessionState.connected ||
        _connectedDevice?.id != device.id) {
      if (_sessionState == CastSessionState.connected ||
          _sessionState == CastSessionState.connecting) {
        throw StateError('cast-busy');
      }
      await connect(device);
    }
    await _remote.load(
      uri,
      position: position,
      title: local.playlist.currentIndex == null
          ? null
          : local.playlist.items[local.playlist.currentIndex!].title,
    );
    await _remote.play();
    _remote._handoffFrom(local);
    if (local.playbackSpeed != 1.0) {
      await _remote.setPlaybackSpeed(local.playbackSpeed);
    }
  }

  Future<void> dispose() async {
    if (_disposed) {
      return;
    }
    _disposed = true;
    await _eventsSub?.cancel();
    _eventsSub = null;
    if (_discovering ||
        _sessionState == CastSessionState.connected ||
        _sessionState == CastSessionState.connecting) {
      try {
        await _platform.stopDiscovery();
      } catch (_) {}
      try {
        await _platform.disconnect();
      } catch (_) {}
    }
    _setSession(CastSessionState.idle);
    _connectedDevice = null;
    _transferLocal = null;
    await _sessionStates.close();
    await _deviceLists.close();
    await _errors.close();
    await _remote._close();
  }

  Future<void> _initialize() async {
    try {
      final state = await _platform.initialize(receiverAppId);
      _setSession(_mapSession(state));
      _eventsSub = _platform.events().listen(_onEvent);
    } catch (_) {
      if (_disposed) {
        return;
      }
      _setSession(CastSessionState.unavailable);
    }
  }

  void _onEvent(pigeon.HostCastEvent event) {
    if (_disposed) {
      return;
    }
    switch (event.kind) {
      case pigeon.HostCastEventKind.sessionState:
        final state = event.sessionState;
        if (state != null) {
          _setSession(_mapSession(state));
          if (state == pigeon.HostCastSessionState.idle ||
              state == pigeon.HostCastSessionState.unavailable) {
            _connectedDevice = null;
          }
        }
      case pigeon.HostCastEventKind.devices:
        final devices = [
          for (final device in event.devices ?? const <pigeon.HostCastDevice>[])
            CastDevice(id: device.id, name: device.name, model: device.model),
        ];
        _devices = devices;
        if (!_deviceLists.isClosed) {
          _deviceLists.add(devices);
        }
      case pigeon.HostCastEventKind.error:
        final error = PlayerError(
          code: _mapError(event.errorCode),
          message: event.errorMessage ?? 'Cast failed',
          nativeDetails: event.nativeDetails,
          isRecoverable: event.isRecoverable ?? false,
        );
        if (!_errors.isClosed) {
          _errors.add(error);
        }
      case pigeon.HostCastEventKind.playbackState:
        _remote._onPlayback(event.playbackState);
      case pigeon.HostCastEventKind.position:
        _remote._onPosition(event.positionMs, event.durationMs);
      case pigeon.HostCastEventKind.tracks:
        _remote._onTracks(event.tracks, event.activeTrackIds);
    }
  }

  void _setSession(CastSessionState state) {
    if (_sessionState == state) {
      return;
    }
    _sessionState = state;
    if (!_sessionStates.isClosed) {
      _sessionStates.add(state);
    }
  }

  void _ensureNotDisposed() {
    if (_disposed) {
      throw StateError('CastClient has been disposed');
    }
  }

  void _ensureAvailable() {
    if (_sessionState == CastSessionState.unavailable) {
      throw StateError('Cast is unavailable');
    }
  }

  Future<void> _invoke(Future<void> Function() call) async {
    try {
      await call();
    } on PlatformException catch (error) {
      throw StateError(error.message ?? error.code);
    }
  }

  Future<void> _resumeLocal(
    PlayerController local, {
    required Duration position,
    required bool play,
  }) async {
    if (local.snapshot.playbackState == PlaybackState.disposed) {
      return;
    }
    try {
      await local.seek(position);
      if (play) {
        await local.play();
      }
    } on StateError {
      // Local player went away.
    }
  }

  static CastSessionState _mapSession(pigeon.HostCastSessionState state) {
    return switch (state) {
      pigeon.HostCastSessionState.unavailable => CastSessionState.unavailable,
      pigeon.HostCastSessionState.idle => CastSessionState.idle,
      pigeon.HostCastSessionState.connecting => CastSessionState.connecting,
      pigeon.HostCastSessionState.connected => CastSessionState.connected,
    };
  }

  static PlayerErrorCode _mapError(pigeon.HostCastErrorCode? code) {
    return switch (code) {
      pigeon.HostCastErrorCode.sourceUnreachable =>
        PlayerErrorCode.sourceUnreachable,
      pigeon.HostCastErrorCode.sourceUnsupported =>
        PlayerErrorCode.sourceUnsupported,
      pigeon.HostCastErrorCode.decodeFailed => PlayerErrorCode.decodeFailed,
      pigeon.HostCastErrorCode.timedOut => PlayerErrorCode.timedOut,
      pigeon.HostCastErrorCode.licenseDenied => PlayerErrorCode.licenseDenied,
      pigeon.HostCastErrorCode.unknown || null => PlayerErrorCode.unknown,
    };
  }
}

final class CastRemotePlayer {
  CastRemotePlayer._(this._client);

  final CastClient _client;

  var _playbackState = PlaybackState.idle;
  var _position = Duration.zero;
  Duration? _duration;
  var _audioTrackList = AudioTrackList.empty;
  var _textTrackList = TextTrackList.empty;
  var _videoTrackList = VideoTrackList.empty;
  String? _activeAudioId;
  String? _activeTextId;
  String? _activeVideoId;
  var _audioAuto = true;
  var _textOff = true;
  var _videoAuto = true;
  String? _handoffAudioLanguage;
  String? _handoffTextLanguage;

  final _playbackStates = StreamController<PlaybackState>.broadcast();
  final _positions = StreamController<Duration>.broadcast();
  final _audioTracks = StreamController<AudioTrackList>.broadcast();
  final _textTracks = StreamController<TextTrackList>.broadcast();
  final _videoTracks = StreamController<VideoTrackList>.broadcast();

  PlaybackState get playbackState => _playbackState;
  Duration get position => _position;
  Duration? get duration => _duration;
  AudioTrackList get audioTrackList => _audioTrackList;
  TextTrackList get textTrackList => _textTrackList;
  VideoTrackList get videoTrackList => _videoTrackList;

  Stream<PlaybackState> get playbackStates =>
      _replay(_playbackState, _playbackStates.stream);
  Stream<Duration> get positions => _replay(_position, _positions.stream);
  Stream<AudioTrackList> get audioTracks =>
      _replay(_audioTrackList, _audioTracks.stream);
  Stream<TextTrackList> get textTracks =>
      _replay(_textTrackList, _textTracks.stream);
  Stream<VideoTrackList> get videoTracks =>
      _replay(_videoTrackList, _videoTracks.stream);

  Future<void> load(
    Uri uri, {
    Duration? position,
    String? title,
    String? contentType,
    Map<String, String>? headers,
    DrmConfiguration? drm,
  }) async {
    _client._ensureNotDisposed();
    await _client._ready;
    if (_client._sessionState != CastSessionState.connected) {
      throw StateError('Cast is not connected');
    }
    if (uri.scheme != 'http' && uri.scheme != 'https') {
      throw ArgumentError.value(
        uri,
        'uri',
        'only http and https URIs can be cast',
      );
    }
    if (headers != null && headers.isNotEmpty) {
      throw ArgumentError(
        'Cast Default Media Receiver does not support media headers',
      );
    }
    if (drm != null) {
      throw ArgumentError('DRM is not supported on Cast');
    }
    if (position != null && position.isNegative) {
      throw ArgumentError.value(position, 'position', 'must not be negative');
    }
    _setPlayback(PlaybackState.loading);
    await _client._invoke(
      () => _client._platform.load(
        uri.toString(),
        position?.inMilliseconds,
        title,
        contentType ?? _inferContentType(uri),
      ),
    );
  }

  Future<void> play() async {
    _client._ensureNotDisposed();
    await _client._ready;
    _ensureConnected();
    await _client._invoke(() => _client._platform.play());
  }

  Future<void> pause() async {
    _client._ensureNotDisposed();
    await _client._ready;
    _ensureConnected();
    await _client._invoke(() => _client._platform.pause());
  }

  Future<void> seek(Duration position) async {
    _client._ensureNotDisposed();
    await _client._ready;
    _ensureConnected();
    if (position.isNegative) {
      throw ArgumentError.value(position, 'position', 'must not be negative');
    }
    await _client._invoke(
      () => _client._platform.seek(position.inMilliseconds),
    );
  }

  Future<void> setVolume(double volume) async {
    _client._ensureNotDisposed();
    await _client._ready;
    _ensureConnected();
    await _client._invoke(
      () => _client._platform.setVolume(volume.clamp(0.0, 1.0)),
    );
  }

  Future<void> setMute(bool mute) async {
    _client._ensureNotDisposed();
    await _client._ready;
    _ensureConnected();
    await _client._invoke(() => _client._platform.setMute(mute));
  }

  Future<void> setPlaybackSpeed(double speed) async {
    _client._ensureNotDisposed();
    await _client._ready;
    _ensureConnected();
    if (speed <= 0) {
      throw ArgumentError.value(speed, 'speed', 'must be > 0');
    }
    await _client._invoke(() => _client._platform.setPlaybackSpeed(speed));
  }

  Future<void> setAudioTrack(String? id) async {
    _client._ensureNotDisposed();
    await _client._ready;
    _ensureConnected();
    if (id != null && _audioTrackList.tracks.isEmpty) {
      throw ArgumentError('Cast receiver has not reported audio tracks');
    }
    _ensureKnown(id, _audioTrackList.tracks.map((track) => track.id));
    _activeAudioId = id;
    _audioAuto = id == null;
    _audioTrackList = AudioTrackList(
      tracks: _audioTrackList.tracks,
      isAuto: _audioAuto,
      activeId: id ?? _audioTrackList.activeId,
    );
    await _pushActiveTracks();
    if (!_audioTracks.isClosed) {
      _audioTracks.add(_audioTrackList);
    }
  }

  Future<void> setTextTrack(String? id) async {
    _client._ensureNotDisposed();
    await _client._ready;
    _ensureConnected();
    if (id != null && _textTrackList.tracks.isEmpty) {
      throw ArgumentError('Cast receiver has not reported caption tracks');
    }
    _ensureKnown(id, _textTrackList.tracks.map((track) => track.id));
    _activeTextId = id;
    _textOff = id == null;
    _textTrackList = TextTrackList(
      tracks: _textTrackList.tracks,
      isAuto: _textOff,
      activeId: id,
    );
    await _pushActiveTracks();
    if (!_textTracks.isClosed) {
      _textTracks.add(_textTrackList);
    }
  }

  Future<void> setVideoTrack(String? id) async {
    _client._ensureNotDisposed();
    await _client._ready;
    _ensureConnected();
    if (_videoTrackList.tracks.isEmpty) {
      throw ArgumentError(
        'Cast Default Media Receiver does not support quality lock',
      );
    }
    _ensureKnown(id, _videoTrackList.tracks.map((track) => track.id));
    _activeVideoId = id;
    _videoAuto = id == null;
    _videoTrackList = VideoTrackList(
      tracks: _videoTrackList.tracks,
      isAuto: _videoAuto,
      activeId: id ?? _videoTrackList.activeId,
    );
    await _pushActiveTracks();
    if (!_videoTracks.isClosed) {
      _videoTracks.add(_videoTrackList);
    }
  }

  void _ensureConnected() {
    if (_client._sessionState != CastSessionState.connected) {
      throw StateError('Cast is not connected');
    }
  }

  void _ensureKnown(String? id, Iterable<String> ids) {
    if (id != null && ids.isNotEmpty && !ids.contains(id)) {
      throw ArgumentError.value(id, 'id', 'unknown Cast track');
    }
  }

  Future<void> _pushActiveTracks() async {
    final ids = <String>[
      if (!_audioAuto) ?_activeAudioId,
      if (!_textOff) ?_activeTextId,
      if (!_videoAuto) ?_activeVideoId,
    ];
    await _client._invoke(() => _client._platform.setActiveTracks(ids));
  }

  void _handoffFrom(PlayerController local) {
    final audio = local.audioTrackList;
    _handoffAudioLanguage = audio.isAuto
        ? null
        : _audioLanguage(audio.tracks, audio.activeId);
    final text = local.textTrackList;
    _handoffTextLanguage = text.isAuto
        ? null
        : _textLanguage(text.tracks, text.activeId);
  }

  static String? _audioLanguage(List<AudioTrack> tracks, String? id) {
    for (final track in tracks) {
      if (track.id == id) {
        return track.language ?? track.label;
      }
    }
    return null;
  }

  static String? _textLanguage(List<TextTrack> tracks, String? id) {
    for (final track in tracks) {
      if (track.id == id) {
        return track.language ?? track.label;
      }
    }
    return null;
  }

  void _onTracks(List<pigeon.HostCastTrack>? tracks, List<String>? activeIds) {
    final all = tracks ?? const <pigeon.HostCastTrack>[];
    final active = {...?activeIds};
    final audio = [
      for (final track in all)
        if (track.kind == pigeon.HostCastTrackKind.audio)
          AudioTrack(
            id: track.id,
            language: track.language,
            label: track.label,
          ),
    ];
    final text = _dedupeText([
      for (final track in all)
        if (track.kind == pigeon.HostCastTrackKind.text)
          TextTrack(id: track.id, language: track.language, label: track.label),
    ]);
    final video = [
      for (final track in all)
        if (track.kind == pigeon.HostCastTrackKind.video)
          VideoTrack(
            id: track.id,
            width: track.width,
            height: track.height,
            bitrate: track.bitrate,
          ),
    ];
    final activeAudio = audio
        .where((track) => active.contains(track.id))
        .map((track) => track.id)
        .firstOrNull;
    final activeText = text
        .where((track) => active.contains(track.id))
        .map((track) => track.id)
        .firstOrNull;
    final activeVideo = video
        .where((track) => active.contains(track.id))
        .map((track) => track.id)
        .firstOrNull;
    _audioTrackList = AudioTrackList(
      tracks: audio,
      isAuto: _audioAuto,
      activeId: _audioAuto ? activeAudio : (_activeAudioId ?? activeAudio),
    );
    _textTrackList = TextTrackList(
      tracks: text,
      isAuto: _textOff,
      activeId: _textOff ? null : (_activeTextId ?? activeText),
    );
    _videoTrackList = VideoTrackList(
      tracks: video,
      isAuto: _videoAuto,
      activeId: _videoAuto ? activeVideo : (_activeVideoId ?? activeVideo),
    );
    if (!_audioTracks.isClosed) {
      _audioTracks.add(_audioTrackList);
    }
    if (!_textTracks.isClosed) {
      _textTracks.add(_textTrackList);
    }
    if (!_videoTracks.isClosed) {
      _videoTracks.add(_videoTrackList);
    }
    unawaited(_applyHandoff(audio, text));
  }

  static List<TextTrack> _dedupeText(List<TextTrack> tracks) {
    final byKey = <String, TextTrack>{};
    for (final track in tracks) {
      final key = (track.language ?? track.label ?? track.id).toLowerCase();
      final existing = byKey[key];
      if (existing == null || _preferSidecar(track.id, existing.id)) {
        byKey[key] = track;
      }
    }
    return byKey.values.toList();
  }

  static bool _preferSidecar(String next, String current) {
    final nextId = int.tryParse(next) ?? 0;
    final currentId = int.tryParse(current) ?? 0;
    return nextId > currentId;
  }

  Future<void> _applyHandoff(
    List<AudioTrack> audio,
    List<TextTrack> text,
  ) async {
    final audioKey = _handoffAudioLanguage;
    final textKey = _handoffTextLanguage;
    if (audioKey == null && textKey == null) {
      return;
    }
    _handoffAudioLanguage = null;
    _handoffTextLanguage = null;
    if (audioKey != null) {
      for (final track in audio) {
        if (_sameLanguage(track.language, audioKey) ||
            track.label == audioKey) {
          await setAudioTrack(track.id);
          break;
        }
      }
    }
    if (textKey != null) {
      for (final track in text) {
        if (_sameLanguage(track.language, textKey) || track.label == textKey) {
          await setTextTrack(track.id);
          break;
        }
      }
    }
  }

  static bool _sameLanguage(String? a, String b) {
    if (a == null || a.isEmpty) {
      return false;
    }
    final left = a.toLowerCase();
    final right = b.toLowerCase();
    return left == right ||
        left.startsWith('$right-') ||
        right.startsWith('$left-');
  }

  void _onPlayback(pigeon.HostCastPlaybackState? state) {
    if (state == null) {
      return;
    }
    _setPlayback(_mapPlayback(state));
  }

  void _onPosition(int? positionMs, int? durationMs) {
    if (positionMs != null) {
      final position = Duration(milliseconds: positionMs);
      if (_position != position) {
        _position = position;
        if (!_positions.isClosed) {
          _positions.add(position);
        }
      }
    }
    if (durationMs != null) {
      _duration = Duration(milliseconds: durationMs);
    }
  }

  void _setPlayback(PlaybackState state) {
    if (_playbackState == state) {
      return;
    }
    _playbackState = state;
    if (!_playbackStates.isClosed) {
      _playbackStates.add(state);
    }
  }

  void _reset() {
    _setPlayback(PlaybackState.idle);
    _position = Duration.zero;
    _duration = null;
    _audioTrackList = AudioTrackList.empty;
    _textTrackList = TextTrackList.empty;
    _videoTrackList = VideoTrackList.empty;
    _activeAudioId = null;
    _activeTextId = null;
    _activeVideoId = null;
    _audioAuto = true;
    _textOff = true;
    _videoAuto = true;
    _handoffAudioLanguage = null;
    _handoffTextLanguage = null;
  }

  Future<void> _close() async {
    await _playbackStates.close();
    await _positions.close();
    await _audioTracks.close();
    await _textTracks.close();
    await _videoTracks.close();
  }

  static PlaybackState _mapPlayback(pigeon.HostCastPlaybackState state) {
    return switch (state) {
      pigeon.HostCastPlaybackState.idle => PlaybackState.idle,
      pigeon.HostCastPlaybackState.loading => PlaybackState.loading,
      pigeon.HostCastPlaybackState.ready => PlaybackState.ready,
      pigeon.HostCastPlaybackState.playing => PlaybackState.playing,
      pigeon.HostCastPlaybackState.paused => PlaybackState.paused,
      pigeon.HostCastPlaybackState.buffering => PlaybackState.buffering,
      pigeon.HostCastPlaybackState.completed => PlaybackState.completed,
      pigeon.HostCastPlaybackState.error => PlaybackState.error,
      pigeon.HostCastPlaybackState.disposed => PlaybackState.disposed,
    };
  }

  static String _inferContentType(Uri uri) {
    final path = uri.path.toLowerCase();
    if (path.endsWith('.m3u8')) {
      return 'application/x-mpegURL';
    }
    if (path.endsWith('.mpd')) {
      return 'application/dash+xml';
    }
    if (path.endsWith('.mp3') || path.endsWith('.m4a')) {
      return 'audio/mpeg';
    }
    return 'video/mp4';
  }
}

Stream<T> _replay<T>(T latest, Stream<T> stream) async* {
  yield latest;
  yield* stream;
}
