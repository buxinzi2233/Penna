import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../../../core/harness/attachment.dart';
import '../../../core/harness/providers/openai_provider.dart';
import 'studio_view_model.dart';
import '../../../l10n/l10n.dart';

const _reversePrompt =
    '你是图像反推助手。看这张图,写出能让文生图模型画出同样画面的英文正面提示词:'
    '主体、场景、构图、光影、色彩、画风与媒介都要写到。'
    '只输出提示词本身,不要解释,不要负面词,不要任何标签或分段标注。'
    '写法(句子还是标签、偏什么风格)照下面用户当前 Preset 的要求来;它没有要求时写成一段英文。';

/// 图像反推:一张参考图,和用看图模型从它反推出的提示词。
/// 反推结果同时交给 [vm] 当 Agent 的上下文,用户可以让 Agent 照着它衍生。
class ReverseModel extends ChangeNotifier {
  /// [dir] 是存参考图和反推结果的文件夹;为 null 时不存(测试用)。
  ReverseModel(this.vm, {this.dir});

  final StudioViewModel vm;
  final Directory? dir;

  Attachment? _image;
  String _prompt = '';
  bool _busy = false;

  /// 换图或清空时加一,用来作废还在路上的反推结果。
  int _round = 0;

  /// 图换过了还没写盘;只是反推结果变了的时候不用把整张图再写一遍。
  bool _imageUnsaved = false;

  Attachment? get image => _image;
  String get prompt => _prompt;
  bool get busy => _busy;

  /// 换一张参考图(null 是清空);原来的反推结果一起清掉。
  void setImage(Attachment? image) {
    assert(image == null || image.isImage);
    _round++;
    _image = image;
    _imageUnsaved = true;
    _busy = false;
    _setPrompt('');
  }

  void _setPrompt(String prompt) {
    _prompt = prompt;
    vm.referencePrompt = prompt;
    notifyListeners();
    _save();
  }

  /// 反推当前这张图。失败时返回给用户看的原因,成功返回 null。
  Future<String?> run() async {
    final image = _image;
    if (image == null) return tr('先放一张图');
    if (_busy) return tr('正在反推');
    final round = ++_round;
    _busy = true;
    notifyListeners();
    String? problem;
    var out = '';
    try {
      out = (await vm.askOnce(
        [
          {
            'role': 'system',
            // 反推跟着用户当前的 Preset 走:他选了写实就按写实写,选了标签就出标签。
            'content':
                '$_reversePrompt\n\n【用户当前的 Preset】\n'
                '${vm.config.config.activePreset.systemPrompt}',
          },
          {'role': 'user', 'content': '反推这张图'},
        ],
        images: {
          1: [(mime: image.mime!, bytes: image.bytes!)],
        },
      )).trim();
      if (out.isEmpty) problem = tr('模型没有返回内容');
    } on LlmException catch (e) {
      problem = e.message;
    } on Object catch (e) {
      // 只报类型,原文可能带着 Key。
      problem = tr('反推失败({0})', [e.runtimeType]);
    }
    // 等结果的时候图已经换了:这次的结果不要了。
    if (round != _round) return null;
    _busy = false;
    if (problem == null) {
      _setPrompt(out);
    } else {
      notifyListeners();
    }
    return problem;
  }

  File? get _meta => dir == null
      ? null
      : File('${dir!.path}${Platform.pathSeparator}reverse.json');
  File? get _bytes => dir == null
      ? null
      : File('${dir!.path}${Platform.pathSeparator}reverse.img');

  void _save() {
    final meta = _meta, bytes = _bytes, image = _image;
    if (meta == null || bytes == null) return;
    try {
      if (image == null) {
        if (meta.existsSync()) meta.deleteSync();
        if (bytes.existsSync()) bytes.deleteSync();
        return;
      }
      meta.parent.createSync(recursive: true);
      if (_imageUnsaved) bytes.writeAsBytesSync(image.bytes!);
      _imageUnsaved = false;
      meta.writeAsStringSync(
        jsonEncode({'name': image.name, 'mime': image.mime, 'prompt': _prompt}),
      );
    } on FileSystemException catch (e) {
      debugPrint(tr('参考图没存上:{0}', [e.message]));
    }
  }

  Future<void> load() async {
    final meta = _meta, bytes = _bytes;
    if (meta == null || bytes == null) return;
    try {
      if (!meta.existsSync() || !bytes.existsSync()) return;
      final j = jsonDecode(await meta.readAsString()) as Map<String, dynamic>;
      final data = await bytes.readAsBytes();
      // 空文件是上次没写完留下的,当没有参考图。
      if (data.isEmpty) return;
      _image = Attachment.image(
        name: j['name'] as String,
        mime: j['mime'] as String,
        bytes: data,
      );
      _prompt = j['prompt'] as String? ?? '';
      vm.referencePrompt = _prompt;
      notifyListeners();
    } on Object {
      // 读不了就当没有参考图,不拦着程序启动。
    }
  }
}
