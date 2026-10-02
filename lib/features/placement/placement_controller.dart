import 'package:flutter/foundation.dart';

import '../../core/models/kanji_card.dart';
import '../../core/models/placement.dart';
import '../../services/placement_service.dart';
import '../../services/placement_test_engine.dart';

enum PlacementPhase { loading, intro, asking, saving, results }

class PlacementController extends ChangeNotifier {
  PlacementController({
    required this.service,
    this.engine = const PlacementTestEngine(),
  });

  final PlacementService service;
  final PlacementTestEngine engine;

  PlacementPhase phase = PlacementPhase.loading;
  PlacementSummary? summary;

  List<KanjiCard> _pool = const [];
  List<PlacementAnswer> _answers = const [];
  PlacementRun? _run;

  List<PlacementAnswer>? _pendingSave;
  bool _saving = false;

  KanjiCard? get question => _run?.currentQuestion;

  int get answeredCount => _answers.length;

  /// Approximate length of the test, for the progress indicator.
  int get estimatedTotal => _run?.estimatedTotal ?? 0;

  double get progress {
    final total = estimatedTotal;
    if (total <= 0) return 0;
    return (answeredCount / total).clamp(0.0, 1.0);
  }

  /// True when a previous run was interrupted and can be picked up.
  bool get isResuming => answeredCount > 0;

  Future<void> load() async {
    phase = PlacementPhase.loading;
    notifyListeners();

    try {
      _pool = await service.candidates();
      _answers = (await service.progress()).answers;
    } catch (_) {
      _pool = const [];
      _answers = const [];
    }
    _run = engine.replay(_pool, _answers);

    // Nothing to ask: finish straight away rather than show an empty test.
    if (_run!.isFinished) {
      await _finish();
      return;
    }

    phase = PlacementPhase.intro;
    notifyListeners();
  }

  void start() {
    if (phase != PlacementPhase.intro) return;
    phase = PlacementPhase.asking;
    notifyListeners();
  }

  Future<void> answer({required bool known}) async {
    final run = _run;
    final card = run?.currentQuestion;
    if (phase != PlacementPhase.asking || run == null || card == null) return;

    _answers = [..._answers, PlacementAnswer(cardId: card.id, known: known)];
    run.record(PlacementAnswer(cardId: card.id, known: known));

    // The next kanji goes up before anything is written to disk; a calibration
    // tap should never wait on storage.
    final finished = run.isFinished;
    if (finished) phase = PlacementPhase.saving;
    notifyListeners();

    await _persistAnswers();
    if (finished) await _finish();
  }

  Future<void> _finish() async {
    final run = _run;
    phase = PlacementPhase.saving;
    notifyListeners();

    try {
      summary = await service.complete(run?.outcome() ?? PlacementOutcome.empty);
    } catch (_) {
      summary = const PlacementSummary(knownCount: 0);
    }
    phase = PlacementPhase.results;
    notifyListeners();
  }

  /// Serialises writes so two quick taps cannot persist out of order.
  Future<void> _persistAnswers() async {
    _pendingSave = _answers;
    if (_saving) return;
    _saving = true;
    try {
      while (_pendingSave != null) {
        final snapshot = _pendingSave!;
        _pendingSave = null;
        await service.saveAnswers(snapshot);
      }
    } catch (_) {
      // An unsaved answer only costs the user that question on a resume.
    } finally {
      _saving = false;
    }
  }
}
