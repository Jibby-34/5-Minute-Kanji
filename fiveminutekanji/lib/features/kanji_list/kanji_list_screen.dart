import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/models/kanji_status.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/app_typography.dart';
import '../../repositories/kanji_repository.dart';
import '../../repositories/progress_repository.dart';
import '../../services/mark_as_known.dart';
import '../../widgets/bottom_action_inset.dart';
import '../../widgets/primary_button.dart';
import 'kanji_detail_screen.dart';
import 'kanji_list_controller.dart';

class KanjiListScreen extends StatelessWidget {
  const KanjiListScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (context) => KanjiListController(
        kanjiRepository: context.read<KanjiRepository>(),
        progressRepository: context.read<ProgressRepository>(),
        markAsKnown: context.read<MarkAsKnownService>(),
      )..load(),
      child: const _KanjiListView(),
    );
  }
}

class _KanjiListView extends StatelessWidget {
  const _KanjiListView();

  Future<void> _openDetail(
    BuildContext context,
    KanjiListController controller,
    KanjiListItem item,
  ) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => KanjiDetailScreen(
          card: item.card,
          schedule: item.schedule,
          status: item.status,
        ),
      ),
    );
    if (!context.mounted) return;
    await controller.load(showLoading: false);
  }

  Future<void> _confirmMarkAsKnown(
    BuildContext context,
    KanjiListController controller,
  ) async {
    final count = controller.selectedCount;
    if (count == 0 || controller.busy) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text('Mark $count kanji as known?'),
          content: const Text(
            'These kanji will skip the normal learning process and enter your review schedule with a long initial interval.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Mark as Known'),
            ),
          ],
        );
      },
    );
    if (confirmed != true || !context.mounted) return;
    await controller.markSelectedAsKnown();
  }

  List<Widget> _sectionSlivers(
    KanjiListController controller,
    KanjiListSection section, {
    required bool isFirst,
  }) {
    return [
      SliverToBoxAdapter(
        child: _JlptSectionHeader(
          title: section.level.sectionTitle,
          isFirst: isFirst,
        ),
      ),
      SliverPadding(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 0),
        sliver: SliverGrid(
          gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: 112,
            mainAxisSpacing: 16,
            crossAxisSpacing: 16,
            childAspectRatio: 1,
          ),
          delegate: SliverChildBuilderDelegate((context, index) {
            final item = section.items[index];
            final selectable = controller.isSelectable(item);
            final selected = controller.isSelected(item.card.id);
            return _KanjiListCard(
              character: item.card.character,
              status: item.status,
              selecting: controller.selecting,
              selectable: selectable,
              selected: selected,
              onTap: () {
                if (controller.selecting) {
                  controller.toggleSelected(item.card.id);
                  return;
                }
                _openDetail(context, controller, item);
              },
            );
          }, childCount: section.items.length),
        ),
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<KanjiListController>();
    final theme = Theme.of(context);
    final sections = controller.sections;

    return PopScope(
      canPop: !controller.selecting,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && controller.selecting) {
          controller.exitSelection();
        }
      },
      child: Scaffold(
        body: SafeArea(
          bottom: !controller.selecting,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 4, 8, 0),
                child: Row(
                  children: [
                    IconButton(
                      tooltip: controller.selecting ? 'Done' : 'Back',
                      onPressed: () {
                        if (controller.selecting) {
                          controller.exitSelection();
                        } else {
                          Navigator.of(context).maybePop();
                        }
                      },
                      icon: Icon(
                        controller.selecting ? Icons.close : Icons.arrow_back,
                      ),
                    ),
                    Expanded(
                      child: Text(
                        controller.selecting
                            ? '${controller.selectedCount} selected'
                            : 'Kanji List',
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    if (!controller.loading)
                      TextButton(
                        onPressed: controller.selecting
                            ? controller.exitSelection
                            : controller.enterSelection,
                        child: Text(controller.selecting ? 'Done' : 'Select'),
                      ),
                  ],
                ),
              ),
              if (controller.selecting)
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 0, 8, 0),
                  child: Wrap(
                    spacing: 4,
                    children: [
                      TextButton(
                        onPressed: controller.busy
                            ? null
                            : controller.selectAllNew,
                        child: const Text('Select All New'),
                      ),
                      TextButton(
                        onPressed:
                            controller.busy || controller.selectedCount == 0
                            ? null
                            : controller.clearSelection,
                        child: const Text('Clear Selection'),
                      ),
                    ],
                  ),
                ),
              Expanded(
                child: controller.loading
                    ? const Center(
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : CustomScrollView(
                        physics: const BouncingScrollPhysics(),
                        slivers: [
                          for (var i = 0; i < sections.length; i++)
                            ..._sectionSlivers(
                              controller,
                              sections[i],
                              isFirst: i == 0,
                            ),
                          const SliverToBoxAdapter(child: SizedBox(height: 32)),
                        ],
                      ),
              ),
              if (controller.selecting)
                BottomActionInset(
                  child: PrimaryButton(
                    label: 'Mark as Known',
                    onPressed: controller.busy || controller.selectedCount == 0
                        ? null
                        : () => _confirmMarkAsKnown(context, controller),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _JlptSectionHeader extends StatelessWidget {
  const _JlptSectionHeader({required this.title, required this.isFirst});

  final String title;
  final bool isFirst;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(24, isFirst ? 12 : 32, 24, 14),
      child: Text(
        title,
        style: theme.textTheme.titleMedium?.copyWith(
          fontWeight: FontWeight.w600,
          letterSpacing: 0.3,
          color: theme.mutedText,
        ),
      ),
    );
  }
}

class _KanjiListCard extends StatelessWidget {
  const _KanjiListCard({
    required this.character,
    required this.status,
    required this.onTap,
    this.selecting = false,
    this.selectable = true,
    this.selected = false,
  });

  final String character;
  final KanjiProgressStatus status;
  final VoidCallback onTap;
  final bool selecting;
  final bool selectable;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dimmed = selecting && !selectable;
    final borderColor = selected ? theme.colorScheme.primary : theme.hairline;
    final borderWidth = selected ? 2.0 : 1.0;

    return Opacity(
      opacity: dimmed ? 0.42 : 1,
      child: Material(
        color: theme.statusWash(status),
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: selecting && !selectable ? null : onTap,
          borderRadius: BorderRadius.circular(12),
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: borderColor, width: borderWidth),
            ),
            child: Stack(
              children: [
                Center(
                  child: Padding(
                    padding: const EdgeInsets.all(10),
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        character,
                        style: AppTypography.kanji(
                          color: theme.colorScheme.onSurface,
                          size: 40,
                        ),
                      ),
                    ),
                  ),
                ),
                if (selected)
                  Positioned(
                    top: 6,
                    right: 6,
                    child: Icon(
                      Icons.check_circle,
                      size: 18,
                      color: theme.colorScheme.primary,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
