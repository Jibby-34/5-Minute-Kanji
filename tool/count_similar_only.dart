import 'package:fiveminutekanji/data/hardcoded_kanji_repository.dart';

void main() async {
  const repo = HardcodedKanjiRepository();
  final cards = await repo.getAll();
  final byKw = <String, List<dynamic>>{};
  for (final c in cards) {
    byKw.putIfAbsent(c.keyword.toLowerCase(), () => []).add(c);
  }
  final dupIds = <String>{};
  for (final e in byKw.entries.where((e) => e.value.length > 1)) {
    for (final c in e.value) dupIds.add(c.id as String);
  }
  final only = cards
      .where((c) => c.disambiguation != null && !dupIds.contains(c.id))
      .toList();
  print('similar-only hints: ${only.length}');
  for (final c in only) {
    print('${c.id} ${c.character} ${c.keyword} -> ${c.disambiguation}');
  }
}
