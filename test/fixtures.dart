import 'dart:io';

import 'package:penna/core/harness/providers/openai_provider.dart';
import 'package:penna/data/services/config_service.dart';
import 'package:penna/data/services/skill_store.dart';
import 'package:penna/ui/features/studio/studio_view_model.dart';

ConfigService tempConfig() =>
    ConfigService(dir: Directory.systemTemp.createTempSync('penna_test'));

SkillStore tempSkills() =>
    SkillStore(Directory.systemTemp.createTempSync('penna_skills'));

/// 一个开头有固定区、后面三块正文、一处待确认 diff 和两个候选方案的工作台。
StudioViewModel sampleStudio({
  ConfigService? config,
  ChatStreamer? streamChat,
}) {
  const lighting = PromptVariant(
    title: '方案 A',
    text: 'dramatic volumetric neon rim lighting, ',
    segmentIndex: 2,
    recommended: true,
  );
  const droplets = PromptVariant(
    title: '方案 B',
    text: 'condensation water droplets, ',
    segmentIndex: 2,
  );
  final time = DateTime(2026, 10, 8, 14, 28, 10);
  return StudioViewModel(
    config: config ?? tempConfig(),
    streamChat: streamChat ?? (_) => const Stream.empty(),
    blocks: const [
      (text: 'masterpiece, titanium armor plating,', pinned: true),
      (text: 'A cybernetic android in the rain. ', pinned: false),
      (text: 'flat generic ambient lighting, ', pinned: false),
      (text: 'Shot on 35mm.', pinned: false),
    ],
    pending: DiffProposal(
      title: 'Agent 建议',
      segmentIndex: 2,
      removed: 'flat generic ambient lighting, ',
      added: lighting.text,
    ),
    messages: [
      ChatMessage(fromUser: true, text: '增强背光', time: time),
      ChatMessage(
        fromUser: false,
        text: '两个方案:',
        time: time,
        toolSummary: '已调用技能: local-edit',
        toolDetails: const ['锁定区校验通过'],
        variants: const [lighting, droplets],
      ),
    ],
  );
}
