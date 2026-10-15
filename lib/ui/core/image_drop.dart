import 'dart:io';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../../core/harness/attachment.dart';
import 'theme.dart';
import 'widgets.dart';

/// 一张图的位置:点一下选图或直接拖进来;有图时显示它,右上角可以换图、移除。
class ImageDrop extends StatelessWidget {
  const ImageDrop({
    super.key,
    required this.image,
    required this.onChanged,
    this.hint = '点击或拖入参考图',
  });

  final Attachment? image;

  /// 没有图时中间的那句话。
  final String hint;

  /// 换了图(移除时是 null)。
  final ValueChanged<Attachment?> onChanged;

  Future<void> _use(BuildContext context, String path) async {
    try {
      final picked = await readAttachment(File(path));
      if (!picked.isImage) throw const AttachmentException('这不是图片');
      onChanged(picked);
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

  @override
  Widget build(BuildContext context) {
    final image = this.image;
    return DropTarget(
      onDragDone: (d) {
        if (d.files.isNotEmpty) _use(context, d.files.first.path);
      },
      child: image == null
          ? _EmptyImage(hint: hint, onTap: () => _pick(context))
          : _ImageBox(
              image: image,
              onReplace: () => _pick(context),
              onClear: () => onChanged(null),
            ),
    );
  }
}

class _EmptyImage extends StatelessWidget {
  const _EmptyImage({required this.hint, required this.onTap});

  final String hint;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        child: PennaCard(
          color: PennaColors.slate50,
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.add_photo_alternate_outlined,
                  size: 26,
                  color: PennaColors.slate400,
                ),
                const SizedBox(height: 6),
                Text(
                  hint,
                  style: const TextStyle(
                    fontSize: 12,
                    color: PennaColors.slate500,
                  ),
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
