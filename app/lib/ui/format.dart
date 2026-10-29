import '../core/dsp/alpha_pipeline.dart';

String mmss(double seconds) {
  final s = seconds.isFinite ? seconds.round().clamp(0, 359999) : 0;
  return '${(s ~/ 60).toString().padLeft(2, '0')}:${(s % 60).toString().padLeft(2, '0')}';
}

/// Czas w minutach i sekundach bez zera wiodacego: 9:40.
String mSs(double seconds) {
  final s = seconds.round();
  return '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';
}

String decimal(double v, [int digits = 2]) => v.toStringAsFixed(digits).replaceAll('.', ',');

String qualityLabel(double? q) => q == null
    ? 'brak danych'
    : q >= 0.8
        ? 'dobry'
        : q >= 0.5
            ? 'średni'
            : 'słaby';

String reasonTitle(InvalidReason r) => switch (r) {
      InvalidReason.gap => 'Utrata pakietów',
      InvalidReason.saturation => 'Nasycenie wejścia',
      InvalidReason.flat => 'Płaski sygnał',
      InvalidReason.amplitude => 'Artefakt ruchowy',
      InvalidReason.jump => 'Gwałtowny skok sygnału',
      InvalidReason.muscle => 'Aktywność mięśniowa',
    };

String reasonHint(InvalidReason r) => switch (r) {
      InvalidReason.gap => 'Zostań w zasięgu czepka, dane wrócą same.',
      InvalidReason.saturation => 'Sprawdź przyleganie elektrod i dociśnij czepek.',
      InvalidReason.flat => 'Sprawdź, czy elektrody dotykają skóry.',
      InvalidReason.amplitude => 'Siedź spokojnie i sprawdź przyleganie elektrod.',
      InvalidReason.jump => 'Unikaj ruchu głową i kabli.',
      InvalidReason.muscle => 'Rozluźnij szczękę i brwi.',
    };
