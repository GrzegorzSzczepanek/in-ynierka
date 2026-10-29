import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/pixel_theme.dart';

/// Mimiki neuronka v2 (assets/neuronek/mimiki.json, siatka znakow).
enum Mood {
  happy('szczęśliwy'),
  focused('skupiony'),
  confused('zdezorientowany'),
  sleepy('śpiący'),
  delighted('zachwycony'),
  worried('zmartwiony');

  const Mood(this.key);

  final String key;
}

class NeuronekSprites {
  NeuronekSprites._(this._rows);

  final Map<String, List<String>> _rows;

  static NeuronekSprites? _instance;

  static NeuronekSprites get instance =>
      _instance ?? (throw StateError('NeuronekSprites.load() nie zostalo wywolane'));

  static Future<NeuronekSprites> load([AssetBundle? bundle]) async {
    final existing = _instance;
    if (existing != null) return existing;
    final raw = await (bundle ?? rootBundle).loadString('assets/neuronek/mimiki.json');
    final json = jsonDecode(raw) as Map<String, dynamic>;
    return _instance = NeuronekSprites._({
      for (final e in json.entries) e.key: [for (final r in e.value as List) r as String],
    });
  }

  List<String> rows(Mood m) => _rows[m.key]!;
}

const _palette = {
  'o': Color(0xFF000000),
  'b': Color(0xFF2CE8F4),
  'd': Color(0xFF0099DC),
  'l': Color(0xFFC0CCDC),
  'a': Color(0xFFFEE861),
  'k': Color(0xFF1B1830),
  'w': Color(0xFFFFFFFF),
};

/// Neuronek rysowany z siatki pikseli, bez rozmycia.
class Neuronek extends StatelessWidget {
  const Neuronek({super.key, this.mood = Mood.happy, this.height = 120, this.shadow = true});

  final Mood mood;
  final double height;
  final bool shadow;

  @override
  Widget build(BuildContext context) {
    final rows = NeuronekSprites.instance.rows(mood);
    final cols = rows.map((r) => r.length).reduce((a, b) => a > b ? a : b);
    final unit = height / rows.length;
    return Semantics(
      label: 'Neuronek, nastrój ${mood.key}',
      child: SizedBox(
        width: unit * cols,
        height: height,
        child: CustomPaint(painter: _SpritePainter(rows, unit, shadow)),
      ),
    );
  }
}

class _SpritePainter extends CustomPainter {
  _SpritePainter(this.rows, this.unit, this.shadow);

  final List<String> rows;
  final double unit;
  final bool shadow;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..isAntiAlias = false;
    if (shadow) {
      paint.color = Px.soft;
      canvas.drawRect(
          Rect.fromLTWH(size.width * 0.2, size.height - unit * 2, size.width * 0.6, unit * 2),
          paint);
    }
    for (var y = 0; y < rows.length; y++) {
      final row = rows[y];
      var x = 0;
      while (x < row.length) {
        final c = row[x];
        var end = x + 1;
        while (end < row.length && row[end] == c) {
          end++;
        }
        final color = _palette[c];
        if (color != null) {
          paint.color = color;
          canvas.drawRect(
              Rect.fromLTWH(x * unit, y * unit, (end - x) * unit + 0.5, unit + 0.5), paint);
        }
        x = end;
      }
    }
  }

  @override
  bool shouldRepaint(_SpritePainter old) =>
      old.rows != rows || old.unit != unit || old.shadow != shadow;
}
