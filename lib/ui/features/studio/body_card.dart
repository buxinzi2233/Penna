import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../../../core/harness/draft_block.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import 'page_strip.dart';
import 'studio_view_model.dart';

part 'body_diff.dart';
part 'body_editor.dart';
part 'body_pins.dart';
part 'body_section_card.dart';

const draftLabelStyle = TextStyle(
  fontSize: 11,
  fontWeight: FontWeight.w600,
  color: PennaColors.slate500,
);

typedef _Tint = ({Color bg, Color border, Color text});

/// 拖着的是哪一栏(blocks 里的起始下标)的第几段。
typedef _SectionDrag = ({int part, int span});

/// 分段框的配色,按段的先后轮着用;避开琥珀色,那是固定区的。
const _sectionTints = <_Tint>[
  (bg: Color(0xFFEFF6FF), border: Color(0xFFBFDBFE), text: Color(0xFF1D4ED8)),
  (bg: Color(0xFFECFDF5), border: Color(0xFFA7F3D0), text: Color(0xFF047857)),
  (bg: Color(0xFFF5F3FF), border: Color(0xFFDDD6FE), text: Color(0xFF6D28D9)),
  (bg: Color(0xFFFFF1F2), border: Color(0xFFFECDD3), text: Color(0xFFBE123C)),
  (bg: Color(0xFFECFEFF), border: Color(0xFFA5F3FC), text: Color(0xFF0E7490)),
  (bg: Color(0xFFFDF4FF), border: Color(0xFFF5D0FE), text: Color(0xFFA21CAF)),
];

/// 没有标注的那段用的中性色。
const _Tint _plainTint = (
  bg: PennaColors.slate50,
  border: PennaColors.border,
  text: PennaColors.slate500,
);

/// 问用户要固定什么内容。点「添加」返回文字,取消返回 null。
Future<String?> showPinDialog(BuildContext context) {
  var text = '';
  return showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('添加固定区', style: TextStyle(fontSize: 16)),
      content: SizedBox(
        width: 420,
        child: PennaField(
          label: '固定内容',
          hint: '例如 masterpiece, best quality,',
          maxLines: 3,
          value: '',
          onChanged: (v) => text = v,
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, text),
          child: const Text('添加'),
        ),
      ],
    ),
  );
}

/// 成稿正文:平时是几栏可编辑文字和可拖动的固定区;
/// 有待确认改动时改为只读并显示 diff。
class BodyCard extends StatelessWidget {
  const BodyCard({
    super.key,
    required this.vm,
    this.onDiscuss,
    this.onPolish,
    this.onTranslate,
    this.onTranslateSelection,
    this.zhOpen = false,
    this.onCopied,
  });

  /// 右键菜单的「翻译选中的」。
  final VoidCallback? onTranslateSelection;

  /// 去掉 [text] 里的 [s] 这一段,连同它和邻段之间的那个换行。
  static String _without(String text, SectionSpan s) => s.end < text.length
      ? text.replaceRange(s.start, s.end + 1, '')
      : text.replaceRange(s.start > 0 ? s.start - 1 : 0, s.end, '');

  final StudioViewModel vm;

  /// 顶栏的「展开」开着:每一段的中文对照都展开。
  final bool zhOpen;

  /// 用户复制了某一段之后。
  final VoidCallback? onCopied;

  /// 用户点了某一段的「润色」;参数是那段提示词在成稿里的范围。
  final void Function(int start, int end)? onPolish;

  /// 用户点了某一段的「翻译」;参数是那段的全文(带标注)和其中的提示词。
  final void Function(String section, String text)? onTranslate;

  /// 用户点了某一段的「讨论」;参数是那段文字(带标注)。
  final ValueChanged<String>? onDiscuss;

