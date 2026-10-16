import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../../l10n/l10n.dart';

/// 档案库里的一条:用户主动存下来的一份成稿。
typedef ArchiveEntry = ({
  String id,
  DateTime time,
  String category,
  String title,
  String text,
});

/// 没填分类时归到这里。
const uncategorized = '未分类';

/// 档案库:用户点「保存」存下来的成稿,带时间和分类。存在「文档\Penna\archive.json」。
class ArchiveStore extends ChangeNotifier {
  /// [file] 为 null 时只在内存里(测试用)。
  ArchiveStore([this.file]);

  final File? file;

  List<ArchiveEntry> _entries = const [];

  /// 新的在前。
  List<ArchiveEntry> get entries => _entries;

  /// 用过的分类,按最近用到的先后。
  List<String> get categories =>
      {for (final e in _entries) e.category}.toList();

  /// 存一条;[text] 是空的就不存。分类没填归「未分类」。
  void add({
    required String text,
    String title = '',
    String category = '',
    DateTime? now,
  }) {
    if (text.trim().isEmpty) return;
    final time = now ?? DateTime.now();
    _set([
      (
        id: '${time.microsecondsSinceEpoch}',
        time: time,
        category: category.trim().isEmpty ? uncategorized : category.trim(),
        title: title.trim(),
        text: text,
      ),
      ..._entries,
    ]);
  }

  void remove(String id) => _set(_entries.where((e) => e.id != id));

  void _set(Iterable<ArchiveEntry> next) {
    _entries = List.unmodifiable(next);
    notifyListeners();
    _save();
  }

  // ponytail: 每次改动都把整个文件重写一遍;存到几千条嫌慢时再改成追加或换数据库。
  void _save() {
    final file = this.file;
    if (file == null) return;
    try {
      file.parent.createSync(recursive: true);
      // 先写临时文件再改名:写到一半断电也不会留下半个文件。
      final temp = File('${file.path}.tmp')
        ..writeAsStringSync(
          jsonEncode([
            for (final e in _entries)
              {
                'id': e.id,
                'time': e.time.toIso8601String(),
                'category': e.category,
                'title': e.title,
                'text': e.text,
              },
          ]),
        );
      temp.renameSync(file.path);
    } on FileSystemException catch (e) {
      debugPrint(tr('档案库没存上:{0}', [e.message]));
    }
  }

  Future<void> load() async {
    final file = this.file;
    if (file == null || !file.existsSync()) return;
    try {
      final list = jsonDecode(await file.readAsString()) as List;
      _entries = List.unmodifiable([
        for (final e in list.cast<Map<String, dynamic>>())
          (
            id: e['id'] as String,
            time: DateTime.parse(e['time'] as String),
            category: e['category'] as String? ?? uncategorized,
            title: e['title'] as String? ?? '',
            text: e['text'] as String,
          ),
      ]);
      notifyListeners();
    } on Object {
      // 读不了的文件留个底再重新开始,不让下一次保存把它盖掉。
      try {
        file.renameSync(
          '${file.path}.bad-${DateTime.now().millisecondsSinceEpoch}',
        );
      } on FileSystemException {
        // 留底失败也不拦着程序启动。
      }
    }
  }
}
