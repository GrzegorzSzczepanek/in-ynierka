import 'package:flutter/material.dart';

import '../neuronek/neuronek.dart';
import '../theme/pixel_theme.dart';

/// Okno ze sprite'em neuronka na jasnym tle.
class SpriteWindow extends StatelessWidget {
  const SpriteWindow({super.key, required this.mood, this.height = 150, this.top});

  final Mood mood;
  final double height;

  /// Dodatek nad sprite'em (np. pasek stanu).
  final Widget? top;

  @override
  Widget build(BuildContext context) => PkWindow(
        padding: EdgeInsets.zero,
        child: Container(
          color: const Color(0xFFDCE6FA),
          padding: const EdgeInsets.symmetric(vertical: 14),
          child: Column(children: [
            ?top,
            Neuronek(mood: mood, height: height),
          ]),
        ),
      );
}

/// Bitmapowa ikonka z wzoru znaków ('#' = piksel).
class PkIcon extends StatelessWidget {
  const PkIcon(this.pattern, {super.key, this.unit = 4, this.color = Px.ink});

  final List<String> pattern;
  final double unit;
  final Color color;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: pattern.first.length * unit,
        height: pattern.length * unit,
        child: CustomPaint(painter: _IconPainter(pattern, unit, color)),
      );
}

class _IconPainter extends CustomPainter {
  _IconPainter(this.pattern, this.unit, this.color);

  final List<String> pattern;
  final double unit;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()..color = color..isAntiAlias = false;
    for (var y = 0; y < pattern.length; y++) {
      for (var x = 0; x < pattern[y].length; x++) {
        if (pattern[y][x] == '#') {
          canvas.drawRect(Rect.fromLTWH(x * unit, y * unit, unit, unit), p);
        }
      }
    }
  }

  @override
  bool shouldRepaint(_IconPainter old) => old.pattern != pattern || old.color != color;
}

const boltIcon = [
  '....##..',
  '...###..',
  '..###...',
  '.######.',
  '...###..',
  '..##....',
  '.##.....',
];

const barsIcon = [
  '......##',
  '......##',
  '...##.##',
  '...##.##',
  '##.##.##',
  '##.##.##',
  '########',
];

const eyeIcon = [
  '..####..',
  '.#....#.',
  '#..##..#',
  '#.####.#',
  '#..##..#',
  '.#....#.',
  '..####..',
];

const gearIcon = [
  '..#..#..',
  '.######.',
  '###..###',
  '#......#',
  '###..###',
  '.######.',
  '..#..#..',
];

const monitorIcon = [
  '########',
  '#......#',
  '#.#..#.#',
  '#..##..#',
  '#......#',
  '########',
  '..####..',
];

const plugIcon = [
  '.#.#.#.#',
  '.#.#.#.#',
  '########',
  '########',
  '.######.',
  '..####..',
  '...##...',
];

class PkTile extends StatelessWidget {
  const PkTile({
    super.key,
    required this.label,
    required this.icon,
    required this.onTap,
    this.selected = false,
    this.big = false,
  });

  final String label;
  final List<String> icon;
  final VoidCallback onTap;
  final bool selected;
  final bool big;

  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        label: label,
        child: GestureDetector(
          onTap: onTap,
          behavior: HitTestBehavior.opaque,
          child: Container(
            height: big ? 112 : 76,
            color: selected ? Px.accentLight : null,
            child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              PkIcon(icon, color: Px.accent, unit: big ? 6 : 4),
              SizedBox(height: big ? 12 : 8),
              Text(label, style: Px.t(big ? 10 : 8, height: 1)),
            ]),
          ),
        ),
      );
}

/// Wykres słupkowy lub liniowy wartości 0..1 z kreskowanym progiem.
class PkChart extends StatelessWidget {
  const PkChart({super.key, required this.values, this.threshold, this.bars = false, this.height = 70});

  final List<double> values;
  final double? threshold;
  final bool bars;
  final double height;

  @override
  Widget build(BuildContext context) => SizedBox(
        height: height,
        width: double.infinity,
        child: CustomPaint(painter: _ChartPainter(values, threshold, bars)),
      );
}

class _ChartPainter extends CustomPainter {
  _ChartPainter(this.values, this.threshold, this.bars);

  final List<double> values;
  final double? threshold;
  final bool bars;

  @override
  void paint(Canvas canvas, Size size) {
    if (values.isEmpty) return;
    final n = values.length;
    double y(double v) => size.height - 2 - v.clamp(0.0, 1.0) * (size.height - 6);
    if (bars) {
      final w = size.width / n;
      for (var i = 0; i < n; i++) {
        final over = threshold != null && values[i] > threshold!;
        canvas.drawRect(
          Rect.fromLTRB(i * w + 1, y(values[i]), (i + 1) * w - 1, size.height - 2),
          Paint()..color = over ? Px.accent : Px.soft..isAntiAlias = false,
        );
      }
    } else {
      final path = Path();
      for (var i = 0; i < n; i++) {
        final x = n == 1 ? 0.0 : size.width * i / (n - 1);
        if (i == 0) {
          path.moveTo(x, y(values[i]));
        } else {
          path.lineTo(x, y(values[i]));
        }
      }
      canvas.drawPath(
          path,
          Paint()
            ..color = Px.accent
            ..style = PaintingStyle.stroke
            ..strokeWidth = 3
            ..isAntiAlias = false);
    }
    canvas.drawRect(Rect.fromLTWH(0, size.height - 2, size.width, 2), Paint()..color = Px.ink);
    if (threshold != null) {
      final ty = y(threshold!);
      for (var x = 0.0; x < size.width; x += 8) {
        canvas.drawRect(Rect.fromLTWH(x, ty, 4, 2), Paint()..color = Px.ink);
      }
    }
  }

  @override
  bool shouldRepaint(_ChartPainter old) =>
      old.values != values || old.threshold != threshold || old.bars != bars;
}

/// Wybór oceny 1..5 w oknie, zaznaczona wartość podświetlona z kursorem.
class PkRating extends StatelessWidget {
  const PkRating({super.key, required this.value, required this.onChanged, this.label});

  final int? value;
  final ValueChanged<int> onChanged;
  final String? label;

  @override
  Widget build(BuildContext context) => PkWindow(
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 6),
        child: Row(children: [
          for (var i = 1; i <= 5; i++)
            Expanded(
              child: Semantics(
                button: true,
                selected: value == i,
                label: '${label ?? 'Ocena'} $i',
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => onChanged(i),
                  child: Container(
                    height: 44,
                    color: value == i ? Px.accentLight : null,
                    alignment: Alignment.center,
                    child: Text('$i', style: Px.t(14, height: 1)),
                  ),
                ),
              ),
            ),
        ]),
      );
}
