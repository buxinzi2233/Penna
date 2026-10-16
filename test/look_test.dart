import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:penna/data/models/app_config.dart';
import 'package:penna/l10n/l10n.dart';
import 'package:penna/ui/core/look_switcher.dart';
import 'package:penna/ui/core/theme.dart';

import 'fixtures.dart';

void main() {
  tearDown(() => applyLook(const AppConfig()));

  test('tr:查不到就用原文,{0} 按顺序填', () {
    useLanguage('xx');
    expect(currentLanguage, 'zh-Hans');
    expect(tr('取消'), '取消');
    expect(tr('第 {0} 页,共 {1} 页', [2, 5]), '第 2 页,共 5 页');
    useLanguage('en');
    expect(tr('取消'), 'Cancel');
  });

  testWidgets('切到深色:换配色,旧画面盖着慢慢露出新画面', (tester) async {
    final config = tempConfig();
    await tester.pumpWidget(
      MaterialApp(
        home: LookSwitcher(
          config: config,
          child: Builder(builder: (_) => ColoredBox(color: PennaColors.bg)),
        ),
      ),
    );
    expect(PennaColors.isDark, isFalse);

    config.update(config.config.copyWith(darkMode: true));
    await tester.pump();
    expect(PennaColors.isDark, isTrue);
    expect(find.byType(CustomPaint), findsWidgets);

    await tester.pumpAndSettle();
    expect(PennaColors.isDark, isTrue);

    config.update(config.config.copyWith(language: 'ja'));
    await tester.pump();
    expect(currentLanguage, 'ja');
  });
}
