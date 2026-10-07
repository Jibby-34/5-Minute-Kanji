import 'package:flutter_test/flutter_test.dart';
import 'package:fiveminutekanji/core/models/card_schedule.dart';
import 'package:fiveminutekanji/core/models/curriculum_mode.dart';
import 'package:fiveminutekanji/core/models/kanji_card.dart';
import 'package:fiveminutekanji/core/models/progress.dart';
import 'package:fiveminutekanji/core/models/review.dart';
import 'package:fiveminutekanji/data/hardcoded_kanji_data.dart';
import 'package:fiveminutekanji/services/curriculum_priority_service.dart';
import 'package:fiveminutekanji/services/daily_workload.dart';
import 'package:fiveminutekanji/services/due_card_selector.dart';
import 'package:fiveminutekanji/services/srs_engine.dart';

import 'support/fakes.dart';

void main() {
  final now = DateTime(2026, 9, 2, 8);

  KanjiCard card(
    String id, {
    required String character,
    required int frequency,
    required int difficulty,
    required JlptLevel level,
    List<String> components = const [],
  }) {
    return testCard(
      id,
      character: character,
      frequency: frequency,
      difficulty: difficulty,
      jlptLevel: level,
      components: components,
    );
  }

  group('frequency', () {
    test('lower ranks score higher across the catalog range', () {
      final service = CurriculumPriorityService(hardcodedKanjiCards);
      final most = service.frequencyScoreFor(1);
      final middle = service.frequencyScoreFor(1000);
      final least = service.frequencyScoreFor(2446);

      expect(most, 1);
      expect(least, 0);
      expect(most, greaterThan(middle));
      expect(middle, greaterThan(least));
      expect(most.isNaN, isFalse);
      expect(middle.isInfinite, isFalse);
    });

    test('a missing rank does not divide by zero', () {
      final service = CurriculumPriorityService(const <KanjiCard>[]);
      expect(service.frequencyScoreFor(0), 0);
      expect(service.frequencyScoreFor(1), 0);
      expect(service.frequencyScoreFor(1).isNaN, isFalse);

      final single = CurriculumPriorityService([
        card(
          'only',
          character: '一',
          frequency: 1,
          difficulty: 1,
          level: JlptLevel.n5,
        ),
      ]);
      expect(single.frequencyScoreFor(1), 1);
      expect(single.frequencyScoreFor(1).isNaN, isFalse);
    });

    test('the score is normalized, not the raw rank', () {
      final sample = card(
        'sample',
        character: '中',
        frequency: 100,
        difficulty: 10,
        level: JlptLevel.n5,
      );
      final service = CurriculumPriorityService([
        card(
          'a',
          character: '一',
          frequency: 1,
          difficulty: 1,
          level: JlptLevel.n5,
        ),
        sample,
        card(
          'z',
          character: '語',
          frequency: 1000,
          difficulty: 40,
          level: JlptLevel.n3,
        ),
      ]);
      final score = service
          .factors(sample, knownCardIds: const {})
          .frequencyScore;

      expect(score, inInclusiveRange(0, 1));
      expect(score, isNot(100));
      expect(score, isNot(closeTo(0.01, 1e-6)));
      expect(score, lessThan(service.frequencyScoreFor(1)));
      expect(score, greaterThan(service.frequencyScoreFor(1000)));
    });
  });

  group('jlpt', () {
    test('N5 outranks N4, then N3, N2, N1, and no level', () {
      const scores = JlptCurriculumScores.initial;
      final ordered = [
        scores.forLevel(JlptLevel.n5),
        scores.forLevel(JlptLevel.n4),
        scores.forLevel(JlptLevel.n3),
        scores.forLevel(JlptLevel.n2),
        scores.forLevel(JlptLevel.n1),
        scores.forLevel(JlptLevel.none),
      ];
      for (var i = 0; i < ordered.length - 1; i++) {
        expect(ordered[i], greaterThan(ordered[i + 1]));
      }
      expect(ordered.first, 1);
      expect(ordered.last, 0.10);
    });
  });

  group('difficulty', () {
    test('easier kanji score higher without leaving 0–1', () {
      final service = CurriculumPriorityService(const <KanjiCard>[]);
      expect(service.difficultyScoreFor(1), 1);
      expect(service.difficultyScoreFor(100), 0);
      expect(service.difficultyScoreFor(50), closeTo(1 - 49 / 99, 1e-12));
      expect(
        service.difficultyScoreFor(1),
        greaterThan(service.difficultyScoreFor(50)),
      );
      expect(
        service.difficultyScoreFor(50),
        greaterThan(service.difficultyScoreFor(100)),
      );
      expect(service.difficultyScoreFor(0), 0.5);
    });
  });

  group('components', () {
    test('known kanji components raise the score, radicals stay neutral', () {
      final woman = card(
        'woman',
        character: '女',
        frequency: 5,
        difficulty: 2,
        level: JlptLevel.n5,
      );
      final notYet = card(
        'not-yet',
        character: '未',
        frequency: 40,
        difficulty: 8,
        level: JlptLevel.n3,
      );
      final sister = card(
        'sister',
        character: '妹',
        frequency: 80,
        difficulty: 20,
        level: JlptLevel.n4,
        components: const ['女 — woman', '未 — not yet'],
      );
      final radicalOnly = card(
        'rest',
        character: '休',
        frequency: 30,
        difficulty: 12,
        level: JlptLevel.n5,
        components: const ['亻 — person'],
      );
      final service = CurriculumPriorityService([
        woman,
        notYet,
        sister,
        radicalOnly,
      ]);

      expect(service.componentScoreFor(sister, knownCardIds: const {}), 0);
      expect(service.componentScoreFor(sister, knownCardIds: {woman.id}), 0.5);
      expect(
        service.componentScoreFor(sister, knownCardIds: {woman.id, notYet.id}),
        1,
      );
      expect(
        service.componentScoreFor(radicalOnly, knownCardIds: const {}),
        CurriculumPriorityService.neutralComponentScore,
      );
      expect(
        service.componentScoreFor(woman, knownCardIds: const {}),
        CurriculumPriorityService.neutralComponentScore,
      );

      final unknown = service.orderedNewKanji(
        cards: [sister],
        isEligibleNew: (_) => true,
        knownCardIds: const {},
      );
      expect(unknown.single.id, sister.id);
    });
  });

  group('weighting', () {
    test('recommended uses 50/30/15/5 on normalized scores', () {
      const weights = CurriculumPriorityWeights.recommended;
      expect(weights.frequency, 0.50);
      expect(weights.jlpt, 0.30);
      expect(weights.difficulty, 0.15);
      expect(weights.component, 0.05);
      expect(
        weights.frequency +
            weights.jlpt +
            weights.difficulty +
            weights.component,
        closeTo(1, 1e-12),
      );

      const factors = KanjiPriorityFactors(
        frequencyScore: 0.90,
        jlptScore: 0.80,
        difficultyScore: 0.60,
        componentScore: 1,
        weights: weights,
      );
      expect(factors.priorityScore, closeTo(0.83, 1e-12));

      final sample = card(
        'sample',
        character: '中',
        frequency: 8,
        difficulty: 40,
        level: JlptLevel.n4,
      );
      final service = CurriculumPriorityService([
        card(
          'top',
          character: '日',
          frequency: 1,
          difficulty: 1,
          level: JlptLevel.n5,
        ),
        sample,
        card(
          'tail',
          character: '語',
          frequency: 500,
          difficulty: 90,
          level: JlptLevel.n1,
        ),
      ]);
      final scored = service.factors(sample, knownCardIds: const {});
      expect(
        scored.priorityScore,
        closeTo(
          scored.frequencyScore * 0.50 +
              scored.jlptScore * 0.30 +
              scored.difficultyScore * 0.15 +
              scored.componentScore * 0.05,
          1e-12,
        ),
      );
      expect(scored.frequencyScore, inInclusiveRange(0, 1));
      expect(scored.frequencyScore, isNot(sample.frequency.toDouble()));
    });

    test('the breakdown names each signal and its weight', () {
      final sample = card(
        'sister',
        character: '妹',
        frequency: 80,
        difficulty: 43,
        level: JlptLevel.n4,
        components: const ['女 — woman', '未 — not yet'],
      );
      final woman = card(
        'woman',
        character: '女',
        frequency: 5,
        difficulty: 2,
        level: JlptLevel.n5,
      );
      final service = CurriculumPriorityService([sample, woman]);
      final text = service.debugBreakdown(sample, knownCardIds: {woman.id});

      expect(text, startsWith('妹'));
      expect(text, contains('Priority:'));
      expect(text, contains('Frequency:'));
      expect(text, contains('× 50%'));
      expect(text, contains('JLPT:'));
      expect(text, contains('× 30%'));
      expect(text, contains('Difficulty:'));
      expect(text, contains('× 15%'));
      expect(text, contains('Components:'));
      expect(text, contains('× 5%'));
    });
  });

  group('ordering', () {
    final easyObscure = card(
      'easy-obscure',
      character: '易',
      frequency: 500,
      difficulty: 1,
      level: JlptLevel.n5,
    );
    final frequentHard = card(
      'frequent-hard',
      character: '用',
      frequency: 1,
      difficulty: 100,
      level: JlptLevel.n1,
    );
    final middle = card(
      'middle',
      character: '中',
      frequency: 50,
      difficulty: 50,
      level: JlptLevel.n3,
    );
    final deck = [easyObscure, frequentHard, middle];

    List<String> ids(CurriculumMode mode, {Map<String, int>? customRanks}) {
      return CurriculumPriorityService(deck)
          .orderedNewKanji(
            cards: deck,
            isEligibleNew: (_) => true,
            knownCardIds: const {},
            mode: mode,
            customRanks: customRanks,
          )
          .map((item) => item.id)
          .toList();
    }

    test('the same inputs always produce the same order', () {
      final service = CurriculumPriorityService(deck);
      final first = service.orderedNewKanji(
        cards: deck.reversed,
        isEligibleNew: (_) => true,
        knownCardIds: const {},
      );
      final second = service.orderedNewKanji(
        cards: deck,
        isEligibleNew: (_) => true,
        knownCardIds: const {},
      );
      expect(second.map((item) => item.id), first.map((item) => item.id));
    });

    test('recommended, frequency, JLPT, and difficulty disagree', () {
      expect(ids(CurriculumMode.frequency), [
        'frequent-hard',
        'middle',
        'easy-obscure',
      ]);
      expect(ids(CurriculumMode.jlpt), [
        'easy-obscure',
        'middle',
        'frequent-hard',
      ]);
      expect(ids(CurriculumMode.difficulty), [
        'easy-obscure',
        'middle',
        'frequent-hard',
      ]);
      expect(ids(CurriculumMode.recommended), [
        'frequent-hard',
        'easy-obscure',
        'middle',
      ]);
      expect(
        ids(CurriculumMode.recommended),
        isNot(ids(CurriculumMode.frequency)),
      );
      expect(ids(CurriculumMode.recommended), isNot(ids(CurriculumMode.jlpt)));
    });

    test('custom order is reserved and falls back to recommended', () {
      expect(ids(CurriculumMode.custom), ids(CurriculumMode.recommended));
      expect(
        ids(
          CurriculumMode.custom,
          customRanks: {'middle': 0, 'easy-obscure': 1, 'frequent-hard': 2},
        ),
        ['middle', 'easy-obscure', 'frequent-hard'],
      );
    });

    test('known, learning, and mastered cards are not new', () {
      final service = CurriculumPriorityService(deck);
      final ordered = service.orderedNewKanji(
        cards: deck,
        isEligibleNew: (item) => item.id == 'middle',
        knownCardIds: {'frequent-hard', 'easy-obscure'},
      );
      expect(ordered.map((item) => item.id), ['middle']);
    });
  });

  group('catalog', () {
    test('recommended order stays useful and deterministic', () {
      final service = CurriculumPriorityService(hardcodedKanjiCards);
      List<KanjiCard> rank() {
        return service.orderedNewKanji(
          cards: hardcodedKanjiCards,
          isEligibleNew: (_) => true,
          knownCardIds: const {},
        );
      }

      final ordered = rank();
      expect(rank().map((item) => item.id), ordered.map((item) => item.id));
      expect(ordered, hasLength(hardcodedKanjiCards.length));
      expect(ordered.first.character, '日');
      expect(
        ordered.take(100).where((item) => item.jlptLevel == JlptLevel.n1),
        isEmpty,
      );
      expect(
        ordered.indexWhere((item) => item.character == '事'),
        lessThan(ordered.indexWhere((item) => item.character == '七')),
      );

      final firstN3 = ordered.indexWhere(
        (item) => item.jlptLevel == JlptLevel.n3,
      );
      final lastN5 = ordered.lastIndexWhere(
        (item) => item.jlptLevel == JlptLevel.n5,
      );
      expect(firstN3, lessThan(lastN5));

      final byFrequency = [...hardcodedKanjiCards]
        ..sort((a, b) => a.frequency.compareTo(b.frequency));
      expect(
        ordered.take(10).map((item) => item.id).toSet(),
        isNot(equals(byFrequency.take(10).map((item) => item.id).toSet())),
      );
      final byJlpt = [...hardcodedKanjiCards]..sort(compareKanjiLearnOrder);
      expect(ordered.first.id, isNot(byJlpt.first.id));
      expect(
        ordered.skip(ordered.length - 15).map((item) => item.jlptLevel),
        everyElement(JlptLevel.n1),
      );

      for (final item in ordered) {
        final factors = service.factors(item, knownCardIds: const {});
        expect(factors.frequencyScore, inInclusiveRange(0, 1));
        expect(factors.jlptScore, inInclusiveRange(0, 1));
        expect(factors.difficultyScore, inInclusiveRange(0, 1));
        expect(factors.componentScore, inInclusiveRange(0, 1));
        expect(factors.priorityScore.isNaN, isFalse);
        expect(factors.priorityScore.isInfinite, isFalse);
      }
    });

    test('placement keeps JLPT order while recommended does not', () {
      final obscureN5 = card(
        'n5',
        character: '七',
        frequency: 2000,
        difficulty: 1,
        level: JlptLevel.n5,
      );
      final commonN1 = card(
        'n1',
        character: '用',
        frequency: 1,
        difficulty: 80,
        level: JlptLevel.n1,
      );
      final jlpt = [commonN1, obscureN5]..sort(compareKanjiLearnOrder);
      expect(jlpt.first.jlptLevel, JlptLevel.n5);

      final recommended = CurriculumPriorityService([obscureN5, commonN1])
          .orderedNewKanji(
            cards: [commonN1, obscureN5],
            isEligibleNew: (_) => true,
            knownCardIds: const {},
          );
      expect(recommended.first.jlptLevel, JlptLevel.n1);
    });
  });

  group('session boundaries', () {
    DailyWorkloadService workloadFor(
      MemoryProgressRepository progress,
      List<KanjiCard> cards,
    ) {
      return DailyWorkloadService(
        kanjiRepository: FakeKanjiRepository(cards),
        progressRepository: progress,
      );
    }

    test(
      'the daily new-card limit still chooses how many, not which',
      () async {
        final cards = [
          card(
            'rare',
            character: '稀',
            frequency: 900,
            difficulty: 90,
            level: JlptLevel.n1,
          ),
          card(
            'common',
            character: '用',
            frequency: 1,
            difficulty: 40,
            level: JlptLevel.n3,
          ),
          card(
            'mid',
            character: '中',
            frequency: 20,
            difficulty: 20,
            level: JlptLevel.n4,
          ),
          card(
            'also',
            character: '上',
            frequency: 30,
            difficulty: 10,
            level: JlptLevel.n5,
          ),
        ];
        final progress = MemoryProgressRepository(
          settings: const AppSettings(dailyStudyMinutes: 60, newKanjiPerDay: 2),
        );

        final workload = await workloadFor(progress, cards).read(now: now);

        expect(workload.sessionCards.map((item) => item.id), [
          'common',
          'also',
        ]);
        expect(workload.newRemainingToday, 2);
      },
    );

    test(
      'a stored curriculum mode changes which new kanji come first',
      () async {
        final cards = [
          card(
            'n5',
            character: '七',
            frequency: 400,
            difficulty: 1,
            level: JlptLevel.n5,
          ),
          card(
            'n1',
            character: '用',
            frequency: 2,
            difficulty: 80,
            level: JlptLevel.n1,
          ),
        ];
        final byFrequency = MemoryProgressRepository(
          settings: const AppSettings(
            dailyStudyMinutes: 30,
            newKanjiPerDay: 1,
            curriculumMode: CurriculumMode.frequency,
          ),
        );
        final byJlpt = MemoryProgressRepository(
          settings: const AppSettings(
            dailyStudyMinutes: 30,
            newKanjiPerDay: 1,
            curriculumMode: CurriculumMode.jlpt,
          ),
        );

        expect(
          (await workloadFor(
            byFrequency,
            cards,
          ).read(now: now)).sessionCards.single.id,
          'n1',
        );
        expect(
          (await workloadFor(
            byJlpt,
            cards,
          ).read(now: now)).sessionCards.single.id,
          'n5',
        );
      },
    );

    test('the time budget can still stop before the daily allowance', () async {
      final cards = [
        for (var i = 0; i < 8; i++)
          card(
            'n$i',
            character: '$i',
            frequency: i + 1,
            difficulty: 10,
            level: JlptLevel.n5,
          ),
      ];
      final progress = MemoryProgressRepository(
        settings: const AppSettings(dailyStudyMinutes: 1, newKanjiPerDay: 8),
      );

      final workload = await workloadFor(progress, cards).read(now: now);

      expect(workload.sessionCards.length, lessThan(8));
      expect(workload.sessionCards.length, 2);
      expect(workload.newRemainingToday, 8);
    });

    test(
      'learning, mastered, and known kanji are not introduced as new',
      () async {
        final cards = [
          card(
            'known',
            character: '日',
            frequency: 1,
            difficulty: 3,
            level: JlptLevel.n5,
          ),
          card(
            'learning',
            character: '人',
            frequency: 2,
            difficulty: 3,
            level: JlptLevel.n5,
          ),
          card(
            'mastered',
            character: '一',
            frequency: 3,
            difficulty: 2,
            level: JlptLevel.n5,
          ),
          card(
            'next',
            character: '年',
            frequency: 5,
            difficulty: 1,
            level: JlptLevel.n5,
          ),
          card(
            'later',
            character: '本',
            frequency: 400,
            difficulty: 50,
            level: JlptLevel.n1,
          ),
        ];
        final progress = MemoryProgressRepository(
          settings: const AppSettings(dailyStudyMinutes: 30, newKanjiPerDay: 1),
          schedules: {
            'known': CardSchedule(
              cardId: 'known',
              state: CardLearningState.review,
              reviewCount: 1,
              correctCount: 1,
              incorrectCount: 0,
              dueAt: now.add(const Duration(days: 30)),
              interval: const Duration(days: 30),
              ease: 2.5,
              consecutiveGoodCount: 1,
            ),
            'learning': CardSchedule(
              cardId: 'learning',
              state: CardLearningState.learning,
              reviewCount: 1,
              correctCount: 0,
              incorrectCount: 1,
              dueAt: now,
              interval: const Duration(minutes: 1),
              ease: 2.5,
            ),
            'mastered': CardSchedule(
              cardId: 'mastered',
              state: CardLearningState.review,
              reviewCount: 3,
              correctCount: 3,
              incorrectCount: 0,
              dueAt: now,
              interval: const Duration(days: 7),
              ease: 2.5,
              consecutiveGoodCount: 3,
            ),
          },
        );

        final workload = await workloadFor(progress, cards).read(now: now);
        final ids = workload.sessionCards.map((item) => item.id).toList();

        expect(ids, contains('next'));
        expect(ids, containsAll(['learning', 'mastered']));
        expect(ids, isNot(contains('known')));
        expect(ids, isNot(contains('later')));
      },
    );

    test('ranking new kanji does not change SRS intervals', () {
      const engine = SrsEngine();
      final current = CardSchedule(
        cardId: 'k',
        state: CardLearningState.review,
        reviewCount: 2,
        correctCount: 2,
        incorrectCount: 0,
        dueAt: now,
        interval: const Duration(days: 4),
        ease: 2.5,
        lastReviewedAt: now.subtract(const Duration(days: 4)),
        consecutiveGoodCount: 2,
      );
      final good = engine.schedule(
        current: current,
        result: ReviewResult.good,
        now: now,
      );
      final again = engine.schedule(
        current: current,
        result: ReviewResult.again,
        now: now,
      );

      CurriculumPriorityService([
        card(
          'k',
          character: '日',
          frequency: 1,
          difficulty: 3,
          level: JlptLevel.n5,
        ),
      ]).orderedNewKanji(
        cards: [
          card(
            'k',
            character: '日',
            frequency: 1,
            difficulty: 3,
            level: JlptLevel.n5,
          ),
        ],
        isEligibleNew: (_) => false,
        knownCardIds: {'k'},
      );

      final goodAfter = engine.schedule(
        current: current,
        result: ReviewResult.good,
        now: now,
      );
      final againAfter = engine.schedule(
        current: current,
        result: ReviewResult.again,
        now: now,
      );

      expect(goodAfter.interval, good.interval);
      expect(goodAfter.dueAt, good.dueAt);
      expect(goodAfter.ease, good.ease);
      expect(againAfter.interval, again.interval);
      expect(againAfter.dueAt, again.dueAt);
      expect(again.interval, isNot(good.interval));
      expect(current.interval, const Duration(days: 4));
      expect(current.reviewCount, 2);
    });
  });

  test('missing curriculum settings stay on Recommended', () {
    expect(const AppSettings().curriculumMode, CurriculumMode.recommended);
    expect(
      AppSettings.fromJson(const {
        'newKanjiPerDay': 5,
        'dailyStudyMinutes': 5,
      }).curriculumMode,
      CurriculumMode.recommended,
    );
    final stored = const AppSettings(
      curriculumMode: CurriculumMode.frequency,
    ).toJson();
    expect(
      AppSettings.fromJson(stored).curriculumMode,
      CurriculumMode.frequency,
    );
    expect(
      CurriculumMode.fromStorage('not-a-mode'),
      CurriculumMode.recommended,
    );
  });
}
