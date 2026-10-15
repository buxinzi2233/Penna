import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:ui' as ui;

import 'package:archive/archive_io.dart';
import 'package:flutter/foundation.dart';

import '../../../core/harness/attachment.dart';
import '../../../core/harness/local/caption_catalog.dart';
import '../../../core/harness/local/download.dart';
import '../../../core/harness/local/florence.dart';
import '../../../core/harness/local/llama_server.dart';
import '../../../core/harness/local/model_scan.dart';
import '../../../core/harness/local/wd_tagger.dart';
import '../../../core/harness/providers/llm_http.dart';
import '../../../data/services/florence_engine.dart';
import '../../../data/services/onnx_model.dart';

part 'local_caption.dart';

/// 看图写自然语言时默认的要求。
const defaultCaptionPrompt =
    'Describe this image in detail as a prompt for an image generation model: '
    'subject, appearance, clothing, pose, expression, background, composition, '
    'lighting and art style. Output only the description in English.';

/// 下载的进度:已有多少字节,总共多少(不知道时为 null)。
typedef Progress = ({int received, int? total});

typedef StreamChatFn = Stream<String> Function(LlmRequest request);

/// 本地推理页的状态:Tag 反推(ONNX 打标模型)和 NL 反推(看图模型,见 [LocalCaption])。
/// 设置存在「文档\Penna\local.json」,模型和运行时在「文档\Penna\models」「runtime」下。
class LocalModel extends ChangeNotifier {
  /// [dir] 为 null 时只在内存里(测试用),也不能下载。
  LocalModel({
    this.dir,
    required this.streamChat,
    LlamaServer? server,
    Future<OnnxModel> Function(String path)? loadOnnx,
  }) : server = server ?? LlamaServer(),
       _loadOnnx = loadOnnx ?? OnnxModel.load {
    // 服务自己退出了(崩了、被别的程序关了),界面跟着变回未启动。
    this.server.onExit = notifyListeners;
  }

  final Directory? dir;
  final StreamChatFn streamChat;
  final LlamaServer server;
  final Future<OnnxModel> Function(String path) _loadOnnx;

  // —— 存盘的设置 ——
  String source = 'mirror';
  String taggerRepo = taggerModels.first.repo;
  double general = taggerModels.first.general;
  double character = taggerModels.first.character;

  /// 自己选的 llama-server.exe;空串用下载的运行时。
  String exePath = '';
  String modelPath = '';
  String mmprojPath = '';
  int port = 8091;
  int context = 4096;
  int gpuLayers = -1;
  String captionPrompt = defaultCaptionPrompt;

  /// 用户加的模型文件夹:连同子文件夹一起找已有的模型,找到的直接用,不用再下。
  List<String> modelFolders = const [];

  /// 两个模型列表用户拖好的顺序(id 的先后);没列的排在后面。
  List<String> taggerOrder = const [];
  List<String> captionOrder = const [];

  /// 各看图模型选的量化档(模型 id → 档名)。
  Map<String, String> quantPicks = const {};

  /// 选中的清单看图模型的 id;选的是自己的 GGUF 时为空串。
  String captionPick = '';

  /// Florence-2 用的指令。
  String florenceTask = florenceTaskLabels.keys.first;

  // —— 只在内存里的 ——
  Attachment? _image;
  final _downloads = <String, Progress>{};
  final _cancels = <String, DownloadCancel>{};
  OnnxModel? _tagger;
  String? _taggerFor;
  List<TagLabel> _labels = const [];
  bool _tagging = false;
  TagResult? _tags;

  /// 换图、换模型时加一;推理途中变了,那次的结果就不要了,免得挂到新图上。
  int _round = 0;

  /// 上次推理每个标签的把握;调阈值时拿它重新筛,不用再跑模型。
  List<double>? _scores;
  bool _starting = false;
  bool _captioning = false;
  String _caption = '';
  FlorenceEngine? _florence;
  String? _florenceFor;

