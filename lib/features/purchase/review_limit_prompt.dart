import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../services/curriculum/curriculum_access.dart';
import '../../services/curriculum/curriculum_links.dart';
import '../../widgets/primary_button.dart';
import 'legal_placeholders.dart';

/// Shown once at the start of a review session after the free trial is used.
Future<void> showReviewLimitPrompt(
  BuildContext context,
  CurriculumAccess access,
) {
  access.analytics.paywallViewed();
  return showDialog<void>(
    context: context,
    barrierDismissible: true,
    builder: (dialogContext) {
      return _ReviewLimitDialog(access: access);
    },
  );
}

class _ReviewLimitDialog extends StatefulWidget {
  const _ReviewLimitDialog({required this.access});

  final CurriculumAccess access;

  @override
  State<_ReviewLimitDialog> createState() => _ReviewLimitDialogState();
}

class _ReviewLimitDialogState extends State<_ReviewLimitDialog> {
  @override
  void initState() {
    super.initState();
    widget.access.addListener(_onAccess);
  }

  @override
  void dispose() {
    widget.access.removeListener(_onAccess);
    super.dispose();
  }

  void _onAccess() {
    if (!mounted) return;
    final access = widget.access;
    if (access.unlocked && !access.promptCancelMonthly) {
      Navigator.of(context).maybePop();
      return;
    }
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final access = widget.access;
    final theme = Theme.of(context);
    final message = _statusMessage(access);

    return AlertDialog(
      title: const Text("You've learned your first 50 kanji!"),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'You can keep reviewing what you\'ve learned. '
              'Unlock the full curriculum to learn new kanji.',
            ),
            if (message != null) ...[
              const SizedBox(height: 12),
              Text(message, style: _messageStyle(theme, access)),
            ],
            if (access.promptCancelMonthly) ...[
              const SizedBox(height: 12),
              const Text(_cancelMonthlyCopy),
              _ManageSubscriptionButton(access: access),
            ],
            if (!access.lifetimeOwned) ...[
              const SizedBox(height: 20),
              PrimaryButton(
                label: access.purchaseButtonLabel,
                onPressed: access.purchaseInProgress ? null : access.buy,
              ),
              if (!access.subscriptionActive) ...[
                const SizedBox(height: 4),
                TextButton(
                  onPressed: access.purchaseInProgress ? null : access.buyMonthly,
                  child: Text(access.monthlyButtonLabel),
                ),
                const SizedBox(height: 4),
                Text(
                  access.monthlyDisclosure,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.mutedText,
                    height: 1.35,
                  ),
                ),
                const _LegalLinks(),
              ],
            ],
            const SizedBox(height: 4),
            TextButton(
              onPressed: access.purchaseInProgress
                  ? null
                  : () => Navigator.of(context).maybePop(),
              child: const Text('Keep reviewing'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Purchase screen opened from Settings.
class UnlockCurriculumScreen extends StatefulWidget {
  const UnlockCurriculumScreen({super.key});

  @override
  State<UnlockCurriculumScreen> createState() => _UnlockCurriculumScreenState();
}

class _UnlockCurriculumScreenState extends State<UnlockCurriculumScreen> {
  CurriculumAccess? _access;
  CurriculumNotice? _seenNotice;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<CurriculumAccess>().analytics.paywallViewed();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final access = context.read<CurriculumAccess>();
    if (identical(_access, access)) return;
    _access?.removeListener(_onAccess);
    _access = access;
    _seenNotice = access.notice;
    access.addListener(_onAccess);
    if (access.lifetimeOwned && !access.promptCancelMonthly) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || _access?.lifetimeOwned != true) return;
        if (_access?.promptCancelMonthly == true) return;
        Navigator.of(context).maybePop();
      });
    }
  }

  void _onAccess() {
    if (!mounted) return;
    final access = _access;
    if (access == null) return;
    final previous = _seenNotice;
    _seenNotice = access.notice;
    if (access.promptCancelMonthly) {
      setState(() {});
      return;
    }
    final justUnlocked =
        previous != CurriculumNotice.unlocked &&
        access.notice == CurriculumNotice.unlocked;
    if (justUnlocked) Navigator.of(context).maybePop();
  }

  @override
  void dispose() {
    _access?.removeListener(_onAccess);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final access = context.watch<CurriculumAccess>();
    final theme = Theme.of(context);
    final price = access.localizedPrice;
    final message = _statusMessage(access);

    return Scaffold(
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: IconButton(
                tooltip: 'Close',
                onPressed: () => Navigator.of(context).maybePop(),
                icon: const Icon(Icons.close),
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
                children: [
                  Text(
                    'Unlock the full curriculum',
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 20),
                  _LifetimeOffer(access: access, price: price),
                  if (!access.lifetimeOwned && !access.subscriptionActive) ...[
                    const SizedBox(height: 16),
                    _MonthlyOffer(access: access),
                  ],
                  if (access.storeUnavailable) ...[
                    const SizedBox(height: 16),
                    Text(
                      'The store is unavailable right now. You can keep reviewing.',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.mutedText,
                        height: 1.4,
                      ),
                    ),
                  ] else if (access.productsFailedToLoad && price == null) ...[
                    const SizedBox(height: 16),
                    Text(
                      'The store products could not be loaded.',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.error,
                        height: 1.4,
                      ),
                    ),
                  ],
                  if (message != null) ...[
                    const SizedBox(height: 16),
                    Text(message, style: _messageStyle(theme, access)),
                  ],
                  if (access.promptCancelMonthly) ...[
                    const SizedBox(height: 16),
                    Text(
                      _cancelMonthlyCopy,
                      style: theme.textTheme.bodyMedium?.copyWith(height: 1.4),
                    ),
                  ],
                  if (access.subscriptionActive) ...[
                    const SizedBox(height: 8),
                    _ManageSubscriptionButton(access: access),
                  ],
                  const SizedBox(height: 12),
                  TextButton(
                    onPressed: access.purchaseInProgress ? null : access.restore,
                    child: const Text('Restore Purchases'),
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

class _LifetimeOffer extends StatelessWidget {
  const _LifetimeOffer({required this.access, required this.price});

  final CurriculumAccess access;
  final String? price;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.indigoWash,
        borderRadius: BorderRadius.circular(AppTheme.cardRadius),
        border: Border.all(color: theme.colorScheme.primary, width: 1.5),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Lifetime',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Learn every kanji, with no subscription.',
              style: theme.textTheme.bodyLarge?.copyWith(height: 1.4),
            ),
            const SizedBox(height: 12),
            Text(
              price ?? 'The price will appear when the store responds.',
              style: theme.textTheme.headlineMedium?.copyWith(
                fontWeight: FontWeight.w600,
                color: price == null ? theme.mutedText : null,
              ),
            ),
            const SizedBox(height: 16),
            PrimaryButton(
              label: access.purchaseInProgress
                  ? 'Contacting the store…'
                  : 'Unlock full version',
              onPressed: access.purchaseInProgress || access.lifetimeOwned
                  ? null
                  : access.buy,
            ),
          ],
        ),
      ),
    );
  }
}

