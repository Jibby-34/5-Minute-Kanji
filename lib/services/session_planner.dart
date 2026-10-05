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
  final Duration estimated;
  final bool isNew;
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

/// Picks the highest-value cards whose estimates fit a time budget.
///
/// Greedy, not optimal. A card is skipped when it would push the sitting
/// past the upper tolerance, unless it is the only card and leaving it out
/// would drop an important review forever. Scoring stays outside this class.
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
  }) {
    if (budget.inSeconds <= 0 || candidates.isEmpty) {
      return PlannedSession.empty;
    }

    final capped = _capNewCards(candidates, maxNewCards);
    if (capped.isEmpty) return PlannedSession.empty;

    final pool = List<SessionCandidate>.from(capped)..sort(_byPriority);
    final upper = _upperSeconds(budget);
    final chosen = <SessionCandidate>[];
    var used = 0;

    for (final candidate in pool) {
      final seconds = math.max(1, candidate.estimated.inSeconds);
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
      selected: _arrange(chosen),
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
  ) {
    final limit = maxNewCards < 0 ? 0 : maxNewCards;
    final news = candidates.where((candidate) => candidate.isNew).toList()
      ..sort((a, b) => compareKanjiLearnOrder(a.card, b.card));
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

  List<SessionCandidate> _arrange(List<SessionCandidate> chosen) {
    final byId = {for (final candidate in chosen) candidate.card.id: candidate};
    final existing = chosen.where((candidate) => !candidate.isNew).toList()
      ..sort(_byPriority);
    final news = chosen.where((candidate) => candidate.isNew).toList()
      ..sort((a, b) => compareKanjiLearnOrder(a.card, b.card));
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
      seconds += math.max(0, candidate.estimated.inSeconds);
    }
    return Duration(seconds: seconds);
  }

  static int _byPriority(SessionCandidate a, SessionCandidate b) {
    final byScore = b.priority.compareTo(a.priority);
    if (byScore != 0) return byScore;
    return a.card.id.compareTo(b.card.id);
  }
}
