// dart run tool/disambiguation_report.dart
import 'dart:io';

import 'package:fiveminutekanji/data/hardcoded_kanji_repository.dart';

void main() async {
  const repo = HardcodedKanjiRepository();
  final cards = await repo.getAll();

  // Exact duplicate groups
  final byKw = <String, List<dynamic>>{};
  for (final c in cards) {
    byKw.putIfAbsent(c.keyword.toLowerCase(), () => []).add(c);
  }
  final dupes = byKw.entries.where((e) => e.value.length > 1).toList()
    ..sort((a, b) => a.key.compareTo(b.key));

  final dupIds = <String>{};
  for (final e in dupes) {
    for (final c in e.value) {
      dupIds.add(c.id as String);
    }
  }

  final similarOnly = cards
      .where((c) => c.disambiguation != null && !dupIds.contains(c.id))
      .toList();

  // Group similar-only by manual clusters (keyword proximity)
  stdout.writeln('SUMMARY');
  stdout.writeln('totalAnalyzed=${cards.length}');
  stdout.writeln(
    'withDisambiguation=${cards.where((c) => c.disambiguation != null).length}',
  );
  stdout.writeln('exactDuplicateGroups=${dupes.length}');
  stdout.writeln('similarConceptGroups=16');
  stdout.writeln('');
  stdout.writeln('=== Exact duplicate keyword groups ===');
  for (final e in dupes) {
    stdout.writeln('[${e.key}]');
    for (final c in e.value) {
      stdout.writeln(
        '  ${c.character} (${c.id}) keyword="${c.keyword}" hint="${c.disambiguation}"',
      );
    }
  }
  stdout.writeln('');
  stdout.writeln('=== Additional similar-concept groups ===');
  final clusterOrder = <Map<String, Object>>[
    {
      'name': 'earth / ground / soil / land',
      'ids': ['n5-034', 'n4-036', 'n1-0205', 'n2-349'],
    },
    {
      'name': 'origin / root / source',
      'ids': ['n4-015', 'n2-153', 'n1-0639'],
    },
    {'name': 'sea / ocean', 'ids': ['n4-094', 'n4-093']},
    {'name': 'person / people', 'ids': ['n5-011', 'n3-204']},
    {'name': 'study / learn', 'ids': ['n5-040', 'n4-123']},
    {'name': 'say / talk', 'ids': ['n4-133', 'n5-070']},
    {'name': 'road / path', 'ids': ['n4-149', 'n3-318']},
    {
      'name': 'spirit / spirits / soul',
      'ids': ['n5-058', 'n1-1176', 'n1-1212'],
    },
    {
      'name': 'beauty / lovely / beautiful',
      'ids': ['n3-274', 'n1-1228', 'n1-0479'],
    },
    {
      'name': 'see / inspection / outlook',
      'ids': ['n5-069', 'n1-0999', 'n3-296'],
    },
    {
      'name': 'evening / night',
      'ids': ['n4-041', 'n3-179', 'n4-043'],
    },
    {
      'name': 'parent / father / mother',
      'ids': ['n4-132', 'n5-061', 'n5-056'],
    },
    {'name': 'life / live', 'ids': ['n5-062', 'n4-010']},
    {
      'name': 'emotion / feelings',
      'ids': ['n3-146', 'n3-143', 'n1-0400'],
    },
    {
      'name': 'tree / woods / forest',
      'ids': ['n5-051', 'n2-145', 'n1-0527', 'n2-156'],
    },
    {'name': 'head / face', 'ids': ['n3-361', 'n3-363']},
  ];

  final cardById = {for (final c in cards) c.id: c};
  for (final cluster in clusterOrder) {
    final name = cluster['name']! as String;
    final ids = cluster['ids']! as List<String>;
    stdout.writeln('[$name]');
    for (final id in ids) {
      final c = cardById[id]!;
      stdout.writeln(
        '  ${c.character} ($id) keyword="${c.keyword}" hint="${c.disambiguation}"',
      );
    }
  }
}
