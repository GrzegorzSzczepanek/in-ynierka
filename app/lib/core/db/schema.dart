/// Schemat wersja 5 (docs/diagrams/schema_v5.dbml) wraz z ograniczeniami CHECK.
const schemaVersion = 2;

const schemaSql = '''
CREATE TABLE processing_configs (
  id INTEGER PRIMARY KEY,
  filter_type TEXT NOT NULL,
  filter_order INTEGER NOT NULL,
  filter_low_hz REAL NOT NULL,
  filter_high_hz REAL NOT NULL,
  window_s REAL NOT NULL,
  step_samples INTEGER NOT NULL,
  eps REAL NOT NULL,
  p0 REAL NOT NULL,
  mad_scale REAL NOT NULL DEFAULT 1.4826,
  s_min REAL NOT NULL,
  map_a REAL NOT NULL,
  map_b REAL NOT NULL,
  smoothing_lambda REAL NOT NULL,
  notch_hz REAL,
  welch_segment_s REAL NOT NULL,
  welch_overlap REAL NOT NULL,
  alpha_low_hz REAL NOT NULL,
  alpha_high_hz REAL NOT NULL,
  amp_threshold_uv REAL NOT NULL,
  hf_ratio_threshold REAL NOT NULL,
  warmup_skip_s REAL NOT NULL,
  calib_min_valid_ratio REAL NOT NULL,
  threshold_percentile REAL NOT NULL,
  hold_time_s REAL NOT NULL
);

CREATE TRIGGER processing_configs_immutable_update
BEFORE UPDATE ON processing_configs
BEGIN SELECT RAISE(ABORT, 'processing_configs jest niezmienna'); END;

CREATE TRIGGER processing_configs_immutable_delete
BEFORE DELETE ON processing_configs
BEGIN SELECT RAISE(ABORT, 'processing_configs jest niezmienna'); END;

CREATE TABLE protocols (
  id INTEGER PRIMARY KEY,
  name TEXT NOT NULL,
  version INTEGER NOT NULL DEFAULT 1,
  processing_config_id INTEGER NOT NULL REFERENCES processing_configs(id),
  UNIQUE (name, version)
);

CREATE TABLE avatar_stages (
  id INTEGER PRIMARY KEY,
  name TEXT NOT NULL UNIQUE,
  required_valid_minutes INTEGER NOT NULL,
  sort_order INTEGER NOT NULL UNIQUE
);

CREATE TABLE manufacturers (
  id INTEGER PRIMARY KEY,
  name TEXT NOT NULL UNIQUE
);

CREATE TABLE device_models (
  id INTEGER PRIMARY KEY,
  manufacturer_id INTEGER NOT NULL REFERENCES manufacturers(id),
  name TEXT NOT NULL,
  channel_count INTEGER NOT NULL,
  sampling_rate_hz REAL NOT NULL,
  UNIQUE (manufacturer_id, name)
);

CREATE TABLE devices (
  id INTEGER PRIMARY KEY,
  device_identifier TEXT NOT NULL UNIQUE,
  model_id INTEGER NOT NULL REFERENCES device_models(id)
);

CREATE TABLE event_types (
  id INTEGER PRIMARY KEY,
  name TEXT NOT NULL UNIQUE,
  description TEXT
);

CREATE TABLE invalid_reasons (
  id INTEGER PRIMARY KEY,
  name TEXT NOT NULL UNIQUE,
  description TEXT
);

CREATE TABLE sessions (
  id INTEGER PRIMARY KEY,
  protocol_id INTEGER NOT NULL REFERENCES protocols(id),
  source_type TEXT NOT NULL CHECK (source_type IN ('device', 'replay', 'mock')),
  device_id INTEGER REFERENCES devices(id),
  created_at TEXT NOT NULL,
  planned_duration_s INTEGER NOT NULL,
  actual_duration_s INTEGER,
  status TEXT NOT NULL DEFAULT 'in_progress'
    CHECK (status IN ('in_progress', 'completed', 'interrupted', 'connection_lost')),
  app_version TEXT NOT NULL,
  firmware TEXT,
  mood_after INTEGER CHECK (mood_after IS NULL OR mood_after BETWEEN 1 AND 5),
  CHECK ((source_type = 'device') = (device_id IS NOT NULL))
);

CREATE TABLE session_channels (
  id INTEGER PRIMARY KEY,
  session_id INTEGER NOT NULL REFERENCES sessions(id),
  channel_name TEXT NOT NULL,
  UNIQUE (session_id, channel_name)
);

CREATE TABLE segments (
  id INTEGER PRIMARY KEY,
  session_id INTEGER NOT NULL REFERENCES sessions(id),
  segment_no INTEGER NOT NULL,
  contract_version INTEGER NOT NULL,
  source_id TEXT NOT NULL,
  fs_nominal_hz INTEGER NOT NULL CHECK (fs_nominal_hz > 0),
  fs_measured_hz REAL,
  chunk_size INTEGER NOT NULL,
  started_at_ms INTEGER NOT NULL,
  end_reason TEXT,
  raw_file_path TEXT NOT NULL,
  UNIQUE (session_id, segment_no)
);

CREATE TABLE segment_gaps (
  id INTEGER PRIMARY KEY,
  segment_id INTEGER NOT NULL REFERENCES segments(id),
  first_sample INTEGER NOT NULL,
  sample_count INTEGER NOT NULL CHECK (sample_count > 0)
);
CREATE INDEX segment_gaps_segment ON segment_gaps (segment_id, first_sample);

CREATE TABLE calibrations (
  id INTEGER PRIMARY KEY,
  session_id INTEGER NOT NULL REFERENCES sessions(id),
  attempt_no INTEGER NOT NULL,
  duration_s INTEGER NOT NULL,
  valid_signal_s INTEGER NOT NULL DEFAULT 0,
  baseline_median REAL,
  baseline_mad REAL,
  threshold_y REAL,
  failure_reason TEXT,
  alpha_ratio REAL,
  alpha_peak_hz REAL,
  succeeded INTEGER NOT NULL DEFAULT 0 CHECK (succeeded IN (0, 1)),
  UNIQUE (session_id, attempt_no)
);

CREATE TABLE blocks (
  id INTEGER PRIMARY KEY,
  session_id INTEGER NOT NULL REFERENCES sessions(id),
  calibration_id INTEGER NOT NULL REFERENCES calibrations(id),
  block_no INTEGER NOT NULL,
  planned_duration_s INTEGER NOT NULL,
  actual_duration_s INTEGER,
  threshold_used REAL NOT NULL,
  valid_signal_s INTEGER NOT NULL DEFAULT 0,
  time_above_threshold_s REAL NOT NULL DEFAULT 0,
  reward_count INTEGER NOT NULL DEFAULT 0,
  control_rating INTEGER CHECK (control_rating IS NULL OR control_rating BETWEEN 1 AND 5),
  UNIQUE (session_id, block_no)
);

CREATE TABLE block_events (
  id INTEGER PRIMARY KEY,
  block_id INTEGER NOT NULL REFERENCES blocks(id),
  event_type_id INTEGER NOT NULL REFERENCES event_types(id),
  occurred_at_ms INTEGER NOT NULL,
  details TEXT
);
CREATE INDEX block_events_block ON block_events (block_id, occurred_at_ms);

CREATE TABLE invalid_intervals (
  id INTEGER PRIMARY KEY,
  block_id INTEGER REFERENCES blocks(id),
  calibration_id INTEGER REFERENCES calibrations(id),
  reason_id INTEGER NOT NULL REFERENCES invalid_reasons(id),
  start_ms INTEGER NOT NULL,
  end_ms INTEGER NOT NULL,
  CHECK ((block_id IS NULL) <> (calibration_id IS NULL)),
  CHECK (start_ms < end_ms)
);

CREATE TABLE session_stats (
  id INTEGER PRIMARY KEY,
  session_id INTEGER NOT NULL UNIQUE REFERENCES sessions(id),
  session_date TEXT NOT NULL,
  valid_minutes REAL NOT NULL,
  blocks_total INTEGER NOT NULL
);

CREATE TABLE settings (
  key TEXT PRIMARY KEY,
  value TEXT NOT NULL
);

CREATE VIEW daily_stats AS
SELECT session_date,
       SUM(valid_minutes) AS valid_minutes,
       SUM(blocks_total) AS blocks_total,
       COUNT(*) AS sessions
FROM session_stats
GROUP BY session_date;
''';

