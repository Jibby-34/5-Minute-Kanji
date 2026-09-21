import 'package:fiveminutekanji/app.dart';
import 'package:fiveminutekanji/core/models/notification_settings.dart';
import 'package:fiveminutekanji/core/models/progress.dart';
import 'package:fiveminutekanji/core/models/start_of_day.dart';
import 'package:fiveminutekanji/core/navigation/app_navigator.dart';
import 'package:fiveminutekanji/data/hardcoded_kanji_repository.dart';
import 'package:fiveminutekanji/data/shared_prefs_progress_repository.dart';
import 'package:fiveminutekanji/features/settings/settings_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  void usePhoneViewport(WidgetTester tester) {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  group('persistence', () {
    test('defaults are a daily reminder at 7:00 PM', () {
      const settings = NotificationSettings.defaults;

      expect(settings.dailyReminderEnabled, isTrue);
      expect(settings.reminderTime.hour, 19);
      expect(settings.reminderTime.minute, 0);
    });

    test('reminder settings survive a JSON round trip', () {
      const original = AppSettings(
        newKanjiPerDay: 7,
        startOfDay: StartOfDay(hour: 3, minute: 30),
        notifications: NotificationSettings(
          dailyReminderEnabled: false,
          reminderTime: ReminderTime(hour: 21, minute: 15),
        ),
      );

      final restored = AppSettings.fromJson(original.toJson());

      expect(restored.notifications, original.notifications);
      expect(restored.startOfDay, original.startOfDay);
      expect(restored.newKanjiPerDay, 7);
    });

    test('settings stored before reminders existed keep the defaults', () {
      final restored = AppSettings.fromJson(const {
        'averageSecondsPerCard': 12,
        'newKanjiPerDay': 5,
        'startOfDayHour': 4,
        'startOfDayMinute': 0,
      });

      expect(restored.notifications, NotificationSettings.defaults);
    });

    test('an out-of-range reminder time is clamped', () {
      final restored = AppSettings.fromJson(const {
        'notifications': {'reminderHour': 99, 'reminderMinute': -5},
      });

      expect(restored.notifications.reminderTime, const ReminderTime(hour: 23));
    });

    test('a saved reminder time is read back by a new repository', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final progress = SharedPrefsProgressRepository(prefs);

      await progress.saveSettings(
        const AppSettings(
          notifications: NotificationSettings(
            reminderTime: ReminderTime(hour: 6, minute: 5),
          ),
        ),
      );

      final reopened = SharedPrefsProgressRepository(prefs);
      final settings = await reopened.getSettings();

      expect(settings.notifications.dailyReminderEnabled, isTrue);
      expect(
        settings.notifications.reminderTime,
        const ReminderTime(hour: 6, minute: 5),
      );
    });
  });

  group('settings screen', () {
    Future<void> openSettings(WidgetTester tester) async {
      usePhoneViewport(tester);
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      const kanji = HardcodedKanjiRepository();
      final progress = SharedPrefsProgressRepository(prefs);
      final cards = await kanji.getAll();
      await progress.seedIfNeeded(cards.map((card) => card.id).toList());

      await tester.pumpWidget(
        FiveMinuteKanjiApp(
          kanjiRepository: kanji,
          progressRepository: progress,
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      await tester.tap(find.byTooltip('Settings'));
      await tester.pumpAndSettle();
    }

    testWidgets('shows the reminder section with its defaults', (tester) async {
      await openSettings(tester);

      expect(find.text('Study reminders'), findsOneWidget);
      expect(find.text('Daily reminder'), findsOneWidget);
      expect(find.text('Reminder time'), findsOneWidget);
      expect(find.text('7:00 PM'), findsOneWidget);
      expect(tester.widget<Switch>(find.byType(Switch)).value, isTrue);
      // No permission notice without a notification gateway.
      expect(find.text('Open Settings'), findsNothing);
    });

    testWidgets('the reminder time opens the platform time picker', (
      tester,
    ) async {
      await openSettings(tester);

      await tester.ensureVisible(find.text('7:00 PM'));
      await tester.tap(find.text('7:00 PM'));
      await tester.pumpAndSettle();
      expect(find.byType(TimePickerDialog), findsOneWidget);

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(find.text('7:00 PM'), findsOneWidget);
    });

    testWidgets('turning the reminder off disables the time row', (
      tester,
    ) async {
      await openSettings(tester);

      await tester.tap(find.byType(Switch));
      await tester.pumpAndSettle();

      expect(tester.widget<Switch>(find.byType(Switch)).value, isFalse);
      await tester.tap(find.text('7:00 PM'));
      await tester.pumpAndSettle();
      expect(find.byType(TimePickerDialog), findsNothing);
    });
  });

  group('notification tap', () {
    testWidgets('returns to Home without starting a session', (tester) async {
      usePhoneViewport(tester);
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      const kanji = HardcodedKanjiRepository();
      final progress = SharedPrefsProgressRepository(prefs);
      final cards = await kanji.getAll();
      await progress.seedIfNeeded(cards.map((card) => card.id).toList());

      await tester.pumpWidget(
        FiveMinuteKanjiApp(
          kanjiRepository: kanji,
          progressRepository: progress,
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      await tester.tap(find.byTooltip('Settings'));
      await tester.pumpAndSettle();
      expect(find.byType(SettingsScreen), findsOneWidget);

      AppNavigator.openHome();
      await tester.pumpAndSettle();

      expect(find.byType(SettingsScreen), findsNothing);
      expect(find.text('kanji remaining today'), findsOneWidget);
      expect(find.text('Start Review'), findsOneWidget);
    });
  });
}
