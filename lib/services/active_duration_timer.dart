/// Active time for one card.
///
/// Pauses drop out, and [start] clears whatever the previous card accumulated
/// so a rebuild or the next card cannot inherit it. This is separate from the
/// daily session clock.
class ActiveDurationTimer {
  Duration _elapsed = Duration.zero;
  DateTime? _runningSince;
  bool _started = false;

  bool get isRunning => _runningSince != null;

  void start(DateTime now) {
    _elapsed = Duration.zero;
    _runningSince = now;
    _started = true;
  }

  void pause(DateTime now) {
    if (!_started) return;
    final start = _runningSince;
    if (start == null) return;
    if (!now.isBefore(start)) {
      _elapsed += now.difference(start);
    }
    _runningSince = null;
  }

  void resume(DateTime now) {
    if (!_started || _runningSince != null) return;
    _runningSince = now;
  }

  Duration elapsedAt(DateTime now) {
    if (!_started) return Duration.zero;
    var total = _elapsed;
    final start = _runningSince;
    if (start != null && !now.isBefore(start)) {
      total += now.difference(start);
    }
    return total.isNegative ? Duration.zero : total;
  }
}
