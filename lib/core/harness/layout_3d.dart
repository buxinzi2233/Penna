import 'layout.dart';

/// 区域控制的 3D 视图怎么带着画板变(摄像机和体块本身在 `camera.dart`):
/// 转镜头时框跟着体块走,2D 里改了框时体块跟着框走。文字块贴在画面上,没有体块。

/// 照 [l] 的镜头重新算各块的框:有体块的投到画布上(出了画布的截掉,整个出去或转到
/// 镜头后面的缩成没有面积,见 [LayoutBox.offscreen]),再按离镜头的远近重排前后:
/// 各层的块数不变,离镜头近的排在前面、拿前面的层。文字块和没有体块的不动。
/// 交回新的各块,每一块带着它原来是第几块(选中的要跟着走)。
List<(int, LayoutBox)> reprojectBoxes(Layout l) {
  final view = CameraView(l.camera, l.width, l.height);
  final kept = <(int, LayoutBox)>[];
  final seen = <(int, LayoutBox, double)>[];
  for (final (i, b) in l.boxes.indexed) {
    final body = b.body;
    if (body == null || b.label == 'text') {
      kept.add((i, b));
      continue;
    }
    final p = projectBody(body, view);
    final box = p == null
        ? null
        : b.copyWith(
            left: p.left.round().clamp(0, l.width),
            top: p.top.round().clamp(0, l.height),
            right: p.right.round().clamp(0, l.width),
            bottom: p.bottom.round().clamp(0, l.height),
          );
    if (box == null || box.offscreen) {
      kept.add((i, b.copyWith(left: 0, top: 0, right: 0, bottom: 0)));
    } else {
      seen.add((i, box, view.toCamera(body.center).z));
    }
  }
  final layers = [for (final s in seen) s.$2.layer]
    ..sort((a, b) => layoutLayers.indexOf(b) - layoutLayers.indexOf(a));
  seen.sort((a, b) => a.$3.compareTo(b.$3));
  return [
    ...kept,
    for (final (k, s) in seen.indexed) (s.$1, s.$2.copyWith(layer: layers[k])),
  ];
}

/// 2D 里改了框(拖动、改大小、换画布):体块跟着调到投影正好是这个框,
/// 远近和朝向不变。调不了(没有面积、在镜头后面)就原样。
LayoutBox refitBody(LayoutBox b, Layout l) {
  final body = b.body;
  if (body == null || b.offscreen) return b;
  final fitted = fitBody(body, b.span, CameraView(l.camera, l.width, l.height));
  return fitted == null ? b : b.copyWith(body: () => fitted);
}

/// 给一块立起体块:照 Agent 写的 [hint],没写就按类别和图层猜一个(记成 guessed)。
/// 文字块不立,有的话也去掉。
LayoutBox liftBox(LayoutBox b, Layout l, [BodyHint? hint]) {
  if (b.label == 'text') return b.copyWith(body: () => null);
  if (b.offscreen) return b;
  return b.copyWith(
    body: () => liftBody(
      b.span,
      CameraView(l.camera, l.width, l.height),
      hint ?? guessBodyHint(b.label, b.layer),
      guessed: hint == null,
    ),
  );
}

/// 还没有体块的块(文字块除外)都猜一个。
List<LayoutBox> liftMissing(Layout l) => [
  for (final b in l.boxes)
    b.body == null && b.label != 'text' ? liftBox(b, l) : b,
];

String _deg(double v) => '${v.round()}°';

/// 告诉 Agent 摄像机现在什么样(发给模型的话,不翻译)。
String describeCamera(Layout l, {required bool threeD}) {
  final c = l.camera;
  final view = threeD ? '用户开着 3D 视图,能转镜头、看到每块的体块' : '用户现在用平面视图';
  final shot = c.isDefault
      ? '镜头正对着画面,没转过。'
      : '镜头水平环绕 ${_deg(c.orbit)}(0 是正面,90 是从主体左侧拍,±180 是从背后拍),'
            '俯仰 ${_deg(c.pitch)}(正数是俯视,负数是仰视),画面歪 ${_deg(c.roll)},'
            '视角 ${_deg(c.fov)},离主体 ${c.distance.toStringAsFixed(2)}(1 是原来的距离)。'
            'bbox 是从这个镜头拍到的样子,描述也要照这个视角写:从背后拍写背影、看不到脸,'
            '俯视写看得到头顶和地面,仰视写看得到下巴和天空,谁挡着谁照现在的前后。';
  return '【摄像机】$view。$shot'
      'items 里的 body 是每块的体块(相对这个镜头量的),写法见技能里的说明。';
}
