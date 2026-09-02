import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import 'buffered_range.dart';
import 'playback_state.dart';
import 'player_error.dart';
import 'player_license.dart';
import 'player_platform.dart';
import 'player_snapshot.dart';
import 'pigeons/player_api.g.dart' as pigeon;
import 'video_track.dart';
import 'audio_track.dart';
import 'text_track.dart';
import 'playlist.dart';
import 'chapter.dart';
import 'skip_segment.dart';
import 'drm.dart';
import 'sprite_sheet.dart';
import 'picture_in_picture.dart';
import 'background_audio.dart';

/// Dart-facing player. App code depends on this type, not on engines.
final class PlayerController {
  PlayerController({
    PlayerPlatform? platform,
    SpriteMetadataFetcher? spriteMetadataFetcher,
  }) : _platform = platform ?? PigeonPlayerPlatform(),
       _spriteMetadataFetcher = spriteMetadataFetcher ?? fetchSpriteMetadata {
    _created = _create();
  }

  final PlayerPlatform _platform;
  final SpriteMetadataFetcher _spriteMetadataFetcher;

  late final Future<void> _created;
  int? _playerId;
  int? _textureId;
  var _disposed = false;
  StreamSubscription<pigeon.HostPlayerEvent>? _eventsSub;

  PlayerSnapshot _snapshot = PlayerSnapshot.initial;

  final _playbackState = StreamController<PlaybackState>.broadcast();
  final _position = StreamController<Duration>.broadcast();
  final _buffered = StreamController<List<BufferedRange>>.broadcast();
  final _errors = StreamController<PlayerError>.broadcast();
  final _videoTracks = StreamController<VideoTrackList>.broadcast();
  final _audioTracks = StreamController<AudioTrackList>.broadcast();
  final _textTracks = StreamController<TextTrackList>.broadcast();
  final _subtitleCues = StreamController<List<SubtitleCue>>.broadcast();
  final _playlists = StreamController<Playlist>.broadcast();
  final textureIdListenable = ValueNotifier<int?>(null);

  int? get textureId => _textureId;

  PlayerSnapshot get snapshot => _snapshot;

  VideoTrackList get videoTrackList => _videoTrackList;
  var _videoTrackList = VideoTrackList.empty;
  var _videoTracksKnown = false;

  Stream<PlaybackState> get playbackState =>
      _replay(_snapshot.playbackState, _playbackState.stream);

  Stream<Duration> get position =>
      _replay(_snapshot.position, _position.stream);

  Stream<List<BufferedRange>> get buffered =>
      _replay(_snapshot.buffered, _buffered.stream);

  Stream<PlayerError> get errors => _errors.stream;

  Stream<VideoTrackList> get videoTracks =>
      _replay(_videoTrackList, _videoTracks.stream);

  AudioTrackList get audioTrackList => _audioTrackList;
  var _audioTrackList = AudioTrackList.empty;
  var _audioTracksKnown = false;

  Stream<AudioTrackList> get audioTracks =>
      _replay(_audioTrackList, _audioTracks.stream);

  TextTrackList get textTrackList => _textTrackList;
  var _textTrackList = TextTrackList.empty;
  var _textTracksKnown = false;
  var _subtitleCueList = const <SubtitleCue>[];

  Stream<TextTrackList> get textTracks =>
      _replay(_textTrackList, _textTracks.stream);

  Stream<List<SubtitleCue>> get subtitleCues =>
      _replay(_subtitleCueList, _subtitleCues.stream);

  Playlist get playlist => _playlist;
  var _playlist = Playlist.empty;
  var _playlistOwnedLoad = false;
  var _playlistLoadGen = 0;

  Stream<Playlist> get playlists => _replay(_playlist, _playlists.stream);

  List<Chapter> get chapters => _chapters;
  var _chapters = const <Chapter>[];
  Chapter? get currentChapter => _currentChapter;
  Chapter? _currentChapter;
  final _chapterLists = StreamController<List<Chapter>>.broadcast();
  final _currentChapters = StreamController<Chapter?>.broadcast();

  Stream<List<Chapter>> get chapterLists =>
      _replay(_chapters, _chapterLists.stream);

  Stream<Chapter?> get currentChapters =>
      _replay(_currentChapter, _currentChapters.stream);

  List<SkipSegment> get skipSegments => _skipSegments;
  var _skipSegments = const <SkipSegment>[];
  SkipSegment? get currentSkipSegment => _currentSkipSegment;
  SkipSegment? _currentSkipSegment;
  var _skipSegmentsAutomatic = true;
  var _userSeek = false;
  var _skipSeek = false;
  final _consumedSkipSegments = <SkipSegment>{};
  final _skipSegmentLists = StreamController<List<SkipSegment>>.broadcast();
  final _currentSkipSegments = StreamController<SkipSegment?>.broadcast();
  final _skipSegmentEvents = StreamController<SkipSegment>.broadcast();

  bool get skipSegmentsAutomatic => _skipSegmentsAutomatic;

  Stream<List<SkipSegment>> get skipSegmentLists =>
      _replay(_skipSegments, _skipSegmentLists.stream);

  Stream<SkipSegment?> get currentSkipSegments =>
      _replay(_currentSkipSegment, _currentSkipSegments.stream);

  Stream<SkipSegment> get skipSegmentEvents => _skipSegmentEvents.stream;

  List<SpriteCue> get spriteCues => _spriteCues;
  var _spriteCues = const <SpriteCue>[];
  SpriteSheet? get spriteSheet => _spriteSheet;
  SpriteSheet? _spriteSheet;
  final _spriteCueLists = StreamController<List<SpriteCue>>.broadcast();
  final _droppedFrames = StreamController<int>.broadcast();
  final _liveOffsets = StreamController<Duration?>.broadcast();

  Stream<List<SpriteCue>> get spriteCueLists =>
      _replay(_spriteCues, _spriteCueLists.stream);

  var _isLive = false;
  Duration? _liveOffset;
  var _droppedFrameCount = 0;

  bool get isLive => _isLive;
  Duration? get liveOffset => _liveOffset;
  int get droppedFrameCount => _droppedFrameCount;

  Stream<Duration?> get liveOffsets =>
      _replay(_liveOffset, _liveOffsets.stream);
  Stream<int> get droppedFrames =>
      _replay(_droppedFrameCount, _droppedFrames.stream);

  var _pictureInPictureState = PictureInPictureState.unavailable;
  var _pictureInPictureAutomatic = false;
  final _pictureInPictureStates =
      StreamController<PictureInPictureState>.broadcast();
  final _pictureInPictureExits =
      StreamController<PictureInPictureExitKind>.broadcast();

