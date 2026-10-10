import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../core/widgets.dart';

/// 多选的选项:勾上几个(或点「全选」),再点「确定」一起当成回答发出去。
/// [onSubmit] 为 null 时只是摆着看(不是最新那条回复,或正在生成)。
class MultiPick extends StatefulWidget {
  const MultiPick({super.key, required this.options, required this.onSubmit});

  final List<String> options;
  final ValueChanged<String>? onSubmit;

  @override
  State<MultiPick> createState() => _PickState();
}

class _PickState extends State<MultiPick> {
  var _picked = const <String>{};

  void _toggle(String option) => setState(
    () => _picked = _picked.contains(option)
        ? _picked.difference({option})
        : {..._picked, option},
  );

  @override
  Widget build(BuildContext context) {
    final live = widget.onSubmit != null;
    final all = _picked.length == widget.options.length;
    return IgnorePointer(
      ignoring: !live,
      child: Opacity(
        opacity: live ? 1 : 0.55,
        child: PennaCard(
          color: PennaColors.slate50,
          radius: 10,
          padding: const EdgeInsets.all(10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final option in widget.options)
                    PennaChip(
                      label: option,
                      selected: _picked.contains(option),
                      onTap: () => _toggle(option),
                    ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  PennaButton(
                    label: all ? '全不选' : '全选',
                    icon: all ? Icons.deselect : Icons.select_all,
                    borderColor: PennaColors.border,
                    onPressed: () => setState(
                      () => _picked = all ? const {} : {...widget.options},
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '已选 ${_picked.length} / ${widget.options.length}',
                      style: const TextStyle(
                        fontSize: 11,
                        color: PennaColors.slate500,
                      ),
                    ),
                  ),
                  PennaButton(
                    label: '确定',
                    icon: Icons.check,
                    background: PennaColors.primary,
                    foreground: Colors.white,
                    // 按原来的先后发出去;全选了就说「全部」。
                    onPressed: _picked.isEmpty
                        ? null
                        : () => widget.onSubmit?.call(
                            all
                                ? '全部'
                                : widget.options
                                      .where(_picked.contains)
                                      .join('、'),
                          ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
