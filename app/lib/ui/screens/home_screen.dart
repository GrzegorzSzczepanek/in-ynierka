import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/session/training_protocol.dart';
import '../neuronek/neuronek.dart';
import '../theme/pixel_theme.dart';
import '../widgets/pk_widgets.dart';

class HomeData {
  const HomeData({
    required this.stageNo,
    required this.stageName,
    required this.trainingMinutes,
    this.energy = 0,
    this.mood,
    this.focus,
    this.streakDays = 0,
    this.sourceLabel = '',
  });

  final int stageNo;
  final String stageName;
  final int trainingMinutes;

  /// Poprawne minuty z ostatnich 7 dni wzgledem celu tygodnia (0..1).
  final double energy;

  /// Srednia z ostatnich ocen samopoczucia (0..1) lub null, gdy brak ocen.
  final double? mood;

  /// Udzial czasu w celu w ostatniej sesji (0..1) lub null.
  final double? focus;
  final int streakDays;

  /// Aktywne zrodlo sygnalu (DEMO lub CZEPEK).
  final String sourceLabel;
}

/// Ekran główny. Na szerokim oknie (od 900 dp) neuronek ma wybieg,
/// a kafelki leżą luźno na dolnym pasku.
class HomeScreen extends StatelessWidget {
  const HomeScreen({
    super.key,
    required this.data,
    required this.selected,
    required this.onSelect,
    required this.onStart,
    required this.onProgress,
    this.onConnection,
    this.onCalibration,
    this.onResearch,
    this.onSettings,
    this.animated = true,
  });

  final HomeData data;
  final TrainingProtocol selected;
  final ValueChanged<TrainingProtocol> onSelect;
  final VoidCallback onStart;
  final VoidCallback onProgress;
  final VoidCallback? onConnection;
  final VoidCallback? onCalibration;
  final VoidCallback? onResearch;
  final VoidCallback? onSettings;
  final bool animated;

  static const desktopWidth = 900.0;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, c) =>
            c.maxWidth >= desktopWidth ? _desktop(context) : _mobile(context),
      );

  Widget _hud({bool wide = false}) => PkWindow(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: Text('NEURONEK', style: Px.t(13, height: 1.5))),
            Text(':L${data.stageNo}', style: Px.t(12, height: 1.5)),
          ]),
          const SizedBox(height: 2),
          Text('etap: ${data.stageName}${data.sourceLabel.isEmpty ? '' : ' · ${data.sourceLabel}'}', style: Px.tiny),
          const SizedBox(height: 6),
          _stat('ENERG', data.energy),
          const SizedBox(height: 6),
          _stat('NASTR', data.mood ?? 0, unknown: data.mood == null),
          const SizedBox(height: 6),
          _stat('FOKUS', data.focus ?? 0, unknown: data.focus == null),
        ]),
      );

  Widget _stat(String label, double v, {bool unknown = false}) => Row(children: [
        SizedBox(width: 52, child: Text(label, style: Px.t(8, height: 1))),
        Expanded(child: PkBar(value: v, height: 12)),
        if (unknown) Padding(padding: const EdgeInsets.only(left: 6), child: Text('--', style: Px.tiny)),
      ]);

  Widget _streak() => SizedBox(
        width: 92,
        child: PkWindow(
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
          child: Column(children: [
            Text('SERIA', style: Px.t(8, height: 1.3)),
            Text('${data.streakDays}', style: Px.t(28, height: 1.3, shadow: true)),
            Text('DNI', style: Px.t(8, height: 1.3)),
          ]),
        ),
      );

  Widget _menu() => PkMenu(rows: [
        for (final p in TrainingProtocol.all)
          PkMenuRow(
            label: p.title.toUpperCase(),
            sub: p.subtitle,
            trailing: '${data.trainingMinutes} min',
            selected: p == selected,
            onTap: () => onSelect(p),
          ),
      ]);

  String get _dialog => 'Dziś ${selected.title.toLowerCase()}, ${data.trainingMinutes} min. '
      'Najpierw sprawdzę kontakt elektrod.';

  List<Widget> _tiles({bool big = false}) => [
        PkTile(label: 'TRENING', icon: boltIcon, onTap: onStart, selected: true, big: big),
        if (onConnection != null)
          PkTile(label: 'POŁĄCZENIE', icon: plugIcon, onTap: onConnection!, big: big),
        if (onCalibration != null)
          PkTile(label: 'KALIBRACJA', icon: eyeIcon, onTap: onCalibration!, big: big),
        PkTile(label: 'POSTĘP', icon: barsIcon, onTap: onProgress, big: big),
        if (onResearch != null)
          PkTile(label: 'BADACZ', icon: monitorIcon, onTap: onResearch!, big: big),
        if (onSettings != null)
          PkTile(label: 'USTAWIENIA', icon: gearIcon, onTap: onSettings!, big: big),
      ];

  Widget _mobile(BuildContext context) {
    final tiles = _tiles();
    return ScreenFrame(
      footer: true,
      child: ListView(
        children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(child: _hud()),
            const SizedBox(width: 8),
            _streak(),
          ]),
          const SizedBox(height: 12),
          PkWindow(
            padding: EdgeInsets.zero,
            child: SizedBox(
              height: 150,
              child: ClipRect(
                child: Stack(children: [
                  Positioned.fill(child: CustomPaint(painter: _RoomPainter())),
                  const Align(alignment: Alignment(0, 0.45), child: Neuronek(height: 100)),
                ]),
              ),
            ),
          ),
          const SizedBox(height: 10),
          PkDialog(text: _dialog),
          const SizedBox(height: 10),
          Text('WYBIERZ TRENING', style: Px.t(10)),
          const SizedBox(height: 6),
          _menu(),
          const SizedBox(height: 10),
          PkWindow(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Column(children: [
              for (var i = 0; i < tiles.length; i += 3)
                Row(children: [
                  for (var j = i; j < i + 3; j++)
                    Expanded(child: j < tiles.length ? tiles[j] : const SizedBox(height: 76)),
                ]),
            ]),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  Widget _desktop(BuildContext context) => Scaffold(
        backgroundColor: Px.bg,
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(children: [
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                SizedBox(width: 340, child: _hud(wide: true)),
                const SizedBox(width: 12),
                _streak(),
                const Spacer(),
                SizedBox(
                  width: 330,
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('WYBIERZ TRENING', style: Px.t(10)),
                    const SizedBox(height: 8),
                    _menu(),
                  ]),
                ),
              ]),
              const SizedBox(height: 16),
              Expanded(
                child: PkWindow(
                  padding: EdgeInsets.zero,
                  child: ClipRect(
                    child: Stack(children: [
                      Positioned.fill(child: CustomPaint(painter: _RoomPainter())),
                      Positioned.fill(child: _Wanderer(animated: animated)),
                      Positioned(
                        left: 20,
                        bottom: 20,
                        width: 430,
                        child: PkDialog(text: _dialog),
                      ),
                    ]),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              PkWindow(
                padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
                child: Row(children: [
                  for (final t in _tiles(big: true)) Expanded(child: t),
                ]),
              ),
              const SizedBox(height: 10),
              Align(
                alignment: Alignment.centerLeft,
                child: Text('Prototyp edukacyjny. To nie jest terapia ani diagnoza.', style: Px.tiny),
              ),
            ]),
          ),
        ),
      );
}

