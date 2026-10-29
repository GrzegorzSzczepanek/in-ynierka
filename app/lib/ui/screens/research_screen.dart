import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../../core/db/session_exporter.dart';
import '../../core/db/session_repository.dart';
import '../../core/research/latency.dart';
import '../../core/research/research_monitor.dart';
import '../../core/session/training_protocol.dart';
import '../app_services.dart';
import '../format.dart';
import '../theme/pixel_theme.dart';

/// Tryb badacza: sygnal na zywo, os artefaktow, opoznienia potoku i eksport.
class ResearchScreen extends StatefulWidget {
  const ResearchScreen({
    super.key,
    this.protocol = TrainingProtocol.relaks,
    this.monitor,
    this.reportOverride,
  });

  final TrainingProtocol protocol;

  /// Gotowy monitor (np. w testach); ekran go nie uruchamia ani nie zatrzymuje.
  final ResearchMonitor? monitor;

  /// Stale opoznienia zamiast zywych (deterministyczne zrzuty w testach).
  final LatencyReport? reportOverride;

  @override
  State<ResearchScreen> createState() => _ResearchScreenState();
}

class _ResearchScreenState extends State<ResearchScreen> {
  ResearchMonitor? _monitor;
  Timer? _tick;
  bool _started = false;
  LatencyReport? _test;
  bool _testing = false;
  List<ExportedFile>? _exported;
  String? _exportError;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    final services = ServicesScope.of(context);
    final m = _monitor = widget.monitor ?? ResearchMonitor(services.sourceFactoryFor(widget.protocol), protocol: widget.protocol);
    if (widget.monitor == null) unawaited(m.start());
    _tick = Timer.periodic(const Duration(milliseconds: 160), (_) {
      if (!mounted) return;
      final sw = Stopwatch()..start();
      setState(() {});
      SchedulerBinding.instance.addPostFrameCallback((_) => m.recordRender(sw.elapsedMicroseconds));
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    if (widget.monitor == null) unawaited(_monitor?.stop());
    super.dispose();
  }

  Future<void> _runTest() async {
    setState(() => _testing = true);
    final r = await ResearchMonitor.runTest(protocol: widget.protocol, seconds: 30);
    if (mounted) {
      setState(() {
        _test = r;
        _testing = false;
      });
    }
  }

  void _export(ExportableSession s) {
    final services = ServicesScope.of(context);
    try {
      final files = SessionExporter(services.repository).export(s.id, services.exportDir);
      setState(() {
        _exported = files;
        _exportError = null;
      });
    } catch (e) {
      setState(() => _exportError = '$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final m = _monitor!;
    final services = ServicesScope.of(context);
    final sessions = services.repository.exportableSessions(limit: 3);
    final wide = MediaQuery.sizeOf(context).width >= 900;
    final left = _Signals(monitor: m, training: widget.protocol.channels);
    final right = _Latency(
      report: _test ?? widget.reportOverride ?? m.report,
      isTest: _test != null,
      testing: _testing,
      onTest: _runTest,
      sessions: sessions,
      exported: _exported,
      exportError: _exportError,
      onExport: _export,
    );
    return Scaffold(
      backgroundColor: Px.bg,
      body: SafeArea(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          _Header(monitor: m, protocol: widget.protocol, onBack: () => Navigator.of(context).pop()),
          Container(height: 3, color: Px.ink),
          Expanded(
            child: wide
                ? Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    Expanded(child: SingleChildScrollView(padding: const EdgeInsets.all(16), child: left)),
                    Container(width: 3, color: Px.ink),
                    SizedBox(
                      width: 420,
                      child: SingleChildScrollView(padding: const EdgeInsets.all(16), child: right),
                    ),
                  ])
                : ListView(padding: const EdgeInsets.all(16), children: [left, const SizedBox(height: 16), right]),
          ),
        ]),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.monitor, required this.protocol, required this.onBack});

