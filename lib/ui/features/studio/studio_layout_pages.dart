part of 'studio_view_model.dart';

/// 区域控制工作台的分页:那场对话(`layoutOnly`)借用成稿的分页和系列(见 [StudioPages]),
/// 每一页的成稿就是一张布局(`Layout.toJson` 的 JSON,空白页是空串)。
/// 画板([StudioViewModel.layout])摆的是眼前这一页:换页时把那页的布局摆上去,
/// 画板上改了什么(拖框、Agent 放布局)写回眼前这页。
extension StudioLayoutPages on StudioViewModel {
  /// 眼前这一页存着的布局 JSON。
  String get _pageText => _blocks.map((b) => b.text).join();

  /// 页 → 画板:眼前这页的布局和画板上次对上的不一样(换了页、回滚、读档)就摆上去。
  /// 头一回对的时候眼前这页还空着,而画板上有东西(旧版只有一张画板),就把画板收进这页。
  void _syncBoard() {
    final board = layout;
    if (board == null) return;
    final text = _pageText;
    if (text == _boardText) return;
    if (_boardText == null && text.trim().isEmpty) return _pullBoard();
    _boardText = text;
    board.replace(_layoutOf(text, board.layout));
  }

  /// 画板 → 页:画板变了就写进眼前这页。只在页从空变成有、或从有变成空、
  /// 或记了一笔操作时通知界面(页签、操作记录要变样);拖框时每一帧都在变,
  /// 其余的只排一次存盘。画板标了这是哪一步操作([LayoutBoard.mark])就记进操作记录,
  /// 拖动时只有第一帧带着它。
  void _pullBoard() {
    final board = layout!;
    final action = board.takeAction();
    final l = board.layout;
    final text = l.isEmpty ? '' : jsonEncode(l.toJson());
    if (text == _boardText) return;
    _boardText = text;
    final was = _pageText;
    if (text == was) return;
    // 要在改之前记:顺手拍下的是这页原来的样子,回滚就回到这里。
    if (action != null) _log(tr('{0}({1})', [action, _here]));
    _blocks = text.isEmpty
        ? const []
        : List.unmodifiable([(text: text, pinned: false)]);
    if (action != null || was.isEmpty != text.isEmpty) return _changed();
    _scheduleSave();
  }

  /// 一页存着的布局;空白页(或读不了)是一张空画布,尺寸沿用 [now] 的。
  static Layout _layoutOf(String text, Layout now) {
    final blank = Layout(width: now.width, height: now.height);
    if (text.trim().isEmpty) return blank;
    try {
      return Layout.fromJson(jsonDecode(text) as Map<String, dynamic>);
    } on Object {
      return blank;
    }
  }

  /// 回复里写了布局(`<layout>`):放到布局画板上,并在这条回复上记一笔。
  /// 区域控制那场对话里按标签上的 `page` 放到该去的页(另起系列、新开一页),
  /// 并换到那一页,用户一眼就看得到。读不了的不记:这一栏前面是个对勾,
  /// 读不了由布局卡片自己标红。
  void _deliverLayout() {
    final board = layout;
    if (board == null || _messages.isEmpty) return;
    final made = splitLayout(splitNewSkill(_messages.last.text).prose);
    final json = made.json;
    if (!made.complete || json == null) return;
    final l0 = board.layout;
    // 先看读不读得了,免得读不了还白开一页。
    if (parseMossLayout(json, width: l0.width, height: l0.height) == null) {
      return;
    }
    final where = layoutOnly
        ? _layoutPageFor(made.page, name: made.name, title: made.series)
        : null;
    if (where != null && where.problem != null) {
      return _note(tr('布局没放上:{0}', [where.problem!]));
    }
    final before = (board.layout.width, board.layout.height);
    if (!board.apply(json)) return;
    final l = board.layout;
    final clipped = board.fixes.where((f) => f.clipped).length;
    final dropped = board.fixes.length - clipped;
    _note(
      [
        tr('已放到区域控制工作台 · {0} 个框', [l.boxes.length]),
        if (where?.moved ?? false)
          tr('「{0}」第 {1} 页', [seriesName(series), pageNumber(_page)]),
        if ((l.width, l.height) != before)
          tr('画布换成 {0}×{1}', [l.width, l.height]),
        if (board.refit case final r?)
          tr('按画布比例摆放:{0}×{1} → {2}×{3}', [
            r.width,
            r.height,
            l.width,
            l.height,
          ]),
        if (clipped > 0) tr('{0} 个超出画布,已截掉', [clipped]),
        if (dropped > 0) tr('{0} 个读不了,已去掉', [dropped]),
      ].join(' · '),
    );
  }

