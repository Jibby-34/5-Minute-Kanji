import 'dart:math' as math;

import '../core/models/kanji_card.dart';
import 'card_time_estimator.dart';

/// Internal knobs for keeping a sitting near its time goal.
///
/// These are not user settings. Change them here while testing. The sitting
/// still starts from the normal session plan; this only decides when that
/// plan's remaining queue may shrink.
class AdaptiveQueueConfig {
  const AdaptiveQueueConfig({
    this.overrunThreshold = const Duration(seconds: 15),
    this.timeBuffer = const Duration(seconds: 10),
    this.minimumSwapSavings = const Duration(seconds: 5),
    this.priorityTolerance = 0.15,
    this.maximumAdjustmentsPerSession = 5,
  });

  /// Projected time above the goal required before any card is touched.
  ///
  /// A sitting planned at the scheduler's usual 5% slack (a 5-minute goal
  /// landing near 5:15) stays put until it passes this margin.
  final Duration overrunThreshold;

  /// How far under the goal the projection should land once cards are removed.
  final Duration timeBuffer;

  /// A shorter stand-in must beat the removed card by at least this much.
  final Duration minimumSwapSavings;

  /// How far below the removed card a replacement may score.
  ///
  /// Scores come from the existing card priority scorer. 0.15 is a small gap
  /// next to the few tenths that usually separate an ordinary review from a
  /// more urgent one.
  /// The same band decides when two removal candidates count as the same
  /// priority, so the longer one can leave first.
  final double priorityTolerance;

  /// Remove or swap steps allowed in one sitting.
  final int maximumAdjustmentsPerSession;

  AdaptiveQueueConfig copyWith({
    Duration? overrunThreshold,
    Duration? timeBuffer,
    Duration? minimumSwapSavings,
    double? priorityTolerance,
    int? maximumAdjustmentsPerSession,
  }) {
    return AdaptiveQueueConfig(
      overrunThreshold: overrunThreshold ?? this.overrunThreshold,
      timeBuffer: timeBuffer ?? this.timeBuffer,
      minimumSwapSavings: minimumSwapSavings ?? this.minimumSwapSavings,
      priorityTolerance: priorityTolerance ?? this.priorityTolerance,
      maximumAdjustmentsPerSession:
          maximumAdjustmentsPerSession ?? this.maximumAdjustmentsPerSession,
    );
  }
}

/// This sitting's actual pace compared with the estimates made beforehand.
///
/// [CardTimeEstimator] stays the source of each card's expected duration.
/// Samples here only raise that estimate when this sitting is running long,
/// so a fast card cannot shrink the projection and a completed card is not
/// added again on top of the clock.
class SessionPaceTracker {
  Duration _estimated = Duration.zero;
  Duration _actual = Duration.zero;
  int _samples = 0;

  int get samples => _samples;

  SessionPaceSnapshot snapshot() {
    return SessionPaceSnapshot(
      estimated: _estimated,
      actual: _actual,
      samples: _samples,
    );
  }

  void restore(SessionPaceSnapshot snapshot) {
    _estimated = snapshot.estimated;
    _actual = snapshot.actual;
    _samples = snapshot.samples;
  }

  /// [estimated] is the one-showing prediction from before this sample was
  /// folded into the historical model.
  void record(Duration estimated, Duration actual) {
    if (estimated <= Duration.zero) return;
    if (!CardTimeEstimator.isUsableDuration(actual)) return;
    _estimated += estimated;
    _actual += actual;
    _samples++;
  }

  /// 1 until a finished card has a usable time. Later samples pull upward
  /// only, and two samples are enough to trust the sitting's own pace.
  double get factor {
    if (_samples == 0 || _estimated.inMilliseconds <= 0) return 1;
    final ratio = _actual.inMilliseconds / _estimated.inMilliseconds;
    final trust = math.min(1.0, _samples / 2);
    final blended = 1 + trust * (ratio - 1);
    if (blended < 1) return 1;
    if (blended > 3) return 3;
    return blended;
  }

  Duration scale(Duration estimate) {
    if (estimate <= Duration.zero) return const Duration(seconds: 1);
    final scaledMs = (estimate.inMilliseconds * factor).round();
    final seconds = (scaledMs / 1000).round();
    if (seconds < 1) return const Duration(seconds: 1);
    return Duration(seconds: seconds);
  }
}

class SessionPaceSnapshot {
  const SessionPaceSnapshot({
    required this.estimated,
    required this.actual,
    required this.samples,
  });

  final Duration estimated;
  final Duration actual;
  final int samples;
}

/// One card the adjuster can keep, drop, or use as a shorter stand-in.
class AdaptiveQueueCard {
  const AdaptiveQueueCard({
    required this.id,
    required this.card,
    required this.priority,
    required this.estimated,
    required this.protected,
    this.isCurrent = false,
  });

