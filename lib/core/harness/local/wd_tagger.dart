import 'dart:math' as math;
import 'dart:typed_data';

// WD14 类的 ONNX 打标模型(SmilingWolf 系列):看图给出 Danbooru 标签和各自的把握。
// 读图、跑模型在别处,这里只管模型清单、标签表、喂给模型的像素和把结果变成标签。
// 做法照 BooruDatasetTagManagerPlus 的 Wd14OnnxTaggerService。

/// 一个打标模型:[general]、[character] 是通用标签和角色标签的默认阈值。
typedef TaggerModel = ({
  String repo,
  String name,
  String note,
  double general,
  double character,
});

/// 内置的模型清单,第一个是默认。阈值取各模型公布的推荐值。
const taggerModels = <TaggerModel>[
  (
    repo: 'SmilingWolf/wd-eva02-large-tagger-v3',
    name: 'EVA02 Large v3',
    note: '最准 · 约 1.2 GB',
    general: 0.52,
    character: 0.85,
  ),
  (
    repo: 'SmilingWolf/wd-vit-large-tagger-v3',
    name: 'ViT Large v3',
    note: '约 1.2 GB',
    general: 0.26,
    character: 0.85,
  ),
  (
    repo: 'SmilingWolf/wd-swinv2-tagger-v3',
    name: 'SwinV2 v3',
    note: '约 470 MB',
    general: 0.25,
    character: 0.85,
  ),
  (
    repo: 'SmilingWolf/wd-convnext-tagger-v3',
    name: 'ConvNeXt v3',
    note: '约 400 MB',
    general: 0.25,
    character: 0.85,
  ),
  (
    repo: 'SmilingWolf/wd-vit-tagger-v3',
    name: 'ViT v3',
    note: '最快 · 约 380 MB',
    general: 0.25,
    character: 0.85,
  ),
];

/// 每个模型要下的两个文件。
const taggerModelFile = 'model.onnx';
const taggerLabelsFile = 'selected_tags.csv';

/// 下载来源:官方和国内镜像,地址写法一样。
const hfSources = {
  'huggingface': 'https://huggingface.co',
  'mirror': 'https://hf-mirror.com',
};

String hfFileUrl(String source, String repo, String file) =>
    '${hfSources[source] ?? hfSources['huggingface']}/$repo/resolve/main/$file';

/// 标签表里的分类:0 通用,4 角色,9 分级(general、sensitive 这类)。
const tagGeneral = 0, tagCharacter = 4, tagRating = 9;

typedef TagLabel = ({String name, int category});

/// 读 selected_tags.csv。v3 的表头是 tag_id,name,category,count;老版本是 name,category。
List<TagLabel> parseSelectedTags(String csv) => List.unmodifiable([
  for (final line in csv.split(RegExp(r'\r?\n'))) ?_parseRow(line.split(',')),
]);

TagLabel? _parseRow(List<String> parts) {
  if (parts.length < 2 || parts.first == 'tag_id' || parts.first == 'name') {
    return null;
  }
  if (parts.length >= 4 && int.tryParse(parts[0]) != null) {
    final category = int.tryParse(parts[2]);
    final name = parts[1].trim();
    if (category != null && name.isNotEmpty) {
      return (name: name, category: category);
    }
  }
  final category = int.tryParse(parts[1]);
  final name = parts[0].trim();
  return category == null || name.isEmpty
      ? null
      : (name: name, category: category);
}

/// 模型要的输入:边长多少,通道在前(NCHW)还是在后(NHWC)。
/// SmilingWolf 的模型是 [1, 448, 448, 3];同结构从 PyTorch 转出来的可能是 [1, 3, 448, 448]。
({int size, bool nchw}) inputLayout(List<int> shape) {
  if (shape.length >= 4) {
    if (shape[3] == 3 && shape[1] > 0) return (size: shape[1], nchw: false);
    if (shape[1] == 3 && shape[2] > 0) return (size: shape[2], nchw: true);
    if (shape[1] > 0 && shape[1] == shape[2]) {
      return (size: shape[1], nchw: false);
    }
  }
  return (size: 448, nchw: false);
}

