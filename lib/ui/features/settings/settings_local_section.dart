import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../../../core/harness/local/llama_server.dart';
import '../../../data/models/app_config.dart';
import '../../../data/services/config_service.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../local/local_model.dart';
import 'settings_sections.dart';

/// 本地反推的设置:模型文件夹、下载来源、HuggingFace Token、llama.cpp 运行时与参数、看图要求。
class LocalSection extends StatelessWidget {
  const LocalSection({super.key, required this.service, required this.local});

  final ConfigService service;
  final LocalModel local;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: local,
      builder: (context, _) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SectionHeading('本地反推', '模型存放、下载与本地运行'),
          _Folders(local: local),
          gap,
          _card(
            '下载',
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Wrap(
                  spacing: 6,
                  children: [
                    for (final (id, label) in const [
                      ('mirror', '国内镜像'),
                      ('huggingface', 'HuggingFace'),
                    ])
                      PennaChip(
                        label: label,
                        selected: local.source == id,
                        onTap: () => local.update(() => local.source = id),
                      ),
                  ],
                ),
                gap,
                PennaField(
                  label: 'HuggingFace Token',
                  hint: '下载要申请访问的模型时用',
                  obscure: true,
                  value: service.config.secrets[hfTokenSecret] ?? '',
                  onChanged: (v) => service.update(
                    service.config.setSecret(hfTokenSecret, v.trim()),
                  ),
                ),
              ],
            ),
          ),
          gap,
          _Runtime(local: local),
          gap,
          _card('llama-server 参数', _Params(local: local)),
          gap,
          _card(
            '看图描述的要求',
            PennaField(
              label: 'GGUF 模型',
              value: local.captionPrompt,
              maxLines: 4,
              onChanged: (v) => local.update(() => local.captionPrompt = v),
            ),
          ),
        ],
      ),
    );
  }
}

Widget _card(String title, Widget child, {Widget? trailing}) => PennaCard(
  padding: const EdgeInsets.all(14),
  child: Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Row(
        children: [
          Expanded(child: Text(title, style: titleStyle)),
          ?trailing,
        ],
      ),
      const SizedBox(height: 10),
      child,
    ],
  ),
);

Widget _path(String text) => Tooltip(
  message: text,
  child: Text(
    text,
    maxLines: 1,
    overflow: TextOverflow.ellipsis,
    style: monoStyle.copyWith(fontSize: 11.5, color: PennaColors.slate700),
  ),
);

/// 模型文件夹:电脑上已有模型的文件夹,连同子文件夹一起找,找到的直接用。
class _Folders extends StatelessWidget {
  const _Folders({required this.local});

  final LocalModel local;

  Future<void> _add() async {
    final path = await getDirectoryPath();
    if (path != null) local.addFolder(path);
  }

  @override
  Widget build(BuildContext context) {
    final f = local.found;
    final counts = [
      if (f.taggers.isNotEmpty) '${f.taggers.length} 个打标模型',
      if (f.ggufs.isNotEmpty) '${f.ggufs.length} 个 GGUF 模型',
      if (f.florences.isNotEmpty) '${f.florences.length} 个 Florence-2',
      if (f.servers.isNotEmpty) 'llama-server',
    ];
    return _card(
      '模型文件夹',
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (local.modelFolders.isNotEmpty)
            IconButton(
              tooltip: '重新扫描',
              iconSize: 16,
              visualDensity: VisualDensity.compact,
              color: PennaColors.slate500,
              icon: const Icon(Icons.refresh),
              onPressed: local.scanning ? null : local.rescan,
            ),
          PennaButton(
            label: '添加文件夹',
            icon: Icons.create_new_folder_outlined,
            borderColor: PennaColors.border,
            onPressed: _add,
          ),
        ],
      ),
      Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final folder in local.modelFolders)
            Row(
              children: [
                const Icon(
                  Icons.folder_outlined,
                  size: 15,
                  color: PennaColors.slate500,
                ),
                const SizedBox(width: 6),
                Expanded(child: _path(folder)),
                IconButton(
                  tooltip: '移除',
                  iconSize: 14,
                  visualDensity: VisualDensity.compact,
                  color: PennaColors.slate400,
                  icon: const Icon(Icons.close),
                  onPressed: () => local.removeFolder(folder),
                ),
              ],
            ),
          Text(
            local.scanning
                ? '扫描中…'
                : local.modelFolders.isEmpty
                ? '添加已有模型的文件夹,子文件夹一起查找'
                : counts.isEmpty
                ? '没有找到可用的模型'
                : '找到 ${counts.join('、')}'
                      '${f.truncated ? '(文件太多,只查了一部分)' : ''}',
            style: const TextStyle(fontSize: 11.5, color: PennaColors.slate500),
          ),
        ],
      ),
    );
  }
}

