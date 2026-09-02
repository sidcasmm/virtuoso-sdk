/// Virtuoso Player core — engine-agnostic controller over Pigeon.
library;

export 'src/buffered_range.dart';
export 'src/playback_state.dart';
export 'src/player_controller.dart';
export 'src/player_license.dart';
export 'src/player_error.dart';
export 'src/player_snapshot.dart';
export 'src/player_view.dart';
export 'src/video_track.dart';
export 'src/audio_track.dart';
export 'src/text_track.dart';
export 'src/player_cache.dart';
export 'src/playlist.dart';
export 'src/chapter.dart';
export 'src/skip_segment.dart';
export 'src/drm.dart';
export 'src/sprite_sheet.dart';
export 'src/picture_in_picture.dart';
export 'src/background_audio.dart';

/// Package name constant.
const String playerCorePackageName = 'player_core';

/// Semver of this package (copied into analytics player details).
const String playerCoreVersion = '0.0.1';
