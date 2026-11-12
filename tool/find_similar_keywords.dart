// dart run tool/find_similar_keywords.dart
import 'dart:io';

void main() {
  final text = File('lib/data/hardcoded_kanji_data.dart').readAsStringSync();
  final pattern = RegExp(
    r"id: '([^']+)',\s*"
    r"character: '([^']+)',\s*"
    r"meaning: '((?:\\'|[^'])*)',\s*"
    r"keyword: '((?:\\'|[^'])*)',",
    multiLine: true,
  );

  final cards = <({String id, String char, String kw})>[];
  for (final m in pattern.allMatches(text)) {
    cards.add((
      id: m.group(1)!,
      char: m.group(2)!,
      kw: m.group(4)!.replaceAll(r"\'", "'").toLowerCase(),
    ));
  }

  // Pairs of keywords that are semantically confusable (curated seed + expansion).
  const similarPairs = <List<String>>[
    ['earth', 'ground', 'soil', 'land'],
    ['origin', 'root', 'source'],
    ['sea', 'ocean'],
    ['river'],
    ['person', 'people', 'human'],
    ['study', 'learn'],
    ['say', 'talk', 'speak', 'words'],
    ['road', 'path', 'way'],
    ['spirit', 'spirits', 'soul'],
    ['beauty', 'lovely', 'beautiful'],
    ['see', 'look', 'watch', 'inspection', 'outlook'],
    ['shop', 'store'],
    ['evening', 'night'],
    ['parent', 'father', 'mother'],
    ['inside', 'outside'],
    ['left', 'right'],
    ['life', 'live'],
    ['death', 'die'],
    ['buy', 'sell'],
    ['new', 'old', 'young'],
    ['man', 'woman'],
    ['hand', 'foot'],
    ['eye', 'ear'],
    ['head', 'face'],
    ['heart', 'mind'],
    ['good', 'bad'],
    ['love', 'hate'],
    ['war', 'peace'],
    ['many', 'few', 'all', 'every'],
    ['same', 'different', 'other'],
    ['time', 'day', 'hour'],
    ['east', 'west', 'north', 'south'],
    ['up', 'down'],
    ['work', 'job'],
    ['write', 'read'],
    ['tree', 'woods', 'forest'],
    ['fire', 'water'],
    ['spring'], // season vs water in dupes
    ['world'],
    ['thing', 'matter', 'object'],
    ['idea', 'thought'],
    ['feelings', 'emotion'],
    ['exist'],
    ['place', 'location'],
    ['medicine', 'drug'],
    ['meeting', 'meet'],
    ['return', 're-'],
  ];

  final kwToCards = <String, List<({String id, String char, String kw})>>{};
  for (final c in cards) {
    kwToCards.putIfAbsent(c.kw, () => []).add(c);
  }

  final seenGroups = <String>{};
  for (final cluster in similarPairs) {
    final groupCards = <({String id, String char, String kw})>[];
    for (final kw in cluster) {
      groupCards.addAll(kwToCards[kw] ?? []);
    }
    if (groupCards.length < 2) continue;
    final key = groupCards.map((c) => c.id).toList()..sort();
    final groupKey = key.join(',');
    if (seenGroups.contains(groupKey)) continue;
    seenGroups.add(groupKey);

    // Only report if spans multiple keywords or multiple chars with same kw
    final keywords = groupCards.map((c) => c.kw).toSet();
    if (keywords.length < 2 && groupCards.length < 2) continue;

    stdout.writeln('--- cluster: ${cluster.join(' / ')} (${groupCards.length} cards) ---');
    for (final c in groupCards) {
      stdout.writeln('  ${c.id} ${c.char} keyword=${c.kw}');
    }
    stdout.writeln('');
  }
}
