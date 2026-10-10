import 'dart:io';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../../../core/harness/mcp/mcp_client.dart';
import '../../../data/models/app_config.dart';
import '../../../data/services/config_service.dart';
import '../../../data/services/skill_store.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import 'settings_agent_sections.dart';
import 'settings_sections.dart';

/// 「添加 Skill」窗口交回来的:拖进来或选中的文件,或者手写的整篇 SKILL.md。
typedef _NewSkill = ({String? path, String? text});

/// Skills:内置的和用户加的,对所有 Preset 生效。每个都能点开看正文。
class SkillsSection extends StatelessWidget {
  const SkillsSection({super.key, required this.service, required this.skills});

  final ConfigService service;
  final SkillStore skills;

  Future<void> _add(BuildContext context) async {
    final picked = await showDialog<_NewSkill>(
      context: context,
      builder: (_) => const _AddSkillDialog(),
    );
    if (picked == null) return;
    try {
      final imported = picked.path != null
          ? await skills.import(File(picked.path!))
          : [await skills.addText(picked.text!)];
      // 以前关掉过同名的:重新加进来就是想用它,打开。
      final off = service.config.disabledSkills;
      if (imported.any((s) => off.contains(s.id))) {
        service.update(
          service.config.copyWith(
            disabledSkills: off.difference({for (final s in imported) s.id}),
          ),
        );
      }
      if (context.mounted) {
        showToast(
          context,
          imported.length == 1
              ? '已添加「${imported.single.name}」'
              : '已添加 ${imported.length} 个 Skill',
        );
      }
    } on SkillException catch (e) {
      if (context.mounted) showToast(context, e.message, warn: true);
    } on FileSystemException {
      if (context.mounted) showToast(context, '保存失败', warn: true);
    }
  }

  Future<void> _delete(BuildContext context, UserSkill skill) async {
    final ok = await confirmDelete(
      context,
      '删除 Skill「${skill.name}」?',
      '文件会从「文档\\Penna\\skills」里删除。',
    );
    if (ok) await skills.remove(skill.id);
  }

