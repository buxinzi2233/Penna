import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/harness/layout.dart';

/// 透视线上能拖的几个消失点(画布像素):先是地平线上的,三点透视最后是竖直方向那个。
List<Offset> vanishingPoints(Perspective p) => [
  for (final x in p.xs) Offset(x.toDouble(), p.horizon.toDouble()),
  if (p.third != null) Offset(p.third!.x.toDouble(), p.third!.y.toDouble()),
];

/// 把第 [i] 个消失点拖到 [to](画布像素)。地平线上的消失点上下拖时地平线跟着走。
// ponytail: 消失点只能拖到画布里面;要放到画布外,得让画布四周留出能拖的空白。
Perspective dragVanishing(Perspective p, int i, Offset to) {
  final x = to.dx.round(), y = to.dy.round();
  if (i < p.xs.length) {
    return p.copyWith(
      horizon: y,
      xs: [for (final (j, old) in p.xs.indexed) j == i ? x : old],
    );
  }
  return p.copyWith(third: (x: x, y: y));
}

/// 每个消失点放出去的辐射线条数。
const _rays = 28;

/// 画透视辅助线:地平线、每个消失点放出的辐射线和能拖的圆点。[scale] 是画布像素到屏幕。
class PerspectivePainter extends CustomPainter {
  PerspectivePainter(this.perspective, this.scale, this.color);

  final Perspective perspective;
  final double scale;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    final rays = Paint()
      ..color = color.withValues(alpha: 0.35)
      ..strokeWidth = 0.8;
    final points = [for (final v in vanishingPoints(perspective)) v * scale];
    final edge = _perimeter(size);
    for (final v in points) {
      for (final e in edge) {
        canvas.drawLine(v, e, rays);
      }
    }
    final y = perspective.horizon * scale;
    canvas.drawLine(
      Offset(0, y),
      Offset(size.width, y),
      Paint()
        ..color = color
        ..strokeWidth = 1.6,
    );
    canvas.restore();
    // 圆点画在裁剪外面:贴着边的消失点也看得全。
    for (final v in points) {
      canvas
        ..drawCircle(v, 6, Paint()..color = Colors.white)
        ..drawCircle(
          v,
          6,
          Paint()
            ..color = color
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2,
        );
    }
  }

  /// 画布四条边上均匀取的点,辐射线连到这里。
  static List<Offset> _perimeter(Size s) {
    final total = 2 * (s.width + s.height);
    return [
      for (var k = 0; k < _rays; k++)
        () {
          var d = total * k / _rays;
          if (d < s.width) return Offset(d, 0);
          d -= s.width;
          if (d < s.height) return Offset(s.width, d);
          d -= s.height;
          if (d < s.width) return Offset(s.width - d, s.height);
          return Offset(0, s.height - math.min(d - s.width, s.height));
        }(),
    ];
  }

  @override
  bool shouldRepaint(PerspectivePainter old) =>
      old.perspective != perspective ||
      old.scale != scale ||
      old.color != color;
}