  /// 一栏可编辑文字:里面有分段标注就一段一个彩色框,没有就是一个普通输入栏。
  /// [tintFrom] 是这栏第一段该用第几个颜色。
  List<Widget> _column(Part p, int partCount, int tintFrom) {
    _BodyEditor editor(
      String text,
      int at,
      int end,
      int minLines, {
      bool acceptPins = true,
      bool detach = false,
      VoidCallback? onEmpty,
    }) => _BodyEditor(
      body: text,
      minLines: minLines,
      acceptPins: acceptPins,
      onChanged: (t) => t.isEmpty && onEmpty != null
          ? onEmpty()
          : vm.setText(p.index, p.text.replaceRange(at, end, t)),
      onSelection: (range) => vm.bodySelection = range == null
          ? null
          : (p.offset + at + range.$1, p.offset + at + range.$2),
      onDropPin: (from, to) => vm.movePin(from, p.offset + at + to),
      // 选中一截文字后右键菜单里多出来的几项;「脱离」只有分段框里才有。
      selectionMenu: [
        ('固定选中的', Icons.push_pin_outlined, vm.pinSelection),
        if (onPolish != null)
          (
            '润色选中的',
            Icons.auto_fix_high,
            () {
              final range = vm.bodySelection;
              if (range != null) onPolish!(range.$1, range.$2);
            },
          ),
        if (onTranslateSelection != null)
          ('翻译选中的', Icons.translate, onTranslateSelection!),
        if (detach) ('脱离选中的', Icons.call_split, vm.detachSelection),
      ],
    );
    final spans = sectionSpans(p.text);
    if (spans.isEmpty) {
      return [
        const SizedBox(height: 6),
        editor(p.text, 0, p.text.length, partCount == 1 ? 6 : 1),
      ];
    }
    return [
      for (final (i, s) in spans.indexed) ...[
        const SizedBox(height: 6),
        // 固定区拖到一段上:插到这段前面。和上一段之间的换行留给这段。
        _DropSlot(
          onDrop: (from) =>
              vm.movePin(from, p.offset + s.start - (s.start > 0 ? 1 : 0)),
          // 同一栏里别的段拖到这段上:挪到这段的位置。
          section: (part: p.index, span: i),
          onDropSection: (from) => vm.moveSection(p.index, from, i),
          // 没有标注的(脱离了分段的)就是一栏普通文字,不画框;删空了这一处就没了。
          child: s.label.isEmpty
              ? editor(
                  p.text.substring(s.textStart, s.textEnd),
                  s.textStart,
                  s.textEnd,
                  1,
                  acceptPins: false,
                  onEmpty: () => vm.setText(p.index, _without(p.text, s)),
                )
              : _SectionCard(
                  leading: spans.length < 2
                      ? null
                      : _SectionHandle(
                          drag: (part: p.index, span: i),
                          label: s.label.isEmpty ? '未标注' : s.label,
                          tint: s.label.isEmpty
                              ? _plainTint
                              : _sectionTints[(tintFrom + i) %
                                    _sectionTints.length],
                        ),
                  label: s.label,
                  tint: s.label.isEmpty
                      ? _plainTint
                      : _sectionTints[(tintFrom + i) % _sectionTints.length],
                  zh: s.zh,
                  openAll: zhOpen,
                  copyText: p.text.substring(s.textStart, s.textEnd),
                  onCopied: onCopied,
                  quoted: vm.quote == p.text.substring(s.start, s.end),
                  onDiscuss: onDiscuss == null || s.textStart == s.textEnd
                      ? null
                      : () => onDiscuss!(p.text.substring(s.start, s.end)),
                  onDetach: s.textStart == s.textEnd
                      ? null
                      : () => vm.detachSection(p.index, i),
                  onPin: () => vm.pinSection(
                    p.offset + s.start,
                    p.offset + s.end,
                    p.text.substring(s.textStart, s.textEnd),
                  ),
                  onPolish: onPolish == null || s.textStart == s.textEnd
                      ? null
                      : () => onPolish!(
                          p.offset + s.textStart,
                          p.offset + s.textEnd,
                        ),
                  onTranslate:
                      onTranslate == null ||
                          s.textStart == s.textEnd ||
                          vm.isTranslating
                      ? null
                      : () => onTranslate!(
                          p.text.substring(s.start, s.end),
                          p.text.substring(s.textStart, s.textEnd),
                        ),
                  onRemove: () => vm.setText(p.index, _without(p.text, s)),
                  child: editor(
                    p.text.substring(s.textStart, s.textEnd),
                    s.textStart,
                    s.textEnd,
                    1,
                    acceptPins: false,
                    detach: true,
                  ),
                ),
        ),
      ],
    ];
  }