  bool get isPictureInPictureAvailable =>
      _pictureInPictureState != PictureInPictureState.unavailable;

  PictureInPictureState get pictureInPictureState => _pictureInPictureState;

  Stream<PictureInPictureState> get pictureInPictureStates =>
      _replay(_pictureInPictureState, _pictureInPictureStates.stream);

  Stream<PictureInPictureExitKind> get pictureInPictureExits =>
      _pictureInPictureExits.stream;

  bool get isPictureInPictureAutomatic => _pictureInPictureAutomatic;

  var _backgroundAudioState = BackgroundAudioState.unavailable;
  var _backgroundAudioEnabled = false;
  NowPlaying? _nowPlaying;
  final _backgroundAudioStates =
      StreamController<BackgroundAudioState>.broadcast();

  bool get isBackgroundAudioAvailable =>
      _backgroundAudioState != BackgroundAudioState.unavailable;

  BackgroundAudioState get backgroundAudioState => _backgroundAudioState;

  Stream<BackgroundAudioState> get backgroundAudioStates =>
      _replay(_backgroundAudioState, _backgroundAudioStates.stream);

  bool get isBackgroundAudioEnabled => _backgroundAudioEnabled;

  NowPlaying? get nowPlaying => _nowPlaying;

  /// Last source accepted by [load] / [loadAsset] / [playAt]. Null after
  /// [dispose] or if nothing has been loaded.
  Uri? get loadedUri => _loadedUri;
  Map<String, String>? get loadedHeaders => _loadedHeaders;
  DrmConfiguration? get loadedDrm => _loadedDrm;

  Uri? _loadedUri;
  Map<String, String>? _loadedHeaders;
  DrmConfiguration? _loadedDrm;

  Future<void> _create() async {
    try {
      final result = await _platform.create();
      _playerId = result.playerId;
      _textureId = result.textureId;
      textureIdListenable.value = result.textureId;
      _setPictureInPictureState(_mapPipState(result.pictureInPictureState));
      _setBackgroundAudioState(
        _mapBackgroundAudioState(result.backgroundAudioState),
      );
      _eventsSub = _platform.events().listen(_onEvent);
    } catch (error) {
      if (_disposed) {
        return;
      }
      _update(
        playbackState: PlaybackState.error,
        error: PlayerError(
          code: PlayerErrorCode.unknown,
          message: '$error',
          isRecoverable: false,
        ),
      );
    }
  }

  Future<void> load(
    Uri uri, {
    Map<String, String>? headers,
    DrmConfiguration? drm,
  }) async {
    _ensureNotDisposed();
    final trimmed = _nonEmptyHeaders(headers);
    if (trimmed != null && uri.scheme != 'http' && uri.scheme != 'https') {
      throw ArgumentError.value(
        uri,
        'uri',
        'headers are only supported for http and https URIs',
      );
    }
    if (uri.scheme == 'player-offline') {
      PlayerLicense.ensure(PaidFeature.downloads);
    }
    if (drm != null) {
      PlayerLicense.ensure(PaidFeature.drm);
    }
    _validateDrm(drm);
    final source = _sourceFromUri(uri, headers: trimmed, drm: drm);
    _loadedUri = uri;
    _loadedHeaders = trimmed;
    _loadedDrm = drm;
    await _created;
    if (!_playlistOwnedLoad) {
      _replacePlaylist(const [], null);
    }
    _replaceChapters(const []);
    _replaceSkipSegments(const []);
    _replaceSpriteCues(const [], sheet: null);
    _resetTelemetry();
    _emitState(PlaybackState.loading, clearError: true);
    _resetVideoTracks();
    _resetAudioTracks();
    _resetTextTracks();
    await _invokeHost(() => _platform.load(_id, source));
    await _syncNowPlaying();
  }

  /// Flutter asset key from the app (or [package]) `pubspec.yaml`.
  Future<void> loadAsset(String asset, {String? package}) async {
    _ensureNotDisposed();
    if (asset.isEmpty) {
      throw ArgumentError.value(asset, 'asset', 'must not be empty');
    }
    _loadedUri = Uri(
      scheme: 'asset',
      path: package == null ? asset : '$package/$asset',
    );
    _loadedHeaders = null;
    _loadedDrm = null;
    await _created;
    _replacePlaylist(const [], null);
    _replaceChapters(const []);
    _replaceSkipSegments(const []);
    _replaceSpriteCues(const [], sheet: null);
    _resetTelemetry();
    _emitState(PlaybackState.loading, clearError: true);
    _resetVideoTracks();
    _resetAudioTracks();
    _resetTextTracks();
    await _invokeHost(
      () => _platform.load(
        _id,
        pigeon.HostMediaSource(
          kind: pigeon.HostSourceKind.asset,
          location: asset,
          packageName: package,
        ),
      ),
    );
    await _syncNowPlaying();
  }

  Future<void> play() async {
    _ensureNotDisposed();
    await _created;
    await _invokeHost(() => _platform.play(_id));
  }

  Future<void> pause() async {
    _ensureNotDisposed();
    await _created;
    await _invokeHost(() => _platform.pause(_id));
  }

  Future<void> seek(Duration position) async {
    _ensureNotDisposed();
    if (position.isNegative) {
      throw ArgumentError.value(position, 'position', 'must not be negative');
    }
    await _created;
    if (!_skipSeek) {
      _userSeek = true;
    }
    await _invokeHost(() => _platform.seek(_id, position.inMilliseconds));
  }

  Future<void> setVolume(double volume) async {
    _ensureNotDisposed();
    await _created;
    await _platform.setVolume(_id, volume.clamp(0.0, 1.0));
  }

  Future<void> setPlaybackSpeed(double speed) async {
    _ensureNotDisposed();
    if (speed <= 0) {
      throw ArgumentError.value(speed, 'speed', 'must be > 0');
    }
    await _created;
    _playbackSpeed = speed;
    await _platform.setPlaybackSpeed(_id, speed);
  }

  var _playbackSpeed = 1.0;

  /// Last [setPlaybackSpeed] value. Default 1.0.
  double get playbackSpeed => _playbackSpeed;

  var _looping = false;

  /// When `true`, playback restarts at zero after the end.
  bool get isLooping => _looping;

  Future<void> setLooping(bool looping) async {
    _ensureNotDisposed();
    await _created;
    _looping = looping;
    await _platform.setLooping(_id, looping);
  }

