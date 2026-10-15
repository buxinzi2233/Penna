import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:penna/core/harness/attachment.dart';
import 'package:penna/core/harness/local/caption_catalog.dart';
import 'package:penna/core/harness/local/download.dart';
import 'package:penna/core/harness/local/florence.dart';
import 'package:penna/core/harness/local/llama_server.dart';
import 'package:penna/core/harness/local/model_scan.dart';
import 'package:penna/core/harness/local/tagger.dart';
import 'package:penna/core/harness/providers/llm_http.dart';
import 'package:penna/ui/features/local/local_model.dart';
import 'package:penna/ui/features/local/local_page.dart';
import 'package:penna/ui/features/studio/studio_view_model.dart';
import 'package:penna/ui/shell.dart';

import 'fixtures.dart';

/// 假的 llama-server 进程:不真的起程序,[exit] 之后算退出。
class _FakeProcess implements Process {
  final _exit = Completer<int>();
  final _err = StreamController<List<int>>();
  bool killed = false;

  void exit(int code, [String stderr = '']) {
    _err.add(utf8.encode(stderr));
    _err.close();
    _exit.complete(code);
  }

  @override
  Future<int> get exitCode => _exit.future;
  @override
  Stream<List<int>> get stdout => const Stream.empty();
  @override
  Stream<List<int>> get stderr => _err.stream;
  @override
  IOSink get stdin => throw UnimplementedError();
  @override
  int get pid => 1;
  @override
  bool kill([ProcessSignal signal = ProcessSignal.sigterm]) {
    killed = true;
    if (!_exit.isCompleted) exit(-1);
    return true;
  }
}

/// 临时文件夹里放好假的 llama-server.exe 和模型,返回启动参数。
ServerSpec _spec(Directory dir) {
  for (final name in ['llama-server.exe', 'm.gguf']) {
    File('${dir.path}/$name').writeAsStringSync('x');
  }
  return (
    exe: '${dir.path}/llama-server.exe',
    model: '${dir.path}/m.gguf',
    mmproj: '',
    port: 8091,
    context: 4096,
    gpuLayers: -1,
  );
}

