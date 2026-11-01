import 'dart:io';

import 'session_repository.dart';

class ExportedFile {
  const ExportedFile(this.path, this.bytes);

  final String path;
  final int bytes;
}

/// Eksport sesji do katalogu: surowe EEG (csv i json z metadanymi segmentu)
/// oraz zdarzenia sesji w TSV (kalibracje, bloki, zdarzenia, przedzialy nieważne).
/// Format FIF wymaga konwersji offline (MNE) z tych plikow.
class SessionExporter {
  SessionExporter(this.repo);

  final SessionRepository repo;

  List<ExportedFile> export(int sessionId, String dir) {
    Directory(dir).createSync(recursive: true);
    final out = <ExportedFile>[];
    final tag = 'S-${sessionId.toString().padLeft(4, '0')}';

    final tsv = File('$dir/${tag}_events.tsv')
      ..writeAsStringSync(_events(sessionId));
    out.add(ExportedFile(tsv.path, tsv.lengthSync()));

    for (final seg in repo.db.select(
      'SELECT segment_no, raw_file_path FROM segments WHERE session_id = ? ORDER BY segment_no',
      [sessionId],
    )) {
      final csv = File(seg['raw_file_path'] as String);
      if (!csv.existsSync()) continue;
      final base = '$dir/${tag}_seg${seg['segment_no']}_raw';
      csv.copySync('$base.csv');
      out.add(ExportedFile('$base.csv', csv.lengthSync()));
      final json = File(csv.path.replaceFirst(RegExp(r'\.csv$'), '.json'));
      if (json.existsSync()) {
        json.copySync('$base.json');
        out.add(ExportedFile('$base.json', json.lengthSync()));
      }
    }
    return out;
  }

  String _events(int id) {
    final b = StringBuffer('typ\tnr\tczas_ms\tkoniec_ms\twartosc\tszczegoly\n');
    final s = repo.db.select(
      'SELECT s.created_at, s.status, s.source_type, s.mood_after, p.name AS protocol '
      'FROM sessions s JOIN protocols p ON p.id = s.protocol_id WHERE s.id = ?',
      [id],
    ).first;
    b.writeln(
      'sesja\t$id\t\t\t${s['status']}\t${s['protocol']} ${s['source_type']} ${s['created_at']}'
      ' nastroj=${s['mood_after'] ?? ''}',
    );
    for (final c in repo.db.select(
      'SELECT * FROM calibrations WHERE session_id = ? ORDER BY attempt_no',
      [id],
    )) {
      b.writeln(
        'kalibracja\t${c['attempt_no']}\t\t\t${c['threshold_y'] ?? ''}\t'
        'baseline=${c['baseline_median'] ?? ''} mad=${c['baseline_mad'] ?? ''} '
        'alfa_x=${c['alpha_ratio'] ?? ''} alfa_hz=${c['alpha_peak_hz'] ?? ''} '
        'powod=${c['failure_reason'] ?? ''}',
      );
    }
    for (final bl in repo.db.select(
      'SELECT * FROM blocks WHERE session_id = ? ORDER BY block_no',
      [id],
    )) {
      b.writeln(
        'blok\t${bl['block_no']}\t\t\t${bl['valid_signal_s']}\t'
        'prog=${bl['threshold_used']} w_celu_s=${bl['time_above_threshold_s']} '
        'nagrody=${bl['reward_count']} kontrola=${bl['control_rating'] ?? ''}',
      );
      for (final e in repo.db.select(
        'SELECT e.occurred_at_ms, t.name FROM block_events e JOIN event_types t ON t.id = e.event_type_id '
        'WHERE e.block_id = ? ORDER BY e.occurred_at_ms',
        [bl['id']],
      )) {
        b.writeln(
          'zdarzenie\t${bl['block_no']}\t${e['occurred_at_ms']}\t\t${e['name']}\t',
        );
      }
      for (final i in repo.db.select(
        'SELECT i.start_ms, i.end_ms, r.name FROM invalid_intervals i JOIN invalid_reasons r ON r.id = i.reason_id '
        'WHERE i.block_id = ? ORDER BY i.start_ms',
        [bl['id']],
      )) {
        b.writeln(
          'nieważne\t${bl['block_no']}\t${i['start_ms']}\t${i['end_ms']}\t${i['name']}\t',
        );
      }
    }
    for (final g in repo.db.select(
      'SELECT g.first_sample, g.sample_count, sg.segment_no FROM segment_gaps g '
      'JOIN segments sg ON sg.id = g.segment_id WHERE sg.session_id = ? ORDER BY sg.segment_no, g.first_sample',
      [id],
    )) {
      b.writeln(
        'luka\t${g['segment_no']}\t${g['first_sample']}\t\t${g['sample_count']}\t',
      );
    }
    return b.toString();
  }
}
