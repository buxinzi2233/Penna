import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:penna/core/harness/layout.dart';
import 'package:penna/core/harness/providers/openai_provider.dart';
import 'package:penna/data/models/app_config.dart';
import 'package:penna/ui/core/theme.dart';
import 'package:penna/ui/features/layout/layout_board.dart';
import 'package:penna/ui/features/layout/layout_camera.dart';
import 'package:penna/ui/features/studio/studio_view_model.dart';

import 'fixtures.dart';

String _draft(String caption) =>
    '{"width": 832, "height": 1216, "summary": {"caption": "$caption"}, '
    '"items": [{"name": "人", "label": "character", "caption": "a girl", '
    '"bbox": [200, 300, 600, 1100]}], '
    '"bbox_coord_space": "abs", "bbox_format": "xyxy"}';

void main() {
  test('Agent 写 <lighting>:画板换上灯光,交出去的 caption 接上光影;再换布局灯光照旧', () async {
    final board = LayoutBoard();
    final service = tempConfig();
    service.update(
      service.config.putLlm(
        const LlmProfile(id: 'a', name: 'A', baseUrl: 'http://a', model: 'm'),
      ),
    );
    final seen = <LlmRequest>[];
    final replies = [
      '<layout>${_draft('A girl in a studio')}</layout>'
          '<lighting>{"preset": "rembrandt"}</lighting>打好光了。',
      '<layout>${_draft('A girl by the window')}</layout>换了个场景。',
    ];
    final chat = StudioViewModel(
      config: service,
      layout: board,
      layoutOnly: true,
      streamChat: (r) {
        seen.add(r);
        return Stream.value(replies[seen.length - 1]);
      },
    );
    chat.send('排一张,用伦勃朗光');
    await pumpEventQueue();
    expect(board.layout.lighting.preset, 'rembrandt');
    expect(chat.messages.last.toolSummary, contains('已调整灯光'));
    final caption =
        (jsonDecode(board.json) as Map)['summary']['caption'] as String;
    expect(caption, startsWith('A girl in a studio. Lighting: '));
    expect(
      caption,
      endsWith(lightingPhrase(board.layout.lighting, null, zh: false)),
    );
    expect(caption, contains('Rembrandt lighting'));

    chat.send('换到窗边');
    await pumpEventQueue();
    expect(board.layout.caption, 'A girl by the window');
    expect(board.layout.lighting.preset, 'rembrandt');
    // 发给模型的系统提示里有灯光现状;上一条回复里的灯光标签换成了一句话。
    final sent = seen.last.messages;
    expect(sent.first['content'], contains('【灯光】开着'));
    expect(
      sent.where((m) => m['role'] == 'assistant').single['content'],
      allOf(isNot(contains('<lighting>')), contains('调过一次灯光')),
    );
  });

  testWidgets('摄像机栏里打开灯光、拖灯光球上的手柄,灯换方向,下面的提示词跟着变', (tester) async {
    tester.view.physicalSize = const Size(400, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final board = LayoutBoard()..setThreeD(true);
    await tester.pumpWidget(
      MaterialApp(
        theme: pennaTheme(),
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              height: 2400,
              child: ListenableBuilder(
                listenable: board,
                builder: (context, _) => CameraPanel(
                  board: board,
                  onRedescribe: () {},
                  onEstimate: () {},
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    final lg = board.layout.lighting;
    expect((lg.enabled, lg.preset), (true, 'natural'));
    expect(find.textContaining('Lighting: Natural daylight'), findsOneWidget);

    // 灯光球 180 宽、半径 89;自然光的主光在左上。
    final ball = find.byWidgetPredicate(
      (w) => w.runtimeType.toString() == '_LightBall',
    );
    final c = tester.getCenter(ball);
    final key = relDir(lg.lights.first, lg, board.layout.camera);
    final from = c + Offset(key.side, -key.up) * 89;
    final g = await tester.startGesture(from);
    await g.moveTo(from + const Offset(20, 10));
    await g.moveTo(c + const Offset(60, 0));
    await g.up();
    await tester.pumpAndSettle();
    final moved = board.layout.lighting;
    expect(moved.preset, '');
    expect(
      relDir(moved.lights.first, moved, board.layout.camera).side,
      greaterThan(0.5),
    );
    expect(find.textContaining('from the front right'), findsOneWidget);
  });
}