  /// 固定区。整段固定下来的还是原来那个分段框,只是罩上一层琥珀色、不能编辑;
  /// 别的是一条琥珀色的固定条。[tint] 是它该用第几个颜色,[live] 为假时不能拖也不能解除。
  Widget _pin(
    String text,
    int index,
    int offset,
    int tint, {
    bool live = true,
  }) {
    final s = text.startsWith('【') ? sectionSpans(text).firstOrNull : null;
    final onUnpin = live ? () => vm.unpin(index) : null;
    return _PinCard(
      text: s == null ? text : text.substring(s.textStart, s.textEnd),
      index: index,
      onUnpin: onUnpin,
      onDropPin: (from) => vm.movePin(from, offset),
      section: s == null
          ? null
          : _SectionCard(
              label: s.label,
              tint: _sectionTints[tint % _sectionTints.length],
              zh: s.zh,
              openAll: zhOpen,
              copyText: text.substring(s.textStart, s.textEnd),
              onCopied: onCopied,
              quoted: false,
              locked: true,
              onUnpin: onUnpin,
              child: Text(
                text.substring(s.textStart, s.textEnd),
                style: monoStyle,
              ),
            ),
    );
  }

  /// 只读的一段:有待确认改动时,没被改到的段照样是彩色框,只是不能编辑。
  Widget _readOnlySection(String text, SectionSpan s, int tint) => _SectionCard(
    label: s.label,
    tint: s.label.isEmpty
        ? _plainTint
        : _sectionTints[tint % _sectionTints.length],
    zh: s.zh,
    openAll: zhOpen,
    quoted: false,
    child: SelectableText(
      contextMenuBuilder: pennaTextMenu,
      text.substring(s.textStart, s.textEnd),
      style: monoStyle,
    ),
  );

  /// 不在改动范围里的一块文字,只读。返回它的组件和占了几个颜色。
  (List<Widget>, int) _readOnlyBlock(String text, int tintFrom) {
    final spans = sectionSpans(text);
    if (spans.isEmpty) {
      return (
        [
          const SizedBox(height: 6),
          SelectableText(
            contextMenuBuilder: pennaTextMenu,
            text,
            style: monoStyle,
          ),
        ],
        0,
      );
    }
    return (
      [
        for (final (i, s) in spans.indexed) ...[
          const SizedBox(height: 6),
          _readOnlySection(text, s, tintFrom + i),
        ],
      ],
      spans.length,
    );
  }

  /// 某一段自己的「采纳」「驳回」。
  List<Widget> _sectionActions(String label) => [
    PennaButton(
      label: '采纳',
      background: PennaColors.diffAdd,
      foreground: PennaColors.diffAddText,
      onPressed: () => vm.acceptSection(label),
    ),
    const SizedBox(width: 4),
    PennaButton(
      label: '驳回',
      background: PennaColors.diffDel,
      foreground: PennaColors.diffDelText,
      onPressed: () => vm.rejectSection(label),
    ),
  ];