  final String id;
  final KanjiCard card;
  final double priority;

  /// Expected time still to spend on this showing, including both showings
  /// of a new kanji that has not been introduced yet.
  final Duration estimated;

  /// New, learning, relearning, failed-this-sitting, or on screen.
  final bool protected;
  final bool isCurrent;

  bool get canRemove => !protected && !isCurrent;
}

/// One card taken out of the remaining queue, with a shorter stand-in if any.
class AdaptiveQueueStep {
  const AdaptiveQueueStep({
    required this.removedId,
    required this.estimatedSaved,
    this.replacement,
  });

  final String removedId;
  final Duration estimatedSaved;
  final KanjiCard? replacement;

  String? get replacementId => replacement?.id;
}

/// Why a sitting's remaining queue changed, in the shape the debug log uses.
class AdaptiveQueueDecision {
  const AdaptiveQueueDecision({
    required this.changed,
    required this.elapsed,
    required this.estimatedRemainingBefore,
    required this.projectedBefore,
    required this.goal,
    required this.projectedAfter,
    required this.estimatedSaved,
    required this.protectedCount,
    required this.eligibleIds,
    required this.steps,
    required this.adjustmentsUsed,
  });

  final bool changed;
  final Duration elapsed;
  final Duration estimatedRemainingBefore;
  final Duration projectedBefore;
  final Duration goal;
  final Duration projectedAfter;
  final Duration estimatedSaved;
  final int protectedCount;
  final List<String> eligibleIds;
  final List<AdaptiveQueueStep> steps;

  /// Steps already used in this sitting, including [steps].
  final int adjustmentsUsed;

  int get eligibleCount => eligibleIds.length;

  String describe() {
    final removed = steps.map((step) => step.removedId).join(', ');
    final swapped = steps
        .where((step) => step.replacementId != null)
        .map((step) => '${step.removedId}->${step.replacementId}')
        .join(', ');
    return 'elapsed=${elapsed.inSeconds}s '
        'estimatedRemainingBefore=${estimatedRemainingBefore.inSeconds}s '
        'projected=${projectedBefore.inSeconds}s '
        'goal=${goal.inSeconds}s '
        'protected=$protectedCount '
        'eligible=${eligibleIds.join(',')}'
        ' removed=$removed'
        ' swappedIn=${swapped.isEmpty ? '-' : swapped}'
        ' saved=${estimatedSaved.inSeconds}s'
        ' projectedAfter=${projectedAfter.inSeconds}s';
  }
}

/// Decides which future reviews can leave the assigned queue.
///
/// The caller supplies estimates from [CardTimeEstimator] and scores from
/// the existing priority scorer. This class does not schedule, save, or
/// choose the original sitting.
class AdaptiveSessionAdjuster {
  const AdaptiveSessionAdjuster({this.config = const AdaptiveQueueConfig()});

  final AdaptiveQueueConfig config;

  bool needsAdjustment({
    required Duration elapsed,
    required Duration goal,
    required List<AdaptiveQueueCard> queue,
    required int adjustmentsUsed,
  }) {
    if (adjustmentsUsed >= config.maximumAdjustmentsPerSession) return false;
    if (!queue.any((card) => card.canRemove)) return false;
    final projected = elapsed + _remaining(queue);
    return projected > goal + config.overrunThreshold;
  }

