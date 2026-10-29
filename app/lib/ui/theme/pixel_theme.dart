import 'package:flutter/material.dart';

/// Styl PK z makiet (design/): Press Start 2P, podwójne ramki z twardym cieniem,
/// menu z kursorem, okienka dialogowe.
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

  static const _family = 'PressStart2P';

  static TextStyle t(double size, {Color color = ink, double height = 1.6, bool shadow = false}) =>
      TextStyle(
        fontFamily: _family,
        fontSize: size,
        color: color,
        height: height,
        shadows: shadow ? const [Shadow(color: soft, offset: Offset(2, 2))] : null,
      );

  static TextStyle get hero => t(64, height: 1.1, shadow: true);
  static TextStyle get display => t(40, height: 1.1, shadow: true);
  static TextStyle get title => t(22, height: 1.3, shadow: true);
  static TextStyle get h2 => t(14, height: 1.4);
  static TextStyle get body => t(11, height: 1.7);
  static TextStyle get small => t(9, color: ink2, height: 1.7);
  static TextStyle get tiny => t(8, color: ink2, height: 1.7);

  static ThemeData get theme => ThemeData(
        useMaterial3: true,
        scaffoldBackgroundColor: bg,
        fontFamily: _family,
        colorScheme: ColorScheme.fromSeed(seedColor: accent, surface: bg),
        textTheme: TextTheme(bodyMedium: body),
      );
}

/// Okno: gruba ramka, cienka ramka w środku, twardy cień.
class PkWindow extends StatelessWidget {
  const PkWindow({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(12),
    this.color = Px.panel,
    this.shadow = true,
  });

  final Widget child;
  final EdgeInsets padding;
  final Color color;
  final bool shadow;

  @override
  Widget build(BuildContext context) => Container(
        margin: shadow ? const EdgeInsets.only(right: 4, bottom: 4) : null,
        decoration: BoxDecoration(
          color: color,
          border: Border.all(color: Px.ink, width: 3),
          boxShadow: shadow ? const [BoxShadow(color: Px.soft, offset: Offset(4, 4))] : null,
        ),
        padding: const EdgeInsets.all(3),
        child: Container(
          decoration: BoxDecoration(border: Border.all(color: Px.ink, width: 1.5)),
          padding: padding,
          child: child,
        ),
      );
}

/// Trójkątny kursor menu.
class PkCursor extends StatelessWidget {
  const PkCursor({super.key, this.size = 14});

  final double size;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: size * 0.7,
        height: size,
        child: CustomPaint(painter: _CursorPainter()),
      );
}

class _CursorPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..moveTo(0, 0)
      ..lineTo(size.width, size.height / 2)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(path, Paint()..color = Px.ink..isAntiAlias = false);
  }

  @override
  bool shouldRepaint(_CursorPainter old) => false;
}

class PkMenuRow extends StatelessWidget {
  const PkMenuRow({
    super.key,
    required this.label,
    this.selected = false,
    this.onTap,
    this.trailing,
    this.sub,
  });

  final String label;
  final String? sub;
  final bool selected;
  final VoidCallback? onTap;
  final String? trailing;

  @override
  Widget build(BuildContext context) => Semantics(
        button: onTap != null,
        selected: selected,
        label: label,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: Container(
            constraints: const BoxConstraints(minHeight: 44),
            color: selected ? Px.accentLight : null,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            child: Row(children: [
              SizedBox(width: 18, child: selected ? const PkCursor() : null),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(label, style: Px.t(12)),
                  if (sub != null) Text(sub!, style: Px.tiny),
                ]),
              ),
              if (trailing != null) Text(trailing!, style: Px.tiny),
            ]),
          ),
        ),
      );
}

/// Okno z wierszami menu.
class PkMenu extends StatelessWidget {
  const PkMenu({super.key, required this.rows});

  final List<PkMenuRow> rows;

  @override
  Widget build(BuildContext context) => PkWindow(
        padding: const EdgeInsets.all(6),
        child: Column(children: rows),
      );
}

/// Pojedyncza akcja jako okno z zaznaczonym wierszem.
class PkAction extends StatelessWidget {
  const PkAction({super.key, required this.label, required this.onTap, this.primary = true});

  final String label;
  final VoidCallback? onTap;
  final bool primary;

  @override
  Widget build(BuildContext context) => Opacity(
        opacity: onTap == null ? 0.45 : 1,
        child: PkMenu(rows: [PkMenuRow(label: label, selected: primary, onTap: onTap)]),
      );
}

class PkDialog extends StatelessWidget {
  const PkDialog({super.key, required this.text, this.color = Px.panel, this.more = true});

  final String text;
  final Color color;
  final bool more;

