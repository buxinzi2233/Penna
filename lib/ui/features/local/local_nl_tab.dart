part of 'local_page.dart';

// 「NL 反推」:按系列挑一个看图模型写描述。GGUF 要在本机起 llama-server
// (运行时和参数在「设置 → 本地反推」);Florence-2 在程序里直接跑,只要选指令。

/// 加进「API 管理」的那个本地模型用这个 id,再点一次是更新它的地址。
const _localLlmId = 'local-llama';

class _NlTab extends StatelessWidget {
  const _NlTab({
    required this.model,
    required this.config,
    required this.onToDraft,
  });

  final LocalModel model;
  final ConfigService config;
  final ValueChanged<String> onToDraft;

  Future<String?> _pickGguf() async => (await openFile(
    acceptedTypeGroups: [
      const XTypeGroup(label: 'GGUF', extensions: ['gguf']),
    ],
  ))?.path;

  /// 把跑着的本地服务加进「API 管理」,Agent 和润色也能用它。
  void _addApi(BuildContext context, String url) {
    final cfg = config.config;
    final old = cfg.llms.where((l) => l.id == _localLlmId).firstOrNull;
    config.update(
      cfg.putLlm(
        LlmProfile(
          id: _localLlmId,
          name: old?.name ?? '本地模型',
          baseUrl: url,
          model: 'local',
          protocol: protocolOpenAi,
          enabled: old?.enabled ?? true,
        ),
      ),
    );
    showToast(context, old == null ? '已加入 API 管理' : '已更新 API 管理里的地址');
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _models(context),
        // Florence-2 在程序里直接跑,不用起 llama-server。
        if (!model.florenceMode) _service(context),
        _caption(context),
      ],
    );
  }

  /// 清单里的一个模型:名字、系列和大小,下面是量化档;文件夹里找到的标「本机」。
  Widget _catalogRow(BuildContext context, CaptionModel m) {
    final quant = model.quantOf(m);
    final total = [
      quant.file.size,
      ?m.mmproj?.size,
      for (final e in m.extra) e.size,
    ].fold<int>(0, (a, b) => a + b);
    final paths = model.captionPaths(m);
    return _DownloadRow(
      model: model,
      keyName: m.id,
      name: m.name,
      note: '${m.params} · ${_size(total)} · ${m.note}',
      files: model.captionFiles(m),
      onDownload: () => model.downloadCaption(m),
      onRemove: () => model.removeCaption(m),
      // 选中的那档没下、但别的档或文件夹里有:标「本机」直接用。
      foundAt: model.ready(model.captionFiles(m)) ? null : paths?.model,
      selected: model.captionPick == m.id,
      onSelect: () => model.useCaption(m)
          ? null
          : showToast(context, '先下载这个模型', warn: true),
      below: m.quants.length < 2
          ? null
          : Wrap(
              spacing: 4,
              runSpacing: 4,
              children: [
                for (final q in m.quants)
                  _QuantChip(
                    label:
                        '${q.recommended ? '★ ' : ''}${q.label} '
                        '${_size(q.file.size)}',
                    selected: q.label == quant.label,
                    onTap: () => model.pickQuant(m, q.label),
                  ),
              ],
            ),
    );
  }

  /// 模型文件夹里找到的 GGUF:点一下就用它(同文件夹里的视觉组件一起配上)。
  Widget _ggufRow(({String model, String mmproj}) g) => _DownloadRow(
    model: model,
    keyName: g.model,
    name: fileName(g.model),
    note: g.mmproj.isEmpty ? '本机 · 仅文本' : '本机 · 视觉组件 ${fileName(g.mmproj)}',
    files: const [],
    done: true,
    onDownload: () async => null,
    foundAt: g.model,
    selected: model.captionPick.isEmpty && model.modelPath == g.model,
    onSelect: () => model.useGguf(g.model, g.mmproj),
  );

  Widget _models(BuildContext context) {
    final picked = model.pickedCaption;
    return _Block(
      title: '模型',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _GroupedModelList(
            current: picked?.series ?? '本机',
            groups: [
              for (final g in model.captionGroups)
                (
                  series: g.series,
                  ids: [for (final r in g.items) r.id],
                  rows: [
                    for (final r in g.items)
                      if (r.model case final m?)
                        _catalogRow(context, m)
                      else
                        _ggufRow(r.gguf!),
                  ],
                ),
            ],
            onMove: model.moveCaption,
          ),
          if (!model.florenceMode) ...[
            const SizedBox(height: 6),
            _PathPicker(
              label: '模型',
              path: model.modelPath,
              onPick: () async {
                final path = await _pickGguf();
                if (path != null) model.useGguf(path, model.mmprojPath);
              },
            ),
            _PathPicker(
              label: '视觉组件',
              path: model.mmprojPath,
              onPick: () async {
                final path = await _pickGguf();
                if (path != null) model.useGguf(model.modelPath, path);
              },
              onClear: () => model.useGguf(model.modelPath, ''),
            ),
          ],
        ],
      ),
    );
  }

  Widget _service(BuildContext context) {
    final url = model.server.baseUrl;
    final running = model.serverRunning && !model.starting;
    return _Block(
      title: '服务',
      trailing: model.serverRunning || model.starting
          ? PennaButton(
              label: '停止',
              icon: Icons.stop_circle_outlined,
              background: PennaColors.diffDel,
              foreground: PennaColors.diffDelText,
              onPressed: model.stopServer,
            )
          : PennaButton(
              label: '启动',
              icon: Icons.play_arrow,
              background: PennaColors.primary,
              foreground: Colors.white,
              onPressed: () => _run(context, model.startServer),
            ),
      child: Row(
        children: [
          Expanded(
            child: running
                ? _PathText('运行中 · $url')
                : Text(
                    model.starting ? '启动中…' : '未启动',
                    style: const TextStyle(
                      fontSize: 12,
                      color: PennaColors.slate500,
                    ),
                  ),
          ),
          if (running && url != null)
            PennaButton(
              label: '加入 API 管理',
              icon: Icons.hub_outlined,
              borderColor: PennaColors.border,
              onPressed: () => _addApi(context, url),
            ),
        ],
      ),
    );
  }

  Widget _caption(BuildContext context) {
    final florence = model.florenceMode ? model.pickedCaption : null;
    final running = florence != null || model.serverRunning && !model.starting;
    return _Block(
      title: '看图描述',
      trailing: PennaButton(
        label: model.captioning ? '生成中…' : '生成',
        icon: Icons.notes,
        background: PennaColors.primary,
        foreground: Colors.white,
        onPressed: !running || model.image == null || model.captioning
            ? null
            : () => _run(context, model.runCaption),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Florence-2 只认几个固定的指令;GGUF 模型照「设置 → 本地反推」里写的要求来。
          if (florence != null) ...[
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final task in florence.tasks)
                  PennaChip(
                    label: florenceTaskLabels[task] ?? task,
                    selected: model.florenceTaskOf(florence) == task,
                    onTap: () => model.update(() => model.florenceTask = task),
                  ),
              ],
            ),
            const SizedBox(height: 10),
          ],
          if (model.caption.isNotEmpty) ...[
            PennaCard(
              color: PennaColors.slate50,
              radius: 4,
              child: SelectableText(
                contextMenuBuilder: pennaTextMenu,
                model.caption,
                style: monoStyle.copyWith(fontSize: 11.5),
              ),
            ),
            if (!model.captioning) ...[
              const SizedBox(height: 8),
              _ResultActions(text: model.caption, onToDraft: onToDraft),
            ],
          ],
        ],
      ),
    );
  }
}

