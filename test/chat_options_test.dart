import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:penna/core/harness/attachment.dart';
import 'package:penna/data/models/app_config.dart';
import 'package:penna/ui/features/studio/studio_view_model.dart';

import 'fixtures.dart';

void main() {
  group('压缩大图', () {
    test('大图缩到 2048 以内并转成 WebP;小图原样', () async {
      // 噪点图压不小,PNG 能有好几 MB,像一张大截图。
      final random = Random(1);
      final noise = img.Image(width: 3000, height: 1500);
      for (final p in noise) {
        p.setRgb(random.nextInt(256), random.nextInt(256), random.nextInt(256));
      }
      final png = img.encodePng(noise);
      expect(png.length, greaterThan(compressAboveBytes));

      final out = await compressImage(
        Attachment.image(name: 'shot.png', mime: 'image/png', bytes: png),
      );

      expect(out.compressed, isTrue);
      expect(out.mime, 'image/webp');
      expect(out.name, 'shot.webp');
      expect(out.bytes!.length, lessThan(png.length));
      final back = img.decodeWebP(out.bytes!)!;
      expect([back.width, back.height], [2048, 1024]);

      final small = Attachment.image(
        name: 'a.png',
        mime: 'image/png',
        bytes: img.encodePng(img.Image(width: 8, height: 8)),
      );
      expect(identical(await compressImage(small), small), isTrue);
    });
  });

  group('自动审批', () {
    StudioViewModel studio({required bool auto}) {
      final config = tempConfig();
      config.update(const AppConfig().copyWith(autoApprove: auto));
      return StudioViewModel(
        config: config,
        streamChat: (_) => const Stream.empty(),
        blocks: const [(text: 'a fox', pinned: false)],
      );
    }

    test('关着时等确认,开着时直接采纳', () {
      final manual = studio(auto: false)..proposeDraft('a red fox');
      expect(manual.pending, isNotNull);
      expect(manual.body, 'a fox');

      final auto = studio(auto: true)..proposeDraft('a red fox');
      expect(auto.pending, isNull);
      expect(auto.body, 'a red fox');
    });
  });
}
