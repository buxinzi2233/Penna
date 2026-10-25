import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/harness/layout.dart';

/// 长方体的 12 条棱:两端的角只差一位(见 `Body.corners`)。
const _edges = [
  (0, 1), (2, 3), (4, 5), (6, 7), //
  (0, 2), (1, 3), (4, 6), (5, 7), //
  (0, 4), (1, 5), (2, 6), (3, 7),
];

/// 正面那四个角(第 2 位是 0 的),按一圈的顺序。
const _front = [0, 1, 3, 2];

/// 画一个投好的长方体:正面淡淡地涂一层(看得出朝哪),棱用实线。
void paintCuboid(
  Canvas canvas,
  List<Offset> corners,
  Color color, {
  double width = 1.2,
}) {
  canvas.drawPath(
    Path()..addPolygon([for (final i in _front) corners[i]], true),
    Paint()..color = color.withValues(alpha: 0.14),
  );
  final line = Paint()
    ..color = color.withValues(alpha: 0.9)
    ..strokeWidth = width;
  for (final (a, b) in _edges) {
    canvas.drawLine(corners[a], corners[b], line);
  }
}

/// 长方体的 6 个面:按一圈的四个角,和没转之前的朝向(世界 y 朝下,顶面朝 -y)。
const _faces = [
  ([0, 1, 3, 2], (0.0, 0.0, -1.0)), // 正面
  ([4, 5, 7, 6], (0.0, 0.0, 1.0)), // 背面
  ([0, 2, 6, 4], (-1.0, 0.0, 0.0)),
  ([1, 3, 7, 5], (1.0, 0.0, 0.0)),
  ([0, 1, 5, 4], (0.0, -1.0, 0.0)), // 顶面
  ([2, 3, 7, 6], (0.0, 1.0, 0.0)),
];

/// 光影预览:照 [layout] 的灯光,把体块从 [eye] 看得到的几个面涂上明暗
/// (这块的 [color] 当底色)。[corners] 是 8 个角投到屏幕上的位置。
void paintLitFaces(
  Canvas canvas,
  Body body,
  List<Offset> corners,
  Vec3 eye,
  Color color,
  Layout layout,
) {
  final a = body.yaw * math.pi / 180;
  final c = math.cos(a), s = math.sin(a);
  final world = body.corners;
  for (final (idx, (lx, ly, lz)) in _faces) {
    // 面的朝向跟着体块转(和 Body.corners 同一个转法)。
    final Vec3 n = (x: lx * c + lz * s, y: ly, z: -lx * s + lz * c);
    final mid = (
      x: idx.map((i) => world[i].x).reduce((p, q) => p + q) / 4,
      y: idx.map((i) => world[i].y).reduce((p, q) => p + q) / 4,
      z: idx.map((i) => world[i].z).reduce((p, q) => p + q) / 4,
    );
    final toward =
        n.x * (eye.x - mid.x) + n.y * (eye.y - mid.y) + n.z * (eye.z - mid.z);
    if (toward <= 0) continue; // 背对着镜头,看不到
    final (r, g, b) = shade(
      n,
      (color.r, color.g, color.b),
      layout.lighting,
      layout.camera,
    );
    canvas.drawPath(
      Path()..addPolygon([for (final i in idx) corners[i]], true),
      Paint()..color = Color.from(alpha: 0.92, red: r, green: g, blue: b),
    );
  }
}

/// 画布背景在这套灯光下的颜色(光影预览:暗调的灯光下画布也暗)。
Color litBackdrop(Layout layout) {
  final (r, g, b) = backdropShade(
    (0.97, 0.97, 0.97),
    layout.lighting,
    layout.camera,
  );
  return Color.from(alpha: 1, red: r, green: g, blue: b);
}

/// 主画布上(3D 视图)每块的体块:投到画布上,[scale] 是画布像素到屏幕。屏蔽了的不画。
/// [lit] 为真时按灯光给看得到的面上明暗(光影预览)。
class BodiesPainter extends CustomPainter {
  BodiesPainter(
    this.layout,
    this.scale,
    this.colorOf,
    this.selected, {
    this.lit = false,
  });

  final Layout layout;
  final double scale;
  final Color Function(int) colorOf;
  final int? selected;
  final bool lit;

