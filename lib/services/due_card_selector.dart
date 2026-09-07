import 'dart:convert';
import 'dart:io';

import '../core/models/card_schedule.dart';
import '../core/models/kanji_card.dart';
import '../core/models/progress.dart';

/// Picks cards for a sitting. SRS [CardSchedule.dueAt] is the ideal review
/// time; this class decides daily availability for today's study window.
class DueCardSelector {
  const DueCardSelector();

  bool isNew(CardSchedule? schedule) {
    return schedule == null || schedule.state == CardLearningState.newCard;
  }

  /// Encountered cards that belong to today's study window.
  bool isEncounteredDue(CardSchedule? schedule, DateTime now) {
    return !isNew(schedule) && isAvailableToday(schedule!, now);
  }

  bool isDue(CardSchedule? schedule, DateTime now) {
    return isNew(schedule) || isAvailableToday(schedule!, now);
  }

  /// True when [schedule] can be shown in today's sitting.
  ///
  /// Overdue cards and cards due later today are included. Cards due
  /// tomorrow or later are not. Does not change SRS intervals.
  bool isAvailableToday(CardSchedule schedule, DateTime now) {
    return schedule.dueAt.isBefore(_startOfTomorrow(now));
  }

  DateTime _startOfTomorrow(DateTime now) =>
      calendarDay(now).add(const Duration(days: 1));

  List<KanjiCard> select({
    required List<KanjiCard> cards,
    required Map<String, CardSchedule> schedules,
    required DateTime now,
    required int limit,
    int? maxNewCards,
  }) {
    if (limit <= 0) return const [];

    final learningDue = <KanjiCard>[];
    final reviewDue = <KanjiCard>[];
    final news = <KanjiCard>[];

    for (final card in cards) {
      final schedule = schedules[card.id];
      if (isNew(schedule)) {
        news.add(card);
      } else if (isAvailableToday(schedule!, now)) {
        if (schedule.state == CardLearningState.learning) {
          learningDue.add(card);
        } else {
          reviewDue.add(card);
        }
      }
    }

    // #region agent log
    final n5News = [
      for (final card in news)
        if (card.jlptLevel == JlptLevel.n5) card,
    ];
    final n4News = [
      for (final card in news)
        if (card.jlptLevel == JlptLevel.n4) card,
    ];
    final n5Ids = [for (final card in n5News) card.id]..sort();
    final listOrderFirstNew = news.isEmpty
        ? null
        : {'id': news.first.id, 'jlpt': news.first.jlptLevel.name};
    _agentLog(
      'H2,H3,H5',
      'due_card_selector.dart:select:beforeSort',
      'unknown new cards before id sort',
      {
        'newCount': news.length,
        'n5NewCount': n5News.length,
        'n4NewCount': n4News.length,
        'lowestN5Id': n5Ids.isEmpty ? null : n5Ids.first,
        'lowestN5Jlpt': n5News.isEmpty ? null : n5News.first.jlptLevel.name,
        'listOrderFirstNew': listOrderFirstNew,
        'n5IdSample': n5Ids.take(5).toList(),
        'n5PrefixWrongJlpt': [
          for (final card in news)
            if (card.id.startsWith('n5-') && card.jlptLevel != JlptLevel.n5)
              {'id': card.id, 'jlpt': card.jlptLevel.name},
        ],
      },
    );
    // #endregion

    _sortByDueThenId(learningDue, schedules, now);
    _sortByDueThenId(reviewDue, schedules, now);
    news.sort(_compareNewLearnOrder);

    // #region agent log
    _agentLog(
      'H1',
      'due_card_selector.dart:select:afterIdSort',
      'unknown new cards after raw id sort',
      {
        'firstNewId': news.isEmpty ? null : news.first.id,
        'firstNewKeyword': news.isEmpty ? null : news.first.keyword,
        'firstNewJlpt': news.isEmpty ? null : news.first.jlptLevel.name,
        'sortedNewSample': [
          for (final card in news.take(8))
            {'id': card.id, 'jlpt': card.jlptLevel.name, 'kw': card.keyword},
        ],
        'n4vsN5Compare': 'n4-001'.compareTo('n5-001'),
        'n5Remain': n5News.isNotEmpty,
      },
    );
    // #endregion

    final existingAvailable = learningDue.length + reviewDue.length;
    final int newTakeCount;
    final int existingTakeCount;
    if (maxNewCards == null) {
      existingTakeCount = existingAvailable < limit ? existingAvailable : limit;
      final leftover = limit - existingTakeCount;
      newTakeCount = news.length < leftover ? news.length : leftover;
    } else {
      final cappedNew = maxNewCards < 0 ? 0 : maxNewCards;
      newTakeCount = [
        cappedNew,
        news.length,
        limit,
      ].reduce((a, b) => a < b ? a : b);
      final leftover = limit - newTakeCount;
      existingTakeCount = existingAvailable < leftover
          ? existingAvailable
          : leftover;
    }

    final newTake = news.take(newTakeCount).toList();
    final existing = [
      ...learningDue,
      ...reviewDue,
    ].take(existingTakeCount).toList();

    final selected = _interleaveNew(existing: existing, news: newTake);

    // #region agent log
    KanjiCard? firstLearnInSession;
    for (final card in selected) {
      if (isNew(schedules[card.id])) {
        firstLearnInSession = card;
        break;
      }
    }
    _agentLog(
      'H1,H4',
      'due_card_selector.dart:select:result',
      'session queue after interleave',
      {
        'maxNewCards': maxNewCards,
        'newTakeCount': newTakeCount,
        'newTakeIds': [for (final card in newTake) card.id],
        'selectedIds': [for (final card in selected) card.id],
        'firstSelectedId': selected.isEmpty ? null : selected.first.id,
        'firstLearnId': firstLearnInSession?.id,
        'firstLearnKeyword': firstLearnInSession?.keyword,
        'firstLearnJlpt': firstLearnInSession?.jlptLevel.name,
        'n5StillUnknown': n5News.isNotEmpty,
      },
    );
    // #endregion

    return selected;
  }

