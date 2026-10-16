import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../../l10n/l10n.dart';

/// 一条消息最多带几个附件。
const maxAttachments = 6;

/// 单张图片的大小上限(字节)。图片会整张编码进请求,太大接口会拒收。
const maxImageBytes = 10 * 1024 * 1024;

/// 给用户看的图片大小上限。
const maxImageLabel = '10 MB';

/// 单个文本附件的长度上限(字符数),和 Skill 正文的上限一致。
const maxFileChars = 60000;

/// 认得的图片扩展名和对应的类型。
const imageMimes = {
  'png': 'image/png',
  'jpg': 'image/jpeg',
  'jpeg': 'image/jpeg',
  'webp': 'image/webp',
  'gif': 'image/gif',
};

/// 随消息发给模型的附件:图片([bytes] + [mime])或文本文件([text])。
@immutable
class Attachment {
  const Attachment.image({
    required this.name,
    required String this.mime,
    required Uint8List this.bytes,
  }) : text = null;

  const Attachment.text({required this.name, required String this.text})
    : mime = null,
      bytes = null;

  final String name;
  final String? mime;
  final Uint8List? bytes;
  final String? text;

  bool get isImage => bytes != null;
}

/// 给用户看的附件错误。
class AttachmentException implements Exception {
  const AttachmentException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// 把一个文件读成附件:图片按扩展名认,其余的当 UTF-8 文本读。
/// 太大、读不了、既不是图片也不是文本时抛 [AttachmentException]。
Future<Attachment> readAttachment(File file) async {
  final name = file.uri.pathSegments.last;
  final dot = name.lastIndexOf('.');
  final mime = dot < 0
      ? null
      : imageMimes[name.substring(dot + 1).toLowerCase()];
  final Uint8List bytes;
  try {
    final size = await file.length();
    if (mime != null && size > maxImageBytes) {
      throw AttachmentException(tr('「{0}」超过 {1}', [name, maxImageLabel]));
    }
    // UTF-8 一个字符最多 4 字节,超过这个数一定超长,不用读进来再数。
    if (mime == null && size > maxFileChars * 4) {
      throw AttachmentException(tr('「{0}」太长', [name]));
    }
    bytes = await file.readAsBytes();
  } on FileSystemException {
    throw AttachmentException(tr('读不了「{0}」', [name]));
  }
  if (mime != null) {
    return Attachment.image(name: name, mime: mime, bytes: bytes);
  }
  final String text;
  try {
    text = utf8.decode(bytes);
  } on FormatException {
    throw AttachmentException(tr('「{0}」不是图片或文本', [name]));
  }
  // 二进制文件碰巧能按 UTF-8 解开时,里面通常有 NUL。
  if (text.contains('\u0000')) {
    throw AttachmentException(tr('「{0}」不是图片或文本', [name]));
  }
  if (text.length > maxFileChars) {
    throw AttachmentException(tr('「{0}」太长', [name]));
  }
  return Attachment.text(name: name, text: text);
}
