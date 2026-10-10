import 'package:flutter/material.dart';

import '../../../core/harness/characters/character_dict.dart';
import '../../../core/harness/draft_block.dart';
import '../../../core/harness/tags/tag_search.dart';
import '../../../data/services/skill_store.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import 'attachment_view.dart';
import 'markdown_text.dart';
import 'mention.dart';
import 'option_pick.dart';
import 'skill_card.dart';
import 'studio_view_model.dart';

String _clock(DateTime t) =>
    [t.hour, t.minute, t.second].map((n) => '$n'.padLeft(2, '0')).join(':');

/// 回复里那份新成稿和左侧成稿的关系。
enum DraftStatus {
  /// 还没放过去,或放过去后成稿又被改了。
  ready,

  /// 已经放过去,等用户在左侧采纳或驳回。
  pending,

  /// 左侧现在就是这份。
  applied,
}

/// 对话时间线里的一条消息。
class ChatMessageView extends StatelessWidget {
  const ChatMessageView({
    super.key,
    required this.message,
    required this.onAdopt,
    required this.onAdoptDraft,
    required this.draftStatus,
    this.streaming = false,
    this.onRetry,
    this.skillNames = const [],
    this.agentAvatar = '',
    this.userAvatar = '',
    this.userSkills = const [],
    this.onAddSkill,
    this.lookups = const [],
    this.onOption,
  });

  /// 用户点了回复里的一个选项;为 null 时选项只是灰的(不是最后一条回复,或正在生成)。
  final ValueChanged<String>? onOption;

  /// 写这条回复之前查标签的那几次记录,合成一块显示。
  final List<ChatMessage> lookups;

  /// 用户已有的 Skill,用来判断回复里新写的那个加没加进去。
  final List<UserSkill> userSkills;

  /// 把回复里新写的 Skill(整篇 SKILL.md)加进用户的 Skills。
  final ValueChanged<String>? onAddSkill;

  /// 两边头像的图片路径;空串用默认头像。
  final String agentAvatar;
  final String userAvatar;

  /// 这条消息用 @ 引用的 Skill 的名字。
  final List<String> skillNames;

  final ChatMessage message;
  final ValueChanged<PromptVariant> onAdopt;

  /// 把回复里的一份新成稿放到左侧它该去的那一页。
  final ValueChanged<AgentDraft> onAdoptDraft;
  final DraftStatus Function(String text) draftStatus;

  /// 这条回复还在生成。
  final bool streaming;

  /// 非空时显示「重新运行」;只给最后一条回复。
  final VoidCallback? onRetry;

