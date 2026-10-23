import 'layout.dart';

/// 程序按框算出来的位置关系,发给 Agent 前接在【布局画板】后面(发给模型的话,不翻译)。
/// MOSS-Image 看不到图层,前后遮挡只能靠描述写出来;模型自己看坐标常漏掉谁压着谁、
/// 谁贴着画面的边被裁掉,出图时位置关系就乱了。所以这里替它算好,让它照着写进描述。
///
/// 写三样:每块在画面的哪里、占多大、贴着哪条边;两块重叠时谁在前、挡住后面那块的
/// 哪一部分、挡住多少;一块整个落在另一块里面。转到镜头外的块不算。
String layoutRelations(Layout l) {
  final shown = [
    for (final (i, b) in l.boxes.indexed)
      if (!b.offscreen) (i, b),
  ];
  if (shown.isEmpty) return '';
  final lines = <String>[
    for (final (i, b) in shown) '- ${_name(b, i)}:${_where(b, l)}',
  ];
  // boxes 从前往后排,所以一对里序号小的在前面。
  for (var x = 0; x < shown.length; x++) {
    for (var y = x + 1; y < shown.length; y++) {
      final line = _overlap(shown[x], shown[y]);
      if (line != null) lines.add('- $line');
    }
  }
  return '【位置关系】程序按框算的,写布局和描述时照这个把位置、前后遮挡写清楚'
      '(MOSS-Image 看不到图层,只能从描述里知道谁在前、谁挡着谁):\n'
      '${lines.join('\n')}\n'
      '要求:summary.caption 把上面每一处遮挡都写出来;重叠的两块,各自的 caption 里也要写'
      '(前面那块写它挡在谁前面、压住对方哪部分,后面那块写哪部分被谁挡住、露出哪部分);'
      '贴着画面边、被裁掉的写 "cropped by the bottom edge" 这类话;每块的 caption 写上它在画面的位置'
      '("in the upper left of the frame")。改了框或前后,这些关系跟着变,照新的写。';
}

String _name(LayoutBox b, int i) =>
    '「${b.name.trim().isEmpty ? '第 ${i + 1} 块' : b.name.trim()}」';

/// 一块在画面的哪里(按中心落在九宫格的哪一格)、占多大、贴着哪条边。
String _where(LayoutBox b, Layout l) {
  final cx = (b.left + b.right) / 2 / l.width;
  final cy = (b.top + b.bottom) / 2 / l.height;
  final area = b.width * b.height * 100 / (l.width * l.height);
  final edges = [
    if (b.top <= l.height * 0.01) '上边',
    if (b.bottom >= l.height * 0.99) '下边',
    if (b.left <= l.width * 0.01) '左边',
    if (b.right >= l.width * 0.99) '右边',
  ];
  final across = b.width >= l.width * 0.9 ? ',横贯整个宽度' : '';
  return '画面${_cell(cx, cy)},占画面 ${area.round()}%$across'
      '${edges.isEmpty ? '' : ',贴着画面${edges.join('、')}(超出的部分被裁掉)'}';
}

/// 按 0–1 的位置说在画面哪一格:左上、上方居中、正中……
String _cell(double x, double y) {
  final (h, v) = _thirds(x, y);
  if (h.isEmpty && v.isEmpty) return '正中';
  if (h.isEmpty) return '$v方居中';
  if (v.isEmpty) return '$h侧居中';
  return '$h$v';
}

/// 按 0–1 的位置说是一块里的哪一部分:左上部、上部、中间……
String _part(double x, double y) {
  final (h, v) = _thirds(x, y);
  if (h.isEmpty && v.isEmpty) return '中间';
  return '$h$v部';
}

(String, String) _thirds(double x, double y) => (
  x < 1 / 3 ? '左' : (x > 2 / 3 ? '右' : ''),
  y < 1 / 3 ? '上' : (y > 2 / 3 ? '下' : ''),
);

/// [inner] 的中心在 [outer] 里的位置(0–1)。
(double, double) _inside(
  int left,
  int top,
  int right,
  int bottom,
  LayoutBox outer,
) => (
  ((left + right) / 2 - outer.left) / outer.width,
  ((top + bottom) / 2 - outer.top) / outer.height,
);

/// 两块重叠时的一句话;不重叠或重叠很少(不到小的那块的 2%)时是 null。
/// [front] 在前面([LayoutBox] 按从前到后排)。
String? _overlap((int, LayoutBox) front, (int, LayoutBox) back) {
  final (fi, f) = front;
  final (bi, b) = back;
  final left = f.left > b.left ? f.left : b.left;
  final right = f.right < b.right ? f.right : b.right;
  final top = f.top > b.top ? f.top : b.top;
  final bottom = f.bottom < b.bottom ? f.bottom : b.bottom;
  if (right <= left || bottom <= top) return null;
  final shared = (right - left) * (bottom - top);
  final smaller = [
    f.width * f.height,
    b.width * b.height,
  ].reduce((a, c) => a < c ? a : c);
  if (shared < smaller * 0.02) return null;
  final a = _name(f, fi), c = _name(b, bi);
  final (x, y) = _inside(left, top, right, bottom, b);
  if (left == f.left &&
      right == f.right &&
      top == f.top &&
      bottom == f.bottom) {
    return '$a整个落在$c的范围里、在它前面,压在$c的${_part(x, y)}';
  }
  final covered = shared * 100 / (b.width * b.height);
  final part = _part(x, y);
  return covered >= 90
      ? '$a在$c前面,几乎整个挡住了它(${covered.round()}%):'
            '要么换前后,要么描述里写清$c从哪里露出来'
      : '$a在$c前面,挡住$c的$part约 ${covered.round()}%';
}