  int countDue({
    required List<KanjiCard> cards,
    required Map<String, CardSchedule> schedules,
    required DateTime now,
  }) {
    var due = 0;
    for (final card in cards) {
      if (isEncounteredDue(schedules[card.id], now)) due++;
    }
    return due;
  }

  int countNew({
    required List<KanjiCard> cards,
    required Map<String, CardSchedule> schedules,
  }) {
    var n = 0;
    for (final card in cards) {
      if (isNew(schedules[card.id])) n++;
    }
    return n;
  }

  DateTime? nextFutureDue({
    required List<KanjiCard> cards,
    required Map<String, CardSchedule> schedules,
    required DateTime now,
  }) {
    DateTime? next;
    for (final card in cards) {
      final schedule = schedules[card.id];
      if (schedule == null ||
          isNew(schedule) ||
          isAvailableToday(schedule, now)) {
        continue;
      }
      if (next == null || schedule.dueAt.isBefore(next)) {
        next = schedule.dueAt;
      }
    }
    return next;
  }

  int _compareNewLearnOrder(KanjiCard a, KanjiCard b) {
    final aLevel = JlptLevel.sectionOrder.indexOf(a.jlptLevel);
    final bLevel = JlptLevel.sectionOrder.indexOf(b.jlptLevel);
    final levelCompare = aLevel.compareTo(bLevel);
    if (levelCompare != 0) return levelCompare;
    return a.id.compareTo(b.id);
  }

  void _sortByDueThenId(
    List<KanjiCard> cards,
    Map<String, CardSchedule> schedules,
    DateTime now,
  ) {
    cards.sort((a, b) {
      final aDue = schedules[a.id]?.dueAt ?? now;
      final bDue = schedules[b.id]?.dueAt ?? now;
      final dueCompare = aDue.compareTo(bDue);
      if (dueCompare != 0) return dueCompare;
      return a.id.compareTo(b.id);
    });
  }

  /// Spreads new cards through existing due cards.
  ///
  /// Starts with a due card when any exist, avoids dumping all new cards at
  /// the front or back, and is not a rigid Review/New/Review/New pattern.
  List<KanjiCard> _interleaveNew({
    required List<KanjiCard> existing,
    required List<KanjiCard> news,
  }) {
    if (news.isEmpty) return existing;
    if (existing.isEmpty) return news;

    final reviews = List<KanjiCard>.from(existing);
    final incoming = List<KanjiCard>.from(news);
    final result = <KanjiCard>[reviews.removeAt(0)];

    final remainingTotal = reviews.length + incoming.length;
    if (remainingTotal == 0) return result;

    final gap = remainingTotal / incoming.length;
    var nextNewAt = gap / 2;
    var position = 0;
    var newIndex = 0;
    var reviewIndex = 0;
    var lastWasNew = false;

    while (reviewIndex < reviews.length || newIndex < incoming.length) {
      final reviewsRemain = reviewIndex < reviews.length;
      final newsRemain = newIndex < incoming.length;
      var placeNew =
          newsRemain && (!reviewsRemain || position + 1 >= nextNewAt.round());
      if (placeNew && lastWasNew && reviewsRemain) {
        placeNew = false;
      }

      if (placeNew) {
        result.add(incoming[newIndex++]);
        nextNewAt += gap;
        lastWasNew = true;
      } else {
        result.add(reviews[reviewIndex++]);
        lastWasNew = false;
      }
      position++;
    }

    return result;
  }
}

// #region agent log
void _agentLog(
  String hypothesisId,
  String location,
  String message,
  Map<String, Object?> data,
) {
  try {
    final payload = jsonEncode({
      'sessionId': 'f5542b',
      'runId': 'post-fix',
      'hypothesisId': hypothesisId,
      'location': location,
      'message': message,
      'data': data,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    });
    try {
      File(
        r'c:\Users\gdegr\Documents\GitHub\5-Minute-Kanji\debug-f5542b.log',
      ).writeAsStringSync('$payload\n', mode: FileMode.append);
    } catch (_) {}
    print('DEBUG_LOG $payload');
    Future<void>(() async {
      for (final host in ['127.0.0.1', '10.0.2.2']) {
        HttpClient? client;
        try {
          client = HttpClient()
            ..connectionTimeout = const Duration(milliseconds: 400);
          final req = await client.postUrl(
            Uri.parse(
              'http://$host:7457/ingest/ef2d480b-c1db-45a8-82b8-a737609db768',
            ),
          );
          req.headers.set('Content-Type', 'application/json');
          req.headers.set('X-Debug-Session-Id', 'f5542b');
          req.add(utf8.encode(payload));
          await req.close().timeout(const Duration(milliseconds: 400));
        } catch (_) {
        } finally {
          client?.close(force: true);
        }
      }
    });
  } catch (_) {}
}
// #endregion

