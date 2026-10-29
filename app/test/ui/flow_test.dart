import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neurotchi/core/db/app_database.dart';
import 'package:neurotchi/core/db/session_repository.dart';
import 'package:neurotchi/core/eeg/mock_source.dart';
import 'package:neurotchi/core/session/session_models.dart';
import 'package:neurotchi/ui/app.dart';
import 'package:neurotchi/ui/app_services.dart';

import '../support/golden_support.dart';

void main() {
  testWidgets('nawigacja: dom, postep, start sesji', (t) async {
    await loadAppFonts();
    final db = AppDatabase.inMemory();
    final services = AppServices(
      repository: SessionRepository(db),
      rawDir: Directory.systemTemp.createTempSync('flow').path,
      sourceFactory: () => MockSource(realtime: true),
      configOverride: const SessionConfig(blocks: 3, blockS: 180),
    );
    await t.runAsync(() => NeuronekSpritesLoader.load());
    t.view.physicalSize = const Size(780, 1688);
    t.view.devicePixelRatio = 2;
    addTearDown(t.view.reset);

    await t.pumpWidget(NeurotchiApp(services: services));
    expect(find.text('TRENING'), findsOneWidget);
    expect(find.text('NEURONEK'), findsOneWidget);
    expect(find.text('ENERG'), findsOneWidget);
    expect(find.text('KALIBRACJA'), findsOneWidget);
    expect(find.textContaining('relaks, 9 min'), findsOneWidget);
    expect(find.text('RELAKS'), findsOneWidget);
    expect(find.text('SKUPIENIE'), findsOneWidget);
    await t.tap(find.text('SKUPIENIE'));
    await t.pump();
    expect(find.textContaining('skupienie, 9 min'), findsOneWidget);
    await t.tap(find.text('RELAKS'));
    await t.pump();

    await t.ensureVisible(find.text('POSTĘP'));
    await t.tap(find.text('POSTĘP'));
    await t.pumpAndSettle();
    expect(find.text('Jeszcze nie ma sesji. Zacznij pierwszy trening.'), findsOneWidget);
    await t.tap(find.text('←'));
    await t.pumpAndSettle();
    expect(find.text('NEURONEK'), findsOneWidget);

    await t.ensureVisible(find.text('TRENING'));
    await t.tap(find.text('TRENING'));
    await t.pump();
    await t.pump(const Duration(milliseconds: 500));
    expect(find.text('POŁĄCZENIE'), findsOneWidget);
    expect(db.db.select('SELECT status FROM sessions').single['status'], 'in_progress');

    await t.tap(find.text('ZAKOŃCZ'));
    await t.pump(const Duration(milliseconds: 100));
    await t.pumpWidget(const SizedBox());
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
  });
}