  /// 看一个 Skill 的简介和正文(给模型看的那份指令)。
  void _preview(BuildContext context, UserSkill skill) => showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(skill.name, style: const TextStyle(fontSize: 16)),
      content: SizedBox(
        width: 560,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (skill.description.isNotEmpty) ...[
                Text(skill.description, style: hintStyle),
                const SizedBox(height: 10),
              ],
              SelectableText(
                skill.body,
                contextMenuBuilder: pennaTextMenu,
                style: monoStyle,
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('关闭'),
        ),
      ],
    ),
  );

  /// 一个 Skill 占一行:点名字或眼睛看正文,右边是开关;[custom] 的还能删。
  Widget _row(BuildContext context, UserSkill skill, {bool custom = false}) {
    return Row(
      children: [
        Expanded(
          child: InkWell(
            onTap: () => _preview(context, skill),
            borderRadius: BorderRadius.circular(6),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(skill.name, style: const TextStyle(fontSize: 13)),
                  if (skill.description.isNotEmpty)
                    Text(
                      skill.description,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: hintStyle,
                    ),
                ],
              ),
            ),
          ),
        ),
        IconButton(
          tooltip: '查看',
          iconSize: 18,
          icon: const Icon(Icons.visibility_outlined),
          color: PennaColors.slate500,
          onPressed: () => _preview(context, skill),
        ),
        if (custom)
          IconButton(
            tooltip: '删除',
            iconSize: 18,
            icon: const Icon(Icons.delete_outline),
            color: PennaColors.slate500,
            onPressed: () => _delete(context, skill),
          ),
        Transform.scale(
          scale: 0.8,
          child: Switch(
            value: !service.config.disabledSkills.contains(skill.id),
            onChanged: (on) =>
                service.update(service.config.setSkill(skill.id, on: on)),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final off = service.config.disabledSkills;
    final on = builtinSkillList.where((s) => !off.contains(s.id)).length;

    return ListenableBuilder(
      listenable: skills,
      builder: (context, _) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SectionHeading('Skills', '对所有 Preset 生效'),
          PennaCard(
            padding: const EdgeInsets.fromLTRB(14, 14, 6, 6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    const Text('内置', style: titleStyle),
                    const SizedBox(width: 8),
                    Text(
                      '已开 $on / ${builtinSkillList.length}',
                      style: hintStyle,
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                for (final skill in builtinSkillList) _row(context, skill),
              ],
            ),
          ),
          gap,
          PennaCard(
            padding: const EdgeInsets.fromLTRB(14, 14, 6, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    const Text('自定义', style: titleStyle),
                    const SizedBox(width: 8),
                    Text('${skills.skills.length} 个', style: hintStyle),
                    const Spacer(),
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: PennaButton(
                        label: '添加 Skill',
                        icon: Icons.add,
                        background: PennaColors.primary,
                        foreground: Colors.white,
                        onPressed: () => _add(context),
                      ),
                    ),
                  ],
                ),
                for (final skill in skills.skills)
                  _row(context, skill, custom: true),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 添加 Skill 的窗口:把 .md / .zip 拖进来(或点一下选文件),或者自己填名称、简介、正文。
class _AddSkillDialog extends StatefulWidget {
  const _AddSkillDialog();

  @override
  State<_AddSkillDialog> createState() => _AddSkillDialogState();
}

class _AddSkillDialogState extends State<_AddSkillDialog> {
  var _name = '';
  var _description = '';
  var _body = '';

  /// 正拖着文件悬在窗口上。
  var _over = false;

  void _useFile(String path) =>
      Navigator.pop<_NewSkill>(context, (path: path, text: null));

  Future<void> _pick() async {
    final picked = await openFile(
      acceptedTypeGroups: const [
        XTypeGroup(label: 'Skill', extensions: ['md', 'zip']),
      ],
    );
    if (picked != null && mounted) _useFile(picked.path);
  }

  /// 把填的三样拼成一篇 SKILL.md;名称和简介各占文件头的一行,所以不能带换行。
  String get _text {
    String line(String s) => s.replaceAll(RegExp(r'\s*\n\s*'), ' ').trim();
    return '---\nname: ${line(_name)}\ndescription: ${line(_description)}\n'
        '---\n\n${_body.trim()}\n';
  }

  @override
  Widget build(BuildContext context) {
    final ready = _name.trim().isNotEmpty && _body.trim().isNotEmpty;
    return DropTarget(
      onDragEntered: (_) => setState(() => _over = true),
      onDragExited: (_) => setState(() => _over = false),
      onDragDone: (d) {
        if (d.files.isNotEmpty) _useFile(d.files.first.path);
      },
      child: AlertDialog(
        title: const Text('添加 Skill', style: TextStyle(fontSize: 16)),
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
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    decoration: BoxDecoration(
                      color: _over
                          ? PennaColors.primaryBg
                          : PennaColors.slate50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: _over ? PennaColors.primary : PennaColors.border,
                      ),
                    ),
                    child: Column(
                      children: [
                        Icon(
                          Icons.upload_file,
                          size: 22,
                          color: _over
                              ? PennaColors.primary
                              : PennaColors.slate400,
                        ),
                        const SizedBox(height: 6),
                        const Text('拖入 .md / .zip,或点击选择', style: hintStyle),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                const Text('或者直接写', style: hintStyle),
                const SizedBox(height: 8),
                PennaField(
                  label: '名称',
                  value: '',
                  onChanged: (v) => setState(() => _name = v),
                ),
                const SizedBox(height: 8),
                PennaField(
                  label: '简介',
                  hint: '什么时候用它',
                  value: '',
                  onChanged: (v) => _description = v,
                ),
                const SizedBox(height: 8),
                PennaField(
                  label: '正文',
                  hint: '给模型看的指令',
                  maxLines: 8,
                  value: '',
                  onChanged: (v) => setState(() => _body = v),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: ready
                ? () => Navigator.pop<_NewSkill>(context, (
                    path: null,
                    text: _text,
                  ))
                : null,
            child: const Text('添加'),
          ),
        ],
      ),
    );
  }
}

const _transportLabels = {mcpHttp: '远程地址', mcpStdio: '本机命令'};

/// MCP:添加外部工具服务,可以测试连接并看它提供哪些工具。
class McpSection extends StatelessWidget {
  const McpSection({super.key, required this.service});

  final ConfigService service;

  void _add() {
    service.update(
      service.config.putMcp(
        McpServer(id: '${DateTime.now().microsecondsSinceEpoch}', name: '新服务'),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionHeading('MCP', '接入外部工具服务'),
        // 内置接好的一个:Agent 转 Danbooru Tag 时用它按意思查标签。
        PennaCard(
          padding: const EdgeInsets.fromLTRB(14, 8, 6, 8),
          child: Row(
            children: [
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('DanbooruSearch', style: titleStyle),
                    Text('内置 · Danbooru 标签搜索,关掉后只查本机词库', style: hintStyle),
                  ],
                ),
              ),
              Transform.scale(
                scale: 0.8,
                child: Switch(
                  value: service.config.tagSearchOnline,
                  onChanged: (on) => service.update(
                    service.config.copyWith(tagSearchOnline: on),
                  ),
                ),
              ),
            ],
          ),
        ),
        gap,
        for (final server in service.config.mcpServers) ...[
          _McpCard(key: ValueKey(server.id), service: service, server: server),
          gap,
        ],
        Align(
          alignment: Alignment.centerLeft,
          child: PennaButton(
            label: '添加服务',
            icon: Icons.add,
            background: PennaColors.primary,
            foreground: Colors.white,
            onPressed: _add,
          ),
        ),
      ],
    );
  }
}