class _MonthlyOffer extends StatelessWidget {
  const _MonthlyOffer({required this.access});

  final CurriculumAccess access;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final price = access.monthlyPrice;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Monthly',
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            price ?? 'The price will appear when the store responds.',
            style: theme.textTheme.titleMedium?.copyWith(
              color: price == null ? theme.mutedText : null,
            ),
          ),
          TextButton(
            onPressed: access.purchaseInProgress ? null : access.buyMonthly,
            child: Text(access.monthlyButtonLabel),
          ),
          Text(
            access.monthlyDisclosure,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.mutedText,
              height: 1.35,
            ),
          ),
          const _LegalLinks(),
        ],
      ),
    );
  }
}

class _LegalLinks extends StatelessWidget {
  const _LegalLinks();

  @override
  Widget build(BuildContext context) {
    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        TextButton(
          onPressed: () {
            Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const TermsOfUsePlaceholder(),
              ),
            );
          },
          child: const Text('Terms of Use'),
        ),
        TextButton(
          onPressed: () {
            Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const PrivacyPolicyPlaceholder(),
              ),
            );
          },
          child: const Text('Privacy Policy'),
        ),
      ],
    );
  }
}

class _ManageSubscriptionButton extends StatelessWidget {
  const _ManageSubscriptionButton({required this.access});

  final CurriculumAccess access;

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: access.purchaseInProgress
          ? null
          : () {
              unawaited(openSubscriptionManagement());
            },
      child: const Text('Manage subscription'),
    );
  }
}

const _cancelMonthlyCopy =
    'Lifetime is unlocked. Cancel the monthly subscription in your store '
    'account settings so you are not billed again. It can\'t be cancelled '
    'from inside the app.';

String? _statusMessage(CurriculumAccess access) {
  return switch (access.notice) {
    CurriculumNotice.failed ||
    CurriculumNotice.pending ||
    CurriculumNotice.cancelled ||
    CurriculumNotice.nothingToRestore ||
    CurriculumNotice.cancelMonthly => access.purchaseMessage,
    CurriculumNotice.none || CurriculumNotice.unlocked => null,
  };
}

TextStyle? _messageStyle(ThemeData theme, CurriculumAccess access) {
  final failed = access.notice == CurriculumNotice.failed;
  return theme.textTheme.bodyMedium?.copyWith(
    color: failed ? theme.colorScheme.error : theme.mutedText,
    height: 1.4,
  );
}
