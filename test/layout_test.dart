import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:penna/core/harness/layout.dart';
import 'package:penna/data/models/app_config.dart';
import 'package:penna/ui/features/layout/layout_board.dart';
import 'package:penna/ui/features/layout/layout_canvas.dart';
import 'package:penna/ui/features/layout/layout_perspective.dart';
import 'package:penna/ui/features/studio/studio_view_model.dart';
import 'package:penna/ui/features/studio/studio_page.dart';
import 'package:penna/ui/shell.dart';

import 'fixtures.dart';

const _official = '''
{
  "summary": {"meta": ["poster"], "canvas": "single", "caption": "A travel poster."},
  "items": [
    {"label": "text", "caption": "Title.", "text": "EXPLORE", "bbox": [-416, -384, -288, 384]},
    {"label": "object", "caption": "Mountain.", "bbox": [-192, -288, 384, 288]}
  ],
  "bbox_coord_space": "abs_centralized",
  "bbox_format": "yxyx"
}''';

void main() {
  _regionTests();
  test('官方示例读进来再写出去,坐标不变', () {
    final l = parseMossLayout(_official, width: 1024, height: 1024)!;
    expect(l.boxes.first.left, 128);
    expect(l.boxes.first.top, 96);
    expect(l.boxes.first.label, 'text');
    expect(l.boxes.first.text, 'EXPLORE');
    expect(l.meta, 'poster');
    final out = jsonDecode(mossLayoutJson(l)) as Map;
    expect(out['bbox_format'], 'yxyx');
    expect(out['bbox_coord_space'], 'abs_centralized');
    final items = out['items'] as List;
    expect(items[0]['bbox'], [-416, -384, -288, 384]);
    expect(items[1]['bbox'], [-192, -288, 384, 288]);
    expect(items[1].containsKey('text'), isFalse);
  });

  test('框超出画布截掉,写反的摆正,没面积的不要,代码块外壳去掉', () {
    final l = parseMossLayout(
      '```json\n{"items": ['
      '{"label": "bogus", "bbox": [600, 500, -700, -10]},'
      '{"bbox": [0, 0, 0, 100]}'
      ']}\n```',
      width: 832,
      height: 1216,
    )!;
    expect(l.boxes, hasLength(1));
    final b = l.boxes.single;
    expect((b.left, b.top, b.right, b.bottom), (406, 0, 832, 1208));
    expect(b.label, 'object');
    expect(parseMossLayout('不是 JSON', width: 64, height: 64), isNull);
  });

  test('模型写坏的 JSON 能修就修:漏了 summary 的右括号、多余逗号、前后带话', () {
    // DeepSeek 实际写出来的样子:summary 没收尾,items 落进了 summary,整份少一个 }。
    const missing = '''
{
  "summary": {
    "canvas": "single",
    "caption": "Two girls. She says \\"hi\\" {not a brace}.",
    "items": [
      {"name": "左", "label": "character", "caption": "a", "bbox": [-100, -100, 100, 0]},
      {"name": "右", "label": "character", "caption": "b", "bbox": [-100, 0, 100, 100]}
    ],
    "bbox_coord_space": "abs_centralized",
    "bbox_format": "yxyx"
  }''';
    final fixed = parseMossLayout(missing, width: 400, height: 400)!;
    expect(fixed.boxes.map((b) => b.name), ['左', '右']);
    expect(fixed.caption, 'Two girls. She says "hi" {not a brace}.');

    final commas = parseMossLayout(
      '这是布局:\n{"summary": {"caption": "x",}, '
      '"items": [{"bbox": [0, 0, 10, 10],},],}\n以上。',
      width: 400,
      height: 400,
    )!;
    expect(commas.boxes, hasLength(1));
    expect(commas.caption, 'x');

    expect(parseMossLayout('不是 JSON', width: 400, height: 400), isNull);
  });

  test('拆 <layout>:写完的取出来,写到一半的不显示', () {
    final done = splitLayout('排好了。<layout>{"items": []}</layout>');
    expect(done.prose, '排好了。');
    expect(done.json, '{"items": []}');
    expect(done.complete, isTrue);
    final half = splitLayout('排好了。<layout>{"ite');
    expect(half.prose, '排好了。');
    expect(half.complete, isFalse);
    expect(splitLayout('排好了。<lay').prose, '排好了。');
  });

  test('画板:换尺寸时框跟着缩放,对调,存尺寸,存盘读回', () async {
    final dir = Directory.systemTemp.createTempSync('penna_layout');
    final board = LayoutBoard(dir: dir)
      ..addBox(const LayoutBox(left: 0, top: 0, right: 416, bottom: 608));
    expect(board.setSize(10, 10), isFalse);
    board.swap();
    expect((board.layout.width, board.layout.height), (1216, 832));
    expect(board.layout.boxes.single.right, 608);
    expect(board.layout.boxes.single.bottom, 416);
    board
      ..saveSize()
      ..setSummary(caption: 'sunset')
      ..dispose();
    final again = LayoutBoard(dir: dir);
    await again.load();
    expect(again.layout.caption, 'sunset');
    expect(again.layout.boxes.single.right, 608);
    expect(again.sizes, contains((width: 1216, height: 832)));
  });

  test('图层和透视:存盘读回;Agent 漏写 layer 时沿用,透视线留着;都说给模型听', () {
    final board = LayoutBoard()
      ..addBox(
        const LayoutBox(left: 0, top: 0, right: 100, bottom: 100, name: '人'),
      )
      ..updateBox(
        0,
        const LayoutBox(
          left: 0,
          top: 0,
          right: 100,
          bottom: 100,
          name: '人',
          layer: 'front',
        ),
      )
      ..setPerspective(3);
    final again = Layout.fromJson(board.layout.toJson());
    expect(again.boxes.single.layer, 'front');
    expect(again.perspective!.points, 3);
    // 交出去的 JSON 不带 layer,给 Agent 的带。
    expect(board.json, isNot(contains('layer')));
    expect(board.prompt, contains('"layer": "front"'));
    expect(board.prompt, contains('前景'));
    expect(board.prompt, contains('【透视辅助】'));

    expect(
      board.apply(
        '{"summary": {"caption": "x"}, "items": [{"label": "object", '
        '"caption": "y", "bbox": [-600, -400, -500, -300]}]}',
      ),
      isTrue,
    );
    expect(board.layout.boxes.single.layer, 'front');
    expect(board.layout.boxes.single.name, '人');
    expect(board.layout.perspective, isNotNull);

    // 拖地平线上的消失点,地平线跟着走;换尺寸时跟着缩放。
    final p = dragVanishing(
      board.layout.perspective!,
      0,
      const Offset(10, 300),
    );
    expect((p.xs.first, p.horizon), (10, 300));
    board
      ..movePerspective(p)
      ..swap();
    expect(board.layout.perspective!.horizon, (300 * 832 / 1216).round());
    board.setPerspective(null);
    expect(board.prompt, contains('【透视辅助】现在关着'));
  });

  test('<perspective>:按百分比读,能放到画面外,off 是关掉;写到一半的不显示', () {
    final p = parsePerspective(
      '{"horizon": 50, "vanishing": [10, 95], "third": [50, -40]}',
      1000,
      2000,
    )!;
    expect(p.off, isFalse);
    expect(p.value!.horizon, 1000);
    expect(p.value!.xs, [100, 950]);
    expect(p.value!.third, (x: 500, y: -800));
    // 太远的截到 -300% / 400%。
    expect(
      parsePerspective(
        '{"horizon": 50, "vanishing": [9999]}',
        100,
        100,
      )!.value!.xs,
      [400],
    );
    expect(parsePerspective(' off ', 100, 100)!.off, isTrue);
    expect(parsePerspective('{"horizon": 50}', 100, 100), isNull);
    expect(
      parsePerspective('{"horizon": 50, "vanishing": []}', 100, 100),
      isNull,
    );

    final done = splitPerspective('调好了。<perspective>off</perspective>');
    expect((done.prose, done.spec), ('调好了。', 'off'));
    final half = splitPerspective('调好了。<persp');
    expect((half.prose, half.spec), ('调好了。', null));
    expect(splitPerspective('调好了。<perspective>{"hor').spec, isNull);
  });

  test('布局对话:Agent 写了 <perspective> 就改画板的透视线,下一轮不重发旧的数', () async {
    final board = LayoutBoard();
    final seen = <List<Map<String, String>>>[];
    final service = tempConfig();
    service.update(
      service.config.putLlm(
        const LlmProfile(id: 'a', name: 'A', baseUrl: 'http://a', model: 'm'),
      ),
    );
    final replies = [
      '照参考图调了透视。<perspective>{"horizon": 75, "vanishing": [20, 80]}</perspective>',
      '好的。',
    ];
    final chat = StudioViewModel(
      config: service,
      layout: board,
      layoutOnly: true,
      streamChat: (request) {
        seen.add(request.messages);
        return Stream.value(replies[seen.length - 1]);
      },
    );
    expect(chat.send('照这张图的透视'), isNull);
    await pumpEventQueue();
    expect(seen.first.first['content'], contains('【透视辅助】现在关着'));
    final p = board.layout.perspective!;
    expect((p.points, p.horizon), (2, 912));
    expect(chat.messages.last.toolSummary, contains('2 点透视'));

    expect(chat.send('再说说'), isNull);
    await pumpEventQueue();
    expect(seen.last[2]['content'], isNot(contains('"horizon"')));
    expect(seen.last[2]['content'], isNot(contains('<perspective>')));
    expect(seen.last.first['content'], contains('2 点透视'));
    expect(seen.last.first['content'], contains('"horizon":75'));
  });

  test('参考图和画布一横一竖时给出对调后的尺寸', () async {
    final board = LayoutBoard();
    Uint8List png(int w, int h) =>
        img.encodePng(img.Image(width: w, height: h));
    expect(await board.swapFor(png(30, 20)), (width: 1216, height: 832));
    expect(await board.swapFor(png(20, 30)), isNull);
    expect(await board.swapFor(png(20, 20)), isNull);
    expect(await board.swapFor(Uint8List(3)), isNull);
  });

  testWidgets('画布上单击选中并告诉属性栏,双击去改,Delete 删掉', (tester) async {
    final board = LayoutBoard()
      ..setSize(100, 200)
      ..addBox(const LayoutBox(left: 0, top: 0, right: 50, bottom: 50))
      ..select(null);
    final picked = <int>[], edited = <int>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: SizedBox(
            width: 200,
            height: 400,
            child: LayoutCanvas(
              board: board,
              onPick: picked.add,
              onEdit: edited.add,
            ),
          ),
        ),
      ),
    );
    final at =
        tester.getTopLeft(find.byType(LayoutCanvas)) + const Offset(40, 40);
    // 双击靠按下时的时间戳判断,测试里自己给。
    final g = await tester.createGesture();
    await g.down(at, timeStamp: const Duration(seconds: 1));
    await g.up();
    await tester.pump();
    expect(board.selected, 0);
    expect(picked, [0]);
    expect(edited, isEmpty);

    // 隔得久的第二下不算双击;紧跟着的第三下算。
    final g2 = await tester.createGesture();
    await g2.down(at, timeStamp: const Duration(seconds: 5));
    await g2.up();
    await tester.pump();
    expect(edited, isEmpty);
    final g3 = await tester.createGesture();
    await g3.down(at, timeStamp: const Duration(seconds: 5, milliseconds: 100));
    await g3.up();
    await tester.pump();
    expect(edited, [0]);

    await tester.sendKeyEvent(LogicalKeyboardKey.delete);
    expect(board.layout.boxes, isEmpty);
  });

  testWidgets('画布上拖出一个框,再拖着它挪动、拉右下角改大小', (tester) async {
    // 画布 100×200 画在 200×400 的地方:屏幕上 2 个点是画布 1 个像素。
    final board = LayoutBoard()..setSize(100, 200);
    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: SizedBox(
            width: 200,
            height: 400,
            child: LayoutCanvas(board: board),
          ),
        ),
      ),
    );
    final origin = tester.getTopLeft(find.byType(LayoutCanvas));
    Future<void> drag(Offset from, Offset by) async {
      await tester.dragFrom(origin + from, by);
      await tester.pump();
    }

    await drag(const Offset(20, 20), const Offset(80, 100));
    var b = board.layout.boxes.single;
    expect((b.left, b.top, b.right, b.bottom), (10, 10, 50, 60));
    expect(board.selected, 0);

    await drag(const Offset(60, 60), const Offset(20, 40));
    b = board.layout.boxes.single;
    expect((b.left, b.top, b.right, b.bottom), (20, 30, 60, 80));

    // 右下角在屏幕 (120, 160)。
    await drag(const Offset(120, 160), const Offset(40, 400));
    b = board.layout.boxes.single;
    expect((b.left, b.top, b.right, b.bottom), (20, 30, 80, 200));

    // 太小的不算。
    await drag(const Offset(180, 380), const Offset(4, 4));
    expect(board.layout.boxes, hasLength(1));
  });

  test('布局页的对话:系统提示只讲布局,回复里的布局放到画板,接着改时带着历史', () async {
    final board = LayoutBoard();
    final seen = <List<Map<String, String>>>[];
    final service = tempConfig();
    service.update(
      service.config.putLlm(
        const LlmProfile(id: 'a', name: 'A', baseUrl: 'http://a', model: 'm'),
      ),
    );
    final named = _official.replaceFirst(
      '"label": "text"',
      '"name": "标题", "label": "text"',
    );
    final replies = [
      '排好了。<layout>$named</layout>',
      // 没写 name、还顺手写了成稿:名字按先后接上,成稿不理。
      '改好了。<layout>$_official</layout><draft>【主体】x</draft>',
    ];
    final chat = StudioViewModel(
      config: service,
      layout: board,
      layoutOnly: true,
      streamChat: (request) {
        seen.add(request.messages);
        return Stream.value(replies[seen.length - 1]);
      },
    );
    expect(chat.send('旅行海报'), isNull);
    await pumpEventQueue();
    final system = seen.first.first['content']!;
    expect(system, contains('布局助手'));
    expect(system, contains('bbox_format'));
    expect(system, contains('【布局画板】画布 832×1216'));
    expect(system, isNot(contains('<draft> 和 </draft> 之间')));
    expect(board.layout.boxes, hasLength(2));
    expect(board.layout.boxes.first.name, '标题');
    expect(chat.messages.last.toolSummary, contains('2'));

    // 用户在两轮之间手动挪了标题框。
    board.updateBox(
      0,
      board.layout.boxes.first.copyWith(
        left: 0,
        top: 0,
        right: 416,
        bottom: 608,
      ),
    );
    chat.quoteSection('【标题】text · x 0 y 0 · 10×10');
    expect(chat.send('再大一点'), isNull);
    await pumpEventQueue();
    // 上一轮自己写的旧坐标不重发,画板此刻的位置在系统提示里。
    expect(seen.last[2]['content'], isNot(contains('bbox')));
    expect(seen.last[2]['content'], contains('现在的样子看【布局画板】'));
    // 标签本身也不留:留着的话模型会照样子把那句说明当成布局写回来。
    expect(seen.last[2]['content'], isNot(contains('<layout>')));
    expect(seen.last.first['content'], contains('横向 0%–50%,纵向 0%–50%'));
    expect(seen.last.first['content'], contains('-608,'));
    // 第二轮带着上一轮;选中的那块随消息发出,系统提示里是带名字的现有布局。
    expect(seen.last.map((m) => m['role']), [
      'system',
      'user',
      'assistant',
      'user',
    ]);
    expect(seen.last.last['content'], contains('布局里的这一块'));
    expect(seen.last.first['content'], contains('"name": "标题"'));
    expect(board.layout.boxes.first.name, '标题');
    expect(chat.body, isEmpty);
    // 交出去的 JSON 不带 name:官方格式不认。
    expect(board.json, isNot(contains('"name"')));
  });

  test('Agent 写的 <layout> 回复说完后放到画板上,系统提示里有画布尺寸', () async {
    final board = LayoutBoard();
    final sent = <String>[];
    final service = tempConfig();
    service.update(
      service.config.putLlm(
        const LlmProfile(id: 'a', name: 'A', baseUrl: 'http://a', model: 'm'),
      ),
    );
    final vm = StudioViewModel(
      config: service,
      layout: board,
      streamChat: (request) {
        sent.add(request.messages.first['content']!);
        return Stream.value('排好了。<layout>$_official</layout>');
      },
    );
    expect(vm.send('做一张海报'), isNull);
    await pumpEventQueue();
    expect(sent.single, contains('【布局画板】画布 832×1216'));
    expect(board.layout.boxes, hasLength(2));
    expect(vm.messages.last.toolSummary, contains('2'));
  });
}

