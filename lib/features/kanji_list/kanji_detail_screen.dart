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
import '../stroke_order/kanji_stroke_animation.dart';

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
    final showSecondaryMeaning =
        card.meaning.trim().isNotEmpty &&
        card.meaning.toLowerCase() != card.keyword.toLowerCase();
    final primaryMeaning = _displayMeaning(
      card.keyword.trim().isNotEmpty ? card.keyword : card.meaning,
    );
    final jlptLabel = _jlptShortLabel(card.jlptLevel);

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
                padding: const EdgeInsets.fromLTRB(24, 8, 24, 40),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    LayoutBuilder(
                      builder: (context, constraints) {
                        return KanjiStrokeAnimation(
                          character: card.character,
                          autoPlay: false,
                          startCompleted: true,
                          size: _kanjiSide(constraints),
                          showFrame: false,
                          showStrokeNumbers: true,
                          showStrokeCount: true,
                          showFallbackCharacter: true,
                          replayColor: theme.colorScheme.primary,
                        );
                      },
                    ),
                    if (primaryMeaning.isNotEmpty) ...[
                      const SizedBox(height: 28),
                      _sectionLabel(theme, 'Meaning'),
                      const SizedBox(height: 6),
                      Text(
                        primaryMeaning,
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontSize: 22,
                          fontWeight: FontWeight.w500,
                          letterSpacing: -0.2,
                          height: 1.25,
                        ),
                      ),
                      if (showSecondaryMeaning) ...[
                        const SizedBox(height: 4),
                        Text(
                          card.meaning.trim(),
                          style: theme.textTheme.bodyLarge?.copyWith(
                            color: theme.mutedText,
                            height: 1.35,
                          ),
                        ),
                      ],
                    ],
                    if (card.hasReadings) ...[
                      const SizedBox(height: 22),
                      _sectionLabel(theme, 'Readings'),
                      const SizedBox(height: 6),
                      if (card.onyomi.isNotEmpty)
                        _readingRow(theme, 'On', card.onyomiLabel),
                      if (card.kunyomi.isNotEmpty)
                        _readingRow(theme, 'Kun', card.kunyomiLabel),
                    ],
                    const SizedBox(height: 22),
                    _sectionLabel(theme, 'Status'),
                    const SizedBox(height: 6),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.baseline,
                      textBaseline: TextBaseline.alphabetic,
                      children: [
                        Expanded(
                          child: Text(
                            _status.label,
                            style: theme.textTheme.bodyLarge?.copyWith(
                              color: _statusColor(theme),
                              fontWeight:
                                  _status == KanjiProgressStatus.notEncountered
                                  ? FontWeight.w400
                                  : FontWeight.w600,
                              height: 1.3,
                            ),
                          ),
                        ),
                        if (jlptLabel != null)
                          Text(
                            jlptLabel,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: theme.mutedText,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 0.4,
                              height: 1.3,
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    _sectionLabel(theme, 'Memory tip'),
                    const SizedBox(height: 6),
                    Text(
                      card.mnemonic,
                      style: theme.textTheme.bodyLarge?.copyWith(
                        color: theme.mutedText,
                        height: 1.4,
                      ),
                    ),
                    if (showComponents) ...[
                      const SizedBox(height: 20),
                      _sectionLabel(theme, 'Components'),
                      const SizedBox(height: 4),
                      Text(
                        card.componentsLabel,
                        style: AppTypography.kanji(
                          color: theme.colorScheme.onSurface,
                          size: 20,
                        ),
                      ),
                    ],
                    const SizedBox(height: 24),
                    Divider(height: 1, thickness: 1, color: theme.hairline),
                    const SizedBox(height: 16),
                    _sectionLabel(theme, 'Review stats'),
                    const SizedBox(height: 8),
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
                      isLast: true,
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

  double _kanjiSide(BoxConstraints constraints) {
    final width = constraints.maxWidth;
    if (!width.isFinite || width <= 0) return 164;
    return (width * 0.48).clamp(150.0, 176.0);
  }

  Widget _sectionLabel(ThemeData theme, String label) {
    return Text(
      label.toUpperCase(),
      style: theme.textTheme.labelLarge?.copyWith(
        color: theme.mutedText,
        letterSpacing: 1.3,
        fontWeight: FontWeight.w600,
        fontSize: 12,
        height: 1.2,
      ),
    );
  }

  Widget _readingRow(ThemeData theme, String kind, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          SizedBox(
            width: 40,
            child: Text(
              kind,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.mutedText,
                fontWeight: FontWeight.w600,
                height: 1.25,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: theme.textTheme.bodyLarge?.copyWith(height: 1.25),
            ),
          ),
        ],
      ),
    );
  }

  Widget _statRow(
    ThemeData theme,
    String label,
    String value, {
    bool isLast = false,
  }) {
    return Padding(
      padding: EdgeInsets.only(bottom: isLast ? 0 : 6),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.mutedText,
                height: 1.3,
              ),
            ),
          ),
          Text(
            value,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.82),
              height: 1.3,
            ),
          ),
        ],
      ),
    );
  }

  Color _statusColor(ThemeData theme) {
    return switch (_status) {
      KanjiProgressStatus.notEncountered => theme.mutedText,
      KanjiProgressStatus.learning => theme.colorScheme.primary,
      KanjiProgressStatus.mastered => theme.colorScheme.onSurface,
    };
  }

  String _displayMeaning(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return trimmed;
    return '${trimmed[0].toUpperCase()}${trimmed.substring(1)}';
  }

  String? _jlptShortLabel(JlptLevel level) {
    return switch (level) {
      JlptLevel.n5 => 'N5',
      JlptLevel.n4 => 'N4',
      JlptLevel.n3 => 'N3',
      JlptLevel.n2 => 'N2',
      JlptLevel.n1 => 'N1',
      JlptLevel.none => null,
    };
  }

  String _formatLastReviewed(DateTime? at) {
    if (at == null) return '—';
    return '${at.month}/${at.day}';
  }
}
