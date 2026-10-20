import 'package:flutter/material.dart';

import '../core/models/kanji_card.dart';
import 'mnemonic_text.dart';
import 'soft_card.dart';

/// The one content card on the learn and answer screens: a lightbulb and the
/// story that makes the kanji stick.
class MnemonicCard extends StatelessWidget {
  const MnemonicCard({
    super.key,
    required this.mnemonic,
    required this.components,
  });

  final String mnemonic;
  final List<KanjiComponent> components;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SoftCard(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ExcludeSemantics(
            child: Padding(
              padding: const EdgeInsets.only(top: 1),
              child: Icon(
                Icons.lightbulb_outline,
                size: 20,
                color: theme.colorScheme.primary,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: MnemonicText(
              mnemonic: mnemonic,
              components: components,
              style: theme.textTheme.titleMedium!.copyWith(height: 1.35),
            ),
          ),
        ],
      ),
    );
  }
}
