// Downloads KanjiVG and writes stroke JSON for kanji in this app's dataset.
//
// Re-run after a KanjiVG release. Application code does not need to change.
//
//   dart run tool/import_kanjivg.dart

import 'dart:convert';
import 'dart:io';

const kanjiVgRelease = 'r20250816';
const kanjiVgZipName = 'kanjivg-20250816-main.zip';
const kanjiVgZipUrl =
    'https://github.com/KanjiVG/kanjivg/releases/download/$kanjiVgRelease/$kanjiVgZipName';
const kanjiVgCopyingUrl =
    'https://raw.githubusercontent.com/KanjiVG/kanjivg/master/COPYING';
const kanjiVgSite = 'https://kanjivg.tagaini.net';
const kanjiVgLicense = 'Creative Commons Attribution-Share Alike 3.0';

final characterPattern = RegExp(r"character:\s*'(.+?)'");
final strokeIdPattern = RegExp(r'-s(\d+)$');
final matrixPattern = RegExp(
  r'matrix\(\s*([-\d.eE]+)\s+([-\d.eE]+)\s+([-\d.eE]+)\s+([-\d.eE]+)\s+([-\d.eE]+)\s+([-\d.eE]+)\s*\)',
);
final translatePattern = RegExp(
  r'translate\(\s*([-\d.eE]+)(?:\s*[,\s]\s*([-\d.eE]+))?\s*\)',
);
final pathPattern = RegExp(r'<path\b([^>]*)/?>');
final textPattern = RegExp(r'<text\b([^>]*)>([^<]*)</text>');
final attributePattern = RegExp(r'''([:\w]+)\s*=\s*("([^"]*)"|'([^']*)')''');
final viewBoxPattern = RegExp(r'''viewBox\s*=\s*("([^"]*)"|'([^']*)')''');

Future<void> main() async {
  final dataFile = File('lib/data/hardcoded_kanji_data.dart');
  if (!dataFile.existsSync()) {
    stderr.writeln('Run this script from the repository root.');
    exitCode = 1;
    return;
  }

  final characters = readDatasetCharacters(await dataFile.readAsString());
  stdout.writeln('Dataset contains ${characters.length} unique kanji');

  final cacheDir = Directory('tool/.cache');
  final zipFile = File('${cacheDir.path}/$kanjiVgZipName');
  if (!zipFile.existsSync()) {
    await download(kanjiVgZipUrl, zipFile);
  } else {
    stdout.writeln('Using cached archive ${zipFile.path}');
  }

  final thirdParty = Directory('third_party/kanjivg');
  final copyingFile = File('${thirdParty.path}/COPYING');
  if (!copyingFile.existsSync()) {
    await download(kanjiVgCopyingUrl, copyingFile);
  }
  await File('${thirdParty.path}/NOTICE').writeAsString(noticeText());

  final extractDir = Directory('${cacheDir.path}/kanjivg-extract');
  if (extractDir.existsSync()) {
    extractDir.deleteSync(recursive: true);
  }
  extractDir.createSync(recursive: true);
  final extract = await Process.run('tar', [
    '-xf',
    zipFile.path,
    '-C',
    extractDir.path,
  ]);
  if (extract.exitCode != 0) {
    stderr.writeln(extract.stderr);
    stderr.writeln('Failed to extract ${zipFile.path}');
    exitCode = 1;
    return;
  }

  final svgByHex = <String, File>{};
  await for (final entity in extractDir.list(recursive: true)) {
    if (entity is! File || !entity.path.toLowerCase().endsWith('.svg')) {
      continue;
    }
    final name = entity.uri.pathSegments.last;
    final hex = name.substring(0, name.length - 4).toLowerCase();
    final parent = entity.parent.path.replaceAll('\\', '/');
    if (parent.endsWith('/kanji') || !svgByHex.containsKey(hex)) {
      svgByHex[hex] = entity;
    }
  }

  final outputDir = Directory('assets/kanji/strokes');
  if (outputDir.existsSync()) {
    for (final file in outputDir.listSync()) {
      if (file is File && file.path.endsWith('.json')) {
        file.deleteSync();
      }
    }
  } else {
    outputDir.createSync(recursive: true);
  }

  var imported = 0;
  final missing = <String>[];
  for (final glyph in characters) {
    final hex = unicodeHex(glyph);
    final svgFile = svgByHex[hex];
    if (svgFile == null) {
      stdout.writeln('MISSING  $glyph  $hex.svg');
      missing.add(glyph);
      continue;
    }
    try {
      final payload = extractStrokeData(svgFile.readAsStringSync(), glyph);
      File(
        '${outputDir.path}/$hex.json',
      ).writeAsStringSync(jsonEncode(payload));
      imported++;
    } catch (error) {
      stdout.writeln('FAILED   $glyph  $hex.svg  ($error)');
      missing.add(glyph);
    }
  }

  await File(
    'assets/kanji/SOURCE.md',
  ).writeAsString(sourceMarkdown(imported: imported, missing: missing));
  stdout.writeln('Wrote $imported stroke files to ${outputDir.path}');
  if (missing.isEmpty) {
    stdout.writeln('All dataset kanji have KanjiVG stroke data.');
  } else {
    stdout.writeln('${missing.length} kanji missing from KanjiVG:');
    for (final glyph in missing) {
      final code = glyph.runes.first
          .toRadixString(16)
          .toUpperCase()
          .padLeft(4, '0');
      stdout.writeln('  $glyph U+$code');
    }
  }
}

List<String> readDatasetCharacters(String source) {
  final characters = <String>[];
  final seen = <String>{};
  for (final match in characterPattern.allMatches(source)) {
    final glyph = match.group(1)!;
    if (seen.add(glyph)) {
      characters.add(glyph);
    }
  }
  return characters;
}

