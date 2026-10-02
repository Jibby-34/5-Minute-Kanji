import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/models/daily_goal.dart';
import '../../core/theme/app_theme.dart';
import '../../services/onboarding_service.dart';
import '../../widgets/bottom_action_inset.dart';
import '../../widgets/primary_button.dart';

/// Asks for a time budget, not a kanji count: the number of new kanji a day is
/// derived from it and lands in the same setting the user can change later.
class DailyGoalScreen extends StatefulWidget {
  const DailyGoalScreen({super.key, required this.onSelected});

  /// Called with the chosen goal. Saving happens in the caller so the flow can
  /// advance only once the goal is stored.
  final Future<void> Function(DailyGoal goal) onSelected;

  @override
  State<DailyGoalScreen> createState() => _DailyGoalScreenState();
}

class _DailyGoalScreenState extends State<DailyGoalScreen> {
  int _minutes = DailyGoal.recommended.minutes;
  int _customMinutes = 20;
  bool _custom = false;
  bool _saving = false;

  void _selectPreset(DailyGoal goal) {
    setState(() {
      _custom = false;
      _minutes = goal.minutes;
    });
  }

  void _selectCustom() {
    setState(() {
      _custom = true;
      _minutes = _customMinutes;
    });
  }

  void _setCustomMinutes(int value) {
    setState(() {
      _customMinutes = value;
      _minutes = value;
    });
  }

  Future<void> _submit() async {
    if (_saving) return;
    setState(() => _saving = true);
    await widget.onSelected(DailyGoal(_minutes));
    if (mounted) setState(() => _saving = false);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final newPerDay = context.read<OnboardingService>().newKanjiPerDayFor(
      DailyGoal(_minutes),
    );

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            Expanded(
              child: ListView(
                physics: const BouncingScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(28, 48, 28, 24),
                children: [
                  Text(
                    'How much time fits into your day?',
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                      letterSpacing: -0.4,
                      height: 1.2,
                    ),
                  ),
                  const SizedBox(height: 32),
                  for (final goal in DailyGoal.presets) ...[
                    _GoalOption(
                      label: goal.label,
                      note: goal == DailyGoal.recommended
                          ? 'Recommended'
                          : null,
                      selected: !_custom && _minutes == goal.minutes,
                      onTap: () => _selectPreset(goal),
                    ),
                    const SizedBox(height: 10),
                  ],
                  _GoalOption(
                    label: 'Custom',
                    note: _custom ? '$_customMinutes minutes' : null,
                    selected: _custom,
                    onTap: _selectCustom,
                  ),
                  if (_custom) ...[
                    const SizedBox(height: 8),
                    Slider(
                      min: DailyGoal.minCustomMinutes.toDouble(),
                      max: DailyGoal.maxCustomMinutes.toDouble(),
                      divisions:
                          DailyGoal.maxCustomMinutes -
                          DailyGoal.minCustomMinutes,
                      value: _customMinutes.toDouble(),
                      label: '$_customMinutes minutes',
                      onChanged: (value) => _setCustomMinutes(value.round()),
                    ),
                  ],
                  const SizedBox(height: 24),
                  Text(
                    'About ${newPerDay == 1 ? '1 new kanji' : '$newPerDay new kanji'} '
                    'a day. You can change this in Settings.',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.mutedText,
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
            BottomActionInset(
              child: PrimaryButton(
                label: 'Begin',
                onPressed: _saving ? null : _submit,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A single tappable choice. Selection is a border and a tick, nothing louder.
class _GoalOption extends StatelessWidget {
  const _GoalOption({
    required this.label,
    required this.selected,
    required this.onTap,
    this.note,
  });

  final String label;
  final String? note;
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
          borderRadius: BorderRadius.circular(14),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: selected ? primary : theme.hairline,
                width: selected ? 1.6 : 1,
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    label,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                    ),
                  ),
                ),
                if (note case final note?)
                  Text(
                    note,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.mutedText,
                    ),
                  ),
                if (selected) ...[
                  const SizedBox(width: 10),
                  Icon(Icons.check, size: 20, color: primary),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