  final ResearchMonitor monitor;
  final TrainingProtocol protocol;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: Wrap(spacing: 12, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
          PkBack(onPressed: onBack),
          Text('NEUROtchi', style: Px.t(18, height: 1.2, shadow: true)),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            color: Px.ink,
            child: Text('tryb badacza', style: Px.t(8, color: Colors.white, height: 1.4)),
          ),
          Text('${protocol.title} · ${monitor.fs} Hz · ${monitor.names.length} kanałów',
              style: Px.small),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            color: Px.accent,
            child: Text('LIVE ${mmss(monitor.elapsed.inSeconds.toDouble())}',
                style: Px.t(8, color: Colors.white, height: 1.4)),
          ),
        ]),
      );
}

class _Signals extends StatelessWidget {
  const _Signals({required this.monitor, required this.training});

  final ResearchMonitor monitor;
  final List<String> training;

  @override
  Widget build(BuildContext context) {
    final traces = monitor.traces;
    final valid = monitor.validSeconds;
    final bad = valid.where((v) => !v).length;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('SUROWY SYGNAŁ', style: Px.t(13, shadow: true)),
      Text(
          '${monitor.config.filterLowHz.round()}–${monitor.config.filterHighHz.round()} Hz, '
          'notch ${monitor.config.notchHz?.round() ?? 'wył.'} Hz, okno ${monitor.seconds} s, 50 µV/div',
          style: Px.tiny),
      const SizedBox(height: 10),
      if (traces.isEmpty)
        Text('Czekam na dane ze źródła…', style: Px.small)
      else
        for (var i = 0; i < traces.length; i++)
          _TraceRow(name: monitor.names[i], data: traces[i], highlight: training.contains(monitor.names[i])),
      const SizedBox(height: 14),
      Row(children: [
        Expanded(child: Text('ARTEFAKTY W CZASIE, OKNA PO 1 s', style: Px.t(9))),
        Text('${valid.length} s · odrzucone $bad', style: Px.tiny),
      ]),
      const SizedBox(height: 6),
      _Timeline(valid: valid),
      const SizedBox(height: 8),
      Text('Ciemne okna: odrzucone z analizy (amplituda, płaski sygnał, mięśnie, luka).', style: Px.tiny),
    ]);
  }
}

class _TraceRow extends StatelessWidget {
  const _TraceRow({required this.name, required this.data, required this.highlight});

  final String name;
  final Float64List data;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    var lo = double.infinity, hi = -double.infinity;
    final from = data.length - 250 < 0 ? 0 : data.length - 250;
    for (var i = from; i < data.length; i++) {
      if (data[i] < lo) lo = data[i];
      if (data[i] > hi) hi = data[i];
    }
    final pp = hi >= lo ? hi - lo : 0;
    return Container(
      height: 52,
      decoration: BoxDecoration(
        color: highlight ? const Color(0xFFDCE6FA) : null,
        border: const Border(bottom: BorderSide(color: Px.soft)),
      ),
      child: Row(children: [
        SizedBox(width: 44, child: Text(name, style: Px.t(9, height: 1))),
        Expanded(child: CustomPaint(painter: _TracePainter(data), child: const SizedBox.expand())),
        SizedBox(width: 96, child: Text('${pp.round()} µV pp', textAlign: TextAlign.right, style: Px.tiny)),
      ]),
    );
  }
}

class _TracePainter extends CustomPainter {
  _TracePainter(this.data);

  final Float64List data;

  @override
  void paint(Canvas canvas, Size size) {
    if (data.isEmpty) return;
    final mid = size.height / 2;
    const range = 100.0; // pelna wysokosc = +-100 uV (50 uV/div)
    final path = Path();
    final cols = size.width.floor().clamp(1, 1200);
    for (var x = 0; x < cols; x++) {
      final i = (x * (data.length - 1) / cols).floor();
      final y = mid - (data[i].clamp(-range, range) / range) * (size.height / 2 - 3);
      if (x == 0) {
        path.moveTo(0, y);
      } else {
        path.lineTo(x * size.width / cols, y);
      }
    }
    canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5
          ..color = Px.ink);
  }

  @override
  bool shouldRepaint(_TracePainter old) => true;
}

class _Timeline extends StatelessWidget {
  const _Timeline({required this.valid});

  final List<bool> valid;

