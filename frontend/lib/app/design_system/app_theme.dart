import 'package:communication_platform/app/design_system/app_tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:forui/forui.dart';

abstract final class AppTheme {
  static ThemeData light() => _material(AppColorTokens.light);
  static ThemeData dark() => _material(AppColorTokens.dark);
  static ThemeData highContrastLight() =>
      _material(AppColorTokens.highContrastLight);
  static ThemeData highContrastDark() =>
      _material(AppColorTokens.highContrastDark);

  static ThemeData _material(AppColorTokens colors) {
    final typography = AppTypographyTokens.from(colors);
    final baseScheme = ColorScheme.fromSeed(
      seedColor: colors.accent,
      brightness: colors.brightness,
    );
    final scheme = baseScheme.copyWith(
      primary: colors.accent,
      onPrimary: colors.brightness == Brightness.light
          ? Colors.white
          : colors.canvas,
      secondary: colors.accentSoft,
      onSecondary: colors.textPrimary,
      error: colors.danger,
      onError: colors.brightness == Brightness.light
          ? Colors.white
          : colors.canvas,
      surface: colors.surface,
      onSurface: colors.textPrimary,
      outline: colors.border,
      scrim: colors.scrim,
    );

    return ThemeData(
      brightness: colors.brightness,
      colorScheme: scheme,
      fontFamily: AppTypographyTokens.fontFamily,
      scaffoldBackgroundColor: colors.canvas,
      canvasColor: colors.canvas,
      focusColor: colors.accent,
      disabledColor: colors.textMuted.withValues(alpha: 0.55),
      textTheme: TextTheme(
        displaySmall: typography.display,
        headlineSmall: typography.title,
        titleLarge: typography.section,
        bodyLarge: typography.body,
        bodyMedium: typography.compact,
        labelLarge: typography.compact.copyWith(fontWeight: FontWeight.w500),
        labelSmall: typography.label,
      ),
      extensions: [AppThemeTokens(colors: colors, typography: typography)],
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: colors.textPrimary,
          borderRadius: AppRadii.compact,
        ),
        textStyle: typography.compact.copyWith(color: colors.canvas),
        waitDuration: AppMotion.press,
      ),
      useMaterial3: true,
    );
  }

  static FThemeData forui(BuildContext context, {required bool touch}) {
    final tokens = context.tokens;
    final colors = tokens.colors;
    final fColors = FColors(
      brightness: colors.brightness,
      systemOverlayStyle: colors.brightness == Brightness.light
          ? SystemUiOverlayStyle.dark
          : SystemUiOverlayStyle.light,
      barrier: colors.scrim,
      background: colors.canvas,
      foreground: colors.textPrimary,
      primary: colors.accent,
      primaryForeground: colors.brightness == Brightness.light
          ? Colors.white
          : colors.canvas,
      secondary: colors.surfaceRaised,
      secondaryForeground: colors.textPrimary,
      muted: colors.surfaceRaised,
      mutedForeground: colors.textMuted,
      destructive: colors.danger,
      destructiveForeground: colors.brightness == Brightness.light
          ? Colors.white
          : colors.canvas,
      error: colors.danger,
      errorForeground: colors.brightness == Brightness.light
          ? Colors.white
          : colors.canvas,
      card: colors.surface,
      border: colors.border,
    );
    final type = tokens.typography;
    final typeface = FTypeface(
      fontFamily: AppTypographyTokens.fontFamily,
      xs: type.label,
      sm: type.compact,
      md: type.body,
      lg: type.section,
      xl: type.title,
      xl2: type.display,
    );
    final typography = FTypography(display: typeface, body: typeface);
    final style =
        FStyle.inherit(
          colors: fColors,
          typography: typography,
          touch: touch,
        ).copyWith(
          borderRadius: const FBorderRadius(
            xs2: AppRadii.compact,
            xs: AppRadii.compact,
            sm: AppRadii.compact,
            md: AppRadii.card,
            lg: AppRadii.card,
            xl: AppRadii.control,
            xl2: AppRadii.message,
            xl3: AppRadii.message,
            pill: AppRadii.pill,
          ),
          focusedOutlineStyle: FFocusedOutlineStyle(
            color: colors.accent,
            borderRadius: AppRadii.control,
            width: AppFocus.ringWidth,
            spacing: AppFocus.ringGap,
          ),
          pagePadding: const EdgeInsetsDelta.value(
            EdgeInsets.symmetric(
              horizontal: AppSpacing.x4,
              vertical: AppSpacing.x2,
            ),
          ),
          shadow: AppElevation.level1,
        );

    return FThemeData(
      colors: fColors,
      touch: touch,
      debugLabel:
          'App ${colors.brightness.name} ${touch ? 'touch' : 'pointer'}',
      typography: typography,
      style: style,
    );
  }
}

/// The package theme boundary used by the application root and component tests.
class AppDesignSystem extends StatelessWidget {
  const AppDesignSystem({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) => FTheme(
      data: AppTheme.forui(
        context,
        touch: AppBreakpoints.of(constraints.maxWidth) == AppWidthClass.narrow,
      ),
      child: child,
    ),
  );
}