  /// 待确认的那一块:按分段标注把改动前后对上,没变的段照常显示,
  /// 只有变了的段里出现红绿对比。返回组件和占了几个颜色。
  (List<Widget>, int) _pendingBlock(DiffProposal diff, int tintFrom) {
    final old = sectionSpans(diff.removed);
    final fresh = sectionSpans(diff.added);
    if (old.isEmpty && fresh.isEmpty) {
      return (
        [
          const SizedBox(height: 8),
          _DiffBlock(
            diff: diff,
            onAccept: vm.acceptDiff,
            onReject: vm.rejectDiff,
          ),
        ],
        0,
      );
    }
    // 先按改动前的顺序排,同标注的配成一对;改动后多出来的段接在最后。
    final unmatched = [...fresh];
    final pairs = <(SectionSpan?, SectionSpan?)>[
      for (final o in old)
        (
          o,
          switch (unmatched.indexWhere((n) => n.label == o.label)) {
            < 0 => null,
            final at => unmatched.removeAt(at),
          },
        ),
      for (final n in unmatched) (null, n),
    ];
    return (
      [
        const SizedBox(height: 8),
        _DiffHeader(
          diff: diff,
          onAccept: vm.acceptDiff,
          onReject: vm.rejectDiff,
          all: old.isNotEmpty,
        ),
        // 改动前是没分段的文字:整段算删掉。
        if (old.isEmpty && diff.removed.trim().isNotEmpty)
          ..._diffLines(diff.removed, ''),
        for (final (i, (before, after)) in pairs.indexed) ...[
          const SizedBox(height: 6),
          if (before != null &&
              after != null &&
              diff.removed.substring(before.start, before.end) ==
                  diff.added.substring(after.start, after.end))
            _readOnlySection(diff.added, after, tintFrom + i)
          else
            _SectionCard(
              label: (after ?? before)!.label,
              tint: (after ?? before)!.label.isEmpty
                  ? _plainTint
                  : _sectionTints[(tintFrom + i) % _sectionTints.length],
              zh: '',
              quoted: true,
              // 改动前就没分段时没法只换一段,只留上面总的那一对按钮。
              actions: old.isEmpty
                  ? const []
                  : _sectionActions((after ?? before)!.label),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: _diffLines(
                  before == null
                      ? ''
                      : diff.removed.substring(before.start, before.end),
                  after == null
                      ? ''
                      : diff.added.substring(after.start, after.end),
                  strip: '【${(after ?? before)!.label}】',
                ),
              ),
            ),
        ],
      ],
      pairs.length,
    );
  }

  @override
  Widget build(BuildContext context) {
    final pending = vm.pending;
    final parts = vm.parts;
    // 每一栏的第一段接着上一栏的颜色往下排,相邻两段不会撞色。
    var tint = 0;
    final columns = <Widget>[];
    if (pending == null) {
      for (final p in parts) {
        if (p.pinned) {
          columns
            ..add(const SizedBox(height: 6))
            ..add(_pin(p.text, p.index, p.offset, tint));
          if (p.text.startsWith('【')) tint++;
        } else {
          columns.addAll(_column(p, parts.length, tint));
          tint += sectionSpans(p.text).length;
        }
      }
      // 最下面留一条落点,固定区才拖得到最后。
      if (parts.any((p) => p.pinned)) {
        columns.add(
          _DropSlot(
            onDrop: (from) => vm.movePin(from, vm.body.length),
            child: const SizedBox(height: 14),
          ),
        );
      }
    } else {
      for (final (i, b) in vm.blocks.indexed) {
        if (b.pinned) {
          columns
            ..add(const SizedBox(height: 6))
            ..add(_pin(b.text, i, 0, tint, live: false));
          if (b.text.startsWith('【')) tint++;
          continue;
        }
        // 改动前后可能是空块(比如改的是开头或全文),不占位置。
        if (i != pending.segmentIndex && b.text.trim().isEmpty) continue;
        final (widgets, used) = i == pending.segmentIndex
            ? _pendingBlock(pending, tint)
            : _readOnlyBlock(b.text, tint);
        columns.addAll(widgets);
        tint += used;
      }
    }
    return PennaCard(
      radius: 6,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PageStrip(vm: vm),
          ...columns,
        ],
      ),
    );
  }
}