  /// [id] of a [VideoTrack] from [videoTrackList], or `null` for ABR.
  Future<void> setVideoTrack(String? id) async {
    _ensureNotDisposed();
    if (id != null) {
      final tracks = _videoTrackList.tracks;
      final unknown =
          (_videoTracksKnown && tracks.isEmpty) ||
          (tracks.isNotEmpty && !tracks.any((track) => track.id == id));
      if (unknown) {
        throw ArgumentError.value(id, 'id', 'unknown video track');
      }
    }
    await _created;
    await _invokeHost(() => _platform.setVideoTrack(_id, id));
  }

  /// [id] of an [AudioTrack] from [audioTrackList], or `null` for default.
  Future<void> setAudioTrack(String? id) async {
    _ensureNotDisposed();
    if (id != null) {
      final tracks = _audioTrackList.tracks;
      final unknown =
          (_audioTracksKnown && tracks.isEmpty) ||
          (tracks.isNotEmpty && !tracks.any((track) => track.id == id));
      if (unknown) {
        throw ArgumentError.value(id, 'id', 'unknown audio track');
      }
    }
    await _created;
    await _invokeHost(() => _platform.setAudioTrack(_id, id));
  }

  /// [id] of a [TextTrack] from [textTrackList], or `null` for Off.
  Future<void> setTextTrack(String? id) async {
    _ensureNotDisposed();
    if (id != null) {
      final tracks = _textTrackList.tracks;
      final unknown =
          (_textTracksKnown && tracks.isEmpty) ||
          (tracks.isNotEmpty && !tracks.any((track) => track.id == id));
      if (unknown) {
        throw ArgumentError.value(id, 'id', 'unknown text track');
      }
    }
    await _created;
    await _invokeHost(() => _platform.setTextTrack(_id, id));
  }

  Future<void> setPictureInPictureAutomatic(bool enabled) async {
    _ensureNotDisposed();
    if (enabled) {
      PlayerLicense.ensure(PaidFeature.pictureInPicture);
    }
    await _created;
    _pictureInPictureAutomatic = enabled;
    await _platform.setPictureInPictureAutomatic(_id, enabled);
  }

  Future<void> enterPictureInPicture({
    int? aspectWidth,
    int? aspectHeight,
    Rect? sourceRect,
  }) async {
    _ensureNotDisposed();
    PlayerLicense.ensure(PaidFeature.pictureInPicture);
    _validatePipAspect(aspectWidth, aspectHeight);
    await _created;
    if (_pictureInPictureState == PictureInPictureState.unavailable) {
      throw StateError('Picture-in-Picture is not available');
    }
    if (_pictureInPictureState == PictureInPictureState.active) {
      return;
    }
    switch (_snapshot.playbackState) {
      case PlaybackState.idle:
      case PlaybackState.loading:
      case PlaybackState.error:
      case PlaybackState.disposed:
        throw StateError('Picture-in-Picture requires a loaded source');
      case PlaybackState.ready:
      case PlaybackState.playing:
      case PlaybackState.paused:
      case PlaybackState.buffering:
      case PlaybackState.completed:
        break;
    }
    await _invokePip(
      () => _platform.enterPictureInPicture(
        _id,
        aspectWidth,
        aspectHeight,
        _hostPipSourceRect(sourceRect),
      ),
    );
  }

  Future<void> exitPictureInPicture() async {
    _ensureNotDisposed();
    await _created;
    if (_pictureInPictureState != PictureInPictureState.active) {
      return;
    }
    await _invokePip(() => _platform.exitPictureInPicture(_id));
  }

  Future<void> setBackgroundAudioEnabled(bool enabled) async {
    _ensureNotDisposed();
    await _created;
    if (!enabled) {
      if (!_backgroundAudioEnabled) {
        return;
      }
      _backgroundAudioEnabled = false;
      await _invokeBackground(
        () => _platform.setBackgroundAudioEnabled(_id, false),
      );
      return;
    }
    if (_backgroundAudioState == BackgroundAudioState.unavailable) {
      throw StateError('Background audio is not available');
    }
    PlayerLicense.ensure(PaidFeature.backgroundAudio);
    if (_backgroundAudioEnabled) {
      return;
    }
    await _invokeBackground(
      () => _platform.setBackgroundAudioEnabled(_id, true),
    );
    _backgroundAudioEnabled = true;
    await _syncNowPlaying();
  }

  Future<void> setNowPlaying(NowPlaying? info) async {
    _ensureNotDisposed();
    if (info != null) {
      PlayerLicense.ensure(PaidFeature.backgroundAudio);
    }
    _validateNowPlaying(info);
    _nowPlaying = info;
    await _created;
    await _syncNowPlaying();
  }

  /// Replaces the queue. Does not load; call [playAt] to start an item.
  Future<void> setPlaylist(List<PlaylistItem> items) async {
    _ensureNotDisposed();
    _replacePlaylist(List<PlaylistItem>.from(items), null);
  }

  /// Inserts [item] at [index], or appends when [index] is omitted.
  Future<void> addToPlaylist(PlaylistItem item, {int? index}) async {
    _ensureNotDisposed();
    final items = [..._playlist.items];
    final at = index ?? items.length;
    if (at < 0 || at > items.length) {
      throw ArgumentError.value(at, 'index', 'out of playlist range');
    }
    items.insert(at, item);
    var current = _playlist.currentIndex;
    if (current != null && at <= current) {
      current += 1;
    }
    _replacePlaylist(items, current);
  }

  Future<void> removeFromPlaylist(int index) async {
    _ensureNotDisposed();
    final items = [..._playlist.items];
    _ensurePlaylistIndex(index, length: items.length);
    final removedCurrent = _playlist.currentIndex == index;
    items.removeAt(index);
    var current = _playlist.currentIndex;
    if (current == null) {
      _replacePlaylist(items, null);
      return;
    }
    if (index < current) {
      current -= 1;
    } else if (index == current) {
      current = items.isEmpty
          ? null
          : (index < items.length ? index : items.length - 1);
    }
    _replacePlaylist(items, current);
    if (removedCurrent && current != null) {
      await playAt(current);
    }
  }

  Future<void> moveInPlaylist(int from, int to) async {
    _ensureNotDisposed();
    final items = [..._playlist.items];
    _ensurePlaylistIndex(from, length: items.length, name: 'from');
    _ensurePlaylistIndex(to, length: items.length, name: 'to');
    if (from == to) {
      return;
    }
    final item = items.removeAt(from);
    items.insert(to, item);
    _replacePlaylist(
      items,
      _movedCurrentIndex(current: _playlist.currentIndex, from: from, to: to),
    );
  }

  Future<void> clearPlaylist() async {
    _ensureNotDisposed();
    _replacePlaylist(const [], null);
  }

