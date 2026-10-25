part of 'layout_camera.dart';

/// 新灯和换色时用的色板、常用色温(照 lighting-kit)。
const _swatches = [
  '#ff3b30',
  '#ff9500',
  '#ffd60a',
  '#34c759',
  '#20c8ff',
  '#0a84ff',
  '#8e5cf7',
  '#ff2e88',
  '#ffffff',
];

/// 摄像机栏里的「灯光」:开关、预设、跟随镜头、灯光球(拖手柄改方向)、选中那盏灯的参数、
/// 环境光和氛围;最下面是交出去时接在整体描述后的那句。本质是一句光影提示词,
/// 球和手柄只是方便看(用户要求;Agent 用 `<lighting>` 改同一份)。
class _LightingSection extends StatefulWidget {
  const _LightingSection({required this.board});

  final LayoutBoard board;

  @override
  State<_LightingSection> createState() => _LightingSectionState();
}

class _LightingSectionState extends State<_LightingSection> {
  /// 选中的那盏灯;没选过或被删了就是第一盏。
  String? _picked;

  LayoutBoard get board => widget.board;
  Lighting get lg => board.layout.lighting;
  Camera get cam => board.layout.camera;

  void _put(Lighting next, [String? action]) =>
      board.setLighting(next, action: action);

  /// 一行参数,拖动时只在开始那一帧记操作。
  Widget _dial(
    String label,
    double value,
    String unit,
    double step,
    double perPx,
    Lighting Function(double) apply,
  ) => _Dial(
    label: label,
    value: value,
    unit: unit,
    step: step,
    perPx: perPx,
    onStart: () => board.mark(tr('调整灯光')),
    onEnd: () => board.mark(null),
    onChanged: (v, {required bool step}) =>
        _put(apply(v), step ? tr('调整灯光') : null),
  );

