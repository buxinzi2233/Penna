import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:flutter_onnxruntime/flutter_onnxruntime.dart';

class OnnxException implements Exception {
  const OnnxException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// 一个加载好的 ONNX 模型:取第一个输入、第一个输出(打标模型都是这样)。
// ponytail: 插件在 Windows 的平台线程上同步跑模型,大模型加载和推理时窗口会停顿一两秒;
// 要完全不卡得换成能在 isolate 里跑的 FFI 版 onnxruntime。也只用 CPU,要用显卡得换 DirectML 版运行库。
class OnnxModel {
  OnnxModel._(this._session, this.inputName, this.inputShape);

  final OrtSession _session;
  final String inputName;

  /// 输入的形状;动态的维度是 -1。
  final List<int> inputShape;

  static Future<OnnxModel> load(String path) async {
    try {
      final session = await OnnxRuntime().createSession(path);
      final input = (await session.getInputInfo()).first;
      return OnnxModel._(session, input['name'] as String, [
        for (final d in input['shape'] as List) (d as num).toInt(),
      ]);
    } on PlatformException catch (e) {
      throw OnnxException('模型加载失败:${_brief(e.message)}');
    } on MissingPluginException {
      throw const OnnxException('这个版本没有带 ONNX 运行库');
    }
  }

  /// 跑一次,返回第一个输出摊平后的数。
  Future<List<double>> run(Float32List data, List<int> shape) async {
    final input = await OrtValue.fromList(data, shape);
    try {
      final outputs = await _session.run({inputName: input});
      try {
        final values = await outputs.values.first.asFlattenedList();
        return [for (final v in values) (v as num).toDouble()];
      } finally {
        for (final v in outputs.values) {
          await v.dispose();
        }
      }
    } on PlatformException catch (e) {
      throw OnnxException('推理失败:${_brief(e.message)}');
    } finally {
      await input.dispose();
    }
  }

  Future<void> close() => _session.close();
}

/// 运行库的报错可能很长,截一截。
String _brief(String? message) {
  final text = (message ?? '未知错误').trim();
  return text.length > 200 ? '${text.substring(0, 200)}…' : text;
}
