import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import '../../../core/harness/layout.dart';
import '../../core/theme.dart';
import 'layout_bodies.dart';
import 'layout_board.dart';
import 'layout_perspective.dart';
import '../../../l10n/l10n.dart';

part 'layout_navigation.dart';

/// 框的颜色按先后轮换。用中间色调,深浅两套配色上都看得清。
const _boxColors = [
  Color(0xFF3B82F6),
  Color(0xFF10B981),
  Color(0xFF8B5CF6),
  Color(0xFFF43F5E),
  Color(0xFF06B6D4),
  Color(0xFFF59E0B),
  Color(0xFFD946EF),
];

Color layoutBoxColor(int i) => _boxColors[i % _boxColors.length];

/// 3D 视图里体块的颜色:和框同一色系、浅一档,框(交出去的)和体块一眼分得开。
Color layoutBodyColor(int i) {
  final hsl = HSLColor.fromColor(layoutBoxColor(i));
  return hsl
      .withLightness((hsl.lightness + 0.16).clamp(0.0, 0.85))
      .withSaturation(hsl.saturation * 0.8)
      .toColor();
}

/// 比这个小(画布像素)的框不算,当成手抖。
const _minBox = 8;

/// 右下角这么大(屏幕像素)的地方按下去是拉大小。
const _handle = 12.0;

enum _Drag { draw, move, resize, vanish, look }

/// 画布:按画布尺寸等比缩放显示。空白处拖出一个新框,拖框移动,拖右下角改大小,
/// 点一下选中,双击改它的描述,Delete 删掉选中的。框按图层先后画,前景盖住后景。
/// 开了透视辅助时画出透视线,消失点能拖。3D 视图里画出每块的体块,鼠标和键盘照 Blender
/// 的习惯转镜头(见 [_Navigation])。屏蔽了的块不画、点不中。
class LayoutCanvas extends StatefulWidget {
  const LayoutCanvas({
    super.key,
    required this.board,
    this.onPick,
    this.onEdit,
  });

  final LayoutBoard board;

  /// 在画布上点中了第几块(属性栏滚过去)。
  final ValueChanged<int>? onPick;

  /// 双击了第几块(光标放进它的描述)。
  final ValueChanged<int>? onEdit;

  @override
  State<LayoutCanvas> createState() => _LayoutCanvasState();
}

