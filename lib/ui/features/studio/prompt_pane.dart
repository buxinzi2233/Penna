import 'package:flutter/material.dart';

import '../../../core/harness/draft_block.dart';
import '../../../data/services/archive_store.dart';
import '../../core/theme.dart';
import '../../core/smooth_scroll.dart';
import '../../core/widgets.dart';
import '../archive/archive_page.dart';
import '../settings/settings_sections.dart';
import 'body_card.dart';
import 'polish_dialog.dart';
import 'reverse_model.dart';
import 'reverse_pane.dart';
import 'studio_view_model.dart';

/// 顶栏里的小计数,例如「128 字符」。
class _Stat extends StatelessWidget {
  const _Stat({required this.value, required this.unit});

  final int value;
  final String unit;

  @override
  Widget build(BuildContext context) {
    return PennaCard(
      color: PennaColors.slate50,
      radius: 99,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      child: Text.rich(
        TextSpan(
          children: [
            TextSpan(
              text: '$value',
              style: const TextStyle(
                fontWeight: FontWeight.w700,
                color: PennaColors.text,
              ),
            ),
            TextSpan(text: ' $unit'),
          ],
        ),
        style: const TextStyle(fontSize: 11, color: PennaColors.slate500),
      ),
    );
  }
}

/// 左栏:上半成稿工作区,下半提示词汇总。
class PromptPane extends StatelessWidget {
  const PromptPane({
    super.key,
    required this.vm,
    required this.archive,
    required this.reverse,
    this.onDiscuss,
    this.onSendToAgent,
  });

  /// 把一段文字放进聊天输入框。
  final ValueChanged<String>? onSendToAgent;

  final StudioViewModel vm;
  final ArchiveStore archive;
  final ReverseModel reverse;

  /// 用户要拿成稿里的某一段去和 Agent 讨论。
  final ValueChanged<String>? onDiscuss;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: PennaColors.card,
      child: Column(
        children: [
          Expanded(
            flex: 14,
            child: _DraftSection(
              vm: vm,
              archive: archive,
              onDiscuss: onDiscuss,
            ),
          ),
          Expanded(
            flex: 10,
            child: _SummarySection(
              vm: vm,
              reverse: reverse,
              onSendToAgent: onSendToAgent,
            ),
          ),
        ],
      ),
    );
  }
}

class _DraftSection extends StatefulWidget {
  const _DraftSection({
    required this.vm,
    required this.archive,
    required this.onDiscuss,
  });

  final StudioViewModel vm;
  final ArchiveStore archive;
  final ValueChanged<String>? onDiscuss;

  @override
  State<_DraftSection> createState() => _DraftSectionState();
}

class _DraftSectionState extends State<_DraftSection> {
  StudioViewModel get vm => widget.vm;
  ArchiveStore get archive => widget.archive;
  ValueChanged<String>? get onDiscuss => widget.onDiscuss;

  /// 每一段的中文对照都展开着。
  bool _zhOpen = false;

  /// [section] 是只润色某一段时那段提示词的范围;不给就按用户自己的选区来。
  Future<void> _polish(BuildContext context, {(int, int)? section}) async {
    if (section != null) vm.bodySelection = section;
    final instruction = await showPolishDialog(context, vm);
    if (instruction == null) {
      // 这个范围是替用户定的,取消了就别留着,免得下次润色还落在这一段上。
      if (section != null) vm.bodySelection = null;
      return;
    }
    final problem = await vm.polish(instruction);
    if (problem != null && context.mounted) {
      showToast(context, problem, warn: true);
    }
  }

  Future<void> _clear(BuildContext context) async {
    if (await confirmDelete(context, '清空工作区?', '当前成稿会记进历史提示词,可以从那里放回来。')) {
      vm.clearDraft();
    }
  }

