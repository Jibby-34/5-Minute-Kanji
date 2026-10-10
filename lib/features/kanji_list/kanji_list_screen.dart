import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/models/kanji_status.dart';
import '../../core/theme/app_colors.dart';
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

  Future<void> _showSortSheet(
    BuildContext context,
    KanjiListController controller,
  ) async {
    FocusManager.instance.primaryFocus?.unfocus();
    final theme = Theme.of(context);
    await showModalBottomSheet<void>(
      context: context,
      useRootNavigator: false,
      showDragHandle: true,
      backgroundColor: theme.scaffoldBackgroundColor,
      builder: (sheetContext) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final option in KanjiListOrdering.displayOptions)
                ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 24),
                  title: Text(
                    option.label,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: option == controller.ordering
                          ? FontWeight.w600
                          : FontWeight.w500,
                    ),
                  ),
                  trailing: option == controller.ordering
                      ? Icon(Icons.check, color: theme.colorScheme.primary)
                      : null,
                  onTap: () {
                    controller.setOrdering(option);
                    Navigator.of(sheetContext).pop();
                  },
                ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }

  List<Widget> _sectionSlivers(
    KanjiListController controller,
    KanjiListSection section, {
    required bool isFirst,
  }) {
    final expanded = controller.isSectionExpanded(section.level);
    return [
      SliverToBoxAdapter(
        child: _JlptSectionHeader(
          title: section.level.sectionTitle,
          count: section.items.length,
          expanded: expanded,
          isFirst: isFirst,
          onTap: () => controller.toggleSection(section.level),
        ),
      ),
      if (expanded) _kanjiGrid(controller, section.items),
    ];
  }

  Widget _kanjiGrid(KanjiListController controller, List<KanjiListItem> items) {
    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 0),
      sliver: SliverGrid(
        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: 112,
          mainAxisSpacing: 16,
          crossAxisSpacing: 16,
          childAspectRatio: 1,
        ),
        delegate: SliverChildBuilderDelegate(
          (context, index) {
            final item = items[index];
            final selectable = controller.isSelectable(item);
            final selected = controller.isSelected(item.card.id);
            return _KanjiListCard(
              key: ValueKey(item.card.id),
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
          },
          childCount: items.length,
          findChildIndexCallback: (key) {
            if (key is! ValueKey<String>) return null;
            final index = items.indexWhere((item) => item.card.id == key.value);
            return index < 0 ? null : index;
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<KanjiListController>();
    final theme = Theme.of(context);
    final sections = controller.groupsByJlpt ? controller.sections : const [];
    final matchCount = controller.loading ? 0 : controller.matchCount;

    return PopScope(
      canPop: !controller.selecting,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && controller.selecting) {
          controller.exitSelection();
        }
      },
      child: Scaffold(
        resizeToAvoidBottomInset: true,
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
              if (controller.loading)
                const Expanded(
                  child: Center(
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                )
              else ...[
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 4, 24, 8),
                  child: _KanjiSearchField(onChanged: controller.setQuery),
                ),
                SizedBox(
                  height: 40,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    itemCount: KanjiListStatusFilter.values.length,
                    separatorBuilder: (_, _) => const SizedBox(width: 8),
                    itemBuilder: (context, index) {
                      final filter = KanjiListStatusFilter.values[index];
                      return Align(
                        alignment: Alignment.center,
                        child: _SelectableChip(
                          label: filter.label,
                          selected: filter == controller.statusFilter,
                          onTap: () => controller.setStatusFilter(filter),
                        ),
                      );
                    },
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 2, 24, 8),
                  child: Row(
                    children: [
                      Flexible(
                        child: _SortButton(
                          label: controller.ordering.label,
                          onTap: () => _showSortSheet(context, controller),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        _kanjiCountLabel(matchCount),
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.mutedText,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: CustomScrollView(
                    key: const PageStorageKey<String>('kanji-list'),
                    keyboardDismissBehavior:
                        ScrollViewKeyboardDismissBehavior.onDrag,
                    physics: const BouncingScrollPhysics(),
                    slivers: [
                      if (matchCount == 0)
                        SliverFillRemaining(
                          hasScrollBody: false,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 32),
                            child: Center(
                              child: Text(
                                controller.searchActive
                                    ? 'No kanji match your search.'
                                    : 'No kanji match this filter.',
                                textAlign: TextAlign.center,
                                style: theme.textTheme.bodyLarge?.copyWith(
                                  color: theme.mutedText,
                                ),
                              ),
                            ),
                          ),
                        )
                      else if (controller.groupsByJlpt)
                        for (var i = 0; i < sections.length; i++)
                          ..._sectionSlivers(
                            controller,
                            sections[i],
                            isFirst: i == 0,
                          )
                      else ...[
                        const SliverToBoxAdapter(child: SizedBox(height: 4)),
                        _kanjiGrid(controller, controller.visibleItems),
                      ],
                      const SliverToBoxAdapter(child: SizedBox(height: 32)),
                    ],
                  ),
                ),
              ],
              if (controller.selecting)
                BottomActionInset(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Align(
                              alignment: Alignment.centerLeft,
                              child: TextButton(
                                onPressed: controller.busy
                                    ? null
                                    : controller.selectAllNew,
                                child: const Text('Select All New'),
                              ),
                            ),
                          ),
                          Expanded(
                            child: Align(
                              alignment: Alignment.centerRight,
                              child: TextButton(
                                onPressed:
                                    controller.busy ||
                                        controller.selectedCount == 0
                                    ? null
                                    : controller.clearSelection,
                                child: const Text('Clear Selection'),
                              ),
                            ),
                          ),
                        ],
                      ),
                      PrimaryButton(
                        label: 'Mark as Known',
                        onPressed:
                            controller.busy || controller.selectedCount == 0
                            ? null
                            : () => _confirmMarkAsKnown(context, controller),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

String _kanjiCountLabel(int count) {
  return count == 1 ? '1 kanji' : '$count kanji';
}

class _KanjiSearchField extends StatefulWidget {
  const _KanjiSearchField({required this.onChanged});

  final ValueChanged<String> onChanged;

  @override
  State<_KanjiSearchField> createState() => _KanjiSearchFieldState();
}

class _KanjiSearchFieldState extends State<_KanjiSearchField> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    setState(() {});
    widget.onChanged(value);
  }

  void _clear() {
    _controller.clear();
    _onChanged('');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide(color: theme.hairline),
    );
    final dark = theme.brightness == Brightness.dark;

    return TextField(
      key: const Key('kanji-list-search'),
      controller: _controller,
      onChanged: _onChanged,
      textInputAction: TextInputAction.search,
      autocorrect: false,
      enableSuggestions: false,
      style: theme.textTheme.bodyLarge,
      cursorColor: theme.colorScheme.primary,
      decoration: InputDecoration(
        isDense: true,
        hintText: 'Search kanji or meaning...',
        hintStyle: theme.textTheme.bodyLarge?.copyWith(color: theme.mutedText),
        prefixIcon: Icon(Icons.search, size: 20, color: theme.mutedText),
        prefixIconConstraints: const BoxConstraints(
          minWidth: 40,
          minHeight: 40,
        ),
        suffixIcon: _controller.text.isEmpty
            ? null
            : IconButton(
                tooltip: 'Clear search',
                onPressed: _clear,
                icon: Icon(Icons.close, size: 18, color: theme.mutedText),
              ),
        suffixIconConstraints: const BoxConstraints(
          minWidth: 40,
          minHeight: 40,
        ),
        filled: true,
        fillColor: dark ? AppColors.darkSurface : AppColors.paperDeep,
        contentPadding: const EdgeInsets.symmetric(vertical: 10),
        border: border,
        enabledBorder: border,
        focusedBorder: border.copyWith(
          borderSide: BorderSide(color: theme.colorScheme.primary, width: 1.4),
        ),
      ),
    );
  }
}