  @override
  Widget build(BuildContext context) {
    final on = lg.enabled;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Divider(height: 1),
        Padding(
          padding: const EdgeInsets.fromLTRB(10, 4, 4, 0),
          child: Row(
            children: [
              Icon(Icons.wb_sunny_outlined, size: 14, color: PennaColors.amber),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  tr('灯光'),
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Transform.scale(
                scale: 0.7,
                child: Switch(
                  value: on,
                  onChanged: (v) => _put(
                    enableLighting(lg, v, cam),
                    v ? tr('打开灯光') : tr('关掉灯光'),
                  ),
                ),
              ),
            ],
          ),
        ),
        if (on) ..._body(),
      ],
    );
  }

  List<Widget> _body() {
    final lights = lg.lights;
    final sel =
        lights.where((l) => l.id == _picked).firstOrNull ?? lights.firstOrNull;
    final preset = findPreset(lg.preset);
    final phrase = lightingPhrase(lg, cam, zh: isCjk(board.layout.caption));
    return [
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Row(
          children: [
            Expanded(
              child: PopupMenuButton<String>(
                tooltip: tr('打光预设'),
                onSelected: (id) {
                  _picked = null;
                  _put(presetLighting(id, cam, lg), tr('套用灯光预设'));
                },
                itemBuilder: (_) => [
                  for (final p in lightPresets)
                    PopupMenuItem(
                      value: p.id,
                      height: 32,
                      child: Text(
                        tr(p.name),
                        style: const TextStyle(fontSize: 12.5),
                      ),
                    ),
                ],
                child: Container(
                  height: 26,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  decoration: BoxDecoration(
                    color: PennaColors.slate50,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: PennaColors.border),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          preset == null ? tr('自定义') : tr(preset.name),
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 12),
                        ),
                      ),
                      Icon(
                        Icons.expand_more,
                        size: 15,
                        color: PennaColors.slate500,
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(width: 6),
            Tooltip(
              message: lg.follow ? tr('灯跟着镜头转') : tr('灯固定在场景里,转镜头时光线相对画面会变'),
              child: PennaChip(
                label: tr('跟随镜头'),
                selected: lg.follow,
                onTap: () => _put(setFollow(lg, !lg.follow, cam), tr('调整灯光')),
              ),
            ),
          ],
        ),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(8, 6, 8, 0),
        child: Align(
          alignment: Alignment.centerLeft,
          child: ValueListenableBuilder(
            valueListenable: board.shadePreview,
            builder: (context, on, _) => Tooltip(
              message: tr('体块和画布按灯光显示明暗'),
              child: PennaChip(
                label: tr('光影预览'),
                selected: on,
                onTap: () => board.shadePreview.value = !on,
              ),
            ),
          ),
        ),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
        child: _LightBall(
          lighting: lg,
          camera: cam,
          selected: sel?.id,
          onPick: (id) => setState(() => _picked = id),
          onStart: () => board.mark(tr('拖动灯光')),
          onMove: (id, a) => _put(
            updateLight(lg, id, {
              'azimuth': a.azimuth,
              'elevation': a.elevation,
            }),
          ),
          onEnd: () => board.mark(null),
        ),
      ),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Wrap(
          spacing: 4,
          runSpacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            for (final (i, l) in lights.indexed)
              PennaChip(
                label: '${i + 1} ${tr(lightRoleInfo[l.role]!.zh)}',
                selected: l.id == sel?.id,
                onTap: () => setState(() => _picked = l.id),
              ),
            if (lights.length < maxLights)
              PopupMenuButton<String>(
                tooltip: tr('加一盏灯'),
                icon: const Icon(Icons.add, size: 16),
                padding: EdgeInsets.zero,
                onSelected: (role) {
                  final next = addLight(lg, role, cam);
                  _picked = next.lights.last.id;
                  _put(next, tr('加一盏灯'));
                },
                itemBuilder: (_) => [
                  for (final r in lightRoles)
                    PopupMenuItem(
                      value: r,
                      height: 32,
                      child: Text(
                        tr(lightRoleInfo[r]!.zh),
                        style: const TextStyle(fontSize: 12.5),
                      ),
                    ),
                ],
              ),
          ],
        ),
      ),
      if (sel != null) ..._lightRows(sel),
      const SizedBox(height: 4),
      _dial(
        tr('环境光'),
        lg.ambient,
        '',
        0.05,
        0.003,
        (v) => lg.patch({'ambient': v}),
      ),
      _dial(
        tr('环境色温'),
        lg.ambientKelvin.toDouble(),
        'K',
        500,
        20,
        (v) => lg.patch({'ambient_kelvin': v}),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(8, 6, 8, 0),
        child: Wrap(
          spacing: 4,
          runSpacing: 4,
          children: [
            for (final e in lightExtras)
              PennaChip(
                label: tr(e.label),
                selected: lg.extras.contains(e.id),
                onTap: () => _put(toggleExtra(lg, e.id), tr('调整灯光')),
              ),
          ],
        ),
      ),
      if (phrase.isNotEmpty)
        Padding(
          padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
          child: Tooltip(
            message: tr('导出时接在整体描述后面'),
            child: SelectableText(
              phrase,
              style: TextStyle(
                fontSize: 11,
                height: 1.4,
                color: PennaColors.slate500,
              ),
            ),
          ),
        ),
    ];
  }

  /// 选中那盏灯的参数:方位(相对镜头)、高度、强度、软硬、色温或颜色,能删、能换角色。
  List<Widget> _lightRows(Light l) {
    final rel = relDir(l, lg, cam);
    Lighting set(Map<String, Object?> f) => updateLight(lg, l.id, f);
    return [
      Padding(
        padding: const EdgeInsets.fromLTRB(8, 6, 4, 2),
        child: Row(
          children: [
            Expanded(
              child: PopupMenuButton<String>(
                tooltip: tr('换角色'),
                onSelected: (r) => _put(set({'role': r}), tr('调整灯光')),
                itemBuilder: (_) => [
                  for (final r in lightRoles)
                    PopupMenuItem(
                      value: r,
                      height: 32,
                      child: Text(
                        tr(lightRoleInfo[r]!.zh),
                        style: const TextStyle(fontSize: 12.5),
                      ),
                    ),
                ],
                child: Row(
                  children: [
                    Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        color: Color(
                          int.parse(l.color.substring(1), radix: 16) |
                              0xFF000000,
                        ),
                        shape: BoxShape.circle,
                        border: Border.all(color: PennaColors.border),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        directionText(rel.h, rel.v, zh: true),
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11.5,
                          color: PennaColors.slate700,
                        ),
                      ),
                    ),
                    Icon(
                      Icons.expand_more,
                      size: 14,
                      color: PennaColors.slate500,
                    ),
                  ],
                ),
              ),
            ),
            IconButton(
              tooltip: tr('删掉这盏灯'),
              iconSize: 14,
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.delete_outline),
              onPressed: () => _put(removeLight(lg, l.id), tr('删掉一盏灯')),
            ),
          ],
        ),
      ),
      _dial(
        tr('方位'),
        rel.h,
        '°',
        15,
        0.5,
        (v) => set({'azimuth': toStoredAzimuth(v, lg, cam)}),
      ),
      _dial(tr('高度'), l.elevation, '°', 5, 0.3, (v) => set({'elevation': v})),
      _dial(
        tr('强度'),
        l.intensity,
        '',
        0.1,
        0.005,
        (v) => set({'intensity': v}),
      ),
      _dial(tr('软硬'), l.softness, '', 0.05, 0.003, (v) => set({'softness': v})),
      _dial(
        tr('色温'),
        (l.kelvin ?? 6500).toDouble(),
        'K',
        100,
        20,
        (v) => set({'kelvin': v}),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(10, 4, 10, 0),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            for (final c in _swatches)
              Tooltip(
                message: tr('彩色灯'),
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: () =>
                      _put(set({'kelvin': null, 'color': c}), tr('调整灯光')),
                  child: Container(
                    width: 16,
                    height: 16,
                    decoration: BoxDecoration(
                      color: Color(
                        int.parse(c.substring(1), radix: 16) | 0xFF000000,
                      ),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: l.kelvin == null && l.color == c
                            ? PennaColors.text
                            : PennaColors.border,
                        width: l.kelvin == null && l.color == c ? 2 : 1,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    ];
  }
}

/// 灯光球:从镜头看主体,球按现在的灯照亮;每盏灯一个带序号的手柄,拖着改方向,
/// 拖出球边就翻到背面(背面的手柄是空心的)。
class _LightBall extends StatefulWidget {
  const _LightBall({
    required this.lighting,
    required this.camera,
    required this.selected,
    required this.onPick,
    required this.onStart,
    required this.onMove,
    required this.onEnd,
  });

  final Lighting lighting;
  final Camera camera;
  final String? selected;
  final ValueChanged<String> onPick;
  final VoidCallback onStart, onEnd;
  final void Function(String id, ({double azimuth, double elevation}) to)
  onMove;

  @override
  State<_LightBall> createState() => _LightBallState();
}

class _LightBallState extends State<_LightBall> {
  ui.Image? _image;
  Object? _for;

  /// 正在拖的灯,和按下时它在正面(1)还是背面(-1)。
  String? _drag;
  int _front = 1;

  @override
  void dispose() {
    _image?.dispose();
    super.dispose();
  }

  /// 球的像素在别的线程外算不值当(最多 256×256):灯或镜头变了就重算一张。
  void _render(int px) {
    final key = (widget.lighting, widget.camera, px);
    if (key == _for) return;
    _for = key;
    ui.decodeImageFromPixels(
      renderLitSphere(px, widget.lighting, widget.camera),
      px,
      px,
      ui.PixelFormat.rgba8888,
      (img) {
        if (!mounted || _for != key) return img.dispose();
        setState(() {
          _image?.dispose();
          _image = img;
        });
      },
    );
  }

  /// 各盏灯的手柄在球上的位置(相对球心,半径为 1;y 朝下)和在不在正面。
  List<(Light, Offset, bool)> get _handles => [
    for (final l in widget.lighting.lights)
      if (relDir(l, widget.lighting, widget.camera) case final r)
        (l, Offset(r.side, -r.up), r.front >= 0),
  ];

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, box) {
        final size = math.min(box.maxWidth, 180.0);
        final dpr = MediaQuery.devicePixelRatioOf(context);
        _render((size * dpr).round().clamp(32, 256));
        final radius = size / 2 - 1;
        final center = Offset(size / 2, size / 2);
        String? hit(Offset p) {
          String? best;
          var bestD = 14.0;
          for (final (l, at, front) in _handles) {
            // 正面的优先:背面的离得一样近时让给正面的。
            final d = (center + at * radius - p).distance + (front ? 0 : 4);
            if (d < bestD) {
              best = l.id;
              bestD = d;
            }
          }
          return best;
        }

        return Center(
          child: SizedBox(
            width: size,
            height: size,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              dragStartBehavior: DragStartBehavior.down,
              onTapUp: (d) {
                final id = hit(d.localPosition);
                if (id != null) widget.onPick(id);
              },
              onPanStart: (d) {
                final id = hit(d.localPosition);
                if (id == null) return;
                _drag = id;
                _front = _handles.firstWhere((h) => h.$1.id == id).$3 ? 1 : -1;
                widget.onPick(id);
                widget.onStart();
              },
              onPanUpdate: (d) {
                final id = _drag;
                if (id == null) return;
                final p = (d.localPosition - center) / radius;
                final rel = ballPointToRel(p.dx, -p.dy, _front);
                widget.onMove(
                  id,
                  fromRel(
                    rel.side,
                    rel.up,
                    rel.front,
                    widget.lighting,
                    widget.camera,
                  ),
                );
              },
              onPanEnd: (_) => _endDrag(),
              onPanCancel: _endDrag,
              child: CustomPaint(
                painter: _BallPainter(
                  _image,
                  _handles,
                  widget.selected,
                  PennaColors.border,
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  void _endDrag() {
    if (_drag == null) return;
    _drag = null;
    widget.onEnd();
  }
}

class _BallPainter extends CustomPainter {
  _BallPainter(this.image, this.handles, this.selected, this.rim);

  final ui.Image? image;
  final List<(Light, Offset, bool)> handles;
  final String? selected;
  final Color rim;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.width / 2 - 1;
    canvas.drawCircle(center, radius, Paint()..color = const Color(0xFF2B2824));
    final img = image;
    if (img != null) {
      paintImage(
        canvas: canvas,
        rect: Offset.zero & size,
        image: img,
        filterQuality: FilterQuality.medium,
      );
    }
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..color = rim
        ..style = PaintingStyle.stroke,
    );
    // 背面的先画,正面的盖在上面。
    for (final (i, (l, at, front)) in [
      ...handles.indexed.where((h) => !h.$2.$3),
      ...handles.indexed.where((h) => h.$2.$3),
    ]) {
      final c = center + at * radius;
      final (r, g, b) = lightRgb(l);
      final color = Color.fromARGB(
        255,
        (r * 255).round(),
        (g * 255).round(),
        (b * 255).round(),
      );
      final big = l.id == selected;
      final rad = big ? 9.0 : 7.5;
      canvas.drawCircle(
        c,
        rad,
        Paint()..color = front ? color : color.withValues(alpha: 0.25),
      );
      canvas.drawCircle(
        c,
        rad,
        Paint()
          ..color = big ? Colors.white : const Color(0xFF1F2533)
          ..style = PaintingStyle.stroke
          ..strokeWidth = big ? 2.2 : 1.2,
      );
      final label = TextPainter(
        text: TextSpan(
          text: '${i + 1}',
          style: TextStyle(
            fontSize: 9.5,
            fontWeight: FontWeight.w700,
            color: front && (r + g + b) > 1.8
                ? const Color(0xFF1F2533)
                : Colors.white,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      label.paint(canvas, c - Offset(label.width / 2, label.height / 2));
    }
  }

  @override
  bool shouldRepaint(_BallPainter old) =>
      old.image != image ||
      old.selected != selected ||
      old.rim != rim ||
      !listEquals(
        [for (final h in old.handles) (h.$1, h.$2, h.$3)],
        [for (final h in handles) (h.$1, h.$2, h.$3)],
      );
}
