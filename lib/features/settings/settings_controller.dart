import 'package:flutter/foundation.dart';

import '../../core/models/progress.dart';
import '../../core/models/start_of_day.dart';
import '../../repositories/progress_repository.dart';
import '../../services/daily_workload_estimator.dart';

class SettingsController extends ChangeNotifier {
  SettingsController({
    required this.progressRepository,
    this.estimator = const DailyWorkloadEstimator(),
  });

  final ProgressRepository progressRepository;
  final DailyWorkloadEstimator estimator;

  bool loading = true;
  AppSettings settings = const AppSettings();
  DailyWorkloadEstimate estimate = const DailyWorkloadEstimate(
    minMinutes: 0,
    maxMinutes: 0,
  );

  int get newKanjiPerDay => settings.newKanjiPerDay;

  StartOfDay get startOfDay => settings.startOfDay;

  Future<void> load() async {
    loading = true;
    notifyListeners();

    try {
      settings = await progressRepository.getSettings();
      _refreshEstimate();
    } catch (_) {
      settings = const AppSettings();
      _refreshEstimate();
    }

    loading = false;
    notifyListeners();
  }

  Future<void> setNewKanjiPerDay(int value) async {
    final clamped = AppSettings.clampNewKanjiPerDay(value);
    if (clamped == settings.newKanjiPerDay && !loading) {
      _refreshEstimate();
      notifyListeners();
      return;
    }

    settings = settings.copyWith(newKanjiPerDay: clamped);
    _refreshEstimate();
    notifyListeners();
    await progressRepository.saveSettings(settings);
  }

  Future<void> setStartOfDay(StartOfDay value) async {
    final next = StartOfDay.normalize(hour: value.hour, minute: value.minute);
    if (next == settings.startOfDay && !loading) return;

    settings = settings.copyWith(startOfDay: next);
    notifyListeners();
    await progressRepository.saveSettings(settings);
  }

  void _refreshEstimate() {
    estimate = estimator.estimate(
      newKanjiPerDay: settings.newKanjiPerDay,
      averageSecondsPerCard: settings.averageSecondsPerCard,
    );
  }
}
