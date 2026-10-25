part of 'layout_board.dart';

/// Agent 这次只该改哪一样:「交给 Agent」时只收描述(和程序猜的体块),
/// 其余(框、形状、图层、名字)由程序守住——模型常顺手把框也重排了。
enum LayoutKeep { none, describe }

/// 「交给 Agent」那句话的开头,[layoutKeepFor] 认它。
String get _handOverHead => tr('照画板现在的样子写好整体描述和每一块的描述');

/// 「交给 Agent」发出去的话(用户要求:设定好形状、视角、灯光、体块之后统一交给 Agent
/// 写成提示词,只留这一个按钮)。按画板现在有什么,点名要它照哪几样写;回复走
/// [LayoutKeep.describe]。
String handOverRequest(LayoutBoard board) {
  final l = board.layout;
  return [
    _handOverHead,
    if (l.boxes.any((b) => b.shape != null && !b.offscreen))
      tr('形状照【形状】写成轮廓和占的位置'),
    if (board.threeD && board.cameraMoved) tr('照现在的视角写朝向、露出哪一面和谁挡着谁'),
    if (l.lighting.enabled) tr('受光面、阴影和投影方向照【灯光】'),
    if (board.threeD && board.guessedBodies) tr('程序猜的体块顺便估好(body)'),
    tr('框、形状和图层都不动'),
  ].join(tr(';'));
}

/// 用户发的这句话要 Agent 只改哪一样。
LayoutKeep layoutKeepFor(String request) =>
    request.startsWith(_handOverHead) ? LayoutKeep.describe : LayoutKeep.none;
