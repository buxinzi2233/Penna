import 'package:flutter/material.dart';

import '../../../data/services/skill_store.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';

/// 回复里新写的 Skill:名字、简介、正文预览,和它在用户 Skills 里的状态。
/// 新名字的在回复结束时已经自动加进去了;同名的要用户点一下才替换。
class NewSkillCard extends StatelessWidget {
  const NewSkillCard({
    super.key,
    required this.text,
    required this.complete,
    required this.writing,
    required this.userSkills,
    required this.onAdd,
  });

  /// 整篇 SKILL.md。
  final String text;

  /// 结束标签到了;为 false 表示还在生成,或被停在半路。
  final bool complete;
  final bool writing;

  /// 用户已有的 Skill(不含内置的)。
  final List<UserSkill> userSkills;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    UserSkill? skill;
    try {
      skill = parseSkill(text, fallbackName: '');
    } on SkillException {
      // 还没写出正文,或者写坏了。
    }
    final existing = skill == null
        ? null
        : userSkills.where((s) => s.id == skill!.id).firstOrNull;
    final (label, icon, ready) = switch (null) {
      _ when writing => ('正在写', Icons.edit_outlined, false),
      _ when !complete || skill == null => ('不完整', Icons.error_outline, false),
      _ when existing == null => ('加入 Skills', Icons.add, true),
      _
          when existing.body == skill.body &&
              existing.description == skill.description =>
        ('已加入 Skills', Icons.check, false),
      _ => ('替换同名 Skill', Icons.sync, true),
    };
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
              const Icon(
                Icons.school_outlined,
                size: 14,
                color: PennaColors.primary,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  skill == null ? '新 Skill' : '新 Skill · ${skill.name}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: PennaColors.primary,
                  ),
                ),
              ),
              PennaButton(
                key: ValueKey(label),
                label: label,
                icon: icon,
                background: PennaColors.primary,
                foreground: Colors.white,
                onPressed: ready ? onAdd : null,
              ),
            ],
          ),
          if (skill != null) ...[
            const SizedBox(height: 6),
            Text(
              skill.description,
              style: const TextStyle(fontSize: 12, color: PennaColors.slate700),
            ),
            const SizedBox(height: 8),
            PennaCard(
              color: PennaColors.slate50,
              radius: 4,
              child: Text(
                skill.body,
                maxLines: 8,
                overflow: TextOverflow.ellipsis,
                style: monoStyle.copyWith(fontSize: 11.5),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
