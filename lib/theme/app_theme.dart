import 'package:flutter/material.dart';
import 'app_tokens.dart';

const kAccent = Color(0xFF1DB954);
const kGround = Color(0xFF0E0F11);

const _accentInk = Color(0xFF04150C);
const _accentSoft = Color(0xFF10241A);
const _line = Color(0xFF353A41);
const _lineSoft = Color(0xFF2A2E34);
const _surface = Color(0xFF15171A);
const _text = Color(0xFFE9EBEE);
const _muted = Color(0xFF8B929B);
const _down = Color(0xFFE06A52);

ColorScheme _scheme() => const ColorScheme(
  brightness: Brightness.dark,
  primary: kAccent,
  onPrimary: _accentInk,
  primaryContainer: _accentSoft,
  onPrimaryContainer: kAccent,
  secondary: kAccent,
  onSecondary: _accentInk,
  secondaryContainer: _accentSoft,
  onSecondaryContainer: kAccent,
  tertiary: Color(0xFFE0B341),
  onTertiary: Color(0xFF221A04),
  error: _down,
  onError: Color(0xFF2A1714),
  errorContainer: Color(0xFF2A1714),
  onErrorContainer: _down,
  surface: kGround,
  onSurface: _text,
  surfaceContainerLowest: Color(0xFF0E0F11),
  surfaceContainerLow: Color(0xFF131518),
  surfaceContainer: _surface,
  surfaceContainerHigh: Color(0xFF1C1F23),
  surfaceContainerHighest: Color(0xFF252930),
  onSurfaceVariant: _muted,
  outline: _line,
  outlineVariant: _lineSoft,
  inverseSurface: _text,
  onInverseSurface: kGround,
  inversePrimary: kAccent,
  shadow: Color(0xFF000000),
  scrim: Color(0xFF000000),
);

ThemeData appTheme() {
  final scheme = _scheme();
  final base = ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: kGround,
    extensions: const [AppTokens.dark],
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: kGround,
      indicatorColor: AppTokens.dark.accentSoft,
      elevation: 0,
      labelTextStyle: WidgetStateProperty.resolveWith(
        (s) => AppText.caption.copyWith(
          color: s.contains(WidgetState.selected)
              ? kAccent
              : AppTokens.dark.muted2,
        ),
      ),
      iconTheme: WidgetStateProperty.resolveWith(
        (s) => IconThemeData(
          color: s.contains(WidgetState.selected)
              ? kAccent
              : AppTokens.dark.muted2,
        ),
      ),
    ),
    cardTheme: CardThemeData(
      color: _surface,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.md),
        side: const BorderSide(color: _lineSoft),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: kAccent,
        foregroundColor: _accentInk,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
      ),
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: _surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.lg)),
      ),
    ),
    progressIndicatorTheme: const ProgressIndicatorThemeData(
      color: kAccent,
      linearTrackColor: Color(0xFF252930),
    ),
    dividerTheme: const DividerThemeData(color: _lineSoft),
    inputDecorationTheme: InputDecorationTheme(
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.sm),
        borderSide: const BorderSide(color: _line),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.sm),
        borderSide: const BorderSide(color: _line),
      ),
    ),
  );
  // Pushed sub-pages keep titleLarge (22px); tab roots opt into AppText.pageTitle.
  // Built from titleLarge so the title keeps the platform font family and color.
  return base.copyWith(
    appBarTheme: AppBarTheme(
      // Flat header like the boards: no green surface tint when content scrolls under.
      scrolledUnderElevation: 0,
      // Raw textTheme has no geometry yet (sizes are added at Theme.of), so set 22 here.
      titleTextStyle: base.textTheme.titleLarge!.copyWith(
        fontSize: 22,
        fontWeight: FontWeight.w600,
      ),
    ),
  );
}