void _regionTests() {
  test('布局 JSON 按功能区切出位置:整体和每一块,字符串里的括号不算', () {
    const text =
        '{"summary": {"caption": "a {curly} [x] \\"q\\""},'
        ' "items": [{"name": "标题", "label": "text", "text": "HI", "bbox": [1, 2, 3, 4]},'
        ' {"label": "object", "caption": "}", "bbox": [5, 6, 7, 8]}],'
        ' "bbox_coord_space": "abs_centralized", "bbox_format": "yxyx"}';
    final r = layoutJsonRegions(text)!;
    expect(r.map((x) => x.item), [-1, 0, 1]);
    expect(text.substring(r[0].start, r[0].end), startsWith('{"caption"'));
    expect(text.substring(r[1].start, r[1].end), endsWith('[1, 2, 3, 4]}'));
    expect(text.substring(r[2].start, r[2].end), endsWith('[5, 6, 7, 8]}'));
    expect((r[1].name, r[1].label, r[1].text), ('标题', 'text', 'HI'));
    expect(layoutJsonRegions('【主体】a girl'), isNull);
    expect(layoutJsonRegions('{"items": []}'), isNull);
  });

  testWidgets('成稿是布局 JSON 时按功能区分框显示,点编辑换回一整块输入框', (tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final json = mossLayoutJson(
      parseMossLayout(_official, width: 1024, height: 1024)!,
    );
    final vm = StudioViewModel(
      config: tempConfig(),
      streamChat: (_) => const Stream.empty(),
      blocks: [(text: json, pinned: false)],
    );
    addTearDown(vm.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: AppShell(vm: vm, config: vm.config, skills: tempSkills()),
      ),
    );
    // 布局页的 JSON 卡片也这样显示:只看工作台的。
    Finder inStudio(Finder f) =>
        find.descendant(of: find.byType(StudioPage), matching: f);
    expect(inStudio(find.text('整体')), findsOneWidget);
    expect(inStudio(find.text('1 · 文字 「EXPLORE」')), findsOneWidget);
    expect(inStudio(find.text('2 · 物体')), findsOneWidget);
    await tester.tap(inStudio(find.text('编辑')));
    await tester.pump();
    expect(inStudio(find.text('整体')), findsNothing);
    // 成稿还是那一整份 JSON,没被拆成分段。
    expect(vm.body, json);
  });
}
