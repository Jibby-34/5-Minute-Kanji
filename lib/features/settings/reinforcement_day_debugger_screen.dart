import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../../repositories/kanji_repository.dart';
import '../../repositories/progress_repository.dart';
import '../../services/reinforcement_day.dart';
import '../../services/reinforcement_day_scenarios.dart';
import '../../widgets/section_label.dart';
import '../../widgets/soft_card.dart';
import '../home/home_controller.dart';
import '../home/study_plan_card.dart';
import 'reinforcement_day_debugger_controller.dart';

/// Controls for Reinforcement Day thresholds and previews.
///
/// Settings shows this in debug runs and in TestFlight installs. An App
/// Store install leaves it out. Thresholds stay in memory, and the screen
/// reads the due queue without writing it.
class ReinforcementDayDebuggerScreen extends StatelessWidget {
  const ReinforcementDayDebuggerScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (context) => ReinforcementDayDebuggerController(
        kanjiRepository: context.read<KanjiRepository>(),
        progressRepository: context.read<ProgressRepository>(),
      )..reevaluate(),
      child: const _DebuggerView(),
    );
  }
}

class _DebuggerView extends StatefulWidget {
  const _DebuggerView();

  @override
  State<_DebuggerView> createState() => _DebuggerViewState();
}

class _DebuggerViewState extends State<_DebuggerView> {
  late final TextEditingController _minimum;
  late final TextEditingController _average;
  late final TextEditingController _low;
  late final TextEditingController _fraction;
  String? _minimumError;
  String? _averageError;
  String? _lowError;
  String? _fractionError;
  var _filled = false;

