import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:penna/core/harness/layout.dart';
import 'package:penna/ui/features/layout/layout_board.dart';
import 'package:penna/ui/features/layout/layout_canvas.dart';

const _tri = LayoutBox(left: 100, top: 100, right: 300, bottom: 300);

void main() {
  test('正多边形撑满框;椭圆和多边形按形状判断点在不在里面', () {
    final s = LayoutShape.regular(3);
    expect(s.points, hasLength(3));
    expect(s.points.map((p) => p.$1).reduce((a, b) => a < b ? a : b), 0);
    expect(s.points.map((p) => p.$2).reduce((a, b) => a > b ? a : b), 1);
    expect(LayoutShape.regular(40).points, hasLength(maxShapePoints));

    final tri = _tri.copyWith(shape: () => s);
    expect(tri.covers(200, 250), isTrue);
    expect(tri.covers(110, 110), isFalse); // 框里、三角形外
    final oval = _tri.copyWith(shape: () => const LayoutShape.ellipse());
    expect(oval.covers(200, 200), isTrue);
    expect(oval.covers(105, 105), isFalse);
    expect(_tri.covers(105, 105), isTrue);
  });

  test('拖一个顶点:框换成新的外框,别的顶点在画布上不动', () {
    final tri = _tri.copyWith(shape: () => LayoutShape.regular(3));
    final moved = tri.withVertex(0, 200, 40);
    expect(
      (moved.left, moved.top, moved.right, moved.bottom),
      (100, 40, 300, 300),
    );
    expect(moved.shapePoints.skip(1), [(300.0, 300.0), (100.0, 300.0)]);
    // 挤成一条线的不收。
    final flat = moved.withVertex(0, 200, 300);
    expect(flat, same(moved));
  });

  test('存盘读回形状一样;交出去的 JSON 只有方框,给 Agent 的带形状', () {
    final l = Layout(
      width: 400,
      height: 400,
      boxes: [
        _tri.copyWith(shape: () => LayoutShape.regular(3)),
        _tri.copyWith(shape: () => const LayoutShape.ellipse()),
      ],
    );
    final back = Layout.fromJson(
      jsonDecode(jsonEncode(l.toJson())) as Map<String, dynamic>,
    );
    expect(back.boxes[0].shape, LayoutShape.regular(3));
    expect(back.boxes[1].shape!.isEllipse, isTrue);

    final out = jsonDecode(mossLayoutJson(l)) as Map;
    final item = (out['items'] as List).first as Map;
    expect(item.containsKey('shape'), isFalse);
    expect(item['bbox'], [-100, -100, 100, 100]);

    final draft = jsonDecode(mossLayoutJson(l, draft: true)) as Map;
    final items = draft['items'] as List;
    expect((items[0] as Map)['shape'], [
      [200, 100],
      [300, 300],
      [100, 300],
    ]);
    expect((items[1] as Map)['shape'], 'ellipse');
  });

  test('读 Agent 写的形状:没写 bbox 拿顶点外框;写了 bbox 形状拉伸进去', () {
    final read = parseMossLayout(
      jsonEncode({
        'summary': {'caption': ''},
        'items': [
          {
            'caption': '山',
            'shape': [
              [200, 100],
              [300, 300],
              [100, 300],
            ],
          },
          {
            'caption': '挪过的山',
            'bbox': [0, 0, 100, 100],
            'shape': [
              [200, 100],
              [300, 300],
              [100, 300],
            ],
          },
          {
            'caption': '脸',
            'bbox': [10, 10, 50, 50],
            'shape': 'ellipse',
          },
        ],
        'bbox_coord_space': 'abs',
        'bbox_format': 'xyxy',
      }),
      width: 400,
      height: 400,
    )!;
    final [mountain, movedMountain, face] = read.boxes;
    expect(
      (mountain.left, mountain.top, mountain.right, mountain.bottom),
      (100, 100, 300, 300),
    );
    expect(mountain.shape, LayoutShape.regular(3));
    expect(movedMountain.right, 100);
    expect(movedMountain.shapePoints.first, (50.0, 0.0));
    expect(face.shape!.isEllipse, isTrue);
  });

  test('Agent 重写布局时没写形状的接原来的,写 rect 的换回方框', () {
    final old = [
      _tri.copyWith(name: '山', shape: () => LayoutShape.regular(3)),
      _tri.copyWith(name: '脸', shape: () => const LayoutShape.ellipse()),
    ];
    final fresh = [
      _tri.copyWith(name: '山'),
      _tri.copyWith(name: '脸', shape: () => LayoutShape.box),
    ];
    final got = inheritNames(old, fresh, keepLayers: true);
    expect(got[0].shape, LayoutShape.regular(3));
    expect(got[1].shape, isNull);
  });

  testWidgets('画布上:点三角形外的空角不选中它,拖顶点改形状', (tester) async {
    final board = LayoutBoard()
      ..setSize(400, 400)
      ..addBox(_tri);
    board.updateBox(
      0,
      board.layout.boxes[0].copyWith(shape: () => LayoutShape.regular(3)),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: 400,
              height: 400,
              child: LayoutCanvas(board: board),
            ),
          ),
        ),
      ),
    );
    final o = tester.getTopLeft(find.byType(LayoutCanvas));
    board.select(null);
    await tester.tapAt(o + const Offset(110, 110));
    await tester.pump(const Duration(milliseconds: 400));
    expect(board.selected, isNull);
    await tester.tapAt(o + const Offset(200, 250));
    await tester.pump(const Duration(milliseconds: 400));
    expect(board.selected, 0);

    final g = await tester.startGesture(o + const Offset(200, 100));
    await g.moveBy(const Offset(0, -20));
    await g.moveBy(const Offset(0, -40));
    await g.up();
    await tester.pump();
    final b = board.layout.boxes.single;
    expect(b.top, 40);
    expect((b.left, b.right, b.bottom), (100, 300, 300));
    expect(b.shapePoints.first, (200.0, 40.0));
  });
}