  Attachment? get image => _image;
  bool get tagging => _tagging;
  TagResult? get tags => _tags;
  bool get starting => _starting;
  bool get captioning => _captioning;
  String get caption => _caption;
  bool get serverRunning => server.running;

  FoundModels _found = noModels;
  bool _scanning = false;

  /// 上次在模型文件夹里扫到的东西。
  FoundModels get found => _found;
  bool get scanning => _scanning;

  /// 正在下载的东西(按 [download] 时给的名字)和进度。
  Progress? progressOf(String key) => _downloads[key];
  bool get downloading => _downloads.isNotEmpty;

  String get _sep => Platform.pathSeparator;
  String get _home => dir?.path ?? '';

  /// 文件夹里找到、但不在清单里的打标模型,id 用这个开头接文件夹路径。
  static const _localTagger = 'local:';

  /// 能选的打标模型:清单里的,加上文件夹里找到的别的 WD 类模型(阈值用常见的默认值)。
  List<TaggerModel> get taggers => [
    ...taggerModels,
    for (final d in _found.taggers)
      if (catalogTaggerFor(d) == null)
        (
          repo: '$_localTagger$d',
          name: folderTitle(d),
          note: '本机',
          general: 0.35,
          character: 0.85,
        ),
  ];

  /// 打标模型列表,按用户拖好的顺序。
  List<TaggerModel> get orderedTaggers =>
      _ordered(taggers, (m) => m.repo, taggerOrder);

  void moveTagger(int from, int to) {
    final ids = [for (final m in orderedTaggers) m.repo];
    ids.insert(to, ids.removeAt(from));
    update(() => taggerOrder = List.unmodifiable(ids));
  }

  TaggerModel get tagger =>
      taggers.where((m) => m.repo == taggerRepo).firstOrNull ??
      taggerModels.first;

  /// 打标模型在文件夹里找到的位置;自己下载过的不算。
  String? foundTagger(TaggerModel m) => m.repo.startsWith(_localTagger)
      ? m.repo.substring(_localTagger.length)
      : _found.taggers.where((d) => catalogTaggerFor(d) == m.repo).firstOrNull;

  /// 要用的模型和标签表:自己下载的优先,其次是文件夹里找到的。都没有时为 null。
  ({String model, String labels})? taggerPaths(TaggerModel m) {
    if (!m.repo.startsWith(_localTagger)) {
      final files = taggerFiles(m);
      if (ready(files)) return (model: files[0].path, labels: files[1].path);
    }
    final dir = foundTagger(m);
    return dir == null
        ? null
        : (
            model: '$dir$_sep$taggerModelFile',
            labels: '$dir$_sep$taggerLabelsFile',
          );
  }

  // —— 文件位置 ——

  List<RemoteFile> taggerFiles(TaggerModel m) => [
    for (final name in [taggerModelFile, taggerLabelsFile])
      (
        url: hfFileUrl(source, m.repo, name),
        path:
            '$_home${_sep}models${_sep}tagger$_sep'
            '${m.repo.replaceAll('/', '__')}$_sep$name',
        size: null,
        sha256: null,
      ),
  ];

  RemoteFile get _runtimeZip => (
    url: llamaRuntimeUrl,
    path: '$_home${_sep}runtime$_sep$llamaRuntimeFile',
    size: llamaRuntimeSize,
    sha256: llamaRuntimeSha256,
  );

  Directory get _runtimeDir =>
      Directory('$_home${_sep}runtime${_sep}llama.cpp-$llamaCppTag');

  bool ready(List<RemoteFile> files) =>
      dir != null && files.every(isDownloaded);

  /// 要用的 llama-server:自己选的优先,其次是下载好的运行时,再次是文件夹里找到的。
  String? get serverExe => exePath.isNotEmpty
      ? exePath
      : (dir == null ? null : findServerExe(_runtimeDir)?.path) ??
            _found.servers.firstOrNull;

  // —— 模型文件夹 ——

