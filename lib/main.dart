import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show kReleaseMode;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:window_manager/window_manager.dart';

import 'core/harness/characters/character_dict.dart';
import 'core/harness/providers/llm_router.dart';
import 'core/harness/tags/tag_dictionary.dart';
import 'core/harness/tags/tag_search.dart';
import 'data/models/app_config.dart';
import 'data/services/archive_store.dart';
import 'data/services/character_store.dart';
import 'data/services/config_service.dart';
import 'data/services/skill_store.dart';
import 'ui/core/look_switcher.dart';
import 'ui/core/theme.dart';
import 'ui/features/local/local_model.dart';
import 'ui/features/studio/reverse_model.dart';
import 'ui/features/studio/studio_view_model.dart';
import 'ui/shell.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // 藏掉系统标题栏,换成 PennaApp 里自己画的那条(能放 logo 和字标图片)。
  await windowManager.ensureInitialized();
  await windowManager.setTitleBarStyle(TitleBarStyle.hidden);
  // 所有用户数据都放在「文档\Penna」下,方便找到和备份。
  // 设了环境变量 PENNA_HOME 就改用它指的文件夹(便携使用,或不碰真实数据地试用)。
  final sep = Platform.pathSeparator;
  final override = Platform.environment['PENNA_HOME'];
  final home = override != null && override.trim().isNotEmpty
      ? Directory(override.trim())
      : Directory(
          '${(await getApplicationDocumentsDirectory()).path}${sep}Penna',
        );
  final config = ConfigService(
    dir: home,
    legacyFile: ConfigService.defaultLegacyFile(),
  );
  final skills = SkillStore(Directory('${home.path}${sep}skills'));
  await config.load();
  applyLook(config.config);
  await skills.load();
  // 内置的 Danbooru 词库(压缩过的文本):在线搜索连不上时用它查,也用它核对标签。
  final tagDictionary = TagDictionary.parse(
    utf8.decode(
      gzip.decode(
        (await rootBundle.load('assets/danbooru_tags.tsv.gz')).buffer
            .asUint8List(),
      ),
    ),
  );
  // 角色库:用户自己存的角色,和内置的 Danbooru 角色(同样是压缩过的文本)。
  final characters = CharacterStore(home);
  await characters.load();
  final characterDict = CharacterDict.parse(
    utf8.decode(
      gzip.decode(
        (await rootBundle.load('assets/danbooru_characters.tsv.gz')).buffer
            .asUint8List(),
      ),
    ),
  );
  // 工作台(成稿、对话、历史提示词)存在 workspace.json,下次打开接着用。
  final vm = StudioViewModel(
    config: config,
    streamChat: streamChat,
    skills: skills,
    tagDictionary: tagDictionary,
    tagSearch: tagSearcher(() => config.config, tagDictionary),
    characters: characters,
    characterDict: characterDict,
    saveFile: File('${home.path}${sep}workspace.json'),
  );
  await vm.load();
  final archive = ArchiveStore(File('${home.path}${sep}archive.json'));
  await archive.load();
  final reverse = ReverseModel(vm, dir: home);
  await reverse.load();
  final local = LocalModel(
    dir: home,
    streamChat: streamChat,
    hfToken: () => config.config.secrets[hfTokenSecret] ?? '',
  );
  await local.load();
  // 关窗前先停掉本地反推起的 llama-server:Windows 不会跟着把它关掉。
  await windowManager.setPreventClose(true);
  runApp(
    PennaApp(
      config: config,
      skills: skills,
      vm: vm,
      archive: archive,
      reverse: reverse,
      local: local,
    ),
  );
}

/// 标题栏左边的字标。
class _Brand extends StatelessWidget {
  const _Brand();

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      'assets/wordmark.png',
      height: 17,
      filterQuality: FilterQuality.medium,
    );
  }
}

class PennaApp extends StatefulWidget {
  const PennaApp({
    super.key,
    required this.config,
    required this.skills,
    required this.vm,
    required this.archive,
    required this.reverse,
    required this.local,
  });

  final ArchiveStore archive;
  final LocalModel local;
  final ReverseModel reverse;
  final StudioViewModel vm;
  final ConfigService config;
  final SkillStore skills;

  @override
  State<PennaApp> createState() => _PennaAppState();
}

class _PennaAppState extends State<PennaApp> with WindowListener {
  StudioViewModel get _vm => widget.vm;

  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
  }

  @override
  Future<void> onWindowClose() async {
    try {
      await widget.local.stopServer();
    } finally {
      await windowManager.destroy();
    }
  }

  // 主题只在字体或深浅色变了的时候重建,不跟着每次设置改动重算。
  (String, String, bool)? _look;
  late ThemeData _theme;

  ThemeData _themeFor(String latin, String cjk) {
    final look = (latin, cjk, PennaColors.isDark);
    if (_look != look) {
      _look = look;
      _theme = pennaTheme(latin: latin, cjk: cjk);
    }
    return _theme;
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    _vm.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.config,
      builder: (context, _) {
        final cfg = widget.config.config;
        return MaterialApp(
          title: 'Penna 羽毛笔',
          debugShowCheckedModeBanner: false,
          theme: _themeFor(cfg.fontLatin, cfg.fontCjk),
          // 深浅色切换有自己的扩散动画(LookSwitcher),主题不再渐变一遍。
          themeAnimationDuration: Duration.zero,
          // 触控板和拖动滚到头时有回弹;滚轮的平滑见 smooth_scroll.dart。
          scrollBehavior: const MaterialScrollBehavior().copyWith(
            physics: const BouncingScrollPhysics(),
          ),
          // 标题栏放在 Navigator 外面:弹窗的遮罩盖不到它,窗口随时能拖。
          // ponytail: 整个界面不出无障碍语义树。Flutter 3.47 的 Windows 无障碍桥有空指针崩溃
          // (flutter/flutter#175041,accessibility_bridge.cc:229):有读屏、输入法这类 UIA
          // 程序在读窗口时,切页就会闪退。代价是读屏软件读不到 Penna;引擎修好后去掉这层。
          builder: (context, child) => ExcludeSemantics(
            child: LookSwitcher(
              config: widget.config,
              child: Column(
                children: [
                  SizedBox(
                    height: kWindowCaptionHeight,
                    child: WindowCaption(
                      brightness: PennaColors.isDark
                          ? Brightness.dark
                          : Brightness.light,
                      backgroundColor: PennaColors.sidebar,
                      title: const _Brand(),
                    ),
                  ),
                  Expanded(child: child!),
                ],
              ),
            ),
          ),
          home: AppShell(
            vm: _vm,
            config: widget.config,
            skills: widget.skills,
            archive: widget.archive,
            reverse: widget.reverse,
            local: widget.local,
            checkUpdates: kReleaseMode,
          ),
        );
      },
    );
  }
}
