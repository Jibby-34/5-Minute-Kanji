import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/models/card_schedule.dart';
import '../../core/models/kanji_card.dart';
import '../../core/models/kanji_status.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/app_typography.dart';
import '../../services/kanji_status_resolver.dart';
import '../../services/mark_as_known.dart';
import '../../widgets/bottom_action_inset.dart';
import '../../widgets/primary_button.dart';

class KanjiDetailScreen extends StatefulWidget {
  const KanjiDetailScreen({
    super.key,
    required this.card,
    required this.status,
    this.schedule,
  });

  final KanjiCard card;
  final CardSchedule? schedule;
  final KanjiProgressStatus status;

  @override
  State<KanjiDetailScreen> createState() => _KanjiDetailScreenState();
}

class _KanjiDetailScreenState extends State<KanjiDetailScreen> {
  static const _resolver = KanjiStatusResolver();

  late KanjiProgressStatus _status;
  late CardSchedule? _schedule;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _status = widget.status;
    _schedule = widget.schedule;
  }

  bool get _canMarkAsKnown =>
      !_busy && _status == KanjiProgressStatus.notEncountered;

  Future<void> _markAsKnown() async {
    if (!_canMarkAsKnown) return;
    setState(() => _busy = true);
    try {
      final updated = await context.read<MarkAsKnownService>().markKanjiAsKnown(
        widget.card.id,
      );
      if (!mounted || updated == null) return;
      setState(() {
        _schedule = updated;
        _status = _resolver.resolve(updated);
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final card = widget.card;
    final showComponents =
        card.components.length > 1 ||
        (card.components.length == 1 &&
            card.components.first != card.character);
    final showMeaning =
        card.meaning.trim().isNotEmpty &&
        card.meaning.toLowerCase() != card.keyword.toLowerCase();

    return Scaffold(
      body: SafeArea(
        bottom: _status != KanjiProgressStatus.notEncountered,
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
                      'Kanji Detail',
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(24, 16, 24, 40),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Center(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          card.character,
                          style: AppTypography.kanji(
                            color: theme.colorScheme.onSurface,
                            size: 104,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      card.keyword.toUpperCase(),
                      textAlign: TextAlign.center,
                      style: AppTypography.keyword(
                        color: theme.colorScheme.onSurface,
                      ),
                    ),
                    if (showMeaning) ...[
                      const SizedBox(height: 8),
                      Text(
                        card.meaning,
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodyLarge?.copyWith(
                          color: theme.mutedText,
                        ),
                      ),
                    ],
                    if (card.hasReadings) ...[
                      const SizedBox(height: 28),
                      _sectionLabel(theme, 'Readings'),
                      const SizedBox(height: 8),
                      if (card.onyomi.isNotEmpty)
                        Text(
                          'On: ${card.onyomiLabel}',
                          style: theme.textTheme.bodyLarge?.copyWith(
                            height: 1.45,
                          ),
                        ),
                      if (card.kunyomi.isNotEmpty)
                        Text(
                          'Kun: ${card.kunyomiLabel}',
                          style: theme.textTheme.bodyLarge?.copyWith(
                            height: 1.45,
                          ),
                        ),
                    ],
                    const SizedBox(height: 28),
                    _sectionLabel(theme, 'Status'),
                    const SizedBox(height: 8),
                    Text(
                      _status.label,
                      style: theme.textTheme.bodyLarge?.copyWith(height: 1.45),
                    ),
                    const SizedBox(height: 20),
                    _sectionLabel(theme, 'Mnemonic'),
                    const SizedBox(height: 8),
                    Text(
                      card.mnemonic,
                      style: theme.textTheme.bodyLarge?.copyWith(height: 1.45),
                    ),
                    if (showComponents) ...[
                      const SizedBox(height: 20),
                      _sectionLabel(theme, 'Components'),
                      const SizedBox(height: 8),
                      Text(
                        card.componentsLabel,
                        style: AppTypography.kanji(
                          color: theme.colorScheme.onSurface,
                          size: 22,
                        ),
                      ),
                    ],
                    const SizedBox(height: 28),
                    _sectionLabel(theme, 'Review stats'),
                    const SizedBox(height: 12),
                    _statRow(
                      theme,
                      'Reviews',
                      '${_schedule?.reviewCount ?? 0}',
                    ),
                    _statRow(
                      theme,
                      'Correct',
                      '${_schedule?.correctCount ?? 0}',
                    ),
                    _statRow(
                      theme,
                      'Incorrect',
                      '${_schedule?.incorrectCount ?? 0}',
                    ),
                    _statRow(
                      theme,
                      'Last reviewed',
                      _formatLastReviewed(_schedule?.lastReviewedAt),
                    ),
                  ],
                ),
              ),
            ),
            if (_status == KanjiProgressStatus.notEncountered)
              BottomActionInset(
                child: PrimaryButton(
                  label: 'Mark as Known',
                  onPressed: _canMarkAsKnown ? _markAsKnown : null,
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _sectionLabel(ThemeData theme, String label) {
    return Text(
      label,
      style: theme.textTheme.labelLarge?.copyWith(
        color: theme.mutedText,
        letterSpacing: 0.8,
        fontWeight: FontWeight.w600,
      ),
    );
  }

  Widget _statRow(ThemeData theme, String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: theme.textTheme.bodyLarge?.copyWith(
                color: theme.mutedText,
              ),
            ),
          ),
          Text(value, style: theme.textTheme.bodyLarge),
        ],
      ),
    );
  }

  String _formatLastReviewed(DateTime? at) {
    if (at == null) return '—';
    return '${at.month}/${at.day}';
  }
}
