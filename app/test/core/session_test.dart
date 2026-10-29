import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:neurotchi/core/eeg/eeg_source.dart';
import 'package:neurotchi/core/eeg/mock_source.dart';
import 'package:neurotchi/core/eeg/stream_item.dart';
import 'package:neurotchi/core/session/session_controller.dart';
import 'package:neurotchi/core/session/session_models.dart';

const cfg = SessionConfig(
  calibrationS: 20,
  blocks: 3,
  blockS: 10,
  breakS: 4,
  contactSettleS: 1,
  contactStableS: 1,
  calibrationClosedS: 0,
  reconnectIntervalS: 15,
);

class FailingSource implements EegSource {
  final _c = StreamController<StreamItem>();

  @override
  Stream<StreamItem> get items => _c.stream;

  @override
  Future<void> start() async {
    _c.add(const DisconnectedEvent(reason: 'connect_failed:1', tRecv: 0));
    unawaited(_c.close());
  }

  @override
  Future<void> stop() async {}
}

MockSource mock({
  double Function(double)? amp,
  int? disconnectAfter,
  bool Function(double)? contact,
  int seconds = 200,
}) =>
    MockSource(
      duration: Duration(seconds: seconds),
      alphaAmplitudeUv: amp ?? (_) => 20,
      noiseUv: 2,
      disconnectAfterChunk: disconnectAfter,
      contactAt: contact,
    );

Future<void> instant(Duration _) async {}

Future<(SessionResult, List<SessionPhase>)> run(
  SessionController c, {
  void Function(SessionSnapshot)? onSnapshot,
}) async {
  final phases = <SessionPhase>[];
  c.snapshots.listen((s) {
    if (phases.isEmpty || phases.last != s.phase) phases.add(s.phase);
    onSnapshot?.call(s);
  });
  final r = await c.run();
  return (r, phases);
}

void main() {
  test('pelny przebieg: kalibracja, trzy bloki, przerwy, podsumowanie', () async {
    final c = SessionController(
      sourceFactory: () => mock(amp: (t) => t < 25 ? 10 : 30),
      config: cfg,
      delay: instant,
    );
    final (r, phases) = await run(c);
    expect(r.status, SessionStatus.completed);
    expect(r.calibrations.single.result.accepted, isTrue);
    expect(r.blocks.map((b) => b.blockNo), [1, 2, 3]);
    expect(phases, [
      SessionPhase.connecting,
      SessionPhase.contactCheck,
      SessionPhase.calibrating,
      SessionPhase.training,
      SessionPhase.breakBetweenBlocks,
      SessionPhase.training,
      SessionPhase.breakBetweenBlocks,
      SessionPhase.training,
      SessionPhase.summary,
      SessionPhase.completed,
    ]);
    for (final b in r.blocks) {
      expect(b.actualS, closeTo(10, 0.5));
      expect(b.validSignalS, closeTo(10, 0.6));
      expect(b.timeAboveThresholdS, lessThanOrEqualTo(b.validSignalS));
    }
    expect(r.blocks.first.rewardCount, greaterThanOrEqualTo(1));
    expect(r.blocks.first.events.first.type, 'reward');
    expect(r.countsForProgress, isTrue);
  });

  test('kontrola kontaktu czeka na kontakt elektrod', () async {
    final c = SessionController(
      sourceFactory: () => mock(contact: (t) => t >= 12),
      config: cfg,
      delay: instant,
    );
    var calibStartElapsedSeen = false;
    final (r, _) = await run(c, onSnapshot: (s) {
      if (s.phase == SessionPhase.calibrating) calibStartElapsedSeen = true;
    });
    expect(calibStartElapsedSeen, isTrue);
    expect(r.status, SessionStatus.completed);
    final first = r.blocks.first;
    expect(first.actualS, closeTo(10, 0.5));
  });

  test('nieudana kalibracja jest powtarzana', () async {
    final c = SessionController(
      sourceFactory: () => mock(amp: (t) => t < 25 ? 150 : 20),
      config: cfg,
      delay: instant,
    );
    final (r, _) = await run(c);
    expect(r.calibrations.length, 2);
    expect(r.calibrations.first.result.accepted, isFalse);
    expect(r.calibrations.last.result.accepted, isTrue);
    expect(r.status, SessionStatus.completed);
  });

  test('utrata polaczenia: ponowne laczenie i kalibracja od poczatku', () async {
    var n = 0;
    final c = SessionController(
      sourceFactory: () => n++ == 0 ? mock(disconnectAfter: 300) : mock(),
      config: cfg,
      delay: instant,
    );
    final (r, phases) = await run(c);
    expect(phases, contains(SessionPhase.reconnecting));
    expect(r.calibrations.length, 2);
    expect(r.blocks.map((b) => b.blockNo), [1, 2, 3]);
    expect(r.status, SessionStatus.completed);
    expect(n, 2);
  });

  test('trzy nieudane proby laczenia na starcie wracaja do wyboru urzadzenia', () async {
    var n = 0;
    final c = SessionController(
      sourceFactory: () {
        n++;
        return FailingSource();
      },
      config: cfg,
      delay: instant,
    );
    final (r, phases) = await run(c);
    expect(n, 3);
    expect(phases.last, SessionPhase.deviceSelection);
    expect(r.status, SessionStatus.connectionLost);
    expect(r.blocks, isEmpty);
  });

  test('po trzech nieudanych ponownych probach czeka na reczne ponowienie', () async {
    var n = 0;
    late SessionController c;
    c = SessionController(
      sourceFactory: () {
        n++;
        if (n == 1) return mock(disconnectAfter: 300);
        if (n <= 4) return FailingSource();
        return mock();
      },
      config: cfg,
      delay: instant,
    );
    final (r, phases) = await run(c, onSnapshot: (s) {
      if (s.phase == SessionPhase.connectionLost) c.retry();
    });
    expect(phases, contains(SessionPhase.connectionLost));
    expect(n, 5);
    expect(r.status, SessionStatus.completed);
  });

  test('zakonczenie w trakcie bloku nie liczy postepu', () async {
    late SessionController c;
    c = SessionController(sourceFactory: mock, config: cfg, delay: instant);
    final (r, _) = await run(c, onSnapshot: (s) {
      if (s.phase == SessionPhase.training && s.phaseElapsedS > 3) c.finish();
    });
    expect(r.status, SessionStatus.interrupted);
    expect(r.blocks, isEmpty);
    expect(r.countsForProgress, isFalse);
  });

  test('zakonczenie po pierwszym bloku liczy postep', () async {
    late SessionController c;
    c = SessionController(sourceFactory: mock, config: cfg, delay: instant);
    final (r, _) = await run(c, onSnapshot: (s) {
      if (s.phase == SessionPhase.breakBetweenBlocks) c.finish();
    });
    expect(r.status, SessionStatus.interrupted);
    expect(r.blocks.length, 1);
    expect(r.countsForProgress, isTrue);
  });

  test('okna niewazne w bloku trafiaja do przedzialow z powodem', () async {
    final c = SessionController(
      sourceFactory: () => mock(amp: (t) => (t > 30 && t < 36) ? 150 : 20),
      config: cfg,
      delay: instant,
    );
    final (r, _) = await run(c);
    final intervals = [for (final b in r.blocks) ...b.invalid];
    expect(intervals, isNotEmpty);
    expect(intervals.every((i) => i.endMs > i.startMs), isTrue);
    expect(intervals.any((i) => i.reason.name == 'amplitude'), isTrue);
  });
}
