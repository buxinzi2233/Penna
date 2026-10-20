import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import 'perspective.dart';

export 'perspective.dart';

/// MOSS-Image 布局提示词(Layout Prompt):画面整体描述 + 一组带位置框的元素,
/// 写成官方的 JSON。框在这里按常规的左上角原点、整数像素存,出 JSON 时才换成
/// `abs_centralized`(画布中心为原点)和 `yxyx`([y_min, x_min, y_max, x_max])。

const layoutLabels = ['object', 'character', 'text'];
const layoutCanvases = ['single', 'multi_panel', 'collage'];

/// 图层:后景、中景、前景。画布上前面的盖住后面的;同一层里后加的在上面。
const layoutLayers = ['back', 'middle', 'front'];
const defaultLayer = 'middle';

const defaultLayoutWidth = 832, defaultLayoutHeight = 1216;

/// 画布边长的范围(像素)。
const minLayoutSide = 64, maxLayoutSide = 4096;

/// 画面里的一个元素:[label] 是类别,[caption] 是这块的描述,
/// [text] 是要画出来的文字(只有 text 类用)。坐标是左上角原点的像素。
/// [name] 是给这一块起的名字,[layer] 是它在哪一层(见 [layoutLayers]),
/// 两样都只在 Penna 里用(用户和 Agent 靠它们说"哪一块"、谁挡着谁),
/// 官方格式不认,交出去的 JSON 里没有。
@immutable
class LayoutBox {
  const LayoutBox({
    required this.left,
    required this.top,
    required this.right,
    required this.bottom,
    this.label = 'object',
    this.caption = '',
    this.text = '',
    this.name = '',
    this.layer = defaultLayer,
  });

  final int left, top, right, bottom;
  final String label, caption, text, name, layer;

  int get width => right - left;
  int get height => bottom - top;

  LayoutBox copyWith({
    int? left,
    int? top,
    int? right,
    int? bottom,
    String? label,
    String? caption,
    String? text,
    String? name,
    String? layer,
  }) => LayoutBox(
    left: left ?? this.left,
    top: top ?? this.top,
    right: right ?? this.right,
    bottom: bottom ?? this.bottom,
    label: label ?? this.label,
    caption: caption ?? this.caption,
    text: text ?? this.text,
    name: name ?? this.name,
    layer: layer ?? this.layer,
  );

  /// 按比例缩到另一块画布上(换画布尺寸时用)。
  LayoutBox scaled(double sx, double sy) => copyWith(
    left: (left * sx).round(),
    top: (top * sy).round(),
    right: (right * sx).round(),
    bottom: (bottom * sy).round(),
  );

  Map<String, Object> toJson() => {
    'box': [left, top, right, bottom],
    'label': label,
    'caption': caption,
    'text': text,
    'name': name,
    'layer': layer,
  };

  static LayoutBox? fromJson(Object? j) {
    if (j is! Map || j['box'] is! List) return null;
    final b = [for (final v in j['box'] as List) (v as num).round()];
    if (b.length != 4) return null;
    return LayoutBox(
      left: b[0],
      top: b[1],
      right: b[2],
      bottom: b[3],
      label: _pick(j['label'], layoutLabels),
      caption: j['caption'] as String? ?? '',
      text: j['text'] as String? ?? '',
      name: j['name'] as String? ?? '',
      layer: _layer(j['layer']),
    );
  }
}

/// 一张布局:画布尺寸、整体描述([meta] 是逗号隔开的几个类型词)和各个元素。
@immutable
class Layout {
  const Layout({
    this.width = defaultLayoutWidth,
    this.height = defaultLayoutHeight,
    this.caption = '',
    this.meta = '',
    this.canvas = 'single',
    this.boxes = const [],
    this.perspective,
  });

  final int width, height;
  final String caption, meta, canvas;
  final List<LayoutBox> boxes;

  /// 透视辅助线;null 是没开。
  final Perspective? perspective;

  bool get isEmpty => boxes.isEmpty && caption.trim().isEmpty;

  Layout copyWith({
    int? width,
    int? height,
    String? caption,
    String? meta,
    String? canvas,
    List<LayoutBox>? boxes,
    Perspective? Function()? perspective,
  }) => Layout(
    width: width ?? this.width,
    height: height ?? this.height,
    caption: caption ?? this.caption,
    meta: meta ?? this.meta,
    canvas: canvas ?? this.canvas,
    boxes: boxes == null ? this.boxes : List.unmodifiable(boxes),
    perspective: perspective == null ? this.perspective : perspective(),
  );

  Map<String, Object> toJson() => {
    'width': width,
    'height': height,
    'caption': caption,
    'meta': meta,
    'canvas': canvas,
    'boxes': [for (final b in boxes) b.toJson()],
    'perspective': ?perspective?.toJson(),
  };

