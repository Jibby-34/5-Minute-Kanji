import '../core/models/kanji_card.dart';
import '../core/models/review.dart';

/// In-memory queue for one study sitting. Duration comes from [config], not a hardcoded 5.
class ReviewSession {
  ReviewSession({
    required this.config,
    required List<KanjiCard> cards,
    this.isPractice = false,
    DateTime? startTime,
  }) : startTime = startTime ?? DateTime.now(),
       initialCount = cards.length,
       _pool = List<KanjiCard>.from(cards),
       _queue = List<KanjiCard>.from(cards);

  static const requeueOffset = 3;

  final ReviewSessionConfig config;
  final bool isPractice;
  final DateTime startTime;
  final int initialCount;
  final List<KanjiCard> _pool;
  final List<KanjiCard> _queue;
  final Set<String> _seenIds = {};
  final Set<String> _againIds = {};
  int _passedCount = 0;

  /// Cards originally selected for this sitting. Used to re-offer due cards.
  List<KanjiCard> get pool => List<KanjiCard>.unmodifiable(_pool);

  List<KanjiCard> get queued => List<KanjiCard>.unmodifiable(_queue);

  KanjiCard? get current => _queue.isEmpty ? null : _queue.first;

  bool get isComplete => _queue.isEmpty;

  bool hasReviewed(String cardId) => _seenIds.contains(cardId);

  int get remaining => _queue.length;

  int get reviewedCount => _seenIds.length;

  int get againCount => _againIds.length;

  int get successfulCount => reviewedCount - againCount;

  /// 1-based index shown as `n / total`. Requeued cards cap at [initialCount].
  int get displayIndex {
    if (initialCount == 0) return 0;
    return (_passedCount + 1).clamp(1, initialCount);
  }

  Duration elapsedAt(DateTime now) {
    final value = now.difference(startTime);
    return value.isNegative ? Duration.zero : value;
  }

  /// Finish the Learn flow: drop the current card without an immediate review.
  KanjiCard? completeIntroduction() {
    if (_queue.isEmpty) return null;
    final card = _queue.removeAt(0);
    _seenIds.add(card.id);
    _passedCount++;
    return card;
  }

  /// Put due session cards back in play. Missing cards keep [dueCards] order
  /// and are mixed a few places later, so a just-learned card does not jump
  /// ahead of the remaining reviews and new cards.
  void offerDue(List<KanjiCard> dueCards) {
    if (dueCards.isEmpty) return;
    final queuedIds = _queue.map((card) => card.id).toSet();
    final missing = dueCards
        .where((card) => !queuedIds.contains(card.id))
        .toList();
    if (missing.isEmpty) return;
    final insertAt = requeueOffset.clamp(0, _queue.length);
    _queue.insertAll(insertAt, missing);
  }

  /// Apply a rating to the current card. Returns the card just rated.
  KanjiCard? recordRating(ReviewResult result) {
    if (_queue.isEmpty) return null;
    final card = _queue.removeAt(0);
    _seenIds.add(card.id);

    if (result == ReviewResult.again) {
      _againIds.add(card.id);
      final insertAt = requeueOffset.clamp(0, _queue.length);
      _queue.insert(insertAt, card);
    } else {
      _passedCount++;
    }
    return card;
  }

  SessionSummary toSummary({required DateTime now, DateTime? nextReviewAt}) {
    return SessionSummary(
      duration: elapsedAt(now),
      reviewedCount: reviewedCount,
      successfulCount: successfulCount < 0 ? 0 : successfulCount,
      againCount: againCount,
      nextReviewAt: nextReviewAt,
    );
  }
}
