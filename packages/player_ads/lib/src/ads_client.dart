import 'dart:async';

import 'package:flutter/services.dart';
import 'package:player_core/player_core.dart';

import 'ads_platform.dart';
import 'pigeons/ads_api.g.dart' as pigeon;

enum AdState { idle, loading, playing, paused, skipped, completed, error }

final class AdInfo {
  const AdInfo({
    required this.position,
    required this.canSkip,
    required this.isSkippable,
    required this.indexInPod,
    required this.podSize,
    this.title,
    this.duration,
    this.skipOffset,
  });

  final String? title;
  final Duration? duration;
  final Duration position;
  final Duration? skipOffset;
  final bool canSkip;
  final bool isSkippable;
  final int indexInPod;
  final int podSize;

  @override
  bool operator ==(Object other) =>
      other is AdInfo &&
      other.title == title &&
      other.duration == duration &&
      other.position == position &&
      other.skipOffset == skipOffset &&
      other.canSkip == canSkip &&
      other.isSkippable == isSkippable &&
      other.indexInPod == indexInPod &&
      other.podSize == podSize;

  @override
  int get hashCode => Object.hash(
    title,
    duration,
    position,
    skipOffset,
    canSkip,
    isSkippable,
    indexInPod,
    podSize,
  );
}

final class AdsRequest {
  const AdsRequest({required this.tag});

  final Uri tag;
}

final class AdsClient {
  AdsClient({AdsPlatform? platform})
    : _platform = platform ?? PigeonAdsPlatform() {
    _ready = _initialize();
  }

  final AdsPlatform _platform;

  late final Future<void> _ready;
  StreamSubscription<pigeon.HostAdEvent>? _eventsSub;
  var _disposed = false;
  var _state = AdState.idle;
  AdInfo? _current;
  int? _boundPlayerId;

  final _states = StreamController<AdState>.broadcast();
  final _currents = StreamController<AdInfo?>.broadcast();

  Future<void> get initialized => _ready;

  AdState get state => _state;
  AdInfo? get current => _current;

  /// Host player id from the last [bind], or null after [clear].
  int? get boundPlayerId => _boundPlayerId;

  Stream<AdState> get states => _replay(_state, _states.stream);
  Stream<AdInfo?> get currents => _replay(_current, _currents.stream);

  Future<void> bind(PlayerController controller, AdsRequest request) async {
    _ensureNotDisposed();
    PlayerLicense.ensure(PaidFeature.ads);
    _ensureHttp(request.tag);
    await _ready;
    await controller.initialized;
    final id = controller.hostPlayerId;
    _boundPlayerId = id;
    await _invoke(() => _platform.bind(id, _withCorrelator(request.tag)));
  }

  Future<void> clear() async {
    _ensureNotDisposed();
    await _ready;
    final id = _boundPlayerId;
    _boundPlayerId = null;
    _setState(AdState.idle);
    _setCurrent(null);
    if (id != null) {
      await _invoke(() => _platform.clear(id));
    }
  }

  Future<void> skip() async {
    _ensureNotDisposed();
    await _ready;
    final id = _boundPlayerId;
    if (id == null || _current?.canSkip != true) {
      return;
    }
    await _invoke(() => _platform.skip(id));
  }

  Future<void> dispose() async {
    if (_disposed) {
      return;
    }
    _disposed = true;
    final id = _boundPlayerId;
    _boundPlayerId = null;
    await _eventsSub?.cancel();
    if (id != null) {
      try {
        await _platform.clear(id);
      } catch (_) {}
    }
    await _states.close();
    await _currents.close();
  }

  Future<void> _initialize() async {
    try {
      await _platform.initialize();
      _eventsSub = _platform.events().listen(_onEvent);
    } catch (_) {
      if (_disposed) {
        return;
      }
    }
  }

  void _onEvent(pigeon.HostAdEvent event) {
    if (_disposed) {
      return;
    }
    switch (event.kind) {
      case pigeon.HostAdEventKind.state:
        final state = event.state;
        if (state != null) {
          _setState(_mapState(state));
        }
        if (event.state == pigeon.HostAdState.error ||
            event.state == pigeon.HostAdState.idle ||
            event.state == pigeon.HostAdState.completed ||
            event.state == pigeon.HostAdState.skipped) {
          if (event.state != pigeon.HostAdState.skipped &&
              event.state != pigeon.HostAdState.completed) {
            _setCurrent(null);
          }
        }
      case pigeon.HostAdEventKind.ad:
        final ad = event.ad;
        if (ad != null) {
          _setCurrent(_mapInfo(ad));
        }
    }
  }

  void _setState(AdState state) {
    if (_state == state) {
      return;
    }
    _state = state;
    if (!_states.isClosed) {
      _states.add(state);
    }
  }

  void _setCurrent(AdInfo? info) {
    if (_current == info) {
      return;
    }
    _current = info;
    if (!_currents.isClosed) {
      _currents.add(info);
    }
  }

  void _ensureNotDisposed() {
    if (_disposed) {
      throw StateError('AdsClient has been disposed');
    }
  }

  void _ensureHttp(Uri tag) {
    if (tag.scheme != 'http' && tag.scheme != 'https') {
      throw ArgumentError.value(tag, 'tag', 'only http and https ad tags');
    }
  }

  Future<T> _invoke<T>(Future<T> Function() call) async {
    try {
      return await call();
    } on PlatformException catch (error) {
      if (error.code == 'argument-error') {
        throw ArgumentError(error.message);
      }
      throw StateError(error.message ?? error.code);
    }
  }

  static AdState _mapState(pigeon.HostAdState state) {
    return switch (state) {
      pigeon.HostAdState.idle => AdState.idle,
      pigeon.HostAdState.loading => AdState.loading,
      pigeon.HostAdState.playing => AdState.playing,
      pigeon.HostAdState.paused => AdState.paused,
      pigeon.HostAdState.skipped => AdState.skipped,
      pigeon.HostAdState.completed => AdState.completed,
      pigeon.HostAdState.error => AdState.error,
    };
  }

  static AdInfo _mapInfo(pigeon.HostAdInfo info) {
    return AdInfo(
      title: info.title,
      duration: info.durationMs == null
          ? null
          : Duration(milliseconds: info.durationMs!),
      position: Duration(milliseconds: info.positionMs),
      skipOffset: info.skipOffsetMs == null
          ? null
          : Duration(milliseconds: info.skipOffsetMs!),
      canSkip: info.canSkip,
      isSkippable: info.isSkippable,
      indexInPod: info.indexInPod,
      podSize: info.podSize,
    );
  }

  static String _withCorrelator(Uri tag) {
    final existing = tag.queryParameters['correlator'];
    if (existing != null && existing.isNotEmpty) {
      return tag.toString();
    }
    return tag
        .replace(
          queryParameters: {
            ...tag.queryParameters,
            'correlator': DateTime.now().millisecondsSinceEpoch.toString(),
          },
        )
        .toString();
  }

  static Stream<T> _replay<T>(T current, Stream<T> inner) async* {
    yield current;
    yield* inner;
  }
}
