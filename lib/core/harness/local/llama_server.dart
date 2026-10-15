import 'dart:async';
import 'dart:convert';
import 'dart:io';

// 本地自然语言反推:在本机起一个 llama.cpp 的 llama-server,加载 GGUF 视觉模型,
// 之后和联网的模型一样走 OpenAI 兼容接口。做法照 NLapt 的 nlapt/local/server.py。

/// 固定用的 llama.cpp 版本。Vulkan 版一个程序就能用 N 卡、A 卡、核显,没有显卡时退回 CPU。
/// 大小和 SHA256 取自 GitHub 发布页,换版本时三样一起改。
const llamaCppTag = 'b10088';
const llamaRuntimeFile = 'llama-$llamaCppTag-bin-win-vulkan-x64.zip';
const llamaRuntimeSize = 33290390;
const llamaRuntimeSha256 =
    'ced37906bfa57dca6079b0e66163edc4f319b43ba8260bda5427fbd20a08324b';
const llamaRuntimeUrl =
    'https://github.com/ggml-org/llama.cpp/releases/download/$llamaCppTag/$llamaRuntimeFile';

/// 一个可以一键下载的看图模型:模型本体和视觉组件(mmproj)。大小和 SHA256 取自 HuggingFace。
typedef CaptionModel = ({
  String id,
  String name,
  String note,
  String repo,
  String file,
  int size,
  String sha256,
  String mmproj,
  int mmprojSize,
  String mmprojSha256,
});

/// 内置的几个看图模型,都是各自推荐的 4 位量化。清单取自 NLapt 的 catalog.py。
const captionModels = <CaptionModel>[
  (
    id: 'gemma4-e4b',
    name: 'Gemma 4 E4B',
    note: '通用 · 约 6 GB',
    repo: 'unsloth/gemma-4-E4B-it-GGUF',
    file: 'gemma-4-E4B-it-Q4_K_M.gguf',
    size: 4977171584,
    sha256: '85a896a047553e842f25297ee5b031d64ff30147d9c4af17b1e4b394cd1fab87',
    mmproj: 'mmproj-F16.gguf',
    mmprojSize: 990372672,
    mmprojSha256:
        'ddf46c21d7078e95338cfc22306b19b276a29a5ad089023449dd54d4b6170a51',
  ),
  (
    id: 'gemma4-e4b-heretic',
    name: 'Gemma 4 E4B Heretic',
    note: '去审查 · 约 6.3 GB',
    repo: 'llmfan46/gemma-4-E4B-it-ultra-uncensored-heretic-GGUF',
    file: 'gemma-4-E4B-it-ultra-uncensored-heretic-Q4_K_M.gguf',
    size: 5335289696,
    sha256: 'f9dbbe3bdf396f65aec4e801516a1b868a510d96225417a8aa06763e3c5b97dc',
    mmproj: 'gemma-4-E4B-it-mmproj-BF16.gguf',
    mmprojSize: 991552000,
    mmprojSha256:
        'ffa64aebf7144bbadd5a1e143b77794d88e76a81cc0168d91de0770eb49e88e0',
  ),
  (
    id: 'toriigate-0.5',
    name: 'ToriiGate 0.5',
    note: '动漫插画 · 约 3.7 GB',
    repo: 'DraconicDragon/ToriiGate-0.5-GGUF',
    file: 'ToriiGate-0.5-Q4_K_M.gguf',
    size: 3066382176,
    sha256: '1dd18497b1a1ee19e5ca63a58efb4614bfd24abf80ee7fd796bbbe3bc1e20cef',
    mmproj: 'ToriiGate-0.5-fp16.mmproj.gguf',
    mmprojSize: 672423360,
    mmprojSha256:
        'e0470d4bff4e932ecf3c7bf3b937d51301722c5d17c43f7ad9dfc73b65808b9c',
  ),
  (
    id: 'joycaption-beta-one',
    name: 'JoyCaption Beta One',
    note: '写实照片 · 约 5.8 GB',
    repo: 'concedo/llama-joycaption-beta-one-hf-llava-mmproj-gguf',
    file: 'Llama-Joycaption-Beta-One-Hf-Llava-Q4_K.gguf',
    size: 4920735936,
    sha256: 'e8ae55dd07e61d541ab741d6ed63e7810192cea65d7ef8cda69b2a99fb06dc15',
    mmproj: 'llama-joycaption-beta-one-llava-mmproj-model-f16.gguf',
    mmprojSize: 877771808,
    mmprojSha256:
        '94002cb5c354c7c9e538e64f37d593db9eceeca2e94573bae6cd3b2bd8bb1952',
  ),
];

/// 在解开的运行时文件夹里找 llama-server.exe;有好几个时取层级最浅的。
File? findServerExe(Directory dir) {
  if (!dir.existsSync()) return null;
  final found =
      dir
          .listSync(recursive: true)
          .whereType<File>()
          .where(
            (f) => f.uri.pathSegments.last.toLowerCase() == 'llama-server.exe',
          )
          .toList()
        ..sort((a, b) => a.uri.pathSegments.length - b.uri.pathSegments.length);
  return found.firstOrNull;
}

/// 启动一个 llama-server 要的东西。[gpuLayers] 小于 0 表示全部放进显卡。
typedef ServerSpec = ({
  String exe,
  String model,
  String mmproj,
  int port,
  int context,
  int gpuLayers,
});

