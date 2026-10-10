import 'dart:io';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../../../core/harness/attachment.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import 'reverse_model.dart';
import 'studio_view_model.dart';

/// 图像反推:左边放参考图(点选或拖进来),右边是从它反推出的原始提示词。
class ReversePane extends StatelessWidget {
  const ReversePane({super.key, required this.model, this.onSend});

  final ReverseModel model;

  /// 把反推出的提示词交给 Agent(放进聊天输入框)。
  final ValueChanged<String>? onSend;

  Future<void> _use(BuildContext context, String path) async {
    try {
      final picked = await readAttachment(File(path));
      if (!picked.isImage) throw const AttachmentException('这不是图片');
      model.setImage(picked);
    } on AttachmentException catch (e) {
      if (context.mounted) showToast(context, e.message, warn: true);
    }
  }

  Future<void> _pick(BuildContext context) async {
    final picked = await openFile(
      acceptedTypeGroups: [
        XTypeGroup(label: '图片', extensions: imageMimes.keys.toList()),
      ],
    );
    if (picked != null && context.mounted) await _use(context, picked.path);
  }

  Future<void> _run(BuildContext context) async {
    final problem = await model.run();
    if (problem != null && context.mounted) {
      showToast(context, problem, warn: true);
    }
  }

  void _toDraft(BuildContext context) {
    final problem = model.vm.restorePrompt((
      time: DateTime.now(),
      text: model.prompt,
    ), title: '图像反推');
    if (problem != null) showToast(context, problem, warn: true);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: model,
      builder: (context, _) {
        final image = model.image;
        final prompt = model.prompt;
        return Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 图这边留一半宽:横构图的图也看得清。
              Expanded(
                child: DropTarget(
                  onDragDone: (d) {
                    if (d.files.isNotEmpty) _use(context, d.files.first.path);
                  },
                  child: image == null
                      ? _EmptyImage(onTap: () => _pick(context))
                      : _ImageBox(
                          image: image,
                          onReplace: () => _pick(context),
                          onClear: () => model.setImage(null),
                        ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: PennaCard(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          const Expanded(
                            child: Text(
                              '原始反推提示词',
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          PennaButton(
                            label: '发送给 Agent',
                            icon: Icons.send_outlined,
                            borderColor: PennaColors.border,
                            onPressed: prompt.isEmpty || onSend == null
                                ? null
                                : () => onSend!(prompt),
                          ),
                          const SizedBox(width: 6),
                          PennaButton(
                            label: prompt.isEmpty ? '反推' : '重新反推',
                            icon: Icons.image_search,
                            background: PennaColors.primaryBg,
                            foreground: PennaColors.primary,
                            borderColor: PennaColors.primaryBorder,
                            onPressed: image == null || model.busy
                                ? null
                                : () => _run(context),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Expanded(
                        child: PennaCard(
                          color: PennaColors.slate50,
                          radius: 4,
                          child: model.busy
                              ? const Center(
                                  child: SizedBox.square(
                                    dimension: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  ),
                                )
                              : prompt.isEmpty
                              ? const Center(
                                  child: Text(
                                    '暂无内容',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: PennaColors.slate400,
                                    ),
                                  ),
                                )
                              : SingleChildScrollView(
                                  child: SelectableText(
                                    contextMenuBuilder: pennaTextMenu,
                                    prompt,
                                    style: monoStyle.copyWith(fontSize: 11.5),
                                  ),
                                ),
                        ),
                      ),
                      if (prompt.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            PennaButton(
                              label: '复制',
                              icon: Icons.content_copy,
                              onPressed: () =>
                                  copyWithToast(context, prompt, '已复制'),
                            ),
                            const SizedBox(width: 6),
                            PennaButton(
                              label: '放到成稿',
                              icon: Icons.keyboard_double_arrow_up,
                              background: PennaColors.accent,
                              foreground: Colors.white,
                              onPressed: () => _toDraft(context),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _EmptyImage extends StatelessWidget {
  const _EmptyImage({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        child: const PennaCard(
          color: PennaColors.slate50,
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.add_photo_alternate_outlined,
                  size: 26,
                  color: PennaColors.slate400,
                ),
                SizedBox(height: 6),
                Text(
                  '点击或拖入参考图',
                  style: TextStyle(fontSize: 12, color: PennaColors.slate500),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ImageBox extends StatelessWidget {
  const _ImageBox({
    required this.image,
    required this.onReplace,
    required this.onClear,
  });

  final Attachment image;
  final VoidCallback onReplace;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return PennaCard(
      color: PennaColors.slate50,
      padding: const EdgeInsets.all(6),
      child: Stack(
        children: [
          Positioned.fill(
            child: Image.memory(
              image.bytes!,
              fit: BoxFit.contain,
              errorBuilder: (_, _, _) => const Center(
                child: Icon(
                  Icons.broken_image_outlined,
                  color: PennaColors.slate400,
                ),
              ),
            ),
          ),
          Positioned(
            top: 0,
            right: 0,
            child: Row(
              children: [
                PennaButton(
                  label: '换图',
                  icon: Icons.swap_horiz,
                  borderColor: PennaColors.border,
                  onPressed: onReplace,
                ),
                const SizedBox(width: 4),
                PennaButton(
                  label: '移除',
                  icon: Icons.close,
                  borderColor: PennaColors.border,
                  onPressed: onClear,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
