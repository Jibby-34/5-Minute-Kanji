import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/models/card_schedule.dart';
import '../../core/models/kanji_card.dart';
import '../../core/models/kanji_status.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/app_typography.dart';
import '../../repositories/stroke_data_repository.dart';
import '../../services/kanji_status_resolver.dart';
import '../../services/mark_as_known.dart';
import '../../widgets/bottom_action_inset.dart';
import '../../widgets/mnemonic_text.dart';
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
  static const _pagePadding = 20.0;
  static const _cardGap = 10.0;

  final _strokeOrder = GlobalKey<KanjiStrokeAnimationState>();

  late KanjiProgressStatus _status;
  late CardSchedule? _schedule;
  bool _busy = false;
  int? _strokeCount;
  var _strokeLookupStarted = false;

  @override
  void initState() {
    super.initState();
    _status = widget.status;
    _schedule = widget.schedule;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_strokeLookupStarted) return;
    _strokeLookupStarted = true;
    _loadStrokeCount();
  }

  @override
  void didUpdateWidget(KanjiDetailScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.card.character != widget.card.character) {
      _strokeCount = null;
      _loadStrokeCount();
    }
  }

  bool get _canMarkAsKnown =>
      !_busy && _status == KanjiProgressStatus.notEncountered;

  Future<void> _loadStrokeCount() async {
    final character = widget.card.character;
    StrokeDataRepository? repo;
    try {
      repo = Provider.of<StrokeDataRepository>(context, listen: false);
    } on ProviderNotFoundException {
      repo = null;
    }
    if (repo == null) return;
    final data = await repo.getForCharacter(character);
    if (!mounted || widget.card.character != character) return;
    final count = data == null || data.strokes.isEmpty
        ? null
        : data.strokeCount;
    setState(() => _strokeCount = count);
  }

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
    final palette = _DetailPalette.of(theme);
    final showComponents = card.hasComponentBreakdown;
    final showSecondaryMeaning =
        card.meaning.trim().isNotEmpty &&
        card.meaning.toLowerCase() != card.keyword.toLowerCase();
    final primaryMeaning = _displayMeaning(
      card.keyword.trim().isNotEmpty ? card.keyword : card.meaning,
    );
    final jlptLabel = _jlptShortLabel(card.jlptLevel);
    final cards = <Widget>[
      if (primaryMeaning.isNotEmpty)
        _infoCard(
          theme: theme,
          tone: palette.meaning,
          label: 'Meaning',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                primaryMeaning,
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontSize: 26,
                  fontWeight: FontWeight.w600,
                  letterSpacing: -0.4,
                  height: 1.15,
                ),
              ),
              if (showSecondaryMeaning) ...[
                const SizedBox(height: 4),
                Text(
                  card.meaning.trim(),
                  style: theme.textTheme.bodyLarge?.copyWith(
                    color: theme.mutedText,
                    height: 1.3,
                  ),
                ),
              ],
            ],
          ),
        ),
      if (card.hasReadings)
        _infoCard(
          theme: theme,
          tone: palette.readings,
          label: 'Readings',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (card.onyomi.isNotEmpty)
                _readingRow(theme, palette, 'On', card.onyomiLabel),
              if (card.onyomi.isNotEmpty && card.kunyomi.isNotEmpty)
                const SizedBox(height: 8),
              if (card.kunyomi.isNotEmpty)
                _readingRow(theme, palette, 'Kun', card.kunyomiLabel),
            ],
          ),
        ),
      _infoCard(
        theme: theme,
        tone: palette.status,
        label: 'Status',
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: Text(
                _status.label,
                style: theme.textTheme.titleLarge?.copyWith(
                  color: _statusColor(theme),
                  fontWeight: _status == KanjiProgressStatus.notEncountered
                      ? FontWeight.w500
                      : FontWeight.w600,
                  fontSize: 22,
                  height: 1.2,
                  letterSpacing: -0.3,
                ),
              ),
            ),
            if (jlptLabel != null) ...[
              const SizedBox(width: 8),
              _levelChip(theme, jlptLabel),
            ],
          ],
        ),
      ),
      if (showComponents)
        _infoCard(
          theme: theme,
          tone: palette.components,
          label: 'Components',
          child: _componentsText(theme, card),
        ),
    ];

    return Scaffold(
      body: SafeArea(
        bottom: _status != KanjiProgressStatus.notEncountered,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 2, 12, 0),
              child: Row(
                children: [
                  IconButton(
                    tooltip: 'Back',
                    onPressed: () => Navigator.of(context).maybePop(),
                    icon: const Icon(Icons.arrow_back),
                  ),
                  Text(
                    'Kanji Detail',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w500,
                      fontSize: 17,
                      letterSpacing: -0.2,
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(
                  _pagePadding,
                  4,
                  _pagePadding,
                  28,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _hero(theme, palette, card),
                    const SizedBox(height: 22),
                    _cardGrid(cards),
                    const SizedBox(height: _cardGap),
                    _infoCard(
                      theme: theme,
                      tone: palette.memory,
                      label: 'Memory tip',
                      child: MnemonicText(
                        mnemonic: card.mnemonic,
                        components: card.componentModels,
                        style: theme.textTheme.bodyLarge!.copyWith(
                          color: theme.colorScheme.onSurface.withValues(
                            alpha: 0.72,
                          ),
                          fontSize: 16,
                          height: 1.45,
                        ),
                      ),
                    ),
                    const SizedBox(height: _cardGap),
                    _infoCard(
                      theme: theme,
                      tone: palette.stats,
                      label: 'Review stats',
                      child: Column(
                        children: [
                          _statRow(
                            theme,
                            'Reviews',
                            '${_schedule?.reviewCount ?? 0}',
                          ),
                          _statDivider(theme),
                          _statRow(
                            theme,
                            'Correct',
                            '${_schedule?.correctCount ?? 0}',
                          ),
                          _statDivider(theme),
                          _statRow(
                            theme,
                            'Incorrect',
                            '${_schedule?.incorrectCount ?? 0}',
                          ),
                          _statDivider(theme),
                          _statRow(
                            theme,
                            'Last reviewed',
                            _formatLastReviewed(_schedule?.lastReviewedAt),
                          ),
                        ],
                      ),
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

  Widget _hero(ThemeData theme, _DetailPalette palette, KanjiCard card) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final kanjiSide = _kanjiSide(constraints.maxWidth);
        return Column(
          children: [
            SizedBox(
              height: kanjiSide,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Container(
                    width: kanjiSide * 0.72,
                    height: kanjiSide * 0.72,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: palette.heroWash,
                    ),
                  ),
                  KanjiStrokeAnimation(
                    key: _strokeOrder,
                    character: card.character,
                    autoPlay: false,
                    startCompleted: true,
                    size: kanjiSide,
                    showFrame: false,
                    showReplay: false,
                    showStrokeCount: false,
                    showStrokeNumbers: true,
                    showFallbackCharacter: true,
                  ),
                ],
              ),
            ),
            if (_strokeCount != null) ...[
              const SizedBox(height: 2),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: palette.pill,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  '$_strokeCount ${_strokeCount == 1 ? 'stroke' : 'strokes'}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.mutedText,
                    fontWeight: FontWeight.w500,
                    fontSize: 12.5,
                    height: 1.2,
                  ),
                ),
              ),
              const SizedBox(height: 10),
              _strokeOrderButton(theme),
            ],
          ],
        );
      },
    );
  }

  Widget _strokeOrderButton(ThemeData theme) {
    final accent = theme.colorScheme.primary;
    return Tooltip(
      message: 'Replay stroke order',
      child: TextButton.icon(
        onPressed: () => _strokeOrder.currentState?.restart(),
        icon: const Icon(Icons.replay, size: 15),
        label: const Text('Stroke Order'),
        style: TextButton.styleFrom(
          foregroundColor: accent,
          backgroundColor: accent.withValues(alpha: 0.07),
          side: BorderSide(color: accent.withValues(alpha: 0.28)),
          shape: const StadiumBorder(),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          minimumSize: const Size(48, 36),
          tapTargetSize: MaterialTapTargetSize.padded,
          visualDensity: VisualDensity.compact,
          textStyle: theme.textTheme.labelLarge?.copyWith(
            fontWeight: FontWeight.w600,
            fontSize: 14,
            letterSpacing: -0.1,
          ),
        ),
      ),
    );
  }

  Widget _cardGrid(List<Widget> cards) {
    final rows = <Widget>[];
    for (var index = 0; index < cards.length; index += 2) {
      if (rows.isNotEmpty) rows.add(const SizedBox(height: _cardGap));
      final left = cards[index];
      if (index + 1 >= cards.length) {
        rows.add(left);
        continue;
      }
      rows.add(
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: left),
              const SizedBox(width: _cardGap),
              Expanded(child: cards[index + 1]),
            ],
          ),
        ),
      );
    }
    return Column(children: rows);
  }

  Widget _infoCard({
    required ThemeData theme,
    required _CardTone tone,
    required String label,
    required Widget child,
  }) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: tone.background,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: tone.border),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 26,
                  height: 26,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: tone.iconBackground,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(tone.icon, size: 14, color: tone.iconColor),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    label.toUpperCase(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: theme.mutedText,
                      letterSpacing: 1.15,
                      fontWeight: FontWeight.w600,
                      fontSize: 11,
                      height: 1.2,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            child,
          ],
        ),
      ),
    );
  }

  Widget _readingRow(
    ThemeData theme,
    _DetailPalette palette,
    String kind,
    String value,
  ) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: palette.readingChip,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            kind,
            style: theme.textTheme.labelMedium?.copyWith(
              color: palette.readingChipText,
              fontWeight: FontWeight.w600,
              fontSize: 12,
              height: 1.2,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Text(
              value,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w500,
                fontSize: 16,
                height: 1.25,
                letterSpacing: 0.2,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _componentsText(ThemeData theme, KanjiCard card) {
    final nameStyle = theme.textTheme.titleMedium?.copyWith(
      fontWeight: FontWeight.w500,
      fontSize: 16,
      height: 1.35,
    );
    final spans = <InlineSpan>[];
    final models = card.componentModels;
    for (var index = 0; index < models.length; index++) {
      final component = models[index];
      if (index > 0) {
        spans.add(TextSpan(text: ' + ', style: nameStyle));
      }
      spans.add(
        TextSpan(
          text: component.character,
          style: AppTypography.kanji(
            color: theme.colorScheme.onSurface,
            size: 22,
          ).copyWith(height: 1.35),
        ),
      );
      spans.add(TextSpan(text: ' — ${component.name}', style: nameStyle));
    }
    return Text.rich(TextSpan(children: spans));
  }

  Widget _levelChip(ThemeData theme, String label) {
    final color = _statusColor(theme);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: theme.textTheme.labelMedium?.copyWith(
          color: color,
          fontWeight: FontWeight.w600,
          fontSize: 12,
          height: 1.1,
          letterSpacing: 0.2,
        ),
      ),
    );
  }

  Widget _statDivider(ThemeData theme) {
    return Divider(height: 1, thickness: 1, color: theme.hairline);
  }

  Widget _statRow(ThemeData theme, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 11),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.mutedText,
                fontSize: 14.5,
                height: 1.2,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Text(
            value,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.82),
              fontSize: 14.5,
              height: 1.2,
            ),
          ),
        ],
      ),
    );
  }

  double _kanjiSide(double width) {
    if (!width.isFinite || width <= 0) return 216;
    return width >= 280 ? 216 : (width * 0.72).clamp(196.0, 216.0);
  }

  Color _statusColor(ThemeData theme) {
    final dark = theme.brightness == Brightness.dark;
    return switch (_status) {
      KanjiProgressStatus.notEncountered => theme.mutedText,
      KanjiProgressStatus.learning =>
        dark ? const Color(0xFF9DC7AE) : const Color(0xFF2F6B4F),
      KanjiProgressStatus.mastered =>
        dark ? const Color(0xFFC9D9CC) : const Color(0xFF2C4A38),
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

class _CardTone {
  const _CardTone({
    required this.background,
    required this.border,
    required this.icon,
    required this.iconBackground,
    required this.iconColor,
  });

  final Color background;
  final Color border;
  final IconData icon;
  final Color iconBackground;
  final Color iconColor;
}

class _DetailPalette {
  const _DetailPalette({
    required this.heroWash,
    required this.pill,
    required this.meaning,
    required this.readings,
    required this.status,
    required this.components,
    required this.memory,
    required this.stats,
    required this.readingChip,
    required this.readingChipText,
  });

  final Color heroWash;
  final Color pill;
  final _CardTone meaning;
  final _CardTone readings;
  final _CardTone status;
  final _CardTone components;
  final _CardTone memory;
  final _CardTone stats;
  final Color readingChip;
  final Color readingChipText;

  static _DetailPalette of(ThemeData theme) {
    final dark = theme.brightness == Brightness.dark;
    if (dark) {
      return _DetailPalette(
        heroWash: Colors.white.withValues(alpha: 0.04),
        pill: Colors.white.withValues(alpha: 0.06),
        meaning: _CardTone(
          background: const Color(0xFF242833),
          border: const Color(0xFF343846),
          icon: Icons.menu_book_outlined,
          iconBackground: const Color(0xFF313848),
          iconColor: const Color(0xFF9AABC8),
        ),
        readings: _CardTone(
          background: const Color(0xFF282633),
          border: const Color(0xFF3A3646),
          icon: Icons.menu_book_outlined,
          iconBackground: const Color(0xFF363348),
          iconColor: const Color(0xFFB3A8C8),
        ),
        status: _CardTone(
          background: const Color(0xFF242C28),
          border: const Color(0xFF343E38),
          icon: Icons.bar_chart_rounded,
          iconBackground: const Color(0xFF314038),
          iconColor: const Color(0xFF9DC7AE),
        ),
        components: _CardTone(
          background: const Color(0xFF2C2A24),
          border: const Color(0xFF3E3A32),
          icon: Icons.grid_view_rounded,
          iconBackground: const Color(0xFF3A352C),
          iconColor: const Color(0xFFD4C09A),
        ),
        memory: _CardTone(
          background: const Color(0xFF292733),
          border: const Color(0xFF3C3848),
          icon: Icons.lightbulb_outline,
          iconBackground: const Color(0xFF383448),
          iconColor: const Color(0xFFB3A8C8),
        ),
        stats: _CardTone(
          background: const Color(0xFF242320),
          border: const Color(0xFF35332E),
          icon: Icons.assignment_outlined,
          iconBackground: const Color(0xFF31363F),
          iconColor: const Color(0xFF9AABC8),
        ),
        readingChip: const Color(0xFF383448),
        readingChipText: const Color(0xFFC4BAD4),
      );
    }

    return _DetailPalette(
      heroWash: const Color(0xFFE7E0D2),
      pill: const Color(0xFFE8E2D6),
      meaning: const _CardTone(
        background: Color(0xFFF3F5FA),
        border: Color(0xFFE3E7F1),
        icon: Icons.menu_book_outlined,
        iconBackground: Color(0xFFE3E8F4),
        iconColor: Color(0xFF5C6B92),
      ),
      readings: const _CardTone(
        background: Color(0xFFF6F4F9),
        border: Color(0xFFE8E4F0),
        icon: Icons.menu_book_outlined,
        iconBackground: Color(0xFFE8E3F3),
        iconColor: Color(0xFF7A6E96),
      ),
      status: const _CardTone(
        background: Color(0xFFF3F7F4),
        border: Color(0xFFE1EAE3),
        icon: Icons.bar_chart_rounded,
        iconBackground: Color(0xFFDDE9E1),
        iconColor: Color(0xFF3E7A5C),
      ),
      components: const _CardTone(
        background: Color(0xFFFBF7EF),
        border: Color(0xFFF0E6D4),
        icon: Icons.grid_view_rounded,
        iconBackground: Color(0xFFF3E6C8),
        iconColor: Color(0xFFB8923E),
      ),
      memory: const _CardTone(
        background: Color(0xFFF5F3F9),
        border: Color(0xFFE6E2EE),
        icon: Icons.lightbulb_outline,
        iconBackground: Color(0xFFE7E2F3),
        iconColor: Color(0xFF7A6E96),
      ),
      stats: const _CardTone(
        background: Color(0xFFFCFBF8),
        border: Color(0xFFE7E2D8),
        icon: Icons.assignment_outlined,
        iconBackground: Color(0xFFE6ECF4),
        iconColor: Color(0xFF5C6B92),
      ),
      readingChip: const Color(0xFFEBE6F3),
      readingChipText: const Color(0xFF6E6484),
    );
  }
}
