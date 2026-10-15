part of 'local_page.dart';

// 「Tag 反推」:按系列挑一个打标模型(WD14、PixAI、CL、OppaiOracle),下载后给左边的图打标。

class _TagTab extends StatelessWidget {
  const _TagTab({required this.model, required this.onToDraft});

  final LocalModel model;
  final ValueChanged<String> onToDraft;

  /// 一个打标模型:自己下载过的可以删;文件夹里找到的标「本机」,直接用。
  Widget _taggerRow(TaggerModel m, {required bool selected}) {
    final files = model.taggerFiles(m);
    final own = files.isNotEmpty && model.ready(files);
    return _DownloadRow(
      model: model,
      keyName: m.id,
      name: m.name,
      note: [
        if (m.size > 0) '约 ${_size(m.size)}',
        if (m.note.isNotEmpty) m.note,
      ].join(' · '),
      files: files,
      onDownload: () => model.downloadTagger(m),
      foundAt: own ? null : model.foundTagger(m),
      selected: selected,
      onSelect: () => model.pickTagger(m.id),
    );
  }

  @override
  Widget build(BuildContext context) {
    final current = model.tagger;
    final ready = model.taggerPaths(current) != null;
    final tags = model.tags;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Block(
          title: '模型',
          child: _GroupedModelList(
            current: current.series,
            groups: [
              for (final g in model.taggerGroups)
                (
                  series: g.series,
                  ids: [for (final m in g.items) m.id],
                  rows: [
                    for (final m in g.items)
                      _taggerRow(m, selected: m.id == current.id),
                  ],
                ),
            ],
            onMove: model.moveTagger,
          ),
        ),
        _Block(
          title: '阈值',
          child: Column(
            children: [
              _Threshold(
                label: '通用',
                value: model.general,
                onChanged: (v) => model.setThresholds(general: v),
              ),
              // OppaiOracle 只有一个阈值。
              if (current.kind != TaggerKind.oppai)
                _Threshold(
                  label: '角色',
                  value: model.character,
                  onChanged: (v) => model.setThresholds(character: v),
                ),
            ],
          ),
        ),
        _Block(
          title: '结果',
          trailing: PennaButton(
            label: model.tagging ? '推理中…' : '推理',
            icon: Icons.sell_outlined,
            background: PennaColors.primary,
            foreground: Colors.white,
            onPressed: model.image == null || !ready || model.tagging
                ? null
                : () => _run(context, model.runTagger),
          ),
          child: tags == null
              ? Text(
                  model.tagging
                      ? '推理中…'
                      : !ready
                      ? '先下载选中的模型'
                      : model.image == null
                      ? '先在左边放一张图'
                      : '暂无结果',
                  style: const TextStyle(
                    fontSize: 12,
                    color: PennaColors.slate400,
                  ),
                )
              : _TagResultView(result: tags, onToDraft: onToDraft),
        ),
      ],
    );
  }
}

/// 一个阈值滑条:低于它的标签不要。
class _Threshold extends StatelessWidget {
  const _Threshold({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final double value;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 36,
          child: Text(label, style: const TextStyle(fontSize: 12)),
        ),
        Expanded(
          child: Slider(
            value: value.clamp(0.05, 1),
            min: 0.05,
            max: 1,
            divisions: 95,
            onChanged: onChanged,
          ),
        ),
        SizedBox(
          width: 36,
          child: Text(
            value.toStringAsFixed(2),
            textAlign: TextAlign.end,
            style: monoStyle.copyWith(fontSize: 12),
          ),
        ),
      ],
    );
  }
}

/// 打出来的标签:分级、角色(琥珀色)、通用标签,鼠标停上去看把握。
class _TagResultView extends StatelessWidget {
  const _TagResultView({required this.result, required this.onToDraft});

  final TagResult result;
  final ValueChanged<String> onToDraft;

  Widget _chip(TagScore t, {bool character = false}) => Tooltip(
    message: '${(t.prob * 100).toStringAsFixed(1)}%',
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: character ? PennaColors.lock : PennaColors.slate50,
        borderRadius: BorderRadius.circular(5),
        border: Border.all(
          color: character ? PennaColors.lockBorder : PennaColors.border,
        ),
      ),
      child: Text(
        tagText(t.tag),
        style: monoStyle.copyWith(
          fontSize: 11.5,
          color: character ? PennaColors.lockText : PennaColors.text,
        ),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final prompt = tagPrompt(result);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (result.rating case final rating?)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              '分级:$rating',
              style: const TextStyle(fontSize: 11, color: PennaColors.slate500),
            ),
          ),
        Wrap(
          spacing: 5,
          runSpacing: 5,
          children: [
            for (final t in result.characters) _chip(t, character: true),
            for (final t in result.general) _chip(t),
          ],
        ),
        if (prompt.isEmpty)
          const Text(
            '没有超过阈值的标签',
            style: TextStyle(fontSize: 12, color: PennaColors.slate400),
          )
        else ...[
          const SizedBox(height: 10),
          _ResultActions(text: prompt, onToDraft: onToDraft),
        ],
      ],
    );
  }
}
