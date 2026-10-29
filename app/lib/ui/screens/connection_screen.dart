import 'package:flutter/material.dart';

import '../../core/session/session_models.dart';
import '../neuronek/neuronek.dart';
import '../theme/pixel_theme.dart';

/// Laczenie, kontrola kontaktu, ponowne laczenie i utrata polaczenia.
class ConnectionScreen extends StatelessWidget {
  const ConnectionScreen({
    super.key,
    required this.snapshot,
    required this.trainingChannels,
    required this.maxAttempts,
    required this.onFinish,
    this.onRetry,
  });

  final SessionSnapshot snapshot;
  final List<String> trainingChannels;
  final int maxAttempts;
  final VoidCallback onFinish;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final phase = snapshot.phase;
    final channels = snapshot.contact;
    final withContact = channels?.where((c) => c.contact).length;
    final missing = [
      for (final n in trainingChannels)
        if (channels != null && !(channels.where((c) => c.name == n).firstOrNull?.contact ?? false)) n,
    ];

    final (headline, body, mood) = switch (phase) {
      SessionPhase.connecting => (
          'Łączenie z czepkiem',
          'Włącz czepek i trzymaj go blisko. Próba ${snapshot.attempt} z $maxAttempts.',
          Mood.sleepy,
        ),
      SessionPhase.reconnecting => (
          'Ponowne łączenie',
          'Połączenie zostało utracone. Próba ${snapshot.attempt} z $maxAttempts, '
              'potem zaczniemy od kalibracji.',
          Mood.worried,
        ),
      SessionPhase.connectionLost => (
          'Połączenie utracone',
          'Nie udało się połączyć. Sprawdź baterię i zasięg czepka.',
          Mood.worried,
        ),
      SessionPhase.deviceSelection => (
          'Nie znaleziono czepka',
          'Włącz czepek, sprawdź baterię i spróbuj jeszcze raz.',
          Mood.confused,
        ),
      _ => missing.isEmpty && channels != null
          ? ('Kontakt w normie', 'Za chwilę kalibracja. Siedź spokojnie.', Mood.happy)
          : (
              'Sprawdzam kontakt',
              missing.isEmpty
                  ? 'Czekam na odczyt kontaktu elektrod.'
                  : '${missing.join(', ')}: brak kontaktu. Rozsuń włosy pod elektrodą i dociśnij czepek.',
              Mood.focused,
            ),
    };

    final lost = phase == SessionPhase.connectionLost || phase == SessionPhase.deviceSelection;
    return ScreenFrame(
      bottom: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (lost && onRetry != null) PixelButton(label: 'Spróbuj ponownie', onPressed: onRetry),
          if (lost && onRetry != null) const SizedBox(height: 8),
          PixelButton(label: lost ? 'Wróć' : 'Zakończ', primary: false, onPressed: onFinish),
        ],
      ),
      child: ListView(
        children: [
          Text('Połączenie', style: Px.h1),
          const SizedBox(height: 16),
          if (withContact != null) ...[
            Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text('$withContact', style: Px.hero),
              const SizedBox(width: 8),
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text('/${channels!.length}', style: Px.text(28, color: Px.ink2)),
              ),
              const Spacer(),
              Neuronek(mood: mood, height: 60, shadow: false),
            ]),
            Text('kanałów z kontaktem', style: Px.secondary),
            const SizedBox(height: 16),
            _ChannelGrid(channels: channels, training: trainingChannels),
          ] else
            Center(child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Neuronek(mood: mood, height: 150),
            )),
          const SizedBox(height: 16),
          PixelCard(
            color: lost ? Px.warnBg : Px.panel,
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(headline, style: Px.text(18, weight: 500)),
              const SizedBox(height: 6),
              Text(body, style: Px.body),
            ]),
          ),
        ],
      ),
    );
  }
}

class _ChannelGrid extends StatelessWidget {
  const _ChannelGrid({required this.channels, required this.training});

  final List<ChannelContact> channels;
  final List<String> training;

  @override
  Widget build(BuildContext context) => Wrap(
        spacing: 6,
        runSpacing: 6,
        children: [
          for (final c in channels)
            Container(
              width: 40,
              height: 32,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: c.contact ? Px.accent : Px.panel,
                border: Border.all(
                  color: training.contains(c.name) ? Px.ink : Px.soft,
                  width: training.contains(c.name) ? 3 : 2,
                ),
              ),
              child: Text(
                c.name.replaceFirst('ch', ''),
                style: Px.text(12, weight: 500, color: c.contact ? Colors.white : Px.ink2),
              ),
            ),
        ],
      );
}
