import 'package:flutter_test/flutter_test.dart';
import 'package:fiveminutekanji/core/models/card_schedule.dart';
import 'package:fiveminutekanji/core/models/kanji_card.dart';
import 'package:fiveminutekanji/core/models/kanji_status.dart';
import 'package:fiveminutekanji/features/kanji_list/kanji_list_controller.dart';
import 'package:fiveminutekanji/services/initial_known_card_schedule.dart';

import 'support/fakes.dart';

void main() {
  final now = DateTime(2026, 9, 2, 8);
  final cards = [
    testCard('a', keyword: 'one', character: '一'),
    testCard('b', keyword: 'two', character: '二'),
    testCard('c', keyword: 'person', character: '人'),
  ];

  test('maps schedules onto not encountered, learning, and mastered', () async {
    final progress = MemoryProgressRepository(
      schedules: {
        'a': CardSchedule.fresh('a', now),
        'b': CardSchedule(
          cardId: 'b',
          state: CardLearningState.review,
          reviewCount: 1,
          correctCount: 1,
          incorrectCount: 0,
          dueAt: now,
          interval: const Duration(days: 1),
          ease: 2.5,
          consecutiveGoodCount: 1,
        ),
        'c': CardSchedule(
          cardId: 'c',
          state: CardLearningState.review,
          reviewCount: 3,
          correctCount: 3,
          incorrectCount: 0,
          dueAt: now,
          interval: const Duration(days: 1),
          ease: 2.5,
          consecutiveGoodCount: 3,
        ),
      },
    );
    final controller = KanjiListController(
      kanjiRepository: FakeKanjiRepository(cards),
      progressRepository: progress,
    );

    await controller.load();

    expect(controller.loading, isFalse);
    expect(controller.items.map((item) => item.card.id), ['a', 'b', 'c']);
    expect(controller.items[0].status, KanjiProgressStatus.notEncountered);
    expect(controller.items[1].status, KanjiProgressStatus.learning);
    expect(controller.items[2].status, KanjiProgressStatus.mastered);
  });

  test('selects only new kanji and clears after marking as known', () async {
    final progress = MemoryProgressRepository(
      schedules: {
        'a': CardSchedule.fresh('a', now),
        'b': CardSchedule(
          cardId: 'b',
          state: CardLearningState.review,
          reviewCount: 1,
          correctCount: 1,
          incorrectCount: 0,
          dueAt: now,
          interval: const Duration(days: 1),
          ease: 2.5,
          consecutiveGoodCount: 1,
        ),
        'c': CardSchedule.fresh('c', now),
      },
    );
    final controller = KanjiListController(
      kanjiRepository: FakeKanjiRepository(cards),
      progressRepository: progress,
    );
    await controller.load();

    controller.enterSelection();
    controller.toggleSelected('a');
    controller.toggleSelected('b');
    controller.toggleSelected('c');
    expect(controller.selectedIds, {'a', 'c'});

    controller.toggleSelected('a');
    expect(controller.selectedIds, {'c'});

    controller.selectAllNew();
    expect(controller.selectedIds, {'a', 'c'});

    controller.clearSelection();
    expect(controller.selectedIds, isEmpty);

    controller.selectAllNew();
    await controller.markSelectedAsKnown(now: now);

    expect(controller.selecting, isFalse);
    expect(controller.selectedIds, isEmpty);
    expect(controller.items[0].status, KanjiProgressStatus.learning);
    expect(controller.items[1].status, KanjiProgressStatus.learning);
    expect(controller.items[2].status, KanjiProgressStatus.learning);
    expect(progress.schedules['b']!.reviewCount, 1);
    expect(
      progress.schedules['a']!.interval,
      calculateInitialKnownCardSchedule('a'),
    );
    expect(progress.schedules['a']!.dueAt.isAfter(now), isTrue);

    final dueBeforeReload = progress.schedules['a']!.dueAt;
    await controller.load(showLoading: false);
    expect(progress.schedules['a']!.dueAt, dueBeforeReload);
    expect(
      progress.schedules['a']!.interval,
      calculateInitialKnownCardSchedule('a'),
    );
  });

  test('groups kanji into JLPT sections without changing status', () async {
    final mixed = [
      testCard('n5', character: '日', jlptLevel: JlptLevel.n5),
      testCard('n3', character: '議', jlptLevel: JlptLevel.n3),
      testCard('none', character: '龍'),
      testCard('n1', character: '憂', jlptLevel: JlptLevel.n1),
      testCard('n4', character: '堂', jlptLevel: JlptLevel.n4),
      testCard('n2', character: '績', jlptLevel: JlptLevel.n2),
      testCard('n5b', character: '人', jlptLevel: JlptLevel.n5),
    ];
    final progress = MemoryProgressRepository(
      schedules: {
        'n5': CardSchedule.fresh('n5', now),
        'n3': CardSchedule(
          cardId: 'n3',
          state: CardLearningState.review,
          reviewCount: 1,
          correctCount: 1,
          incorrectCount: 0,
          dueAt: now,
          interval: const Duration(days: 1),
          ease: 2.5,
          consecutiveGoodCount: 1,
        ),
        'none': CardSchedule(
          cardId: 'none',
          state: CardLearningState.review,
          reviewCount: 3,
          correctCount: 3,
          incorrectCount: 0,
          dueAt: now,
          interval: const Duration(days: 1),
          ease: 2.5,
          consecutiveGoodCount: 3,
        ),
        'n1': CardSchedule.fresh('n1', now),
        'n4': CardSchedule.fresh('n4', now),
        'n2': CardSchedule.fresh('n2', now),
        'n5b': CardSchedule.fresh('n5b', now),
      },
    );
    final controller = KanjiListController(
      kanjiRepository: FakeKanjiRepository(mixed),
      progressRepository: progress,
    );

    await controller.load();

    expect(
      controller.sections.map((section) => section.level),
      JlptLevel.sectionOrder,
    );
    expect(controller.sections.map((section) => section.level.sectionTitle), [
      'JLPT N5',
      'JLPT N4',
      'JLPT N3',
      'JLPT N2',
      'JLPT N1',
      'No JLPT Level',
    ]);
    expect(controller.sections[0].items.map((item) => item.card.character), [
      '日',
      '人',
    ]);
    expect(controller.sections[1].items.map((item) => item.card.character), [
      '堂',
    ]);
    expect(controller.sections[2].items.map((item) => item.card.character), [
      '議',
    ]);
    expect(controller.sections[3].items.map((item) => item.card.character), [
      '績',
    ]);
    expect(controller.sections[4].items.map((item) => item.card.character), [
      '憂',
    ]);
    expect(controller.sections[5].items.map((item) => item.card.character), [
      '龍',
    ]);
    expect(
      controller.sections[0].items[0].status,
      KanjiProgressStatus.notEncountered,
    );
    expect(
      controller.sections[2].items[0].status,
      KanjiProgressStatus.learning,
    );
    expect(
      controller.sections[5].items[0].status,
      KanjiProgressStatus.mastered,
    );
    expect(progress.schedules['n3']!.reviewCount, 1);
    expect(progress.schedules['none']!.consecutiveGoodCount, 3);
  });

  test('omits JLPT sections that have no kanji', () {
    final sections = groupKanjiByJlpt([
      KanjiListItem(
        card: testCard('n5', character: '日', jlptLevel: JlptLevel.n5),
        schedule: null,
        status: KanjiProgressStatus.notEncountered,
      ),
      KanjiListItem(
        card: testCard('n3', character: '議', jlptLevel: JlptLevel.n3),
        schedule: null,
        status: KanjiProgressStatus.notEncountered,
      ),
    ]);

    expect(sections.map((section) => section.level), [
      JlptLevel.n5,
      JlptLevel.n3,
    ]);
    expect(sections[0].items, hasLength(1));
    expect(sections[1].items, hasLength(1));
  });

  test('mark as known still works when cards sit in JLPT sections', () async {
    final mixed = [
      testCard('n5', character: '日', jlptLevel: JlptLevel.n5),
      testCard('none', character: '龍'),
    ];
    final progress = MemoryProgressRepository(
      schedules: {
        'n5': CardSchedule.fresh('n5', now),
        'none': CardSchedule.fresh('none', now),
      },
    );
    final controller = KanjiListController(
      kanjiRepository: FakeKanjiRepository(mixed),
      progressRepository: progress,
    );
    await controller.load();

    controller.enterSelection();
    controller.selectAllNew();
    await controller.markSelectedAsKnown(now: now);

    expect(controller.items[0].status, KanjiProgressStatus.learning);
    expect(controller.items[1].status, KanjiProgressStatus.learning);
    expect(
      controller.sections[0].items.single.status,
      KanjiProgressStatus.learning,
    );
    expect(
      controller.sections[1].items.single.status,
      KanjiProgressStatus.learning,
    );
    expect(
      progress.schedules['n5']!.interval,
      calculateInitialKnownCardSchedule('n5'),
    );
    expect(
      progress.schedules['none']!.interval,
      calculateInitialKnownCardSchedule('none'),
    );
  });
}
