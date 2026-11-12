import 'package:flutter/material.dart';

import '../core/theme/app_theme.dart';

/// Quiet extra gloss under a keyword when two kanji share a meaning.
///
/// Smaller and muted so the original keyword stays the thing to recall.
class DisambiguationHint extends StatelessWidget {
  const DisambiguationHint(
    this.text, {
    super.key,
    this.textAlign = TextAlign.start,
    this.maxLines,
    this.fontSize = 14,
  });

  final String text;
  final TextAlign textAlign;
  final int? maxLines;
  final double fontSize;

  /// Gap plus hint, or nothing when [value] is null or blank.
  static List<Widget> below(
    String? value, {
    TextAlign textAlign = TextAlign.start,
    double fontSize = 14,
    int? maxLines,
    double gap = 4,
  }) {
    final text = value?.trim();
    if (text == null || text.isEmpty) return const [];
    return [
      SizedBox(height: gap),
      DisambiguationHint(
        text,
        textAlign: textAlign,
        fontSize: fontSize,
        maxLines: maxLines,
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Text(
      text,
      textAlign: textAlign,
      maxLines: maxLines,
      overflow: maxLines == null ? TextOverflow.visible : TextOverflow.ellipsis,
      style: theme.textTheme.bodyMedium?.copyWith(
        color: theme.mutedText,
        fontSize: fontSize,
        fontWeight: FontWeight.w500,
        height: 1.25,
      ),
    );
  }
}