  /// Loads [playlist] item [index] and calls [play].
  Future<void> playAt(int index) async {
    _ensureNotDisposed();
    _ensurePlaylistIndex(index, length: _playlist.items.length);
    _replacePlaylist(_playlist.items, index);
    final gen = ++_playlistLoadGen;
    _playlistOwnedLoad = true;
    try {
      final item = _playlist.items[index];
      await load(item.uri, headers: item.headers, drm: item.drm);
      if (_disposed || gen != _playlistLoadGen) {
        return;
      }
      if (_snapshot.playbackState == PlaybackState.error) {
        return;
      }
      await play();
    } finally {
      if (gen == _playlistLoadGen) {
        _playlistOwnedLoad = false;
      }
    }
  }

  Future<void> playNext() async {
    _ensureNotDisposed();
    if (!_playlist.hasNext) {
      return;
    }
    await playAt(_playlist.currentIndex! + 1);
  }

  Future<void> playPrevious() async {
    _ensureNotDisposed();
    if (!_playlist.hasPrevious) {
      return;
    }
    await playAt(_playlist.currentIndex! - 1);
  }

  Future<void> setChapters(List<Chapter> chapters) async {
    _ensureNotDisposed();
    PlayerLicense.ensure(PaidFeature.chapters);
    final sorted = [...chapters]..sort((a, b) => a.start.compareTo(b.start));
    for (final chapter in sorted) {
      if (chapter.start.isNegative) {
        throw ArgumentError.value(
          chapter.start,
          'start',
          'must not be negative',
        );
      }
      final end = chapter.end;
      if (end != null && end <= chapter.start) {
        throw ArgumentError.value(end, 'end', 'must be after start');
      }
    }
    _replaceChapters(sorted);
  }

  Future<void> setChaptersFromVtt(String vtt) async {
    _ensureNotDisposed();
    await setChapters(parseChaptersFromVtt(vtt));
  }

  Future<void> clearChapters() async {
    _ensureNotDisposed();
    _replaceChapters(const []);
  }

  Future<void> seekToChapter(int index) async {
    _ensureNotDisposed();
    PlayerLicense.ensure(PaidFeature.chapters);
    if (index < 0 || index >= _chapters.length) {
      throw ArgumentError.value(index, 'index', 'out of chapter range');
    }
    await seek(_chapters[index].start);
  }

  Future<void> setSkipSegments(List<SkipSegment> segments) async {
    _ensureNotDisposed();
    PlayerLicense.ensure(PaidFeature.skipSegments);
    final sorted = [...segments]..sort((a, b) => a.start.compareTo(b.start));
    for (final segment in sorted) {
      if (segment.start.isNegative) {
        throw ArgumentError.value(
          segment.start,
          'start',
          'must not be negative',
        );
      }
      if (segment.end <= segment.start) {
        throw ArgumentError.value(segment.end, 'end', 'must be after start');
      }
    }
    _replaceSkipSegments(sorted);
  }

  Future<void> clearSkipSegments() async {
    _ensureNotDisposed();
    _replaceSkipSegments(const []);
  }

  Future<void> setSkipSegmentsAutomatic(bool enabled) async {
    _ensureNotDisposed();
    PlayerLicense.ensure(PaidFeature.skipSegments);
    _skipSegmentsAutomatic = enabled;
    _maybeAutoSkip();
  }

  Future<void> skipCurrentSegment() async {
    _ensureNotDisposed();
    PlayerLicense.ensure(PaidFeature.skipSegments);
    final segment = _currentSkipSegment;
    if (segment == null) {
      return;
    }
    await _consumeAndSeek(segment);
  }

  Future<void> setSpriteSheet(SpriteSheet sheet) async {
    _ensureNotDisposed();
    PlayerLicense.ensure(PaidFeature.spritesheet);
    final body = await _spriteMetadataFetcher(
      sheet.metadataUrl,
      headers: sheet.headers,
    );
    await setSpriteCues(
      parseSpriteCuesFromJson(
        body,
        spriteUrl: sheet.spriteUrl,
        base: sheet.metadataUrl,
      ),
    );
    _spriteSheet = sheet;
  }

  Future<void> setSpriteSheetFromUrl(
    Uri metadataUrl, {
    Map<String, String>? headers,
  }) async {
    _ensureNotDisposed();
    PlayerLicense.ensure(PaidFeature.spritesheet);
    final trimmed = _nonEmptyHeaders(headers);
    final body = await _spriteMetadataFetcher(metadataUrl, headers: trimmed);
    final text = body.trimLeft();
    if (text.startsWith('{')) {
      await setSpriteCues(parseSpriteCuesFromJson(text, base: metadataUrl));
    } else {
      await setSpriteCues(parseSpriteCuesFromVtt(text, base: metadataUrl));
    }
    _spriteSheet = null;
  }

  Future<void> setSpriteCues(List<SpriteCue> cues) async {
    _ensureNotDisposed();
    PlayerLicense.ensure(PaidFeature.spritesheet);
    final sorted = [...cues]..sort((a, b) => a.start.compareTo(b.start));
    for (final cue in sorted) {
      if (cue.start.isNegative) {
        throw ArgumentError.value(cue.start, 'start', 'must not be negative');
      }
      if (cue.end <= cue.start) {
        throw ArgumentError.value(cue.end, 'end', 'must be after start');
      }
      if (cue.width <= 0 || cue.height <= 0) {
        throw ArgumentError('width and height must be > 0');
      }
    }
    _replaceSpriteCues(sorted, sheet: null);
  }

  Future<void> clearSpriteSheet() async {
    _ensureNotDisposed();
    _replaceSpriteCues(const [], sheet: null);
  }

  SpriteCue? spriteCueAt(Duration position) {
    _ensureNotDisposed();
    SpriteCue? match;
    for (final cue in _spriteCues) {
      if (cue.start > position) {
        break;
      }
      if (position < cue.end) {
        match = cue;
      }
    }
    return match;
  }

