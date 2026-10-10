import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../settings/settings_sections.dart';
import 'studio_view_model.dart';

typedef _Tint = ({Color bg, Color border, Color text});

/// 系列外框的配色,按系列出现的先后轮着用。
const _seriesTints = <_Tint>[
  (bg: Color(0xFFEEF2FF), border: Color(0xFFC7D2FE), text: Color(0xFF4338CA)),
  (bg: Color(0xFFF0FDFA), border: Color(0xFF99F6E4), text: Color(0xFF0F766E)),
  (bg: Color(0xFFFFF1F2), border: Color(0xFFFECDD3), text: Color(0xFFBE123C)),
  (bg: Color(0xFFF0F9FF), border: Color(0xFFBAE6FD), text: Color(0xFF0369A1)),
  (bg: Color(0xFFFAF5FF), border: Color(0xFFE9D5FF), text: Color(0xFF7E22CE)),
];

/// 问用户要一个名字。点「确定」返回文字(可以是空串),取消返回 null。
Future<String?> _askName(BuildContext context, String title, String initial) {
  var text = initial;
  return showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title, style: const TextStyle(fontSize: 16)),
      content: SizedBox(
        width: 320,
        child: PennaField(
          label: '名字',
          hint: '留空就用默认的',
          value: initial,
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
          child: const Text('确定'),
        ),
      ],
    ),
  );
}

/// 在鼠标的位置弹一个小菜单,返回选中的那一项。
Future<String?> _menu(BuildContext context, Offset at, List<String> items) {
  return showMenu<String>(
    context: context,
    position: RelativeRect.fromLTRB(at.dx, at.dy, at.dx, at.dy),
    items: [
      for (final item in items)
        PopupMenuItem(
          value: item,
          height: 34,
          child: Text(item, style: const TextStyle(fontSize: 13)),
        ),
    ],
  );
}

/// 成稿正文上方的页签:每个系列一个彩色框,框里先是系列的名字,再是它的各页
/// (页码每个系列都从 1 数)。右键改名或删除,按住页签可以在系列里拖着调顺序。
class PageStrip extends StatelessWidget {
  const PageStrip({super.key, required this.vm});

  final StudioViewModel vm;

  void _do(BuildContext context, String? problem) {
    if (problem != null) showToast(context, problem, warn: true);
  }

  Future<void> _pageMenu(BuildContext context, Offset at, int i) async {
    final picked = await _menu(context, at, const [
      '改名',
      '脱离系列',
      '建立系列',
      '删除这一页',
      '删除整个系列',
    ]);
    if (!context.mounted || picked == null) return;
    final page = vm.pages[i];
    if (picked == '脱离系列') return _do(context, vm.detachPage(i));
    if (picked == '建立系列') return _do(context, vm.addPage(newSeries: true));
    if (picked == '删除整个系列') return _removeSeries(context, page.series);
    if (picked == '改名') {
      final name = await _askName(
        context,
        '第 ${vm.pageNumber(i)} 页的名字',
        page.name,
      );
      if (name != null) vm.renamePage(i, name);
      return;
    }
    final empty =
        page.pending == null && page.blocks.every((b) => b.text.trim().isEmpty);
    if (!empty &&
        !await confirmDelete(
          context,
          '删除第 ${vm.pageNumber(i)} 页?',
          '这一页的成稿会一起删掉。',
        )) {
      return;
    }
    if (context.mounted) _do(context, vm.removePage(i));
  }

  Future<void> _seriesMenu(BuildContext context, Offset at, int series) async {
    final picked = await _menu(context, at, const ['改名', '删除整个系列']);
    if (!context.mounted || picked == null) return;
    if (picked == '改名') {
      final next = await _askName(context, '系列的名字', vm.seriesName(series));
      if (next != null) vm.renameSeries(series, next);
      return;
    }
    await _removeSeries(context, series);
  }

  /// 删掉整个系列,先问一句。
  Future<void> _removeSeries(BuildContext context, int series) async {
    final name = vm.seriesName(series);
    if (!await confirmDelete(context, '删除「$name」?', '这个系列的每一页都会删掉,对话收进历史。')) {
      return;
    }
    if (context.mounted) _do(context, vm.removeSeries(series));
  }

