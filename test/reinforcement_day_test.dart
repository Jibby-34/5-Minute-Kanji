import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fiveminutekanji/core/models/card_schedule.dart';
import 'package:fiveminutekanji/core/models/daily_session_plan.dart';
import 'package:fiveminutekanji/core/models/kanji_card.dart';
import 'package:fiveminutekanji/core/models/progress.dart';
import 'package:fiveminutekanji/core/models/start_of_day.dart';
import 'package:fiveminutekanji/core/models/study_day_type.dart';
import 'package:fiveminutekanji/data/shared_prefs_progress_repository.dart';
import 'package:fiveminutekanji/services/card_priority_scorer.dart';
import 'package:fiveminutekanji/services/daily_workload.dart';
import 'package:fiveminutekanji/services/recall_estimator.dart';
import 'package:fiveminutekanji/services/reinforcement_day.dart';

import 'support/fakes.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final now = DateTime(2026, 10, 26, 9);
  const policy = ReinforcementDayPolicy();
  const config = ReinforcementDayConfig();
  const scorer = CardPriorityScorer();

  List<double> filled(int count, double value) =>
      List<double>.filled(count, value);

  DailyWorkloadService serviceFor(
    MemoryProgressRepository progress,
    List<KanjiCard> cards, {
    RecallEstimator? recall,
  }) {
    return DailyWorkloadService(
      kanjiRepository: FakeKanjiRepository(cards),
      progressRepository: progress,
      scorer: recall == null ? scorer : CardPriorityScorer(recall: recall),
    );
  }

  group('ReinforcementDayPolicy', () {
    test('fewer than the minimum number of due cards stays a normal day', () {
      expect(policy.dayTypeFor(filled(7, 0)), StudyDayType.normal);
      expect(
        policy.dayTypeFor(filled(config.minimumDueCards - 1, 0.1)),
        StudyDayType.normal,
      );
    });

    test('a healthy average and a small low-recall share stay normal', () {
      final recall = [...filled(7, 0.95), 0.1];
      expect(policy.dayTypeFor(recall), StudyDayType.normal);
      expect(
        _average(recall),
        greaterThanOrEqualTo(config.averageRecallThreshold),
      );
      expect(_lowFraction(recall), lessThan(0.25));
    });

    test('a low average triggers reinforcement on its own', () {
      final recall = filled(8, 0.30);
      expect(_average(recall), lessThan(config.averageRecallThreshold));
      expect(_lowFraction(recall), lessThan(0.25));
      expect(policy.dayTypeFor(recall), StudyDayType.reinforcement);
    });

    test('the low-recall fraction triggers reinforcement on its own', () {
      final recall = [...filled(6, 1), ...filled(2, 0)];
      expect(
        _average(recall),
        greaterThanOrEqualTo(config.averageRecallThreshold),
      );
      expect(_lowFraction(recall), 0.25);
      expect(policy.dayTypeFor(recall), StudyDayType.reinforcement);
    });

    test('both recall rules can be true together', () {
      expect(policy.dayTypeFor(filled(8, 0)), StudyDayType.reinforcement);
    });

    test('thresholds use strict probability checks and an inclusive share', () {
      expect(policy.dayTypeFor(filled(8, 0.40)), StudyDayType.normal);
      expect(policy.dayTypeFor(filled(8, 0.39)), StudyDayType.reinforcement);

      final onLowLine = [...filled(6, 1), ...filled(2, 0.20)];
      expect(_lowFraction(onLowLine), 0);
      expect(policy.dayTypeFor(onLowLine), StudyDayType.normal);

      final justUnderShare = [...filled(7, 1.0), 0.0];
      expect(_lowFraction(justUnderShare), lessThan(0.25));
      expect(policy.dayTypeFor(justUnderShare), StudyDayType.normal);

      final exactShare = [...filled(6, 1), ...filled(2, 0.199)];
      expect(
        _average(exactShare),
        greaterThanOrEqualTo(config.averageRecallThreshold),
      );
      expect(_lowFraction(exactShare), 0.25);
      expect(policy.dayTypeFor(exactShare), StudyDayType.reinforcement);

      expect(policy.dayTypeFor(filled(8, 0)), StudyDayType.reinforcement);
      expect(policy.dayTypeFor(filled(8, 1)), StudyDayType.normal);
    });

    test('an empty sample and unusable estimates stay a normal day', () {
      expect(policy.dayTypeFor(const []), StudyDayType.normal);
      expect(
        policy.dayTypeFor(const [
          double.nan,
          double.infinity,
          double.negativeInfinity,
          -0.01,
          1.01,
        ]),
        StudyDayType.normal,
      );
      expect(policy.dayTypeFor(filled(12, double.nan)), StudyDayType.normal);
    });

    test('unusable estimates are left out of the count and the average', () {
      final withGaps = [...filled(6, 0.1), ...filled(4, double.nan)];
      expect(policy.dayTypeFor(withGaps), StudyDayType.normal);

      final enough = [...filled(8, 0.1), double.nan, double.infinity];
      expect(policy.dayTypeFor(enough), StudyDayType.reinforcement);
    });

    test('a custom configuration is the only source of the thresholds', () {
      const tuned = ReinforcementDayPolicy(
        config: ReinforcementDayConfig(
          minimumDueCards: 2,
          averageRecallThreshold: 0.5,
          lowRecallThreshold: 0.2,
          lowRecallFractionThreshold: 0.5,
        ),
      );

      expect(tuned.dayTypeFor(const [0.4, 0.4]), StudyDayType.reinforcement);
      expect(policy.dayTypeFor(const [0.4, 0.4]), StudyDayType.normal);

      expect(tuned.dayTypeFor(const [0.9, 0.1]), StudyDayType.reinforcement);
      expect(tuned.dayTypeFor(const [0.9, 0.2]), StudyDayType.normal);
    });

    test('only due, already studied cards are sampled', () {
      final cards = [
        for (var i = 0; i < 8; i++) testCard('known$i'),
        for (var i = 0; i < 8; i++) testCard('later$i'),
        for (var i = 0; i < 8; i++) testCard('fresh$i'),
        for (var i = 0; i < 8; i++) testCard('learning$i'),
        testCard('missing'),
      ];
      final schedules = <String, CardSchedule>{
        for (var i = 0; i < 8; i++) 'known$i': _markedKnown('known$i', now),
        for (var i = 0; i < 8; i++)
          'later$i': _due(
            'later$i',
            now,
          ).copyWith(dueAt: now.add(const Duration(days: 3))),
        for (var i = 0; i < 8; i++)
          'fresh$i': CardSchedule.fresh('fresh$i', now),
        for (var i = 0; i < 8; i++) 'learning$i': _learning('learning$i', now),
      };
      final recall = _ScriptedRecall({for (final card in cards) card.id: 0});

      expect(
        policy.dayTypeForCards(
          cards: cards.where((card) => card.id != 'learning0').toList(),
          schedules: schedules,
          now: now,
          startOfDay: StartOfDay.defaults,
          recall: recall,
        ),
        StudyDayType.normal,
      );
      expect(
        policy.dayTypeForCards(
          cards: cards,
          schedules: schedules,
          now: now,
          startOfDay: StartOfDay.defaults,
          recall: recall,
        ),
        StudyDayType.reinforcement,
      );
    });
  });

  group('daily plan', () {
    test(
      'a low average from the recall estimator plans no new kanji',
      () async {
        final built = _deck(count: 8, schedule: (id) => _moderate(id, now));
        final probabilities = _probabilities(built.schedules, now);
        expect(
          _average(probabilities),
          lessThan(config.averageRecallThreshold),
        );
        expect(_lowFraction(probabilities), lessThan(0.25));

        final workload = await serviceFor(
          built.progress,
          built.cards,
        ).read(now: now);

        expect(workload.dayType, StudyDayType.reinforcement);
        expect(
          built.progress.dailySessionPlan.dayType,
          StudyDayType.reinforcement,
        );
        expect(workload.allocation.newCards, 0);
        expect(workload.allocation.newSeconds, 0);
        expect(workload.sessionCards.map((card) => card.id), [
          for (final card in built.reviews) card.id,
        ]);
        expect(
          built.progress.settings.newKanjiPerDay,
          AppSettings.defaultNewKanjiPerDay,
        );
        expect(
          built.progress.dailySessionPlan.newKanjiPerDay,
          AppSettings.defaultNewKanjiPerDay,
        );
        expect(
          built.progress.dailySessionPlan.budgetMinutes,
          built.progress.settings.dailyStudyMinutes,
        );
      },
    );

    test(
      'a low-recall fraction from the estimator plans no new kanji',
      () async {
        final built = _deck(
          count: 8,
          schedule: (id) => id.endsWith('6') || id.endsWith('7')
              ? _collapsed(id, now)
              : _strong(id, now),
        );
        final probabilities = _probabilities(built.schedules, now);
        expect(
          _average(probabilities),
          greaterThanOrEqualTo(config.averageRecallThreshold),
        );
        expect(_lowFraction(probabilities), greaterThanOrEqualTo(0.25));

        final workload = await serviceFor(
          built.progress,
          built.cards,
        ).read(now: now);

        expect(workload.dayType, StudyDayType.reinforcement);
        expect(workload.allocation.newCards, 0);
        expect(
          workload.sessionCards.map((card) => card.id),
          isNot(contains('n0')),
        );
      },
    );

    test('healthy recall keeps today\'s new kanji', () async {
      final built = _deck(count: 8, schedule: (id) => _strong(id, now));
      final probabilities = _probabilities(built.schedules, now);
      expect(
        _average(probabilities),
        greaterThanOrEqualTo(config.averageRecallThreshold),
      );
      expect(_lowFraction(probabilities), lessThan(0.25));
      final before = _snapshot(built.progress);

      final workload = await serviceFor(
        built.progress,
        built.cards,
      ).read(now: now);

      expect(workload.dayType, StudyDayType.normal);
      expect(workload.allocation.newCards, 2);
      expect(
        workload.sessionCards.map((card) => card.id),
        containsAll(['n0', 'n1']),
      );
      expect(workload.sessionCards.length, built.reviews.length + 2);
      expect(_snapshot(built.progress), before);
      expect(built.progress.dailyNewKanji.count, 0);
    });

    test('too few due cards keep today\'s new kanji', () async {
      final built = _deck(count: 7, schedule: (id) => _collapsed(id, now));
      final workload = await serviceFor(
        built.progress,
        built.cards,
      ).read(now: now);

      expect(workload.dayType, StudyDayType.normal);
      expect(
        workload.sessionCards.map((card) => card.id),
        containsAll(['n0', 'n1']),
      );
    });

    test('marked-known cards do not trigger and are still reviewed', () async {
      final known = [for (var i = 0; i < 8; i++) testCard('k$i')];
      final news = [testCard('n0'), testCard('n1')];
      final progress = MemoryProgressRepository(
        settings: const AppSettings(dailyStudyMinutes: 30, newKanjiPerDay: 2),
        schedules: {
          for (final card in known) card.id: _markedKnown(card.id, now),
        },
      );

      final workload = await serviceFor(progress, [
        ...known,
        ...news,
      ]).read(now: now);

      expect(workload.dayType, StudyDayType.normal);
      expect(
        workload.sessionCards.map((card) => card.id),
        containsAll([...known.map((card) => card.id), 'n0', 'n1']),
      );
    });

    test('no due reviews does not invent a review session', () async {
      final news = [testCard('n0'), testCard('n1')];
      final progress = MemoryProgressRepository(
        settings: const AppSettings(newKanjiPerDay: 2),
      );

      final workload = await serviceFor(progress, news).read(now: now);

      expect(workload.dayType, StudyDayType.normal);
      expect(workload.dueCount, 0);
      expect(workload.sessionCards.map((card) => card.id), ['n0', 'n1']);
      expect(workload.allocation.reviewCards, 0);
      expect(workload.studyAnywayAvailable, isFalse);
    });

    test('future reviews are not sampled and are not studied today', () async {
      final later = _deck(
        count: 8,
        schedule: (id) => _collapsed(
          id,
          now,
        ).copyWith(dueAt: now.add(const Duration(days: 4))),
      );

      final workload = await serviceFor(
        later.progress,
        later.cards,
      ).read(now: now);

      expect(workload.dayType, StudyDayType.normal);
      expect(workload.dueCount, 0);
      expect(
        workload.sessionCards.map((card) => card.id),
        containsAll(['n0', 'n1']),
      );
      expect(
        workload.sessionCards.map((card) => card.id),
        isNot(contains('r00')),
      );
    });

    test('invalid recall estimates do not force a reinforcement day', () async {
      final built = _deck(count: 10, schedule: (id) => _due(id, now));
      final workload = await serviceFor(
        built.progress,
        built.cards,
        recall: _ScriptedRecall({
          for (final card in built.reviews) card.id: double.nan,
        }),
      ).read(now: now);

      expect(workload.dayType, StudyDayType.normal);
      expect(
        workload.sessionCards.map((card) => card.id),
        containsAll(['n0', 'n1', 'r00']),
      );
    });

    test('scripted boundaries plan new kanji only on a normal day', () async {
      Future<StudyDayType> day(Map<String, double> recall) async {
        final reviews = [for (final id in recall.keys) testCard(id)];
        final cards = [...reviews, testCard('n0')];
        final progress = MemoryProgressRepository(
          settings: const AppSettings(dailyStudyMinutes: 30, newKanjiPerDay: 1),
          schedules: {for (final id in recall.keys) id: _due(id, now)},
        );
        final workload = await serviceFor(
          progress,
          cards,
          recall: _ScriptedRecall(recall),
        ).read(now: now);
        final ids = workload.sessionCards.map((card) => card.id);
        expect(ids.contains('n0'), workload.dayType == StudyDayType.normal);
        return workload.dayType;
      }

      expect(
        await day({for (var i = 0; i < 7; i++) 'r$i': 0}),
        StudyDayType.normal,
      );
      expect(
        await day({for (var i = 0; i < 8; i++) 'r$i': 0.40}),
        StudyDayType.normal,
      );
      expect(
        await day({for (var i = 0; i < 8; i++) 'r$i': 0.39}),
        StudyDayType.reinforcement,
      );
      expect(
        await day({for (var i = 0; i < 6; i++) 'h$i': 1, 'l0': 0, 'l1': 0}),
        StudyDayType.reinforcement,
      );
      expect(
        await day({for (var i = 0; i < 7; i++) 'h$i': 1, 'l0': 0}),
        StudyDayType.normal,
      );
      expect(
        await day({
          for (var i = 0; i < 6; i++) 'h$i': 1,
          'l0': 0.20,
          'l1': 0.20,
        }),
        StudyDayType.normal,
      );
    });

    test(
      'review priority and the time budget match a reviews-only plan',
      () async {
        final reviews = [for (var i = 0; i < 24; i++) testCard('r$i')];
        final news = [for (var i = 0; i < 3; i++) testCard('n$i')];
        CardSchedule schedule(String id) => _moderate(id, now);
        final progress = MemoryProgressRepository(
          settings: const AppSettings(dailyStudyMinutes: 5, newKanjiPerDay: 5),
          schedules: {for (final card in reviews) card.id: schedule(card.id)},
        );
        final reviewsOnly = MemoryProgressRepository(
          settings: const AppSettings(dailyStudyMinutes: 5, newKanjiPerDay: 0),
          schedules: {for (final card in reviews) card.id: schedule(card.id)},
        );
        final before = _snapshot(progress);

        final workload = await serviceFor(progress, [
          ...reviews,
          ...news,
        ]).read(now: now);
        final baseline = await serviceFor(reviewsOnly, reviews).read(now: now);

        expect(workload.dayType, StudyDayType.reinforcement);
        expect(workload.allocation.newCards, 0);
        expect(workload.allocation.newSeconds, 0);
        expect(workload.sessionCards.length, lessThan(reviews.length));
        expect(
          workload.sessionCards.map((card) => card.id),
          baseline.sessionCards.map((card) => card.id),
        );
        expect(
          workload.allocation.reviewSeconds,
          baseline.allocation.reviewSeconds,
        );
        expect(workload.estimatedMinutes, baseline.estimatedMinutes);
        expect(progress.settings.dailyStudyMinutes, 5);
        expect(progress.settings.newKanjiPerDay, 5);
        expect(_snapshot(progress), before);

        final scores = [
          for (final card in workload.sessionCards)
            scorer.score(
              schedule: progress.schedules[card.id],
              now: now,
              isNew: false,
            ),
        ];
        for (var i = 1; i < scores.length; i++) {
          expect(scores[i], lessThanOrEqualTo(scores[i - 1]));
        }
      },
    );

    test(
      'study anyway keeps the due reviews and leaves new kanji out',
      () async {
        final built = _deck(
          count: 24,
          schedule: (id) => _moderate(id, now),
          minutes: 5,
        );
        final workload = await serviceFor(
          built.progress,
          built.cards,
        ).read(now: now);
        final selected = workload.sessionCards.map((card) => card.id).toSet();
        expect(selected, isNotEmpty);
        expect(selected.length, lessThan(built.reviews.length));

        for (final id in selected) {
          built.progress.schedules[id] = _strong(
            id,
            now,
          ).copyWith(dueAt: now.add(const Duration(days: 4)));
        }
        await built.progress.saveDailySessionPlan(
          built.progress.dailySessionPlan.copyWith(completed: true),
        );

        final done = await serviceFor(
          built.progress,
          built.cards,
        ).read(now: now);

        expect(done.dayType, StudyDayType.reinforcement);
        expect(done.recommendedComplete, isTrue);
        expect(done.studyAnywayAvailable, isTrue);
        expect(done.sessionCards, isEmpty);
        expect(done.overflowCards, isNotEmpty);
        expect(
          done.overflowCards.map((card) => card.id),
          isNot(contains('n0')),
        );
        expect(
          done.overflowCards.map((card) => card.id),
          isNot(containsAll(selected)),
        );
      },
    );

    test('the day type stays put while reviews are finished', () async {
      final built = _deck(count: 8, schedule: (id) => _moderate(id, now));
      final service = serviceFor(built.progress, built.cards);
      final first = await service.read(now: now);
      expect(first.dayType, StudyDayType.reinforcement);

      final finished = built.reviews.first.id;
      built.progress.schedules[finished] = _strong(
        finished,
        now,
      ).copyWith(dueAt: now.add(const Duration(days: 4)));
      for (final card in built.reviews.skip(1)) {
        built.progress.schedules[card.id] = _strong(card.id, now);
      }

      final later = now.add(const Duration(hours: 3));
      final second = await service.read(now: later);
      expect(second.dayType, StudyDayType.reinforcement);
      expect(second.sessionCards.map((card) => card.id), isNot(contains('n0')));
      expect(
        second.sessionCards.map((card) => card.id),
        isNot(contains(finished)),
      );
      expect(
        _average(_probabilities(built.progress.schedules, later)),
        greaterThanOrEqualTo(config.averageRecallThreshold),
      );

      final restarted = await serviceFor(
        built.progress,
        built.cards,
      ).read(now: later);
      expect(restarted.dayType, StudyDayType.reinforcement);
      expect(
        restarted.sessionCards.map((card) => card.id),
        second.sessionCards.map((card) => card.id),
      );

      final continued = await service.eligibleByPriority(now: later);
      expect(continued.map((card) => card.id), isNot(contains('n0')));
    });

    test('the next study day decides again', () async {
      final built = _deck(count: 8, schedule: (id) => _moderate(id, now));
      final service = serviceFor(built.progress, built.cards);
      expect(
        (await service.read(now: now)).dayType,
        StudyDayType.reinforcement,
      );

      for (final card in built.reviews) {
        built.progress.schedules[card.id] = _strong(card.id, now);
      }
      final tomorrow = now.add(const Duration(days: 1));
      final next = await service.read(now: tomorrow);

      expect(next.dayType, StudyDayType.normal);
      expect(built.progress.dailySessionPlan.dayType, StudyDayType.normal);
      expect(next.sessionCards.map((card) => card.id), contains('n0'));
      expect(
        StartOfDay.defaults.studyDate(tomorrow),
        isNot(StartOfDay.defaults.studyDate(now)),
      );
    });

    test(
      'a normal plan does not flip until the next planning boundary',
      () async {
        final built = _deck(count: 8, schedule: (id) => _strong(id, now));
        final service = serviceFor(built.progress, built.cards);
        final first = await service.read(now: now);
        expect(first.dayType, StudyDayType.normal);
        expect(first.sessionCards.map((card) => card.id), contains('n0'));

        for (final card in built.reviews) {
          built.progress.schedules[card.id] = _collapsed(card.id, now);
        }
        final later = await service.read(
          now: now.add(const Duration(hours: 2)),
        );
        expect(later.dayType, StudyDayType.normal);
        expect(later.sessionCards.map((card) => card.id), contains('n0'));

        final tomorrow = await service.read(
          now: now.add(const Duration(days: 1)),
        );
        expect(tomorrow.dayType, StudyDayType.reinforcement);
        expect(
          tomorrow.sessionCards.map((card) => card.id),
          isNot(contains('n0')),
        );
      },
    );

    test('a stored plan keeps its day type across a restart', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final reviews = [for (var i = 0; i < 8; i++) testCard('r$i')];
      final cards = [...reviews, testCard('n0')];
      final schedules = [for (final card in reviews) _moderate(card.id, now)];

      final firstRepo = SharedPrefsProgressRepository(prefs);
      await firstRepo.saveSettings(
        const AppSettings(dailyStudyMinutes: 15, newKanjiPerDay: 3),
      );
      await firstRepo.saveSchedules(schedules);
      final first = await DailyWorkloadService(
        kanjiRepository: FakeKanjiRepository(cards),
        progressRepository: firstRepo,
      ).read(now: now);
      expect(first.dayType, StudyDayType.reinforcement);

      final stored = await firstRepo.getDailySessionPlan();
      expect(
        DailySessionPlan.fromJson(stored.toJson()).dayType,
        stored.dayType,
      );

      final restarted = SharedPrefsProgressRepository(prefs);
      await restarted.saveSchedules([
        for (final card in reviews) _strong(card.id, now),
      ]);
      final second = await DailyWorkloadService(
        kanjiRepository: FakeKanjiRepository(cards),
        progressRepository: restarted,
      ).read(now: now.add(const Duration(hours: 1)));

      expect(second.dayType, StudyDayType.reinforcement);
      expect(second.sessionCards.map((card) => card.id), isNot(contains('n0')));
      expect((await restarted.getSettings()).newKanjiPerDay, 3);
      expect((await restarted.getSettings()).dailyStudyMinutes, 15);
    });

    test('older plans without a day type stay normal', () {
      final legacy = DailySessionPlan.fromJson({
        'studyDate': '2026-10-26',
        'budgetMinutes': 5,
        'newKanjiPerDay': 5,
        'cardIds': ['n0'],
      });
      expect(legacy.dayType, StudyDayType.normal);
      expect(
        DailySessionPlan.fromJson({
          'studyDate': '2026-10-26',
          'dayType': 'surprise',
        }).dayType,
        StudyDayType.normal,
      );

      final saved = DailySessionPlan(
        studyDate: now,
        budgetMinutes: 5,
        newKanjiPerDay: 5,
        dayType: StudyDayType.reinforcement,
        cardIds: const ['r00'],
      );
      expect(DailySessionPlan.fromJson(saved.toJson()).dayType, saved.dayType);
      expect(saved.copyWith(completed: true).dayType, saved.dayType);
      expect(
        saved.matches(
          studyDate: now,
          budgetMinutes: 5,
          newKanjiPerDay: 5,
          startOfDay: StartOfDay.defaults,
        ),
        isTrue,
      );
    });
  });
}

