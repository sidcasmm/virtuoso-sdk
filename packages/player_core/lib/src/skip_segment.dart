/// A time range on the current item that may be jumped. The app paints Skip UI.
final class SkipSegment {
  const SkipSegment({
    required this.start,
    required this.end,
    this.label,
    this.id,
  });

  final Duration start;
  final Duration end;
  final String? label;
  final String? id;

  @override
  bool operator ==(Object other) =>
      other is SkipSegment &&
      start == other.start &&
      end == other.end &&
      label == other.label &&
      id == other.id;

  @override
  int get hashCode => Object.hash(start, end, label, id);
}
