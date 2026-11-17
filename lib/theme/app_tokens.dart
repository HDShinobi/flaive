import 'package:flutter/material.dart';

@immutable
class AppTokens extends ThemeExtension<AppTokens> {
  const AppTokens({
    required this.surface2,
    required this.surface3,
    required this.accentSoft,
    required this.accentLine,
    required this.accentInk,
    required this.warn,
    required this.warnSoft,
    required this.warnLine,
    required this.down,
    required this.downSoft,
    required this.muted2,
    required this.lineSoft,
    required this.info,
    required this.infoSoft,
    required this.mono,
  });

  final Color surface2, surface3, accentSoft, accentLine, accentInk;
  final Color warn, warnSoft, warnLine, down, downSoft, muted2;
  final Color lineSoft, info, infoSoft;
  final TextStyle mono;

  Color get verified => const Color(0xFF1DB954);
  Color get suspect => warn;
  Color get suspectSoft => warnSoft;

  static const AppTokens dark = AppTokens(
    surface2: Color(0xFF1C1F23),
    surface3: Color(0xFF252930),
    accentSoft: Color(0xFF10241A),
    accentLine: Color(0xFF1F4D36),
    accentInk: Color(0xFF04150C),
    warn: Color(0xFFE0B341),
    warnSoft: Color(0xFF2A2310),
    warnLine: Color(0xFF4D4022),
    down: Color(0xFFE06A52),
    downSoft: Color(0xFF2A1714),
    muted2: Color(0xFF7A818B),
    lineSoft: Color(0xFF2A2E34),
    info: Color(0xFF5EA8E6),
    infoSoft: Color(0xFF10202E),
    mono: TextStyle(
      fontFamily: 'JetBrainsMono',
      fontFeatures: [FontFeature.tabularFigures()],
      letterSpacing: -0.2,
    ),
  );

  @override
  AppTokens copyWith({
    Color? surface2,
    Color? surface3,
    Color? accentSoft,
    Color? accentLine,
    Color? accentInk,
    Color? warn,
    Color? warnSoft,
    Color? warnLine,
    Color? down,
    Color? downSoft,
    Color? muted2,
    Color? lineSoft,
    Color? info,
    Color? infoSoft,
    TextStyle? mono,
  }) {
    return AppTokens(
      surface2: surface2 ?? this.surface2,
      surface3: surface3 ?? this.surface3,
      accentSoft: accentSoft ?? this.accentSoft,
      accentLine: accentLine ?? this.accentLine,
      accentInk: accentInk ?? this.accentInk,
      warn: warn ?? this.warn,
      warnSoft: warnSoft ?? this.warnSoft,
      warnLine: warnLine ?? this.warnLine,
      down: down ?? this.down,
      downSoft: downSoft ?? this.downSoft,
      muted2: muted2 ?? this.muted2,
      lineSoft: lineSoft ?? this.lineSoft,
      info: info ?? this.info,
      infoSoft: infoSoft ?? this.infoSoft,
      mono: mono ?? this.mono,
    );
  }

  @override
  AppTokens lerp(ThemeExtension<AppTokens>? other, double t) {
    if (other is! AppTokens) return this;
    return AppTokens(
      surface2: Color.lerp(surface2, other.surface2, t)!,
      surface3: Color.lerp(surface3, other.surface3, t)!,
      accentSoft: Color.lerp(accentSoft, other.accentSoft, t)!,
      accentLine: Color.lerp(accentLine, other.accentLine, t)!,
      accentInk: Color.lerp(accentInk, other.accentInk, t)!,
      warn: Color.lerp(warn, other.warn, t)!,
      warnSoft: Color.lerp(warnSoft, other.warnSoft, t)!,
      warnLine: Color.lerp(warnLine, other.warnLine, t)!,
      down: Color.lerp(down, other.down, t)!,
      downSoft: Color.lerp(downSoft, other.downSoft, t)!,
      muted2: Color.lerp(muted2, other.muted2, t)!,
      lineSoft: Color.lerp(lineSoft, other.lineSoft, t)!,
      info: Color.lerp(info, other.info, t)!,
      infoSoft: Color.lerp(infoSoft, other.infoSoft, t)!,
      mono: TextStyle.lerp(mono, other.mono, t)!,
    );
  }
}

abstract final class AppText {
  static const pageTitle = TextStyle(
    fontSize: 28,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.3,
  );
  static const section = TextStyle(fontSize: 18, fontWeight: FontWeight.w600);
  static const title = TextStyle(fontSize: 16, fontWeight: FontWeight.w500);
  static const body = TextStyle(fontSize: 14, fontWeight: FontWeight.w400);
  static const caption = TextStyle(fontSize: 12, fontWeight: FontWeight.w400);
  static const badge = TextStyle(
    fontSize: 11,
    fontWeight: FontWeight.w600,
    letterSpacing: 0.4,
  );
}

abstract final class AppRadius {
  static const double xs = 6, sm = 10, md = 13, lg = 24;
}

abstract final class AppSpace {
  static const double xs = 4, sm = 8, md = 12, lg = 16, xl = 24, xxl = 32;
  static const double page = 16;
}

extension AppTokensX on BuildContext {
  AppTokens get tokens =>
      Theme.of(this).extension<AppTokens>() ?? AppTokens.dark;
}