  @override
  void initState() {
    super.initState();
    _minimum = TextEditingController();
    _average = TextEditingController();
    _low = TextEditingController();
    _fraction = TextEditingController();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_filled) return;
    _filled = true;
    _fill(context.read<ReinforcementDayDebuggerController>());
  }

  @override
  void dispose() {
    _minimum.dispose();
    _average.dispose();
    _low.dispose();
    _fraction.dispose();
    super.dispose();
  }

  void _fill(ReinforcementDayDebuggerController controller) {
    final config = controller.diagnostic;
    _minimum.text = '${config.minimumDueCards}';
    _average.text = formatThreshold(config.averageRecallThreshold);
    _low.text = formatThreshold(config.lowRecallThreshold);
    _fraction.text = formatThreshold(config.lowRecallFractionThreshold);
  }

  void _reset() {
    final controller = context.read<ReinforcementDayDebuggerController>();
    controller.resetThresholds();
    _fill(controller);
    setState(() {
      _minimumError = null;
      _averageError = null;
      _lowError = null;
      _fractionError = null;
    });
  }

  Future<void> _confirmRebuild() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text("Rebuild today's saved plan?"),
          content: const Text(
            'This clears today\'s saved queue and builds it again with the '
            'production thresholds. Diagnostic values on this screen stay as '
            'they are. Learned schedules stay as they are.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Rebuild'),
            ),
          ],
        );
      },
    );
    if (confirmed != true || !mounted) return;
    final controller = context.read<ReinforcementDayDebuggerController>();
    await controller.rebuildSavedPlan();
    if (!mounted) return;
    await context.read<HomeController>().load(showLoading: false);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final controller = context.watch<ReinforcementDayDebuggerController>();
    final home = context.watch<HomeController>();
    final diagnosis = controller.diagnosis;
    final config = controller.diagnostic;
    final quiet = theme.textTheme.bodyMedium?.copyWith(
      color: theme.mutedText,
      height: 1.35,
    );
    final preview = allocationForPreview(
      sitting: home.studyAllocation,
      dayType: controller.previewDayType,
    );

    return Scaffold(
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const _Header(),
            Expanded(
              child: ListView(
                physics: const BouncingScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(24, 8, 24, 40),
                children: [
                  Text(
                    'Diagnostic values stay on this screen. Today\'s saved plan keeps its current day type until you rebuild it below.',
                    style: quiet,
                  ),
                  const SizedBox(height: 28),
                  const SectionLabel('Saved plan'),
                  const SizedBox(height: 12),
                  SoftCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Saved plan: ${controller.savedPlan.dayType.label}',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          '${_cardsInQueue(controller.savedPlan.cardIds.length)} in the saved queue.',
                          style: quiet,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 28),
                  const SectionLabel('Queue'),
                  const SizedBox(height: 12),
                  DropdownButton<ReinforcementDiagnosticSource>(
                    key: const Key('debug-source'),
                    value: controller.source,
                    isExpanded: true,
                    items: [
                      for (final source in ReinforcementDiagnosticSource.values)
                        DropdownMenuItem(
                          value: source,
                          child: Text(source.label),
                        ),
                    ],
                    onChanged: (value) {
                      if (value == null) return;
                      controller.selectSource(value);
                    },
                  ),
                  const SizedBox(height: 8),
                  Text(controller.source.detail, style: quiet),
                  const SizedBox(height: 8),
                  Text(
                    controller.simulation
                        ? 'Simulation. These probabilities are sample data.'
                        : 'Live queue. This reads cards due today and leaves them unchanged.',
                    style: quiet,
                  ),
                  const SizedBox(height: 28),
                  const SectionLabel('Thresholds'),
                  const SizedBox(height: 8),
                  Text(
                    'Editing a value recalculates the prediction immediately.',
                    style: quiet,
                  ),
                  if (!controller.usingProductionThresholds) ...[
                    const SizedBox(height: 8),
                    Text(
                      'These values differ from the production defaults.',
                      style: quiet,
                    ),
                  ],
                  const SizedBox(height: 12),
                  _NumberField(
                    fieldKey: const Key('debug-minimum'),
                    controller: _minimum,
                    label: 'Minimum due cards',
                    error: _minimumError,
                    decimal: false,
                    onChanged: (text) {
                      final ok = controller.applyMinimum(text);
                      setState(() {
                        _minimumError = ok
                            ? null
                            : 'Enter a whole number from 0 to 999.';
                      });
                    },
                  ),
                  _NumberField(
                    fieldKey: const Key('debug-average'),
                    controller: _average,
                    label: 'Average recall threshold',
                    error: _averageError,
                    onChanged: (text) {
                      final ok = controller.applyAverage(text);
                      setState(() {
                        _averageError = ok
                            ? null
                            : 'Enter a value from 0 to 1.';
                      });
                    },
                  ),
                  _NumberField(
                    fieldKey: const Key('debug-low'),
                    controller: _low,
                    label: 'Low recall threshold',
                    error: _lowError,
                    onChanged: (text) {
                      final ok = controller.applyLow(text);
                      setState(() {
                        _lowError = ok ? null : 'Enter a value from 0 to 1.';
                      });
                    },
                  ),
                  _NumberField(
                    fieldKey: const Key('debug-fraction'),
                    controller: _fraction,
                    label: 'Low-recall fraction',
                    error: _fractionError,
                    onChanged: (text) {
                      final ok = controller.applyFraction(text);
                      setState(() {
                        _fractionError = ok
                            ? null
                            : 'Enter a value from 0 to 1.';
                      });
                    },
                  ),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton(
                      key: const Key('debug-reset'),
                      onPressed: _reset,
                      child: const Text('Reset to production defaults'),
                    ),
                  ),
                  const SizedBox(height: 16),
                  const SectionLabel('Diagnostic prediction'),
                  const SizedBox(height: 12),
                  SoftCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _Metric(
                          'Eligible due cards: ${diagnosis.eligibleCount}',
                        ),
                        if (diagnosis.excludedCount > 0)
                          _Metric(
                            'Estimates left out: ${diagnosis.excludedCount}',
                          ),
                        _Metric('Average recall: ${diagnosis.averageLabel}'),
                        _Metric(
                          'Below the low threshold: ${diagnosis.lowShareLabel}',
                        ),
                        _Metric(
                          'Minimum queue: ${diagnosis.minimumLabel(config.minimumDueCards)}',
                        ),
                        _Metric('Predicted: ${diagnosis.dayType.label}'),
                        const SizedBox(height: 8),
                        Text(diagnosis.triggerLabel(config), style: quiet),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton(
                    key: const Key('debug-reevaluate'),
                    onPressed: controller.loading
                        ? null
                        : () => controller.reevaluate(),
                    child: const Text('Reevaluate diagnostic prediction'),
                  ),
                  const SizedBox(height: 28),
                  const SectionLabel('UI preview'),
                  const SizedBox(height: 8),
                  Text(
                    'Automatic follows the diagnostic prediction. Card counts come from today\'s sitting on Home. A Reinforcement preview shows 0 new kanji.',
                    style: quiet,
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final mode in DayTypePreview.values)
                        ChoiceChip(
                          label: Text(mode.label),
                          selected: controller.preview == mode,
                          onSelected: (_) => controller.selectPreview(mode),
                        ),
                    ],
                  ),
                  if (controller.preview != DayTypePreview.automatic)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton(
                        onPressed: controller.returnToAutomatic,
                        child: const Text('Return to automatic'),
                      ),
                    ),
                  const SizedBox(height: 12),
                  StudyPlanCard(
                    allocation: preview,
                    dayType: controller.previewDayType,
                    trial: home.trialProgressLabel,
                  ),
                  const SizedBox(height: 28),
                  const SectionLabel('Saved plan rebuild'),
                  const SizedBox(height: 8),
                  Text(
                    'Debug only. Builds today\'s queue again with the production thresholds. It does not apply the values above, and it leaves learned schedules alone.',
                    style: quiet,
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton(
                    key: const Key('debug-rebuild'),
                    onPressed: controller.rebuilding ? null : _confirmRebuild,
                    child: const Text("Rebuild today's saved plan"),
                  ),
                  if (controller.rebuildNote != null) ...[
                    const SizedBox(height: 8),
                    Text(controller.rebuildNote!, style: quiet),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

String _cardsInQueue(int count) {
  return count == 1 ? '1 card' : '$count cards';
}

class _Header extends StatelessWidget {
  const _Header();

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
            child: Text(
              'Reinforcement Day Debugger',
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _NumberField extends StatelessWidget {
  const _NumberField({
    required this.fieldKey,
    required this.controller,
    required this.label,
    required this.onChanged,
    this.error,
    this.decimal = true,
  });

  final Key fieldKey;
  final TextEditingController controller;
  final String label;
  final String? error;
  final bool decimal;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: TextField(
        key: fieldKey,
        controller: controller,
        keyboardType: TextInputType.numberWithOptions(decimal: decimal),
        decoration: InputDecoration(labelText: label, errorText: error),
        onChanged: onChanged,
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(text),
    );
  }
}
