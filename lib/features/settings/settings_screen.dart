import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/models/daily_goal.dart';
import '../../core/models/notification_settings.dart';
import '../../core/models/start_of_day.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/time_format.dart';
import '../../repositories/progress_repository.dart';
import '../../services/placement_service.dart';
import '../../services/reminder_scheduler.dart';
import '../../widgets/section_label.dart';
import '../../widgets/soft_card.dart';
import '../placement/placement_screen.dart';
import 'open_source_licenses_screen.dart';
import 'settings_controller.dart';

const _sectionGap = 36.0;
const _screenPadding = 24.0;

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

  /// A retake only ever adds known kanji: kanji with progress are left out of
  /// the test, so nothing already learned is disturbed.
  Future<void> _retakePlacementTest(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Retake placement test?'),
          content: const Text(
            'This will reassess your level and update your starting kanji.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Retake test'),
            ),
          ],
        );
      },
    );
    if (confirmed != true || !context.mounted) return;

    final service = context.read<PlacementService>();
    await service.restart();
    if (!context.mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (routeContext) => PlacementScreen(
          onFinished: () => Navigator.of(routeContext).maybePop(),
        ),
      ),
    );
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

    return Scaffold(
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const _SettingsHeader(),
            Expanded(
              child: controller.loading
                  ? const Center(
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : SingleChildScrollView(
                      physics: const BouncingScrollPhysics(),
                      padding: const EdgeInsets.fromLTRB(
                        _screenPadding,
                        16,
                        _screenPadding,
                        40,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _StudySection(
                            controller: controller,
                            onPickStartOfDay: () =>
                                _pickStartOfDay(context, controller),
                          ),
                          const SizedBox(height: _sectionGap),
                          const _ReminderSection(),
                          const SizedBox(height: _sectionGap),
                          _OtherSection(
                            onRetakePlacement: () =>
                                _retakePlacementTest(context),
                            onOpenLicenses: () {
                              Navigator.of(context).push(
                                MaterialPageRoute<void>(
                                  builder: (_) =>
                                      const OpenSourceLicensesScreen(),
                                ),
                              );
                            },
                          ),
                        ],
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SettingsHeader extends StatelessWidget {
  const _SettingsHeader();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 4, 16, 0),
      child: Row(
        children: [
          IconButton(
            tooltip: 'Back',
            onPressed: () => Navigator.of(context).maybePop(),
            icon: const Icon(Icons.arrow_back),
          ),
          Expanded(
            child: Semantics(
              header: true,
              child: Text(
                'Settings',
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StudySection extends StatelessWidget {
  const _StudySection({
    required this.controller,
    required this.onPickStartOfDay,
  });

  final SettingsController controller;
  final VoidCallback onPickStartOfDay;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final title = _settingTitle(theme);
    final quiet = _quietText(theme);

    return _SettingsSection(
      label: 'Study',
      child: _GroupedCard(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Daily study time', style: title),
                const SizedBox(height: 4),
                Text(
                  'Choose how much time you want to study each day.',
                  style: quiet,
                ),
                const SizedBox(height: 14),
                _StudyTimeChoices(controller: controller),
                const SizedBox(height: 12),
                Text(
                  'Plans your normal session. Extra due kanji stay optional.',
                  style: quiet,
                ),
              ],
            ),
          ),
          const _CardDivider(),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(child: Text('New kanji per day', style: title)),
                    const SizedBox(width: 12),
                    Text(
                      '${controller.newKanjiPerDay}',
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w600,
                        height: 1.1,
                        letterSpacing: -0.4,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                _NewKanjiSlider(controller: controller),
                Text(controller.estimate.label, style: quiet),
              ],
            ),
          ),
          const _CardDivider(),
          _SettingsRow(
            label: 'Start of day',
            subtitle: 'When a new study day begins',
            value: formatStartOfDay(controller.startOfDay),
            showChevron: true,
            onTap: onPickStartOfDay,
          ),
        ],
      ),
    );
  }
}

class _StudyTimeChoices extends StatelessWidget {
  const _StudyTimeChoices({required this.controller});

  final SettingsController controller;

  @override
  Widget build(BuildContext context) {
    final choices = _studyMinuteChoices(controller.dailyStudyMinutes);

    return Column(
      children: [
        for (var i = 0; i < choices.length; i++) ...[
          if (i > 0) const SizedBox(height: 8),
          _StudyTimeOption(
            label: '${choices[i]} minutes',
            selected: controller.dailyStudyMinutes == choices[i],
            onTap: () => controller.setDailyStudyMinutes(choices[i]),
          ),
        ],
      ],
    );
  }
}

/// Presets, plus the stored value when it is not one of them (a custom goal
/// chosen during onboarding).
List<int> _studyMinuteChoices(int current) {
  final choices = [for (final goal in DailyGoal.presets) goal.minutes];
  if (!choices.contains(current)) {
    choices.add(current);
    choices.sort();
  }
  return choices;
}

class _StudyTimeOption extends StatelessWidget {
  const _StudyTimeOption({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primary = theme.colorScheme.primary;

    return Semantics(
      selected: selected,
      button: true,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppTheme.buttonRadius),
          child: Container(
            constraints: const BoxConstraints(minHeight: 46),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: selected ? theme.accentWash : null,
              borderRadius: BorderRadius.circular(AppTheme.buttonRadius),
              border: Border.all(
                color: selected ? primary : theme.hairline,
                width: selected ? 1.6 : 1.2,
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    label,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                      color: selected ? primary : null,
                    ),
                  ),
                ),
                if (selected) _SelectionMark(color: primary),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SelectionMark extends StatelessWidget {
  const _SelectionMark({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 22,
      height: 22,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      child: Icon(
        Icons.check,
        size: 14,
        color: Theme.of(context).colorScheme.onPrimary,
      ),
    );
  }
}

class _NewKanjiSlider extends StatelessWidget {
  const _NewKanjiSlider({required this.controller});

  final SettingsController controller;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primary = theme.colorScheme.primary;

    return SliderTheme(
      data: SliderTheme.of(context).copyWith(
        trackHeight: 4,
        activeTrackColor: primary,
        inactiveTrackColor: theme.hairline,
        thumbColor: primary,
        overlayColor: primary.withValues(alpha: 0.12),
        thumbShape: const RoundSliderThumbShape(
          enabledThumbRadius: 11,
          elevation: 0,
          pressedElevation: 0,
        ),
        overlayShape: const RoundSliderOverlayShape(overlayRadius: 22),
      ),
      child: Slider(
        min: 0,
        max: 50,
        divisions: 50,
        value: controller.newKanjiPerDay.toDouble(),
        label: '${controller.newKanjiPerDay}',
        semanticFormatterCallback: (value) =>
            '${value.round()} new kanji per day',
        onChanged: (value) => controller.setNewKanjiPerDay(value.round()),
      ),
    );
  }
}

class _ReminderSection extends StatelessWidget {
  const _ReminderSection();

  Future<void> _pickReminderTime(BuildContext context) async {
    final controller = context.read<SettingsController>();
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
    final controller = context.watch<SettingsController>();
    final enabled = controller.dailyReminderEnabled;
    final time = MaterialLocalizations.of(context).formatTimeOfDay(
      TimeOfDay(
        hour: controller.reminderTime.hour,
        minute: controller.reminderTime.minute,
      ),
      alwaysUse24HourFormat: MediaQuery.alwaysUse24HourFormatOf(context),
    );

    return _SettingsSection(
      label: 'Reminders',
      child: _GroupedCard(
        children: [
          _SettingsRow(
            label: 'Enable notifications',
            trailing: Switch.adaptive(
              value: enabled,
              onChanged: controller.setDailyReminderEnabled,
            ),
          ),
          const _CardDivider(),
          _SettingsRow(
            label: 'Reminder time',
            value: time,
            enabled: enabled,
            showChevron: true,
            onTap: enabled ? () => _pickReminderTime(context) : null,
          ),
          const _CardDivider(),
          // The scheduler sends one reminder every study day. There is no
          // weekday filter; the row states that cadence.
          _SettingsRow(
            label: 'Days',
            value: 'Every day',
            enabled: enabled,
            // Match the disclosure rows so this value lines up with the time.
            reserveChevronGap: true,
          ),
          if (controller.remindersBlockedBySystem) ...[
            const _CardDivider(),
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 10, 18, 12),
              child: _SystemNotificationsNotice(controller: controller),
            ),
          ],
        ],
      ),
    );
  }
}

class _OtherSection extends StatelessWidget {
  const _OtherSection({
    required this.onRetakePlacement,
    required this.onOpenLicenses,
  });

  final VoidCallback onRetakePlacement;
  final VoidCallback onOpenLicenses;

  @override
  Widget build(BuildContext context) {
    return _SettingsSection(
      label: 'Other',
      child: _GroupedCard(
        children: [
          _SettingsRow(
            label: 'Placement test',
            subtitle:
                'Retake the placement test to reset your level and get a new set of kanji.',
            showChevron: true,
            onTap: onRetakePlacement,
          ),
          const _CardDivider(),
          _SettingsRow(
            label: 'Open source licenses',
            subtitle: 'View the licenses for libraries used by 5-Minute Kanji.',
            showChevron: true,
            onTap: onOpenLicenses,
          ),
        ],
      ),
    );
  }
}

class _SettingsSection extends StatelessWidget {
  const _SettingsSection({required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [SectionLabel(label), const SizedBox(height: 10), child],
    );
  }
}

class _GroupedCard extends StatelessWidget {
  const _GroupedCard({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return SoftCard(
      padding: EdgeInsets.zero,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppTheme.cardRadius),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: children,
        ),
      ),
    );
  }
}