void main() {
  late Directory tmp;
  setUp(() => tmp = Directory.systemTemp.createTempSync('penna_local'));
  tearDown(() => tmp.deleteSync(recursive: true));

  group('打标模型', () {
    test('标签表:v3 和老版本的写法都认,表头跳过', () {
      expect(
        parseSelectedTags(
          'tag_id,name,category,count\n9999999,general,9,1\n1,long_hair,0,5\n'
          '2,hatsune_miku,4,3\n',
        ),
        [
          (name: 'general', category: 9),
          (name: 'long_hair', category: 0),
          (name: 'hatsune_miku', category: 4),
        ],
      );
      expect(parseSelectedTags('name,category\nsmile,0\r\n'), [
        (name: 'smile', category: 0),
      ]);
    });

    test('输入的形状:通道在后或在前', () {
      expect(inputLayout([1, 448, 448, 3]), (size: 448, nchw: false));
      expect(inputLayout([-1, 448, 448, 3]), (size: 448, nchw: false));
      expect(inputLayout([1, 3, 384, 384]), (size: 384, nchw: true));
      expect(inputLayout([]), (size: 448, nchw: false));
      expect(fitInside(1000, 500, 448), (width: 448, height: 224));
      expect(fitInside(100, 50, 448), (width: 100, height: 50));
    });

    test('贴到白底正中,透明的算白色,输出 BGR', () {
      // 1×2 的图:上面一个不透明的红点,下面一个全透明的点。
      final rgba = Uint8List.fromList([255, 0, 0, 255, 0, 0, 0, 0]);
      final out = letterboxBgr(rgba, 1, 2, size: 2);
      // 宽 1 放在第 0 列(左右各空 0.5 取整),上面一行是红点。
      expect(out.sublist(0, 3), [0, 0, 255]);
      expect(out.sublist(3, 6), [255, 255, 255]);
      expect(out.sublist(6, 9), [255, 255, 255]);

      final planes = letterboxBgr(rgba, 1, 2, size: 2, nchw: true);
      // 通道在前:B、G、R 各一整块,红点在每块的第 0 个。
      expect([planes[0], planes[4], planes[8]], [0, 0, 255]);
    });

    test('按阈值筛:角色、通用分开,分级取把握最大的;没过 sigmoid 的先补上', () {
      const labels = [
        (name: 'general', category: tagRating),
        (name: 'sensitive', category: tagRating),
        (name: 'long_hair', category: tagGeneral),
        (name: 'smile', category: tagGeneral),
        (name: 'hatsune_miku', category: tagCharacter),
      ];
      final r = decodeTags(
        [0.2, 0.7, 0.4, 0.9, 0.95],
        labels,
        general: 0.35,
        character: 0.85,
      );
      expect(r.rating, 'sensitive');
      expect(r.characters.map((t) => t.tag), ['hatsune_miku']);
      expect(r.general.map((t) => t.tag), ['smile', 'long_hair']);
      expect(tagPrompt(r), 'hatsune miku, smile, long hair');

      final logits = decodeTags(
        [-5, -5, 3, -3, -1],
        labels,
        general: 0.5,
        character: 0.85,
      );
      expect(logits.general.map((t) => t.tag), ['long_hair']);
      expect(logits.characters, isEmpty);
    });

    test('颜文字的下划线留着', () {
      expect(tagText('^_^'), '^_^');
      expect(tagText('looking_at_viewer'), 'looking at viewer');
    });
  });

  group('llama-server', () {
    test('参数:-1 层是全部放进显卡,有视觉组件才带 --mmproj', () {
      final spec = (
        exe: 'a.exe',
        model: 'm.gguf',
        mmproj: 'p.gguf',
        port: 9000,
        context: 2048,
        gpuLayers: -1,
      );
      final args = serverArgs(spec);
      expect(args.join(' '), contains('-ngl 999'));
      expect(args.join(' '), contains('--port 9000'));
      expect(args.sublist(args.length - 2), ['--mmproj', 'p.gguf']);
      expect(
        serverArgs((
          exe: 'a.exe',
          model: 'm.gguf',
          mmproj: '',
          port: 9000,
          context: 2048,
          gpuLayers: 20,
        )),
        isNot(contains('--mmproj')),
      );
    });

    test('等到 /health 通了才算起来;停掉会结束进程', () async {
      final process = _FakeProcess();
      var polls = 0;
      final server = LlamaServer(
        start: (_, _) async => process,
        health: (_) async => ++polls >= 3,
      );

      final url = await server.start(_spec(tmp), poll: Duration.zero);

      expect(url, 'http://127.0.0.1:8091/v1');
      expect(server.running, isTrue);
      await server.stop();
      expect(process.killed, isTrue);
      expect(server.running, isFalse);
    });

    test('起来后马上退出:报出最后一行输出', () async {
      final process = _FakeProcess();
      final server = LlamaServer(
        start: (_, _) async {
          scheduleMicrotask(() => process.exit(1, 'loading\nout of memory\n'));
          return process;
        },
        health: (_) async => false,
      );

      await expectLater(
        server.start(_spec(tmp), poll: const Duration(milliseconds: 5)),
        throwsA(
          isA<LocalServerException>().having(
            (e) => e.message,
            'message',
            allOf(contains('退出了'), contains('out of memory')),
          ),
        ),
      );
      expect(server.running, isFalse);
    });

    test('加载途中点停止:说「已停止」,不当成崩了', () async {
      final server = LlamaServer(
        start: (_, _) async => _FakeProcess(),
        health: (_) async => false,
      );

      final starting = server.start(
        _spec(tmp),
        poll: const Duration(milliseconds: 5),
      );
      // 先挂上判断,不然它报错时还没人接。
      final check = expectLater(
        starting,
        throwsA(
          isA<LocalServerException>().having(
            (e) => e.message,
            'message',
            '已停止',
          ),
        ),
      );
      // 等它真的起了进程、开始等 /health 再停。
      while (!server.running) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
      await server.stop();
      await check;
    });

    test('找不到文件时不启动', () async {
      final server = LlamaServer(start: (_, _) => fail('不该启动'));
      await expectLater(
        server.start((
          exe: '${tmp.path}/none.exe',
          model: 'm',
          mmproj: '',
          port: 1,
          context: 1,
          gpuLayers: 0,
        )),
        throwsA(isA<LocalServerException>()),
      );
    });

    test('在解开的运行时里找最浅的 llama-server.exe', () {
      Directory('${tmp.path}/a/b').createSync(recursive: true);
      File('${tmp.path}/a/b/llama-server.exe').writeAsStringSync('');
      File('${tmp.path}/a/llama-server.exe').writeAsStringSync('');
      expect(
        findServerExe(tmp)!.path.replaceAll('\\', '/'),
        endsWith('/a/llama-server.exe'),
      );
      expect(findServerExe(Directory('${tmp.path}/none')), isNull);
    });
  });

  group('下载', () {
    // 这个文件里有 testWidgets,Flutter 会拦掉真实的网络请求;这组要连本机的假服务器。
    setUp(() => HttpOverrides.global = null);

    late HttpServer http;
    final body = List.generate(1000, (i) => i % 251);
    final ranges = <String?>[];

    setUp(() async {
      ranges.clear();
      http = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      http.listen((request) async {
        final range = request.headers.value(HttpHeaders.rangeHeader);
        ranges.add(range);
        if (request.uri.path == '/missing') {
          request.response.statusCode = 404;
        } else if (range != null) {
          final from = int.parse(range.split('=')[1].split('-')[0]);
          request.response.statusCode = HttpStatus.partialContent;
          request.response.add(body.sublist(from));
        } else {
          request.response.add(body);
        }
        await request.response.close();
      });
    });
    tearDown(() => http.close(force: true));

    RemoteFile file({String path = '/f', String? sha}) => (
      url: 'http://127.0.0.1:${http.port}$path',
      path: '${tmp.path}/out.bin',
      size: body.length,
      sha256: sha,
    );

    test('从断开的地方接着下;校验通过才改成正式的名字', () async {
      File('${tmp.path}/out.bin.part').writeAsBytesSync(body.sublist(0, 400));
      final seen = <int>[];

      await downloadFile(
        file(sha: '${sha256.convert(body)}'),
        onProgress: (got, _) => seen.add(got),
      );

      expect(ranges, ['bytes=400-']);
      expect(File('${tmp.path}/out.bin').readAsBytesSync(), body);
      expect(File('${tmp.path}/out.bin.part').existsSync(), isFalse);
      expect(seen.last, 1000);
      expect(isDownloaded(file()), isTrue);
    });

    test('校验不对就删掉;找不到文件说人话', () async {
      await expectLater(
        downloadFile(file(sha: '00')),
        throwsA(
          isA<DownloadException>().having(
            (e) => e.message,
            'message',
            contains('校验'),
          ),
        ),
      );
      expect(File('${tmp.path}/out.bin.part').existsSync(), isFalse);
      expect(File('${tmp.path}/out.bin').existsSync(), isFalse);

      await expectLater(
        downloadFile(file(path: '/missing')),
        throwsA(
          isA<DownloadException>().having(
            (e) => e.message,
            'message',
            contains('404'),
          ),
        ),
      );
    });
  });

  group('模型文件夹', () {
    /// 在 [root] 下放好一堆文件(路径用 / 分隔),内容随便。
    void files(Directory root, List<String> paths) {
      for (final p in paths) {
        File('${root.path}/$p')
          ..createSync(recursive: true)
          ..writeAsStringSync('x');
      }
    }

    late Directory root;
    setUp(() {
      root = Directory('${tmp.path}/models')..createSync();
      files(root, [
        // BooruDatasetTagManagerPlus 的放法
        'bdtm/Models/SmilingWolf/wd-vit-tagger-v3/model.onnx',
        'bdtm/Models/SmilingWolf/wd-vit-tagger-v3/selected_tags.csv',
        // HuggingFace 缓存
        'hf/hub/models--SmilingWolf--wd-swinv2-tagger-v3/snapshots/'
            '0123456789abcdef0123/model.onnx',
        'hf/hub/models--SmilingWolf--wd-swinv2-tagger-v3/snapshots/'
            '0123456789abcdef0123/selected_tags.csv',
        // 不在清单里的 WD 模型
        'other/my-tagger/model.onnx',
        'other/my-tagger/selected_tags.csv',
        // CL v1 放在仓库的子文件夹里
        'hf/Nonene/cl_tagger/cl_tagger_1_02/model.onnx',
        'hf/Nonene/cl_tagger/cl_tagger_1_02/tag_mapping.json',
        // 只有模型、没有标签表的不算
        'half/model.onnx',
        // NLapt 的放法
        'nlapt/toriigate-0.5/ToriiGate-0.5-Q4_K_M.gguf',
        'nlapt/toriigate-0.5/ToriiGate-0.5-fp16.mmproj.gguf',
        // 别的 GGUF,配同文件夹的视觉组件
        'llm/qwen/qwen-vl.gguf',
        'llm/qwen/mmproj-qwen.gguf',
        'llm/text-only.gguf',
        'bin/llama-server.exe',
        // 跳过的文件夹
        'node_modules/x/model.gguf',
      ]);
    });

    test('一层层往下找;认得清单里的模型,跳过 node_modules', () {
      final f = scanModelFolders([root.path]);

      expect(f.taggers, hasLength(4));
      expect(f.taggers.map(catalogTaggerFor).toSet(), {
        'SmilingWolf/wd-vit-tagger-v3',
        'SmilingWolf/wd-swinv2-tagger-v3',
        'cl:Nonene/cl_tagger:1_02',
        null,
      });
      expect(f.ggufs.map(fileName).toSet(), {
        'ToriiGate-0.5-Q4_K_M.gguf',
        'qwen-vl.gguf',
        'text-only.gguf',
      });
      expect(f.mmprojs, hasLength(2));
      expect(f.servers, hasLength(1));
      expect(f.truncated, isFalse);
      expect(
        folderTitle(
          '${root.path}/hf/hub/models--SmilingWolf--wd-swinv2-tagger-v3/'
          'snapshots/0123456789abcdef0123',
        ),
        'wd-swinv2-tagger-v3',
      );
      // 条目太多时停下,说一声。
      expect(scanModelFolders([root.path], maxEntries: 3).truncated, isTrue);
    });

    test('找到的直接能用:打标模型、看图模型、llama-server,不在清单里的也列出来', () async {
      final model = LocalModel(
        dir: tmp,
        streamChat: (_) => const Stream.empty(),
      );
      expect(model.taggerPaths(taggerModels.first), isNull);

      model.addFolder(root.path);
      while (model.scanning) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }

      // ViT v3 在 BDTM 的文件夹里找到了,不用下。
      final vit = taggerModels.firstWhere(
        (m) => m.id == 'SmilingWolf/wd-vit-tagger-v3',
      );
      expect(model.taggerPaths(vit)!.model, endsWith('model.onnx'));
      // 不在清单里的那个也能选,阈值用默认值。
      final mine = model.taggers.firstWhere((m) => m.name == '[本机] my-tagger');
      expect(
        (mine.general, mine.series, mine.kind),
        (0.35, '本机', TaggerKind.wd),
      );
      expect(model.taggerPaths(mine), isNotNull);
      // CL 的标签表是 tag_mapping.json。
      final cl = taggerModels.firstWhere((m) => m.kind == TaggerKind.clV1);
      expect(model.taggerPaths(cl)!.labels, endsWith('tag_mapping.json'));

      final torii = captionModels.firstWhere((m) => m.id == 'toriigate-0.5');
      expect(model.useCaption(torii), isTrue);
      expect(model.modelPath, endsWith('ToriiGate-0.5-Q4_K_M.gguf'));
      expect(model.mmprojPath, endsWith('ToriiGate-0.5-fp16.mmproj.gguf'));

      expect(
        {
          for (final g in model.foundGgufs)
            fileName(g.model): fileName(g.mmproj),
        },
        {'qwen-vl.gguf': 'mmproj-qwen.gguf', 'text-only.gguf': ''},
      );
      expect(model.serverExe, endsWith('llama-server.exe'));

      // 文件夹存盘后还在,重开时自动再扫一遍。
      final again = LocalModel(
        dir: tmp,
        streamChat: (_) => const Stream.empty(),
      );
      await again.load();
      expect(again.modelFolders, [root.path]);
      while (again.scanning) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      expect(again.found.taggers, hasLength(4));

      model.removeFolder(root.path);
      while (model.scanning) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      expect(model.taggerPaths(vit), isNull);
    });
  });

  group('各种打标模型', () {
    test('标签表:PixAI 的 csv 和 tags.json、CL 的两种 json、OppaiOracle 的 csv', () {
      expect(
        parseLabels(
          TaggerKind.pixai09,
          'id,tag_id,name,category\n0,5,smile,0\n1,6,miku,4',
        ),
        [(name: 'smile', category: 0), (name: 'miku', category: 4)],
      );
      expect(
        parseLabels(
          TaggerKind.pixai10,
          jsonEncode({
            'categories': [
              {
                'name': 'character',
                'offset': 1,
                'count': 1,
                'tags': ['miku'],
              },
              {
                'name': 'general',
                'offset': 0,
                'count': 1,
                'tags': ['smile'],
              },
            ],
          }),
        ),
        [
          (name: 'smile', category: tagGeneral),
          (name: 'miku', category: tagCharacter),
        ],
      );
      expect(
        parseLabels(
          TaggerKind.clV1,
          jsonEncode({
            '1': {'tag': 'miku', 'category': 'Character'},
            '0': {'tag': 'smile', 'category': 'General'},
          }),
        ),
        [
          (name: 'smile', category: tagGeneral),
          (name: 'miku', category: tagCharacter),
        ],
      );
      expect(
        parseLabels(
          TaggerKind.clV2,
          jsonEncode({
            'idx_to_tag': {'0': 'smile', '1': 'miku', '2': 'oc'},
            'tag_to_category': {
              'smile': 'General',
              'miku': 1,
              'oc': 'Copyright',
            },
          }),
        ),
        [
          (name: 'smile', category: tagGeneral),
          (name: 'miku', category: tagCharacter),
          (name: 'oc', category: tagCopyright),
        ],
      );
      final oo = parseLabels(
        TaggerKind.oppai,
        'tag_id,name\n0,<PAD>\n1,smile\n2,rating:safe',
      );
      expect([for (final l in oo) l.category], [-1, tagGeneral, -1]);
    });

    test('只留通用和角色;logits 过 sigmoid;skip 里的不要', () {
      const labels = [
        (name: 'smile', category: tagGeneral),
        (name: 'oc', category: tagCopyright),
        (name: 'gray_background', category: tagGeneral),
      ];
      final r = decodeTags(
        [3, 3, 3],
        labels,
        general: 0.5,
        character: 0.5,
        logits: true,
        skip: {'gray_background'},
      );
      expect(r.general.map((t) => t.tag), ['smile']);
      expect(r.general.single.prob, closeTo(0.9526, 1e-3));
    });

    test('预处理:PixAI v1.0 黑底、OppaiOracle 灰底加掩码、CL v1 用 BGR', () {
      // 1×1 的红点贴到 3×3 的画布正中。
      final red = Uint8List.fromList([255, 0, 0, 255]);
      double norm(int v) => (v / 255 - 0.5) / 0.5;

      final pixai = prepareTaggerInput(TaggerKind.pixai10, red, 1, 1, size: 3);
      expect(pixai.shape, [1, 3, 3, 3]);
      expect(pixai.pixels[0], norm(0)); // 角上是黑色
      expect(pixai.pixels[4], norm(255)); // 正中 R 通道是红

      final oo = prepareTaggerInput(TaggerKind.oppai, red, 1, 1, size: 3);
      expect(oo.pixels[0], closeTo(norm(114), 1e-6));
      expect(oo.mask, [true, true, true, true, false, true, true, true, true]);

      final cl = prepareTaggerInput(TaggerKind.clV1, red, 1, 1, size: 3);
      // BGR:第 0 个通道是蓝色,红点那里是 0。
      expect(cl.pixels[4], norm(0));
      expect(cl.pixels[2 * 9 + 4], norm(255));

      expect(taggerImageSize(TaggerKind.pixai10, 200, 100, 1008), (
        width: 1008,
        height: 504,
      ));
      expect(taggerImageSize(TaggerKind.oppai, 200, 100, 448), (
        width: 200,
        height: 100,
      ));
      expect(taggerImageSize(TaggerKind.clV2, 200, 100, 384), (
        width: 384,
        height: 384,
      ));
    });
  });

  group('Florence-2', () {
    // 一个很小的 BPE 词表:单个字母,加上 "Wh"、"Wha"、"What" 三条合并;Ġ 是空格。
    const tokenizer = '''{
      "model": {
        "vocab": {"<s>": 0, "<pad>": 1, "</s>": 2, "W": 3, "h": 4, "a": 5,
          "t": 6, "Wh": 7, "Wha": 8, "What": 9, "Ġ": 10, "Ġa": 11},
        "merges": ["W h", "Wh a", "Wha t", "Ġ a"]
      },
      "added_tokens": [{"id": 12, "content": "<loc_1>"}]
    }''';

    test('分词:按合并规则拼词,首尾套上 <s> </s>;解码去掉特殊符号', () {
      final t = FlorenceTokenizer.parse(tokenizer);
      expect(t.encode('What a'), [9, 11]);
      expect(t.encodePrompt('What'), [florenceBos, 9, florenceEos]);
      expect(t.decode([0, 9, 11, 12, 2]), 'What a<loc_1>');
      expect(
        () => FlorenceTokenizer.parse('{}'),
        throwsA(isA<FlorenceException>()),
      );
    });

    test('防重复:出了就会重复一个三连词的那个字不能出;挑最大的时跳过它', () {
      expect(bannedNext([5, 6, 7, 5, 6]), {7});
      expect(bannedNext([5, 6]), isEmpty);
      expect(argmaxExcept([0.1, 0.9, 0.5], {1}), 2);
    });

    test('指令:官方的几个换成英文问句,PromptGen 的原样', () {
      expect(florencePrompt('<CAPTION>'), 'What does the image describe?');
      expect(florencePrompt('<GENERATE_TAGS>'), '<GENERATE_TAGS>');
    });

    test('像素:透明算白,按 ImageNet 均值方差归一化,通道在前', () {
      // 1×1:一个全透明的点 → 白色。
      final px = florencePixels(Uint8List.fromList([0, 0, 0, 0]), 1);
      expect(px[0], closeTo((1 - 0.485) / 0.229, 1e-5));
      expect(px[2], closeTo((1 - 0.406) / 0.225, 1e-5));
    });
  });

  group('模型清单、量化档与排序', () {
    LocalModel fresh() =>
        LocalModel(dir: tmp, streamChat: (_) => const Stream.empty());
    CaptionModel byId(String id) => captionModels.firstWhere((m) => m.id == id);

    test('清单只收能看图的;默认用推荐档,选过的档存盘后还在', () async {
      expect(
        captionModels.map((m) => m.id),
        isNot(contains('gemma4-26b-a4b-heretic')),
      );
      expect(
        captionModels.every((m) => m.florence || m.mmproj != null),
        isTrue,
      );

      final model = fresh();
      final gemma = byId('gemma4-e4b');
      expect(model.quantOf(gemma).label, 'Q4_K_M');
      model.pickQuant(gemma, 'Q8_0');
      expect(
        fileName(model.captionFiles(gemma).first.path),
        'gemma-4-E4B-it-Q8_0.gguf',
      );
      // GGUF:本体 + 视觉组件;Florence-2:解码器 + 另外三个 ONNX + 分词器。
      expect(model.captionFiles(gemma), hasLength(2));
      expect(model.captionFiles(byId('florence2-base-ft')), hasLength(5));

      final again = fresh();
      await again.load();
      expect(again.quantOf(gemma).label, 'Q8_0');
    });

    test('按系列分组;整组拖、组里拖都存盘后还在', () async {
      final model = fresh();
      expect(
        [for (final g in model.taggerGroups) g.series],
        ['WD14', 'PixAI', 'CL', 'OppaiOracle'],
      );
      expect(
        [for (final g in model.captionGroups) g.series],
        [
          'Gemma 4',
          'Gemma 4 · Heretic',
          'ToriiGate',
          'JoyCaption',
          'Florence-2',
        ],
      );
      // 把 OppaiOracle 整组挪到最前;WD14 组里把第一个挪到第三个。
      model.moveTagger(null, 3, 0);
      final first = model.taggerGroups[1].items.first.id;
      model.moveTagger(1, 0, 2);
      // NL:Florence-2 组挪到最前。
      model.moveCaption(null, 4, 0);

      final again = fresh();
      await again.load();
      expect(again.taggerGroups.first.series, 'OppaiOracle');
      expect(again.taggerGroups[1].items[2].id, first);
      expect(again.captionGroups.first.series, 'Florence-2');
      expect(
        again.captionGroups.expand((g) => g.items),
        hasLength(captionModels.length),
      );
    });

    test('要申请访问的模型没填 Token 时不下载', () async {
      final gated = taggerModels.firstWhere((m) => m.gated);
      expect(await fresh().downloadTagger(gated), contains('Token'));
    });

    test('文件夹里有别的量化档、NLapt 放的 Florence-2:都直接能用', () async {
      for (final p in [
        'nl/gemma4-e4b/gemma-4-E4B-it-Q8_0.gguf',
        'nl/gemma4-e4b/mmproj-F16.gguf',
        for (final f in [...florenceOnnx, florenceTokenizer])
          'nl/florence2-base-ft/$f',
      ]) {
        File('${tmp.path}/$p')
          ..createSync(recursive: true)
          ..writeAsStringSync('x');
      }
      final model = fresh()..addFolder('${tmp.path}/nl');
      while (model.scanning) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }

      final gemma = model.captionPaths(byId('gemma4-e4b'))!;
      expect(fileName(gemma.model), 'gemma-4-E4B-it-Q8_0.gguf');
      expect(fileName(gemma.mmproj), 'mmproj-F16.gguf');

      final florence = byId('florence2-base-ft');
      expect(model.useCaption(florence), isTrue);
      expect(model.florenceMode, isTrue);
      expect(
        model.captionPaths(florence)!.model,
        endsWith('florence2-base-ft'),
      );
      // 用的指令:它不认的换成它的第一个。
      model.update(() => model.florenceTask = '<ANALYZE>');
      expect(model.florenceTaskOf(florence), florence.tasks.first);
      // 选回 GGUF 就不是 Florence 了。
      expect(model.useCaption(byId('gemma4-e4b')), isTrue);
      expect(model.florenceMode, isFalse);
    });
  });

  group('看图描述的要求', () {
    LocalModel fresh() =>
        LocalModel(dir: tmp, streamChat: (_) => const Stream.empty());

    test('像 Preset 一样:新建、改名、改正文、切换、删除,存盘后还在', () async {
      final model = fresh();
      expect(model.captionPrompts, defaultCaptionPrompts);
      expect(model.currentPrompt.name, '详细描述');

      model.addPrompt();
      expect(model.currentPrompt.name, '详细描述 副本');
      model.editPrompt(name: '中文', text: '用中文描述');
      model.pickPrompt(1);

      final again = fresh();
      await again.load();
      expect(again.captionPrompts.last, (name: '中文', text: '用中文描述'));
      expect(again.currentPrompt.name, '简短描述');

      again.pickPrompt(again.captionPrompts.length - 1);
      again.removePrompt();
      expect(again.captionPrompts, hasLength(defaultCaptionPrompts.length));
      expect(again.currentPrompt.name, defaultCaptionPrompts.last.name);
    });

    test('以前只有一条要求:改过的那条留下来并选中', () async {
      File('${tmp.path}/local.json')
          .writeAsStringSync(jsonEncode({'captionPrompt': '您是一套图像分析系统'}));
      final model = fresh();
      await model.load();
      expect(model.currentPrompt, (name: '我的要求', text: '您是一套图像分析系统'));
      expect(model.captionPrompts, hasLength(defaultCaptionPrompts.length + 1));
    });
  });

  group('本地推理页的状态', () {
    test('换打标模型:阈值换成它的推荐值;设置存盘后还在', () async {
      final model = LocalModel(
        dir: tmp,
        streamChat: (_) => const Stream.empty(),
      );
      model.pickTagger(taggerModels[2].id);
      expect(model.general, taggerModels[2].general);
      model.setThresholds(character: 0.7);
      model.update(() => model.port = 9100);

      final again = LocalModel(
        dir: tmp,
        streamChat: (_) => const Stream.empty(),
      );
      await again.load();
      expect(again.taggerRepo, taggerModels[2].id);
      expect(again.character, 0.7);
      expect(again.port, 9100);
    });

    test('起了服务才能看图写描述,图带在请求里', () async {
      LlmRequest? asked;
      final model = LocalModel(
        dir: tmp,
        streamChat: (request) {
          asked = request;
          return Stream.fromIterable(['a girl ', 'in a field']);
        },
        server: LlamaServer(
          start: (_, _) async => _FakeProcess(),
          health: (_) async => true,
        ),
      );
      final spec = _spec(tmp);
      model.update(() {
        model.exePath = spec.exe;
        model.modelPath = spec.model;
      });

      model.setImage(
        Attachment.image(
          name: 'a.png',
          mime: 'image/png',
          bytes: Uint8List.fromList([1, 2, 3]),
        ),
      );
      expect(await model.runCaption(), '先启动模型');
      expect(await model.startServer(), isNull);
      expect(model.serverRunning, isTrue);

      expect(await model.runCaption(), isNull);
      expect(model.caption, 'a girl in a field');
      expect(asked!.baseUrl, 'http://127.0.0.1:8091/v1');
      // 用的是选中的那条要求。
      expect(asked!.messages.single['content'], model.currentPrompt.text);
      expect(asked!.images[0]!.single.bytes, [1, 2, 3]);

      // 正在用的模型不能删。
      expect(
        await model.remove([
          (url: '', path: spec.model, size: null, sha256: null),
        ]),
        contains('正在用'),
      );

      await model.stopServer();
      expect(model.serverRunning, isFalse);
    });

    test('生成途中换了图:前一张图的字不会挂到新图上', () async {
      final reply = StreamController<String>();
      final model = LocalModel(
        dir: tmp,
        streamChat: (_) => reply.stream,
        server: LlamaServer(
          start: (_, _) async => _FakeProcess(),
          health: (_) async => true,
        ),
      );
      final spec = _spec(tmp);
      model.update(() {
        model.exePath = spec.exe;
        model.modelPath = spec.model;
      });
      Attachment image(int b) => Attachment.image(
        name: 'a.png',
        mime: 'image/png',
        bytes: Uint8List.fromList([b]),
      );
      model.setImage(image(1));
      expect(await model.startServer(), isNull);

      final running = model.runCaption();
      reply.add('a cat ');
      await pumpEventQueue();
      model.setImage(image(2));
      reply.add('on a sofa');
      await reply.close();

      expect(await running, isNull);
      expect(model.caption, isEmpty);
      expect(model.captioning, isFalse);
      await model.stopServer();
    });

    testWidgets('结果「发送给 Agent」:切回工作台,填进聊天输入框', (tester) async {
      tester.view.physicalSize = const Size(1440, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final local = LocalModel(
        dir: tmp,
        streamChat: (_) => Stream.value('a cat on a sofa'),
        server: LlamaServer(
          start: (_, _) async => _FakeProcess(),
          health: (_) async => true,
        ),
      );
      await tester.runAsync(() async {
        final spec = _spec(tmp);
        local.update(() {
          local.exePath = spec.exe;
          local.modelPath = spec.model;
        });
        local.setImage(
          Attachment.image(
            name: 'a.png',
            mime: 'image/png',
            bytes: Uint8List.fromList([1, 2, 3]),
          ),
        );
        await local.startServer();
        await local.runCaption();
      });
      final vm = StudioViewModel(
        config: tempConfig(),
        streamChat: (_) => const Stream.empty(),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: AppShell(
            vm: vm,
            config: vm.config,
            skills: tempSkills(),
            local: local,
          ),
        ),
      );

      await tester.tap(find.byTooltip('本地反推'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('NL 反推'));
      await tester.pumpAndSettle();
      final send = find.descendant(
        of: find.byType(LocalPage),
        matching: find.text('发送给 Agent'),
      );
      await tester.ensureVisible(send);
      await tester.tap(send);
      await tester.pumpAndSettle();

      expect(find.widgetWithText(TextField, 'a cat on a sofa'), findsOneWidget);
      await tester.runAsync(local.stopServer);
    });
  });
}