  @override
  Widget build(BuildContext context) => PkWindow(
        color: color,
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(text, style: Px.t(11, height: 1.8)),
          if (more)
            const Align(
              alignment: Alignment.centerRight,
              child: _DownMark(),
            ),
        ]),
      );
}

class _DownMark extends StatelessWidget {
  const _DownMark();

  @override
  Widget build(BuildContext context) => SizedBox(
        width: 12,
        height: 8,
        child: CustomPaint(painter: _DownPainter()),
      );
}

class _DownPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..moveTo(0, 0)
      ..lineTo(size.width, 0)
      ..lineTo(size.width / 2, size.height)
      ..close();
    canvas.drawPath(path, Paint()..color = Px.ink..isAntiAlias = false);
  }

  @override
  bool shouldRepaint(_DownPainter old) => false;
}

/// Pasek wartości z ramką, opcjonalnym znacznikiem progu.
class PkBar extends StatelessWidget {
  const PkBar({super.key, required this.value, this.height = 16, this.marker, this.color = Px.accent});

  final double value;
  final double height;
  final double? marker;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
        height: height,
        decoration: BoxDecoration(
          color: Px.panel,
          border: Border.all(color: Px.ink, width: 2),
        ),
        child: LayoutBuilder(
          builder: (context, c) => Stack(children: [
            Container(width: c.maxWidth * value.clamp(0.0, 1.0), color: color),
            if (marker != null)
              Positioned(
                left: c.maxWidth * marker!.clamp(0.0, 1.0) - 1,
                top: -2,
                bottom: -2,
                child: Container(width: 3, color: Px.ink),
              ),
          ]),
        ),
      );
}

/// Pasek segmentowy, np. postęp odliczania.
class PkSegBar extends StatelessWidget {
  const PkSegBar({super.key, required this.value, this.segments = 20, this.height = 18});

  final double value;
  final int segments;
  final double height;

  @override
  Widget build(BuildContext context) {
    final filled = (value.clamp(0.0, 1.0) * segments).floor();
    return Container(
      height: height,
      decoration: BoxDecoration(color: Px.panel, border: Border.all(color: Px.ink, width: 2)),
      child: Row(children: [
        for (var i = 0; i < segments; i++)
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: i < filled ? Px.accent : Px.panel,
                border: i == segments - 1
                    ? null
                    : const Border(right: BorderSide(color: Px.soft, width: 1)),
              ),
            ),
          ),
      ]),
    );
  }
}

/// Wiersz z kropkowaną linią: etykieta ........ wartość.
class PkLeader extends StatelessWidget {
  const PkLeader(this.label, this.value, {super.key, this.bold = false});

  final String label;
  final String value;
  final bool bold;

  @override
  Widget build(BuildContext context) {
    final style = Px.t(9, color: bold ? Px.ink : Px.ink2, height: 1.9);
    return Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
      Text(label, style: style),
      const SizedBox(width: 4),
      const Expanded(child: _Dots()),
      const SizedBox(width: 4),
      Text(value, style: style.copyWith(color: Px.ink)),
    ]);
  }
}

class _Dots extends StatelessWidget {
  const _Dots();

  @override
  Widget build(BuildContext context) => SizedBox(height: 14, child: CustomPaint(painter: _DotsPainter()));
}

class _DotsPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()..color = Px.ink2..isAntiAlias = false;
    for (var x = 0.0; x < size.width; x += 4) {
      canvas.drawRect(Rect.fromLTWH(x, size.height - 4, 2, 2), p);
    }
  }

  @override
  bool shouldRepaint(_DotsPainter old) => false;
}

/// Przycisk ← w nagłówku ekranu pobocznego.
class PkBack extends StatelessWidget {
  const PkBack({super.key, required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        label: 'Wstecz',
        child: GestureDetector(
          onTap: onPressed,
          child: PkWindow(
            padding: EdgeInsets.zero,
            shadow: false,
            child: SizedBox(
              width: 34,
              height: 34,
              child: Center(child: Text('←', style: Px.t(18, height: 1))),
            ),
          ),
        ),
      );
}

/// Kolumna ekranu z marginesami, stopka z dopiskiem o prototypie.
class ScreenFrame extends StatelessWidget {
  const ScreenFrame({super.key, required this.child, this.bottom, this.footer = false});

  final Widget child;
  final Widget? bottom;
  final bool footer;

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
                    if (bottom != null) ...[const SizedBox(height: 12), bottom!],
                    if (footer) ...[
                      const SizedBox(height: 10),
                      Text('Prototyp edukacyjny. To nie jest terapia ani diagnoza.',
                          style: Px.tiny),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      );
}
