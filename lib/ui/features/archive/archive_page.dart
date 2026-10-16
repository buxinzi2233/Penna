import 'package:flutter/material.dart';

import '../../../core/harness/draft_block.dart';
import '../../../data/services/archive_store.dart';
import '../../core/smooth_scroll.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../settings/settings_sections.dart';
import '../studio/studio_view_model.dart';
import '../../../l10n/l10n.dart';

/// 问用户这份成稿叫什么、归到哪一类;取消返回 null。
Future<({String title, String category})?> showSaveDialog(
  BuildContext context,
  List<String> categories,
) {
  var title = '';
  var category = categories.firstOrNull ?? '';
  // 点了已有分类后,分类输入框靠它重建来显示选中的名字。
  var picks = 0;
  return showDialog<({String title, String category})>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        title: Text(tr('保存到档案库'), style: TextStyle(fontSize: 16)),
        content: SizedBox(
          width: 360,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              PennaField(
                label: tr('名称'),
                hint: tr('可留空'),
                value: title,
                onChanged: (v) => title = v,
              ),
              const SizedBox(height: 12),
              PennaField(
                key: ValueKey(picks),
                label: tr('分类'),
                hint: tr(uncategorized),
                value: category,
                onChanged: (v) => setState(() => category = v),
              ),
              if (categories.isNotEmpty) ...[
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final c in categories)
                      PennaChip(
                        label: tr(c), // 「未分类」要翻译,自己起的分类原样
                        selected: c == category.trim(),
                        onTap: () => setState(() {
                          category = c;
                          picks++;
                        }),
                      ),
                  ],
                ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(tr('取消')),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.pop(context, (title: title, category: category)),
            child: Text(tr('保存')),
          ),
        ],
      ),
    ),
  );
}

/// 档案库:用户存下来的成稿,按分类筛选,新的在前。
class ArchivePage extends StatefulWidget {
  const ArchivePage({
    super.key,
    required this.archive,
    required this.vm,
    required this.onOpenStudio,
  });

  final ArchiveStore archive;
  final StudioViewModel vm;

  /// 放回成稿之后回到工作台。
  final VoidCallback onOpenStudio;

  @override
  State<ArchivePage> createState() => _ArchivePageState();
}

class _ArchivePageState extends State<ArchivePage> {
  /// 只看这个分类;null 是全部。
  String? _category;

  void _restore(ArchiveEntry entry) {
    final problem = widget.vm.restorePrompt((
      time: entry.time,
      text: entry.text,
    ), title: tr('档案库'));
    if (problem != null) return showToast(context, problem, warn: true);
    widget.onOpenStudio();
  }

  Future<void> _delete(ArchiveEntry entry) async {
    final name = entry.title.isEmpty ? tr('这条记录') : tr('「{0}」', [entry.title]);
    if (await confirmDelete(context, tr('删除{0}?', [name]), tr('删掉后找不回来。'))) {
      widget.archive.remove(entry.id);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.archive,
      builder: (context, _) {
        final all = widget.archive.entries;
        final categories = widget.archive.categories;
        // 筛着的分类被删空了就回到全部。
        final category = categories.contains(_category) ? _category : null;
        final shown = [
          for (final e in all)
            if (category == null || e.category == category) e,
        ];
        return ColoredBox(
          color: PennaColors.editorBg,
          child: Column(
            children: [
              PennaBar(
                color: PennaColors.card,
                children: [
                  Icon(
                    Icons.inventory_2_outlined,
                    size: 15,
                    color: PennaColors.primary,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    tr('档案库'),
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    tr('{0} 条', [all.length]),
                    style: TextStyle(fontSize: 11, color: PennaColors.slate500),
                  ),
                ],
              ),
              if (all.isEmpty)
                Expanded(
                  child: Center(
                    child: Text(
                      tr('还没有存档 · 在工作区点「保存」'),
                      style: TextStyle(
                        fontSize: 12,
                        color: PennaColors.slate400,
                      ),
                    ),
                  ),
                )
              else
                Expanded(
                  child: SmoothScroller(
                    builder: (controller) => ListView(
                      controller: controller,
                      padding: const EdgeInsets.all(16),
                      children: [
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: [
                            PennaChip(
                              label: tr('全部'),
                              selected: category == null,
                              onTap: () => setState(() => _category = null),
                            ),
                            for (final c in categories)
                              PennaChip(
                                label: tr(c),
                                selected: c == category,
                                onTap: () => setState(() => _category = c),
                              ),
                          ],
                        ),
                        for (final entry in shown) ...[
                          const SizedBox(height: 10),
                          _EntryCard(
                            key: ValueKey(entry.id),
                            entry: entry,
                            onRestore: () => _restore(entry),
                            onDelete: () => _delete(entry),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _EntryCard extends StatelessWidget {
  const _EntryCard({
    super.key,
    required this.entry,
    required this.onRestore,
    required this.onDelete,
  });

  final ArchiveEntry entry;
  final VoidCallback onRestore;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    // 预览和复制都用干净的提示词;放回成稿时才带着分段标注。
    final clean = stripSectionLabels(entry.text);
    return PennaCard(
      padding: const EdgeInsets.fromLTRB(12, 8, 8, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              PennaCard(
                color: PennaColors.primaryBg,
                borderColor: PennaColors.primaryBorder,
                radius: 99,
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
                child: Text(
                  tr(entry.category),
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: PennaColors.primary,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  entry.title.isEmpty ? tr('未命名') : entry.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: entry.title.isEmpty
                        ? PennaColors.slate400
                        : PennaColors.text,
                  ),
                ),
              ),
              Text(
                shortTime(entry.time),
                style: TextStyle(fontSize: 11, color: PennaColors.slate400),
              ),
              const SizedBox(width: 8),
              PennaButton(
                label: tr('放回成稿'),
                icon: Icons.keyboard_double_arrow_up,
                onPressed: onRestore,
              ),
              PennaButton(
                label: tr('复制'),
                icon: Icons.content_copy,
                onPressed: () => copyWithToast(context, clean, tr('已复制')),
              ),
              IconButton(
                tooltip: tr('删除'),
                iconSize: 15,
                visualDensity: VisualDensity.compact,
                color: PennaColors.slate400,
                icon: const Icon(Icons.delete_outline),
                onPressed: onDelete,
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            clean,
            maxLines: 5,
            overflow: TextOverflow.ellipsis,
            style: monoStyle.copyWith(fontSize: 11.5),
          ),
        ],
      ),
    );
  }
}
