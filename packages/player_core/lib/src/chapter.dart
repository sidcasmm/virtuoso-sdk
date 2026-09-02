/// A time marker on the current item. The app paints chapter UI.
final class Chapter {
  const Chapter({required this.start, this.end, required this.title, this.id});

  final Duration start;
  final Duration? end;
  final String title;
  final String? id;

  @override
  bool operator ==(Object other) =>
      other is Chapter &&
      start == other.start &&
      end == other.end &&
      title == other.title &&
      id == other.id;

  @override
  int get hashCode => Object.hash(start, end, title, id);
}

final _timing = RegExp(
  r'^(?:(\d{2,}):)?(\d{2}):(\d{2})[.,](\d{3})\s+-->\s+'
  r'(?:(\d{2,}):)?(\d{2}):(\d{2})[.,](\d{3})',
);

/// WebVTT chapter cues (`WEBVTT` + `start --> end` + title lines).
List<Chapter> parseChaptersFromVtt(String vtt) {
  final text = vtt.trimLeft();
  if (text.isEmpty) {
    throw FormatException('VTT is empty');
  }
  final lines = text.split(RegExp(r'\r\n|\n|\r'));
  var i = 0;
  if (lines[i].startsWith('WEBVTT')) {
    i++;
  }
  final chapters = <Chapter>[];
  while (i < lines.length) {
    var line = lines[i].trim();
    if (line.isEmpty || line.startsWith('NOTE')) {
      i++;
      continue;
    }
    var id = line;
    var timing = _timing.firstMatch(line);
    if (timing == null) {
      i++;
      if (i >= lines.length) {
        throw FormatException('VTT cue is missing a timing line');
      }
      timing = _timing.firstMatch(lines[i].trim());
      if (timing == null) {
        throw FormatException('VTT cue is missing a timing line');
      }
    } else {
      id = '';
    }
    i++;
    final titleLines = <String>[];
    while (i < lines.length && lines[i].trim().isNotEmpty) {
      titleLines.add(lines[i].trim());
      i++;
    }
    final title = titleLines.join(' ');
    if (title.isEmpty) {
      throw FormatException('VTT cue is missing a title');
    }
    chapters.add(
      Chapter(
        start: _vttClock(timing, 1),
        end: _vttClock(timing, 5),
        title: title,
        id: id.isEmpty ? null : id,
      ),
    );
  }
  if (chapters.isEmpty) {
    throw FormatException('VTT has no cues');
  }
  return chapters;
}

Duration _vttClock(RegExpMatch match, int hourGroup) {
  final hours = int.parse(match.group(hourGroup) ?? '0');
  final minutes = int.parse(match.group(hourGroup + 1)!);
  final seconds = int.parse(match.group(hourGroup + 2)!);
  final millis = int.parse(match.group(hourGroup + 3)!);
  return Duration(
    hours: hours,
    minutes: minutes,
    seconds: seconds,
    milliseconds: millis,
  );
}
