import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/eeg/brainaccess/lib_locator.dart';
import '../../core/eeg/brainaccess/scanner.dart';
import '../../core/session/training_protocol.dart';
import '../../core/settings/app_settings.dart';
import '../app_services.dart';
import '../theme/pixel_theme.dart';

typedef ScanFn = Future<List<String>> Function(String libPath);

/// Ustawienia: zrodlo sygnalu, czepek, nazwy kanalow i kanaly treningowe.
/// Zmiany zapisuja sie od razu w bazie.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({
    super.key,
    this.scan = platformScan,
    this.needsLibrary,
  });

  final ScanFn scan;

  /// Czy trzeba lokalnej biblioteki SDK (macOS); na Androidzie SDK jest w aplikacji.
  final bool? needsLibrary;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late AppSettings _s;
  late final TextEditingController _lib;
  bool _loaded = false;
  bool _scanning = false;
  List<String>? _found;
  String? _scanError;
  bool _saved = false;
  Timer? _savedTimer;

  static const _demoChannels = ['O1', 'O2', 'F3', 'F4', 'C3', 'C4'];

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_loaded) return;
    _loaded = true;
    _s = ServicesScope.of(context).settings;
    _lib = TextEditingController(text: _s.libPath);
  }

  @override
  void dispose() {
    _savedTimer?.cancel();
    _lib.dispose();
    super.dispose();
  }

  bool get _needsLib => widget.needsLibrary ?? platformNeedsLibrary;

  void _save() {
    _s.save(ServicesScope.of(context).repository);
    _savedTimer?.cancel();
    _savedTimer = Timer(const Duration(milliseconds: 1800), () {
      if (mounted) setState(() => _saved = false);
    });
    setState(() => _saved = true);
  }

  Future<void> _scan() async {
    final lib = _needsLib ? findBacoreLib(override: _s.libPath) : '';
    if (lib == null) {
      setState(
        () => _scanError =
            'Nie znaleziono biblioteki libbacore. Wpisz jej ścieżkę poniżej.',
      );
      return;
    }
    setState(() {
      _scanning = true;
      _scanError = null;
      _found = null;
    });
    try {
      final names = await widget.scan(lib);
      if (!mounted) return;
      setState(() {
        _found = names;
        _scanning = false;
        if (names.length == 1) {
          _s.deviceName = names.first;
          _save();
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _scanning = false;
        _scanError =
            'Skan nie powiódł się: $e. Sprawdź Bluetooth i uprawnienia aplikacji.';
      });
    }
  }

  void _toggle(TrainingProtocol p, String name) {
    final base = [..._s.trainingChannelsFor(p)];
    if (base.contains(name)) {
      base.remove(name);
    } else {
      base.add(name);
    }
    if (base.isEmpty) {
      _s.training.remove(p.id);
    } else {
      _s.training[p.id] = base;
    }
    _save();
  }

  @override
  Widget build(BuildContext context) {
    final device = _s.source == SourceKind.device;
    final lib = findBacoreLib(override: _s.libPath);
    final names = device ? _s.channelNames : _demoChannels;
    return ScreenFrame(
      footer: true,
      child: ListView(
        children: [
          Row(
            children: [
              PkBack(onPressed: () => Navigator.of(context).pop()),
              const SizedBox(width: 12),
              Expanded(child: Text('USTAWIENIA', style: Px.t(20, height: 1.3, shadow: true))),
              AnimatedOpacity(
                opacity: _saved ? 1 : 0,
                duration: const Duration(milliseconds: 150),
                child: Text('ZAPISANO ✓', style: Px.t(9, color: Px.accent, height: 1)),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text('ŹRÓDŁO SYGNAŁU', style: Px.t(10)),
          const SizedBox(height: 6),
          PkMenu(
            rows: [
              PkMenuRow(
                label: 'DEMO',
                sub: 'sygnał symulowany, bez czepka',
                selected: !device,
                onTap: () {
                  _s.source = SourceKind.demo;
                  _save();
                },
              ),
              PkMenuRow(
                label: 'CZEPEK BRAINACCESS',
                sub: 'prawdziwy sygnał przez Bluetooth',
                selected: device,
                onTap: () {
                  _s.source = SourceKind.device;
                  _save();
                },
              ),
            ],
          ),
          if (device) ...[
            const SizedBox(height: 14),
            Text('CZEPEK', style: Px.t(10)),
            const SizedBox(height: 6),
            PkLeader(
              'Wybrany',
              _s.deviceName.isEmpty ? 'brak' : _s.deviceName,
              bold: true,
            ),
            if (_needsLib) ...[
              PkLeader(
                'Biblioteka SDK',
                lib == null ? 'nie znaleziono' : 'znaleziona',
              ),
              if (lib != null) Text(lib, style: Px.tiny),
            ],
            const SizedBox(height: 8),
            PkAction(
              label: _scanning ? 'SZUKAM CZEPKA…' : 'SZUKAJ CZEPKA',
              onTap: _scanning ? null : _scan,
              primary: _s.deviceName.isEmpty,
            ),
            if (_scanning)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  'Skan trwa ok. 5 s. Włącz czepek i trzymaj go blisko.',
                  style: Px.tiny,
                ),
              ),
            if (_found != null) ...[
              const SizedBox(height: 8),
              if (_found!.isEmpty)
                Text(
                  'Nie znaleziono czepka. Włącz go i spróbuj jeszcze raz.',
                  style: Px.small,
                )
              else
                PkMenu(
                  rows: [
                    for (final n in _found!)
                      PkMenuRow(
                        label: n,
                        selected: n == _s.deviceName,
                        onTap: () {
                          _s.deviceName = n;
                          _save();
                        },
                      ),
                  ],
                ),
            ],
            if (_scanError != null)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(_scanError!, style: Px.t(8, color: Px.danger)),
              ),
            if (_needsLib) ...[
              const SizedBox(height: 8),
              Text(
                'Ścieżka libbacore (puste: szukam automatycznie)',
                style: Px.tiny,
              ),
              const SizedBox(height: 4),
              TextField(
                controller: _lib,
                style: Px.t(9, height: 1.4),
                decoration: const InputDecoration(
                  isDense: true,
                  border: OutlineInputBorder(borderRadius: BorderRadius.zero),
                  filled: true,
                  fillColor: Px.panel,
                ),
                onChanged: (v) {
                  _s.libPath = v.trim();
                  _s.save(ServicesScope.of(context).repository);
                },
                onSubmitted: (_) => setState(() {}),
              ),
            ],
            const SizedBox(height: 14),
            Text('NAZWY KANAŁÓW', style: Px.t(10)),
            const SizedBox(height: 6),
            PkMenu(
              rows: [
                PkMenuRow(
                  label: 'WG TABELI PRODUCENTA',
                  sub: 'O1, O2, Pz... (MAXI, niepotwierdzone pomiarem)',
                  selected: _s.naming == ChannelNaming.manufacturer,
                  onTap: () {
                    _s.naming = ChannelNaming.manufacturer;
                    _s.training.clear();
                    _save();
                  },
                ),
                PkMenuRow(
                  label: 'NUMERY',
                  sub: 'ch1 ... ch32, bez mapy głowy',
                  selected: _s.naming == ChannelNaming.numbered,
                  onTap: () {
                    _s.naming = ChannelNaming.numbered;
                    _s.training.clear();
                    _save();
                  },
                ),
              ],
            ),
          ],
          const SizedBox(height: 14),
          Text('TRENING', style: Px.t(10)),
          const SizedBox(height: 6),
          PkMenu(
            rows: [
              PkMenuRow(
                label: 'INSTRUKCJA PRZED TRENINGIEM',
                sub: _s.showInstruction ? 'pokazuję przy każdym starcie' : 'pomijam, start od razu',
                trailing: _s.showInstruction ? 'WŁ' : 'WYŁ',
                selected: _s.showInstruction,
                onTap: () {
                  _s.showInstruction = !_s.showInstruction;
                  _save();
                },
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text('KANAŁY TRENINGOWE', style: Px.t(10)),
          Text(
            'Wybierz kanały z kontaktem. Puste = domyślne protokołu.',
            style: Px.tiny,
          ),
          for (final p in TrainingProtocol.all) ...[
            const SizedBox(height: 8),
            Text(
              '${p.title.toUpperCase()}: ${_s.trainingChannelsFor(p).join(' ')}',
              style: Px.t(9),
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 5,
              runSpacing: 5,
              children: [
                for (final n in names)
                  _Chip(
                    label:
                        device && _s.effectiveNaming == ChannelNaming.numbered
                        ? n.replaceFirst('ch', '')
                        : n,
                    on: _s.trainingChannelsFor(p).contains(n),
                    onTap: () => _toggle(p, n),
                  ),
              ],
            ),
          ],
          const SizedBox(height: 10),
          Text(
            'Zmiany zapisują się od razu (widać to przy napisie ZAPISANO). Aktywną masę (BIAS) ustawiam automatycznie na dwóch pierwszych kanałach treningowych.',
            style: Px.tiny,
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.label, required this.on, required this.onTap});

  final String label;
  final bool on;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    selected: on,
    label: label,
    child: GestureDetector(
      onTap: onTap,
      child: Container(
        constraints: const BoxConstraints(minWidth: 38, minHeight: 30),
        padding: const EdgeInsets.symmetric(horizontal: 6),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: on ? Px.accent : Px.panel,
          border: Border.all(color: on ? Px.ink : Px.soft, width: 2),
        ),
        child: Text(
          label,
          style: Px.t(8, color: on ? Colors.white : Px.ink2, height: 1),
        ),
      ),
    ),
  );
}
