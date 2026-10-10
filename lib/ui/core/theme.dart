import 'package:flutter/material.dart';

/// 颜色取自 design/desktop/code.html 的 tailwind 配置(浅色原型)。
abstract final class PennaColors {
  static const bg = Color(0xFFF8F9FA);
  static const sidebar = Color(0xFFF1F3F5);
  static const card = Colors.white;
  static const editorBg = Color(0xFFFCFDFD);
  static const border = Color(0xFFE2E8F0);
  static const slate50 = Color(0xFFF8FAFC);
  static const slate100 = Color(0xFFF1F5F9);
  static const slate400 = Color(0xFF94A3B8);
  static const slate500 = Color(0xFF64748B);
  static const slate700 = Color(0xFF334155);
  static const text = Color(0xFF0F172A);
  static const primary = Color(0xFF2563EB);
  static const primaryBg = Color(0xFFEFF6FF);
  static const primaryBorder = Color(0xFFBFDBFE);
  static const accent = Color(0xFF059669);
  static const amber = Color(0xFFF59E0B);
  static const lock = Color(0xFFFFFBEB);
  static const lockBorder = Color(0xFFFDE68A);
  static const lockText = Color(0xFF92400E);
  static const diffAdd = Color(0xFFECFDF5);
  static const diffAddText = Color(0xFF065F46);
  static const diffDel = Color(0xFFFEF2F2);
  static const diffDelText = Color(0xFFBE123C);
}

/// 随软件打包的默认字体(见 pubspec.yaml 的 fonts 与 font/ 目录)。
const bundledLatinFont = 'Maple Mono';
const bundledCjkFont = 'LXGW 975 Yuan SC';

/// 成稿区文字:字体跟随全局(默认的 Maple Mono 本身就是等宽)。
const TextStyle monoStyle = TextStyle(
  fontSize: 12.5,
  height: 1.6,
  color: PennaColors.slate700,
);

/// [latin] / [cjk] 是用户在设置里选的字体名,留空用内置字体。
ThemeData pennaTheme({String latin = '', String cjk = ''}) {
  final family = latin.trim().isEmpty ? bundledLatinFont : latin.trim();
  final fallback = [
    // 用户填的英文字体没装时,英文仍落回内置英文字体而不是中文字体。
    bundledLatinFont,
    if (cjk.trim().isNotEmpty) cjk.trim(),
    bundledCjkFont,
    'Microsoft YaHei UI',
  ];
  // 这几处主题的文字样式是整体替换的,不带上字体就会掉回系统默认字体。
  final font = TextStyle(fontFamily: family, fontFamilyFallback: fallback);
  final scheme = ColorScheme.fromSeed(seedColor: PennaColors.primary).copyWith(
    primary: PennaColors.primary,
    surface: PennaColors.card,
    surfaceTint: Colors.transparent,
    outline: PennaColors.border,
    outlineVariant: PennaColors.border,
  );
  final base = ThemeData(
    useMaterial3: true,
    fontFamily: family,
    fontFamilyFallback: fallback,
    colorScheme: scheme,
    scaffoldBackgroundColor: PennaColors.bg,
    dividerColor: PennaColors.border,
    popupMenuTheme: PopupMenuThemeData(
      color: PennaColors.card,
      surfaceTintColor: Colors.transparent,
      elevation: 8,
      shadowColor: const Color(0x330F172A),
      menuPadding: const EdgeInsets.all(4),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: const BorderSide(color: PennaColors.border),
      ),
    ),
    tooltipTheme: TooltipThemeData(
      waitDuration: const Duration(milliseconds: 400),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: PennaColors.text,
        borderRadius: BorderRadius.circular(6),
      ),
      textStyle: font.copyWith(fontSize: 11.5, color: Colors.white),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: PennaColors.text,
      behavior: SnackBarBehavior.floating,
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      contentTextStyle: font.copyWith(fontSize: 12.5, color: Colors.white),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: PennaColors.card,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
    sliderTheme: const SliderThemeData(
      trackHeight: 4,
      activeTrackColor: PennaColors.primary,
      inactiveTrackColor: PennaColors.border,
      thumbColor: PennaColors.primary,
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected)
            ? Colors.white
            : PennaColors.slate400,
      ),
      trackColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected)
            ? PennaColors.primary
            : PennaColors.slate100,
      ),
      trackOutlineColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected)
            ? Colors.transparent
            : PennaColors.border,
      ),
    ),
  );
  return base.copyWith(
    textTheme: base.textTheme.apply(
      bodyColor: PennaColors.text,
      displayColor: PennaColors.text,
    ),
  );
}
