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
                  onPressed: access.purchaseInProgress
                      ? null
                      : access.buyMonthly,
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

    return Scaffold(
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final tight = constraints.maxHeight < 700;
            return CustomScrollView(
              slivers: [
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(24, 0, 24, tight ? 4 : 8),
                    child: _PaywallColumn(access: access, tight: tight),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _PaywallColumn extends StatelessWidget {
  const _PaywallColumn({required this.access, required this.tight});

  final CurriculumAccess access;
  final bool tight;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final message = _statusMessage(access);
    final gap = tight ? 8.0 : 12.0;

    return Column(
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
        Text(
          'Unlock the full curriculum',
          style: theme.textTheme.headlineMedium?.copyWith(
            fontSize: 32,
            fontWeight: FontWeight.w700,
            height: 1.05,
            letterSpacing: -0.6,
            color: AppColors.charcoal,
          ),
        ),
        SizedBox(height: tight ? 6 : 8),
        Text(
          'Keep going past your first 50 kanji.',
          style: theme.textTheme.bodyLarge?.copyWith(
            fontSize: 17,
            height: 1.25,
            color: AppColors.muted,
          ),
        ),
        SizedBox(height: tight ? 14 : 22),
        _BenefitList(gap: gap, compact: tight),
        SizedBox(height: tight ? 16 : 28),
        const Spacer(),
        _LifetimeHero(access: access, tight: tight),
        SizedBox(height: tight ? 10 : 14),
        _MonthlyRow(access: access),
        if (access.storeUnavailable) ...[
          const SizedBox(height: 12),
          Text(
            'The store is unavailable right now. You can keep reviewing.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: AppColors.muted,
              height: 1.4,
            ),
          ),
        ] else if (access.productsFailedToLoad &&
            access.localizedPrice == null) ...[
          const SizedBox(height: 12),
          Text(
            'The store products could not be loaded.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.error,
              height: 1.4,
            ),
          ),
        ],
        if (message != null) ...[
          const SizedBox(height: 12),
          Text(
            message,
            textAlign: TextAlign.center,
            style: _messageStyle(theme, access),
          ),
        ],
        if (access.promptCancelMonthly) ...[
          const SizedBox(height: 12),
          Text(
            _cancelMonthlyCopy,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(height: 1.4),
          ),
        ],
        if (access.subscriptionActive)
          _ManageSubscriptionButton(access: access),
        SizedBox(height: tight ? 10 : 14),
        Text(
          access.monthlyDisclosure,
          textAlign: TextAlign.center,
          style: theme.textTheme.bodySmall?.copyWith(
            fontSize: 12.5,
            height: 1.4,
            color: AppColors.muted,
          ),
        ),
        SizedBox(height: tight ? 4 : 8),
        _PaywallLinks(access: access),
      ],
    );
  }
}

class _BenefitList extends StatelessWidget {
  const _BenefitList({required this.gap, required this.compact});

  final double gap;
  final bool compact;

