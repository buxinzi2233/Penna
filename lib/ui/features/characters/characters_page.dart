import 'dart:io';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../../../core/harness/attachment.dart';
import '../../../core/harness/characters/character_dict.dart';
import '../../../data/services/character_store.dart';
import '../../core/smooth_scroll.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../settings/settings_sections.dart';
import '../../../l10n/l10n.dart';

/// 添加或修改角色的窗口交回来的内容;[image] 为 null 表示图没动。
typedef _Draft = ({String name, String prompt, CharacterImage? image});

/// 内置角色一次最多列出几个。
const _maxBuiltin = 30;

/// 先摆出来的系列有几个(角色最多的那些)。
const _maxSeries = 80;

/// 系列的格子至少这么宽,窗口窄了就少排几列;格子之间隔这么远。
const _seriesTileWidth = 220.0;
const _seriesGap = 10.0;

/// 角色库:上面是用户自己存的角色(名字、图、提示词),下面按名字查内置的 Danbooru 角色。
class CharactersPage extends StatefulWidget {
  const CharactersPage({super.key, required this.store, required this.dict});

  final CharacterStore store;

  /// 内置的角色;没有就只有用户自己的那部分(测试用)。
  final CharacterDict? dict;

  @override
  State<CharactersPage> createState() => _CharactersPageState();
}

class _CharactersPageState extends State<CharactersPage> {
  var _query = '';

  /// 正在看哪个系列里的内置角色;null 是在看各个系列。
  String? _series;

  Future<void> _edit([CharacterCard? card, CharacterHit? from]) async {
    final draft = await showDialog<_Draft>(
      context: context,
      builder: (_) => _CharacterDialog(
        name: card?.name ?? from?.name ?? '',
        prompt: card?.prompt ?? (from == null ? '' : _fullPrompt(from)),
        image: card?.image ?? '',
        editing: card != null,
      ),
    );
    if (draft == null || !mounted) return;
    final saved = widget.store.put(
      id: card?.id,
      name: draft.name,
      prompt: draft.prompt,
      image: draft.image,
    );
    if (saved != null) showToast(context, tr('已存进角色库'));
  }

  Future<void> _delete(CharacterCard card) async {
    if (await confirmDelete(
      context,
      tr('删除角色「{0}」?', [card.name]),
      tr('删掉后找不回来。'),
    )) {
      widget.store.remove(card.id);
    }
  }

