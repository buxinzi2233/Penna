import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/harness/attachment.dart';
import '../../../core/harness/layout.dart';
import '../../../data/services/archive_store.dart';
import '../../../data/services/config_service.dart';
import '../../core/scroll_strip.dart';
import '../../core/smooth_scroll.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../archive/archive_page.dart';
import '../settings/settings_sections.dart';
import '../studio/chat_pane.dart';
import '../studio/studio_view_model.dart';
import 'layout_board.dart';
import 'layout_canvas.dart';
import 'layout_json_view.dart';
import '../../../l10n/l10n.dart';

part 'layout_props.dart';

const _propsWidth = 340.0;
const _chatWidth = 420.0;

/// 顶栏存的画布尺寸最多露出几个,多的横着滚。
const _maxSizes = 4;

/// 区域控制工作台:左边写各块的属性,中间在画布上画框,右边和布局 Agent 对话,
/// 得到 MOSS-Image 的布局 JSON。能存进档案库的「区域控制」分区。
class LayoutPage extends StatefulWidget {
  const LayoutPage({
    super.key,
    required this.board,
    required this.vm,
    required this.chat,
    required this.config,
    required this.archive,
    required this.onOpenStudio,
    required this.onOpenSettings,
  });

  final LayoutBoard board;

  /// 「保存」存进它的「区域控制」分区。
  final ArchiveStore archive;

  /// 工作台:「放到成稿」放进它当前那一页。
  final StudioViewModel vm;

  /// 布局页自己那场对话(`layoutOnly`):和工作台的是两场,界面一样。
  final StudioViewModel chat;
  final ConfigService config;
  final VoidCallback onOpenStudio;
  final VoidCallback onOpenSettings;

  @override
  State<LayoutPage> createState() => _LayoutPageState();
}

class _LayoutPageState extends State<LayoutPage> {
  final _input = TextEditingController();
  final _inputFocus = FocusNode();

  /// 各块在属性栏里的卡片和正文输入框,按第几块记。
  final _cards = <int, GlobalKey>{};
  final _fields = <int, FocusNode>{};

  LayoutBoard get board => widget.board;

  GlobalKey _cardKey(int i) => _cards.putIfAbsent(i, GlobalKey.new);
  FocusNode _fieldFocus(int i) => _fields.putIfAbsent(i, FocusNode.new);

  @override
  void dispose() {
    _input.dispose();
    _inputFocus.dispose();
    for (final f in _fields.values) {
      f.dispose();
    }
    super.dispose();
  }

  /// 图层面板里展开着的几块(按第几块记);默认都折叠。
  var _open = <int>{};

  void _toggle(int i) => setState(
    () => _open = _open.contains(i) ? ({..._open}..remove(i)) : {..._open, i},
  );

  /// 拖着换前后。序号都变了,展开状态只留给挪动的那一块(它展开着的话)。
  void _move(int from, int to) {
    final wasOpen = _open.contains(from);
    board.move(from, to);
    setState(() => _open = {if (wasOpen) ?board.selected});
  }

  /// 删掉一块:后面的序号往前挪一个,展开状态跟着挪。
  void _delete(int i) {
    board.removeBox(i);
    setState(
      () => _open = {
        for (final j in _open)
          if (j != i) j > i ? j - 1 : j,
      },
    );
  }