/// Migracje: klucz to wersja docelowa.
const migrationSql = {
  2: '''
ALTER TABLE sessions ADD COLUMN mood_after INTEGER
  CHECK (mood_after IS NULL OR mood_after BETWEEN 1 AND 5);
ALTER TABLE calibrations ADD COLUMN alpha_ratio REAL;
ALTER TABLE calibrations ADD COLUMN alpha_peak_hz REAL;
ALTER TABLE blocks ADD COLUMN control_rating INTEGER
  CHECK (control_rating IS NULL OR control_rating BETWEEN 1 AND 5);
''',
};

/// Dane slownikowe i ustawienia domyslne.
const seedSql = '''
INSERT INTO event_types (name, description) VALUES
  ('reward', 'Nagroda: cel utrzymany przez zadany czas'),
  ('feedback_paused', 'Feedback wstrzymany (okno niewazne)'),
  ('feedback_resumed', 'Feedback wznowiony'),
  ('disconnected', 'Utrata polaczenia z czepkiem');

INSERT INTO invalid_reasons (name, description) VALUES
  ('gap', 'Luka w numeracji probek'),
  ('saturation', 'Nasycenie przetwornika'),
  ('flat', 'Plaski sygnal'),
  ('amplitude', 'Amplituda powyzej progu'),
  ('jump', 'Gwaltowny skok'),
  ('muscle', 'Aktywnosc miesniowa (30 do 40 Hz)');

INSERT INTO avatar_stages (name, required_valid_minutes, sort_order) VALUES
  ('soma', 0, 1),
  ('neuron', 10, 2),
  ('dwa neurony', 30, 3),
  ('mała sieć', 60, 4),
  ('większa sieć', 100, 5),
  ('sieć w zarysie mózgu', 150, 6);

INSERT INTO manufacturers (name) VALUES ('BrainAccess');
INSERT INTO device_models (manufacturer_id, name, channel_count, sampling_rate_hz) VALUES
  (1, 'MINI', 8, 250),
  (1, 'MIDI', 16, 250),
  (1, 'MAXI', 32, 250);

INSERT INTO settings (key, value) VALUES
  ('default_calibration_s', '60'),
  ('default_blocks', '3'),
  ('default_block_s', '180'),
  ('default_break_s', '30');
''';
