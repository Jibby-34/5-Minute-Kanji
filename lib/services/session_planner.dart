import 'dart:math' as math;

import '../core/models/kanji_card.dart';
import 'due_card_selector.dart';

/// One eligible card, already scored and timed by the scheduling layer.
class SessionCandidate {
  const SessionCandidate({
    required this.card,
    required this.priority,
    required this.estimated,
    required this.isNew,
  });

  final KanjiCard card;
  final double priority;

  /// Expected time for one showing.
  final Duration estimated;
  final bool isNew;

  /// Seconds reserved in the sitting. A new kanji is introduced and then
  /// retrieved before the sitting ends, so its one-showing estimate counts
  /// twice. A non-positive estimate still reserves one second per showing.
  int get reservedSeconds {
    final showing = math.max(1, estimated.inSeconds);
    return isNew ? showing * 2 : showing;
  }
}

/// The recommended sitting and the eligible cards that did not fit.
class PlannedSession {
  const PlannedSession({
    required this.selected,
    required this.overflow,
    required this.estimated,
  });

  static const empty = PlannedSession(
    selected: [],
    overflow: [],
    estimated: Duration.zero,
  );

  /// Study order for the normal session. New cards are spread through reviews.
  final List<SessionCandidate> selected;

  /// Eligible cards that did not fit, highest priority first.
  final List<SessionCandidate> overflow;

  final Duration estimated;
}

/// Picks cards for a time budget.
///
/// Every new kanji allowed today is included, even when that pushes the
/// sitting past the budget. Each new kanji reserves two showings — the
/// introduction and the retrieval later in the same sitting — and reviews
/// then fill whatever time is left, highest priority first. Greedy, not
/// optimal. A review is skipped when it would push the sitting past the
/// upper tolerance, unless it is the only card and leaving it out would drop
/// an important review forever. Scoring stays outside this class.
class SessionPlanner {
  const SessionPlanner({
    this.upperTolerance = 1.05,
    this.arranger = const DueCardSelector(),
  });

  /// A 5-minute budget may run to about 5:15. It is not a hard stopwatch.
  final double upperTolerance;
  final DueCardSelector arranger;

  PlannedSession plan({
    required List<SessionCandidate> candidates,
    required Duration budget,
    required int maxNewCards,
    int Function(KanjiCard a, KanjiCard b) compareNewCards =
        compareKanjiLearnOrder,
  }) {
    if (budget.inSeconds <= 0 || candidates.isEmpty) {
      return PlannedSession.empty;
    }

    final capped = _capNewCards(candidates, maxNewCards, compareNewCards);
    if (capped.isEmpty) return PlannedSession.empty;

    final news = capped.where((candidate) => candidate.isNew).toList();
    final reviews = capped.where((candidate) => !candidate.isNew).toList()
      ..sort(_byPriority);
    final upper = _upperSeconds(budget);
    final chosen = <SessionCandidate>[];
    var used = 0;

    for (final candidate in news) {
      chosen.add(candidate);
      used += candidate.reservedSeconds;
    }

    for (final candidate in reviews) {
      final seconds = candidate.reservedSeconds;
      if (chosen.isEmpty && seconds > upper) {
        chosen.add(candidate);
        used += seconds;
        break;
      }
      if (used + seconds <= upper) {
        chosen.add(candidate);
        used += seconds;
      }
    }

    final selectedIds = chosen.map((candidate) => candidate.card.id).toSet();
    final overflow =
        capped
            .where((candidate) => !selectedIds.contains(candidate.card.id))
            .toList()
          ..sort(_byPriority);

    return PlannedSession(
      selected: _arrange(chosen, compareNewCards),
      overflow: overflow,
      estimated: _sum(chosen),
    );
  }

  int _upperSeconds(Duration budget) {
    final scaled = (budget.inSeconds * upperTolerance).round();
    return scaled < budget.inSeconds ? budget.inSeconds : scaled;
  }

  List<SessionCandidate> _capNewCards(
    List<SessionCandidate> candidates,
    int maxNewCards,
    int Function(KanjiCard a, KanjiCard b) compareNewCards,
  ) {
    final limit = maxNewCards < 0 ? 0 : maxNewCards;
    final news = candidates.where((candidate) => candidate.isNew).toList()
      ..sort((a, b) => compareNewCards(a.card, b.card));
    final allowed = news
        .take(limit)
        .map((candidate) => candidate.card.id)
        .toSet();
    return candidates
        .where(
          (candidate) =>
              !candidate.isNew || allowed.contains(candidate.card.id),
        )
        .toList();
  }

  List<SessionCandidate> _arrange(
    List<SessionCandidate> chosen,
    int Function(KanjiCard a, KanjiCard b) compareNewCards,
  ) {
    final byId = {for (final candidate in chosen) candidate.card.id: candidate};
    final existing = chosen.where((candidate) => !candidate.isNew).toList()
      ..sort(_byPriority);
    final news = chosen.where((candidate) => candidate.isNew).toList()
      ..sort((a, b) => compareNewCards(a.card, b.card));
    final ordered = arranger.arrangeSession(
      existing: existing.map((candidate) => candidate.card).toList(),
      news: news.map((candidate) => candidate.card).toList(),
    );
    return [
      for (final card in ordered)
        if (byId[card.id] != null) byId[card.id]!,
    ];
  }

  Duration _sum(List<SessionCandidate> chosen) {
    var seconds = 0;
    for (final candidate in chosen) {
      seconds += candidate.reservedSeconds;
    }
    return Duration(seconds: seconds);
  }

  static int _byPriority(SessionCandidate a, SessionCandidate b) {
    final byScore = b.priority.compareTo(a.priority);
    if (byScore != 0) return byScore;
    return a.card.id.compareTo(b.card.id);
  }
}
