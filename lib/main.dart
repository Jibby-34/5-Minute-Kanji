import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app.dart';
import 'core/licenses/third_party_licenses.dart';
import 'core/navigation/app_navigator.dart';
import 'data/hardcoded_kanji_repository.dart';
import 'data/shared_prefs_curriculum_repository.dart';
import 'data/shared_prefs_progress_repository.dart';
import 'services/analytics/analytics_service.dart';
import 'services/analytics/firebase_startup.dart';
import 'services/curriculum/curriculum_access.dart';
import 'services/curriculum/curriculum_analytics.dart';
import 'services/curriculum/store_curriculum_billing.dart';
import 'services/daily_workload.dart';
import 'services/local_notification_gateway.dart';
import 'services/reminder_scheduler.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  registerThirdPartyLicenses();

  const kanjiRepository = HardcodedKanjiRepository();
  final prefsFuture = SharedPreferences.getInstance();
  final firebaseReady = FirebaseStartup.initialize();
  final prefs = await prefsFuture;
  if (await firebaseReady) FirebaseStartup.installCrashHandlers();
  final analytics = AnalyticsService(
    client: FirebaseStartup.isReady
        ? FirebaseAnalyticsClient()
        : const NoopAnalyticsClient(),
    reportedTransactionIds:
        prefs.getStringList(AnalyticsService.reportedTransactionIdsKey) ??
        const [],
    onReportedTransactionIdsChanged: (ids) {
      unawaited(
        prefs.setStringList(AnalyticsService.reportedTransactionIdsKey, ids),
      );
    },
  );
  final progressRepository = SharedPrefsProgressRepository(prefs);
  final curriculumAccess = CurriculumAccess(
    progressRepository: progressRepository,
    repository: SharedPrefsCurriculumRepository(prefs),
    billing: StoreCurriculumBilling(),
    analytics: CurriculumAnalytics(events: analytics),
  );

  final cards = await kanjiRepository.getAll();
  await progressRepository.seedIfNeeded(cards.map((card) => card.id).toList());
  await curriculumAccess.load();

  // The notification plugin initialises lazily on first use, so startup is not
  // held up by it. Home's first load schedules the reminder.
  final reminderScheduler = ReminderScheduler(
    gateway: LocalNotificationGateway(onReminderTapped: AppNavigator.openHome),
    progressRepository: progressRepository,
    workloadService: DailyWorkloadService(
      kanjiRepository: kanjiRepository,
      progressRepository: progressRepository,
      curriculumAccess: curriculumAccess,
      analytics: analytics,
    ),
  );

  runApp(
    FiveMinuteKanjiApp(
      kanjiRepository: kanjiRepository,
      progressRepository: progressRepository,
      reminderScheduler: reminderScheduler,
      curriculumAccess: curriculumAccess,
      analytics: analytics,
    ),
  );
}
