import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neurotchi/core/db/app_database.dart';
import 'package:neurotchi/core/db/session_repository.dart';
import 'package:neurotchi/core/settings/app_settings.dart';
import 'package:neurotchi/ui/app.dart';
import 'package:neurotchi/ui/app_services.dart';

import '../support/golden_support.dart';

const _body = '{"tag_name":"v0.2.0","html_url":"https://gh/r","assets":[]}';

Future<(AppServices, List<String>, SessionRepository)> setup(WidgetTester t, {String body = _body}) async {
  await loadAppFonts();
  final repo = SessionRepository(AppDatabase.inMemory());
  final opened = <String>[];
  final services = AppServices(
    repository: repo,
    rawDir: Directory.systemTemp.createTempSync('upd').path,
    appVersion: '0.1.0',
    updateFetch: (_, _) async => body,
    openUrl: (u) async => opened.add(u),
  );
  await t.runAsync(() => NeuronekSpritesLoader.load());
  t.view.physicalSize = const Size(780, 1688);
  t.view.devicePixelRatio = 2;
  addTearDown(t.view.reset);
  return (services, opened, repo);
}

void main() {
  testWidgets('nowa wersja: pytanie i pobranie otwiera strone wydania', (t) async {
    final (services, opened, _) = await setup(t);
    await t.pumpWidget(NeurotchiApp(services: services));
    await t.pump();
    await t.pump(const Duration(milliseconds: 300));
    expect(find.textContaining('NOWA WERSJA 0.2.0'), findsOneWidget);
    await t.tap(find.text('POBIERZ'));
    await t.pump();
    await t.pump(const Duration(seconds: 1));
    expect(opened, ['https://gh/r']);
    expect(find.textContaining('NOWA WERSJA'), findsNothing);
  });

  testWidgets('pomin ta wersje: zapisane i nie pyta ponownie', (t) async {
    final (services, _, repo) = await setup(t);
    await t.pumpWidget(NeurotchiApp(services: services));
    await t.pump();
    await t.pump(const Duration(milliseconds: 300));
    await t.tap(find.text('POMIŃ TĘ WERSJĘ'));
    await t.pump(const Duration(milliseconds: 300));
    expect(AppSettings.load(repo).skippedVersion, '0.2.0');

    await t.pumpWidget(const SizedBox());
    await t.pumpWidget(NeurotchiApp(services: services));
    await t.pump();
    await t.pump(const Duration(milliseconds: 300));
    expect(find.textContaining('NOWA WERSJA'), findsNothing);
  });

  testWidgets('aktualna wersja i wylaczone sprawdzanie: bez pytania', (t) async {
    final (services, _, repo) = await setup(t, body: '{"tag_name":"v0.1.0","assets":[]}');
    await t.pumpWidget(NeurotchiApp(services: services));
    await t.pump();
    await t.pump(const Duration(milliseconds: 300));
    expect(find.textContaining('NOWA WERSJA'), findsNothing);

    AppSettings(checkUpdates: false).save(repo);
    final (s2, _, repo2) = await setup(t);
    AppSettings(checkUpdates: false).save(repo2);
    await t.pumpWidget(const SizedBox());
    await t.pumpWidget(NeurotchiApp(services: s2));
    await t.pump();
    await t.pump(const Duration(milliseconds: 300));
    expect(find.textContaining('NOWA WERSJA'), findsNothing);
  });
}