  void addFolder(String path) {
    if (modelFolders.contains(path)) return;
    update(() => modelFolders = List.unmodifiable([...modelFolders, path]));
    rescan();
  }

  void removeFolder(String path) {
    update(
      () => modelFolders = List.unmodifiable(
        modelFolders.where((f) => f != path),
      ),
    );
    rescan();
  }

  /// 重新扫一遍模型文件夹。在别的 isolate 里扫,文件多也不卡界面。
  Future<void> rescan() async {
    final roots = modelFolders;
    _scanning = true;
    notifyListeners();
    FoundModels result = noModels;
    try {
      result = await Isolate.run(() => scanModelFolders(roots));
    } on Object catch (e) {
      debugPrint('扫描模型文件夹失败:${e.runtimeType}');
    }
    // 扫的时候文件夹又变了:以后面那次为准。
    if (!identical(roots, modelFolders)) return;
    _found = result;
    _scanning = false;
    notifyListeners();
  }

  // —— 改设置 ——

  /// 通知界面。扩展里不能直接调 notifyListeners(它是受保护的)。
  void _changed() => notifyListeners();

  void update(void Function() change) {
    change();
    notifyListeners();
    _save();
  }

  /// 换打标模型:阈值换成它的推荐值,已加载的模型放掉。
  void pickTagger(String repo) {
    // 推理途中不换:正在用的模型会被关掉。
    if (repo == taggerRepo || _tagging) return;
    _round++;
    update(() {
      taggerRepo = repo;
      general = tagger.general;
      character = tagger.character;
      _tags = null;
      _scores = null;
    });
    _dropTagger();
  }

  /// 调阈值:上次推理的结果按新阈值重新筛。
  void setThresholds({double? general, double? character}) => update(() {
    this.general = general ?? this.general;
    this.character = character ?? this.character;
    _refilter();
  });

  void _refilter() {
    final scores = _scores;
    _tags = scores == null
        ? null
        : decodeTags(scores, _labels, general: general, character: character);
  }

  void setImage(Attachment? image) {
    _round++;
    _image = image;
    _tags = null;
    _scores = null;
    _caption = '';
    notifyListeners();
  }

  // —— 下载 ——

  /// 依次下载 [files],进度记在 [key] 下。失败时返回给用户看的原因。
  Future<String?> download(String key, List<RemoteFile> files) async {
    if (dir == null) return '没有存放的地方';
    if (_downloads.containsKey(key)) return '正在下载';
    final cancel = _cancels[key] = DownloadCancel();
    final sizes = [for (final f in files) f.size];
    final total = sizes.contains(null)
        ? null
        : sizes.fold<int>(0, (a, b) => a + b!);
    var before = 0;
    _downloads[key] = (received: 0, total: total);
    notifyListeners();
    String? problem;
    try {
      for (final f in files) {
        await downloadFile(
          f,
          cancel: cancel,
          onProgress: (got, all) {
            _downloads[key] = (
              received: before + got,
              total: total ?? (files.length == 1 ? all : null),
            );
            notifyListeners();
          },
        );
        before += File(f.path).lengthSync();
      }
    } on DownloadException catch (e) {
      problem = e.message;
    } on FileSystemException catch (e) {
      problem = '存不下来:${e.osError?.message ?? e.message}';
    }
    _downloads.remove(key);
    _cancels.remove(key);
    notifyListeners();
    return problem;
  }

  void cancelDownload(String key) => _cancels[key]?.cancel();

