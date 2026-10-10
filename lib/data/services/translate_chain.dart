import '../models/app_config.dart';
import 'translate_engines.dart';

typedef ConfigTranslator = Future<TranslateResult> Function(
  AppConfig config,
  String text,
);

String mtLabel(String id) => mtEngines.firstWhere((e) => e.id == id).label;

// ponytail: 方向固定英→中(成稿是英文,译文给人核对);要反向或自动识别时再加参数。
/// 按设置里的引擎顺序、尝试次数和超时翻译 [text]。
Future<TranslateResult> translateWithConfig(AppConfig config, String text) {
  return translateWithFailover(
    chain: [for (final id in config.mtChain) (id, _engine(config, id))],
    text: text,
    from: 'en',
    to: 'zh',
    attempts: config.mtAttempts,
    timeout: Duration(seconds: config.mtTimeoutSeconds),
  );
}

Translator _engine(AppConfig config, String id) {
  String value(String field) {
    final key = 'mt.$id.$field';
    return config.secrets[key] ?? config.fields[key] ?? '';
  }

  return switch (id) {
    'google_free' => googleFree,
    'mymemory' => myMemory,
    'google' => googleCloud(value('key')),
    'ali' => ali(value('id'), value('secret')),
    'baidu' => baidu(value('appid'), value('secret')),
    _ => throw StateError('未知翻译引擎:$id'),
  };
}