  /// 把当前成稿存进档案库(带着分段标注,放回来时分段还在)。
  Future<void> _save(BuildContext context) async {
    final text = vm.labeledPrompt;
    final picked = await showSaveDialog(context, archive.categories);
    if (picked == null) return;
    archive.add(text: text, title: picked.title, category: picked.category);
    if (context.mounted) showToast(context, '已存进档案库');
  }

  /// 把眼前这个系列的每一页都存进档案库:一页一条,分类就是系列的名字。
  void _saveSeries(BuildContext context) {
    final prompts = vm.seriesPrompts;
    if (prompts.isEmpty) return showToast(context, '这个系列还是空的', warn: true);
    final category = vm.seriesName(vm.series);
    final now = DateTime.now();
    // 档案库里新的在前:倒着存,第 1 页才排在最上面。时间各错开一点,编号不会撞。
    for (final (i, p) in prompts.reversed.indexed) {
      archive.add(
        text: p.text,
        title: p.title,
        category: category,
        now: now.add(Duration(microseconds: i)),
      );
    }
    showToast(context, '「$category」的 ${prompts.length} 页已存进档案库');
  }

  Future<void> _pin(BuildContext context) async {
    if (vm.pinSelection()) return;
    final text = await showPinDialog(context);
    if (text != null) vm.addPin(text);
  }