  /// 删掉下载好的文件(连同没下完的)。删不了时返回给用户看的原因。
  Future<String?> remove(List<RemoteFile> files) async {
    final paths = {for (final f in files) f.path};
    if (server.running &&
        (paths.contains(modelPath) || paths.contains(mmprojPath))) {
      return '这个模型正在用,先停止服务';
    }
    if (_tagging && paths.any((p) => p.endsWith(taggerModelFile))) {
      return '正在推理';
    }
    if (paths.any((p) => p.endsWith(taggerModelFile))) _dropTagger();
    if (paths.any((p) => _florenceFor != null && p.startsWith(_florenceFor!))) {
      _dropFlorence();
    }
    String? problem;
    try {
      for (final path in paths) {
        for (final file in [File(path), File('$path.part')]) {
          if (file.existsSync()) await file.delete();
        }
      }
    } on FileSystemException catch (e) {
      problem = '删不掉:${e.osError?.message ?? e.message}';
    }
    // 选着的模型删掉了就不再指着它。
    if (paths.contains(modelPath) || paths.contains(mmprojPath)) {
      update(() {
        if (paths.contains(modelPath)) modelPath = '';
        if (paths.contains(mmprojPath)) mmprojPath = '';
      });
    } else {
      notifyListeners();
    }
    return problem;
  }

  /// 下载并解开 llama.cpp 运行时。
  Future<String?> downloadRuntime() async {
    final zip = _runtimeZip;
    final problem = await download('runtime', [zip]);
    if (problem != null) return problem;
    // 先解到旁边的临时文件夹,全解完才换上:解到一半失败时不会留下缺文件的运行时。
    // 解压放到另一个 isolate 里,界面不卡。
    final target = _runtimeDir.path;
    final temp = '$target.tmp';
    try {
      final from = zip.path;
      await Isolate.run(() => _extractInto(from, temp, target));
      await File(zip.path).delete();
    } on Object catch (e) {
      // 下好的压缩包留着,再点一次直接重新解压。
      return '运行时解压失败(${e.runtimeType})';
    }
    notifyListeners();
    return serverExe == null ? '运行时里没找到 llama-server.exe' : null;
  }

  // —— Tag ——

  /// 用选中的打标模型给当前的图打标。失败时返回给用户看的原因。
  Future<String?> runTagger() async {
    final image = _image;
    if (image == null) return '先放一张图';
    if (_tagging) return '正在推理';
    final paths = taggerPaths(tagger);
    if (paths == null) return '先下载模型';
    _tagging = true;
    final round = _round;
    notifyListeners();
    String? problem;
    try {
      if (_taggerFor != tagger.repo) {
        _dropTagger();
        _labels = parseSelectedTags(await File(paths.labels).readAsString());
        _tagger = await _loadOnnx(paths.model);
        _taggerFor = tagger.repo;
      }
      final model = _tagger!;
      final layout = inputLayout(model.inputShape);
      final pixels = await decodeImage(image.bytes!, layout.size);
      final input = letterboxBgr(
        pixels.rgba,
        pixels.width,
        pixels.height,
        size: layout.size,
        nchw: layout.nchw,
      );
      final scores = await model.run(
        input,
        layout.nchw
            ? [1, 3, layout.size, layout.size]
            : [1, layout.size, layout.size, 3],
      );
      // 推理途中换了图:这次的结果不是眼前这张图的。
      if (round == _round) {
        _scores = scores;
        _refilter();
      }
    } on OnnxException catch (e) {
      problem = e.message;
      _dropTagger();
    } on FileSystemException catch (e) {
      problem = '读不了模型文件:${e.osError?.message ?? e.message}';
    } on Object catch (e) {
      problem = '推理失败(${e.runtimeType})';
    }
    _tagging = false;
    notifyListeners();
    return round == _round ? problem : null;
  }

  void _dropTagger() {
    final old = _tagger;
    _tagger = null;
    _taggerFor = null;
    old?.close().catchError((Object _) {});
  }

  // —— 存盘 ——

  File? get _file => dir == null ? null : File('$_home${_sep}local.json');

  Map<String, Object> toJson() => {
    'source': source,
    'taggerRepo': taggerRepo,
    'general': general,
    'character': character,
    'exePath': exePath,
    'modelPath': modelPath,
    'mmprojPath': mmprojPath,
    'port': port,
    'context': context,
    'gpuLayers': gpuLayers,
    'captionPrompt': captionPrompt,
    'modelFolders': modelFolders,
    'taggerOrder': taggerOrder,
    'captionOrder': captionOrder,
    'quantPicks': quantPicks,
    'captionPick': captionPick,
    'florenceTask': florenceTask,
  };