  Future<void> dispose() async {
    if (_disposed) {
      return;
    }
    _disposed = true;
    if (_pictureInPictureState == PictureInPictureState.active) {
      _setPictureInPictureState(
        PictureInPictureState.inactive,
        exit: PictureInPictureExitKind.dismissed,
      );
    }
    if (_backgroundAudioState == BackgroundAudioState.active) {
      _backgroundAudioEnabled = false;
      _setBackgroundAudioState(BackgroundAudioState.inactive);
    }
    _nowPlaying = null;
    await _eventsSub?.cancel();
    _eventsSub = null;
    final id = _playerId;
    if (id != null) {
      await _platform.disposePlayer(id);
    }
    _playerId = null;
    _textureId = null;
    textureIdListenable.value = null;
    _loadedUri = null;
    _loadedHeaders = null;
    _loadedDrm = null;
    _emitState(PlaybackState.disposed);
    await _playbackState.close();
    await _position.close();
    await _buffered.close();
    await _errors.close();
    await _videoTracks.close();
    await _audioTracks.close();
    await _textTracks.close();
    await _subtitleCues.close();
    await _playlists.close();
    await _chapterLists.close();
    await _currentChapters.close();
    await _skipSegmentLists.close();
    await _currentSkipSegments.close();
    await _skipSegmentEvents.close();
    await _spriteCueLists.close();
    await _droppedFrames.close();
    await _liveOffsets.close();
    await _pictureInPictureStates.close();
    await _pictureInPictureExits.close();
    await _backgroundAudioStates.close();
  }

  /// Completes when the host player and texture exist.
  Future<void> get initialized => _created;

  /// Host player id for sibling plugins (`player_ads`, tests).
  int get hostPlayerId => _id;

  int get _id {
    final id = _playerId;
    if (id == null) {
      throw StateError('Player is not created yet');
    }
    return id;
  }

  void _ensureNotDisposed() {
    if (_disposed) {
      throw StateError('PlayerController has been disposed');
    }
  }

  pigeon.HostMediaSource _sourceFromUri(
    Uri uri, {
    Map<String, String>? headers,
    DrmConfiguration? drm,
  }) {
    switch (uri.scheme) {
      case 'http':
      case 'https':
        return pigeon.HostMediaSource(
          kind: pigeon.HostSourceKind.network,
          location: uri.toString(),
          headers: headers,
          drm: _hostDrm(drm),
        );
      case 'file':
        return pigeon.HostMediaSource(
          kind: pigeon.HostSourceKind.file,
          location: uri.toFilePath(),
          drm: _hostDrm(drm),
        );
      case 'content':
        return pigeon.HostMediaSource(
          kind: pigeon.HostSourceKind.content,
          location: uri.toString(),
          drm: _hostDrm(drm),
        );
      case 'player-offline':
        final id = _offlineDownloadId(uri);
        return pigeon.HostMediaSource(
          kind: pigeon.HostSourceKind.offline,
          location: id,
          drm: _hostDrm(drm),
        );
      default:
        throw ArgumentError.value(
          uri,
          'uri',
          'only http, https, file, content, and player-offline URIs are supported',
        );
    }
  }

  static String _offlineDownloadId(Uri uri) {
    final path = uri.path;
    if (path.isNotEmpty) {
      return path.startsWith('/') ? path.substring(1) : path;
    }
    if (uri.host.isNotEmpty) {
      return uri.host;
    }
    const prefix = 'player-offline:';
    final encoded = uri.toString();
    if (encoded.startsWith(prefix)) {
      final id = encoded.substring(prefix.length);
      if (id.isNotEmpty) {
        return id;
      }
    }
    throw ArgumentError.value(
      uri,
      'uri',
      'player-offline URI must include an id',
    );
  }

  pigeon.HostDrmConfiguration? _hostDrm(DrmConfiguration? drm) {
    if (drm == null) {
      return null;
    }
    return pigeon.HostDrmConfiguration(
      scheme: switch (drm.scheme) {
        DrmScheme.widevine => pigeon.HostDrmScheme.widevine,
        DrmScheme.fairPlay => pigeon.HostDrmScheme.fairPlay,
        DrmScheme.clearKey => pigeon.HostDrmScheme.clearKey,
      },
      licenseUrl: drm.licenseUrl?.toString(),
      licenseHeaders: _nonEmptyHeaders(drm.licenseHeaders),
      clearKeys: _nonEmptyHeaders(drm.clearKeys),
      certificate: drm.certificate,
      contentId: drm.contentId,
    );
  }

  void _validateDrm(DrmConfiguration? drm) {
    if (drm == null) {
      return;
    }
    switch (drm.scheme) {
      case DrmScheme.widevine:
        if (drm.licenseUrl == null) {
          throw ArgumentError.value(
            drm.licenseUrl,
            'licenseUrl',
            'is required for Widevine',
          );
        }
      case DrmScheme.fairPlay:
        if (drm.licenseUrl == null) {
          throw ArgumentError.value(
            drm.licenseUrl,
            'licenseUrl',
            'is required for FairPlay',
          );
        }
        final certificate = drm.certificate;
        if (certificate == null || certificate.isEmpty) {
          throw ArgumentError.value(
            certificate,
            'certificate',
            'is required for FairPlay',
          );
        }
      case DrmScheme.clearKey:
        final keys = drm.clearKeys;
        if ((keys == null || keys.isEmpty) && drm.licenseUrl == null) {
          throw ArgumentError('ClearKey requires clearKeys or licenseUrl');
        }
        if (keys != null) {
          for (final entry in keys.entries) {
            _validateClearKeyHex(entry.key, 'kid');
            _validateClearKeyHex(entry.value, 'key');
          }
        }
    }
  }

  void _validateClearKeyHex(String value, String name) {
    if (!RegExp(r'^[0-9a-fA-F]{32}$').hasMatch(value)) {
      throw ArgumentError.value(value, name, 'must be 32 hex characters');
    }
  }

  Map<String, String>? _nonEmptyHeaders(Map<String, String>? headers) {
    if (headers == null || headers.isEmpty) {
      return null;
    }
    return Map<String, String>.from(headers);
  }

  /// Host failures belong on [errors], not as a thrown [PlatformException].
  Future<void> _invokeHost(Future<void> Function() call) async {
    try {
      await call();
    } on PlatformException catch (error) {
      _emitHostFailure(error);
    }
  }

  void _emitHostFailure(PlatformException error) {
    final playerError = PlayerError(
      code: PlayerErrorCode.unknown,
      message: error.message ?? 'Playback failed',
      nativeDetails: error.code,
      isRecoverable: false,
    );
    _update(playbackState: PlaybackState.error, error: playerError);
    if (!_errors.isClosed) {
      _errors.add(playerError);
    }
  }

  Future<void> _invokePip(Future<void> Function() call) async {
    try {
      await call();
    } on PlatformException catch (error) {
      throw StateError(error.message ?? 'Picture-in-Picture failed');
    }
  }

  Future<void> _invokeBackground(Future<void> Function() call) async {
    try {
      await call();
    } on PlatformException catch (error) {
      throw StateError(error.message ?? 'Background audio failed');
    }
  }

