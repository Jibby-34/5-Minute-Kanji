// dart run tool/validate_disambiguation.dart
import 'dart:convert';
import 'dart:io';

import 'package:fiveminutekanji/data/hardcoded_kanji_repository.dart';

void main() async {
  final hints = jsonDecode(
    File('tool/disambiguation_hints.json').readAsStringSync(),
  ) as Map<String, dynamic>;

  const repo = HardcodedKanjiRepository();
  final cards = await repo.getAll();
  stdout.writeln('Total kanji: ${cards.length}');

  var withHint = 0;
  final hintMismatch = <String>[];

  for (final card in cards) {
    if (card.disambiguation != null) withHint++;
    final expected = hints[card.id];
    if (expected != null && card.disambiguation != expected) {
      hintMismatch.add(card.id);
    }
    if (expected == null && card.disambiguation != null) {
      hintMismatch.add('${card.id} unexpected hint');
    }
  }
  stdout.writeln('Cards with disambiguation: $withHint');

  // Exact duplicate keyword groups
  final byKw = <String, List<dynamic>>{};
  for (final c in cards) {
    byKw.putIfAbsent(c.keyword.toLowerCase(), () => []).add(c);
  }
  final dupes = byKw.entries.where((e) => e.value.length > 1).toList();
  stdout.writeln('Exact duplicate keyword groups: ${dupes.length}');

  var dupeMissing = 0;
  for (final e in dupes) {
    for (final c in e.value) {
      if (c.disambiguation == null) dupeMissing++;
    }
  }
  stdout.writeln('Duplicate-group cards missing hint: $dupeMissing');

  // Hints unique within each duplicate group
  var indistinct = 0;
  for (final e in dupes) {
    final hintsInGroup = e.value
        .map((c) => c.disambiguation as String?)
        .whereType<String>()
        .toList();
    if (hintsInGroup.length != e.value.length) continue;
    if (hintsInGroup.toSet().length != hintsInGroup.length) indistinct++;
  }
  stdout.writeln('Duplicate groups with indistinct hints: $indistinct');

  if (hintMismatch.isNotEmpty) {
    stdout.writeln('Hint mismatches: ${hintMismatch.length}');
    exitCode = 1;
  }
  if (dupeMissing > 0 || indistinct > 0) exitCode = 1;
}