class _CardDivider extends StatelessWidget {
  const _CardDivider();

  @override
  Widget build(BuildContext context) {
    return Divider(height: 1, thickness: 1, color: Theme.of(context).hairline);
  }
}

class _SettingsRow extends StatelessWidget {
  const _SettingsRow({
    required this.label,
    this.subtitle,
    this.value,
    this.trailing,
    this.onTap,
    this.enabled = true,
    this.showChevron = false,
    this.reserveChevronGap = false,
  });

  final String label;
  final String? subtitle;
  final String? value;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool enabled;
  final bool showChevron;

  /// Keeps a value aligned with rows that show a disclosure chevron.
  final bool reserveChevronGap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final canTap = enabled && onTap != null;
    final labelStyle = _settingTitle(
      theme,
    )?.copyWith(color: enabled ? null : theme.mutedText);
    final valueStyle = theme.textTheme.bodyLarge?.copyWith(
      fontWeight: FontWeight.w600,
      color: enabled ? null : theme.mutedText,
    );
    final vertical = trailing != null ? 2.0 : (subtitle == null ? 8.0 : 12.0);

    final row = ConstrainedBox(
      constraints: BoxConstraints(minHeight: subtitle == null ? 52 : 72),
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          18,
          vertical,
          showChevron ? 10 : 18,
          vertical,
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: labelStyle),
                  if (subtitle case final subtitle?) ...[
                    const SizedBox(height: 3),
                    Text(subtitle, style: _quietText(theme)),
                  ],
                ],
              ),
            ),
            if (value case final value?) ...[
              const SizedBox(width: 12),
              Text(value, style: valueStyle),
            ],
            ?trailing,
            if (showChevron) ...[
              const SizedBox(width: 2),
              ExcludeSemantics(
                child: Icon(
                  Icons.chevron_right,
                  size: 22,
                  color: enabled
                      ? theme.mutedText
                      : theme.mutedText.withValues(alpha: 0.55),
                ),
              ),
            ] else if (reserveChevronGap)
              const SizedBox(width: 16),
          ],
        ),
      ),
    );

    if (!canTap) {
      return MergeSemantics(child: row);
    }

    return MergeSemantics(
      child: Material(
        color: Colors.transparent,
        child: InkWell(onTap: onTap, child: row),
      ),
    );
  }
}

TextStyle? _settingTitle(ThemeData theme) {
  return theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600);
}

TextStyle? _quietText(ThemeData theme) {
  return theme.textTheme.bodyMedium?.copyWith(
    color: theme.mutedText,
    height: 1.4,
  );
}

/// Shown only when reminders are on and the OS will not deliver them.
class _SystemNotificationsNotice extends StatelessWidget {
  const _SystemNotificationsNotice({required this.controller});

  final SettingsController controller;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final canRequest = controller.canRequestPermission;

    return Column(
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
    );
  }
}
