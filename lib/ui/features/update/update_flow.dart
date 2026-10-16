import 'dart:io';

import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import '../../../core/harness/local/download.dart';
import '../../../core/harness/update/updater.dart';
import '../../core/theme.dart';
import '../../core/version.dart';
import '../../core/widgets.dart';
import '../settings/settings_sections.dart';
import '../studio/markdown_text.dart';

typedef FetchRelease = Future<Release?> Function();

/// 检查更新。有新版本就弹窗介绍并可一键更新。
/// [quiet] 为真时(启动时自动检查)已是最新、出错都不打扰用户。
Future<void> checkForUpdate(
  BuildContext context, {
  bool quiet = false,
  FetchRelease fetch = fetchLatestRelease,
  String current = appVersion,
}) async {
  Release? release;
  try {
    release = await fetch();
  } on UpdateException catch (e) {
    if (!quiet && context.mounted) showToast(context, e.message, warn: true);
    return;
  }
  if (!context.mounted) return;
  if (release == null || compareVersions(release.version, current) <= 0) {
    if (!quiet) showToast(context, '已是最新版本');
    return;
  }
  final found = release;
  await showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => UpdateDialog(release: found, current: current),
  );
}

/// 新版本弹窗:更新说明,点「更新」后下载、解开,退出 Penna 换上新文件再重新打开。
class UpdateDialog extends StatefulWidget {
  const UpdateDialog({super.key, required this.release, required this.current});

  final Release release;
  final String current;

  @override
  State<UpdateDialog> createState() => _UpdateDialogState();
}

class _UpdateDialogState extends State<UpdateDialog> {
  final _cancel = DownloadCancel();

  /// 下载进度(0~1);null 表示还没开始下载。
  double? _progress;
  String? _status;
  bool _busy = false;

  Future<void> _update() async {
    final release = widget.release;
    setState(() {
      _busy = true;
      _progress = 0;
      _status = '下载中…';
    });
    try {
      final temp = await Directory.systemTemp.createTemp('penna-update-');
      final zip = '${temp.path}${Platform.pathSeparator}update.zip';
      await downloadFile(
        (
          url: release.url,
          path: zip,
          size: release.size,
          sha256: release.sha256,
        ),
        cancel: _cancel,
        onProgress: (got, total) {
          if (mounted && total != null && total > 0) {
            setState(() => _progress = got / total);
          }
        },
      );
      if (!mounted) return;
      setState(() => _status = '正在解压…');
      final from = await unpackUpdate(
        zip,
        '${temp.path}${Platform.pathSeparator}new',
      );
      setState(() => _status = '即将重启…');
      await launchUpdater(
        updateScript(
          pid: pid,
          from: from,
          to: File(Platform.resolvedExecutable).parent.path,
          cleanup: temp.path,
        ),
        temp.path,
      );
      // 走正常的关窗流程:先停掉本地反推的服务,再退出;脚本等 Penna 退出后换文件、重新打开。
      await windowManager.close();
    } on DownloadException catch (e) {
      _fail(e.message);
    } on UpdateException catch (e) {
      _fail(e.message);
    } on Object catch (e) {
      _fail('更新失败(${e.runtimeType})');
    }
  }

  void _fail(String message) {
    if (!mounted) return;
    setState(() {
      _busy = false;
      _progress = null;
      _status = message;
    });
  }

  @override
  void dispose() {
    _cancel.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final release = widget.release;
    const body = TextStyle(fontSize: 13, height: 1.6, color: PennaColors.text);
    return AlertDialog(
      title: Text(
        '发现新版本 v${release.version}',
        style: const TextStyle(fontSize: 16),
      ),
      content: SizedBox(
        width: 520,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '当前版本 v${widget.current}',
              style: const TextStyle(fontSize: 12, color: PennaColors.slate500),
            ),
            const SizedBox(height: 10),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 340),
              child: PennaCard(
                color: PennaColors.slate50,
                radius: 6,
                child: SingleChildScrollView(
                  child: release.notes.isEmpty
                      ? const Text('暂无更新说明', style: body)
                      : SelectableText.rich(
                          markdownSpan(release.notes, body),
                          contextMenuBuilder: pennaTextMenu,
                        ),
                ),
              ),
            ),
            if (_progress != null || _status != null) ...[
              const SizedBox(height: 12),
              if (_progress != null)
                LinearProgressIndicator(value: _progress, minHeight: 4),
              if (_status != null) ...[
                const SizedBox(height: 6),
                Text(
                  _status!,
                  style: TextStyle(
                    fontSize: 12,
                    color: _busy
                        ? PennaColors.slate500
                        : PennaColors.diffDelText,
                  ),
                ),
              ],
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () {
            _cancel.cancel();
            Navigator.pop(context);
          },
          child: Text(_busy ? '取消' : '稍后'),
        ),
        TextButton(
          onPressed: _busy ? null : _update,
          child: const Text('更新并重启'),
        ),
      ],
    );
  }
}

/// 设置里的「版本与更新」:当前版本和「检查更新」按钮。
class UpdateCard extends StatefulWidget {
  const UpdateCard({super.key, this.fetch = fetchLatestRelease});

  final FetchRelease fetch;

  @override
  State<UpdateCard> createState() => _UpdateCardState();
}

class _UpdateCardState extends State<UpdateCard> {
  bool _checking = false;

  Future<void> _check() async {
    setState(() => _checking = true);
    await checkForUpdate(context, fetch: widget.fetch);
    if (mounted) setState(() => _checking = false);
  }

  @override
  Widget build(BuildContext context) {
    return PennaCard(
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('版本与更新', style: titleStyle),
                SizedBox(height: 2),
                Text(
                  '当前版本 v$appVersion · 每次启动自动检查',
                  style: TextStyle(fontSize: 12, color: PennaColors.slate500),
                ),
              ],
            ),
          ),
          PennaButton(
            label: _checking ? '检查中…' : '检查更新',
            icon: Icons.system_update_alt,
            borderColor: PennaColors.border,
            onPressed: _checking ? null : _check,
          ),
        ],
      ),
    );
  }
}
