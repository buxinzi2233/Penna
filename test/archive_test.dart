import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:penna/core/harness/attachment.dart';
import 'package:penna/core/harness/providers/openai_provider.dart';
import 'package:penna/data/models/app_config.dart';
import 'package:penna/data/services/archive_store.dart';
import 'package:penna/ui/core/theme.dart';
import 'package:penna/ui/features/studio/reverse_model.dart';
import 'package:penna/ui/features/studio/studio_view_model.dart';
import 'package:penna/ui/shell.dart';

import 'fixtures.dart';

final _image = Attachment.image(
  name: 'ref.png',
  mime: 'image/png',
  bytes: Uint8List.fromList([1, 2, 3]),
);

/// 配好一个模型的工作台,回复由 [stream] 决定。
StudioViewModel _studio(ChatStreamer stream) {
  final config = tempConfig()
    ..update(
      const AppConfig().putLlm(
        const LlmProfile(id: 'a', name: 'A', baseUrl: 'http://x', model: 'm'),
      ),
    );
  return StudioViewModel(config: config, streamChat: stream);
}

void main() {
  group('档案库', () {
    test('存一条带时间和分类;空的不存;分类没填归未分类;能删', () {
      final store = ArchiveStore();
      store.add(text: '  ');
      store.add(text: 'a fox', now: DateTime(2026, 10, 9, 8));
      store.add(
        text: '【主体】a cat',
        title: '猫',
        category: ' 动物 ',
        now: DateTime(2026, 10, 9, 9),
      );

      expect(store.entries.map((e) => e.title), ['猫', '']);
      expect(store.entries.first.time, DateTime(2026, 10, 9, 9));
      expect(store.categories, ['动物', uncategorized]);

      store.remove(store.entries.first.id);
      expect(store.entries.single.text, 'a fox');
    });

    test('存盘后重新打开还在;读不了的文件改名留底', () async {
      final dir = Directory.systemTemp.createTempSync('penna_archive');
      addTearDown(() => dir.deleteSync(recursive: true));
      final file = File('${dir.path}/archive.json');
      ArchiveStore(file).add(text: 'a fox', title: '狐', category: '动物');

      final reopened = ArchiveStore(file);
      await reopened.load();
      expect(reopened.entries.single.title, '狐');
      expect(reopened.entries.single.category, '动物');

      file.writeAsStringSync('{坏的');
      final broken = ArchiveStore(file);
      await broken.load();
      expect(broken.entries, isEmpty);
      expect(
        dir.listSync().map((f) => f.path),
        contains(contains('archive.json.bad-')),
      );
    });
  });

  group('图像反推', () {
    test('把图发给模型,结果留在右侧并交给 Agent 当上下文', () async {
      final seen = <LlmRequest>[];
      final vm = _studio((req) {
        seen.add(req);
        return Stream.value(' a red fox, soft light ');
      });
      final model = ReverseModel(vm);

      expect(await model.run(), '先放一张图');
      model.setImage(_image);
      expect(await model.run(), isNull);

      expect(model.prompt, 'a red fox, soft light');
      expect(seen.single.images[1]!.single.mime, 'image/png');

      vm.send('照参考图的风格写一只猫');
      await pumpEventQueue();
      expect(seen.last.messages.first['content'], contains('【参考图反推】'));
      expect(seen.last.messages.first['content'], contains('a red fox'));
    });

    test('模型出错时说明原因;等结果时换了图,旧结果作废', () async {
      final failing = ReverseModel(
        _studio((_) => Stream.error(const LlmException('看不了图'))),
      )..setImage(_image);
      expect(await failing.run(), contains('看不了图'));
      expect(failing.busy, isFalse);

      final gate = Completer<void>();
      final model = ReverseModel(
        _studio((_) => Stream.fromFuture(gate.future.then((_) => '旧图的词'))),
      )..setImage(_image);
      final running = model.run();
      model.setImage(_image);
      gate.complete();
      await running;

      expect(model.prompt, isEmpty);
      expect(model.busy, isFalse);
    });

    test('参考图和结果存盘,重新打开还在;移除后文件也清掉', () async {
      final dir = Directory.systemTemp.createTempSync('penna_reverse');
      addTearDown(() => dir.deleteSync(recursive: true));
      final first = ReverseModel(
        _studio((_) => Stream.value('a fox')),
        dir: dir,
      )..setImage(_image);
      await first.run();

      final vm = _studio((_) => const Stream.empty());
      final reopened = ReverseModel(vm, dir: dir);
      await reopened.load();
      expect(reopened.image!.bytes, [1, 2, 3]);
      expect(reopened.prompt, 'a fox');
      expect(vm.referencePrompt, 'a fox');

      reopened.setImage(null);
      expect(dir.listSync(), isEmpty);
    });
  });

  testWidgets('工作区点保存 → 档案库里看得到,能按分类筛、放回成稿;下半区能切到图像反推', (tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final vm = StudioViewModel(
      config: tempConfig(),
      streamChat: (_) => const Stream.empty(),
      blocks: const [(text: '【主体】a fox', pinned: false)],
    );
    addTearDown(vm.dispose);
    final archive = ArchiveStore()..add(text: 'old cat', category: '动物');
    await tester.pumpWidget(
      MaterialApp(
        theme: pennaTheme(),
        home: AppShell(
          vm: vm,
          config: vm.config,
          skills: tempSkills(),
          archive: archive,
        ),
      ),
    );

    await tester.tap(find.text('图像反推'));
    await tester.pumpAndSettle();
    expect(find.text('点击或拖入参考图'), findsOneWidget);
    expect(find.text('原始反推提示词'), findsOneWidget);

    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, '可留空'), '狐狸');
    await tester.enterText(find.widgetWithText(TextField, '动物'), '写实');
    await tester.tap(find.widgetWithText(FilledButton, '保存'));
    await tester.pumpAndSettle();

    expect(archive.entries.first.text, '【主体】a fox');
    expect(archive.entries.first.category, '写实');

    await tester.tap(find.byTooltip('档案库'));
    await tester.pumpAndSettle();
    expect(find.text('狐狸'), findsOneWidget);
    expect(find.text('old cat'), findsOneWidget);

    await tester.tap(find.widgetWithText(GestureDetector, '动物').first);
    await tester.pumpAndSettle();
    expect(find.text('狐狸'), findsNothing);

    await tester.tap(find.text('放回成稿'));
    await tester.pumpAndSettle();
    expect(vm.pending!.added, 'old cat');
  });
}