class _McpCard extends StatefulWidget {
  const _McpCard({super.key, required this.service, required this.server});

  final ConfigService service;
  final McpServer server;

  @override
  State<_McpCard> createState() => _McpCardState();
}

class _McpCardState extends State<_McpCard> {
  bool _testing = false;

  /// 最近一次测试的结果;[_failed] 决定它用什么颜色显示。
  String? _result;
  bool _failed = false;

  McpServer get _server => widget.server;
  ConfigService get _service => widget.service;

  void _put(McpServer next) => _service.update(_service.config.putMcp(next));

  void _setSecret(String key, String value) =>
      _service.update(_service.config.setSecret(key, value));

  Future<void> _test() async {
    setState(() {
      _testing = true;
      _result = null;
    });
    final secrets = _service.config.secrets;
    String? result;
    var failed = false;
    try {
      final tools = _server.transport == mcpStdio
          ? await listStdioMcpTools(
              _server.command,
              environment: parseEnv(secrets[mcpEnvKey(_server.id)] ?? ''),
            )
          : await listHttpMcpTools(
              _server.url,
              token: secrets[mcpTokenKey(_server.id)] ?? '',
            );
      result = tools.isEmpty
          ? '已连接 · 没有工具'
          : '已连接 · ${tools.length} 个工具:${tools.map((t) => t.name).join('、')}';
    } on McpException catch (e) {
      result = e.message;
      failed = true;
    } on Object catch (e) {
      // 没料到的错误也要让按钮恢复可用;只报类型,原文可能带着令牌。
      result = '连接失败(${e.runtimeType})';
      failed = true;
    }
    if (!mounted) return;
    setState(() {
      _testing = false;
      _result = result;
      _failed = failed;
    });
  }

  Future<void> _delete() async {
    final ok = await confirmDelete(context, '删除「${_server.name}」?', '此操作不可撤销。');
    if (ok) _service.update(_service.config.removeMcp(_server.id));
  }

  @override
  Widget build(BuildContext context) {
    final secrets = _service.config.secrets;
    final stdio = _server.transport == mcpStdio;
    return PennaCard(
      borderColor: _server.enabled
          ? PennaColors.primaryBorder
          : PennaColors.border,
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              for (final transport in _transportLabels.keys) ...[
                PennaChip(
                  label: _transportLabels[transport]!,
                  selected: _server.transport == transport,
                  onTap: () => _put(_server.copyWith(transport: transport)),
                ),
                const SizedBox(width: 6),
              ],
              const Spacer(),
              IconButton(
                tooltip: '删除',
                iconSize: 18,
                icon: const Icon(Icons.delete_outline),
                color: PennaColors.slate500,
                onPressed: _delete,
              ),
              Transform.scale(
                scale: 0.8,
                child: Switch(
                  value: _server.enabled,
                  onChanged: (on) => _put(_server.copyWith(enabled: on)),
                ),
              ),
            ],
          ),
          gap,
          PennaField(
            label: '名称',
            value: _server.name,
            onChanged: (v) => _put(_server.copyWith(name: v)),
          ),
          gap,
          if (stdio) ...[
            PennaField(
              key: const ValueKey('command'),
              label: '启动命令',
              hint: 'npx -y @scope/server',
              value: _server.command,
              onChanged: (v) => _put(_server.copyWith(command: v)),
            ),
            gap,
            PennaField(
              key: const ValueKey('env'),
              // 打码的输入框只能单行,会把多行压成一行,所以这里不打码。
              label: '环境变量(每行 KEY=VALUE)',
              hint: '可留空',
              maxLines: 4,
              value: secrets[mcpEnvKey(_server.id)] ?? '',
              onChanged: (v) => _setSecret(mcpEnvKey(_server.id), v),
            ),
          ] else ...[
            PennaField(
              key: const ValueKey('url'),
              label: '地址',
              hint: 'https://example.com/mcp',
              value: _server.url,
              onChanged: (v) => _put(_server.copyWith(url: v)),
            ),
            gap,
            PennaField(
              key: const ValueKey('token'),
              label: '令牌',
              hint: '可留空',
              obscure: true,
              value: secrets[mcpTokenKey(_server.id)] ?? '',
              onChanged: (v) => _setSecret(mcpTokenKey(_server.id), v),
            ),
          ],
          gap,
          Row(
            children: [
              PennaButton(
                label: '测试连接',
                icon: Icons.sync_alt,
                background: PennaColors.slate100,
                onPressed: _testing ? null : _test,
              ),
              const SizedBox(width: 10),
              if (_result != null)
                Expanded(
                  child: Text(
                    _result!,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      color: _failed
                          ? PennaColors.diffDelText
                          : PennaColors.accent,
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
