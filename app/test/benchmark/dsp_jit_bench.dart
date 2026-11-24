import 'package:flutter_test/flutter_test.dart';
import 'package:neurotchi/core/research/research_monitor.dart';

void main() {
  test('runTest w trybie JIT (flutter test), 60 s sygnalu', () async {
    final r = await ResearchMonitor.runTest(seconds: 60);
    // ignore: avoid_print
    print(
      'JIT runTest: okna=${r.windows} razem p50=${r.total.p50Ms.toStringAsFixed(3)} ms '
      'p95=${r.total.p95Ms.toStringAsFixed(3)} ms; '
      '${[for (final s in r.stages) '${s.name}: ${s.p50Ms.toStringAsFixed(3)}/${s.p95Ms.toStringAsFixed(3)}'].join('; ')}',
    );
  });
}
