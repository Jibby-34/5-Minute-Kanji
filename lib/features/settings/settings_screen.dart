import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/models/start_of_day.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/time_format.dart';
import '../../repositories/progress_repository.dart';
import 'open_source_licenses_screen.dart';
import 'settings_controller.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (context) => SettingsController(
        progressRepository: context.read<ProgressRepository>(),
      )..load(),
      child: const _SettingsView(),
    );
  }
}

class _SettingsView extends StatelessWidget {
  const _SettingsView();

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