  /// 照 `<layout>` 标签上的 page / series / name 定好放到哪一页并换过去
  /// (同 [placeDraft])。[moved] 是换了页或另起了系列。
  ({bool moved, String? problem}) _layoutPageFor(
    String? page, {
    String? name,
    String? title,
  }) {
    final from = _page;
    if (_wantsNewSeries(page)) {
      final failed = _startSeries(title?.trim() ?? '');
      if (failed != null) return (moved: false, problem: failed);
    }
    final (at, problem) = _pageFor(page, {});
    if (at == null) return (moved: false, problem: problem);
    if (at != _page) {
      _show(at);
      _leftPage();
    }
    final pageName = name?.trim() ?? '';
    if (pageName.isNotEmpty && _pages[_page].name.isEmpty) {
      renamePage(_page, pageName);
    }
    final seriesTitle = title?.trim() ?? '';
    if (seriesTitle.isNotEmpty && !_seriesNames.containsKey(series)) {
      renameSeries(series, seriesTitle);
    }
    return (moved: _page != from || page != null, problem: null);
  }

  /// 接在带参考图的那条用户消息后面(只发给模型,不存):画布多大、只能怎么写宽高。
  String _canvasReminder() {
    final l = layout?.layout;
    if (l == null) return '';
    final (w, h) = (l.width, l.height);
    return '\n\n(程序提示:画布是 $w×$h。参考图只看画面内容和横竖,不照它的比例:'
        '<layout> 的 width / height 写 $w×$h'
        '${w == h ? '' : ',用户要横竖对调时写 $h×$w'};'
        'bbox 用这块画布的像素,不用 0–1000 的比例坐标。'
        '排框之前先照图把关系看清:谁在前、谁挡着谁、各挡住哪部分;哪些东西被画面的边裁掉;'
        '机位高低和俯仰、透视线往哪收;各元素之间的大小比例。框照这些摆(有遮挡的地方框要重叠,'
        '被裁掉的贴着画面边),前后写进 layer,透视写 <perspective>,'
        '这些关系还要写进 summary.caption 和每块的 caption。)';
  }

  /// 在最后一条回复的记录上添一笔。
  void _note(String text) => _updateReply(
    (m) => m.copyWith(toolSummary: [?m.toolSummary, text].join(' · ')),
  );

  /// 把一份布局 JSON 放到布局画板上(聊天里布局卡片上的按钮),放进眼前这一页。
  /// 读不了返回 false。
  bool adoptLayout(String json) => layout?.apply(json) ?? false;

  /// 告诉区域控制的 Agent 有哪些页、眼前是哪一页;同系列的别的页只列名字和各块。
  String get _layoutPagesPrompt {
    final others = [
      for (final (i, p) in pages.indexed)
        if (i != _page && p.series == series)
          '第 ${pageNumber(i)} 页${p.name.isEmpty ? '' : '「${p.name}」'}:'
              '${_layoutOf(p.blocks.map((b) => b.text).join(), const Layout()).boxes.map((b) => b.name.isEmpty ? b.label : b.name).join('、')}',
    ];
    return '【分页】区域控制工作台分系列、分页(最多 ${StudioPages.maxSeries} 个系列,每个系列的页数不限),'
        '每页是一张独立的布局,【布局画板】摆的是眼前这一页。'
        '【当前系列】「${seriesName(series)}」,共 $seriesLength 页,眼前是第 ${pageNumber(_page)} 页'
        '${_pages[_page].name.isEmpty ? '' : '「${_pages[_page].name}」'}。'
        '${others.isEmpty ? '' : '同系列的其他页(各块的名字):\n${others.join('\n')}'}';
  }
}
