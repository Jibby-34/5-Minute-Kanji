import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/models/notification_settings.dart';
import '../../core/models/start_of_day.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/time_format.dart';
import '../../repositories/progress_repository.dart';
import '../../services/reminder_scheduler.dart';
import 'open_source_licenses_screen.dart';
import 'settings_controller.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (context) => SettingsController(
        progressRepository: context.read<ProgressRepository>(),
        reminderScheduler: context.read<ReminderScheduler?>(),
      )..load(),
      child: const _SettingsView(),
    );
  }
}

class _SettingsView extends StatefulWidget {
  const _SettingsView();

  @override
  State<_SettingsView> createState() => _SettingsViewState();
}

class _SettingsViewState extends State<_SettingsView>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // The user may have just changed notification permission in system
    // settings.
    if (state == AppLifecycleState.resumed && mounted) {
      context.read<SettingsController>().refreshPermission();
    }
  }

  Future<void> _pickStartOfDay(
    BuildContext context,
    SettingsController controller,
  ) async {
    final current = controller.startOfDay;
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: current.hour, minute: current.minute),
    );
    if (picked == null || !context.mounted) return;
    await controller.setStartOfDay(
      StartOfDay(hour: picked.hour, minute: picked.minute),
    );
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<SettingsController>();
    final theme = Theme.of(context);
    final sectionTitle = theme.textTheme.titleMedium?.copyWith(
      fontWeight: FontWeight.w600,
    );
    final valueStyle = theme.textTheme.displaySmall?.copyWith(
      fontWeight: FontWeight.w600,
      height: 1.05,
      letterSpacing: -0.8,
    );

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 4, 16, 0),
              child: Row(
                children: [
                  IconButton(
                    tooltip: 'Back',
                    onPressed: () => Navigator.of(context).maybePop(),
                    icon: const Icon(Icons.arrow_back),
                  ),
                  Expanded(
                    child: Text(
                      'Settings',
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: controller.loading
                  ? const Center(
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : ListView(
                      physics: const BouncingScrollPhysics(),
                      padding: const EdgeInsets.fromLTRB(24, 28, 24, 40),
                      children: [
                        Text('New kanji per day', style: sectionTitle),
                        const SizedBox(height: 16),
                        Text(
                          '${controller.newKanjiPerDay}',
                          textAlign: TextAlign.center,
                          style: valueStyle,
                        ),
                        const SizedBox(height: 8),
                        Slider(
                          min: 0,
                          max: 50,
                          divisions: 50,
                          value: controller.newKanjiPerDay.toDouble(),
                          label: '${controller.newKanjiPerDay}',
                          onChanged: (value) {
                            controller.setNewKanjiPerDay(value.round());
                          },
                        ),
                        const SizedBox(height: 4),
                        Text(
                          controller.estimate.label,
                          style: theme.textTheme.bodyLarge?.copyWith(
                            color: theme.mutedText,
                          ),
                        ),
                        const SizedBox(height: 40),
                        Text('Start of day', style: sectionTitle),
                        const SizedBox(height: 16),
                        Material(
                          color: Colors.transparent,
                          child: InkWell(
                            onTap: () => _pickStartOfDay(context, controller),
                            borderRadius: BorderRadius.circular(12),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              child: Text(
                                formatStartOfDay(controller.startOfDay),
                                textAlign: TextAlign.center,
                                style: valueStyle,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 40),
                        Text('Study reminders', style: sectionTitle),
                        const SizedBox(height: 4),
                        _ReminderRows(controller: controller),
                        const SizedBox(height: 48),
                        Material(
                          color: Colors.transparent,
                          child: InkWell(
                            onTap: () {
                              Navigator.of(context).push(
                                MaterialPageRoute<void>(
                                  builder: (_) =>
                                      const OpenSourceLicensesScreen(),
                                ),
                              );
                            },
                            borderRadius: BorderRadius.circular(12),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      'Open source licenses',
                                      style: sectionTitle,
                                    ),
                                  ),
                                  Icon(
                                    Icons.chevron_right,
                                    color: theme.mutedText,
                                  ),
                                ],
                              ),
                            ),
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

/// Compact reminder controls. Deliberately quieter than the sections above it.
class _ReminderRows extends StatelessWidget {
  const _ReminderRows({required this.controller});

  final SettingsController controller;

  Future<void> _pickReminderTime(BuildContext context) async {
    final current = controller.reminderTime;
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: current.hour, minute: current.minute),
    );
    if (picked == null || !context.mounted) return;
    await controller.setReminderTime(
      ReminderTime(hour: picked.hour, minute: picked.minute),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final enabled = controller.dailyReminderEnabled;
    final labelStyle = theme.textTheme.bodyLarge;
    final valueStyle = theme.textTheme.bodyLarge?.copyWith(
      color: enabled ? null : theme.mutedText,
      fontWeight: FontWeight.w600,
    );
    final time = MaterialLocalizations.of(context).formatTimeOfDay(
      TimeOfDay(
        hour: controller.reminderTime.hour,
        minute: controller.reminderTime.minute,
      ),
      alwaysUse24HourFormat: MediaQuery.alwaysUse24HourFormatOf(context),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            children: [
              Expanded(child: Text('Daily reminder', style: labelStyle)),
              Switch.adaptive(
                value: enabled,
                onChanged: controller.setDailyReminderEnabled,
              ),
            ],
          ),
        ),
        Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: enabled ? () => _pickReminderTime(context) : null,
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Reminder time',
                      style: labelStyle?.copyWith(
                        color: enabled ? null : theme.mutedText,
                      ),
                    ),
                  ),
                  Text(time, style: valueStyle),
                ],
              ),
            ),
          ),
        ),
        if (controller.remindersBlockedBySystem)
          _SystemNotificationsNotice(controller: controller),
      ],
    );
  }
}

/// Shown only when reminders are on and the OS will not deliver them.
class _SystemNotificationsNotice extends StatelessWidget {
  const _SystemNotificationsNotice({required this.controller});

  final SettingsController controller;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final canRequest = controller.canRequestPermission;

    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            canRequest
                ? 'Allow notifications to receive your daily reminder.'
                : 'Notifications are disabled in system settings.',
            style: theme.textTheme.bodyMedium?.copyWith(color: theme.mutedText),
          ),
          const SizedBox(height: 4),
          TextButton(
            style: TextButton.styleFrom(
              padding: EdgeInsets.zero,
              minimumSize: const Size(0, 36),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              alignment: Alignment.centerLeft,
            ),
            onPressed: canRequest
                ? controller.requestPermission
                : controller.openSystemNotificationSettings,
            child: Text(canRequest ? 'Allow' : 'Open Settings'),
          ),
        ],
      ),
    );
  }
}
