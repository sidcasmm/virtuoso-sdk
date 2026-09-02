import 'dart:convert';
import 'dart:io';

/// JPEG/WebP grid plus JSON metadata that describes tile timing.
final class SpriteSheet {
  const SpriteSheet({
    required this.spriteUrl,
    required this.metadataUrl,
    this.headers,
  });

  final Uri spriteUrl;
  final Uri metadataUrl;
  final Map<String, String>? headers;

  @override
  bool operator ==(Object other) =>
      other is SpriteSheet &&
      spriteUrl == other.spriteUrl &&
      metadataUrl == other.metadataUrl &&
      _sameHeaders(headers, other.headers);

  @override
  int get hashCode =>
      Object.hash(spriteUrl, metadataUrl, Object.hashAll(_pairs));

  Iterable<String> get _pairs {
    if (headers == null) {
      return const [];
    }
    final keys = headers!.keys.toList()..sort();
    return keys.map((key) => '$key=${headers![key]}');
  }

  static bool _sameHeaders(Map<String, String>? a, Map<String, String>? b) {
    if (identical(a, b)) {
      return true;
    }
    if (a == null || b == null || a.length != b.length) {
      return a == b;
    }
    for (final entry in a.entries) {
      if (b[entry.key] != entry.value) {
        return false;
      }
    }
    return true;
  }
}

/// One seek-preview tile. The app crops [image] to [x]/[y]/[width]/[height].
final class SpriteCue {
  const SpriteCue({
    required this.start,
    required this.end,
    required this.image,
    required this.x,
    required this.y,
    required this.width,
    required this.height,
  });

  final Duration start;
  final Duration end;
  final Uri image;
  final int x;
  final int y;
  final int width;
  final int height;

  @override
  bool operator ==(Object other) =>
      other is SpriteCue &&
      start == other.start &&
      end == other.end &&
      image == other.image &&
      x == other.x &&
      y == other.y &&
      width == other.width &&
      height == other.height;

  @override
  int get hashCode => Object.hash(start, end, image, x, y, width, height);
}

typedef SpriteMetadataFetcher = Future<String> Function(
  Uri uri, {
  Map<String, String>? headers,
});

final _timing = RegExp(
  r'^(?:(\d{2,}):)?(\d{2}):(\d{2})[.,](\d{3})\s+-->\s+'
  r'(?:(\d{2,}):)?(\d{2}):(\d{2})[.,](\d{3})',
);

final _xywh = RegExp(r'#xywh=(\d+),(\d+),(\d+),(\d+)\s*$');

List<SpriteCue> parseSpriteCuesFromVtt(String vtt, {Uri? base}) {
  final text = vtt.trimLeft();
  if (text.isEmpty) {
    throw const FormatException('VTT is empty');
  }
  final lines = text.split(RegExp(r'\r\n|\n|\r'));
  var i = 0;
  if (lines[i].startsWith('WEBVTT')) {
    i++;
  }
  final cues = <SpriteCue>[];
  while (i < lines.length) {
    var line = lines[i].trim();
    if (line.isEmpty || line.startsWith('NOTE')) {
      i++;
      continue;
    }
    var timing = _timing.firstMatch(line);
    if (timing == null) {
      i++;
      if (i >= lines.length) {
        throw const FormatException('VTT cue is missing a timing line');
      }
      timing = _timing.firstMatch(lines[i].trim());
      if (timing == null) {
        throw const FormatException('VTT cue is missing a timing line');
      }
    }
    i++;
    final body = <String>[];
    while (i < lines.length && lines[i].trim().isNotEmpty) {
      body.add(lines[i].trim());
      i++;
    }
    final payload = body.join('');
    final xywh = _xywh.firstMatch(payload);
    if (xywh == null) {
      throw const FormatException('VTT cue is missing #xywh=x,y,w,h');
    }
    final imagePart = payload.substring(0, xywh.start).trim();
    if (imagePart.isEmpty) {
      throw const FormatException('VTT cue is missing an image URL');
    }
    final image = base == null ? Uri.parse(imagePart) : base.resolve(imagePart);
    final start = _vttClock(timing, 1);
    final end = _vttClock(timing, 5);
    if (end <= start) {
      throw FormatException('VTT cue end must be after start');
    }
    cues.add(
      SpriteCue(
        start: start,
        end: end,
        image: image,
        x: int.parse(xywh.group(1)!),
        y: int.parse(xywh.group(2)!),
        width: int.parse(xywh.group(3)!),
        height: int.parse(xywh.group(4)!),
      ),
    );
  }
  if (cues.isEmpty) {
    throw const FormatException('VTT has no cues');
  }
  return cues;
}

