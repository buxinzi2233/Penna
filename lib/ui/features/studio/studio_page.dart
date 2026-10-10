import 'package:flutter/material.dart';

import '../../../data/services/archive_store.dart';
import '../../../data/services/config_service.dart';
import '../../core/theme.dart';
import 'activity_bar.dart';
import 'chat_pane.dart';
import 'prompt_pane.dart';
import 'reverse_model.dart';
import 'studio_view_model.dart';

const _splitterWidth = 4.0;
const _minSplit = 0.3;
const _maxSplit = 0.7;

/// 工作台:左成稿 + 可拖分割线 + 右对话。
// ponytail: 小窗不折叠成页签,靠 windows/runner/win32_window.cpp 里的最小窗口尺寸
// (1100x700)兜底;要支持更小的窗口时再做页签降级。
class StudioPage extends StatefulWidget {
  const StudioPage({
    super.key,
    required this.vm,
    required this.config,
    required this.archive,
    required this.reverse,
    required this.onOpenSettings,
  });

  final StudioViewModel vm;
  final ArchiveStore archive;
  final ReverseModel reverse;
  final ConfigService config;
  final VoidCallback onOpenSettings;

  @override
  State<StudioPage> createState() => _StudioPageState();
}

class _StudioPageState extends State<StudioPage> {
  final _input = TextEditingController();
  final _inputFocus = FocusNode();
  late final _changes = Listenable.merge([widget.vm, widget.config]);
  double _split = 0.53;

  @override
  void dispose() {
    _input.dispose();
    _inputFocus.dispose();
    super.dispose();
  }

  /// 把快捷指令填进输入框,光标放到末尾并聚焦,方便接着打字。
  void _fillInput(String text) {
    _input.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
    _inputFocus.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, box) {
        final usable =
            box.maxWidth - _splitterWidth - ActivityBar.widthOf(open: false);
        return ListenableBuilder(
          listenable: _changes,
          builder: (context, _) => Row(
            children: [
              ActivityBar(vm: widget.vm),
              // 左栏的宽度是算好的;操作记录展开时多占的那一截,由右边的对话让出来。
              SizedBox(
                width: usable * _split,
                child: PromptPane(
                  vm: widget.vm,
                  archive: widget.archive,
                  reverse: widget.reverse,
                  onSendToAgent: _fillInput,
                  // 选中一段后直接去输入框打字。
                  onDiscuss: (section) {
                    widget.vm.quoteSection(section);
                    _inputFocus.requestFocus();
                  },
                ),
              ),
              _Splitter(
                onDrag: (dx) => setState(() {
                  _split = (_split + dx / usable).clamp(_minSplit, _maxSplit);
                }),
              ),
              Expanded(
                child: ChatPane(
                  vm: widget.vm,
                  config: widget.config,
                  input: _input,
                  inputFocus: _inputFocus,
                  onQuickAction: _fillInput,
                  onOpenSettings: widget.onOpenSettings,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _Splitter extends StatelessWidget {
  const _Splitter({required this.onDrag});

  final ValueChanged<double> onDrag;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.resizeColumn,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onHorizontalDragUpdate: (d) => onDrag(d.delta.dx),
        child: Container(
          width: _splitterWidth,
          color: PennaColors.border,
          alignment: Alignment.center,
          child: Container(width: 2, height: 32, color: PennaColors.slate400),
        ),
      ),
    );
  }
}