  static const _items = [
    'Every kanji, start anywhere',
    'Smart 5-minute daily reviews',
    'Writing practice and mnemonics',
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style = theme.textTheme.bodyLarge?.copyWith(
      fontSize: compact ? 16 : 17,
      height: 1.2,
      color: AppColors.charcoal,
    );
    return Column(
      children: [
        for (var i = 0; i < _items.length; i++) ...[
          if (i > 0) SizedBox(height: gap),
          Row(
            children: [
              Container(
                width: 26,
                height: 26,
                alignment: Alignment.center,
                decoration: const BoxDecoration(
                  color: AppColors.indigoWash,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.check,
                  size: 15,
                  color: AppColors.indigo,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(child: Text(_items[i], style: style)),
            ],
          ),
        ],
      ],
    );
  }
}

class _LifetimeHero extends StatelessWidget {
  const _LifetimeHero({required this.access, required this.tight});

  final CurriculumAccess access;
  final bool tight;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final price = access.localizedPrice;

    return Padding(
      padding: const EdgeInsets.only(top: 13),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              color: AppColors.indigoWash,
              borderRadius: BorderRadius.circular(28),
              border: Border.all(color: AppColors.indigo, width: 2),
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(22, 26, 22, 22),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Lifetime',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: AppColors.charcoal,
                    ),
                  ),
                  SizedBox(height: tight ? 4 : 8),
                  if (price == null)
                    Text(
                      'The price will appear when the store responds.',
                      style: theme.textTheme.bodyLarge?.copyWith(
                        fontSize: 16,
                        height: 1.3,
                        color: AppColors.muted,
                      ),
                    )
                  else
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.baseline,
                        textBaseline: TextBaseline.alphabetic,
                        children: [
                          Text(
                            price,
                            style: theme.textTheme.displaySmall?.copyWith(
                              fontSize: 60,
                              fontWeight: FontWeight.w700,
                              height: 1,
                              letterSpacing: -2,
                              color: AppColors.charcoal,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'one time',
                            style: theme.textTheme.bodyLarge?.copyWith(
                              fontSize: 16,
                              color: AppColors.muted,
                            ),
                          ),
                        ],
                      ),
                    ),
                  const SizedBox(height: 18),
                  Text(
                    'Learn every kanji, with no subscription.',
                    style: theme.textTheme.bodyLarge?.copyWith(
                      fontSize: 16,
                      height: 1.3,
                      color: AppColors.muted,
                    ),
                  ),
                  const SizedBox(height: 18),
                  FilledButton(
                    onPressed: access.purchaseInProgress || access.lifetimeOwned
                        ? null
                        : access.buy,
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.indigo,
                      foregroundColor: theme.colorScheme.onPrimary,
                      disabledBackgroundColor: AppColors.indigo.withValues(
                        alpha: 0.45,
                      ),
                      disabledForegroundColor: theme.colorScheme.onPrimary,
                      elevation: 0,
                      minimumSize: const Size.fromHeight(0),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      padding: const EdgeInsets.symmetric(vertical: 18),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(18),
                      ),
                      textStyle: theme.textTheme.titleMedium?.copyWith(
                        fontSize: 19,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    child: Text(
                      access.purchaseInProgress
                          ? 'Contacting the store…'
                          : 'Unlock full version',
                    ),
                  ),
                ],
              ),
            ),
          ),
          Positioned(
            top: -13,
            left: 18,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: AppColors.indigo,
                borderRadius: BorderRadius.circular(999),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  vertical: 4,
                  horizontal: 12,
                ),
                child: Text(
                  'BEST VALUE',
                  style: theme.textTheme.labelMedium?.copyWith(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.6,
                    color: theme.colorScheme.onPrimary,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MonthlyRow extends StatelessWidget {
  const _MonthlyRow({required this.access});

  final CurriculumAccess access;

  @override
  Widget build(BuildContext context) {
    if (access.lifetimeOwned || access.subscriptionActive) {
      return const SizedBox.shrink();
    }
    final theme = Theme.of(context);
    final price = access.monthlyPrice;
    final line = theme.textTheme.bodyMedium?.copyWith(
      fontSize: 15,
      height: 1.2,
    );

    return DecoratedBox(
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: AppColors.hairline)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Row(
          children: [
            Expanded(
              child: Text.rich(
                TextSpan(
                  style: line,
                  children: [
                    TextSpan(
                      text: 'Monthly',
                      style: line?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: AppColors.charcoal,
                      ),
                    ),
                    if (price != null)
                      TextSpan(
                        text: ' · $price / month',
                        style: line?.copyWith(color: AppColors.muted),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 12),
            OutlinedButton(
              onPressed: access.purchaseInProgress ? null : access.buyMonthly,
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.indigo,
                backgroundColor: Colors.transparent,
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                padding: const EdgeInsets.symmetric(
                  vertical: 8,
                  horizontal: 16,
                ),
                side: const BorderSide(color: AppColors.indigo, width: 1.5),
                shape: const StadiumBorder(),
                textStyle: theme.textTheme.labelLarge?.copyWith(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
              child: const Text('Subscribe'),
            ),
          ],
        ),
      ),
    );
  }
}

class _PaywallLinks extends StatelessWidget {
  const _PaywallLinks({required this.access});

  final CurriculumAccess access;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style = theme.textTheme.bodyMedium?.copyWith(
      fontSize: 14,
      fontWeight: FontWeight.w500,
      color: AppColors.indigo,
    );
    return FittedBox(
      fit: BoxFit.scaleDown,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          _PaywallLink(
            label: 'Terms of Use',
            style: style,
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const TermsOfUsePlaceholder(),
                ),
              );
            },
          ),
          const SizedBox(width: 18),
          _PaywallLink(
            label: 'Privacy Policy',
            style: style,
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const PrivacyPolicyPlaceholder(),
                ),
              );
            },
          ),
          const SizedBox(width: 18),
          _PaywallLink(
            label: 'Restore Purchases',
            style: style,
            onPressed: access.purchaseInProgress ? null : access.restore,
          ),
        ],
      ),
    );
  }
}

class _PaywallLink extends StatelessWidget {
  const _PaywallLink({
    required this.label,
    required this.style,
    required this.onPressed,
  });

  final String label;
  final TextStyle? style;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: onPressed,
      style: TextButton.styleFrom(
        foregroundColor: AppColors.indigo,
        padding: EdgeInsets.zero,
        minimumSize: Size.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        textStyle: style,
      ),
      child: Text(label),
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
