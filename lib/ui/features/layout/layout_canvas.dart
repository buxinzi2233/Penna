import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/harness/layout.dart';
import '../../core/theme.dart';
import 'layout_board.dart';
import 'layout_perspective.dart';
import '../../../l10n/l10n.dart';

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

/// 比这个小(画布像素)的框不算,当成手抖。
const _minBox = 8;

/// 右下角这么大(屏幕像素)的地方按下去是拉大小。
const _handle = 12.0;

enum _Drag { draw, move, resize, vanish }

/// 画布:按画布尺寸等比缩放显示。空白处拖出一个新框,拖框移动,拖右下角改大小,
/// 点一下选中,双击改它的描述,Delete 删掉选中的。框按图层先后画,前景盖住后景。
/// 开了透视辅助时画出透视线,消失点能拖。
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

class _LayoutCanvasState extends State<LayoutCanvas> {
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

  /// 正在画的新框(画布像素)。
  Rect? _drawing;

  LayoutBoard get _board => widget.board;

  @override
  void dispose() {
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
    final i = _board.selected;
    if (e is! KeyDownEvent || i == null) return KeyEventResult.ignored;
    if (e.logicalKey != LogicalKeyboardKey.delete &&
        e.logicalKey != LogicalKeyboardKey.backspace) {
      return KeyEventResult.ignored;
    }
    _board.removeBox(i);
    return KeyEventResult.handled;
  }

  /// 画框的先后:后景、中景、前景,同一层里按先后。后画的盖在上面。
  List<int> get _paintOrder {
    final boxes = _board.layout.boxes;
    int rank(int i) => layoutLayers.indexOf(boxes[i].layer);
    return [for (var i = 0; i < boxes.length; i++) i]
      ..sort((a, b) => rank(a) != rank(b) ? rank(a) - rank(b) : a - b);
  }

  /// 按在了哪个消失点上;没开透视或没按中是 null。
  int? _hitVanishing(Offset p, double scale) {
    final per = _board.layout.perspective;
    if (per == null) return null;
    for (final (i, v) in vanishingPoints(per).indexed) {
      if ((p - v).distance * scale <= _handle) return i;
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

  void _start(Offset p, double scale) {
    // 消失点在最上面,先看是不是按在它上面。
    final v = _hitVanishing(p, scale);
    if (v != null) {
      _drag = _Drag.vanish;
      _target = v;
      _from = p;
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
      _pick(i);
    }
    _from = p;
    setState(() {});
  }

  void _update(Offset p) {
    final l = _board.layout;
    final b = _origin;
    switch (_drag) {
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
      case _Drag.resize when b != null:
        _board.updateBox(
          _target,
          b.copyWith(
            right: math.max(b.left + _minBox, p.dx.round()).clamp(0, l.width),
            bottom: math.max(b.top + _minBox, p.dy.round()).clamp(0, l.height),
          ),
        );
      case _Drag.vanish:
        final per = l.perspective;
        if (per != null) {
          _board.movePerspective(dragVanishing(per, _target, p));
        }
      default:
    }
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
    setState(() {
      _drag = null;
      _drawing = null;
      _origin = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _board,
      builder: (context, _) => LayoutBuilder(
        builder: (context, box) {
          final l = _board.layout;
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
                  },
                  child: MouseRegion(
                    cursor: SystemMouseCursors.precise,
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      // 从按下的那一点算起,不是挪过一小段之后。
                      dragStartBehavior: DragStartBehavior.down,
                      onTapUp: (d) =>
                          _tap(_hit(toCanvas(d.localPosition), scale)),
                      onPanStart: (d) =>
                          _start(toCanvas(d.localPosition), scale),
                      onPanUpdate: (d) => _update(toCanvas(d.localPosition)),
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
          // 中线:abs_centralized 的原点在这里。
          Positioned.fill(
            child: CustomPaint(painter: _CenterLines(PennaColors.border)),
          ),
          if (l.boxes.isEmpty && _drawing == null)
            Center(
              child: Text(
                tr('拖出一个框'),
                style: TextStyle(fontSize: 12, color: PennaColors.slate400),
              ),
            ),
          for (final i in _paintOrder)
            Positioned.fromRect(
              rect: screen(l.boxes[i]),
              child: _BoxView(
                index: i,
                box: l.boxes[i],
                selected: _board.selected == i,
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
  });

  final int index;
  final LayoutBox box;
  final bool selected;

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
              color: color.withValues(alpha: selected ? 0.2 : 0.12),
              border: Border.all(color: color, width: selected ? 2.5 : 1.5),
            ),
            child: ClipRect(
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

class _CenterLines extends CustomPainter {
  _CenterLines(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1;
    canvas
      ..drawLine(
        Offset(size.width / 2, 0),
        Offset(size.width / 2, size.height),
        paint,
      )
      ..drawLine(
        Offset(0, size.height / 2),
        Offset(size.width, size.height / 2),
        paint,
      );
  }

  @override
  bool shouldRepaint(_CenterLines old) => old.color != color;
}