/// Neuronek spaceruje po wybiegu: powoli w prawo i w lewo, kiwa się, czasem się nudzi.
class _Wanderer extends StatefulWidget {
  const _Wanderer({required this.animated});

  final bool animated;

  @override
  State<_Wanderer> createState() => _WandererState();
}

class _WandererState extends State<_Wanderer> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 16),
  );

  @override
  void initState() {
    super.initState();
    if (widget.animated) _c.repeat(reverse: true);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, box) {
          final h = math.min(box.maxHeight * 0.55, 260.0);
          return AnimatedBuilder(
            animation: _c,
            builder: (context, _) {
              final t = Curves.easeInOut.transform(_c.value);
              final span = box.maxWidth - h * 0.9 - 80;
              final x = 40 + span * (widget.animated ? t : 0.5);
              final bob = widget.animated ? math.sin(_c.value * math.pi * 2 * 18).abs() * 6 : 0.0;
              final goingLeft = _c.status == AnimationStatus.reverse;
              final resting = widget.animated && (_c.value < 0.04 || _c.value > 0.96);
              return Stack(children: [
                Positioned(
                  left: x,
                  bottom: box.maxHeight * 0.14 + bob,
                  child: Transform.flip(
                    flipX: goingLeft,
                    child: Neuronek(mood: resting ? Mood.sleepy : Mood.happy, height: h),
                  ),
                ),
              ]);
            },
          );
        },
      );
}

/// Ściana z podłogą w szachownicę.
class _RoomPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final wallH = size.height * 0.5;
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, wallH), Paint()..color = const Color(0xFFD7E3FB));
    canvas.drawRect(Rect.fromLTWH(0, wallH - 3, size.width, 3), Paint()..color = Px.ink);
    const tile = 28.0;
    for (var y = wallH; y < size.height; y += tile) {
      for (var x = 0.0; x < size.width; x += tile) {
        final dark = (((x / tile).floor() + ((y - wallH) / tile).floor()) % 2) == 0;
        canvas.drawRect(Rect.fromLTWH(x, y, tile, tile),
            Paint()..color = dark ? const Color(0xFFDCE6FA) : const Color(0xFFEEF3FD));
      }
    }
  }

  @override
  bool shouldRepaint(_RoomPainter old) => false;
}
