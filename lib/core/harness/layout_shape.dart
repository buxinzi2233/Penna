part of 'layout.dart';

/// 多边形的顶点数范围。
const minShapePoints = 3, maxShapePoints = 12;

/// 框里的异形:椭圆(内切在框里)或多边形。框还是它的外框,交出去的 JSON 只有这个方框;
/// 形状只在 Penna 里用,用户画、和 Agent 商量构图时更直观。
/// 多边形的顶点按框的比例存(0–1,左上角是 (0, 0)):框挪动、缩放、3D 里重投时跟着走。
@immutable
class LayoutShape {
  const LayoutShape.ellipse() : points = const [];
  const LayoutShape.polygon(this.points);

  /// 正 [n] 边形(尖朝上),撑满整个框。取到存盘的精度,存了再读回来还是同一个。
  factory LayoutShape.regular(int n) {
    n = n.clamp(minShapePoints, maxShapePoints);
    final pts = _normalize([
      for (var k = 0; k < n; k++)
        (
          math.cos(-math.pi / 2 + 2 * math.pi * k / n),
          math.sin(-math.pi / 2 + 2 * math.pi * k / n),
        ),
    ]);
    return LayoutShape.polygon(
      List.unmodifiable([for (final (x, y) in pts) (_round4(x), _round4(y))]),
    );
  }

  /// Agent 写 `"shape": "rect"` 时读成它:要把原来的形状去掉、换回方框
  /// (没写 shape 的照原来的,见 [inheritNames])。
  static const box = LayoutShape.polygon([(0, 0), (1, 0), (1, 1), (0, 1)]);

  /// 多边形的顶点;椭圆是空的。
  final List<(double, double)> points;

  bool get isEllipse => points.isEmpty;

  Object toJson() => isEllipse
      ? 'ellipse'
      : [
          for (final (x, y) in points) [_round4(x), _round4(y)],
        ];

  static LayoutShape? fromJson(Object? j) {
    if (j == 'ellipse') return const LayoutShape.ellipse();
    final pts = _pairs(j);
    if (pts == null) return null;
    return LayoutShape.polygon(
      List.unmodifiable([
        for (final (x, y) in pts) (x.clamp(0.0, 1.0), y.clamp(0.0, 1.0)),
      ]),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is LayoutShape && listEquals(other.points, points);

  @override
  int get hashCode => Object.hashAll(points);
}

double _round4(double v) => (v * 10000).round() / 10000;

/// `[[x, y], …]` 读成一串点;不是三个以上的数对返回 null。
List<(double, double)>? _pairs(Object? j) {
  if (j is! List || j.length < minShapePoints) return null;
  final out = <(double, double)>[];
  for (final p in j.take(maxShapePoints * 2)) {
    if (p is! List || p.length < 2 || p[0] is! num || p[1] is! num) return null;
    out.add(((p[0] as num).toDouble(), (p[1] as num).toDouble()));
  }
  return out;
}

/// 一串点按它们的外框换成 0–1 的比例(挤成一条线的那个方向放在正中)。
List<(double, double)> _normalize(List<(double, double)> pts) {
  final xs = pts.map((p) => p.$1), ys = pts.map((p) => p.$2);
  final x0 = xs.reduce(math.min), x1 = xs.reduce(math.max);
  final y0 = ys.reduce(math.min), y1 = ys.reduce(math.max);
  double f(double v, double a, double b) =>
      b - a < 1e-9 ? 0.5 : (v - a) / (b - a);
  return List.unmodifiable([
    for (final (x, y) in pts) (f(x, x0, x1), f(y, y0, y1)),
  ]);
}

/// 框和它的形状在画布上的样子。
extension LayoutBoxShape on LayoutBox {
  /// 多边形各顶点在画布上的位置(像素);方框、椭圆是空的。
  List<(double, double)> get shapePoints => [
    for (final (x, y) in shape?.points ?? const <(double, double)>[])
      (left + x * width, top + y * height),
  ];

  /// 画布上的 ([x], [y]) 在不在它的形状里(方框就看框)。
  bool covers(double x, double y) {
    if (x < left || x > right || y < top || y > bottom) return false;
    final s = shape;
    if (s == null) return true;
    if (s.isEllipse) {
      final rx = width / 2, ry = height / 2;
      final dx = (x - left - rx) / rx, dy = (y - top - ry) / ry;
      return dx * dx + dy * dy <= 1;
    }
    // 射线法:往右数穿过几条边。
    final pts = shapePoints;
    var inside = false;
    for (var i = 0, j = pts.length - 1; i < pts.length; j = i++) {
      final (xi, yi) = pts[i];
      final (xj, yj) = pts[j];
      if ((yi > y) != (yj > y) && x < (xj - xi) * (y - yi) / (yj - yi) + xi) {
        inside = !inside;
      }
    }
    return inside;
  }

  /// 第 [k] 个顶点挪到画布上的 ([x], [y]):框换成新的外框,各顶点按新框重新算比例。
  /// 挤得太扁(外框有一边不到两个像素)时不动。
  LayoutBox withVertex(int k, double x, double y) {
    final pts = shapePoints;
    if (k < 0 || k >= pts.length) return this;
    pts[k] = (x, y);
    final xs = pts.map((p) => p.$1), ys = pts.map((p) => p.$2);
    final l = xs.reduce(math.min).round(), r = xs.reduce(math.max).round();
    final t = ys.reduce(math.min).round(), b = ys.reduce(math.max).round();
    if (r - l < 2 || b - t < 2) return this;
    return copyWith(
      left: l,
      top: t,
      right: r,
      bottom: b,
      shape: () => LayoutShape.polygon(
        List.unmodifiable([
          for (final (px, py) in pts) ((px - l) / (r - l), (py - t) / (b - t)),
        ]),
      ),
    );
  }

  /// 给 Agent 看的形状:椭圆写 `"ellipse"`,多边形写各顶点的画布像素(和 bbox 同一套坐标)。
  Object? get draftShape => switch (shape) {
    null => null,
    final s when s.isEllipse => 'ellipse',
    _ => [
      for (final (x, y) in shapePoints) [x.round(), y.round()],
    ],
  };
}
