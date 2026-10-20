part of 'layout_page.dart';

/// 左边一栏:顶上一直是交出去的 JSON(不跟着滚),下面是整体描述、各块的名字和描述。
class _Properties extends StatelessWidget {
  const _Properties({
    required this.board,
    required this.onDiscuss,
    required this.onToDraft,
    required this.onAsk,
    required this.cardKey,
    required this.fieldFocus,
  });

  final LayoutBoard board;

  /// 带着第几块去右边的对话里改。
  final ValueChanged<int> onDiscuss;
  final VoidCallback onToDraft;
  final VoidCallback onAsk;

  /// 第几块的卡片和它正文输入框的焦点:画布上点框、双击框时用。
  final GlobalKey Function(int) cardKey;
  final FocusNode Function(int) fieldFocus;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 0),
          child: _JsonCard(board: board, onToDraft: onToDraft, onAsk: onAsk),
        ),
        Expanded(
          // 不用 ListView:它不建看不见的卡片,画布上点了框就滚不过去。
          child: SmoothScroller(
            builder: (controller) => SingleChildScrollView(
              controller: controller,
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _SummaryCard(board: board),
                  for (final (i, _) in board.layout.boxes.indexed) ...[
                    const SizedBox(height: 10),
                    _BoxCard(
                      key: cardKey(i),
                      board: board,
                      index: i,
                      focus: fieldFocus(i),
                      onDiscuss: () => onDiscuss(i),
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

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.board});

  final LayoutBoard board;

  @override
  Widget build(BuildContext context) {
    final l = board.layout;
    final r = board.revision;
    return PennaCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PennaField(
            key: ValueKey('caption-$r'),
            label: tr('整体描述'),
            value: l.caption,
            maxLines: 4,
            hint: tr('画面整体的场景与风格'),
            onChanged: (v) => board.setSummary(caption: v),
          ),
          const SizedBox(height: 10),
          PennaField(
            key: ValueKey('meta-$r'),
            label: tr('类型'),
            value: l.meta,
            hint: 'poster, illustration',
            onChanged: (v) => board.setSummary(meta: v),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final c in layoutCanvases)
                PennaChip(
                  label: c,
                  selected: l.canvas == c,
                  onTap: () => board.setSummary(canvas: c),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _BoxCard extends StatelessWidget {
  const _BoxCard({
    super.key,
    required this.board,
    required this.index,
    required this.focus,
    required this.onDiscuss,
  });

  final LayoutBoard board;
  final int index;

  /// 正文输入框的焦点:文字块是「文字内容」,别的是「这一块的描述」。
  final FocusNode focus;
  final VoidCallback onDiscuss;

  /// 输入框里改的是这一块最新的样子,不是画这张卡片时的。
  void _edit(LayoutBox Function(LayoutBox) change) =>
      board.updateBox(index, change(board.layout.boxes[index]));

  @override
  Widget build(BuildContext context) {
    final b = board.layout.boxes[index];
    final r = board.revision;
    final selected = board.selected == index;
    final color = layoutBoxColor(index);
    return GestureDetector(
      onTap: () => board.select(index),
      child: PennaCard(
        borderColor: selected ? color : null,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  color: color,
                  child: Text(
                    '${index + 1}',
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                for (final label in layoutLabels) ...[
                  PennaChip(
                    label: layoutLabelName(label),
                    selected: b.label == label,
                    onTap: () => _edit((b) => b.copyWith(label: label)),
                  ),
                  const SizedBox(width: 4),
                ],
                const Spacer(),
                IconButton(
                  tooltip: tr('讨论'),
                  iconSize: 16,
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.chat_bubble_outline),
                  onPressed: onDiscuss,
                ),
                IconButton(
                  tooltip: tr('删除'),
                  iconSize: 16,
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.close),
                  onPressed: () => board.removeBox(index),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                for (final layer in layoutLayers.reversed) ...[
                  PennaChip(
                    label: layoutLayerName(layer),
                    selected: b.layer == layer,
                    onTap: () => _edit((b) => b.copyWith(layer: layer)),
                  ),
                  const SizedBox(width: 4),
                ],
              ],
            ),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Text(
                'x ${b.left}  y ${b.top}  ·  ${b.width}×${b.height}',
                style: TextStyle(fontSize: 11, color: PennaColors.slate500),
              ),
            ),
            PennaField(
              key: ValueKey('name-$r-$index'),
              label: tr('名字'),
              value: b.name,
              hint: tr('例如 主角、标题、背景山'),
              onChanged: (v) => _edit((b) => b.copyWith(name: v)),
            ),
            const SizedBox(height: 8),
            if (b.label == 'text') ...[
              PennaField(
                key: ValueKey('text-$r-$index'),
                label: tr('文字内容'),
                value: b.text,
                focusNode: focus,
                onChanged: (v) => _edit((b) => b.copyWith(text: v)),
              ),
              const SizedBox(height: 8),
            ],
            PennaField(
              key: ValueKey('box-$r-$index'),
              label: tr('这一块的描述'),
              value: b.caption,
              maxLines: 3,
              focusNode: b.label == 'text' ? null : focus,
              onChanged: (v) => _edit((b) => b.copyWith(caption: v)),
            ),
          ],
        ),
      ),
    );
  }
}

/// 顶上 JSON 卡片里那段 JSON 最多这么高。
const _jsonMaxHeight = 240.0;

class _JsonCard extends StatelessWidget {
  const _JsonCard({
    required this.board,
    required this.onToDraft,
    required this.onAsk,
  });

  final LayoutBoard board;
  final VoidCallback onToDraft;
  final VoidCallback onAsk;

  /// 把剪贴板里的一份布局 JSON 换到画板上(别处写好的、带名字的都行)。
  Future<void> _paste(BuildContext context) async {
    final text = (await Clipboard.getData(Clipboard.kTextPlain))?.text ?? '';
    if (!context.mounted) return;
    final ok = text.trim().isNotEmpty && board.apply(text);
    showToast(context, ok ? tr('已导入') : tr('剪贴板里没有布局 JSON'), warn: !ok);
  }

  @override
  Widget build(BuildContext context) {
    final json = board.json;
    return PennaCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              PennaButton(
                label: tr('复制'),
                icon: Icons.copy,
                onPressed: () => copyWithToast(context, json, tr('已复制')),
              ),
              PennaButton(
                label: tr('导入'),
                icon: Icons.content_paste,
                tooltip: tr('从剪贴板导入布局 JSON'),
                onPressed: () => _paste(context),
              ),
              PennaButton(
                label: tr('放到成稿'),
                icon: Icons.south_west,
                onPressed: onToDraft,
              ),
              PennaButton(
                label: tr('交给 Agent'),
                icon: Icons.auto_awesome_outlined,
                background: PennaColors.primary,
                foreground: Colors.white,
                onPressed: onAsk,
              ),
            ],
          ),
          const SizedBox(height: 10),
          // 一直在顶上:JSON 长了在自己的框里滚,不把下面各块挤没。
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: _jsonMaxHeight),
            child: SingleChildScrollView(
              // 自己出的 JSON 一定读得出功能区。
              child: LayoutJsonView(
                text: json,
                regions: layoutJsonRegions(json)!,
                names: [for (final b in board.layout.boxes) b.name],
                style: TextStyle(
                  fontFamily: 'Consolas',
                  fontSize: 11.5,
                  height: 1.45,
                  color: PennaColors.slate700,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
