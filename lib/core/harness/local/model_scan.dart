import 'dart:io';

import 'llama_server.dart';
import 'wd_tagger.dart';

// 在用户指定的文件夹(连同子文件夹)里找已经有的模型,免得同一个模型反复下载。
// 认得 BooruDatasetTagManagerPlus(Models\SmilingWolf\wd-...\)、
// NLapt(模型目录\<id>\xxx.gguf)和 HuggingFace 缓存(models--作者--名字\snapshots\<哈希>\)的放法。

/// 扫到的东西,都是完整路径。
typedef FoundModels = ({
  /// 同时放着 model.onnx 和 selected_tags.csv 的文件夹(WD14 打标模型)。
  List<String> taggers,

  /// 模型本体 .gguf(名字里带 mmproj 的算视觉组件,不在这里)。
  List<String> ggufs,

  /// 视觉组件 .gguf。
  List<String> mmprojs,

  /// llama-server.exe。
  List<String> servers,

  /// 文件太多,没扫完就停了。
  bool truncated,
});

const noModels = (
  taggers: <String>[],
  ggufs: <String>[],
  mmprojs: <String>[],
  servers: <String>[],
  truncated: false,
);

/// 这些文件夹里不会有模型,还常常很大,不进去。
const _skipDirs = {
  '.git',
  'node_modules',
  r'$recycle.bin',
  'system volume information',
  '__pycache__',
};

String fileName(String path) => path.split(RegExp(r'[\\/]')).last;

bool isMmproj(String path) => fileName(path).toLowerCase().contains('mmproj');

/// 在 [roots] 里一层层往下找,最深 [maxDepth] 层,最多看 [maxEntries] 个条目。
/// 读不了的文件夹跳过。同步执行,要在别的 isolate 里调。
FoundModels scanModelFolders(
  List<String> roots, {
  int maxDepth = 8,
  int maxEntries = 200000,
}) {
  final taggers = <String>[], ggufs = <String>[], mmprojs = <String>[];
  final servers = <String>[];
  var seen = 0;
  var truncated = false;
  final queue = <(Directory, int)>[for (final r in roots) (Directory(r), 0)];
  while (queue.isNotEmpty) {
    final (dir, depth) = queue.removeAt(0);
    final List<FileSystemEntity> entries;
    try {
      entries = dir.listSync(followLinks: false);
    } on FileSystemException {
      continue;
    }
    final files = <String>{};
    for (final e in entries) {
      if (++seen > maxEntries) {
        truncated = true;
        break;
      }
      // HuggingFace 缓存里的文件常常是链接:指向文件的照常算,指向文件夹的不跟进去,免得绕圈。
      final type = e is Link
          ? FileSystemEntity.typeSync(e.path)
          : e is Directory
          ? FileSystemEntityType.directory
          : FileSystemEntityType.file;
      final name = fileName(e.path).toLowerCase();
      if (type == FileSystemEntityType.directory) {
        if (e is! Link && depth < maxDepth && !_skipDirs.contains(name)) {
          queue.add((Directory(e.path), depth + 1));
        }
      } else if (type == FileSystemEntityType.file) {
        files.add(name);
        if (name.endsWith('.gguf')) {
          (isMmproj(name) ? mmprojs : ggufs).add(e.path);
        } else if (name == 'llama-server.exe') {
          servers.add(e.path);
        }
      }
    }
    if (files.contains(taggerModelFile) && files.contains(taggerLabelsFile)) {
      taggers.add(dir.path);
    }
    if (truncated) break;
  }
  return (
    taggers: taggers,
    ggufs: ggufs,
    mmprojs: mmprojs,
    servers: servers,
    truncated: truncated,
  );
}

/// 这个文件夹是不是清单里的那个打标模型:路径里有一层的名字以模型名结尾
/// (wd-vit-tagger-v3、SmilingWolf__wd-vit-tagger-v3、models--SmilingWolf--wd-vit-tagger-v3)。
String? catalogTaggerFor(String dir) {
  final segments = dir.toLowerCase().split(RegExp(r'[\\/]'));
  for (final m in taggerModels) {
    final base = m.repo.split('/').last.toLowerCase();
    bool hit(String s) =>
        s == base ||
        s.endsWith(base) && '-_ '.contains(s[s.length - base.length - 1]);
    if (segments.any(hit)) return m.repo;
  }
  return null;
}

final _hash = RegExp(r'^[0-9a-f]{16,}$');

/// 给扫到的文件夹起个能看的名字:跳过缓存里的哈希和 snapshots 那几层。
String folderTitle(String dir) {
  for (final s in dir.split(RegExp(r'[\\/]')).reversed) {
    final low = s.toLowerCase();
    if (s.isEmpty || low == 'snapshots' || _hash.hasMatch(low)) continue;
    return low.startsWith('models--') ? s.split('--').last : s;
  }
  return dir;
}

String _parent(String path) {
  final cut = path.lastIndexOf(RegExp(r'[\\/]'));
  return cut < 0 ? '' : path.substring(0, cut);
}

/// 给模型本体配一个视觉组件:同一个文件夹里的优先。没有就是空串。
String mmprojFor(String gguf, List<String> mmprojs) =>
    mmprojs.where((p) => _parent(p) == _parent(gguf)).firstOrNull ?? '';

/// 清单里的看图模型在扫到的文件里有没有:按文件名找本体和视觉组件,同一个文件夹里的优先。
({String model, String mmproj})? findCaption(CaptionModel m, FoundModels f) {
  final model = f.ggufs.where((p) => fileName(p) == m.file).firstOrNull;
  final pairs = f.mmprojs.where((p) => fileName(p) == m.mmproj).toList();
  if (model == null || pairs.isEmpty) return null;
  final same = pairs.where((p) => _parent(p) == _parent(model)).firstOrNull;
  return (model: model, mmproj: same ?? pairs.first);
}