  void _validateNowPlaying(NowPlaying? info) {
    final uri = info?.artworkUri;
    if (uri == null) {
      return;
    }
    if (uri.scheme != 'http' && uri.scheme != 'https') {
      throw ArgumentError.value(uri, 'artworkUri', 'must be http or https');
    }
  }

  Future<void> _syncNowPlaying() async {
    if (!_backgroundAudioEnabled || _disposed) {
      return;
    }
    final info = _nowPlaying;
    await _invokeBackground(
      () => _platform.setNowPlaying(
        _id,
        info?.title ?? _currentPlaylistTitle,
        info?.artist,
        info?.album,
        info?.artworkUri?.toString(),
      ),
    );
  }

  String? get _currentPlaylistTitle {
    final index = _playlist.currentIndex;
    if (index == null || index < 0 || index >= _playlist.items.length) {
      return null;
    }
    return _playlist.items[index].title;
  }

  pigeon.HostPipSourceRect? _hostPipSourceRect(Rect? sourceRect) {
    if (sourceRect == null || sourceRect.width <= 0 || sourceRect.height <= 0) {
      return null;
    }
    final views = SchedulerBinding.instance.platformDispatcher.views;
    if (views.isEmpty) {
      return null;
    }
    final dpr = views.first.devicePixelRatio;
    return pigeon.HostPipSourceRect(
      left: (sourceRect.left * dpr).round(),
      top: (sourceRect.top * dpr).round(),
      width: (sourceRect.width * dpr).round(),
      height: (sourceRect.height * dpr).round(),
    );
  }

  void _validatePipAspect(int? aspectWidth, int? aspectHeight) {
    if ((aspectWidth == null) != (aspectHeight == null)) {
      throw ArgumentError(
        'aspectWidth and aspectHeight must both be set or both be omitted',
      );
    }
    if (aspectWidth != null && aspectWidth <= 0) {
      throw ArgumentError.value(aspectWidth, 'aspectWidth', 'must be > 0');
    }
    if (aspectHeight != null && aspectHeight <= 0) {
      throw ArgumentError.value(aspectHeight, 'aspectHeight', 'must be > 0');
    }
  }

  void _setPictureInPictureState(
    PictureInPictureState? state, {
    PictureInPictureExitKind? exit,
  }) {
    if (state != null && state != _pictureInPictureState) {
      _pictureInPictureState = state;
      if (!_pictureInPictureStates.isClosed) {
        _pictureInPictureStates.add(state);
      }
    }
    if (exit != null && !_pictureInPictureExits.isClosed) {
      _pictureInPictureExits.add(exit);
    }
  }

  PictureInPictureState? _mapPipState(pigeon.HostPictureInPictureState? state) {
    return switch (state) {
      pigeon.HostPictureInPictureState.unavailable =>
        PictureInPictureState.unavailable,
      pigeon.HostPictureInPictureState.inactive =>
        PictureInPictureState.inactive,
      pigeon.HostPictureInPictureState.active => PictureInPictureState.active,
      null => null,
    };
  }

  void _setBackgroundAudioState(BackgroundAudioState? state) {
    if (state == null || state == _backgroundAudioState) {
      return;
    }
    _backgroundAudioState = state;
    if (!_backgroundAudioStates.isClosed) {
      _backgroundAudioStates.add(state);
    }
  }

  BackgroundAudioState? _mapBackgroundAudioState(
    pigeon.HostBackgroundAudioState? state,
  ) {
    return switch (state) {
      pigeon.HostBackgroundAudioState.unavailable =>
        BackgroundAudioState.unavailable,
      pigeon.HostBackgroundAudioState.inactive => BackgroundAudioState.inactive,
      pigeon.HostBackgroundAudioState.active => BackgroundAudioState.active,
      null => null,
    };
  }

  PictureInPictureExitKind? _mapPipExit(
    pigeon.HostPictureInPictureExitKind? kind,
  ) {
    return switch (kind) {
      pigeon.HostPictureInPictureExitKind.restored =>
        PictureInPictureExitKind.restored,
      pigeon.HostPictureInPictureExitKind.dismissed =>
        PictureInPictureExitKind.dismissed,
      null => null,
    };
  }

  void _onEvent(pigeon.HostPlayerEvent event) {
    if (_disposed || event.playerId != _playerId) {
      return;
    }
    switch (event.kind) {
      case pigeon.HostEventKind.playbackState:
        final mapped = _mapState(event.playbackState);
        if (mapped == null) {
          return;
        }
        final position = _durationOrNull(event.positionMs);
        _update(
          playbackState: mapped,
          position: position,
          duration: _durationOrNull(event.durationMs),
          clearDuration:
              event.durationMs == null && mapped == PlaybackState.loading,
          clearError: mapped != PlaybackState.error,
        );
        if (position != null && !_position.isClosed) {
          _position.add(position);
        }
      case pigeon.HostEventKind.position:
        final position = _durationOrNull(event.positionMs);
        if (position == null) {
          return;
        }
        _update(
          position: position,
          duration: _durationOrNull(event.durationMs),
        );
        if (!_position.isClosed) {
          _position.add(position);
        }
      case pigeon.HostEventKind.buffered:
        final ranges = (event.buffered ?? const <pigeon.HostBufferedRange>[])
            .map(
              (range) => BufferedRange(
                start: Duration(milliseconds: range.startMs),
                end: Duration(milliseconds: range.endMs),
              ),
            )
            .toList(growable: false);
        _update(buffered: ranges);
        if (!_buffered.isClosed) {
          _buffered.add(ranges);
        }
      case pigeon.HostEventKind.error:
        final error = PlayerError(
          code: _mapError(event.errorCode),
          message: event.errorMessage ?? 'Playback failed',
          nativeDetails: event.nativeDetails,
          isRecoverable: event.isRecoverable ?? false,
        );
        _update(playbackState: PlaybackState.error, error: error);
        if (!_errors.isClosed) {
          _errors.add(error);
        }
      case pigeon.HostEventKind.videoTracks:
        _setVideoTracks(
          VideoTrackList(
            tracks: (event.videoTracks ?? const <pigeon.HostVideoTrack>[])
                .map(
                  (track) => VideoTrack(
                    id: track.id,
                    width: track.width,
                    height: track.height,
                    bitrate: track.bitrate,
                    codec: track.codec,
                  ),
                )
                .toList(growable: false),
            isAuto: event.videoTrackAuto ?? true,
            activeId: event.selectedVideoTrackId,
          ),
        );
      case pigeon.HostEventKind.audioTracks:
        _setAudioTracks(
          AudioTrackList(
            tracks: (event.audioTracks ?? const <pigeon.HostAudioTrack>[])
                .map(
                  (track) => AudioTrack(
                    id: track.id,
                    language: track.language,
                    label: track.label,
                    channels: track.channels,
                    codec: track.codec,
                  ),
                )
                .toList(growable: false),
            isAuto: event.audioTrackAuto ?? true,
            activeId: event.selectedAudioTrackId,
          ),
        );
      case pigeon.HostEventKind.textTracks:
        _setTextTracks(
          TextTrackList(
            tracks: (event.textTracks ?? const <pigeon.HostTextTrack>[])
                .map(
                  (track) => TextTrack(
                    id: track.id,
                    language: track.language,
                    label: track.label,
                    codec: track.codec,
                  ),
                )
                .toList(growable: false),
            isAuto: event.textTrackAuto ?? true,
            activeId: event.selectedTextTrackId,
          ),
        );
      case pigeon.HostEventKind.subtitleCues:
        _setSubtitleCues(
          _uniqueSubtitleCues(
            (event.subtitleCues ?? const <pigeon.HostSubtitleCue>[]).map(
              (cue) => cue.text,
            ),
          ),
        );
      case pigeon.HostEventKind.droppedFrames:
        _setDroppedFrameCount(event.droppedFrameCount ?? 0);
      case pigeon.HostEventKind.live:
        _setLive(
          isLive: event.isLive ?? false,
          offset: _durationOrNull(event.liveOffsetMs),
        );
      case pigeon.HostEventKind.pictureInPicture:
        final mapped = _mapPipState(event.pictureInPictureState);
        if (mapped == null) {
          return;
        }
        _setPictureInPictureState(
          mapped,
          exit: _mapPipExit(event.pictureInPictureExit),
        );
      case pigeon.HostEventKind.backgroundAudio:
        final mapped = _mapBackgroundAudioState(event.backgroundAudioState);
        if (mapped == null) {
          return;
        }
        if (mapped != BackgroundAudioState.active) {
          _backgroundAudioEnabled = false;
        }
        _setBackgroundAudioState(mapped);
      case pigeon.HostEventKind.mediaCommand:
        if (_disposed) {
          return;
        }
        switch (event.mediaCommand) {
          case pigeon.HostMediaCommand.next:
            unawaited(playNext());
          case pigeon.HostMediaCommand.previous:
            unawaited(playPrevious());
          case null:
            return;
        }
    }
  }