/// llama.cpp 运行时:下载固定版本,或用自己的 llama-server.exe。
class _Runtime extends StatelessWidget {
  const _Runtime({required this.local});

  final LocalModel local;

  Future<void> _pick() async {
    final picked = await openFile(
      acceptedTypeGroups: [
        const XTypeGroup(label: 'llama-server', extensions: ['exe']),
      ],
    );
    if (picked != null) local.update(() => local.exePath = picked.path);
  }

  Future<void> _download(BuildContext context) async {
    final problem = await local.downloadRuntime();
    if (problem != null && context.mounted) {
      showToast(context, problem, warn: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final exe = local.serverExe;
    final progress = local.progressOf('runtime');
    return _card(
      'llama.cpp 运行时',
      trailing: PennaButton(
        label: '选择 llama-server.exe',
        icon: Icons.folder_open,
        borderColor: PennaColors.border,
        onPressed: _pick,
      ),
      exe != null
          ? Row(
              children: [
                const Icon(
                  Icons.check_circle,
                  size: 15,
                  color: PennaColors.accent,
                ),
                const SizedBox(width: 6),
                Expanded(child: _path(exe)),
                if (local.exePath.isNotEmpty)
                  PennaButton(
                    label: '不用这个',
                    icon: Icons.close,
                    background: PennaColors.slate100,
                    onPressed: () => local.update(() => local.exePath = ''),
                  ),
              ],
            )
          : Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'llama.cpp $llamaCppTag · Vulkan 版 · '
                        '${(llamaRuntimeSize / (1 << 20)).toStringAsFixed(1)} MB',
                        style: const TextStyle(fontSize: 12),
                      ),
                      if (progress != null) ...[
                        const SizedBox(height: 4),
                        LinearProgressIndicator(
                          value: progress.received / llamaRuntimeSize,
                          minHeight: 3,
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                if (progress != null)
                  PennaButton(
                    label: '停止',
                    icon: Icons.stop_circle_outlined,
                    background: PennaColors.slate100,
                    onPressed: () => local.cancelDownload('runtime'),
                  )
                else
                  PennaButton(
                    label: '下载',
                    icon: Icons.download,
                    background: PennaColors.primaryBg,
                    foreground: PennaColors.primary,
                    onPressed: local.dir == null
                        ? null
                        : () => _download(context),
                  ),
              ],
            ),
    );
  }
}

/// 端口、上下文长度、GPU 层数。不在范围里的数不收,框里改回合法的数才生效。
class _Params extends StatelessWidget {
  const _Params({required this.local});

  final LocalModel local;

  Widget _field(
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
          local.update(() => set(n));
        }
      },
    ),
  );

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _field('端口', local.port, (
          min: 1024,
          max: 65535,
        ), (n) => local.port = n),
        const SizedBox(width: 10),
        _field('上下文长度', local.context, (
          min: 512,
          max: 262144,
        ), (n) => local.context = n),
        const SizedBox(width: 10),
        _field('GPU 层数(-1 全部)', local.gpuLayers, (
          min: -1,
          max: 999,
        ), (n) => local.gpuLayers = n),
      ],
    );
  }
}