class _SortButton extends StatelessWidget {
  const _SortButton({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      button: true,
      label: 'Sort by $label',
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          key: const Key('kanji-list-sort'),
          onTap: onTap,
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  fit: FlexFit.loose,
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                Icon(Icons.arrow_drop_down, color: theme.mutedText),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SelectableChip extends StatelessWidget {
  const _SelectableChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final background = selected ? theme.colorScheme.primary : theme.cardColor;
    final foreground = selected
        ? theme.colorScheme.onPrimary
        : theme.colorScheme.onSurface;
    return Semantics(
      button: true,
      selected: selected,
      child: Material(
        color: background,
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(18),
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: selected ? theme.colorScheme.primary : theme.hairline,
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              child: Text(
                label,
                style: theme.textTheme.labelLarge?.copyWith(
                  color: foreground,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _JlptSectionHeader extends StatelessWidget {
  const _JlptSectionHeader({
    required this.title,
    required this.count,
    required this.expanded,
    required this.isFirst,
    required this.onTap,
  });

  final String title;
  final int count;
  final bool expanded;
  final bool isFirst;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final countLabel = _kanjiCountLabel(count);
    return Semantics(
      button: true,
      expanded: expanded,
      label: '$title, $countLabel',
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: onTap,
          child: ExcludeSemantics(
            child: Padding(
              padding: EdgeInsets.fromLTRB(24, isFirst ? 4 : 16, 12, 10),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      title,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.3,
                        color: theme.mutedText,
                      ),
                    ),
                  ),
                  Text(
                    '$count',
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: theme.mutedText,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Icon(
                    expanded ? Icons.expand_less : Icons.expand_more,
                    size: 22,
                    color: theme.mutedText,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _KanjiListCard extends StatelessWidget {
  const _KanjiListCard({
    super.key,
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
    final label = [
      character,
      status.label,
      if (selecting && selected) 'selected',
    ].join(', ');

    return Semantics(
      button: true,
      enabled: !dimmed,
      selected: selecting && selected,
      label: label,
      child: ExcludeSemantics(
        child: Opacity(
          opacity: dimmed ? 0.42 : 1,
          child: Material(
            color: theme.statusWash(status),
            borderRadius: BorderRadius.circular(12),
            child: InkWell(
              onTap: dimmed ? null : onTap,
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
        ),
      ),
    );
  }
}
