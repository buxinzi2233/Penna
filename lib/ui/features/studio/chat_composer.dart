part of 'chat_pane.dart';

// 对话底部:快捷操作、输入框、附件、发送和停止。

class _Composer extends StatelessWidget {
  const _Composer({
    required this.input,
    required this.inputFocus,
    required this.quickActions,
    required this.onQuickAction,
    required this.onKey,
    required this.onSend,
    required this.onStop,
    required this.picker,
    required this.chips,
    required this.onAttach,
    required this.dragging,
    this.queued = const [],
  });

  /// 排着队等发的那几条,显示在最上面。
  final List<Widget> queued;

  /// 打 @ 时显示在输入框上方的 Skill 列表;不在打 @ 时为 null。
  final Widget? picker;

  /// 附件和已引用的 Skill 的标签,显示在输入框里文字的上方。
  final List<Widget> chips;

  final VoidCallback onAttach;

  /// 有文件正拖在上方:输入框描边变色,提示可以松手。
  final bool dragging;

  final TextEditingController input;
  final FocusNode inputFocus;
  final List<QuickAction> quickActions;
  final ValueChanged<String> onQuickAction;
  final FocusOnKeyEventCallback onKey;
  final VoidCallback onSend;

  /// 非空表示正在生成,发送键变成停止键。
  final VoidCallback? onStop;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: const BoxDecoration(
        color: PennaColors.card,
        border: Border(top: BorderSide(color: PennaColors.border)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 排队的条目增减时,高度顺着伸缩。
          AnimatedSize(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            alignment: Alignment.bottomCenter,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final row in queued) ...[row, const SizedBox(height: 6)],
              ],
            ),
          ),
          if (quickActions.isNotEmpty) ...[
            Wrap(
              spacing: 6,
              runSpacing: 6,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                const Text(
                  '快捷操作:',
                  style: TextStyle(fontSize: 11, color: PennaColors.slate400),
                ),
                for (final action in quickActions)
                  PennaButton(
                    label: action.label,
                    background: PennaColors.slate100,
                    onPressed: () => onQuickAction(action.prompt),
                  ),
              ],
            ),
            const SizedBox(height: 8),
          ],
          if (picker != null) ...[
            PopIn(child: picker!),
            const SizedBox(height: 6),
          ],
          PennaCard(
            color: dragging ? PennaColors.primaryBg : PennaColors.slate50,
            borderColor: dragging ? PennaColors.primary : PennaColors.border,
            radius: 16,
            padding: const EdgeInsets.fromLTRB(16, 4, 8, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (chips.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 6, right: 8),
                    child: Wrap(spacing: 6, runSpacing: 6, children: chips),
                  ),
                Focus(
                  onKeyEvent: onKey,
                  child: TextField(
                    contextMenuBuilder: pennaTextMenu,
                    controller: input,
                    focusNode: inputFocus,
                    minLines: 3,
                    maxLines: 3,
                    style: const TextStyle(fontSize: 14, height: 1.5),
                    decoration: const InputDecoration(
                      hintText: 'Enter 发送 · Shift+Enter 换行 · @ 引用 Skill',
                      hintStyle: TextStyle(color: PennaColors.slate400),
                      border: InputBorder.none,
                      isDense: true,
                    ),
                  ),
                ),
                Row(
                  children: [
                    // 输入框左边有 16 的留白,往回收一点让图标和文字左缘对齐。
                    Transform.translate(
                      offset: const Offset(-6, 0),
                      child: IconButton(
                        onPressed: onAttach,
                        tooltip: '添加图片或文本文件',
                        icon: const Icon(Icons.attach_file, size: 17),
                        color: PennaColors.slate500,
                        style: IconButton.styleFrom(
                          minimumSize: const Size.square(28),
                          padding: EdgeInsets.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                      ),
                    ),
                    const Spacer(),
                    Bouncy(
                      child: IconButton.filled(
                        onPressed: onStop ?? onSend,
                        tooltip: onStop == null ? '发送' : '停止生成(Esc)',
                        icon: AnimatedSwitcher(
                          duration: const Duration(milliseconds: 200),
                          transitionBuilder: (child, animation) =>
                              ScaleTransition(scale: animation, child: child),
                          child: Icon(
                            onStop == null ? Icons.arrow_upward : Icons.stop,
                            key: ValueKey(onStop == null),
                            size: 16,
                          ),
                        ),
                        style: IconButton.styleFrom(
                          backgroundColor: PennaColors.text,
                          foregroundColor: Colors.white,
                          minimumSize: const Size.square(28),
                          padding: EdgeInsets.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 排着队的一条消息:等正在生成的回复说完自动发,也可以立刻发或撤掉。
class _QueuedRow extends StatelessWidget {
  const _QueuedRow({
    required this.text,
    required this.onSendNow,
    required this.onRemove,
  });

  final String text;
  final VoidCallback onSendNow;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return PopIn(
      child: PennaCard(
        color: PennaColors.slate50,
        radius: 10,
        padding: const EdgeInsets.fromLTRB(10, 3, 2, 3),
        child: Row(
          children: [
            const Icon(Icons.schedule, size: 14, color: PennaColors.slate400),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                text,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 12.5,
                  color: PennaColors.slate700,
                ),
              ),
            ),
            PennaButton(
              label: '立刻发送',
              icon: Icons.bolt,
              tooltip: '打断正在生成的回复,马上发这条',
              onPressed: onSendNow,
            ),
            IconButton(
              tooltip: '撤掉',
              iconSize: 14,
              visualDensity: VisualDensity.compact,
              color: PennaColors.slate400,
              icon: const Icon(Icons.close),
              onPressed: onRemove,
            ),
          ],
        ),
      ),
    );
  }
}