  @override
  void paint(Canvas canvas, Size size) {
    final view = CameraView(layout.camera, layout.width, layout.height);
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    for (final (i, b) in layout.boxes.indexed.toList().reversed) {
      final body = b.body;
      if (body == null || b.offscreen || !b.shownIn(threeD: true)) continue;
      final pts = [for (final c in body.corners) view.project(c)];
      if (pts.contains(null)) continue;
      final screen = [for (final p in pts) Offset(p!.u * scale, p.v * scale)];
      if (lit) {
        paintLitFaces(canvas, body, screen, view.eye, colorOf(i), layout);
      }
      paintCuboid(canvas, screen, colorOf(i), width: i == selected ? 2 : 1.2);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(BodiesPainter old) =>
      old.layout != layout ||
      old.scale != scale ||
      old.selected != selected ||
      old.lit != lit;
}

/// 摄像机面板里的小场景:斜上方看下去的一个固定视角,画出各块的体块、
/// 粉色的水平环绕圈、青色的俯仰弧和黄色的摄像机(连着它看的目标点)。
class OrbitPainter extends CustomPainter {
  OrbitPainter(this.layout, this.colorOf, {required this.grid});

  final Layout layout;
  final Color Function(int) colorOf;
  final Color grid;

  static const _ring = Color(0xFFF43F5E);
  static const _arc = Color(0xFF06B6D4);
  static const _eye = Color(0xFFF59E0B);

  @override
  void paint(Canvas canvas, Size size) {
    final cam = layout.camera;
    final t = cam.target;
    final r = cam.distance;
    // 看场景的那台"观察镜头":离得远、视角窄,近似平行投影。
    final watcher = CameraView(
      Camera(
        orbit: -35,
        pitch: 28,
        distance: 20,
        fov: 10,
        panX: t.x,
        panY: t.y,
        panZ: t.z - 1,
      ),
      100,
      100,
    );
    Offset? at(Vec3 p) {
      final q = watcher.project(p);
      return q == null ? null : Offset(q.u, q.v);
    }

    final o = cam.orbit * math.pi / 180;
    Vec3 orbitPoint(double a, double e) => (
      x: t.x - r * math.sin(a) * math.cos(e),
      y: t.y - r * math.sin(e),
      z: t.z - r * math.cos(a) * math.cos(e),
    );
    final ring = [
      for (var k = 0; k <= 48; k++) at(orbitPoint(k * math.pi / 24, 0)),
    ];
    final arc = [
      for (var e = -80; e <= 80; e += 5) at(orbitPoint(o, e * math.pi / 180)),
    ];
    final eyeView = CameraView(cam, layout.width, layout.height);
    final eye = at(eyeView.eye);
    final look = at((
      x: eyeView.eye.x + eyeView.fwd.x * r * 0.35,
      y: eyeView.eye.y + eyeView.fwd.y * r * 0.35,
      z: eyeView.eye.z + eyeView.fwd.z * r * 0.35,
    ));
    final bodies = <(int, List<Offset?>)>[
      for (final (i, b) in layout.boxes.indexed)
        if (b.body != null && b.shownIn(threeD: true))
          (i, [for (final c in b.body!.corners) at(c)]),
    ];
    // 把用到的点都框进面板里。
    final all = [
      ...ring,
      ...arc,
      eye,
      at(t),
      for (final b in bodies) ...b.$2,
    ].whereType<Offset>().toList();
    if (all.isEmpty) return;
    var box = Rect.fromPoints(all.first, all.first);
    for (final p in all) {
      box = box.expandToInclude(Rect.fromPoints(p, p));
    }
    const pad = 14.0;
    final k = math.min(
      (size.width - 2 * pad) / math.max(box.width, 1e-6),
      (size.height - 2 * pad) / math.max(box.height, 1e-6),
    );
    final shift = size.center(Offset.zero) - box.center * k;
    Offset? fit(Offset? p) => p == null ? null : p * k + shift;

    void polyline(List<Offset?> pts, Paint paint) {
      for (var i = 0; i + 1 < pts.length; i++) {
        final a = fit(pts[i]), b = fit(pts[i + 1]);
        if (a != null && b != null) canvas.drawLine(a, b, paint);
      }
    }

    polyline(
      ring,
      Paint()
        ..color = _ring.withValues(alpha: 0.85)
        ..strokeWidth = 2.5,
    );
    polyline(
      arc,
      Paint()
        ..color = _arc.withValues(alpha: 0.35)
        ..strokeWidth = 2,
    );
    // 从水平到现在的俯仰角,每 2° 一段。
    final steps = (cam.pitch.abs() / 2).ceil();
    final pitchArc = [
      for (var k = 0; k <= steps; k++)
        at(orbitPoint(o, cam.pitch * k / steps * math.pi / 180)),
    ];
    if (steps > 0) {
      polyline(
        pitchArc,
        Paint()
          ..color = _arc
          ..strokeWidth = 3,
      );
    }
    for (final (i, pts) in bodies) {
      if (pts.contains(null)) continue;
      paintCuboid(canvas, [for (final p in pts) fit(p)!], colorOf(i));
    }
    final target = fit(at(t));
    final e = fit(eye), l = fit(look);
    if (target != null) {
      canvas.drawCircle(target, 2.5, Paint()..color = grid);
    }
    if (e != null && target != null) {
      canvas.drawLine(
        e,
        target,
        Paint()
          ..color = _eye.withValues(alpha: 0.6)
          ..strokeWidth = 1.5,
      );
    }
    final ringDot = fit(at(orbitPoint(o, 0)));
    if (ringDot != null) canvas.drawCircle(ringDot, 5, Paint()..color = _ring);
    if (e != null) {
      if (l != null) {
        canvas.drawLine(
          e,
          l,
          Paint()
            ..color = _eye
            ..strokeWidth = 3,
        );
      }
      canvas
        ..drawCircle(e, 6.5, Paint()..color = _eye)
        ..drawCircle(
          e,
          6.5,
          Paint()
            ..color = Colors.white
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.5,
        );
    }
  }

  @override
  bool shouldRepaint(OrbitPainter old) =>
      old.layout != layout || old.grid != grid;
}
