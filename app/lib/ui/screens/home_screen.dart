import 'package:flutter/material.dart';

import '../../core/session/training_protocol.dart';
import '../neuronek/neuronek.dart';
import '../theme/pixel_theme.dart';
import '../widgets/pk_widgets.dart';

class HomeData {
  const HomeData({
    required this.stageNo,
    required this.stageName,
    required this.stageProgress,
    required this.minutesToNext,
    required this.sourceLabel,
    required this.trainingMinutes,
    required this.channelsLabel,
    this.streakDays = 0,
    this.weekSessions = 0,
    this.weekGoal = 3,
  });

  final int stageNo;
  final String stageName;

  /// Postep do nastepnego etapu 0..1 (1 dla ostatniego).
  final double stageProgress;
  final double? minutesToNext;
  final String sourceLabel;
  final int trainingMinutes;
  final String channelsLabel;
  final int streakDays;
  final int weekSessions;
  final int weekGoal;
}

class HomeScreen extends StatelessWidget {
  const HomeScreen({
    super.key,
    required this.data,
    required this.selected,
    required this.onSelect,
    required this.onStart,
    required this.onProgress,
  });

  final HomeData data;
  final TrainingProtocol selected;
  final ValueChanged<TrainingProtocol> onSelect;
  final VoidCallback onStart;
  final VoidCallback onProgress;

  @override
  Widget build(BuildContext context) => ScreenFrame(
        footer: true,
        child: ListView(
          children: [
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(
                child: PkWindow(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      Expanded(child: Text('NEURONEK', style: Px.t(13, height: 1.5))),
                      Text(':L${data.stageNo}', style: Px.t(12, height: 1.5)),
                    ]),
                    const SizedBox(height: 4),
                    Text('etap: ${data.stageName}', style: Px.tiny),
                    const SizedBox(height: 6),
                    Row(children: [
                      SizedBox(width: 46, child: Text('ETAP', style: Px.t(8, height: 1))),
                      Expanded(child: PkBar(value: data.stageProgress, height: 12)),
                    ]),
                    const SizedBox(height: 6),
                    Row(children: [
                      SizedBox(width: 46, child: Text('TYDZ', style: Px.t(8, height: 1))),
                      Expanded(
                        child: PkBar(
                          value: data.weekGoal == 0 ? 0 : data.weekSessions / data.weekGoal,
                          height: 12,
                        ),
                      ),
                    ]),
                  ]),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 92,
                child: PkWindow(
                  padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
                  child: Column(children: [
                    Text('SERIA', style: Px.t(8, height: 1.3)),
                    Text('${data.streakDays}', style: Px.t(28, height: 1.3, shadow: true)),
                    Text('DNI', style: Px.t(8, height: 1.3)),
                  ]),
                ),
              ),
            ]),
            const SizedBox(height: 12),
            PkWindow(
              padding: EdgeInsets.zero,
              child: SizedBox(
                height: 210,
                child: ClipRect(
                  child: Stack(children: [
                    Positioned.fill(child: CustomPaint(painter: _RoomPainter())),
                    const Align(alignment: Alignment(0, 0.35), child: Neuronek(height: 140)),
                  ]),
                ),
              ),
            ),
            const SizedBox(height: 12),
            PkDialog(
              text: 'Dziś ${selected.title.toLowerCase()}, ${data.trainingMinutes} min. '
                  'Najpierw sprawdzę kontakt elektrod.',
            ),
            const SizedBox(height: 12),
            Text('WYBIERZ TRENING', style: Px.t(10)),
            const SizedBox(height: 8),
            PkMenu(rows: [
              for (final p in TrainingProtocol.all)
                PkMenuRow(
                  label: p.title.toUpperCase(),
                  sub: p.subtitle,
                  trailing: '${data.trainingMinutes} min',
                  selected: p == selected,
                  onTap: () => onSelect(p),
                ),
            ]),
            const SizedBox(height: 12),
            PkWindow(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(children: [
                Expanded(child: PkTile(label: 'TRENING', icon: boltIcon, onTap: onStart, selected: true)),
                Expanded(child: PkTile(label: 'POSTĘP', icon: barsIcon, onTap: onProgress)),
              ]),
            ),
            const SizedBox(height: 8),
          ],
        ),
      );
}

/// Ściana z podłogą w szachownicę.
class _RoomPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final wallH = size.height * 0.5;
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, wallH), Paint()..color = const Color(0xFFD7E3FB));
    canvas.drawRect(Rect.fromLTWH(0, wallH - 3, size.width, 3), Paint()..color = Px.ink);
    const tile = 24.0;
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
