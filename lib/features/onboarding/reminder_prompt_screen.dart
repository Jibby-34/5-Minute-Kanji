import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../../repositories/progress_repository.dart';
import '../../services/notification_gateway.dart';
import '../../services/reminder_scheduler.dart';
import '../../widgets/bottom_action_inset.dart';
import '../../widgets/centered_copy.dart';
import '../../widgets/primary_button.dart';
import '../settings/settings_controller.dart';

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
    final theme = Theme.of(context);
    final controller = context.watch<SettingsController>();
    final busy = controller.loading;

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            Expanded(
              child: CenteredCopy(
                children: [
                  Text(
                    'Want a reminder tomorrow?',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                      letterSpacing: -0.4,
                      height: 1.2,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    "We'll remind you when it's time for your 5-minute "
                    'kanji session.',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: theme.mutedText,
                      fontWeight: FontWeight.w400,
                      height: 1.45,
                    ),
                  ),
                ],
              ),
            ),
            BottomActionInset(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  PrimaryButton(
                    label: 'Remind Me',
                    onPressed: busy ? null : () => _accept(context),
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: OutlinedButton(
                      onPressed: busy ? null : () => _decline(context),
                      child: const Text('Maybe Later'),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
