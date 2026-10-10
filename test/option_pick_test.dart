import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:penna/ui/features/studio/option_pick.dart';

void main() {
  testWidgets('多选:勾几个发那几个,全选了发「全部」,没勾不能发', (tester) async {
    final sent = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MultiPick(
            options: const ['主体', '服装', '场景'],
            onSubmit: sent.add,
          ),
        ),
      ),
    );

    await tester.tap(find.text('确定'));
    expect(sent, isEmpty);

    // 先勾后面的再勾前面的:发出去按原来的先后。
    await tester.tap(find.text('场景'));
    await tester.tap(find.text('主体'));
    await tester.pumpAndSettle();
    expect(find.text('已选 2 / 3'), findsOneWidget);
    await tester.tap(find.text('确定'));
    expect(sent, ['主体、场景']);

    await tester.tap(find.text('全选'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('确定'));
    expect(sent.last, '全部');
  });
}