  void _resetTelemetry() {
    _setDroppedFrameCount(0);
    _setLive(isLive: false, offset: null);
  }

  void _setDroppedFrameCount(int count) {
    if (_droppedFrameCount == count) {
      return;
    }
    _droppedFrameCount = count;
    if (!_droppedFrames.isClosed) {
      _droppedFrames.add(count);
    }
  }

  void _setLive({required bool isLive, Duration? offset}) {
    if (_isLive == isLive && _liveOffset == offset) {
      return;
    }
    _isLive = isLive;
    _liveOffset = isLive ? offset : null;
    if (!_liveOffsets.isClosed) {
      _liveOffsets.add(_liveOffset);
    }
  }

  void _resetVideoTracks() {
    _videoTracksKnown = false;
    _setVideoTracks(VideoTrackList.empty, known: false);
  }

  void _setVideoTracks(VideoTrackList list, {bool known = true}) {
    _videoTracksKnown = known;
    _videoTrackList = list;
    if (!_videoTracks.isClosed) {
      _videoTracks.add(list);
    }
  }

  void _resetAudioTracks() {
    _audioTracksKnown = false;
    _setAudioTracks(AudioTrackList.empty, known: false);
  }

  void _setAudioTracks(AudioTrackList list, {bool known = true}) {
    _audioTracksKnown = known;
    _audioTrackList = list;
    if (!_audioTracks.isClosed) {
      _audioTracks.add(list);
    }
  }

  void _resetTextTracks() {
    _textTracksKnown = false;
    _setTextTracks(TextTrackList.empty, known: false);
    _setSubtitleCues(const <SubtitleCue>[]);
  }

  void _setTextTracks(TextTrackList list, {bool known = true}) {
    _textTracksKnown = known;
    _textTrackList = list;
    if (!_textTracks.isClosed) {
      _textTracks.add(list);
    }
  }

  void _setSubtitleCues(List<SubtitleCue> cues) {
    _subtitleCueList = cues;
    if (!_subtitleCues.isClosed) {
      _subtitleCues.add(cues);
    }
  }

  void _emitState(PlaybackState state, {bool clearError = false}) {
    _update(playbackState: state, clearError: clearError);
  }

  void _update({
    PlaybackState? playbackState,
    Duration? position,
    Duration? duration,
    List<BufferedRange>? buffered,
    PlayerError? error,
    bool clearError = false,
    bool clearDuration = false,
  }) {
    final previous = _snapshot;
    _snapshot = _snapshot.copyWith(
      playbackState: playbackState,
      position: position,
      duration: duration,
      buffered: buffered,
      error: error,
      clearError: clearError,
      clearDuration: clearDuration,
    );
    if (!_playbackState.isClosed &&
        playbackState != null &&
        previous.playbackState != _snapshot.playbackState) {
      _playbackState.add(_snapshot.playbackState);
    }
    if (playbackState == PlaybackState.completed &&
        previous.playbackState != PlaybackState.completed) {
      _maybeAdvancePlaylist();
    }
    final positionChanged =
        position != null && previous.position != _snapshot.position;
    final stateChanged =
        playbackState != null &&
        previous.playbackState != _snapshot.playbackState;
    if (positionChanged) {
      if (!_userSeek &&
          previous.position > Duration.zero &&
          _snapshot.position == Duration.zero) {
        _consumedSkipSegments.clear();
      }
      _syncCurrentChapter();
      _syncCurrentSkipSegment();
    }
    if (stateChanged &&
        _looping &&
        previous.playbackState == PlaybackState.completed &&
        _snapshot.playbackState == PlaybackState.playing) {
      _consumedSkipSegments.clear();
      _syncCurrentSkipSegment();
    }
    if (positionChanged || stateChanged) {
      _maybeAutoSkip();
    }
  }

  void _replaceChapters(List<Chapter> chapters) {
    final next = chapters.isEmpty
        ? const <Chapter>[]
        : List<Chapter>.unmodifiable(chapters);
    if (!listEquals(next, _chapters)) {
      _chapters = next;
      if (!_chapterLists.isClosed) {
        _chapterLists.add(_chapters);
      }
    }
    _syncCurrentChapter();
  }

