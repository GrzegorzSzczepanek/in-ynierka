import 'package:flutter/material.dart';

import '../neuronek/neuronek.dart';
import '../theme/pixel_theme.dart';

class HomeData {
  const HomeData({
    required this.stageNo,
    required this.stageName,
    required this.stageProgress,
    required this.minutesToNext,
    required this.sourceLabel,
    required this.trainingMinutes,
    required this.channelsLabel,
  });

  final int stageNo;
  final String stageName;

  /// Postep do nastepnego etapu 0..1 (1 dla ostatniego).
  final double stageProgress;
  final double? minutesToNext;
  final String sourceLabel;
  final int trainingMinutes;
  final String channelsLabel;
}

class HomeScreen extends StatelessWidget {
  const HomeScreen({
    super.key,
    required this.data,
    required this.onStart,
    required this.onProgress,
  });

  final HomeData data;
  final VoidCallback onStart;
  final VoidCallback onProgress;

  @override
  Widget build(BuildContext context) => ScreenFrame(
        bottom: PixelButton(label: 'Rozpocznij trening', onPressed: onStart),
        child: ListView(
          children: [
            Row(
              children: [
                Expanded(child: Text('NEUROtchi', style: Px.h1)),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: Px.panel,
                    border: Border.all(color: Px.ink, width: 2),
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Container(width: 10, height: 10, color: Px.accent),
                    const SizedBox(width: 8),
                    Text(data.channelsLabel, style: Px.text(14, weight: 500)),
                  ]),
                ),
              ],
            ),
            const SizedBox(height: 16),
            PixelCard(
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 16),
              child: Column(children: [
                const Neuronek(height: 150),
                const SizedBox(height: 16),
                Text(
                  'Dziś trening alfa, około ${data.trainingMinutes} minut. '
                  'Najpierw sprawdzę, czy elektrody mają kontakt.',
                  textAlign: TextAlign.center,
                  style: Px.secondary.copyWith(color: Px.ink),
                ),
              ]),
            ),
            const SizedBox(height: 24),
            Text('Trening', style: Px.h2),
            const SizedBox(height: 12),
            PixelCard(
              selected: true,
              child: Row(children: [
                Container(width: 18, height: 18, color: Px.accent),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('Trening alfa', style: Px.text(22)),
                    Text('alfa 8–12 Hz, O1 O2', style: Px.caption),
                  ]),
                ),
                Text('${data.trainingMinutes} min', style: Px.text(18)),
              ]),
            ),
            const SizedBox(height: 24),
            Row(children: [
              Expanded(
                child: Text('Etap ${data.stageNo}: ${data.stageName}', style: Px.text(18)),
              ),
              if (data.minutesToNext != null)
                Text('jeszcze ${data.minutesToNext!.ceil()} min', style: Px.caption),
            ]),
            const SizedBox(height: 8),
            PixelBar(value: data.stageProgress),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerLeft,
              child: GestureDetector(
                onTap: onProgress,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Text('Postęp i historia',
                      style: Px.text(16, weight: 500, color: Px.accent)
                          .copyWith(decoration: TextDecoration.underline)),
                ),
              ),
            ),
          ],
        ),
      );
}