  Future<void> _translate(
    BuildContext context, {
    bool selection = false,
  }) async {
    final problem = await vm.translateDraft(selection: selection);
    if (problem != null && context.mounted) {
      showToast(context, problem, warn: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final prompt = vm.finalPrompt;
    final words = RegExp(r'\S+').allMatches(prompt).length;
    return Column(
      children: [
        PennaBar(
          color: PennaColors.card,
          children: [
            const CircleAvatar(radius: 4, backgroundColor: PennaColors.amber),
            const SizedBox(width: 6),
            const Text(
              '工作区',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
            ),
            const SizedBox(width: 10),
            // 窄的时候计数先让位,再是状态;放不下就不画,按钮始终完整。
            Expanded(
              child: LayoutBuilder(
                builder: (context, box) {
                  final chip = vm.pending != null && box.maxWidth >= _chipRoom;
                  final stats =
                      prompt.isNotEmpty &&
                      box.maxWidth >= _statsRoom + (chip ? _chipRoom : 0);
                  return ClipRect(
                    child: Row(
                      children: [
                        if (stats) ...[
                          _Stat(value: prompt.length, unit: '字符'),
                          const SizedBox(width: 6),
                          _Stat(value: words, unit: '词'),
                          const SizedBox(width: 6),
                        ],
                        if (chip)
                          Flexible(child: _PendingChip(more: vm.queuedDiffs)),
                      ],
                    ),
                  );
                },
              ),
            ),
            PennaButton(
              label: '清空',
              icon: Icons.cleaning_services_outlined,
              borderColor: PennaColors.border,
              tooltip: '清空工作区,开始写下一条',
              onPressed: vm.body.isEmpty ? null : () => _clear(context),
            ),
            const SizedBox(width: 6),
            PennaButton(
              label: '保存',
              icon: Icons.bookmark_add_outlined,
              borderColor: PennaColors.border,
              tooltip: '存进档案库',
              onPressed: prompt.isEmpty ? null : () => _save(context),
            ),
            // 这个系列不止一页时滑出来:把整个系列一起存。
            AnimatedSize(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOutCubic,
              alignment: Alignment.centerLeft,
              child: vm.seriesLength > 1
                  ? Padding(
                      padding: const EdgeInsets.only(left: 6),
                      child: PopIn(
                        child: PennaButton(
                          label: '保存系列',
                          icon: Icons.collections_bookmark_outlined,
                          background: PennaColors.accent,
                          foreground: Colors.white,
                          tooltip: '把这个系列的每一页都存进档案库',
                          onPressed: () => _saveSeries(context),
                        ),
                      ),
                    )
                  : const SizedBox.shrink(),
            ),
            const SizedBox(width: 6),
            PennaButton(
              label: '固定',
              icon: Icons.push_pin_outlined,
              borderColor: PennaColors.border,
              tooltip: '固定选中的文字,没选就新增一段',
              onPressed: vm.pending != null ? null : () => _pin(context),
            ),
            const SizedBox(width: 6),
            PennaButton(
              label: '润色',
              icon: Icons.auto_fix_high,
              borderColor: PennaColors.border,
              tooltip: '改写选中的一段,没选就是整栏',
              onPressed: prompt.isEmpty || vm.isPolishing || vm.pending != null
                  ? null
                  : () => _polish(context),
            ),
            const SizedBox(width: 6),
            PennaButton(
              label: '翻译',
              icon: Icons.translate,
              borderColor: PennaColors.border,
              onPressed: prompt.isEmpty || vm.isTranslating
                  ? null
                  : () => _translate(context),
            ),
            const SizedBox(width: 6),
            PennaButton(
              label: '合并',
              icon: Icons.merge_type,
              borderColor: PennaColors.border,
              tooltip: '去掉分段,合成一整段文字',
              onPressed:
                  vm.pending == null &&
                      vm.blocks.any(
                        (b) => !b.pinned && sectionSpans(b.text).isNotEmpty,
                      )
                  ? vm.unsection
                  : null,
            ),
            const SizedBox(width: 6),
            PennaButton(
              label: _zhOpen ? '收起' : '展开',
              icon: _zhOpen ? Icons.unfold_less : Icons.unfold_more,
              borderColor: PennaColors.border,
              tooltip: '展开或收起每一段的中文',
              onPressed: vm.body.contains(zhMark)
                  ? () => setState(() => _zhOpen = !_zhOpen)
                  : null,
            ),
          ],
        ),
        Expanded(
          child: ColoredBox(
            color: PennaColors.editorBg,
            child: SmoothScroller(
              builder: (controller) => ListView(
                controller: controller,
                padding: const EdgeInsets.all(14),
                children: [
                  BodyCard(
                    // 换页就是换了一份成稿:各段展开没展开、光标在哪都重新算。
                    key: ValueKey(vm.pageIndex),
                    vm: vm,
                    zhOpen: _zhOpen,
                    onCopied: vm.recordPrompt,
                    onDiscuss: onDiscuss,
                    // 和顶栏的润色是同一套,只是范围先定在这一段上。
                    onPolish: vm.isPolishing
                        ? null
                        : (start, end) =>
                              _polish(context, section: (start, end)),
                    onTranslateSelection: () =>
                        _translate(context, selection: true),
                    onTranslate: (section, text) async {
                      final problem = await vm.translateSection(section, text);
                      if (problem != null && context.mounted) {
                        showToast(context, problem, warn: true);
                      }
                    },
                  ),
                  if (vm.translation != null) ...[
                    const SizedBox(height: 10),
                    PopIn(
                      child: _TranslationCard(
                        text: vm.translation!,
                        engine: vm.translationBy,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// 顶栏里「Diff 待合并」和两个计数至少各要这么宽才画得完整。
const _chipRoom = 100.0;
const _statsRoom = 190.0;

class _PendingChip extends StatelessWidget {
  const _PendingChip({required this.more});

  /// 这一处后面还排着几处。
  final int more;

  @override
  Widget build(BuildContext context) {
    return PennaCard(
      color: PennaColors.lock,
      borderColor: PennaColors.lockBorder,
      radius: 99,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      child: Text(
        more == 0 ? 'Diff 待合并' : 'Diff 待合并 · 后面还有 $more 处',
        overflow: TextOverflow.ellipsis,
        style: monoStyle.copyWith(fontSize: 11, color: PennaColors.lockText),
      ),
    );
  }
}

class _TranslationCard extends StatelessWidget {
  const _TranslationCard({required this.text, required this.engine});

  final String text;

  /// 译文出自哪个引擎。
  final String? engine;

  @override
  Widget build(BuildContext context) {
    return PennaCard(
      color: PennaColors.primaryBg,
      borderColor: PennaColors.primaryBorder,
      radius: 6,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.translate, size: 13, color: PennaColors.primary),
              const SizedBox(width: 4),
              Text(
                engine == null ? '中文对照' : '中文对照 · $engine',
                style: draftLabelStyle,
              ),
            ],
          ),
          const SizedBox(height: 4),
          SelectableText(
            contextMenuBuilder: pennaTextMenu,
            text,
            style: const TextStyle(
              fontSize: 12,
              height: 1.5,
              color: PennaColors.slate700,
            ),
          ),
        ],
      ),
    );
  }
}

class _SummarySection extends StatefulWidget {
  const _SummarySection({
    required this.vm,
    required this.reverse,
    this.onSendToAgent,
  });

  final StudioViewModel vm;
  final ReverseModel reverse;
  final ValueChanged<String>? onSendToAgent;

  @override
  State<_SummarySection> createState() => _SummarySectionState();
}

class _SummarySectionState extends State<_SummarySection> {
  /// 现在看的是「图像反推」而不是「成稿汇总」。
  bool _reversing = false;

  StudioViewModel get vm => widget.vm;

  @override
  Widget build(BuildContext context) {
    final prompt = vm.finalPrompt;
    return Column(
      children: [
        const Divider(height: 1),
        PennaBar(
          children: [
            _Tab(
              icon: Icons.inventory_2_outlined,
              label: '成稿汇总',
              selected: !_reversing,
              onTap: () => setState(() => _reversing = false),
            ),
            const SizedBox(width: 6),
            _Tab(
              icon: Icons.image_search,
              label: '图像反推',
              selected: _reversing,
              onTap: () => setState(() => _reversing = true),
            ),
          ],
        ),
        Expanded(
          child: ColoredBox(
            color: PennaColors.editorBg,
            child: _reversing
                ? ReversePane(
                    model: widget.reverse,
                    onSend: widget.onSendToAgent,
                  )
                : prompt.isEmpty && vm.tags.isEmpty && vm.promptLog.isEmpty
                ? const Center(
                    child: Text(
                      '暂无内容',
                      style: TextStyle(
                        fontSize: 12,
                        color: PennaColors.slate400,
                      ),
                    ),
                  )
                : SmoothScroller(
                    builder: (controller) => ListView(
                      controller: controller,
                      padding: const EdgeInsets.all(14),
                      children: [
                        if (vm.tags.isNotEmpty) ...[
                          _CopyCard(
                            icon: Icons.sell_outlined,
                            iconColor: PennaColors.amber,
                            title: 'Danbooru 风格 Tag 汇总',
                            text: vm.tags,
                            toast: '已复制全部 Tag',
                          ),
                          const SizedBox(height: 12),
                        ],
                        if (prompt.isNotEmpty)
                          _CopyCard(
                            icon: Icons.verified_outlined,
                            iconColor: PennaColors.accent,
                            title: vm.pages.length > 1
                                ? '最终提示词 · ${vm.seriesName(vm.series)}'
                                      ' · 第 ${vm.pageNumber(vm.pageIndex)} 页'
                                : '最终提示词',
                            text: prompt,
                            toast: '已复制',
                            onCopied: vm.recordPrompt,
                          ),
                        if (vm.promptLog.isNotEmpty) ...[
                          const SizedBox(height: 14),
                          const Text('历史提示词', style: draftLabelStyle),
                          for (final record in vm.promptLog) ...[
                            const SizedBox(height: 8),
                            _HistoryCard(
                              key: ObjectKey(record),
                              vm: vm,
                              record: record,
                            ),
                          ],
                        ],
                      ],
                    ),
                  ),
          ),
        ),
      ],
    );
  }
}

/// 下半区顶上的一个页签。
class _Tab extends StatelessWidget {
  const _Tab({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = selected ? PennaColors.primary : PennaColors.slate500;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: selected ? PennaColors.card : PennaColors.slate50,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: selected ? PennaColors.border : PennaColors.slate50,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 14, color: color),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: selected ? PennaColors.text : color,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 历史提示词收起时最多显示几行。
const _historyLines = 3;

/// 历史提示词里的一条:当时的成稿,可以放回工作区或复制;长的可以展开看全。
class _HistoryCard extends StatefulWidget {
  const _HistoryCard({super.key, required this.vm, required this.record});

  final StudioViewModel vm;
  final PromptRecord record;

  @override
  State<_HistoryCard> createState() => _HistoryCardState();
}

class _HistoryCardState extends State<_HistoryCard> {
  bool _open = false;

  StudioViewModel get vm => widget.vm;
  PromptRecord get record => widget.record;

  @override
  Widget build(BuildContext context) {
    // 复制和预览都用干净的提示词:标注和中文对照不带。
    final clean = stripSectionLabels(record.text);
    return PennaCard(
      padding: const EdgeInsets.fromLTRB(10, 6, 6, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  shortTime(record.time),
                  style: const TextStyle(
                    fontSize: 11,
                    color: PennaColors.slate400,
                  ),
                ),
              ),
              PennaButton(
                label: '放回成稿',
                icon: Icons.keyboard_double_arrow_up,
                onPressed: () {
                  final problem = vm.restorePrompt(record);
                  if (problem != null) showToast(context, problem, warn: true);
                },
              ),
              PennaButton(
                label: '复制这条',
                icon: Icons.content_copy,
                onPressed: () => copyWithToast(context, clean, '已复制'),
              ),
              IconButton(
                tooltip: '删除这条',
                iconSize: 14,
                visualDensity: VisualDensity.compact,
                color: PennaColors.slate400,
                icon: const Icon(Icons.close),
                onPressed: () => vm.deletePrompt(record),
              ),
            ],
          ),
          LayoutBuilder(
            builder: (context, box) {
              final style = monoStyle.copyWith(fontSize: 11.5);
              // 收起时放得下就不用「展开」按钮。
              final long = (TextPainter(
                text: TextSpan(text: clean, style: style),
                maxLines: _historyLines,
                textDirection: TextDirection.ltr,
              )..layout(maxWidth: box.maxWidth)).didExceedMaxLines;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  AnimatedSize(
                    duration: const Duration(milliseconds: 160),
                    curve: Curves.easeOut,
                    alignment: Alignment.topLeft,
                    child: Text(
                      clean,
                      maxLines: _open ? null : _historyLines,
                      overflow: _open ? null : TextOverflow.ellipsis,
                      style: style,
                    ),
                  ),
                  if (long)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: PennaButton(
                        label: _open ? '收起' : '展开',
                        icon: _open ? Icons.expand_less : Icons.expand_more,
                        background: Colors.transparent,
                        foreground: PennaColors.slate500,
                        onPressed: () => setState(() => _open = !_open),
                      ),
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _CopyCard extends StatelessWidget {
  const _CopyCard({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.text,
    required this.toast,
    this.onCopied,
  });

  /// 点了复制之后顺带做的事(记进历史提示词)。
  final VoidCallback? onCopied;

  final IconData icon;
  final Color iconColor;
  final String title;
  final String text;
  final String toast;

  @override
  Widget build(BuildContext context) {
    return PennaCard(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(icon, size: 14, color: iconColor),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  title,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              PennaButton(
                label: '一键复制',
                icon: Icons.content_copy,
                background: PennaColors.primaryBg,
                foreground: PennaColors.primary,
                borderColor: PennaColors.primaryBorder,
                onPressed: () {
                  onCopied?.call();
                  copyWithToast(context, text, toast);
                },
              ),
            ],
          ),
          const SizedBox(height: 8),
          PennaCard(
            color: PennaColors.slate50,
            radius: 4,
            child: SelectableText(
              contextMenuBuilder: pennaTextMenu,
              text,
              style: monoStyle.copyWith(fontSize: 11.5),
            ),
          ),
        ],
      ),
    );
  }
}