  /// 「内置」那一块:在查名字就是结果;没在查时先列各个系列(角色多的在前),
  /// 点一个系列看它名下的角色(图多的在前)。
  Widget _builtin(CharacterDict dict, String q, List<CharacterHit> found) {
    final series = _series;
    final hits = q.isNotEmpty
        ? found
        : series == null
        ? const <CharacterHit>[]
        : dict.inSeries(series);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (q.isNotEmpty)
          _Heading(tr('内置'), tr('{0} 个', [found.length]))
        else if (series == null) ...[
          _Heading(tr('内置'), tr('{0} 个系列', [dict.series.length])),
          const SizedBox(height: 8),
          // 一格一个系列,格子一样大,排成整齐的几列(宽的时候 5 列)。
          LayoutBuilder(
            builder: (context, box) {
              final columns = (box.maxWidth / _seriesTileWidth).floor().clamp(
                2,
                5,
              );
              final width =
                  (box.maxWidth - _seriesGap * (columns - 1)) / columns;
              return Wrap(
                spacing: _seriesGap,
                runSpacing: _seriesGap,
                children: [
                  for (final s in dict.series.take(_maxSeries))
                    SizedBox(
                      // 留一点余量:算出来的小数宽度加起来不能超过一行。
                      width: width.floorToDouble(),
                      child: _SeriesTile(
                        name: s.name,
                        count: s.count,
                        onTap: () => setState(() => _series = s.name),
                      ),
                    ),
                ],
              );
            },
          ),
        ] else
          Row(
            children: [
              PennaButton(
                label: tr('全部系列'),
                icon: Icons.arrow_back,
                borderColor: PennaColors.border,
                onPressed: () => setState(() => _series = null),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _Heading(series, tr('前 {0} 个 · 图多的在前', [hits.length])),
              ),
            ],
          ),
        if (q.isNotEmpty && hits.isEmpty) _Empty(tr('没有找到')),
        for (final hit in hits) ...[
          const SizedBox(height: 8),
          _BuiltinCard(hit: hit, onSave: () => _edit(null, hit)),
        ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.store,
      builder: (context, _) {
        final dict = widget.dict;
        final q = _query.trim();
        final mine = q.isEmpty ? widget.store.cards : widget.store.find(q);
        final builtin = q.isEmpty || dict == null
            ? const <CharacterHit>[]
            : dict.search(q, limit: _maxBuiltin);
        return ColoredBox(
          color: PennaColors.editorBg,
          child: Column(
            children: [
              PennaBar(
                color: PennaColors.card,
                children: [
                  Icon(
                    Icons.face_retouching_natural_outlined,
                    size: 15,
                    color: PennaColors.primary,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    tr('角色库'),
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      tr(
                        '我的 {0} 个'
                        '{1}',
                        [
                          widget.store.cards.length,
                          dict == null ? '' : tr(' · 内置 {0} 个', [dict.length]),
                        ],
                      ),
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11,
                        color: PennaColors.slate500,
                      ),
                    ),
                  ),
                  PennaButton(
                    label: tr('添加角色'),
                    icon: Icons.add,
                    background: PennaColors.primary,
                    foreground: Colors.white,
                    onPressed: _edit,
                  ),
                ],
              ),
              Expanded(
                child: SmoothScroller(
                  builder: (controller) => ListView(
                    controller: controller,
                    padding: const EdgeInsets.all(16),
                    children: [
                      PennaCard(
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        child: TextField(
                          contextMenuBuilder: pennaTextMenu,
                          onChanged: (v) => setState(() => _query = v),
                          style: const TextStyle(fontSize: 13),
                          decoration: InputDecoration(
                            icon: Icon(
                              Icons.search,
                              size: 17,
                              color: PennaColors.slate400,
                            ),
                            hintText: tr('按名字找:初音未来、甘雨、hatsune miku'),
                            hintStyle: TextStyle(
                              fontSize: 12.5,
                              color: PennaColors.slate400,
                            ),
                            border: InputBorder.none,
                            isDense: true,
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),
                      _Heading(tr('我的'), tr('{0} 个', [mine.length])),
                      if (mine.isEmpty)
                        _Empty(
                          q.isEmpty
                              ? tr('还没有角色 · 点「添加角色」,或让 Agent 存')
                              : tr('没有找到'),
                        ),
                      for (final card in mine) ...[
                        const SizedBox(height: 8),
                        _MineCard(
                          key: ValueKey(card.id),
                          card: card,
                          onEdit: () => _edit(card),
                          onDelete: () => _delete(card),
                        ),
                      ],
                      if (dict != null) ...[
                        const SizedBox(height: 18),
                        // 三种样子:查名字的结果、各个系列、某个系列里的角色。
                        // 换的时候旧的淡出、新的滑进来,高度跟着顺过去。
                        AnimatedSize(
                          duration: const Duration(milliseconds: 280),
                          curve: Curves.easeOutCubic,
                          alignment: Alignment.topCenter,
                          child: AnimatedSwitcher(
                            duration: const Duration(milliseconds: 280),
                            switchInCurve: Curves.easeOutCubic,
                            switchOutCurve: Curves.easeInCubic,
                            layoutBuilder: (current, previous) => Stack(
                              alignment: Alignment.topCenter,
                              children: [...previous, ?current],
                            ),
                            transitionBuilder: (child, animation) =>
                                FadeTransition(
                                  opacity: animation,
                                  child: SlideTransition(
                                    position: Tween(
                                      begin: const Offset(0.03, 0),
                                      end: Offset.zero,
                                    ).animate(animation),
                                    child: child,
                                  ),
                                ),
                            child: KeyedSubtree(
                              key: ValueKey(
                                q.isNotEmpty ? tr('查') : _series ?? tr('系列'),
                              ),
                              child: _builtin(dict, q, builtin),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// 内置角色的整条提示词:触发词、外貌、服装。
String _fullPrompt(CharacterHit c) => [
  characterTrigger(c),
  c.looks,
  c.outfit,
].where((s) => s.isNotEmpty).join(', ');

/// 一个系列占的那一格:名字,和它名下有几个角色。
class _SeriesTile extends StatelessWidget {
  const _SeriesTile({
    required this.name,
    required this.count,
    required this.onTap,
  });

  final String name;
  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Bouncy(
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: onTap,
          child: PennaCard(
            padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
            child: SizedBox(
              height: 62,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 13.5,
                        height: 1.3,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  Text(
                    tr('{0} 个角色', [count]),
                    style: TextStyle(
                      fontSize: 11.5,
                      color: PennaColors.slate500,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Heading extends StatelessWidget {
  const _Heading(this.title, this.note);

  final String title;
  final String note;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Flexible(
        child: Text(
          title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
        ),
      ),
      const SizedBox(width: 8),
      Text(note, style: TextStyle(fontSize: 11, color: PennaColors.slate500)),
    ],
  );
}

class _Empty extends StatelessWidget {
  const _Empty(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 18),
    child: Center(
      child: Text(
        text,
        style: TextStyle(fontSize: 12, color: PennaColors.slate400),
      ),
    ),
  );
}

/// 角色的图;没有、或读不了时是一个占位的小人。
class _Portrait extends StatelessWidget {
  const _Portrait({required this.path, this.size = 76});

  final String path;
  final double size;

  @override
  Widget build(BuildContext context) {
    final blank = ColoredBox(
      color: PennaColors.slate100,
      child: Icon(Icons.person_outline, color: PennaColors.slate400),
    );
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: SizedBox(
        width: size,
        height: size,
        child: path.isEmpty
            ? blank
            : Image.file(
                File(path),
                fit: BoxFit.cover,
                // 只按缩略图的大小解码,大图不占内存。
                cacheWidth: (size * 2).round(),
                errorBuilder: (_, _, _) => blank,
              ),
      ),
    );
  }
}

class _MineCard extends StatelessWidget {
  const _MineCard({
    super.key,
    required this.card,
    required this.onEdit,
    required this.onDelete,
  });

  final CharacterCard card;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return PennaCard(
      padding: const EdgeInsets.fromLTRB(10, 10, 8, 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Portrait(path: card.image),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        card.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    PennaButton(
                      label: tr('复制'),
                      icon: Icons.content_copy,
                      onPressed: () =>
                          copyWithToast(context, card.prompt, tr('已复制')),
                    ),
                    PennaButton(
                      label: tr('修改'),
                      icon: Icons.edit_outlined,
                      onPressed: onEdit,
                    ),
                    IconButton(
                      tooltip: tr('删除'),
                      iconSize: 15,
                      visualDensity: VisualDensity.compact,
                      color: PennaColors.slate400,
                      icon: const Icon(Icons.delete_outline),
                      onPressed: onDelete,
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  card.prompt,
                  maxLines: 4,
                  overflow: TextOverflow.ellipsis,
                  style: monoStyle.copyWith(fontSize: 11.5),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _BuiltinCard extends StatelessWidget {
  const _BuiltinCard({required this.hit, required this.onSave});

  final CharacterHit hit;

  /// 存一份到「我的」,之后可以自己改。
  final VoidCallback onSave;

  Widget _line(String label, String text) => Padding(
    padding: const EdgeInsets.only(top: 3),
    child: Text.rich(
      TextSpan(
        children: [
          TextSpan(
            text: '$label ',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: PennaColors.slate500,
            ),
          ),
          TextSpan(text: text, style: monoStyle.copyWith(fontSize: 11.5)),
        ],
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final trigger = characterTrigger(hit);
    return PennaCard(
      padding: const EdgeInsets.fromLTRB(12, 8, 8, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  trigger,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              PennaButton(
                label: tr('复制'),
                icon: Icons.content_copy,
                tooltip: tr('触发词、外貌和服装'),
                onPressed: () =>
                    copyWithToast(context, _fullPrompt(hit), tr('已复制')),
              ),
              if (hit.looks.isNotEmpty && hit.outfit.isNotEmpty)
                PennaButton(
                  label: tr('只要外貌'),
                  icon: Icons.face_outlined,
                  tooltip: tr('不带服装的词'),
                  onPressed: () => copyWithToast(
                    context,
                    '$trigger, ${hit.looks}',
                    tr('已复制(不带服装)'),
                  ),
                ),
              PennaButton(
                label: tr('存到我的'),
                icon: Icons.bookmark_add_outlined,
                onPressed: onSave,
              ),
            ],
          ),
          if (hit.alias.isNotEmpty)
            Text(
              hit.alias,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 11, color: PennaColors.slate500),
            ),
          if (hit.looks.isNotEmpty) _line(tr('外貌'), hit.looks),
          if (hit.outfit.isNotEmpty) _line(tr('服装'), hit.outfit),
        ],
      ),
    );
  }
}

/// 添加或修改一个角色:名字、提示词,图可以拖进来或点一下选。
class _CharacterDialog extends StatefulWidget {
  const _CharacterDialog({
    required this.name,
    required this.prompt,
    required this.image,
    required this.editing,
  });

  final String name;
  final String prompt;

  /// 现在的图(文件路径),没有就是空串。
  final String image;
  final bool editing;

  @override
  State<_CharacterDialog> createState() => _CharacterDialogState();
}

class _CharacterDialogState extends State<_CharacterDialog> {
  late var _name = widget.name;
  late var _prompt = widget.prompt;

  /// 新选的图;没选就是 null,保存时留着原来的。
  CharacterImage? _image;
  late var _preview = widget.image;

  /// 正拖着文件悬在窗口上。
  var _over = false;

  void _useImage(String path) {
    final dot = path.lastIndexOf('.');
    final ext = dot < 0 ? '' : path.substring(dot + 1).toLowerCase();
    if (!imageMimes.containsKey(ext)) {
      return showToast(context, tr('只能放图片(png、jpg、webp、gif)'), warn: true);
    }
    try {
      final file = File(path);
      if (file.lengthSync() > maxCharacterImageBytes) {
        return showToast(context, tr('图片太大(上限 20 MB)'), warn: true);
      }
      final bytes = file.readAsBytesSync();
      setState(() {
        _image = (bytes: bytes, ext: ext);
        _preview = path;
      });
    } on FileSystemException {
      showToast(context, tr('读不了这张图'), warn: true);
    }
  }

  Future<void> _pick() async {
    final picked = await openFile(
      acceptedTypeGroups: [
        XTypeGroup(label: tr('图片'), extensions: imageMimes.keys.toList()),
      ],
    );
    if (picked != null && mounted) _useImage(picked.path);
  }

  @override
  Widget build(BuildContext context) {
    final ready = _name.trim().isNotEmpty && _prompt.trim().isNotEmpty;
    return DropTarget(
      onDragEntered: (_) => setState(() => _over = true),
      onDragExited: (_) => setState(() => _over = false),
      onDragDone: (d) {
        setState(() => _over = false);
        if (d.files.isNotEmpty) _useImage(d.files.first.path);
      },
      child: AlertDialog(
        title: Text(
          widget.editing ? tr('修改角色') : tr('添加角色'),
          style: const TextStyle(fontSize: 16),
        ),
        content: SizedBox(
          width: 480,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                InkWell(
                  onTap: _pick,
                  borderRadius: BorderRadius.circular(8),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 140),
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: _over
                          ? PennaColors.primaryBg
                          : PennaColors.slate50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: _over ? PennaColors.primary : PennaColors.border,
                      ),
                    ),
                    child: Row(
                      children: [
                        _Portrait(path: _preview, size: 64),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            tr('拖入图片,或点击选择'),
                            style: TextStyle(
                              fontSize: 12,
                              color: PennaColors.slate500,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                PennaField(
                  label: tr('名字'),
                  value: _name,
                  onChanged: (v) => setState(() => _name = v),
                ),
                const SizedBox(height: 8),
                PennaField(
                  label: tr('提示词'),
                  hint: tr('这个角色的长相和标志性的穿着'),
                  maxLines: 7,
                  value: _prompt,
                  onChanged: (v) => setState(() => _prompt = v),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(tr('取消')),
          ),
          TextButton(
            onPressed: ready
                ? () => Navigator.pop<_Draft>(context, (
                    name: _name,
                    prompt: _prompt,
                    image: _image,
                  ))
                : null,
            child: Text(tr('保存')),
          ),
        ],
      ),
    );
  }
}
