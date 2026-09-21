import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app.dart';
import 'core/licenses/third_party_licenses.dart';
import 'core/navigation/app_navigator.dart';
import 'data/hardcoded_kanji_repository.dart';
import 'data/shared_prefs_progress_repository.dart';
import 'services/daily_workload.dart';
import 'services/local_notification_gateway.dart';
import 'services/reminder_scheduler.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  registerThirdPartyLicenses();

  const kanjiRepository = HardcodedKanjiRepository();
  final prefs = await SharedPreferences.getInstance();
  final progressRepository = SharedPrefsProgressRepository(prefs);

  final cards = await kanjiRepository.getAll();
  await progressRepository.seedIfNeeded(cards.map((card) => card.id).toList());

  // The notification plugin initialises lazily on first use, so startup is not
  // held up by it. Home's first load schedules the reminder.
  final reminderScheduler = ReminderScheduler(
    gateway: LocalNotificationGateway(onReminderTapped: AppNavigator.openHome),
    progressRepository: progressRepository,
    workloadService: DailyWorkloadService(
      kanjiRepository: kanjiRepository,
      progressRepository: progressRepository,
    ),
  );

  runApp(
    FiveMinuteKanjiApp(
      kanjiRepository: kanjiRepository,
      progressRepository: progressRepository,
      reminderScheduler: reminderScheduler,
    ),
  );
}