class _ScriptedRecall extends RecallEstimator {
  _ScriptedRecall(this.values);

  final Map<String, double> values;

  @override
  double probability({
    required CardSchedule? schedule,
    required DateTime now,
    required bool isNew,
  }) {
    final id = schedule?.cardId;
    if (id == null) return double.nan;
    return values[id] ?? double.nan;
  }
}

class _BuiltDeck {
  const _BuiltDeck({
    required this.cards,
    required this.reviews,
    required this.progress,
  });

  final List<KanjiCard> cards;
  final List<KanjiCard> reviews;
  final MemoryProgressRepository progress;

  Map<String, CardSchedule> get schedules => progress.schedules;
}

_BuiltDeck _deck({
  required int count,
  required CardSchedule Function(String id) schedule,
  int minutes = 30,
  int newCards = 2,
}) {
  final reviews = [
    for (var i = 0; i < count; i++)
      testCard('r${i.toString().padLeft(2, '0')}'),
  ];
  final news = [for (var i = 0; i < newCards; i++) testCard('n$i')];
  return _BuiltDeck(
    cards: [...reviews, ...news],
    reviews: reviews,
    progress: MemoryProgressRepository(
      settings: AppSettings(dailyStudyMinutes: minutes, newKanjiPerDay: 5),
      schedules: {for (final card in reviews) card.id: schedule(card.id)},
    ),
  );
}

