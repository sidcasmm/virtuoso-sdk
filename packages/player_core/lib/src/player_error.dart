/// Stable, app-facing error categories. Expand only via a new spec.
enum PlayerErrorCode {
  sourceUnreachable,
  sourceUnsupported,
  decodeFailed,
  timedOut,
  licenseDenied,
  unknown,
}

/// Discrete failure surfaced to Dart. Never a silent log-only event.
final class PlayerError {
  const PlayerError({
    required this.code,
    required this.message,
    this.nativeDetails,
    required this.isRecoverable,
  });

  final PlayerErrorCode code;
  final String message;
  final String? nativeDetails;
  final bool isRecoverable;
}
