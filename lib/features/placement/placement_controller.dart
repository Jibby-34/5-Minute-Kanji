import 'package:flutter/foundation.dart';

import '../../core/models/kanji_card.dart';
import '../../core/models/placement.dart';
import '../../services/placement_service.dart';
import '../../services/placement_test_engine.dart';

enum PlacementPhase { loading, selfAssessment, intro, asking, saving, results }

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
  List<KanjiCard> _catalog = const [];
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

    PlacementSelfAssessment? assessment;
    try {
      _catalog = await service.catalog();
      _pool = await service.candidates();
      final saved = await service.progress();
      _answers = saved.answers;
      assessment = saved.selfAssessment;
    } catch (_) {
      _catalog = const [];
      _pool = const [];
      _answers = const [];
      assessment = null;
    }

    // Nothing left to ask: finish straight away, without the self-assessment.
    final probe = PlacementTestEngine(
      maxQuestions: engine.maxQuestions,
      selectionSeed: engine.selectionSeed,
    ).replay(_pool, const [], corpus: _catalog);
    if (probe.isFinished) {
      _run = probe;
      await _finish();
      return;
    }

    if (assessment == null) {
      phase = PlacementPhase.selfAssessment;
      notifyListeners();
      return;
    }
    if (assessment == PlacementSelfAssessment.newUser) {
      await _finishFromStart();
      return;
    }
    await _openRun(assessment);
  }

  /// Records the starting guess. [PlacementSelfAssessment.newUser] skips the
  /// kanji questions and leaves every card new.
  Future<void> choose(PlacementSelfAssessment assessment) async {
    if (phase != PlacementPhase.selfAssessment) return;
    try {
      await service.saveSelfAssessment(assessment);
    } catch (_) {
      // The guess can still shape this sitting if saving the preference fails.
    }
    if (assessment == PlacementSelfAssessment.newUser) {
      await _finishFromStart();
      return;
    }
    await _openRun(assessment);
  }

  Future<void> _openRun(PlacementSelfAssessment assessment) async {
    final seed = _pool.isEmpty ? engine.selectionSeed : await _selectionSeed();
    _run = PlacementTestEngine(
      maxQuestions: engine.maxQuestions,
      selectionSeed: seed,
    ).replay(_pool, _answers, corpus: _catalog, selfAssessment: assessment);

    if (_run!.isFinished) {
      await _finish();
      return;
    }

    phase = PlacementPhase.intro;
    notifyListeners();
  }

  /// A new learner starts at the beginning. No kanji is marked known.
  Future<void> _finishFromStart() async {
    phase = PlacementPhase.saving;
    notifyListeners();
    try {
      summary = await service.complete(
        const PlacementOutcome(knownCardIds: [], answeredCount: 0),
      );
    } catch (_) {
      summary = const PlacementSummary(
        knownCount: 0,
        headline: 'Your starting point is ready.',
      );
    }
    phase = PlacementPhase.results;
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
      summary = await service.complete(
        run?.outcome() ?? PlacementOutcome.empty,
      );
    } catch (_) {
      summary = const PlacementSummary(
        knownCount: 0,
        headline: 'Your starting point is ready.',
      );
    }
    phase = PlacementPhase.results;
    notifyListeners();
  }

  Future<int> _selectionSeed() async {
    try {
      return await service.ensureSelectionSeed();
    } catch (_) {
      return engine.selectionSeed == 0 ? 1 : engine.selectionSeed;
    }
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