List<SpriteCue> parseSpriteCuesFromGridJson(
  String json, {
  required Uri spriteUrl,
}) {
  return parseSpriteCuesFromJson(json, spriteUrl: spriteUrl);
}

/// Uniform grid JSON: `tileWidth`, `tileHeight`, `columns`, `rows`,
/// `intervalMs`. Optional `url` when [spriteUrl] is omitted.
List<SpriteCue> parseSpriteCuesFromJson(
  String json, {
  Uri? spriteUrl,
  Uri? base,
}) {
  final map = decodeSpriteGridJson(json);
  return spriteCuesFromGrid(
    spriteUrl: spriteUrl ?? _spriteImageUrl(map, base),
    tileWidth: _jsonInt(map, 'tileWidth'),
    tileHeight: _jsonInt(map, 'tileHeight'),
    columns: _jsonInt(map, 'columns'),
    rows: _jsonInt(map, 'rows'),
    intervalMs: _jsonInt(map, 'intervalMs'),
    count: map.containsKey('count') ? _jsonInt(map, 'count') : null,
  );
}

Map<String, dynamic> decodeSpriteGridJson(String json) {
  final decoded = jsonDecode(json);
  if (decoded is! Map) {
    throw const FormatException('sprite JSON must be an object');
  }
  return decoded.cast<String, dynamic>();
}

List<SpriteCue> spriteCuesFromGrid({
  required Uri spriteUrl,
  required int tileWidth,
  required int tileHeight,
  required int columns,
  required int rows,
  required int intervalMs,
  int? count,
}) {
  if (tileWidth <= 0 || tileHeight <= 0) {
    throw ArgumentError('tileWidth and tileHeight must be > 0');
  }
  if (columns <= 0 || rows <= 0) {
    throw ArgumentError('columns and rows must be > 0');
  }
  if (intervalMs <= 0) {
    throw ArgumentError.value(intervalMs, 'intervalMs', 'must be > 0');
  }
  final total = columns * rows;
  final tiles = count ?? total;
  if (tiles <= 0 || tiles > total) {
    throw ArgumentError.value(tiles, 'count', 'must be 1..columns*rows');
  }
  final cues = <SpriteCue>[];
  for (var i = 0; i < tiles; i++) {
    final col = i % columns;
    final row = i ~/ columns;
    cues.add(
      SpriteCue(
        start: Duration(milliseconds: i * intervalMs),
        end: Duration(milliseconds: (i + 1) * intervalMs),
        image: spriteUrl,
        x: col * tileWidth,
        y: row * tileHeight,
        width: tileWidth,
        height: tileHeight,
      ),
    );
  }
  return cues;
}

Future<String> fetchSpriteMetadata(
  Uri uri, {
  Map<String, String>? headers,
}) async {
  if (uri.scheme != 'http' && uri.scheme != 'https') {
    throw ArgumentError.value(
      uri,
      'uri',
      'only http and https URIs are supported',
    );
  }
  final client = HttpClient();
  try {
    final request = await client.getUrl(uri);
    headers?.forEach(request.headers.set);
    final response = await request.close();
    final body = await utf8.decodeStream(response);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw HttpException(
        'sprite metadata HTTP ${response.statusCode}',
        uri: uri,
      );
    }
    return body;
  } finally {
    client.close(force: true);
  }
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

Uri _spriteImageUrl(Map<String, dynamic> map, Uri? base) {
  final urlRaw = map['url'];
  if (urlRaw is! String || urlRaw.isEmpty) {
    throw const FormatException('sprite JSON missing "url"');
  }
  final parsed = Uri.parse(urlRaw);
  if (parsed.hasScheme || base == null) {
    return parsed;
  }
  return base.resolve(urlRaw);
}

int _jsonInt(Map<String, dynamic> map, String key) {
  final value = map[key];
  if (value is int) {
    return value;
  }
  if (value is num) {
    return value.toInt();
  }
  throw FormatException('sprite JSON missing int "$key"');
}
