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
    this.prominentLinks = false,
  });

  final String mnemonic;
  final List<KanjiComponent> components;

  /// Larger link marks and a 44px tap target. Used on the first rating
  /// screen, where the small inline bulbs are hard to see.
  final bool prominentLinks;

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
              prominentLinks: prominentLinks,
              style: theme.textTheme.titleMedium!.copyWith(
                fontSize: 16,
                height: 1.35,
                color: theme.colorScheme.onSurface,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
