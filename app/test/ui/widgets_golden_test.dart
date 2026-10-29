import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neurotchi/ui/neuronek/neuronek.dart';
import 'package:neurotchi/ui/theme/pixel_theme.dart';
import 'package:neurotchi/ui/widgets/pk_widgets.dart';

import '../support/golden_support.dart';

void main() {
  testWidgets('arkusz widgetow PK', (tester) async {
    await pumpScreen(
      tester,
      ScreenFrame(
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('NEUROTCHI', style: Px.title),
              const SizedBox(height: 12),
              Wrap(spacing: 8, runSpacing: 8, children: [
                for (final m in Mood.values) Neuronek(mood: m, height: 90),
              ]),
              const SizedBox(height: 12),
              const PkDialog(text: 'Dziś relaks, 9 min. Ąćęłńóśźż → α β θ'),
              const SizedBox(height: 12),
              PkMenu(rows: [
                PkMenuRow(label: 'RELAKS', sub: 'alfa 8–12 Hz, O1 O2', trailing: '9 min', selected: true, onTap: () {}),
                PkMenuRow(label: 'SKUPIENIE', sub: 'β/(α+θ), F3 F4 C3 C4', trailing: '9 min', onTap: () {}),
              ]),
              const SizedBox(height: 12),
              const PkBar(value: 0.7, marker: 0.6),
              const SizedBox(height: 8),
              const PkSegBar(value: 0.35),
              const SizedBox(height: 8),
              const PkLeader('Czas w celu', '41%'),
              const PkLeader('Odrzucone okna', '11/450'),
              const SizedBox(height: 8),
              PkChart(values: const [0.3, 0.4, 0.5, 0.45, 0.6, 0.7, 0.65, 0.8], threshold: 0.55, bars: true),
              const SizedBox(height: 8),
              PkAction(label: 'ZAPISZ I WRÓĆ', onTap: () {}),
            ],
          ),
        ),
      ),
      size: const Size(390, 900),
    );
    await tester.pumpAndSettle();
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('../goldens/widgets.png'));
  });
}
