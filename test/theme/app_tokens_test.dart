import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lossless_music_download/theme/app_tokens.dart';
import 'package:lossless_music_download/theme/app_theme.dart';

void main() {
  test('AppTokens.dark holds the locked brand hexes', () {
    const t = AppTokens.dark;
    expect(t.surface2, const Color(0xFF1C1F23));
    expect(t.surface3, const Color(0xFF252930));
    expect(t.accentSoft, const Color(0xFF10241A));
    expect(t.accentLine, const Color(0xFF1F4D36));
    expect(t.accentInk, const Color(0xFF04150C));
    expect(t.warn, const Color(0xFFE0B341));
    expect(t.down, const Color(0xFFE06A52));
    expect(t.muted2, const Color(0xFF7A818B));
    expect(t.lineSoft, const Color(0xFF2A2E34));
    expect(t.info, const Color(0xFF5EA8E6));
    expect(t.infoSoft, const Color(0xFF10202E));
    expect(t.verified, const Color(0xFF1DB954));
    expect(t.suspect, t.warn);
    expect(t.suspectSoft, t.warnSoft);
    expect(t.mono.fontFamily, 'JetBrainsMono');
    expect(t.mono.fontFeatures, [const FontFeature.tabularFigures()]);
    expect(t.mono.letterSpacing, -0.2);
  });

  test('lerp returns an AppTokens (identity at t=0)', () {
    const t = AppTokens.dark;
    final l = t.lerp(t, 0);
    expect(l.accentSoft, t.accentSoft);
  });

  test('new colors survive copyWith and interpolate between themes', () {
    const t = AppTokens.dark;
    final unchanged = t.copyWith();
    expect(unchanged.lineSoft, t.lineSoft);
    expect(unchanged.info, t.info);
    expect(unchanged.infoSoft, t.infoSoft);
    final other = t.copyWith(
      lineSoft: const Color(0xFF4A4E54),
      info: const Color(0xFF7EC8F6),
      infoSoft: const Color(0xFF30404E),
      warn: const Color(0xFFFFFFFF),
      warnSoft: const Color(0xFF000000),
    );
    expect(other.lineSoft, const Color(0xFF4A4E54));
    expect(other.info, const Color(0xFF7EC8F6));
    expect(other.infoSoft, const Color(0xFF30404E));
    expect(other.suspect, const Color(0xFFFFFFFF));
    expect(other.suspectSoft, const Color(0xFF000000));
    final midpoint = t.lerp(other, 0.5);
    expect(midpoint.lineSoft.toARGB32(), 0xFF3A3E44);
    expect(midpoint.info.toARGB32(), 0xFF6EB8EE);
    expect(midpoint.infoSoft.toARGB32(), 0xFF20303E);
    expect(t.lerp(other, 0).info, t.info);
    expect(t.lerp(other, 1).info, other.info);
    expect(t.lerp(null, 0.5), same(t));
  });

  test('type, radius and spacing scales match the refresh contract', () {
    expect(
      AppText.pageTitle,
      const TextStyle(
        fontSize: 28,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.3,
      ),
    );
    expect(
      AppText.section,
      const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
    );
    expect(
      AppText.title,
      const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
    );
    expect(
      AppText.body,
      const TextStyle(fontSize: 14, fontWeight: FontWeight.w400),
    );
    expect(
      AppText.caption,
      const TextStyle(fontSize: 12, fontWeight: FontWeight.w400),
    );
    expect(
      AppText.badge,
      const TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.4,
      ),
    );
    expect(
      [AppRadius.xs, AppRadius.sm, AppRadius.md, AppRadius.lg],
      [6, 10, 13, 24],
    );
    expect(
      [
        AppSpace.xs,
        AppSpace.sm,
        AppSpace.md,
        AppSpace.lg,
        AppSpace.xl,
        AppSpace.xxl,
      ],
      [4, 8, 12, 16, 24, 32],
    );
    expect(AppSpace.page, 16);
  });

  test(
    'theme applies refreshed navigation, surfaces, title and input tokens',
    () {
      final theme = appTheme();
      expect(theme.colorScheme.outline, const Color(0xFF353A41));
      expect(theme.colorScheme.outlineVariant, const Color(0xFF2A2E34));
      expect(theme.colorScheme.surfaceContainerLow, const Color(0xFF131518));
      expect(theme.colorScheme.surfaceContainer, const Color(0xFF15171A));
      expect(theme.cardTheme.color, const Color(0xFF15171A));
      expect(theme.bottomSheetTheme.backgroundColor, const Color(0xFF15171A));
      expect(theme.dividerTheme.color, const Color(0xFF2A2E34));
      final title = theme.appBarTheme.titleTextStyle!;
      // Sub-pages get 22px; the 28px pageTitle is applied only on tab roots.
      expect(title.fontSize, 22);
      expect(title.fontWeight, FontWeight.w600);
      // A null family renders as tofu boxes in goldens; keep the theme's font.
      expect(title.fontFamily, isNotNull);
      final nav = theme.navigationBarTheme;
      expect(nav.indicatorColor, const Color(0xFF10241A));
      expect(nav.labelTextStyle!.resolve({})!.fontSize, 12);
      expect(nav.labelTextStyle!.resolve({})!.color, const Color(0xFF7A818B));
      expect(nav.iconTheme!.resolve({})!.color, const Color(0xFF7A818B));
      expect(
        nav.labelTextStyle!.resolve({WidgetState.selected})!.color,
        kAccent,
      );
      expect(nav.iconTheme!.resolve({WidgetState.selected})!.color, kAccent);
      final border = theme.inputDecorationTheme.border! as OutlineInputBorder;
      expect(border.borderRadius, BorderRadius.circular(10));
      expect(border.borderSide.color, const Color(0xFF353A41));
    },
  );
}
