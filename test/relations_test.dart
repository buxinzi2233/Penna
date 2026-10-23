import 'package:flutter_test/flutter_test.dart';
import 'package:penna/core/harness/layout.dart';
import 'package:penna/core/harness/layout_relations.dart';
import 'package:penna/ui/features/layout/layout_board.dart';

LayoutBox _b(
  String name,
  int l,
  int t,
  int r,
  int b, {
  String layer = 'middle',
}) => LayoutBox(left: l, top: t, right: r, bottom: b, name: name, layer: layer);

void main() {
  // 前后照 boxes 的先后:标题最前,人物其次,大字最后。
  final layout = Layout(
    width: 832,
    height: 1216,
    caption: 'poster',
    boxes: [
      _b('标题', 0, 0, 500, 300, layer: 'front'),
      _b('小杯子', 300, 500, 400, 600, layer: 'front'),
      _b('人物', 200, 200, 650, 1216),
      _b('大字', 0, 400, 832, 800, layer: 'back'),
    ],
  );
  final text = layoutRelations(layout);

  test('每块在画面哪里、占多大、贴着哪条边', () {
    expect(text, contains('「标题」:画面左上'));
    expect(text, contains('贴着画面上边、左边'));
    expect(text, contains('「大字」:画面正中'));
    expect(text, contains('横贯整个宽度'));
    expect(text, contains('「人物」'));
    expect(text, contains('贴着画面下边'));
  });

  test('重叠时说谁在前、挡住后面那块的哪部分、挡多少;整个落在里面的单说', () {
    expect(text, contains('「标题」在「人物」前面,挡住「人物」的上部'));
    expect(text, contains('「人物」在「大字」前面,挡住「大字」的中间'));
    expect(text, contains('「小杯子」整个落在「人物」的范围里、在它前面'));
    // 不重叠的两块不提。
    expect(text, isNot(contains('「标题」在「小杯子」')));
  });

  test('发给 Agent 的画板现状里带着位置关系,空画板不带', () {
    final board = LayoutBoard()..replace(layout);
    expect(board.prompt, contains('【位置关系】'));
    board.clear();
    expect(board.prompt, isNot(contains('【位置关系】')));
  });
}
