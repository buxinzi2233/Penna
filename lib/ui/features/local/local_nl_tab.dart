part of 'local_page.dart';

// 「自然语言」:下载 llama.cpp 运行时和一个看图模型,在本机起服务,看图写描述。

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

  Future<void> _pickExe() async {
    final picked = await openFile(
      acceptedTypeGroups: [
        const XTypeGroup(label: 'llama-server', extensions: ['exe']),
      ],
    );
    if (picked != null) model.update(() => model.exePath = picked.path);
  }

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
        _FoldersBlock(model: model),
        _runtime(context),
        _models(context),
        _params(),
        _service(context),
        _caption(context),
      ],
    );
  }

  Widget _runtime(BuildContext context) {
    final exe = model.serverExe;
    return _Block(
      title: '运行时',
      trailing: PennaButton(
        label: '选择 llama-server.exe',
        icon: Icons.folder_open,
        borderColor: PennaColors.border,
        onPressed: _pickExe,
      ),
      child: exe != null
          ? Row(
              children: [
                const Icon(
                  Icons.check_circle,
                  size: 15,
                  color: PennaColors.accent,
                ),
                const SizedBox(width: 6),
                Expanded(child: _PathText(exe)),
                if (model.exePath.isNotEmpty)
                  PennaButton(
                    label: '不用这个',
                    icon: Icons.close,
                    background: PennaColors.slate100,
                    onPressed: () => model.update(() => model.exePath = ''),
                  ),
              ],
            )
          : _DownloadRow(
              model: model,
              keyName: 'runtime',
              name: 'llama.cpp $llamaCppTag',
              note: 'Vulkan 版,N 卡 / A 卡 / 核显通用 · ${_size(llamaRuntimeSize)}',
              files: const [],
              done: false,
              onDownload: model.downloadRuntime,
            ),
    );
  }

  Widget _models(BuildContext context) {
    return _Block(
      title: '模型',
      trailing: _SourcePicker(model: model),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final m in captionModels)
            _DownloadRow(
              model: model,
              keyName: m.id,
              name: m.name,
              note: m.note,
              files: model.captionFiles(m),
              onDownload: () => model.downloadCaption(m),
              foundAt: model.ready(model.captionFiles(m))
                  ? null
                  : model.captionPaths(m)?.model,
              selected: model.modelPath == model.captionPaths(m)?.model,
              onSelect: () => model.useCaption(m)
                  ? null
                  : showToast(context, '先下载这个模型', warn: true),
            ),
          // 文件夹里找到的别的 GGUF:点一下就用它(同文件夹里的视觉组件一起配上)。
          for (final g in model.foundGgufs)
            _DownloadRow(
              model: model,
              keyName: g.model,
              name: fileName(g.model),
              note: g.mmproj.isEmpty
                  ? '本机 · 仅文本'
                  : '本机 · 视觉组件 ${fileName(g.mmproj)}',
              files: const [],
              done: true,
              onDownload: () async => null,
              foundAt: g.model,
              selected: model.modelPath == g.model,
              onSelect: () => model.update(() {
                model.modelPath = g.model;
                model.mmprojPath = g.mmproj;
              }),
            ),
          const SizedBox(height: 6),
          _PathPicker(
            label: '模型',
            path: model.modelPath,
            onPick: () async {
              final path = await _pickGguf();
              if (path != null) model.update(() => model.modelPath = path);
            },
          ),
          _PathPicker(
            label: '视觉组件',
            path: model.mmprojPath,
            onPick: () async {
              final path = await _pickGguf();
              if (path != null) model.update(() => model.mmprojPath = path);
            },
            onClear: () => model.update(() => model.mmprojPath = ''),
          ),
        ],
      ),
    );
  }

  Widget _params() {
    // 不在范围里的数不收,框里改回合法的数才生效。
    Widget field(
      String label,
      int value,
      ({int min, int max}) range,
      ValueChanged<int> set,
    ) => Expanded(
      child: PennaField(
        label: label,
        value: '$value',
        onChanged: (v) {
          final n = int.tryParse(v.trim());
          if (n != null && n >= range.min && n <= range.max) {
            model.update(() => set(n));
          }
        },
      ),
    );
    return _Block(
      title: '参数',
      child: Row(
        children: [
          field('端口', model.port, (
            min: 1024,
            max: 65535,
          ), (n) => model.port = n),
          const SizedBox(width: 10),
          field('上下文长度', model.context, (
            min: 512,
            max: 262144,
          ), (n) => model.context = n),
          const SizedBox(width: 10),
          field('GPU 层数(-1 全部)', model.gpuLayers, (
            min: -1,
            max: 999,
          ), (n) => model.gpuLayers = n),
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
    final running = model.serverRunning && !model.starting;
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
          PennaField(
            label: '要求',
            value: model.captionPrompt,
            maxLines: 3,
            onChanged: (v) => model.update(() => model.captionPrompt = v),
          ),
          const SizedBox(height: 10),
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