/// 缩图后的长宽:长边不超过 [size],不放大。
({int width, int height}) fitInside(int width, int height, int size) {
  final scale = math.min(1.0, size / math.max(width, height));
  return (
    width: math.max(1, (width * scale).round()),
    height: math.max(1, (height * scale).round()),
  );
}

/// 把已经缩到长边不超过 [size] 的图([rgba],宽 [width] 高 [height])
/// 贴到 [size]×[size] 的白底正中,透明的地方算白色,
/// 输出模型要的 BGR、0~255 的浮点数,按 [nchw] 排通道。
Float32List letterboxBgr(
  Uint8List rgba,
  int width,
  int height, {
  required int size,
  bool nchw = false,
}) {
  final out = Float32List(size * size * 3)..fillRange(0, size * size * 3, 255);
  final left = (size - width) ~/ 2, top = (size - height) ~/ 2;
  final plane = size * size;
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      final i = (y * width + x) * 4;
      final a = rgba[i + 3] / 255;
      final white = 255 * (1 - a);
      final b = rgba[i + 2] * a + white;
      final g = rgba[i + 1] * a + white;
      final r = rgba[i] * a + white;
      final at = (y + top) * size + x + left;
      if (nchw) {
        out[at] = b;
        out[plane + at] = g;
        out[2 * plane + at] = r;
      } else {
        out[at * 3] = b;
        out[at * 3 + 1] = g;
        out[at * 3 + 2] = r;
      }
    }
  }
  return out;
}

typedef TagScore = ({String tag, int category, double prob});

/// 推出来的标签:角色、通用标签各自按把握从高到低;[rating] 是把握最大的分级。
typedef TagResult = ({
  List<TagScore> characters,
  List<TagScore> general,
  String? rating,
});

/// 把模型输出的每个标签的把握按阈值筛出来。输出还没过 sigmoid(有不在 0~1 的值)时先补上。
TagResult decodeTags(
  List<double> scores,
  List<TagLabel> labels, {
  required double general,
  required double character,
}) {
  final raw = scores.any((v) => v < 0 || v > 1);
  final characters = <TagScore>[], kept = <TagScore>[];
  TagScore? rating;
  for (var i = 0; i < math.min(scores.length, labels.length); i++) {
    final prob = raw ? 1 / (1 + math.exp(-scores[i])) : scores[i];
    final label = labels[i];
    final score = (tag: label.name, category: label.category, prob: prob);
    switch (label.category) {
      case tagRating:
        if (rating == null || prob > rating.prob) rating = score;
      case tagCharacter:
        if (prob >= character) characters.add(score);
      default:
        if (prob >= general) kept.add(score);
    }
  }
  int byProb(TagScore a, TagScore b) => b.prob.compareTo(a.prob);
  return (
    characters: List.unmodifiable(characters..sort(byProb)),
    general: List.unmodifiable(kept..sort(byProb)),
    rating: rating?.tag,
  );
}

/// 这些颜文字标签的下划线是字的一部分,不能换成空格。
const _kaomoji = {
  '0_0', '(o)_(o)', '+_+', '+_-', '._.', '<o>_<o>', '<|>_<|>', '=_=', //
  '>_<', '3_3', '6_9', '>_o', '@_@', '^_^', 'o_o', 'u_u', 'x_x', '|_|',
  '||_||',
};

/// 标签的写法:小写,下划线换成空格(颜文字除外)。
String tagText(String tag) =>
    _kaomoji.contains(tag) ? tag : tag.replaceAll('_', ' ');

/// 推出来的标签连成一条提示词:角色在前,通用标签在后,用英文逗号隔开。
String tagPrompt(TagResult r) =>
    [...r.characters, ...r.general].map((t) => tagText(t.tag)).join(', ');
