import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neurotchi/ui/neuronek/neuronek.dart';
import '../support/golden_support.dart';
import 'package:neurotchi/ui/theme/pixel_theme.dart';

void main() {
  testWidgets('arkusz widgetow', (tester) async {
    await pumpScreen(
      tester,
      ScreenFrame(
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('NEUROtchi', style: Px.h1),
              const SizedBox(height: 12),
              Wrap(spacing: 8, runSpacing: 8, children: [
                for (final m in Mood.values) Neuronek(mood: m, height: 110),
              ]),
              const SizedBox(height: 16),
              PixelCard(child: Text('Dziś relaks, 15 minut.', style: Px.body)),
              const SizedBox(height: 12),
              const PixelBar(value: 0.58),
              const SizedBox(height: 12),
              PixelButton(label: 'Rozpocznij trening', onPressed: () {}),
              const SizedBox(height: 8),
              PixelButton(label: 'Pauza', primary: false, onPressed: () {}),
              const SizedBox(height: 12),
              Text('0,72', style: Px.hero),
              Text('alfa 8–12 Hz, O1 O2 → ąćęłńóśźż', style: Px.secondary),
            ],
          ),
        ),
      ),
      size: const Size(390, 700),
    );
    await tester.pumpAndSettle();
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('../goldens/widgets.png'));
  });
}