CardSchedule _due(String id, DateTime now) {
  return CardSchedule(
    cardId: id,
    state: CardLearningState.review,
    reviewCount: 2,
    correctCount: 2,
    incorrectCount: 0,
    dueAt: now,
    interval: const Duration(days: 3),
    ease: 2.5,
    lastReviewedAt: now.subtract(const Duration(days: 1)),
    consecutiveGoodCount: 1,
  );
}

/// About 0.31 recall: below the average threshold, and above the low line.
CardSchedule _moderate(String id, DateTime now) {
  return CardSchedule(
    cardId: id,
    state: CardLearningState.review,
    reviewCount: 4,
    correctCount: 4,
    incorrectCount: 0,
    dueAt: now,
    interval: const Duration(days: 10),
    ease: 2.5,
    lastReviewedAt: now.subtract(const Duration(days: 17)),
  );
}

CardSchedule _strong(String id, DateTime now) {
  return CardSchedule(
    cardId: id,
    state: CardLearningState.review,
    reviewCount: 8,
    correctCount: 8,
    incorrectCount: 0,
    dueAt: now,
    interval: const Duration(days: 40),
    ease: 2.5,
    lastReviewedAt: now.subtract(const Duration(hours: 12)),
    consecutiveGoodCount: 6,
  );
}

