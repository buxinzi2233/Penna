import 'package:flutter/material.dart';

import '../data/services/archive_store.dart';
import '../data/services/character_store.dart';
import '../data/services/config_service.dart';
import '../data/services/skill_store.dart';
import 'core/theme.dart';
import 'core/widgets.dart';
import 'features/archive/archive_page.dart';
import 'features/characters/characters_page.dart';
import 'features/settings/settings_page.dart';
import 'features/studio/reverse_model.dart';
import 'features/studio/studio_page.dart';
import 'features/studio/studio_view_model.dart';

/// 显示在右下角的版本号;要和 pubspec.yaml 的 version 一致(version_test.dart 会查)。
const appVersion = '0.1.0';

const _studio = 0, _archivePage = 1, _settings = 2, _charactersPage = 3;

/// 应用外壳:最左图标栏,右边在「工作台」「档案库」「设置」之间切换。
class AppShell extends StatefulWidget {
  const AppShell({
    super.key,
    required this.vm,
    required this.config,
    required this.skills,
    this.archive,
    this.reverse,
  });

  final StudioViewModel vm;
  final ConfigService config;
  final SkillStore skills;

  /// 档案库和图像反推;不给就各用一个只在内存里的(测试用)。
  final ArchiveStore? archive;
  final ReverseModel? reverse;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _page = _studio;
  late final _archive = widget.archive ?? ArchiveStore();
  late final _reverse = widget.reverse ?? ReverseModel(widget.vm);
  // 角色库跟着工作台走:Agent 存进去的和这一页上看到的是同一份。
  late final _characters = widget.vm.characters ?? CharacterStore();

  void _go(int page) => setState(() => _page = page);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: ListenableBuilder(
        listenable: widget.config,
        builder: (context, _) => Column(
          children: [
            if (widget.config.lastError != null)
              _ErrorBanner(message: widget.config.lastError!),
            Expanded(
              child: Row(
                children: [
                  _NavRail(page: _page, onSelect: _go),
                  Expanded(
                    // 几页都一直留着,切去设置时工作台的输入和滚动位置不丢。
                    child: Stack(
                      children: [
                        _Page(
                          active: _page == _studio,
                          child: StudioPage(
                            vm: widget.vm,
                            config: widget.config,
                            archive: _archive,
                            reverse: _reverse,
                            onOpenSettings: () => _go(_settings),
                          ),
                        ),
                        _Page(
                          active: _page == _archivePage,
                          child: ArchivePage(
                            archive: _archive,
                            vm: widget.vm,
                            onOpenStudio: () => _go(_studio),
                          ),
                        ),
                        _Page(
                          active: _page == _charactersPage,
                          child: CharactersPage(
                            store: _characters,
                            dict: widget.vm.characterDict,
                          ),
                        ),
                        _Page(
                          active: _page == _settings,
                          child: SettingsPage(
                            service: widget.config,
                            skills: widget.skills,
                          ),
                        ),
                        const Positioned(
                          right: 8,
                          bottom: 3,
                          child: IgnorePointer(
                            child: Text(
                              'v$appVersion',
                              style: TextStyle(
                                fontSize: 10,
                                color: PennaColors.slate400,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 一页内容:切入时淡入并轻轻弹上来,切出后不可见也不响应点击。
class _Page extends StatelessWidget {
  const _Page({required this.active, required this.child});

  final bool active;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: IgnorePointer(
        ignoring: !active,
        child: ExcludeFocus(
          excluding: !active,
          child: AnimatedOpacity(
            opacity: active ? 1 : 0,
            duration: const Duration(milliseconds: 160),
            child: AnimatedSlide(
              offset: active ? Offset.zero : const Offset(0, 0.02),
              duration: const Duration(milliseconds: 360),
              curve: Curves.easeOutBack,
              child: child,
            ),
          ),
        ),
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: PennaColors.diffDel,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: SelectableText(
        contextMenuBuilder: pennaTextMenu,
        message,
        style: const TextStyle(fontSize: 12, color: PennaColors.diffDelText),
      ),
    );
  }
}

class _NavRail extends StatelessWidget {
  const _NavRail({required this.page, required this.onSelect});

  final int page;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 48,
      // 顶部留白让第一个按钮和右边 PennaBar 那一行垂直居中对齐。
      padding: const EdgeInsets.only(top: 1, bottom: 12),
      decoration: const BoxDecoration(
        color: PennaColors.sidebar,
        border: Border(right: BorderSide(color: PennaColors.border)),
      ),
      child: Column(
        children: [
          _RailButton(
            icon: Icons.space_dashboard_outlined,
            tooltip: '工作台',
            selected: page == _studio,
            onTap: () => onSelect(_studio),
          ),
          const SizedBox(height: 6),
          _RailButton(
            icon: Icons.inventory_2_outlined,
            tooltip: '档案库',
            selected: page == _archivePage,
            onTap: () => onSelect(_archivePage),
          ),
          const SizedBox(height: 6),
          _RailButton(
            icon: Icons.face_retouching_natural_outlined,
            tooltip: '角色库',
            selected: page == _charactersPage,
            onTap: () => onSelect(_charactersPage),
          ),
          const Spacer(),
          _RailButton(
            icon: Icons.settings_outlined,
            tooltip: '设置',
            selected: page == _settings,
            onTap: () => onSelect(_settings),
          ),
        ],
      ),
    );
  }
}

class _RailButton extends StatelessWidget {
  const _RailButton({
    required this.icon,
    required this.tooltip,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Bouncy(
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: GestureDetector(
            onTap: onTap,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: selected ? PennaColors.card : PennaColors.sidebar,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: selected ? PennaColors.border : PennaColors.sidebar,
                ),
              ),
              child: Icon(
                icon,
                size: 19,
                color: selected ? PennaColors.primary : PennaColors.slate500,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
