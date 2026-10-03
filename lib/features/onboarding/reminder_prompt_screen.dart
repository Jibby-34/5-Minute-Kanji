import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../../repositories/progress_repository.dart';
import '../../services/notification_gateway.dart';
import '../../services/reminder_scheduler.dart';
import '../../widgets/primary_button.dart';
import '../settings/settings_controller.dart';
import 'widgets/onboarding_scaffold.dart';

/// Offered once, after the first session, never at launch.
///
/// Both answers lead to the same place: the app. Declining only turns the
/// app's own reminder off, which Settings can turn back on later.
class ReminderPromptScreen extends StatelessWidget {
  const ReminderPromptScreen({super.key, required this.onDone});

  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (context) => SettingsController(
        progressRepository: context.read<ProgressRepository>(),
        reminderScheduler: context.read<ReminderScheduler?>(),
      )..load(),
      child: _ReminderPromptView(onDone: onDone),
    );
  }
}

class _ReminderPromptView extends StatelessWidget {
  const _ReminderPromptView({required this.onDone});

  final VoidCallback onDone;

  Future<void> _accept(BuildContext context) async {
    final controller = context.read<SettingsController>();
    // Reminders are on by default, so the OS prompt is the only thing missing.
    if (!controller.dailyReminderEnabled) {
      await controller.setDailyReminderEnabled(true);
    } else if (controller.notificationPermission !=
        NotificationPermission.granted) {
      await controller.requestPermission();
    }
    onDone();
  }

  Future<void> _decline(BuildContext context) async {
    await context.read<SettingsController>().setDailyReminderEnabled(false);
    onDone();
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<SettingsController>();
    final busy = controller.loading;

    return OnboardingScaffold(
      action: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          PrimaryButton(
            label: 'Remind Me',
            onPressed: busy ? null : () => _accept(context),
          ),
          const SizedBox(height: 10),
          SecondaryButton(
            label: 'Maybe Later',
            onPressed: busy ? null : () => _decline(context),
          ),
        ],
      ),
      content: (context, height) {
        return Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const OnboardingHeadline(
              label: 'Daily reminder',
              title: 'Want a reminder tomorrow?',
              subtitle:
                  "We'll remind you when it's time\n"
                  'for your 5-minute kanji session.',
            ),
            SizedBox(height: (height * 0.06).clamp(24.0, 36.0)),
            _TimeChip(controller: controller),
          ],
        );
      },
    );
  }
}

/// Shows the time the reminder would actually arrive, so the ask is concrete.
class _TimeChip extends StatelessWidget {
  const _TimeChip({required this.controller});

  final SettingsController controller;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final time = MaterialLocalizations.of(context).formatTimeOfDay(
      TimeOfDay(
        hour: controller.reminderTime.hour,
        minute: controller.reminderTime.minute,
      ),
    );

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
      decoration: BoxDecoration(
        color: theme.cardWash,
        borderRadius: BorderRadius.circular(AppTheme.buttonRadius),
        border: Border.all(color: theme.hairline),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.notifications_none_rounded,
            size: 19,
            color: theme.mutedText,
          ),
          const SizedBox(width: 9),
          Text(
            time,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w600,
              letterSpacing: 0.2,
            ),
          ),
        ],
      ),
    );
  }
}
