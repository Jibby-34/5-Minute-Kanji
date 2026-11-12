// dart run tool/find_indistinct.dart
import 'package:fiveminutekanji/data/hardcoded_kanji_repository.dart';

void main() async {
  const repo = HardcodedKanjiRepository();
  final cards = await repo.getAll();
  final byKw = <String, List<dynamic>>{};
  for (final c in cards) {
    byKw.putIfAbsent(c.keyword.toLowerCase(), () => []).add(c);
  }
  for (final e in byKw.entries.where((e) => e.value.length > 1)) {
    final hintsInGroup = e.value
        .map((c) => c.disambiguation as String?)
        .whereType<String>()
        .toList();
    if (hintsInGroup.length != e.value.length) continue;
    if (hintsInGroup.toSet().length != hintsInGroup.length) {
      for (final c in e.value) {
        print('${c.id} ${c.character} ${c.disambiguation}');
      }
      print('keyword: ${e.key}\n');
    }
  }
}
