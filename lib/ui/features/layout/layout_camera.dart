import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../../../core/harness/layout.dart';
import '../../core/theme.dart';
import '../../../l10n/l10n.dart';
import 'layout_bodies.dart';
import 'layout_board.dart';
import 'layout_canvas.dart';

const _panelWidth = 232.0;
const _sceneHeight = 150.0;

/// 拖小场景时每移动一个屏幕像素转多少度。
const _orbitPerPx = 0.6, _pitchPerPx = 0.4;

/// 3D 视图里画布右上角的摄像机面板:上面是小场景(拖着转镜头、滚轮推拉),
/// 下面一行一个参数(两边的箭头一步一步调,按住中间左右拖着调),
/// 最底下是交给 Agent 的两件事。
class CameraPanel extends StatefulWidget {
  const CameraPanel({
    super.key,
    required this.board,
    required this.onRedescribe,
    required this.onEstimate,
  });

  final LayoutBoard board;

  /// 镜头转过了:让 Agent 照新视角改描述。
  final VoidCallback onRedescribe;

  /// 有体块是程序猜的:让 Agent 估。
  final VoidCallback onEstimate;

  @override
  State<CameraPanel> createState() => _CameraPanelState();
}

class _CameraPanelState extends State<CameraPanel> {
  bool _open = true;
  Camera? _dragFrom;
  Offset _dragStart = Offset.zero;

  LayoutBoard get board => widget.board;

  @override
  Widget build(BuildContext context) {
    final cam = board.layout.camera;
    final dials =
        <
          ({
            String label,
            String unit,
            double value,
            double step,
            double perPx,
            Camera Function(double) apply,
          })
        >[
          (
            label: tr('环绕'),
            unit: '°',
            value: cam.orbit,
            step: 15,
            perPx: 0.5,
            apply: (v) => cam.copyWith(orbit: v),
          ),
          (
            label: tr('俯仰'),
            unit: '°',
            value: cam.pitch,
            step: 5,
            perPx: 0.3,
            apply: (v) => cam.copyWith(pitch: v),
          ),
          (
            label: tr('滚转'),
            unit: '°',
            value: cam.roll,
            step: 5,
            perPx: 0.3,
            apply: (v) => cam.copyWith(roll: v),
          ),
          (
            label: tr('距离'),
            unit: '',
            value: cam.distance,
            step: 0.1,
            perPx: 0.01,
            apply: (v) => cam.copyWith(distance: v),
          ),
          (
            label: tr('视角'),
            unit: '°',
            value: cam.fov,
            step: 5,
            perPx: 0.2,
            apply: (v) => cam.copyWith(fov: v),
          ),
          (
            label: tr('平移 X'),
            unit: '',
            value: cam.panX,
            step: 0.1,
            perPx: 0.005,
            apply: (v) => cam.copyWith(panX: v),
          ),
          (
            label: tr('平移 Y'),
            unit: '',
            value: cam.panY,
            step: 0.1,
            perPx: 0.005,
            apply: (v) => cam.copyWith(panY: v),
          ),
          (
            label: tr('平移 Z'),
            unit: '',
            value: cam.panZ,
            step: 0.1,
            perPx: 0.005,
            apply: (v) => cam.copyWith(panZ: v),
          ),
        ];
    return Container(
      width: _panelWidth,
      decoration: BoxDecoration(
        color: PennaColors.card,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: PennaColors.border),
        boxShadow: const [BoxShadow(color: Color(0x1F000000), blurRadius: 14)],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _header(cam),
          if (_open) ...[
            const Divider(height: 1),
            _scene(),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Column(
                children: [
                  for (final d in dials)
                    _Dial(
                      label: d.label,
                      value: d.value,
                      unit: d.unit,
                      step: d.step,
                      perPx: d.perPx,
                      onStart: () => board.mark(tr('调整镜头的{0}', [d.label])),
                      onEnd: () => board.mark(null),
                      onChanged: (v, {required bool step}) => board.setCamera(
                        d.apply(v),
                        action: step ? tr('调整镜头的{0}', [d.label]) : null,
                      ),
                    ),
                ],
              ),
            ),
            if (board.cameraMoved || board.guessedBodies) ...[
              const Divider(height: 1),
              Padding(
                padding: const EdgeInsets.all(8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  spacing: 6,
                  children: [
                    if (board.cameraMoved)
                      _AgentButton(
                        icon: Icons.edit_note,
                        label: tr('按视角改描述'),
                        onTap: widget.onRedescribe,
                      ),
                    if (board.guessedBodies)
                      _AgentButton(
                        icon: Icons.view_in_ar_outlined,
                        label: tr('让 Agent 估体块'),
                        onTap: widget.onEstimate,
                      ),
                  ],
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }

  Widget _header(Camera cam) => SizedBox(
    height: 34,
    child: Row(
      children: [
        const SizedBox(width: 10),
        Icon(Icons.videocam_outlined, size: 15, color: PennaColors.primary),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            tr('摄像机'),
            style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700),
          ),
        ),
        IconButton(
          tooltip: tr('镜头复位'),
          iconSize: 15,
          visualDensity: VisualDensity.compact,
          icon: const Icon(Icons.restart_alt),
          onPressed: cam.isDefault
              ? null
              : () => board.setCamera(const Camera(), action: tr('镜头复位')),
        ),
        IconButton(
          tooltip: _open ? tr('收起') : tr('展开'),
          iconSize: 16,
          visualDensity: VisualDensity.compact,
          icon: Icon(_open ? Icons.expand_less : Icons.expand_more),
          onPressed: () => setState(() => _open = !_open),
        ),
      ],
    ),
  );

  /// 小场景:左右拖是水平环绕,上下拖是俯仰,滚轮推拉镜头。
  Widget _scene() => Listener(
    onPointerSignal: (e) {
      if (e is! PointerScrollEvent) return;
      final c = board.layout.camera;
      board.setCamera(
        c.copyWith(distance: c.distance * math.exp(e.scrollDelta.dy / 600)),
      );
    },
    child: MouseRegion(
      cursor: SystemMouseCursors.grab,
      child: GestureDetector(
        onPanStart: (d) {
          _dragFrom = board.layout.camera;
          _dragStart = d.localPosition;
          board.mark(tr('转动镜头'));
        },
        onPanUpdate: (d) {
          final from = _dragFrom;
          if (from == null) return;
          final m = d.localPosition - _dragStart;
          board.setCamera(
            from.copyWith(
              orbit: from.orbit + m.dx * _orbitPerPx,
              pitch: from.pitch + m.dy * _pitchPerPx,
            ),
          );
        },
        onPanEnd: (_) => _endDrag(),
        onPanCancel: _endDrag,
        child: SizedBox(
          height: _sceneHeight,
          child: CustomPaint(
            painter: OrbitPainter(
              board.layout,
              layoutBoxColor,
              grid: PennaColors.slate400,
            ),
          ),
        ),
      ),
    ),
  );

  void _endDrag() {
    _dragFrom = null;
    board.mark(null);
  }
}

/// 一行参数:◀ 名字 数值 ▶。点箭头走一步,按住中间左右拖着调。
class _Dial extends StatefulWidget {
  const _Dial({
    required this.label,
    required this.value,
    required this.unit,
    required this.step,
    required this.perPx,
    required this.onStart,
    required this.onEnd,
    required this.onChanged,
  });

