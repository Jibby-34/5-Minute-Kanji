// dart run tool/export_dupe_ids.dart
import 'dart:convert';
import 'dart:io';

void main() {
  final text = File('lib/data/hardcoded_kanji_data.dart').readAsStringSync();
  final pattern = RegExp(
    r"KanjiCard\(\s*"
    r"id: '([^']+)',\s*"
    r"character: '([^']+)',\s*"
    r"meaning: '((?:\\'|[^'])*)',\s*"
    r"keyword: '((?:\\'|[^'])*)',",
    multiLine: true,
  );

  final cards = <Map<String, String>>[];
  for (final m in pattern.allMatches(text)) {
    cards.add({
      'id': m.group(1)!,
      'character': m.group(2)!,
      'meaning': m.group(3)!.replaceAll(r"\'", "'"),
      'keyword': m.group(4)!.replaceAll(r"\'", "'"),
    });
  }

  final byKw = <String, List<Map<String, String>>>{};
  for (final c in cards) {
    byKw.putIfAbsent(c['keyword']!, () => []).add(c);
  }

  final dupes = byKw.entries.where((e) => e.value.length > 1).toList()
    ..sort((a, b) => a.key.compareTo(b.key));

  final flat = <Map<String, String>>[];
  for (final e in dupes) {
    for (final c in e.value) {
      flat.add({...c, 'groupKeyword': e.key});
    }
  }

  File('tool/dupe_cards.json').writeAsStringSync(
    const JsonEncoder.withIndent('  ').convert(flat),
  );
  stderr.writeln('Wrote ${flat.length} cards to tool/dupe_cards.json');
}