  @override
  Widget build(BuildContext context) {
    final pages = vm.pages;
    final full = pages.length >= StudioPages.maxPages;
    // 同系列的页挨在一起,所以顺着数就能分出组来。
    final groups = <List<int>>[];
    for (final (i, p) in pages.indexed) {
      if (i > 0 && pages[i - 1].series == p.series) {
        groups.last.add(i);
      } else {
        groups.add([i]);
      }
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.only(top: 7, right: 10),
          child: Text(
            '成稿正文',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: PennaColors.slate500,
            ),
          ),
        ),
        Expanded(
          // 页多了自己折行,不会挤出去。
          child: Wrap(
            spacing: 8,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              for (final (g, group) in groups.indexed)
                _SeriesFrame(
                  tint: _seriesTints[g % _seriesTints.length],
                  // 眼前这个系列的框描深一点。
                  current: pages[group.first].series == vm.series,
                  children: [
                    _SeriesLabel(
                      name: vm.seriesName(pages[group.first].series),
                      tint: _seriesTints[g % _seriesTints.length],
                      onMenu: (at) =>
                          _seriesMenu(context, at, pages[group.first].series),
                    ),
                    for (final i in group)
                      _PageChip(
                        index: i,
                        number: vm.pageNumber(i),
                        name: pages[i].name,
                        tint: _seriesTints[g % _seriesTints.length],
                        selected: i == vm.pageIndex,
                        waiting: pages[i].pending != null,
                        // 只收同一个系列里拖过来的。
                        accepts: (from) =>
                            from != i && pages[from].series == pages[i].series,
                        onTap: () => _do(context, vm.openPage(i)),
                        onMenu: (at) => _pageMenu(context, at, i),
                        onDrop: (from) => _do(context, vm.movePage(from, i)),
                      ),
                    _IconChip(
                      icon: Icons.add,
                      tip: '在这个系列里加一页',
                      color: _seriesTints[g % _seriesTints.length].text,
                      onTap: full
                          ? null
                          : () => _do(
                              context,
                              vm.addPage(toSeries: pages[group.first].series),
                            ),
                    ),
                  ],
                ),
              Tooltip(
                message: '另起一个系列,对话和别的系列分开',
                child: PennaButton(
                  label: '新系列',
                  icon: Icons.add,
                  borderColor: PennaColors.border,
                  onPressed: full
                      ? null
                      : () => _do(context, vm.addPage(newSeries: true)),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// 把同一个系列的页框在一起的彩色框。
class _SeriesFrame extends StatelessWidget {
  const _SeriesFrame({
    required this.tint,
    required this.current,
    required this.children,
  });

  final _Tint tint;
  final bool current;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 160),
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: tint.bg,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: current ? tint.text : tint.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final (i, child) in children.indexed) ...[
            if (i > 0) const SizedBox(width: 4),
            child,
          ],
        ],
      ),
    );
  }
}

/// 框里最前面的系列名;右键改名或删掉整个系列。
class _SeriesLabel extends StatelessWidget {
  const _SeriesLabel({
    required this.name,
    required this.tint,
    required this.onMenu,
  });

  final String name;
  final _Tint tint;
  final ValueChanged<Offset> onMenu;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: '右键改名或删除',
      waitDuration: const Duration(milliseconds: 600),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onSecondaryTapDown: (d) => onMenu(d.globalPosition),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 5),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 120),
            child: Text(
              name,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
                color: tint.text,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 一页的页签:点一下换页,右键改名或删除,按住拖到同系列的另一页上调顺序。
/// [waiting] 表示这页有待确认的改动,右上角亮一个小点。
class _PageChip extends StatelessWidget {
  const _PageChip({
    required this.index,
    required this.number,
    required this.name,
    required this.tint,
    required this.selected,
    required this.waiting,
    required this.accepts,
    required this.onTap,
    required this.onMenu,
    required this.onDrop,
  });

  /// 这页在全部页里排第几,拖动时带着它。
  final int index;

  /// 这页是它那个系列里的第几页。
  final int number;
  final String name;
  final _Tint tint;
  final bool selected;
  final bool waiting;
  final bool Function(int from) accepts;
  final VoidCallback onTap;
  final ValueChanged<Offset> onMenu;
  final ValueChanged<int> onDrop;

  Widget _face({required bool hovered}) {
    final label = name.isEmpty ? '$number' : '$number $name';
    return AnimatedContainer(
      duration: const Duration(milliseconds: 160),
      height: 22,
      constraints: const BoxConstraints(minWidth: 26, maxWidth: 110),
      padding: const EdgeInsets.symmetric(horizontal: 7),
      decoration: BoxDecoration(
        color: selected ? tint.text : PennaColors.card,
        borderRadius: BorderRadius.circular(5),
        border: Border.all(
          color: hovered || selected ? tint.text : tint.border,
          width: hovered ? 2 : 1,
        ),
      ),
      // 宽度跟着字走(不写 widthFactor 会把页签撑到最宽)。
      child: Center(
        widthFactor: 1,
        child: Text(
          label,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 11.5,
            fontWeight: FontWeight.w700,
            color: selected ? Colors.white : tint.text,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return DragTarget<int>(
      onWillAcceptWithDetails: (d) => accepts(d.data),
      onAcceptWithDetails: (d) => onDrop(d.data),
      builder: (context, incoming, _) => LongPressDraggable<int>(
        data: index,
        delay: const Duration(milliseconds: 250),
        feedback: Material(
          color: Colors.transparent,
          elevation: 6,
          borderRadius: BorderRadius.circular(5),
          child: _face(hovered: false),
        ),
        childWhenDragging: Opacity(opacity: 0.35, child: _face(hovered: false)),
        child: Tooltip(
          message: [
            '第 $number 页',
            if (name.isNotEmpty) name,
            if (waiting) '有待确认的改动',
          ].join(' · '),
          waitDuration: const Duration(milliseconds: 600),
          child: GestureDetector(
            onTap: onTap,
            onSecondaryTapDown: (d) => onMenu(d.globalPosition),
            child: MouseRegion(
              cursor: SystemMouseCursors.click,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  _face(hovered: incoming.isNotEmpty),
                  if (waiting)
                    const Positioned(
                      top: -2,
                      right: -2,
                      child: CircleAvatar(
                        radius: 3.5,
                        backgroundColor: PennaColors.amber,
                      ),
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

/// 页签条上的小图标按钮;[onTap] 为 null 时是灰的。
class _IconChip extends StatelessWidget {
  const _IconChip({
    required this.icon,
    required this.tip,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String tip;
  final Color color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(5),
        child: SizedBox(
          width: 22,
          height: 22,
          child: Icon(
            icon,
            size: 15,
            color: onTap == null ? PennaColors.slate400 : color,
          ),
        ),
      ),
    );
  }
}