  final String label, unit;
  final double value, step, perPx;
  final VoidCallback onStart, onEnd;
  final void Function(double value, {required bool step}) onChanged;

  @override
  State<_Dial> createState() => _DialState();
}

class _DialState extends State<_Dial> {
  double _from = 0, _dx = 0;

  String get _text => widget.unit == '°'
      ? '${widget.value.round()}°'
      : widget.value.toStringAsFixed(2);

  @override
  Widget build(BuildContext context) {
    Widget arrow(IconData icon, double sign) => InkWell(
      borderRadius: BorderRadius.circular(4),
      onTap: () =>
          widget.onChanged(widget.value + sign * widget.step, step: true),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
        child: Icon(icon, size: 14, color: PennaColors.slate500),
      ),
    );
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      child: Container(
        height: 24,
        decoration: BoxDecoration(
          color: PennaColors.slate50,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: PennaColors.border),
        ),
        child: Row(
          children: [
            arrow(Icons.chevron_left, -1),
            Expanded(
              child: MouseRegion(
                cursor: SystemMouseCursors.resizeLeftRight,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onHorizontalDragStart: (_) {
                    _from = widget.value;
                    _dx = 0;
                    widget.onStart();
                  },
                  onHorizontalDragUpdate: (d) {
                    _dx += d.delta.dx;
                    widget.onChanged(_from + _dx * widget.perPx, step: false);
                  },
                  onHorizontalDragEnd: (_) => widget.onEnd(),
                  onHorizontalDragCancel: widget.onEnd,
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          widget.label,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 11.5,
                            color: PennaColors.slate700,
                          ),
                        ),
                      ),
                      Text(
                        _text,
                        style: TextStyle(
                          fontSize: 11.5,
                          fontFeatures: const [FontFeature.tabularFigures()],
                          color: PennaColors.text,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            arrow(Icons.chevron_right, 1),
          ],
        ),
      ),
    );
  }
}

class _AgentButton extends StatelessWidget {
  const _AgentButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => OutlinedButton.icon(
    onPressed: onTap,
    icon: Icon(icon, size: 15),
    label: Text(label, style: const TextStyle(fontSize: 12)),
    style: OutlinedButton.styleFrom(
      visualDensity: VisualDensity.compact,
      foregroundColor: PennaColors.primary,
      side: BorderSide(color: PennaColors.primaryBorder),
    ),
  );
}
