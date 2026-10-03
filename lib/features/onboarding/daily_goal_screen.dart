import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/models/daily_goal.dart';
import '../../core/theme/app_theme.dart';
import '../../services/onboarding_service.dart';
import '../../widgets/primary_button.dart';
import 'widgets/onboarding_scaffold.dart';

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

    return OnboardingScaffold(
      step: 3,
      action: PrimaryButton(
        label: 'Begin',
        onPressed: _saving ? null : _submit,
      ),
      content: (context, height) {
        return Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const OnboardingHeadline(
              label: 'Daily goal',
              title: 'How much time fits into your day?',
            ),
            SizedBox(height: (height * 0.06).clamp(24.0, 40.0)),
            for (final goal in DailyGoal.presets) ...[
              _GoalOption(
                label: goal.label,
                note: goal == DailyGoal.recommended ? 'Recommended' : null,
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
            if (_custom)
              SliderTheme(
                data: SliderTheme.of(
                  context,
                ).copyWith(trackHeight: 3, inactiveTrackColor: theme.hairline),
                child: Slider(
                  min: DailyGoal.minCustomMinutes.toDouble(),
                  max: DailyGoal.maxCustomMinutes.toDouble(),
                  divisions:
                      DailyGoal.maxCustomMinutes - DailyGoal.minCustomMinutes,
                  value: _customMinutes.toDouble(),
                  label: '$_customMinutes minutes',
                  onChanged: (value) => _setCustomMinutes(value.round()),
                ),
              ),
            SizedBox(height: _custom ? 12 : 24),
            Text(
              'About ${newPerDay == 1 ? '1 new kanji' : '$newPerDay new kanji'} '
              'a day.\nYou can change this in Settings.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.mutedText,
                height: 1.4,
              ),
            ),
          ],
        );
      },
    );
  }
}

/// A single tappable choice: a warm fill and a tick when picked, nothing
/// louder.
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
          borderRadius: BorderRadius.circular(AppTheme.buttonRadius),
          child: Container(
            constraints: const BoxConstraints(minHeight: 64),
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            decoration: BoxDecoration(
              color: selected ? theme.accentWash.withValues(alpha: 0.55) : null,
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
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontSize: 20,
                      fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                      letterSpacing: -0.2,
                    ),
                  ),
                ),
                if (note case final note?)
                  Text(
                    note,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: selected ? primary : theme.mutedText,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                SizedBox(width: selected ? 12 : 0),
                if (selected) _Tick(color: primary),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Tick extends StatelessWidget {
  const _Tick({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 24,
      height: 24,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      child: Icon(
        Icons.check,
        size: 15,
        color: Theme.of(context).colorScheme.onPrimary,
      ),
    );
  }
}
