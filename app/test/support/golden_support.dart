import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neurotchi/ui/neuronek/neuronek.dart';
import 'package:neurotchi/ui/theme/pixel_theme.dart';

/// Czcionka z assets, bo flutter_test domyslnie uzywa blokow (Ahem).
var _fontsLoaded = false;

Future<void> loadAppFonts() async {
  if (_fontsLoaded) return;
  _fontsLoaded = true;
  final loader = FontLoader('IBMPlexSans')
    ..addFont(rootBundle.load('assets/fonts/IBMPlexSans-Variable.ttf'));
  await loader.load();
}

Future<void> pumpScreen(WidgetTester tester, Widget screen,
    {Size size = const Size(390, 844)}) async {
  await loadAppFonts();
  await NeuronekSprites.load();
  tester.view.physicalSize = size * 2;
  tester.view.devicePixelRatio = 2;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: Px.theme,
    home: screen,
  ));
  await tester.pump();
}

/// Wczytanie sprite'ow bez FakeAsync (uzywac w tester.runAsync).
class NeuronekSpritesLoader {
  static Future<void> load() => NeuronekSprites.load().then((_) {});
}
