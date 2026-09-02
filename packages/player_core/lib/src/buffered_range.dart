/// One contiguous buffered interval in media time.
final class BufferedRange {
  const BufferedRange({required this.start, required this.end});

  final Duration start;
  final Duration end;

  @override
  bool operator ==(Object other) =>
      other is BufferedRange && other.start == start && other.end == end;

  @override
  int get hashCode => Object.hash(start, end);
}