  void _replaceSkipSegments(List<SkipSegment> segments) {
    final next = segments.isEmpty
        ? const <SkipSegment>[]
        : List<SkipSegment>.unmodifiable(segments);
    _consumedSkipSegments.clear();
    _userSeek = false;
    if (!listEquals(next, _skipSegments)) {
      _skipSegments = next;
      if (!_skipSegmentLists.isClosed) {
        _skipSegmentLists.add(_skipSegments);
      }
    }
    _syncCurrentSkipSegment();
    _maybeAutoSkip();
  }

  void _syncCurrentSkipSegment() {
    final next = _skipSegmentAt(_snapshot.position);
    if (next == null) {
      _userSeek = false;
    }
    if (next == _currentSkipSegment) {
      return;
    }
    _currentSkipSegment = next;
    if (!_currentSkipSegments.isClosed) {
      _currentSkipSegments.add(next);
    }
  }

  SkipSegment? _skipSegmentAt(Duration position) {
    for (final segment in _skipSegments) {
      if (segment.start > position) {
        break;
      }
      if (position < segment.end) {
        return segment;
      }
    }
    return null;
  }

  void _maybeAutoSkip() {
    if (!_skipSegmentsAutomatic || _skipSeek) {
      return;
    }
    final state = _snapshot.playbackState;
    if (state != PlaybackState.playing && state != PlaybackState.buffering) {
      return;
    }
    final segment = _currentSkipSegment;
    if (segment == null ||
        _userSeek ||
        _consumedSkipSegments.contains(segment)) {
      return;
    }
    unawaited(_consumeAndSeek(segment));
  }

  Future<void> _consumeAndSeek(SkipSegment segment) async {
    _consumedSkipSegments.add(segment);
    if (!_skipSegmentEvents.isClosed) {
      _skipSegmentEvents.add(segment);
    }
    _skipSeek = true;
    try {
      await seek(segment.end);
    } on StateError {
      // Disposed while seeking.
    } finally {
      _skipSeek = false;
    }
  }

  void _replaceSpriteCues(List<SpriteCue> cues, {required SpriteSheet? sheet}) {
    final next = cues.isEmpty
        ? const <SpriteCue>[]
        : List<SpriteCue>.unmodifiable(cues);
    _spriteSheet = sheet;
    if (listEquals(next, _spriteCues)) {
      return;
    }
    _spriteCues = next;
    if (!_spriteCueLists.isClosed) {
      _spriteCueLists.add(_spriteCues);
    }
  }

  void _syncCurrentChapter() {
    final next = _chapterAt(_snapshot.position);
    if (next == _currentChapter) {
      return;
    }
    _currentChapter = next;
    if (!_currentChapters.isClosed) {
      _currentChapters.add(next);
    }
  }

  Chapter? _chapterAt(Duration position) {
    Chapter? match;
    for (final chapter in _chapters) {
      if (chapter.start > position) {
        break;
      }
      final end = chapter.end;
      if (end == null || position < end) {
        match = chapter;
      }
    }
    return match;
  }

  void _maybeAdvancePlaylist() {
    if (_looping || !_playlist.hasNext || _playlistOwnedLoad) {
      return;
    }
    unawaited(playAt(_playlist.currentIndex! + 1));
  }

  void _replacePlaylist(List<PlaylistItem> items, int? currentIndex) {
    final next = Playlist(
      items: items.isEmpty ? const [] : List<PlaylistItem>.unmodifiable(items),
      currentIndex: currentIndex,
    );
    if (next == _playlist) {
      return;
    }
    _playlist = next;
    if (!_playlists.isClosed) {
      _playlists.add(_playlist);
    }
  }

  void _ensurePlaylistIndex(
    int index, {
    required int length,
    String name = 'index',
  }) {
    if (index < 0 || index >= length) {
      throw ArgumentError.value(index, name, 'out of playlist range');
    }
  }

  int? _movedCurrentIndex({
    required int? current,
    required int from,
    required int to,
  }) {
    if (current == null) {
      return null;
    }
    if (current == from) {
      return to;
    }
    if (from < current && to >= current) {
      return current - 1;
    }
    if (from > current && to <= current) {
      return current + 1;
    }
    return current;
  }

  Duration? _durationOrNull(int? ms) =>
      ms == null ? null : Duration(milliseconds: ms);

  PlaybackState? _mapState(pigeon.HostPlaybackState? state) {
    return switch (state) {
      pigeon.HostPlaybackState.idle => PlaybackState.idle,
      pigeon.HostPlaybackState.loading => PlaybackState.loading,
      pigeon.HostPlaybackState.ready => PlaybackState.ready,
      pigeon.HostPlaybackState.playing => PlaybackState.playing,
      pigeon.HostPlaybackState.paused => PlaybackState.paused,
      pigeon.HostPlaybackState.buffering => PlaybackState.buffering,
      pigeon.HostPlaybackState.completed => PlaybackState.completed,
      pigeon.HostPlaybackState.error => PlaybackState.error,
      pigeon.HostPlaybackState.disposed => PlaybackState.disposed,
      null => null,
    };
  }

  PlayerErrorCode _mapError(pigeon.HostErrorCode? code) {
    return switch (code) {
      pigeon.HostErrorCode.sourceUnreachable =>
        PlayerErrorCode.sourceUnreachable,
      pigeon.HostErrorCode.sourceUnsupported =>
        PlayerErrorCode.sourceUnsupported,
      pigeon.HostErrorCode.decodeFailed => PlayerErrorCode.decodeFailed,
      pigeon.HostErrorCode.timedOut => PlayerErrorCode.timedOut,
      pigeon.HostErrorCode.licenseDenied => PlayerErrorCode.licenseDenied,
      pigeon.HostErrorCode.unknown || null => PlayerErrorCode.unknown,
    };
  }
}

/// Visible cue texts with duplicates removed (engines often emit the same
/// line twice: WebVTT + CEA-608, or two attributed strings).
List<SubtitleCue> _uniqueSubtitleCues(Iterable<String> texts) {
  final seen = <String>{};
  final cues = <SubtitleCue>[];
  for (final raw in texts) {
    final lines = raw
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty);
    for (final line in lines) {
      if (seen.add(line)) {
        cues.add(SubtitleCue(text: line));
      }
    }
  }
  return List<SubtitleCue>.unmodifiable(cues);
}

Stream<T> _replay<T>(T latest, Stream<T> stream) {
  return Stream<T>.multi((listener) {
    listener.add(latest);
    final sub = stream.listen(
      listener.add,
      onError: listener.addError,
      onDone: listener.close,
    );
    listener.onCancel = sub.cancel;
  });
}