  AdaptiveQueueDecision decide({
    required Duration elapsed,
    required Duration goal,
    required List<AdaptiveQueueCard> queue,
    required List<AdaptiveQueueCard> replacements,
    required Set<String> droppedIds,
    required int adjustmentsUsed,
    required int maxQueueLength,
  }) {
    final remainingBefore = _remaining(queue);
    final projectedBefore = elapsed + remainingBefore;
    final protectedCount = queue.where((card) => card.protected).length;
    final eligibleIds = [
      for (final card in queue)
        if (card.canRemove && !droppedIds.contains(card.id)) card.id,
    ];
    final limit = goal + config.overrunThreshold;
    if (projectedBefore <= limit ||
        adjustmentsUsed >= config.maximumAdjustmentsPerSession ||
        eligibleIds.isEmpty) {
      return AdaptiveQueueDecision(
        changed: false,
        elapsed: elapsed,
        estimatedRemainingBefore: remainingBefore,
        projectedBefore: projectedBefore,
        goal: goal,
        projectedAfter: projectedBefore,
        estimatedSaved: Duration.zero,
        protectedCount: protectedCount,
        eligibleIds: eligibleIds,
        steps: const [],
        adjustmentsUsed: adjustmentsUsed,
      );
    }

    final target = goal > config.timeBuffer
        ? goal - config.timeBuffer
        : Duration.zero;
    final working = List<AdaptiveQueueCard>.from(queue);
    final dropped = Set<String>.from(droppedIds);
    final inQueue = working.map((card) => card.id).toSet();
    final steps = <AdaptiveQueueStep>[];
    var used = adjustmentsUsed;
    var projected = projectedBefore;

    while (projected > target && used < config.maximumAdjustmentsPerSession) {
      final eligible = working
          .where((card) => card.canRemove && !dropped.contains(card.id))
          .toList();
      if (eligible.isEmpty) break;
      final victim = _chooseRemoval(eligible);
      final index = working.indexWhere((card) => card.id == victim.id);
      if (index <= 0) break;

      final swap = working.length > maxQueueLength
          ? null
          : _chooseSwap(
              victim: victim,
              replacements: replacements,
              inQueue: inQueue,
              dropped: dropped,
            );
      if (swap == null) {
        working.removeAt(index);
        inQueue.remove(victim.id);
        dropped.add(victim.id);
        steps.add(
          AdaptiveQueueStep(
            removedId: victim.id,
            estimatedSaved: victim.estimated,
          ),
        );
      } else {
        working[index] = swap;
        inQueue
          ..remove(victim.id)
          ..add(swap.id);
        dropped.add(victim.id);
        final saved = victim.estimated - swap.estimated;
        steps.add(
          AdaptiveQueueStep(
            removedId: victim.id,
            estimatedSaved: saved < Duration.zero ? Duration.zero : saved,
            replacement: swap.card,
          ),
        );
      }
      used++;
      projected = elapsed + _remaining(working);
    }

    final remainingAfter = _remaining(working);
    final saved = remainingBefore - remainingAfter;
    return AdaptiveQueueDecision(
      changed: steps.isNotEmpty,
      elapsed: elapsed,
      estimatedRemainingBefore: remainingBefore,
      projectedBefore: projectedBefore,
      goal: goal,
      projectedAfter: elapsed + remainingAfter,
      estimatedSaved: saved.isNegative ? Duration.zero : saved,
      protectedCount: protectedCount,
      eligibleIds: eligibleIds,
      steps: steps,
      adjustmentsUsed: used,
    );
  }

  AdaptiveQueueCard _chooseRemoval(List<AdaptiveQueueCard> eligible) {
    var lowest = eligible.first.priority;
    for (final card in eligible) {
      if (card.priority < lowest) lowest = card.priority;
    }
    final bandLimit = lowest + config.priorityTolerance;
    final band = eligible.where((card) => card.priority <= bandLimit).toList();
    band.sort((a, b) {
      final byTime = b.estimated.compareTo(a.estimated);
      if (byTime != 0) return byTime;
      final byPriority = a.priority.compareTo(b.priority);
      if (byPriority != 0) return byPriority;
      return a.id.compareTo(b.id);
    });
    return band.first;
  }

  AdaptiveQueueCard? _chooseSwap({
    required AdaptiveQueueCard victim,
    required List<AdaptiveQueueCard> replacements,
    required Set<String> inQueue,
    required Set<String> dropped,
  }) {
    final floor = victim.priority - config.priorityTolerance;
    final viable = <AdaptiveQueueCard>[];
    for (final candidate in replacements) {
      if (candidate.protected || candidate.isCurrent) continue;
      if (candidate.id == victim.id) continue;
      if (inQueue.contains(candidate.id) || dropped.contains(candidate.id)) {
        continue;
      }
      final savings = victim.estimated - candidate.estimated;
      if (savings < config.minimumSwapSavings) continue;
      if (candidate.priority < floor) continue;
      viable.add(candidate);
    }
    if (viable.isEmpty) return null;

    final preferred = viable
        .where((candidate) => candidate.priority >= victim.priority)
        .toList();
    final pool = preferred.isNotEmpty ? preferred : viable;
    final preferPriority = preferred.isNotEmpty;
    pool.sort((a, b) {
      if (preferPriority) {
        final byPriority = b.priority.compareTo(a.priority);
        if (byPriority != 0) return byPriority;
      }
      final bySavings = (victim.estimated - b.estimated).compareTo(
        victim.estimated - a.estimated,
      );
      if (bySavings != 0) return bySavings;
      if (!preferPriority) {
        final byPriority = b.priority.compareTo(a.priority);
        if (byPriority != 0) return byPriority;
      }
      return a.id.compareTo(b.id);
    });
    return pool.first;
  }

  Duration _remaining(List<AdaptiveQueueCard> queue) {
    var total = Duration.zero;
    for (final card in queue) {
      total += card.estimated;
    }
    return total;
  }
}