  static Layout fromJson(Map<String, dynamic> j) => Layout(
    width: _side(j['width'], defaultLayoutWidth),
    height: _side(j['height'], defaultLayoutHeight),
    caption: j['caption'] as String? ?? '',
    meta: j['meta'] as String? ?? '',
    canvas: _pick(j['canvas'], layoutCanvases),
    boxes: List.unmodifiable([
      for (final b in j['boxes'] as List? ?? const []) ?LayoutBox.fromJson(b),
    ]),
    perspective: Perspective.fromJson(j['perspective']),
  );
}

String _pick(Object? v, List<String> allowed) =>
    v is String && allowed.contains(v.trim()) ? v.trim() : allowed.first;

String _layer(Object? v) =>
    v is String && layoutLayers.contains(v.trim()) ? v.trim() : defaultLayer;

int _side(Object? v, int fallback) =>
    v is num ? v.round().clamp(minLayoutSide, maxLayoutSide) : fallback;

/// 写成 MOSS-Image 的布局 JSON。换算照官方 compile_prompt.py:减去宽高的一半(整除);
/// 画布尺寸不写进去(生成时另设)。[names] 为真时每一块带上 `name` 和 `layer`:
/// 那是给 Agent 看的,官方格式不认,交出去的不带。
String mossLayoutJson(Layout l, {bool names = false}) {
  final w2 = l.width ~/ 2, h2 = l.height ~/ 2;
  final meta = [
    for (final m in l.meta.split(RegExp('[,,、]')))
      if (m.trim().isNotEmpty) m.trim(),
  ];
  return const JsonEncoder.withIndent('  ').convert({
    'summary': {
      if (meta.isNotEmpty) 'meta': meta,
      'canvas': l.canvas,
      'caption': l.caption.trim(),
    },
    'items': [
      for (final b in l.boxes)
        {
          if (names && b.name.trim().isNotEmpty) 'name': b.name.trim(),
          if (names) 'layer': b.layer,
          'label': b.label,
          'caption': b.caption.trim(),
          if (b.label == 'text' && b.text.trim().isNotEmpty)
            'text': b.text.trim(),
          'bbox': [b.top - h2, b.left - w2, b.bottom - h2, b.right - w2],
        },
    ],
    'bbox_coord_space': 'abs_centralized',
    'bbox_format': 'yxyx',
  });
}

/// 读回一份布局 JSON(Agent 写的,或用户贴的),放到 [width]×[height] 的画布上。
/// 框超出画布的截掉,上下、左右写反的摆正,截完没有面积的不要。读不了返回 null。
Layout? parseMossLayout(String raw, {required int width, required int height}) {
  // 模型常把 JSON 套进代码块。
  final text = raw
      .trim()
      .replaceFirst(RegExp(r'^```[a-zA-Z]*\s*'), '')
      .replaceFirst(RegExp(r'\s*```$'), '');
  final Object? j;
  try {
    j = jsonDecode(_repairJson(text));
  } on FormatException {
    return null;
  }
  if (j is! Map) return null;
  final root = j;
  final summary = root['summary'] is Map ? root['summary'] as Map : const {};
  // 模型漏写 summary 的右括号时,items 这几项会落进 summary 里:从那里也找。
  Object? field(String key) => root[key] ?? summary[key];
  final xyxy = field('bbox_format') == 'xyxy';
  final w2 = width ~/ 2, h2 = height ~/ 2;
  final boxes = <LayoutBox>[];
  final items = field('items');
  for (final item in items is List ? items : const []) {
    if (item is! Map || item['bbox'] is! List) continue;
    final v = [
      for (final n in item['bbox'] as List)
        if (n is num) n.toDouble(),
    ];
    if (v.length != 4) continue;
    final (y0, x0, y1, x1) = xyxy
        ? (v[1], v[0], v[3], v[2])
        : (v[0], v[1], v[2], v[3]);
    int x(double n) => (n + w2).round().clamp(0, width);
    int y(double n) => (n + h2).round().clamp(0, height);
    final box = LayoutBox(
      left: math.min(x(x0), x(x1)),
      top: math.min(y(y0), y(y1)),
      right: math.max(x(x0), x(x1)),
      bottom: math.max(y(y0), y(y1)),
      label: _pick(item['label'], layoutLabels),
      caption: item['caption'] is String ? item['caption'] as String : '',
      text: item['text'] is String ? item['text'] as String : '',
      name: item['name'] is String ? item['name'] as String : '',
      layer: _layer(item['layer']),
    );
    if (box.width > 0 && box.height > 0) boxes.add(box);
  }
  final meta = summary['meta'];
  return Layout(
    width: width,
    height: height,
    caption: summary['caption'] is String ? summary['caption'] as String : '',
    meta: meta is List
        ? meta.whereType<String>().join(', ')
        : meta is String
        ? meta
        : '',
    canvas: _pick(summary['canvas'], layoutCanvases),
    boxes: List.unmodifiable(boxes),
  );
}

