import 'package:flutter/material.dart';

/// Paleta i widgety w stylu makiet (docs/diagrams/mapa_ekranow, design/).
class Px {
  static const bg = Color(0xFFEAF0FB);
  static const panel = Color(0xFFF7F9FF);
  static const ink = Color(0xFF0B1B3F);
  static const ink2 = Color(0xFF41527E);
  static const soft = Color(0xFFB8C6E8);
  static const accent = Color(0xFF1D4ED8);
  static const accentDark = Color(0xFF1338A8);
  static const accentLight = Color(0xFFBFD3FF);
  static const warnBg = Color(0xFFFFF1C2);
  static const danger = Color(0xFFD64545);

  static const _family = 'IBMPlexSans';

  static TextStyle text(
    double size, {
    int weight = 400,
    Color color = ink,
    double? height,
    List<FontFeature>? features,
  }) =>
      TextStyle(
        fontFamily: _family,
        fontSize: size,
        color: color,
        height: height,
        fontVariations: [FontVariation('wght', weight.toDouble())],
        fontFeatures: features ?? const [FontFeature.tabularFigures()],
      );

  static TextStyle get hero => text(64, weight: 400, height: 1.0);
  static TextStyle get display => text(40, weight: 400, height: 1.1);
  static TextStyle get h1 => text(28, weight: 400, height: 1.15);
  static TextStyle get h2 => text(20, weight: 500, height: 1.2);
  static TextStyle get body => text(16);
  static TextStyle get secondary => text(14, color: ink2);
  static TextStyle get caption => text(12, color: ink2);

  static ThemeData get theme => ThemeData(
        useMaterial3: true,
        scaffoldBackgroundColor: bg,
        fontFamily: _family,
        colorScheme: ColorScheme.fromSeed(seedColor: accent, surface: bg),
        textTheme: TextTheme(bodyMedium: body),
      );
}

/// Ramka 2 px z twardym cieniem (bez promienia).
class PixelCard extends StatelessWidget {
  const PixelCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.color = Px.panel,
    this.selected = false,
  });

  final Widget child;
  final EdgeInsets padding;
  final Color color;
  final bool selected;

  @override
  Widget build(BuildContext context) => Container(
        padding: padding,
        decoration: BoxDecoration(
          color: selected ? Px.accentLight : color,
          border: Border.all(color: Px.ink, width: 2),
        ),
        child: child,
      );
}

/// Przycisk 56 dp: wciśnięta dolna krawędź jak w makietach.
class PixelButton extends StatelessWidget {
  const PixelButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.primary = true,
    this.height = 56,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool primary;
  final double height;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    final bg = primary ? Px.accent : Px.panel;
    final edge = primary ? Px.accentDark : Px.soft;
    final fg = primary ? Colors.white : Px.ink;
    return Semantics(
      button: true,
      enabled: enabled,
      label: label,
      child: GestureDetector(
        onTap: onPressed,
        child: Opacity(
          opacity: enabled ? 1 : 0.45,
          child: Container(
            height: height,
            decoration: BoxDecoration(
              color: bg,
              border: Border.all(color: Px.ink, width: 2),
            ),
            child: Container(
              decoration: BoxDecoration(
                border: Border(bottom: BorderSide(color: edge, width: primary ? 6 : 4)),
              ),
              alignment: Alignment.center,
              child: Text(label,
                  style: Px.text(primary ? 22 : 20, color: fg, weight: 400)),
            ),
          ),
        ),
      ),
    );
  }
}

/// Pasek segmentowy (np. postęp do następnego etapu).
class PixelBar extends StatelessWidget {
  const PixelBar({super.key, required this.value, this.segments = 12, this.height = 24});

  /// 0..1
  final double value;
  final int segments;
  final double height;

  @override
  Widget build(BuildContext context) {
    final filled = (value.clamp(0.0, 1.0) * segments).floor();
    return Container(
      height: height,
      decoration: BoxDecoration(
        color: Px.panel,
        border: Border.all(color: Px.ink, width: 2),
      ),
      child: Row(
        children: [
          for (var i = 0; i < segments; i++)
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: i < filled ? Px.accent : Px.panel,
                  border: Border(
                    right: i == segments - 1
                        ? BorderSide.none
                        : const BorderSide(color: Px.ink, width: 1),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Przycisk ← w nagłówku ekranu pobocznego.
class PixelBack extends StatelessWidget {
  const PixelBack({super.key, required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        label: 'Wstecz',
        child: GestureDetector(
          onTap: onPressed,
          child: Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: Px.panel,
              border: Border.all(color: Px.ink, width: 2),
            ),
            alignment: Alignment.center,
            child: Text('←', style: Px.text(26, weight: 500)),
          ),
        ),
      );
}

/// Kolumna ekranu 390 dp na środku z marginesami 16.
class ScreenFrame extends StatelessWidget {
  const ScreenFrame({super.key, required this.child, this.bottom});

  final Widget child;
  final Widget? bottom;

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: Px.bg,
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 430),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
                child: Column(
                  children: [
                    Expanded(child: child),
                    if (bottom != null) ...[const SizedBox(height: 16), bottom!],
                  ],
                ),
              ),
            ),
          ),
        ),
      );
}
