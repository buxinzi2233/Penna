import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';

import '../../../core/harness/layout.dart';
import '../../../l10n/l10n.dart';

/// 存下来的一个画布尺寸。
typedef LayoutSize = ({int width, int height});

const _defaultSizes = <LayoutSize>[
  (width: defaultLayoutWidth, height: defaultLayoutHeight),
];

/// 布局画板:当前这张布局、选中的框、用户存的几个画布尺寸。存在 layout.json。
/// Agent 写的 `<layout>` 也放到这里(见 `studio_chat.dart` 的 `_deliverLayout`)。
class LayoutBoard extends ChangeNotifier {
  /// [dir] 为 null 时不存盘(测试用)。
  LayoutBoard({this.dir});

  final Directory? dir;

  Layout _layout = const Layout();
  List<LayoutSize> _sizes = List.unmodifiable(_defaultSizes);
  int? _selected;

  /// 框的文字被整个换掉(Agent 放进来、删了框)时加一:输入框靠它重建。
  int _revision = 0;
  Timer? _saveTimer;

  Layout get layout => _layout;
  List<LayoutSize> get sizes => _sizes;
  int? get selected => _selected;
  int get revision => _revision;
  String get json => mossLayoutJson(_layout);

  /// 告诉模型画布尺寸和现有的布局,它写 `<layout>` 时坐标才对得上。
  String get prompt {
    final l = _layout;
    String pct(int v, int side) => '${(v * 100 / side).round()}%';
    // 换成占画布的几成,模型不用自己算坐标也知道每块在哪、多大、和谁挨着。
    final where = [
      for (final (i, b) in l.boxes.indexed)
        '${i + 1}. ${b.name.isEmpty ? '(没起名)' : b.name}'
            '(${b.label},${_layerNames[b.layer]}):'
            '横向 ${pct(b.left, l.width)}–${pct(b.right, l.width)},'
            '纵向 ${pct(b.top, l.height)}–${pct(b.bottom, l.height)}',
    ].join('\n');
    return '【布局画板】画布 ${l.width}×${l.height}(宽×高),'
        'abs_centralized 坐标里 x 从 ${-(l.width ~/ 2)} 到 ${l.width - l.width ~/ 2},'
        'y 从 ${-(l.height ~/ 2)} 到 ${l.height - l.height ~/ 2}。'
        '${l.isEmpty ? '现在是空的。' : '下面是画板此刻的样子:用户可能刚拖过框、改过字或类别,'
                  '一切以这里为准,上文对话里的旧布局不算数'
                  '(你以前写的布局在上文里已省略,只留了一句说明)。'
                  '这次要改布局,就照这里的样子改好,把完整的 JSON 写进 <layout>。'
                  '没让你动的框,bbox 照这里原样抄,label、meta、canvas 也照抄。'
                  'name 是用户给这一块起的名字,他说"把某某挪到……"指的就是它;'
                  '你写的时候照样带着 name,新加的块也起一个两到六个字的中文名。\n'
                  '各块按前后排:1 在最前面,越往后越靠后,重叠时前面的盖住后面的;'
                  'items 也照这个先后写(前景、中景、后景依次),要调前后就换它们的先后;'
                  '只换前后、改名字、换前中后景时写 <layers> 就够了。'
                  '各块在画布上的范围(从左上角量,0% 是左边或顶上):\n$where\n'
                  '<current-layout>\n${mossLayoutJson(l, names: true)}\n</current-layout>'}'
        '\n\n${l.perspective?.describe(l.width, l.height) ?? '【透视辅助】现在关着。'}';
  }

  /// 换成 [layout]:框先按前后排好(见 [stacked])。[follow] 是要跟着选中的那一块
  /// (排序后它的位置可能变了)。框的先后变了时输入框要重建,和 [rebuild] 一样。
  void _set(Layout layout, {bool rebuild = false, LayoutBox? follow}) {
    final boxes = stacked(layout.boxes);
    final reordered = [
      for (final (i, b) in boxes.indexed) identical(b, layout.boxes[i]),
    ].contains(false);
    _layout = layout.copyWith(boxes: boxes);
    if (rebuild || reordered) _revision++;
    if (follow != null) {
      final at = boxes.indexWhere((b) => identical(b, follow));
      _selected = at < 0 ? null : at;
    } else if (_selected != null && _selected! >= boxes.length) {
      _selected = null;
    }
    notifyListeners();
    _scheduleSave();
  }

  void select(int? i) {
    if (_selected == i) return;
    _selected = i;
    notifyListeners();
  }

  /// 换画布尺寸,框按比例跟着缩放。尺寸不在范围内就不换,返回 false。
  bool setSize(int width, int height) {
    if (!_validSide(width) || !_validSide(height)) return false;
    final l = _layout;
    if (width == l.width && height == l.height) return true;
    final sx = width / l.width, sy = height / l.height;
    _set(
      l.copyWith(
        width: width,
        height: height,
        boxes: [for (final b in l.boxes) b.scaled(sx, sy)],
        perspective: () => l.perspective?.scaled(sx, sy),
      ),
    );
    return true;
  }

  /// 开 / 关透视辅助线;[points] 是几点透视(1 到 3),换的时候从默认的样子开始。
  void setPerspective(int? points) => _set(
    _layout.copyWith(
      perspective: () => points == null
          ? null
          : Perspective.preset(points, _layout.width, _layout.height),
    ),
  );

  /// 拖动透视线(画布上拖消失点时用)。
  void movePerspective(Perspective p) =>
      _set(_layout.copyWith(perspective: () => p));

  /// 照 Agent 写的 `<layers>` 调图层(见 [parseLayers]):按给的先后排,顺便改名字和
  /// 前中后景;框的位置和描述一点不动。没写到的块按原来的先后接在后面。
  /// 序号对不上或重复时返回 false,画板不动。
  bool applyLayers(List<LayerOp> ops) {
    final old = _layout.boxes;
    final listed = <int>{};
    for (final op in ops) {
      if (op.from < 1 || op.from > old.length || !listed.add(op.from)) {
        return false;
      }
    }
    _selected = null;
    _set(
      _layout.copyWith(
        boxes: [
          for (final op in ops)
            old[op.from - 1].copyWith(name: op.name, layer: op.layer),
          for (final (i, b) in old.indexed)
            if (!listed.contains(i + 1)) b,
        ],
      ),
      rebuild: true,
    );
    return true;
  }

  /// 照 Agent 写的 `<perspective>` 改透视线(见 [parsePerspective])。
  /// 读不了返回 false,画板不动。
  bool applyPerspective(String spec) {
    final parsed = parsePerspective(spec, _layout.width, _layout.height);
    if (parsed == null) return false;
    _set(_layout.copyWith(perspective: () => parsed.value));
    return true;
  }

  /// 宽高对调(横竖切换)。
  void swap() => setSize(_layout.height, _layout.width);

  /// 参考图和画布一横一竖时,对调后的画布尺寸;图是方的、画布是方的、
  /// 本来就对得上或者图读不了时为 null。
  Future<LayoutSize?> swapFor(Uint8List image) async {
    final size = await _imageSize(image);
    final l = _layout;
    if (size == null || size.width == size.height || l.width == l.height) {
      return null;
    }
    if ((size.width > size.height) == (l.width > l.height)) return null;
    return (width: l.height, height: l.width);
  }

  void saveSize() {
    final size = (width: _layout.width, height: _layout.height);
    if (_sizes.contains(size)) return;
    _sizes = List.unmodifiable([..._sizes, size]);
    notifyListeners();
    _scheduleSave();
  }

  void removeSize(LayoutSize size) {
    _sizes = List.unmodifiable(_sizes.where((s) => s != size));
    notifyListeners();
    _scheduleSave();
  }

  void setSummary({String? caption, String? meta, String? canvas}) =>
      _set(_layout.copyWith(caption: caption, meta: meta, canvas: canvas));

  /// 加一个框并选中它:放在它那一层的最前面(像 PS 新建的图层在最上面)。
  void addBox(LayoutBox box) {
    final at = _layout.boxes.indexWhere(
      (b) => _rank(b.layer) <= _rank(box.layer),
    );
    final boxes = [..._layout.boxes]
      ..insert(at < 0 ? _layout.boxes.length : at, box);
    _set(_layout.copyWith(boxes: boxes), follow: box);
  }

  void updateBox(int i, LayoutBox box) {
    if (i < 0 || i >= _layout.boxes.length) return;
    _set(
      _layout.copyWith(
        boxes: [for (final (j, b) in _layout.boxes.indexed) j == i ? box : b],
      ),
      // 改了前中后景时它会挪到别处,选中的跟着它走。
      follow: _selected == i ? box : null,
    );
  }

  /// 拖着换前后:把第 [from] 块挪到第 [to] 个位置(按挪走之后的列表数)。
  /// 前、中、后景跟着落点变:夹在两个前景之间的就成了前景,拖到前景和中景之间的
  /// 尽量保持原来那一层。
  void move(int from, int to) {
    final boxes = [..._layout.boxes];
    if (from < 0 || from >= boxes.length) return;
    final b = boxes.removeAt(from);
    final at = to.clamp(0, boxes.length);
    final above = at > 0 ? _rank(boxes[at - 1].layer) : layoutLayers.length - 1;
    final below = at < boxes.length ? _rank(boxes[at].layer) : 0;
    final moved = b.copyWith(
      layer: layoutLayers[_rank(b.layer).clamp(below, above)],
    );
    boxes.insert(at, moved);
    _set(_layout.copyWith(boxes: boxes), rebuild: true, follow: moved);
  }

  void removeBox(int i) {
    if (i < 0 || i >= _layout.boxes.length) return;
    _selected = null;
    _set(
      _layout.copyWith(
        boxes: [
          for (final (j, b) in _layout.boxes.indexed)
            if (j != i) b,
        ],
      ),
      rebuild: true,
    );
  }

  /// 清掉描述和所有的框,画布尺寸留着。
  void clear() {
    _selected = null;
    _set(Layout(width: _layout.width, height: _layout.height), rebuild: true);
  }

  /// 整个换成 [layout](从档案库放回来的),画布尺寸也跟着换。
  void replace(Layout layout) {
    _selected = null;
    _set(layout, rebuild: true);
  }

  /// 换成一份布局 JSON(Agent 写的),用当前的画布尺寸。读不了返回 false。
  bool apply(String json) {
    final parsed = parseMossLayout(
      json,
      width: _layout.width,
      height: _layout.height,
    );
    if (parsed == null) return false;
    // Agent 常把 name、layer 漏掉:块数没变时按先后把原来的接上。
    final old = _layout.boxes;
    final same = old.length == parsed.boxes.length;
    final layers = json.contains('"layer"');
    final boxes = [
      for (final (i, b) in parsed.boxes.indexed)
        same
            ? b.copyWith(
                name: b.name.isEmpty ? old[i].name : null,
                layer: layers ? null : old[i].layer,
              )
            : b,
    ];
    _selected = null;
    // 透视线是用户拉的,JSON 里没有它:留着。
    _set(
      parsed.copyWith(boxes: boxes, perspective: () => _layout.perspective),
      rebuild: true,
    );
    return true;
  }

  File? get _file => dir == null
      ? null
      : File('${dir!.path}${Platform.pathSeparator}layout.json');

  void _scheduleSave() {
    if (_file == null) return;
    // 拖框时每一帧都在变:停下来一会儿再存。
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 500), _save);
  }

  void _save() {
    final file = _file;
    if (file == null) return;
    try {
      file.parent.createSync(recursive: true);
      File('${file.path}.tmp')
        ..writeAsStringSync(
          jsonEncode({
            'layout': _layout.toJson(),
            'sizes': [
              for (final s in _sizes) [s.width, s.height],
            ],
          }),
          flush: true,
        )
        ..renameSync(file.path);
    } on FileSystemException catch (e) {
      debugPrint(tr('布局没存上:{0}', [e.message]));
    }
  }

  Future<void> load() async {
    final file = _file;
    if (file == null || !file.existsSync()) return;
    try {
      final j = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      final loaded = Layout.fromJson(j['layout'] as Map<String, dynamic>);
      _layout = loaded.copyWith(boxes: stacked(loaded.boxes));
      _sizes = List.unmodifiable([
        for (final s in j['sizes'] as List? ?? const [])
          if (s is List &&
              s.length == 2 &&
              _validSide(s[0]) &&
              _validSide(s[1]))
            (width: s[0] as int, height: s[1] as int),
      ]);
      _revision++;
      notifyListeners();
    } on Object {
      // 读不了就从默认的空画板开始,不拦着程序启动。
    }
  }

  @override
  void dispose() {
    if (_saveTimer?.isActive ?? false) {
      _saveTimer!.cancel();
      _save();
    }
    super.dispose();
  }
}

/// 只读图片的宽高,不解出整张图。读不了返回 null。
Future<({int width, int height})?> _imageSize(Uint8List bytes) async {
  try {
    final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
    final d = await ui.ImageDescriptor.encoded(buffer);
    final size = (width: d.width, height: d.height);
    d.dispose();
    buffer.dispose();
    return size;
  } on Object {
    return null;
  }
}

int _rank(String layer) => layoutLayers.indexOf(layer);

/// 按前后排好:第 0 个在最前面,前景、中景、后景依次往后,同一层里保持原来的先后
/// (`mergeSort` 是稳定排序)。画布倒着画,后画的盖住先画的。
List<LayoutBox> stacked(List<LayoutBox> boxes) {
  final out = [...boxes];
  mergeSort(out, compare: (a, b) => _rank(b.layer) - _rank(a.layer));
  return out;
}

/// 说给模型听的图层名。
const _layerNames = {'back': '后景', 'middle': '中景', 'front': '前景'};

bool _validSide(Object? v) =>
    v is int && v >= minLayoutSide && v <= maxLayoutSide;