/// 模型写的 JSON 常差一点:从第一个 `{` 开始取,去掉 `}`、`]` 前多余的逗号,
/// 末尾缺的右括号按顺序补上。字符串里的字一个不动。
String _repairJson(String text) {
  final start = text.indexOf('{');
  if (start < 0) return text;
  final out = StringBuffer();
  final open = <String>[];
  var inString = false, escaped = false;
  for (final ch in text.substring(start).split('')) {
    if (inString) {
      out.write(ch);
      if (escaped) {
        escaped = false;
      } else if (ch == r'\') {
        escaped = true;
      } else if (ch == '"') {
        inString = false;
      }
      continue;
    }
    switch (ch) {
      case '"':
        inString = true;
      case '{':
        open.add('}');
      case '[':
        open.add(']');
      case '}' || ']':
        if (open.isEmpty) return out.toString(); // 多出来的右括号之后不要了
        open.removeLast();
        // 去掉紧挨着的那个多余逗号。
        final kept = out.toString().trimRight();
        if (kept.endsWith(',')) {
          out
            ..clear()
            ..write(kept.substring(0, kept.length - 1));
        }
    }
    out.write(ch);
    if (open.isEmpty && ch == '}') break; // 整份读完了,后面的话不要
  }
  if (inString) out.write('"');
  out.writeAll(open.reversed);
  return out.toString();
}

final _ask = RegExp(
  r'<ask-layout(?:\s+name\s*=\s*"([^"\n]*)")?\s*>([\s\S]*?)</ask-layout>',
);
const _askOpen = '<ask-layout';

/// 主工作区把排布局的活交给区域控制工作台的 Agent:`<ask-layout name="系列名">任务</ask-layout>`。
/// [asks] 是写完的那几个(任务是空的不算),[prose] 是去掉它们之后给人看的话,
/// 还没写完的那一个先不显示。
({String prose, List<({String name, String brief})> asks}) splitAskLayout(
  String reply,
) {
  final asks = [
    for (final m in _ask.allMatches(reply))
      if (m[2]!.trim().isNotEmpty)
        (name: (m[1] ?? '').trim(), brief: m[2]!.trim()),
  ];
  var prose = reply.replaceAll(_ask, '');
  final half = prose.indexOf(_askOpen);
  if (half >= 0) {
    prose = prose.substring(0, half);
  } else {
    // 开始标签只到了一半(流式生成中)。
    for (var n = _askOpen.length - 1; n > 1; n--) {
      if (prose.endsWith(_askOpen.substring(0, n))) {
        prose = prose.substring(0, prose.length - n);
        break;
      }
    }
  }
  return (prose: prose.trim(), asks: asks);
}

final _block = RegExp(r'<layout>([\s\S]*?)</layout>');
const _open = '<layout>';

/// 发给模型的旧回复里,整个 `<layout>…</layout>` 换成一句话:用户之后可能拖过框、改过字,
/// 旧坐标留在上文里,模型会照抄回去。画板现在的样子只看系统提示里的【布局画板】。
/// 这句话不带标签:带着 `<layout>` 的话,模型会照样子把这句话当成布局写回来。
String forgetLayouts(String reply) =>
    reply.replaceAll(_block, '(这里写过一份布局 JSON,已放到画板上,内容省略;现在的样子看【布局画板】)');

final _layersTag = RegExp(r'<layers>([\s\S]*?)</layers>');
const _layersOpen = '<layers>';

/// Agent 调图层的一项:把现在第 [from] 块(从 1 数)排到这个位置,
/// [name]、[layer] 不为 null 时顺便改掉。
typedef LayerOp = ({int from, String? name, String? layer});

/// 拆回复里的 `<layers>`(有好几个时取最后一个):[spec] 是里面的内容,
/// [prose] 是去掉它之后给人看的话;还没写完的那一个先不显示,[spec] 为 null。
({String prose, String? spec}) splitLayers(String reply) {
  final done = _layersTag.allMatches(reply).lastOrNull;
  var prose = reply.replaceAll(_layersTag, '');
  var spec = done?[1]!.trim();
  final half = prose.indexOf(_layersOpen);
  if (half >= 0) {
    prose = prose.substring(0, half);
    spec = null;
  } else {
    // 开始标签只到了一半(流式生成中)。
    for (var n = _layersOpen.length - 1; n > 1; n--) {
      if (prose.endsWith(_layersOpen.substring(0, n))) {
        prose = prose.substring(0, prose.length - n);
        break;
      }
    }
  }
  return (prose: prose.trim(), spec: spec);
}