  @override
  Widget build(BuildContext context) => SizedBox(
        height: 14,
        child: Row(children: [
          for (var i = 0; i < 120; i++)
            Expanded(
              child: Container(
                margin: const EdgeInsets.only(right: 1),
                color: i < 120 - valid.length
                    ? Px.panel
                    : (valid[i - (120 - valid.length)] ? Px.soft : Px.ink),
              ),
            ),
        ]),
      );
}

class _Latency extends StatelessWidget {
  const _Latency({
    required this.report,
    required this.isTest,
    required this.testing,
    required this.onTest,
    required this.sessions,
    required this.exported,
    required this.exportError,
    required this.onExport,
  });

  final LatencyReport report;
  final bool isTest;
  final bool testing;
  final VoidCallback onTest;
  final List<ExportableSession> sessions;
  final List<ExportedFile>? exported;
  final String? exportError;
  final ValueChanged<ExportableSession> onExport;

  String _ms(double v) => v.isNaN ? '--' : (v < 10 ? decimal(v, 1) : v.round().toString());

  @override
  Widget build(BuildContext context) {
    final stages = [for (final s in report.stages) if (s.name != 'Okno analizy (krok)') s];
    final p50 = stages.where((s) => s.hasData).fold(0.0, (a, s) => a + s.p50Ms);
    final p95 = stages.where((s) => s.hasData).fold(0.0, (a, s) => a + s.p95Ms);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(
        isTest ? 'Test opóźnień (syntetyczny sygnał), n = ${report.windows} okien'
            : 'Opóźnienie na żywo, n = ${report.windows} okien',
        style: Px.tiny,
      ),
      const SizedBox(height: 4),
      Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
        Text(_ms(p50), style: Px.t(46, height: 1.1, shadow: true)),
        const SizedBox(width: 8),
        Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Text('ms p50', style: Px.t(12, height: 1.2)),
        ),
      ]),
      Text('p95 ${_ms(p95)}', style: Px.t(11, color: Px.ink2)),
      const SizedBox(height: 6),
      Text('Cel: poniżej 300 ms. Okno analizy dodaje własne opóźnienie ${report.stages[2].p50Ms.round()} ms (krok).',
          style: Px.tiny),
      const SizedBox(height: 10),
      Row(children: [
        Expanded(child: Text('ETAP', style: Px.tiny)),
        Text('p50 / p95 ms', style: Px.tiny),
      ]),
      for (final s in report.stages)
        PkLeader(s.name, s.hasData ? '${_ms(s.p50Ms)} / ${_ms(s.p95Ms)}' : '--'),
      PkLeader('Razem (suma)', '${_ms(p50)} / ${_ms(p95)}', bold: true),
      const SizedBox(height: 6),
      Text('Pomiar: znaczniki czasu w kodzie. Percentyle nie sumują się, suma p95 to górna granica.',
          style: Px.tiny),
      const SizedBox(height: 10),
      PkAction(label: testing ? 'TEST TRWA…' : 'URUCHOM TEST LATENCJI', onTap: testing ? null : onTest, primary: false),
      const SizedBox(height: 18),
      Text('EKSPORT', style: Px.t(13, shadow: true)),
      const SizedBox(height: 6),
      if (sessions.isEmpty) Text('Brak sesji do eksportu.', style: Px.small),
      for (final s in sessions)
        GestureDetector(
          onTap: () => onExport(s),
          child: PkLeader(
            'S-${s.id.toString().padLeft(4, '0')} ${s.protocol.title.toLowerCase()}',
            s.status == 'completed' ? '${s.createdAt.toLocal().day}.${s.createdAt.toLocal().month}' : 'niepełny',
          ),
        ),
      const SizedBox(height: 8),
      PkAction(
        label: 'EKSPORTUJ SESJĘ',
        onTap: sessions.isEmpty ? null : () => onExport(sessions.first),
      ),
      if (exported != null) ...[
        const SizedBox(height: 8),
        for (final f in exported!)
          Text('${f.path.split('/').last}  ${(f.bytes / 1024).toStringAsFixed(1)} kB', style: Px.tiny),
        Text('Katalog: ${exported!.first.path.substring(0, exported!.first.path.lastIndexOf('/'))}', style: Px.tiny),
      ],
      if (exportError != null) Text('Błąd eksportu: $exportError', style: Px.t(8, color: Px.danger)),
    ]);
  }
}