String unicodeHex(String character) {
  return character.runes.first.toRadixString(16).padLeft(5, '0');
}

Future<void> download(String url, File dest) async {
  dest.parent.createSync(recursive: true);
  stdout.writeln('Downloading $url');
  final client = HttpClient();
  try {
    final request = await client.getUrl(Uri.parse(url));
    request.followRedirects = true;
    final response = await request.close();
    if (response.statusCode >= 400) {
      throw HttpException('HTTP ${response.statusCode} for $url');
    }
    await response.pipe(dest.openWrite());
    stdout.writeln('Saved ${dest.path} (${dest.lengthSync()} bytes)');
  } finally {
    client.close();
  }
}

Map<String, String> parseAttributes(String raw) {
  final attributes = <String, String>{};
  for (final match in attributePattern.allMatches(raw)) {
    attributes[match.group(1)!] = match.group(3) ?? match.group(4) ?? '';
  }
  return attributes;
}

List<double>? parseNumberPosition(String? transform) {
  if (transform == null || transform.isEmpty) return null;
  final matrix = matrixPattern.firstMatch(transform);
  if (matrix != null) {
    return [double.parse(matrix.group(5)!), double.parse(matrix.group(6)!)];
  }
  final translate = translatePattern.firstMatch(transform);
  if (translate != null) {
    return [
      double.parse(translate.group(1)!),
      double.parse(translate.group(2) ?? '0'),
    ];
  }
  return null;
}

Map<String, Object> extractStrokeData(String svgText, String character) {
  final hexId = unicodeHex(character);
  final pathsStart = svgText.indexOf('kvg:StrokePaths');
  final numbersStart = svgText.indexOf('kvg:StrokeNumbers');
  final pathsSection = pathsStart >= 0
      ? svgText.substring(pathsStart, numbersStart >= 0 ? numbersStart : null)
      : svgText;

  final indexed = <({int index, String d})>[];
  for (final match in pathPattern.allMatches(pathsSection)) {
    final attributes = parseAttributes(match.group(1)!);
    final d = attributes['d'];
    if (d == null || d.isEmpty) continue;
    final id = attributes['id'] ?? '';
    final strokeMatch = strokeIdPattern.firstMatch(id);
    indexed.add((
      index: strokeMatch == null
          ? indexed.length + 1
          : int.parse(strokeMatch.group(1)!),
      d: d,
    ));
  }
  indexed.sort((a, b) => a.index.compareTo(b.index));
  if (indexed.isEmpty) {
    throw StateError('no stroke paths');
  }

  final numbers = <int, List<double>>{};
  if (numbersStart >= 0) {
    for (final match in textPattern.allMatches(
      svgText.substring(numbersStart),
    )) {
      final label = match.group(2)!.trim();
      final index = int.tryParse(label);
      if (index == null) continue;
      final attributes = parseAttributes(match.group(1)!);
      final position = parseNumberPosition(attributes['transform']);
      if (position != null) {
        numbers[index] = [
          double.parse(position[0].toStringAsFixed(2)),
          double.parse(position[1].toStringAsFixed(2)),
        ];
      }
    }
  }

  final viewBoxMatch = viewBoxPattern.firstMatch(svgText);
  final viewBoxRaw =
      viewBoxMatch?.group(2) ?? viewBoxMatch?.group(3) ?? '0 0 109 109';
  final viewBox = [
    for (final part in viewBoxRaw.replaceAll(',', ' ').split(RegExp(r'\s+')))
      if (part.isNotEmpty) double.parse(part),
  ];

  return {
    'character': character,
    'unicode': hexId,
    'viewBox': viewBox.length == 4 ? viewBox : [0.0, 0.0, 109.0, 109.0],
    'strokes': [
      for (final stroke in indexed)
        {
          'd': stroke.d,
          if (numbers[stroke.index] != null) 'number': numbers[stroke.index],
        },
    ],
  };
}

String noticeText() {
  return '''
KanjiVG
Copyright © 2009-2026 Ulrich Apel

This product includes stroke-order data derived from KanjiVG
($kanjiVgSite), released under the $kanjiVgLicense license.

The JSON files in assets/kanji/strokes/ are an adaptation of KanjiVG SVG
data and are therefore also licensed under CC BY-SA 3.0.

Full license text: COPYING
''';
}

String sourceMarkdown({required int imported, required List<String> missing}) {
  final missingLines = missing.isEmpty
      ? 'None.'
      : missing
            .map((glyph) {
              final code = glyph.runes.first
                  .toRadixString(16)
                  .toUpperCase()
                  .padLeft(4, '0');
              return '- $glyph (U+$code)';
            })
            .join('\n');

  return '''
# KanjiVG stroke data

Stroke-order assets in `assets/kanji/strokes/` are derived from [KanjiVG]($kanjiVgSite).

| Field | Value |
| --- | --- |
| Source | KanjiVG |
| Release | `$kanjiVgRelease` |
| Archive | `$kanjiVgZipName` |
| Download | $kanjiVgZipUrl |
| License | $kanjiVgLicense |
| Copyright | © 2009–2026 Ulrich Apel |
| Imported kanji | $imported |
| Missing kanji | ${missing.length} |

The JSON files are an adaptation of the KanjiVG SVG stroke paths for the kanji
currently included in this app. They are **not** the full KanjiVG repository.

To refresh the data after a new KanjiVG release, update the constants at the
top of `tool/import_kanjivg.dart` if needed and run:

```
dart run tool/import_kanjivg.dart
```

A Python equivalent lives at `tool/import_kanjivg.py`.

Missing from this KanjiVG release:

$missingLines

See `third_party/kanjivg/` for the license text and attribution notice.
''';
}