/// llama-server 的命令行参数(不经命令行解释,路径里有空格也没事)。
/// 关掉思考:会思考的模型(比如 Gemma 4)会把字数全花在思考上,回来的正文是空的。
List<String> serverArgs(ServerSpec s) => [
  '-m',
  s.model,
  '--host',
  '127.0.0.1',
  '--port',
  '${s.port}',
  '-c',
  '${s.context}',
  '-ngl',
  '${s.gpuLayers < 0 ? 999 : s.gpuLayers}',
  '--reasoning',
  'off',
  if (s.mmproj.isNotEmpty) ...['--mmproj', s.mmproj],
];

class LocalServerException implements Exception {
  const LocalServerException(this.message);

  final String message;

  @override
  String toString() => message;
}

typedef ProcessStarter = Future<Process> Function(
  String exe,
  List<String> args,
);

typedef HealthCheck = Future<bool> Function(Uri url);

/// 看 llama-server 准备好了没有:/health 回 200 才算(加载模型时回 503)。
Future<bool> _health(Uri url) async {
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 2);
  try {
    final response = await (await client.getUrl(url))
        .close()
        .timeout(const Duration(seconds: 2));
    await response.drain<void>();
    return response.statusCode == HttpStatus.ok;
  } on Object {
    return false;
  } finally {
    client.close(force: true);
  }
}

/// 管着最多一个 llama-server:起、等它就绪、停。
///
/// 用「分离、但接着输出管道」的方式起:窗口程序直接起控制台程序时,
/// Windows 会给它弹一个黑框,用户关掉黑框服务就没了。分离的进程拿不到退出码,
/// 所以靠错误输出关上来判断它退出了。
class LlamaServer {
  LlamaServer({ProcessStarter? start, HealthCheck? health})
    : _start =
          start ??
          ((exe, args) => Process.start(
            exe,
            args,
            mode: ProcessStartMode.detachedWithStdio,
          )),
      _isHealthy = health ?? _health;

  final ProcessStarter _start;
  final HealthCheck _isHealthy;

  /// 服务自己退出了(不是 [stop] 停的)时调,好让界面跟着变。
  void Function()? onExit;

  Process? _process;
  ServerSpec? _spec;
  Future<void>? _exited;

  /// 用户用 [stop] 停掉的那个;启动途中被停时据此说「已停止」而不是「退出了」。
  Process? _stopped;

  /// 最近几行错误输出,启动失败时拿来告诉用户为什么。
  final _tail = <String>[];

  bool get running => _process != null;
  ServerSpec? get spec => _spec;

  /// 正在跑时的 OpenAI 兼容地址。
  String? get baseUrl =>
      _spec == null ? null : 'http://127.0.0.1:${_spec!.port}/v1';

  /// 起一个 llama-server 并等到它能用,返回接口地址。已经在跑的先停掉。
  Future<String> start(
    ServerSpec spec, {
    Duration timeout = const Duration(minutes: 3),
    Duration poll = const Duration(milliseconds: 500),
  }) async {
    for (final (path, what) in [
      (spec.exe, 'llama-server'),
      (spec.model, '模型文件'),
      if (spec.mmproj.isNotEmpty) (spec.mmproj, '视觉组件'),
    ]) {
      if (!File(path).existsSync()) {
        throw LocalServerException('找不到$what:$path');
      }
    }
    await stop();
    // 端口被别的程序(比如上次没关掉的 llama-server)占着时,新起的会马上退出,
    // 而 /health 却可能是那个旧程序在回答,看着像起来了。先试着占一下这个端口。
    try {
      await (await ServerSocket.bind(
        InternetAddress.loopbackIPv4,
        spec.port,
      )).close();
    } on SocketException {
      throw LocalServerException('端口 ${spec.port} 被占用了,换一个端口,或先关掉占着它的程序');
    }
    _tail.clear();
    final Process process;
    try {
      process = await _start(spec.exe, serverArgs(spec));
    } on ProcessException {
      throw const LocalServerException('启动不了 llama-server');
    }
    _process = process;
    _spec = spec;
    // 不读走输出的话,程序写满缓冲区会卡住。
    unawaited(process.stdout.drain<void>().catchError((Object _) {}));
    var exited = false;
    final done = Completer<void>();
    _exited = done.future;
    process.stderr
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(
          (line) {
            _tail.add(line);
            if (_tail.length > 8) _tail.removeAt(0);
          },
          onError: (Object _) {},
          onDone: () {
            exited = true;
            done.complete();
            // 跑着跑着自己退出了(比如崩了):当成停了。
            if (_process == process) {
              _clear(process);
              onExit?.call();
            }
          },
        );
    final health = Uri.parse('http://127.0.0.1:${spec.port}/health');
    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      if (_stopped == process) {
        throw const LocalServerException('已停止');
      }
      if (exited) {
        final why = _tail.where((l) => l.trim().isNotEmpty).lastOrNull;
        throw LocalServerException(
          'llama-server 启动后退出了'
          '${why == null ? '' : ':${_short(why)}'}。'
          '常见原因是显存不够,可以调低 GPU 层数或上下文长度',
        );
      }
      if (await _isHealthy(health) && _process == process) return baseUrl!;
      await Future<void>.delayed(poll);
    }
    await stop();
    throw const LocalServerException('等了很久还没准备好,已停下');
  }

  void _clear(Process process) {
    if (_process != process) return;
    _process = null;
    _spec = null;
  }

  /// 停掉正在跑的 llama-server;没在跑就什么也不做。
  Future<void> stop() async {
    final process = _process;
    if (process == null) return;
    _stopped = process;
    _clear(process);
    process.kill();
    await _exited?.timeout(const Duration(seconds: 10), onTimeout: () {});
  }
}

String _short(String line) =>
    line.length > 160 ? '${line.substring(0, 160)}…' : line;
