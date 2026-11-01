import 'package:flutter/material.dart';

import '../../core/session/session_models.dart';
import '../neuronek/neuronek.dart';
import '../theme/pixel_theme.dart';
import '../widgets/head_map.dart';

/// Laczenie, kontrola kontaktu, ponowne laczenie i utrata polaczenia.
class ConnectionScreen extends StatelessWidget {
  const ConnectionScreen({
    super.key,
    required this.snapshot,
    required this.trainingChannels,
    required this.maxAttempts,
    required this.onFinish,
    this.onRetry,
    this.onUseContactChannels,
  });

  final SessionSnapshot snapshot;
  final List<String> trainingChannels;
  final int maxAttempts;
  final VoidCallback onFinish;
  final VoidCallback? onRetry;

  /// Przelacza trening na kanaly, ktore teraz maja kontakt.
  final VoidCallback? onUseContactChannels;

  @override
  Widget build(BuildContext context) {
    final phase = snapshot.phase;
    final channels = snapshot.contact;
    final withContact = channels?.where((c) => c.contact).length;
    final missing = [
      for (final n in trainingChannels)
        if (channels != null &&
            !(channels.where((c) => c.name == n).firstOrNull?.contact ?? false))
          n,
    ];

    final (headline, body, mood) = switch (phase) {
      SessionPhase.connecting => (
        'ŁĄCZENIE',
        'Włącz czepek i trzymaj go blisko. Próba ${snapshot.attempt} z $maxAttempts.',
        Mood.sleepy,
      ),
      SessionPhase.reconnecting => (
        'PONOWNE ŁĄCZENIE',
        'Połączenie utracone. Próba ${snapshot.attempt} z $maxAttempts, potem kalibracja od nowa.',
        Mood.worried,
      ),
      SessionPhase.connectionLost => (
        'POŁĄCZENIE UTRACONE',
        'Nie udało się połączyć. Sprawdź baterię i zasięg czepka.',
        Mood.worried,
      ),
      SessionPhase.deviceSelection => (
        'NIE ZNALEZIONO CZEPKA',
        'Włącz czepek, sprawdź baterię i spróbuj jeszcze raz.',
        Mood.confused,
      ),
      _ =>
        missing.isEmpty && channels != null
            ? (
                'KONTAKT W NORMIE',
                'Za chwilę kalibracja. Siedź spokojnie.',
                Mood.happy,
              )
            : (
                'SPRAWDZAM KONTAKT',
                missing.isEmpty
                    ? 'Czekam na odczyt kontaktu elektrod.'
                    : '${missing.join(', ')}: kontakt za słaby. Rozsuń włosy pod elektrodą i dociśnij czepek albo użyj kanałów, które kontakt mają.',
                Mood.focused,
              ),
    };

    final lost =
        phase == SessionPhase.connectionLost ||
        phase == SessionPhase.deviceSelection;
    final canSwitch =
        onUseContactChannels != null &&
        (phase == SessionPhase.contactCheck) &&
        missing.isNotEmpty &&
        (withContact ?? 0) > 0;
    // Układ desktopowy (mapa głowy obok statusu) napisany z pomocą AI (Claude).
    final wide = isWideLayout(context);
    final header = Row(
      children: [
        PkBack(onPressed: onFinish),
        const SizedBox(width: 12),
        Text(
          'POŁĄCZENIE',
          style: Px.t(wide ? 24 : 20, height: 1.3, shadow: true),
        ),
      ],
    );
    final counter = withContact == null
        ? null
        : Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text('$withContact', style: Px.hero),
                  const SizedBox(width: 6),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(
                      '/${channels!.length}',
                      style: Px.t(20, color: Px.ink2),
                    ),
                  ),
                  const Spacer(),
                  Neuronek(mood: mood, height: wide ? 90 : 56, shadow: false),
                ],
              ),
              Text('kanałów z kontaktem', style: Px.small),
            ],
          );
    final headMap = withContact == null
        ? null
        : PkWindow(
            padding: const EdgeInsets.all(8),
            child: HeadMap.canDraw(channels!)
                ? HeadMap(channels: channels, training: trainingChannels)
                : _ChannelGrid(channels: channels, training: trainingChannels),
          );
    final bigNeuronek = Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Neuronek(mood: mood, height: wide ? 220 : 150),
      ),
    );
    final dialog = PkDialog(
      color: lost ? Px.warnBg : Px.panel,
      text:
          '$headline\n$body${snapshot.error == null || phase == SessionPhase.contactCheck ? '' : '\n\nPowód: ${connectErrorText(snapshot.error!)}'}',
    );
    return ScreenFrame(
      wide: wide,
      footer: true,
      bottom: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (canSwitch)
            PkAction(
              label: 'UŻYJ KANAŁÓW Z KONTAKTEM',
              onTap: onUseContactChannels,
            ),
          if (canSwitch) const SizedBox(height: 8),
          if (lost && onRetry != null)
            PkAction(label: 'SPRÓBUJ PONOWNIE', onTap: onRetry),
          if (lost && onRetry != null) const SizedBox(height: 8),
          PkAction(
            label: lost ? 'WRÓĆ' : 'ZAKOŃCZ',
            primary: !(lost && onRetry != null) && !canSwitch,
            onTap: onFinish,
          ),
        ],
      ),
      child: wide
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                header,
                const SizedBox(height: 16),
                Expanded(
                  child: PkTwoPane(
                    leftFlex: 5,
                    rightFlex: 4,
                    left: [headMap ?? bigNeuronek],
                    right: [
                      ?counter,
                      if (counter != null) const SizedBox(height: 12),
                      dialog,
                    ],
                  ),
                ),
              ],
            )
          : ListView(
              children: [
                header,
                const SizedBox(height: 12),
                if (counter != null) ...[
                  counter,
                  const SizedBox(height: 12),
                  headMap!,
                ] else
                  bigNeuronek,
                const SizedBox(height: 12),
                dialog,
              ],
            ),
    );
  }
}

/// Czytelny powod nieudanego polaczenia z kodu lub komunikatu zrodla.
String connectErrorText(String reason) {
  if (reason.startsWith('connect_failed'))
    return 'czepek nie odpowiada (${reason.split(':').last}). Włącz go i zbliż.';
  if (reason.startsWith('channels'))
    return 'czepek ma mniej kanałów, niż ustawiono.';
  if (reason.startsWith('start_stream') || reason.startsWith('load_config')) {
    return 'nie udało się uruchomić strumienia ($reason).';
  }
  return reason;
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
          width: 34,
          height: 28,
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
            style: Px.t(
              8,
              color: c.contact ? Colors.white : Px.ink2,
              height: 1,
            ),
          ),
        ),
    ],
  );
}