  /// Agent 回复的正文:说的话、新成稿卡片,生成完后再加一排操作。
  List<Widget> _reply(BuildContext context) {
    final m = message;
    // 先拆新 Skill:它正文里举例用的成稿标签不能被当成成稿。
    final made = splitNewSkill(
      splitCharacterTags(splitTagSearch(m.text).prose).prose,
    );
    final newSkill = made.skill;
    final asked = splitOptions(made.prose);
    final (:prose, :drafts) = splitDrafts(asked.prose);
    // 复制出去的是能直接用的:标注和中文对照不带。
    final copyable = [
      prose,
      for (final draft in drafts) stripSectionLabels(draft.text),
    ].where((s) => s.isNotEmpty).join('\n\n');
    return [
      if (prose.isNotEmpty)
        SelectableText.rich(markdownSpan(prose, _bodyStyle))
      else if (streaming && drafts.isEmpty && newSkill == null)
        const _TypingDots()
      else if (drafts.isEmpty && newSkill == null && !m.stopped)
        const Text('…', style: _bodyStyle),
      // 一份成稿一张卡片;分了页的各去各的页。
      for (final (i, draft) in drafts.indexed) ...[
        if (prose.isNotEmpty || i > 0) const SizedBox(height: 10),
        PopIn(
          child: _DraftCard(
            draft: draft,
            // 只有最后一份可能还在写。
            writing: streaming && i == drafts.length - 1,
            status: draftStatus(draft.text),
            onAdopt: () => onAdoptDraft(draft),
          ),
        ),
      ],
      if (newSkill != null) ...[
        if (prose.isNotEmpty || drafts.isNotEmpty) const SizedBox(height: 10),
        PopIn(
          child: NewSkillCard(
            text: newSkill,
            complete: made.complete,
            writing: streaming,
            userSkills: userSkills,
            onAdd: () => onAddSkill?.call(newSkill),
          ),
        ),
      ],
      // 给用户点的选项:点一下就当成他的回答发出去。
      // 这条回复已经把成稿写出来了就不显示:没有什么还要他先点头的。
      if (asked.options.isNotEmpty && !streaming && drafts.isEmpty) ...[
        const SizedBox(height: 10),
        if (asked.multi)
          PopIn(
            child: MultiPick(options: asked.options, onSubmit: onOption),
          )
        else
          PopIn(
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final (i, option) in asked.options.indexed)
                  PennaButton(
                    label: option,
                    background: i == 0
                        ? PennaColors.primary
                        : PennaColors.primaryBg,
                    foreground: i == 0 ? Colors.white : PennaColors.primary,
                    borderColor: PennaColors.primaryBorder,
                    onPressed: onOption == null
                        ? null
                        : () => onOption!(option),
                  ),
              ],
            ),
          ),
      ],
      if (!streaming) ...[
        const SizedBox(height: 6),
        PopIn(
          child: Row(
            children: [
              if (m.stopped) ...[
                const Icon(
                  Icons.stop_circle_outlined,
                  size: 13,
                  color: PennaColors.slate400,
                ),
                const SizedBox(width: 4),
                const Text(
                  '已停止',
                  style: TextStyle(fontSize: 11, color: PennaColors.slate400),
                ),
                const SizedBox(width: 8),
              ],
              if (copyable.isNotEmpty)
                PennaButton(
                  label: '复制回复',
                  icon: Icons.content_copy,
                  background: Colors.transparent,
                  foreground: PennaColors.slate500,
                  onPressed: () => copyWithToast(context, copyable, '已复制'),
                ),
              if (onRetry != null)
                PennaButton(
                  label: '重新运行',
                  icon: Icons.refresh,
                  background: Colors.transparent,
                  foreground: PennaColors.slate500,
                  onPressed: onRetry,
                ),
            ],
          ),
        ),
      ],
    ];
  }

  @override
  Widget build(BuildContext context) {
    final m = message;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        PennaAvatar(
          fromUser: m.fromUser,
          path: m.fromUser ? userAvatar : agentAvatar,
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Text(
                    m.fromUser ? '用户' : 'Penna Agent',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (m.by != null) ...[
                    const SizedBox(width: 8),
                    Flexible(child: _ModelTag(name: m.by!)),
                  ],
                  const SizedBox(width: 8),
                  Text(
                    _clock(m.time),
                    style: const TextStyle(
                      fontSize: 11,
                      color: PennaColors.slate400,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              // 程序替模型查回来的资料:查了几轮都收在这一块里。
              if (lookups.isNotEmpty) ...[
                _ToolBlock(
                  summary: lookups.length == 1
                      ? lookups.single.toolSummary ?? '查了资料'
                      : '查了资料 · ${lookups.length} 次',
                  details: [for (final l in lookups) ...l.toolDetails],
                ),
                const SizedBox(height: 10),
              ],
              if (m.toolSummary != null) ...[
                _ToolBlock(summary: m.toolSummary!, details: m.toolDetails),
                const SizedBox(height: 10),
              ],
              if (m.attachments.isNotEmpty) ...[
                AttachmentStrip(attachments: m.attachments),
                if (m.text.isNotEmpty) const SizedBox(height: 6),
              ],
              // 只发了附件、没写字的消息不画空气泡。
              if (m.fromUser && m.text.isEmpty)
                const SizedBox.shrink()
              else if (m.fromUser)
                PennaCard(
                  radius: 14,
                  padding: const EdgeInsets.all(14),
                  child: SelectableText(
                    contextMenuBuilder: pennaTextMenu,
                    m.text,
                    style: _bodyStyle,
                  ),
                )
              else
                ..._reply(context),
              if (skillNames.isNotEmpty || m.quote != null) ...[
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    if (m.quote != null)
                      MentionChip(name: sectionTitle(m.quote!), prefix: '段 · '),
                    for (final name in skillNames) MentionChip(name: name),
                  ],
                ),
              ],
              for (final v in m.variants) ...[
                const SizedBox(height: 8),
                _VariantCard(variant: v, onAdopt: () => onAdopt(v)),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

const _bodyStyle = TextStyle(fontSize: 14, height: 1.6);

/// 等第一个字出来时的三个跳动小点。
class _TypingDots extends StatefulWidget {
  const _TypingDots();

  @override
  State<_TypingDots> createState() => _TypingDotsState();
}

class _TypingDotsState extends State<_TypingDots>
    with SingleTickerProviderStateMixin {
  late final _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 22,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (_, _) => Row(
          children: [
            for (var i = 0; i < 3; i++)
              Builder(
                builder: (_) {
                  // 三个点依次起跳:每个点比前一个晚 0.18 圈。
                  final t = (_controller.value - i * 0.18) % 1;
                  // 前 0.4 圈里升到顶再落回,其余时间待在原地。
                  final up = t < 0.4 ? 1 - (t / 0.2 - 1).abs() : 0.0;
                  return Padding(
                    padding: const EdgeInsets.only(right: 5),
                    child: Transform.translate(
                      offset: Offset(0, -4 * up),
                      child: CircleAvatar(
                        radius: 3,
                        backgroundColor: Color.lerp(
                          PennaColors.slate400,
                          PennaColors.primary,
                          up,
                        ),
                      ),
                    ),
                  );
                },
              ),
          ],
        ),
      ),
    );
  }
}

/// 回复里另出的新成稿:分段列出,一键放到左侧等用户确认。
class _DraftCard extends StatefulWidget {
  const _DraftCard({
    required this.draft,
    required this.writing,
    required this.status,
    required this.onAdopt,
  });

  final AgentDraft draft;

  /// 还在生成:先不让放。
  final bool writing;
  final DraftStatus status;
  final VoidCallback onAdopt;

  @override
  State<_DraftCard> createState() => _DraftCardState();
}

class _DraftCardState extends State<_DraftCard> {
  /// 用户自己点过折叠或展开;没点过就按状态来。
  bool? _open;

  AgentDraft get draft => widget.draft;
  bool get writing => widget.writing;
  DraftStatus get status => widget.status;
  VoidCallback get onAdopt => widget.onAdopt;

  @override
  Widget build(BuildContext context) {
    // 已经送到左侧的收起来(内容在左边看),还没送的、正在写的摊开。
    final open = _open ?? (writing || status == DraftStatus.ready);
    final (label, icon) = switch (status) {
      _ when writing => ('正在写', Icons.edit_outlined),
      // 被打断或出错的半截成稿不让放,免得把残缺的内容盖到成稿上。
      _ when !draft.complete => ('不完整', Icons.error_outline),
      DraftStatus.ready => ('放到成稿', Icons.keyboard_double_arrow_left),
      DraftStatus.pending => ('待确认', Icons.hourglass_empty),
      DraftStatus.applied => ('已在成稿', Icons.check),
    };
    final ready = !writing && draft.complete && status == DraftStatus.ready;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: PennaColors.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: ready ? PennaColors.primaryBorder : PennaColors.border,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              // 点标题这一截折叠或展开。
              Expanded(
                child: MouseRegion(
                  cursor: SystemMouseCursors.click,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => setState(() => _open = !open),
                    child: Row(
                      children: [
                        AnimatedRotation(
                          turns: open ? 0.25 : 0,
                          duration: const Duration(milliseconds: 160),
                          child: const Icon(
                            Icons.chevron_right,
                            size: 16,
                            color: PennaColors.primary,
                          ),
                        ),
                        const SizedBox(width: 2),
                        Flexible(
                          child: Text(
                            [
                              switch (draft.page) {
                                null => '新成稿',
                                final page when int.tryParse(page) != null =>
                                  '新成稿 · 第 $page 页',
                                _ => '新成稿 · 新的一页',
                              },
                              ?draft.name,
                              // 收起时用各段的标注当摘要。
                              if (!open)
                                draft.sections
                                    .map((s) => s.label)
                                    .where((l) => l.isNotEmpty)
                                    .join('、'),
                            ].where((s) => s.isNotEmpty).join(' · '),
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: PennaColors.primary,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 220),
                transitionBuilder: (child, animation) => ScaleTransition(
                  scale: animation,
                  child: FadeTransition(opacity: animation, child: child),
                ),
                child: PennaButton(
                  key: ValueKey(label),
                  label: label,
                  icon: icon,
                  background: PennaColors.primary,
                  foreground: Colors.white,
                  onPressed: ready ? onAdopt : null,
                ),
              ),
            ],
          ),
          // 一段一段长出来,卡片跟着平滑变高。
          AnimatedSize(
            duration: const Duration(milliseconds: 160),
            curve: Curves.easeOut,
            alignment: Alignment.topCenter,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (!open) const SizedBox(width: double.infinity),
                for (final s
                    in open ? draft.sections : const <DraftSection>[]) ...[
                  const SizedBox(height: 8),
                  PennaCard(
                    color: PennaColors.slate50,
                    borderColor: PennaColors.slate100,
                    radius: 6,
                    padding: const EdgeInsets.all(8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (s.label.isNotEmpty) ...[
                          Text(
                            s.label,
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: PennaColors.primary,
                            ),
                          ),
                          const SizedBox(height: 2),
                        ],
                        SelectableText(
                          contextMenuBuilder: pennaTextMenu,
                          s.text,
                          style: monoStyle.copyWith(fontSize: 12),
                        ),
                        if (s.zh.isNotEmpty)
                          Text(
                            s.zh,
                            style: const TextStyle(
                              fontSize: 11.5,
                              height: 1.5,
                              color: PennaColors.slate400,
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 这条回复出自哪个模型。
class _ModelTag extends StatelessWidget {
  const _ModelTag({required this.name});

  final String name;

  @override
  Widget build(BuildContext context) {
    return PennaCard(
      color: PennaColors.slate100,
      borderColor: PennaColors.slate100,
      radius: 4,
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      child: Text(
        name,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 11, color: PennaColors.slate500),
      ),
    );
  }
}

/// 工具调用折叠块:默认展开,可收起,不抢成稿的注意力。
class _ToolBlock extends StatelessWidget {
  const _ToolBlock({required this.summary, required this.details});

  final String summary;
  final List<String> details;

  @override
  Widget build(BuildContext context) {
    return PennaCard(
      color: PennaColors.slate50,
      radius: 12,
      padding: EdgeInsets.zero,
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        // ExpansionTile 的水波纹要画在 Material 上,外层的底色盒子会挡住它。
        child: Material(
          type: MaterialType.transparency,
          child: ExpansionTile(
            dense: true,
            initiallyExpanded: true,
            tilePadding: const EdgeInsets.symmetric(horizontal: 10),
            childrenPadding: const EdgeInsets.fromLTRB(34, 0, 10, 10),
            expandedCrossAxisAlignment: CrossAxisAlignment.start,
            expandedAlignment: Alignment.centerLeft,
            leading: const Icon(
              Icons.check_circle_outline,
              size: 15,
              color: PennaColors.accent,
            ),
            title: Text(
              summary,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: PennaColors.slate700,
              ),
            ),
            children: [
              for (final d in details)
                Text(
                  d,
                  style: monoStyle.copyWith(
                    fontSize: 11,
                    color: PennaColors.slate500,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _VariantCard extends StatelessWidget {
  const _VariantCard({required this.variant, required this.onAdopt});

  final PromptVariant variant;
  final VoidCallback onAdopt;

  @override
  Widget build(BuildContext context) {
    final v = variant;
    return PennaCard(
      radius: 12,
      padding: const EdgeInsets.all(12),
      borderColor: v.recommended
          ? PennaColors.primaryBorder
          : PennaColors.border,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  v.title,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: v.recommended
                        ? PennaColors.primary
                        : PennaColors.slate700,
                  ),
                ),
              ),
              PennaButton(
                label: '采纳至成稿',
                background: v.recommended
                    ? PennaColors.primary
                    : PennaColors.slate100,
                foreground: v.recommended ? Colors.white : PennaColors.slate700,
                onPressed: onAdopt,
              ),
            ],
          ),
          const SizedBox(height: 6),
          PennaCard(
            color: PennaColors.slate50,
            borderColor: PennaColors.slate100,
            radius: 4,
            padding: const EdgeInsets.all(8),
            child: Text('+ ${v.text}', style: monoStyle.copyWith(fontSize: 12)),
          ),
          if (v.notes.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              v.notes.join('  •  '),
              style: const TextStyle(fontSize: 11, color: PennaColors.slate400),
            ),
          ],
        ],
      ),
    );
  }
}