CardSchedule _collapsed(String id, DateTime now) {
  return CardSchedule(
    cardId: id,
    state: CardLearningState.review,
    reviewCount: 6,
    correctCount: 1,
    incorrectCount: 5,
    dueAt: now.subtract(const Duration(days: 13)),
    interval: const Duration(days: 1),
    ease: 1.3,
    lastReviewedAt: now.subtract(const Duration(days: 14)),
  );
}

CardSchedule _markedKnown(String id, DateTime now) {
  return CardSchedule(
    cardId: id,
    state: CardLearningState.review,
    reviewCount: 0,
    correctCount: 0,
    incorrectCount: 0,
    dueAt: now,
    interval: const Duration(days: 30),
    ease: 2.5,
  );
}

CardSchedule _learning(String id, DateTime now) {
  return CardSchedule(
    cardId: id,
    state: CardLearningState.learning,
    reviewCount: 1,
    correctCount: 0,
    incorrectCount: 1,
    dueAt: now,
    interval: const Duration(minutes: 10),
    ease: 2.3,
    lastReviewedAt: now.subtract(const Duration(minutes: 30)),
  );
}

List<double> _probabilities(Map<String, CardSchedule> schedules, DateTime now) {
  const estimator = RecallEstimator();
  return [
    for (final schedule in schedules.values)
      estimator.probability(schedule: schedule, now: now, isNew: false),
  ];
}

double _average(List<double> values) {
  var total = 0.0;
  for (final value in values) {
    total += value;
  }
  return total / values.length;
}

double _lowFraction(List<double> values) {
  final line = ReinforcementDayConfig.production.lowRecallThreshold;
  final low = values.where((value) => value < line).length;
  return low / values.length;
}

Map<String, Map<String, dynamic>> _snapshot(MemoryProgressRepository progress) {
  return {
    for (final entry in progress.schedules.entries)
      entry.key: entry.value.toJson(),
  };
}
