part of 'layout_board.dart';

/// Agent 这次只该改哪一样:按视角、按形状改描述时只收描述,估体块时只收体块,
/// 其余(框、形状、图层、名字)由程序守住——模型常顺手把框也重排了。
enum LayoutKeep { none, captions, bodies }

/// 「按视角改描述」「让 Agent 估体块」「按形状改描述」发出去的话;
/// 回复照 [LayoutKeep] 只收那一样。
String get redescribeRequest =>
    tr('镜头换了角度,照新视角改整体描述和每块的描述(朝向、露出哪一面、左右前后的位置关系、谁挡着谁),框、体块和图层都不动');
String get estimateRequest => tr('给画板上每块估体块(body:远近、厚度、朝向),框的位置、描述和图层都不动');
String get shapeRequest =>
    tr('照【形状】改每块的描述:把形状写成画面里看得出的轮廓和占的位置(交出去只有方框),框、形状和图层都不动');

/// 用户发的这句话要 Agent 只改哪一样。
LayoutKeep layoutKeepFor(String request) =>
    request == redescribeRequest || request == shapeRequest
    ? LayoutKeep.captions
    : request == estimateRequest
    ? LayoutKeep.bodies
    : LayoutKeep.none;