/// 一个文件:标题、路径(没选时是「未选择」),右边是选择和清掉。
class _PathPicker extends StatelessWidget {
  const _PathPicker({
    required this.label,
    required this.path,
    required this.onPick,
    this.onClear,
  });

  final String label;
  final String path;
  final VoidCallback onPick;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        children: [
          SizedBox(
            width: 64,
            child: Text(label, style: const TextStyle(fontSize: 12)),
          ),
          Expanded(
            child: path.isEmpty
                ? const Text(
                    '未选择',
                    style: TextStyle(fontSize: 12, color: PennaColors.slate400),
                  )
                : _PathText(path),
          ),
          if (path.isNotEmpty && onClear != null)
            IconButton(
              tooltip: '清掉',
              iconSize: 14,
              visualDensity: VisualDensity.compact,
              color: PennaColors.slate400,
              icon: const Icon(Icons.close),
              onPressed: onClear,
            ),
          PennaButton(
            label: '选择',
            icon: Icons.folder_open,
            borderColor: PennaColors.border,
            onPressed: onPick,
          ),
        ],
      ),
    );
  }
}

/// 一行路径或地址:太长时省略中间,鼠标停上去看全。
class _PathText extends StatelessWidget {
  const _PathText(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: text,
      child: Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: monoStyle.copyWith(fontSize: 11.5, color: PennaColors.slate700),
      ),
    );
  }
}

/// 量化档的小标签:选中的描边加深。
class _QuantChip extends StatelessWidget {
  const _QuantChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: selected ? PennaColors.primaryBg : PennaColors.slate50,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
            color: selected ? PennaColors.primary : PennaColors.border,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 10.5,
            color: selected ? PennaColors.primary : PennaColors.slate500,
          ),
        ),
      ),
    );
  }
}