  void _save() {
    final file = _file;
    if (file == null) return;
    try {
      file.parent.createSync(recursive: true);
      file.writeAsStringSync(jsonEncode(toJson()));
    } on FileSystemException catch (e) {
      debugPrint('本地推理的设置没存上:${e.message}');
    }
  }

  Future<void> load() async {
    final file = _file;
    if (file == null || !file.existsSync()) return;
    try {
      final j = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      source = j['source'] as String? ?? source;
      taggerRepo = j['taggerRepo'] as String? ?? taggerRepo;
      general = (j['general'] as num?)?.toDouble() ?? general;
      character = (j['character'] as num?)?.toDouble() ?? character;
      exePath = j['exePath'] as String? ?? '';
      modelPath = j['modelPath'] as String? ?? '';
      mmprojPath = j['mmprojPath'] as String? ?? '';
      port = j['port'] as int? ?? port;
      context = j['context'] as int? ?? context;
      gpuLayers = j['gpuLayers'] as int? ?? gpuLayers;
      captionPrompt = j['captionPrompt'] as String? ?? captionPrompt;
      modelFolders = List.unmodifiable([
        for (final f in j['modelFolders'] as List? ?? const []) f as String,
      ]);
      List<String> strings(String key) => List.unmodifiable([
        for (final v in j[key] as List? ?? const []) v as String,
      ]);
      taggerOrder = strings('taggerOrder');
      captionOrder = strings('captionOrder');
      quantPicks = Map.unmodifiable(
        (j['quantPicks'] as Map? ?? const {}).cast<String, String>(),
      );
      captionPick = j['captionPick'] as String? ?? '';
      florenceTask = j['florenceTask'] as String? ?? florenceTask;
      // 不等它扫完:文件夹大的话要好一会儿,不拦着程序启动。
      if (modelFolders.isNotEmpty) rescan();
      notifyListeners();
    } on Object {
      // 读不了就用默认设置,不拦着程序启动。
    }
  }

  @override
  void dispose() {
    for (final c in _cancels.values) {
      c.cancel();
    }
    _dropTagger();
    _dropFlorence();
    server.stop();
    super.dispose();
  }
}

/// 读出图片的像素,缩到长边不超过 [size](不放大);[stretch] 为真时直接拉成 [size]×[size]。
/// 透明度是没乘进颜色的。
Future<({Uint8List rgba, int width, int height})> decodeImage(
  Uint8List bytes,
  int size, {
  bool stretch = false,
}) async {
  final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
  final descriptor = await ui.ImageDescriptor.encoded(buffer);
  final fit = stretch
      ? (width: size, height: size)
      : fitInside(descriptor.width, descriptor.height, size);
  final codec = await descriptor.instantiateCodec(
    targetWidth: fit.width,
    targetHeight: fit.height,
  );
  final frame = await codec.getNextFrame();
  final data = await frame.image.toByteData(
    format: ui.ImageByteFormat.rawStraightRgba,
  );
  frame.image.dispose();
  codec.dispose();
  descriptor.dispose();
  buffer.dispose();
  if (data == null) throw const OnnxException('读不了这张图');
  return (
    rgba: data.buffer.asUint8List(),
    width: fit.width,
    height: fit.height,
  );
}

/// 把 [zip] 解到 [temp],全解完再换成 [target]。
Future<void> _extractInto(String zip, String temp, String target) async {
  final dir = Directory(temp);
  if (dir.existsSync()) dir.deleteSync(recursive: true);
  await extractFileToDisk(zip, temp);
  final old = Directory(target);
  if (old.existsSync()) old.deleteSync(recursive: true);
  dir.renameSync(target);
}
