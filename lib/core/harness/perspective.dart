import 'package:flutter/foundation.dart';

/// 区域控制画板上的透视辅助线(像 Photoshop 拉的透视线):一条地平线,
/// 地平线上一到两个消失点,三点透视再加一个竖直方向的消失点。
/// 坐标是左上角原点的画布像素,和框一样。只在 Penna 里用,交出去的 JSON 里没有它;
/// 发给模型时换成一段话([describe]),让它照这个透视写机位和每一块。
@immutable
class Perspective {
  const Perspective({required this.horizon, required this.xs, this.third});

  /// 一点(1)、两点(2)、三点(3)透视的默认样子:地平线在正中。
  factory Perspective.preset(int points, int width, int height) => Perspective(
    horizon: height ~/ 2,
    xs: points == 1 ? [width ~/ 2] : [0, width],
    third: points == 3 ? (x: width ~/ 2, y: 0) : null,
  );

  /// 地平线的 y。
  final int horizon;

  /// 地平线上各消失点的 x(一个或两个)。
  final List<int> xs;

  /// 竖直方向的第三个消失点(三点透视才有)。
  final ({int x, int y})? third;

  int get points => xs.length + (third == null ? 0 : 1);

  Perspective copyWith({
    int? horizon,
    List<int>? xs,
    ({int x, int y})? third,
  }) => Perspective(
    horizon: horizon ?? this.horizon,
    xs: List.unmodifiable(xs ?? this.xs),
    third: third ?? this.third,
  );

  /// 换画布尺寸时按比例跟着缩放。
  Perspective scaled(double sx, double sy) => Perspective(
    horizon: (horizon * sy).round(),
    xs: List.unmodifiable([for (final x in xs) (x * sx).round()]),
    third: third == null
        ? null
        : (x: (third!.x * sx).round(), y: (third!.y * sy).round()),
  );

  Map<String, Object> toJson() => {
    'horizon': horizon,
    'xs': xs,
    if (third != null) 'third': [third!.x, third!.y],
  };

  static Perspective? fromJson(Object? j) {
    if (j is! Map || j['horizon'] is! num || j['xs'] is! List) return null;
    final xs = [
      for (final x in j['xs'] as List)
        if (x is num) x.round(),
    ];
    if (xs.isEmpty || xs.length > 2) return null;
    final t = j['third'];
    return Perspective(
      horizon: (j['horizon'] as num).round(),
      xs: List.unmodifiable(xs),
      third: t is List && t.length == 2 && t[0] is num && t[1] is num
          ? (x: (t[0] as num).round(), y: (t[1] as num).round())
          : null,
    );
  }

  /// 说给模型听:几点透视、地平线和各消失点在画面哪里、这意味着什么机位。
  String describe(int width, int height) {
    String pct(int v, int side) => '${(v * 100 / side).round()}%';
    final h = horizon / height;
    final eye = h < 0.4
        ? '地平线偏高,镜头朝下看(俯视)'
        : h > 0.6
        ? '地平线偏低,镜头朝上看(仰视),人物和高的东西显得高大'
        : '地平线在中间附近,平视';
    final vps = [
      for (final (i, x) in xs.indexed)
        '${xs.length == 1 ? '消失点' : '消失点 ${i + 1}'}在横向 ${pct(x, width)}、纵向 ${pct(horizon, height)}',
    ];
    final t = third;
    final vertical = t == null
        ? ''
        : '第三个消失点在横向 ${pct(t.x, width)}、纵向 ${pct(t.y, height)},'
              '${t.y < horizon ? '竖直的线往上收拢,越高的地方越窄,是从下往上看的仰视' : '竖直的线往下收拢,是从上往下看的俯视'}。';
    return '【透视辅助】用户在画板上拉了透视线(位置从画布左上角量,0% 是左边或顶上):'
        '$points 点透视。地平线在纵向 ${pct(horizon, height)},$eye。'
        '${vps.join(';')}。$vertical'
        '照这个透视写:summary.caption 写清机位高低、视角和透视的强弱;'
        '每一块的 caption 写它朝哪个消失点延伸、近大远小的方向,'
        '人物写清从这个视角看到的样子(仰视看得到下巴和下侧,俯视看得到头顶和肩)。'
        '框的位置和大小也要顺着透视:离消失点越近的东西越小。';
  }
}