/// 读 `<layers>` 里的 JSON 数组:按从前到后的新顺序一项一块,
/// `[{"from": 2, "name": "维尔汀", "layer": "front"}, {"from": 1}]`。
/// `from` 是这一块现在的序号(从 1 数);`name`、`layer` 要改才写。
/// 读不了、layer 不认得时返回 null。
List<LayerOp>? parseLayers(String spec) {
  final Object? list;
  try {
    // 模型常把 JSON 套进代码块。
    list = jsonDecode(
      spec
          .trim()
          .replaceFirst(RegExp(r'^```[a-zA-Z]*\s*'), '')
          .replaceFirst(RegExp(r'\s*```$'), ''),
    );
  } on FormatException {
    return null;
  }
  if (list is! List || list.isEmpty) return null;
  final ops = <LayerOp>[];
  for (final item in list) {
    if (item is! Map || item['from'] is! num) return null;
    final layer = item['layer'];
    if (layer != null && !layoutLayers.contains(layer)) return null;
    final name = item['name'];
    ops.add((
      from: (item['from'] as num).round(),
      name: name is String && name.trim().isNotEmpty ? name.trim() : null,
      layer: layer as String?,
    ));
  }
  return ops;
}

/// 发给模型的旧回复里,整个 `<layers>…</layers>` 换成一句不带标签的话(同 [forgetLayouts])。
String forgetLayers(String reply) =>
    reply.replaceAll(_layersTag, '(这里调过一次图层,已放到画板上,内容省略;现在的样子看【布局画板】)');

/// 把回复里的 `<layout>` 拆出来(有好几个时取最后一个):[json] 是里面的布局,
/// [prose] 是去掉它之后给人看的话;还没写完的那一个先不显示,[complete] 为假。
({String prose, String? json, bool complete}) splitLayout(String reply) {
  final done = _block.allMatches(reply).lastOrNull;
  var prose = reply.replaceAll(_block, '');
  String? json = done?[1]!.trim();
  var complete = done != null;
  final half = prose.indexOf(_open);
  if (half >= 0) {
    json = prose.substring(half + _open.length).trim();
    complete = false;
    prose = prose.substring(0, half);
  } else {
    // 开始标签只到了一半(流式生成中)。
    for (var n = _open.length - 1; n > 1; n--) {
      if (prose.endsWith(_open.substring(0, n))) {
        prose = prose.substring(0, prose.length - n);
        break;
      }
    }
  }
  return (prose: prose.trim(), json: json, complete: complete);
}

/// 布局 JSON 里的一个功能区:`summary`(整体,[item] 为 -1)或 `items` 里的第 [item] 块。
/// [start]、[end] 是它那个 `{…}` 在原文里的位置;[label]、[name]、[text] 给标题用。
typedef LayoutRegion = ({
  int start,
  int end,
  int item,
  String label,
  String name,
  String text,
});

/// 把一份布局 JSON 按功能区切出位置,只用来分区显示,原文一个字不动。
/// 不是布局 JSON(读不了、没有 summary 和 items)返回 null。
List<LayoutRegion>? layoutJsonRegions(String source) {
  final Object? j;
  try {
    j = jsonDecode(source);
  } on FormatException {
    return null;
  }
  if (j is! Map || j['summary'] is! Map || j['items'] is! List) return null;
  final items = j['items'] as List;
  String field(int i, String key) {
    final item = i < items.length ? items[i] : null;
    final v = item is Map ? item[key] : null;
    return v is String ? v.trim() : '';
  }

  final out = <LayoutRegion>[];
  var depth = 0, keyStart = 0, next = 0;
  var inString = false, escaped = false;
  // 最外层最近读到的那个字符串(值前面的就是键),和正在里面的那个值的键。
  String? key, owner;
  int? open;
  for (var i = 0; i < source.length; i++) {
    final c = source[i];
    if (inString) {
      if (escaped) {
        escaped = false;
      } else if (c == r'\') {
        escaped = true;
      } else if (c == '"') {
        inString = false;
        if (depth == 1) key = source.substring(keyStart + 1, i);
      }
      continue;
    }
    switch (c) {
      case '"':
        inString = true;
        keyStart = i;
      case '{' || '[':
        if (depth == 1) owner = key;
        if (c == '{' &&
            (depth == 1 && owner == 'summary' ||
                depth == 2 && owner == 'items')) {
          open = i;
        }
        depth++;
      case '}' || ']':
        depth--;
        if (c == '}' && open != null && (depth == 1 || depth == 2)) {
          final n = depth == 1 ? -1 : next++;
          out.add((
            start: open,
            end: i + 1,
            item: n,
            label: n < 0 ? '' : field(n, 'label'),
            name: n < 0 ? '' : field(n, 'name'),
            text: n < 0 ? '' : field(n, 'text'),
          ));
          open = null;
        }
    }
  }
  return out;
}