class _LayoutCanvasState extends State<LayoutCanvas>
    with SingleTickerProviderStateMixin {
  _Drag? _drag;
  int _target = -1;

  /// 按 Delete 要画布有焦点:按下鼠标时拿过来。
  final _focus = FocusNode();

  /// 上一次单击的是哪块、什么时候:再点同一块算双击。不用 onDoubleTap,
  /// 它会让单击等一会儿才生效(同 page_strip 的 _QuickTap)。
  /// 时间用按下那一刻的事件时间戳。
  int? _lastTap;
  var _lastTapAt = Duration.zero, _downAt = Duration.zero;

  /// 按下时的位置(画布像素),和那时被拖的框。
  Offset _from = Offset.zero;
  LayoutBox? _origin;

  /// 上一帧拖完画板上那一块的样子:对不上就是拖到一半画板被换掉了(Agent 放上布局、
  /// 回滚),这次拖动作废,免得照旧序号去改别的块。
  LayoutBox? _dragged;

  /// 正在画的新框(画布像素)。
  Rect? _drawing;

  /// 开始拖消失点时它在哪(画布像素,可以在画面外)。
  Offset _vanishStart = Offset.zero;

  /// 3D 视图里用中键、右键拖镜头:按下的位置、那时的镜头和拖的是哪一种。
  Offset? _camFrom;
  Camera? _camStart;
  _CamDrag _camDrag = _CamDrag.orbit;

  /// 自由镜头里按着 WASDQE 时每帧走一点(见 [_Navigation._walkTick])。
  late final Ticker _walker = createTicker((t) => _walkTick(t));
  Duration _walkedAt = Duration.zero;

  /// 上一帧是不是自由镜头:刚打开时把焦点拿到画布上,WASD 才收得到。
  bool _wasFree = false;

  LayoutBoard get _board => widget.board;

  @override
  void dispose() {
    _walker.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _pick(int? i) {
    _board.select(i);
    if (i != null) widget.onPick?.call(i);
  }

  void _tap(int? i) {
    final second =
        i != null && i == _lastTap && _downAt - _lastTapAt < kDoubleTapTimeout;
    _lastTap = second ? null : i;
    _lastTapAt = _downAt;
    _pick(i);
    if (second) widget.onEdit?.call(i);
  }

  KeyEventResult _key(FocusNode _, KeyEvent e) {
    if (_navKey(e) == KeyEventResult.handled) return KeyEventResult.handled;
    final i = _board.selected;
    if (e is! KeyDownEvent || i == null) return KeyEventResult.ignored;
    if (e.logicalKey != LogicalKeyboardKey.delete &&
        e.logicalKey != LogicalKeyboardKey.backspace) {
      return KeyEventResult.ignored;
    }
    _board.removeBox(i);
    return KeyEventResult.handled;
  }

  /// 画框的先后:画板里的框已经按前后排好(第 0 个在最前,见 `stacked`),
  /// 倒着画,后画的盖在上面。
  List<int> get _paintOrder => [
    for (var i = _board.layout.boxes.length - 1; i >= 0; i--) i,
  ];

  /// 按在了哪个消失点上;没开透视或没按中是 null。画面外的消失点按它在画布边上的
  /// 替身算(见 [vanishMarker])。
  int? _hitVanishing(Offset p, double scale) {
    final l = _board.layout;
    final per = l.perspective;
    if (per == null) return null;
    final canvas = Size(l.width.toDouble(), l.height.toDouble());
    for (final (i, v) in vanishingPoints(per).indexed) {
      final at = vanishMarker(v, canvas, markerInset / scale);
      if ((p - at).distance * scale <= _handle) return i;
    }
    return null;
  }

  int? _hit(Offset p, double scale) {
    final boxes = _board.layout.boxes;
    // 选中的优先,其余盖在上面的优先。
    final order = [
      ?_board.selected,
      for (final i in _paintOrder.reversed)
        if (i != _board.selected) i,
    ];
    for (final i in order) {
      final b = boxes[i];
      if (b.offscreen || !_board.shown(i)) continue;
      final r = Rect.fromLTRB(
        b.left.toDouble(),
        b.top.toDouble(),
        b.right.toDouble(),
        b.bottom.toDouble(),
      ).inflate(_handle / 2 / scale);
      if (r.contains(p)) return i;
    }
    return null;
  }

  /// [raw] 是没截到画布里的那个点(画布像素):拖消失点时要能拖到画面外。
  void _start(Offset p, double scale, Offset raw) {
    // 自由镜头里左键拖动是转头,不碰框。
    if (_board.freeCam) {
      _drag = _Drag.look;
      _from = p * scale;
      _camStart = _board.layout.camera;
      return;
    }
    // 消失点在最上面,先看是不是按在它上面。
    final v = _hitVanishing(p, scale);
    if (v != null) {
      _drag = _Drag.vanish;
      _target = v;
      _from = raw;
      _vanishStart = vanishingPoints(_board.layout.perspective!)[v];
      _board.mark(tr('拖动消失点'));
      return setState(() {});
    }
    final i = _hit(p, scale);
    if (i == null) {
      _drag = _Drag.draw;
      _drawing = Rect.fromPoints(p, p);
      _board.select(null);
    } else {
      final b = _board.layout.boxes[i];
      final corner = Offset(b.right.toDouble(), b.bottom.toDouble());
      _drag = (p - corner).distance * scale <= _handle
          ? _Drag.resize
          : _Drag.move;
      _target = i;
      _origin = b;
      _dragged = b;
      _pick(i);
      // 选中会通知一次,标记要放在它后面,留给接下来真正的改动。
      final name = boxName(b, i);
      _board.mark(
        _drag == _Drag.resize
            ? tr('调整「{0}」的大小', [name])
            : tr('移动「{0}」', [name]),
      );
    }
    _from = p;
    setState(() {});
  }

  void _update(Offset p, double scale, Offset raw) {
    final l = _board.layout;
    final b = _origin;
    if ((_drag == _Drag.move || _drag == _Drag.resize) &&
        !identical(l.boxes.elementAtOrNull(_target), _dragged)) {
      return _end();
    }
    switch (_drag) {
      case _Drag.look:
        final start = _camStart;
        if (start != null) _look(_from, p * scale, start);
      case _Drag.draw:
        setState(() => _drawing = Rect.fromPoints(_from, p));
      case _Drag.move when b != null:
        final dx = (p.dx - _from.dx).round().clamp(-b.left, l.width - b.right);
        final dy = (p.dy - _from.dy).round().clamp(-b.top, l.height - b.bottom);
        _board.updateBox(
          _target,
          b.copyWith(
            left: b.left + dx,
            top: b.top + dy,
            right: b.right + dx,
            bottom: b.bottom + dy,
          ),
        );
        _follow();
      case _Drag.resize when b != null:
        _board.updateBox(
          _target,
          b.copyWith(
            right: math.max(b.left + _minBox, p.dx.round()).clamp(0, l.width),
            bottom: math.max(b.top + _minBox, p.dy.round()).clamp(0, l.height),
          ),
        );
        _follow();
      // 按住时那个消失点在哪,加上鼠标挪了多少;不截到画布里,画面外也拖得到。
      // 3D 视图里拖它就是转镜头(见 LayoutBoard.moveVanishing)。
      case _Drag.vanish:
        final to = _vanishStart + (raw - _from);
        _board.moveVanishing(_target, to.dx, to.dy);
      default:
    }
  }

  /// 改完这一帧:排序变了时跟着选中的那一块(它还是被拖的这块),记下它现在的样子。
  void _follow() {
    _target = _board.selected ?? _target;
    _dragged = _board.layout.boxes.elementAtOrNull(_target);
  }

  void _end() {
    final r = _drawing;
    if (_drag == _Drag.draw && r != null) {
      if (r.width >= _minBox && r.height >= _minBox) {
        _board.addBox(
          LayoutBox(
            left: r.left.round(),
            top: r.top.round(),
            right: r.right.round(),
            bottom: r.bottom.round(),
          ),
        );
      }
    }
    if (_drag == _Drag.look) _camStart = null;
    _board.mark(null);
    setState(() {
      _drag = null;
      _drawing = null;
      _origin = null;
      _dragged = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _board,
      builder: (context, _) => LayoutBuilder(
        builder: (context, box) {
          final l = _board.layout;
          if (_board.freeCam && !_wasFree) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) _focus.requestFocus();
            });
          }
          _wasFree = _board.freeCam;
          final scale = math.min(
            box.maxWidth / l.width,
            box.maxHeight / l.height,
          );
          // 屏幕上的点换成画布像素,不出画布。
          Offset toCanvas(Offset p) => Offset(
            (p.dx / scale).clamp(0.0, l.width.toDouble()),
            (p.dy / scale).clamp(0.0, l.height.toDouble()),
          );
          return Center(
            child: SizedBox(
              width: l.width * scale,
              height: l.height * scale,
              child: Focus(
                focusNode: _focus,
                onKeyEvent: _key,
                child: Listener(
                  onPointerDown: (e) {
                    _downAt = e.timeStamp;
                    _focus.requestFocus();
                    _cameraDown(e);
                  },
                  onPointerMove: (e) => _cameraMove(e, scale),
                  onPointerUp: (_) => _cameraUp(),
                  onPointerCancel: (_) => _cameraUp(),
                  onPointerSignal: _zoom,
                  child: MouseRegion(
                    cursor: _board.freeCam
                        ? SystemMouseCursors.move
                        : SystemMouseCursors.precise,
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      // 从按下的那一点算起,不是挪过一小段之后。
                      dragStartBehavior: DragStartBehavior.down,
                      onTapUp: (d) =>
                          _tap(_hit(toCanvas(d.localPosition), scale)),
                      onPanStart: (d) => _start(
                        toCanvas(d.localPosition),
                        scale,
                        d.localPosition / scale,
                      ),
                      onPanUpdate: (d) => _update(
                        toCanvas(d.localPosition),
                        scale,
                        d.localPosition / scale,
                      ),
                      onPanEnd: (_) => _end(),
                      onPanCancel: _end,
                      child: _paint(l, scale),
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _paint(Layout l, double scale) {
    Rect screen(LayoutBox b) => Rect.fromLTRB(
      b.left * scale,
      b.top * scale,
      b.right * scale,
      b.bottom * scale,
    );
    return DecoratedBox(
      decoration: BoxDecoration(
        color: PennaColors.card,
        border: Border.all(color: PennaColors.border),
        boxShadow: const [BoxShadow(color: Color(0x14000000), blurRadius: 12)],
      ),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // 中心的小十字:abs_centralized 的原点在这里。不画贯穿全画布的中线,
          // 那条横线和透视的地平线长得一样,关了透视还以为没关掉。
          Positioned.fill(
            child: CustomPaint(painter: _CenterMark(PennaColors.slate400)),
          ),
          if (l.boxes.isEmpty && _drawing == null)
            Center(
              child: Text(
                tr('拖出一个框'),
                style: TextStyle(fontSize: 12, color: PennaColors.slate400),
              ),
            ),
          for (final i in _paintOrder)
            if (!l.boxes[i].offscreen && _board.shown(i))
              Positioned.fromRect(
                rect: screen(l.boxes[i]),
                child: _BoxView(
                  index: i,
                  box: l.boxes[i],
                  selected: _board.selected == i,
                  threeD: _board.threeD,
                ),
              ),
          if (_board.threeD)
            Positioned.fill(
              child: IgnorePointer(
                child: CustomPaint(
                  painter: BodiesPainter(
                    l,
                    scale,
                    layoutBodyColor,
                    _board.selected,
                  ),
                ),
              ),
            ),
          if (_drawing != null)
            Positioned.fromRect(
              rect: Rect.fromLTRB(
                _drawing!.left * scale,
                _drawing!.top * scale,
                _drawing!.right * scale,
                _drawing!.bottom * scale,
              ),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: PennaColors.primary.withValues(alpha: 0.08),
                  border: Border.all(color: PennaColors.primary, width: 1.5),
                ),
              ),
            ),
          if (l.perspective != null)
            Positioned.fill(
              child: IgnorePointer(
                child: CustomPaint(
                  painter: PerspectivePainter(
                    l.perspective!,
                    scale,
                    PennaColors.amber,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _BoxView extends StatelessWidget {
  const _BoxView({
    required this.index,
    required this.box,
    required this.selected,
    required this.threeD,
  });

  final int index;
  final LayoutBox box;
  final bool selected;

  /// 3D 视图里框只留边和标题条(底色更淡、不写描述),让位给体块,免得叠得太乱。
  final bool threeD;

  @override
  Widget build(BuildContext context) {
    final color = layoutBoxColor(index);
    final words = box.label == 'text' && box.text.trim().isNotEmpty
        ? '"${box.text.trim()}"'
        : box.caption.trim();
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: color.withValues(
                alpha: threeD
                    ? (selected ? 0.08 : 0.03)
                    : (selected ? 0.2 : 0.12),
              ),
              border: Border.all(color: color, width: selected ? 2.5 : 1.5),
            ),
            child: threeD
                ? null
                : ClipRect(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(6, 22, 6, 4),
                      child: Text(
                        words,
                        overflow: TextOverflow.fade,
                        style: TextStyle(fontSize: 11, color: PennaColors.text),
                      ),
                    ),
                  ),
          ),
        ),
        Positioned(
          left: 0,
          top: 0,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
            color: color,
            child: Text(
              '${index + 1} · ${box.name.trim().isEmpty ? layoutLabelName(box.label) : box.name.trim()}'
              ' · ${layoutLayerName(box.layer)}',
              style: const TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w700,
                color: Colors.white,
              ),
            ),
          ),
        ),
        if (selected)
          Positioned(
            right: -5,
            bottom: -5,
            child: MouseRegion(
              cursor: SystemMouseCursors.resizeDownRight,
              child: Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: Colors.white,
                  border: Border.all(color: color, width: 2),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// 类别显示的名字;存的和发出去的都是英文原值。
String layoutLabelName(String label) => switch (label) {
  'character' => tr('角色'),
  'text' => tr('文字'),
  _ => tr('物体'),
};

/// 图层显示的名字;存的和发给 Agent 的是英文原值。
String layoutLayerName(String layer) => switch (layer) {
  'front' => tr('前景'),
  'back' => tr('后景'),
  _ => tr('中景'),
};

/// 中心十字每条臂的长度(屏幕像素)。
const _markArm = 7.0;

class _CenterMark extends CustomPainter {
  _CenterMark(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1;
    final c = size.center(Offset.zero);
    canvas
      ..drawLine(c.translate(-_markArm, 0), c.translate(_markArm, 0), paint)
      ..drawLine(c.translate(0, -_markArm), c.translate(0, _markArm), paint);
  }

  @override
  bool shouldRepaint(_CenterMark old) => old.color != color;
}
