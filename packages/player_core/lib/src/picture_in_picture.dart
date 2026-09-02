/// System Picture-in-Picture window for the current [PlayerController].
enum PictureInPictureState {
  /// OS, activity, or this player cannot enter PiP.
  unavailable,

  /// Available and not in PiP.
  inactive,

  /// System PiP window is showing this player.
  active,
}

/// Why PiP stopped. Discrete; does not replay.
enum PictureInPictureExitKind {
  /// User expanded PiP or Dart called [PlayerController.exitPictureInPicture].
  restored,

  /// User closed PiP, or [PlayerController.load] / dispose ended it.
  dismissed,
}
