// dart run tool/apply_disambiguation.dart
import 'dart:convert';
import 'dart:io';

void main() {
  final hints = jsonDecode(
    File('tool/disambiguation_hints.json').readAsStringSync(),
  ) as Map<String, dynamic>;

  final path = 'lib/data/hardcoded_kanji_data.dart';
  var text = File(path).readAsStringSync();

  final cardPattern = RegExp(
    r"KanjiCard\(\s*id: '([^']+)',[\s\S]*?keyword: '((?:\\'|[^'])*)',",
    multiLine: true,
  );

  var applied = 0;
  var skipped = 0;
  text = text.replaceAllMapped(cardPattern, (match) {
    final id = match.group(1)!;
    final segment = match.group(0)!;
    if (segment.contains('disambiguation:')) {
      skipped++;
      return segment;
    }
    final hint = hints[id];
    if (hint == null) return segment;
    applied++;
    return '$segment\n    disambiguation: ${_dartString(hint as String)},';
  });

  File(path).writeAsStringSync(text);
  stderr.writeln('Applied $applied disambiguation hints (skipped $skipped existing).');
}

String _dartString(String s) => "'${s.replaceAll("'", r"\'")}'";
