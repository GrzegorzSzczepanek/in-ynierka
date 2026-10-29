# in-ynierka

Praca inżynierska: multiplatformowa aplikacja do neurofeedbacku alfa na konsumenckim czepku EEG
(BrainAccess MAXI). Flutter na macOS i Androida, jeden potok DSP w Dart, BrainAccess SDK
(biblioteka C na macOS, Kotlin SDK na Androidzie).

## Struktura

```
app/                        aplikacja Flutter (macOS, Android)
  lib/core/eeg/               EegSource, StreamItem, Mock i Replay
  lib/core/dsp/               filtr, Welch, potok alfa, kalibracja, mapowanie, nagroda
  lib/core/session/           sesja: kontakt, kalibracja, bloki, przerwy, ponowne łączenie
  lib/core/db/                SQLite wg docs/diagrams/schema_v5.dbml, zapis sesji i surowego EEG
  test/                       testy, w tym zgodność z SciPy (test/fixtures)
design/                     makiety UI (neuronek, ekrany), zasady w DESIGN_RULES.md
docs/                       diagramy, notatki, wnioski, bibliografia
praca/                      źródła pracy (LaTeX)
scripts/brainaccess_probe/  sonda SDK BrainAccess (ctypes) i fakty_brainaccess.md
vendor/                     binaria BrainAccess (poza gitem)
archive/                    stara analiza EEGMAT, paczki zip
```

## Testy

```
cd app && flutter test
```

Fixtures DSP odtwarza `app/test/fixtures/generate_fixtures.py` (SciPy).

## Narzędzia czepka (macOS)

Z Terminal.app, w `app/` (nagrania w formacie Replay, odliczanie od pierwszej paczki):

```
dart run tool/brainaccess_check.dart "BA MAXI 012" 15
dart run tool/brainaccess_record.dart "BA MAXI 012" 60 nagrania/sesja1
dart run tool/channel_activity.dart nagrania/sesja1 5
```

## Sonda BrainAccess

Uruchamiaj z Terminal.app (potrzebne uprawnienie Bluetooth), po zdjęciu kwarantanny z SDK w `vendor/`:

```
python3 -u scripts/brainaccess_probe/probe.py --device "BA MAXI 012" --seconds 60 --accel --tag _head
python3 scripts/brainaccess_probe/analyze.py --tag _head
python3 -u scripts/brainaccess_probe/disconnect_test.py --device "BA MAXI 012"
```

Wyniki: `scripts/brainaccess_probe/fakty_brainaccess.md`. Surowe nagrania `probe_dump*.csv` są poza gitem.
