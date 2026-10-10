part of 'chat_pane.dart';

// 对话顶栏:选模型、新对话、历史、切换 Preset。

/// 顶栏:当前模型(点击去设置)+ Preset 切换。
class _Header extends StatelessWidget {
  const _Header({
    required this.vm,
    required this.config,
    required this.onOpenSettings,
  });

  final StudioViewModel vm;
  final ConfigService config;

  /// 「新对话」和「历史」两个按钮;生成中换不了,所以先禁用。
  List<Widget> _chatButtons(BuildContext context) => [
    PennaButton(
      label: '新对话',
      icon: Icons.add_comment_outlined,
      borderColor: PennaColors.border,
      onPressed: vm.isStreaming || vm.messages.isEmpty ? null : vm.newChat,
    ),
    const SizedBox(width: 6),
    PopupMenuButton<String>(
      tooltip: '历史对话',
      enabled: !vm.isStreaming && vm.pastChats.isNotEmpty,
      position: PopupMenuPosition.under,
      offset: const Offset(0, 6),
      constraints: const BoxConstraints(maxWidth: 320, maxHeight: 420),
      onSelected: vm.openChat,
      itemBuilder: (menu) => [
        for (final chat in vm.pastChats)
          PopupMenuItem(
            value: chat.id,
            height: 34,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        chatTitle(chat.messages),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                          color: PennaColors.slate700,
                        ),
                      ),
                      Text(
                        '${shortTime(chat.messages.first.time)} · '
                        '${chat.messages.length} 条',
                        style: const TextStyle(
                          fontSize: 11,
                          color: PennaColors.slate400,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: '删除这场对话',
                  iconSize: 14,
                  visualDensity: VisualDensity.compact,
                  color: PennaColors.slate400,
                  icon: const Icon(Icons.close),
                  onPressed: () {
                    vm.deleteChat(chat.id);
                    Navigator.pop(menu);
                  },
                ),
              ],
            ),
          ),
      ],
      child: Bouncy(
        child: PennaCard(
          color: PennaColors.card,
          radius: 6,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.history,
                size: 14,
                color: vm.pastChats.isEmpty
                    ? PennaColors.slate400
                    : PennaColors.slate700,
              ),
              const SizedBox(width: 4),
              Text(
                '历史',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: vm.pastChats.isEmpty
                      ? PennaColors.slate400
                      : PennaColors.slate700,
                ),
              ),
            ],
          ),
        ),
      ),
    ),
    const SizedBox(width: 6),
  ];
  final VoidCallback onOpenSettings;

  @override
  Widget build(BuildContext context) {
    final cfg = config.config;
    final chain = cfg.agentChain;
    // 指定的模型被删了或关了,就当作按顺序。
    final pinned = chain.any((l) => l.id == cfg.activeLlmId)
        ? cfg.activeLlmId
        : null;
    PopupMenuItem<String> item(String value, String name, bool selected) =>
        PopupMenuItem(
          value: value,
          height: 34,
          padding: EdgeInsets.zero,
          child: _PresetMenuRow(name: name, selected: selected),
        );
    return PennaBar(
      color: PennaColors.card,
      children: [
        if (chain.isEmpty)
          PennaButton(
            label: '未连接模型 · 去设置',
            icon: Icons.auto_awesome,
            background: PennaColors.slate50,
            foreground: PennaColors.slate500,
            borderColor: PennaColors.border,
            onPressed: onOpenSettings,
          )
        else
          PopupMenuButton<String>(
            tooltip: 'Agent 使用的模型',
            position: PopupMenuPosition.under,
            offset: const Offset(0, 6),
            onSelected: (id) => id == _manageModels
                ? onOpenSettings()
                : config.update(
                    cfg.copyWith(activeLlmId: () => id == _byOrder ? null : id),
                  ),
            itemBuilder: (_) => [
              item(_byOrder, '按顺序', pinned == null),
              for (final l in chain)
                item(
                  l.id,
                  l.name.trim().isEmpty ? '未命名' : l.name,
                  pinned == l.id,
                ),
              const PopupMenuDivider(height: 8),
              item(_manageModels, '管理模型…', false),
            ],
            child: Bouncy(
              child: PennaCard(
                color: PennaColors.slate50,
                radius: 6,
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.auto_awesome,
                      size: 14,
                      color: PennaColors.primary,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      chain.first.name.trim().isEmpty
                          ? '未命名'
                          : chain.first.name,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const Icon(
                      Icons.keyboard_arrow_down,
                      size: 14,
                      color: PennaColors.slate500,
                    ),
                  ],
                ),
              ),
            ),
          ),
        const Spacer(),
        ..._chatButtons(context),
        PopupMenuButton<String>(
          tooltip: '切换 Preset',
          position: PopupMenuPosition.under,
          offset: const Offset(0, 6),
          onSelected: (id) => config.update(cfg.copyWith(activePresetId: id)),
          itemBuilder: (_) => [
            for (final p in cfg.presets)
              PopupMenuItem(
                value: p.id,
                height: 34,
                padding: EdgeInsets.zero,
                child: _PresetMenuRow(
                  name: p.displayName,
                  selected: p.id == cfg.activePreset.id,
                ),
              ),
          ],
          child: Bouncy(
            child: PennaCard(
              color: PennaColors.slate100,
              borderColor: PennaColors.slate100,
              radius: 6,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.tune, size: 14, color: PennaColors.slate500),
                  const SizedBox(width: 4),
                  Text(
                    cfg.activePreset.displayName,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: PennaColors.slate700,
                    ),
                  ),
                  const Icon(
                    Icons.keyboard_arrow_down,
                    size: 14,
                    color: PennaColors.slate500,
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _PresetMenuRow extends StatelessWidget {
  const _PresetMenuRow({required this.name, required this.selected});

  final String name;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final color = selected ? PennaColors.primary : PennaColors.slate700;
    return Container(
      constraints: const BoxConstraints(minWidth: 150),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: selected ? PennaColors.primaryBg : null,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              name,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: color,
              ),
            ),
          ),
          if (selected) Icon(Icons.check, size: 14, color: color),
        ],
      ),
    );
  }
}
