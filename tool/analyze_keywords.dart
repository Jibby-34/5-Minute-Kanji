// dart run tool/analyze_keywords.dart
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

  stdout.writeln('Total cards parsed: ${cards.length}');

  final byKw = <String, List<Map<String, String>>>{};
  for (final c in cards) {
    final k = c['keyword']!.toLowerCase().trim();
    byKw.putIfAbsent(k, () => []).add(c);
  }

  final dupes = byKw.entries.where((e) => e.value.length > 1).toList()
    ..sort((a, b) => b.value.length.compareTo(a.value.length));

  stdout.writeln('Exact duplicate keyword groups: ${dupes.length}');
  stdout.writeln(
    'Cards in duplicate groups: ${dupes.fold<int>(0, (s, e) => s + e.value.length)}',
  );
  stdout.writeln('');

  for (final e in dupes) {
    final entries = e.value;
    stdout.writeln('[${entries.length}] keyword=${entries.first['keyword']}');
    for (final card in entries) {
      stdout.writeln(
        "    ${card['id']} ${card['character']} meaning=${card['meaning']}",
      );
    }
    stdout.writeln('');
  }
}
