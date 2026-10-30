import 'dart:io';

import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';

import 'core/db/app_database.dart';
import 'core/db/session_repository.dart';
import 'core/update/update_checker.dart';
import 'ui/app.dart';
import 'ui/app_services.dart';
import 'ui/neuronek/neuronek.dart';

/// Zrodlo sygnalu (Demo lub czepek), nazwy kanalow i kanaly treningowe
/// ustawia sie w aplikacji (ekran Ustawienia), nie w wierszu polecen.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await NeuronekSprites.load();
  final dir = await getApplicationSupportDirectory();
  final database = AppDatabase.open('${dir.path}/neurotchi.db');
  final raw = '${dir.path}/raw';
  Directory(raw).createSync(recursive: true);

  runApp(NeurotchiApp(
    services: AppServices(
      repository: SessionRepository(database),
      rawDir: raw,
      appVersion: (await PackageInfo.fromPlatform()).version,
      updateFetch: httpFetch,
      openUrl: (url) async {
        await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
      },
      exportDir: '${(await getApplicationDocumentsDirectory()).path}/NEUROtchi/eksport',
    ),
  ));
}