  /// 画布上点了第 [i] 块:属性栏滚到它那张卡片;[edit] 时展开它并把光标放进正文。
  void _reveal(int i, {bool edit = false}) {
    if (edit && !_open.contains(i)) setState(() => _open = {..._open, i});
    // 等这一帧建好(刚画出来的框还没有卡片,刚展开的还没有输入框)。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final card = _cards[i]?.currentContext;
      if (card == null || !card.mounted) return;
      Scrollable.ensureVisible(
        card,
        duration: const Duration(milliseconds: 200),
        alignment: 0.05,
      );
      if (edit) _fields[i]?.requestFocus();
    });
  }

  void _toDraft() {
    final problem = widget.vm.restorePrompt((
      time: DateTime.now(),
      text: board.json,
    ), title: tr('区域控制'));
    if (problem != null) return showToast(context, problem, warn: true);
    widget.onOpenStudio();
  }

  void _ask() {
    final problem = widget.chat.send(tr('照布局画板完善整体描述和每个框的描述,框的位置不动'));
    if (problem != null) showToast(context, problem, warn: true);
  }

  /// 对话里放进一张参考图:它和画布一横一竖时,问一句要不要把画布对调
  /// (开了自动审批就直接换)。
  Future<void> _matchImage(Attachment image) async {
    final to = await board.swapFor(image.bytes!);
    if (to == null || !mounted) return;
    final size = '${to.width}×${to.height}';
    if (!widget.config.config.autoApprove &&
        !await confirmDelete(
          context,
          to.width > to.height ? tr('参考图是横构图') : tr('参考图是竖构图'),
          tr('画布换成 {0}?', [size]),
          action: tr('换'),
        )) {
      return;
    }
    board.swap();
    if (mounted) showToast(context, tr('画布已换成 {0}', [size]));
  }

  /// 带着这一块去对话里:输入框上方出现它,接着打字说怎么改。
  void _discuss(int i) {
    final b = board.layout.boxes[i];
    final name = b.name.trim().isEmpty ? tr('第 {0} 块', [i + 1]) : b.name.trim();
    widget.chat.quoteSection(
      '【$name】${b.label} · x ${b.left} y ${b.top} · '
      '${b.width}×${b.height}\n${b.caption.trim()}',
    );
    _inputFocus.requestFocus();
  }

  /// 快捷操作:接在输入框已有的话后面,不替换。
  void _appendInput(String text) {
    final had = _input.text.trimRight();
    final next = had.isEmpty ? text : '$had $text';
    _input.value = TextEditingValue(
      text: next,
      selection: TextSelection.collapsed(offset: next.length),
    );
    _inputFocus.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final side = BorderSide(color: PennaColors.border);
    return ListenableBuilder(
      listenable: board,
      builder: (context, _) => ColoredBox(
        color: PennaColors.editorBg,
        child: Column(
          children: [
            _TopBar(board: board, archive: widget.archive),
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(
                    width: _propsWidth,
                    decoration: BoxDecoration(
                      color: PennaColors.bg,
                      border: Border(right: side),
                    ),
                    child: _Properties(
                      board: board,
                      onDiscuss: _discuss,
                      onToDraft: _toDraft,
                      onAsk: _ask,
                      cardKey: _cardKey,
                      fieldFocus: _fieldFocus,
                      isOpen: _open.contains,
                      onToggle: _toggle,
                      onMove: _move,
                      onDelete: _delete,
                    ),
                  ),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: LayoutCanvas(
                        board: board,
                        onPick: _reveal,
                        onEdit: (i) => _reveal(i, edit: true),
                      ),
                    ),
                  ),
                  Container(
                    width: _chatWidth,
                    decoration: BoxDecoration(border: Border(left: side)),
                    child: ListenableBuilder(
                      listenable: Listenable.merge([
                        widget.chat,
                        widget.config,
                      ]),
                      builder: (context, _) => ChatPane(
                        vm: widget.chat,
                        config: widget.config,
                        input: _input,
                        inputFocus: _inputFocus,
                        onQuickAction: _appendInput,
                        onOpenSettings: widget.onOpenSettings,
                        onImage: _matchImage,
                      ),
                    ),
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

class _TopBar extends StatelessWidget {
  const _TopBar({required this.board, required this.archive});

  final LayoutBoard board;
  final ArchiveStore archive;

  /// 把整张布局(连同画布尺寸和各块的名字)存进档案库的「区域控制」分区。
  Future<void> _save(BuildContext context) async {
    final picked = await showSaveDialog(
      context,
      archive.categoriesOf(archiveLayout),
    );
    if (picked == null) return;
    archive.add(
      text: jsonEncode(board.layout.toJson()),
      title: picked.title,
      category: picked.category,
      kind: archiveLayout,
    );
    if (context.mounted) showToast(context, tr('已存进档案库'));
  }

  @override
  Widget build(BuildContext context) {
    final l = board.layout;
    void resize(int? w, int? h) {
      if (!board.setSize(w ?? l.width, h ?? l.height)) {
        showToast(
          context,
          tr('边长要在 {0} 到 {1} 之间', [minLayoutSide, maxLayoutSide]),
          warn: true,
        );
      }
    }

    return PennaBar(
      color: PennaColors.card,
      children: [
        Icon(Icons.crop_free, size: 15, color: PennaColors.primary),
        const SizedBox(width: 6),
        Text(
          tr('区域控制工作台'),
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
        ),
        const SizedBox(width: 16),
        _SideField(
          value: l.width,
          tooltip: tr('宽'),
          onSubmit: (v) => resize(v, null),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Text('×', style: TextStyle(color: PennaColors.slate500)),
        ),
        _SideField(
          value: l.height,
          tooltip: tr('高'),
          onSubmit: (v) => resize(null, v),
        ),
        IconButton(
          tooltip: tr('横竖对调'),
          iconSize: 16,
          visualDensity: VisualDensity.compact,
          icon: const Icon(Icons.swap_horiz),
          onPressed: board.swap,
        ),
        IconButton(
          tooltip: tr('存下这个尺寸'),
          iconSize: 16,
          visualDensity: VisualDensity.compact,
          icon: const Icon(Icons.bookmark_add_outlined),
          onPressed: board.saveSize,
        ),
        const SizedBox(width: 4),
        _PerspectiveButton(board: board),
        const SizedBox(width: 6),
        Expanded(
          child: Align(
            alignment: Alignment.centerLeft,
            child: ScrollStrip(
              visible: _maxSizes,
              children: [
                for (final s in board.sizes)
                  Tooltip(
                    message: tr('右键删除'),
                    child: GestureDetector(
                      onSecondaryTap: () => board.removeSize(s),
                      child: PennaChip(
                        label: '${s.width}×${s.height}',
                        selected: s.width == l.width && s.height == l.height,
                        onTap: () => board.setSize(s.width, s.height),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 6),
        PennaButton(
          label: tr('保存'),
          icon: Icons.save_outlined,
          borderColor: PennaColors.border,
          onPressed: l.isEmpty ? null : () => _save(context),
        ),
        const SizedBox(width: 4),
        IconButton(
          tooltip: tr('清空'),
          iconSize: 16,
          visualDensity: VisualDensity.compact,
          icon: const Icon(Icons.delete_sweep_outlined),
          onPressed: l.isEmpty
              ? null
              : () async {
                  if (await confirmDelete(
                    context,
                    tr('清空区域控制?'),
                    tr('框和描述都会清掉,画布尺寸留着。'),
                  )) {
                    board.clear();
                  }
                },
        ),
      ],
    );
  }
}

/// 透视辅助的开关:点开选一点、两点、三点透视,或关掉。默认关。
class _PerspectiveButton extends StatelessWidget {
  const _PerspectiveButton({required this.board});

  final LayoutBoard board;

  @override
  Widget build(BuildContext context) {
    final on = board.layout.perspective;
    final names = {1: tr('一点透视'), 2: tr('两点透视'), 3: tr('三点透视')};
    return PopupMenuButton<int>(
      tooltip: tr('透视辅助'),
      position: PopupMenuPosition.under,
      onSelected: (n) => board.setPerspective(n == 0 ? null : n),
      itemBuilder: (_) => [
        for (final MapEntry(key: n, value: name) in names.entries)
          CheckedPopupMenuItem(
            value: n,
            checked: on?.points == n,
            height: 34,
            child: Text(name, style: const TextStyle(fontSize: 12.5)),
          ),
        if (on != null) ...[
          const PopupMenuDivider(height: 8),
          PopupMenuItem(
            value: 0,
            height: 34,
            child: Text(tr('关闭'), style: const TextStyle(fontSize: 12.5)),
          ),
        ],
      ],
      child: PennaChip(
        label: on == null ? tr('透视') : names[on.points]!,
        selected: on != null,
        onTap: null,
      ),
    );
  }
}

/// 一条边长的输入框:回车或离开时才生效;外面改了尺寸(对调、点了存的尺寸)跟着变。
class _SideField extends StatefulWidget {
  const _SideField({
    required this.value,
    required this.tooltip,
    required this.onSubmit,
  });

  final int value;
  final String tooltip;
  final ValueChanged<int?> onSubmit;

  @override
  State<_SideField> createState() => _SideFieldState();
}

class _SideFieldState extends State<_SideField> {
  late final _controller = TextEditingController(text: '${widget.value}');
  final _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    _focus.addListener(() {
      if (!_focus.hasFocus) _submit();
    });
  }

  @override
  void didUpdateWidget(_SideField old) {
    super.didUpdateWidget(old);
    if (old.value != widget.value) _controller.text = '${widget.value}';
  }

  void _submit() {
    final v = int.tryParse(_controller.text.trim());
    if (v == widget.value) return;
    widget.onSubmit(v ?? 0);
    // 没换成(超出范围):把原来的数放回去。
    if (mounted) _controller.text = '${widget.value}';
  }

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(6),
      borderSide: BorderSide(color: PennaColors.border),
    );
    return Tooltip(
      message: widget.tooltip,
      child: SizedBox(
        width: 64,
        child: TextField(
          contextMenuBuilder: pennaTextMenu,
          controller: _controller,
          focusNode: _focus,
          textAlign: TextAlign.center,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          onSubmitted: (_) => _submit(),
          style: const TextStyle(fontSize: 12.5),
          decoration: InputDecoration(
            isDense: true,
            filled: true,
            fillColor: PennaColors.card,
            contentPadding: const EdgeInsets.symmetric(vertical: 7),
            border: border,
            enabledBorder: border,
          ),
        ),
      ),
    );
  }
}
