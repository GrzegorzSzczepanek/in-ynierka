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

## Uruchomienie na macOS

Wymaga pełnego Xcode (z App Store), bo `flutter build macos` nie działa na samym Command Line Tools:

```
sudo xcode-select --switch /Applications/Xcode.app/Contents/Developer
sudo xcodebuild -runFirstLaunch
flutter doctor
```

```
cd app && flutter run -d macos
```

Całą konfigurację czepka robi się w aplikacji, na ekranie Ustawienia (ikona koła zębatego na ekranie głównym):

- Źródło: Demo (sygnał symulowany) albo Czepek BrainAccess.
- Szukaj czepka: skanuje Bluetooth i zapamiętuje wybrane urządzenie (jedno znalezione wybiera się samo).
- Biblioteka `libbacore`: szukana automatycznie (`vendor/mac_os_testing/...`, pakiet aplikacji), ścieżkę można też wpisać ręcznie.
- Nazwy kanałów: wg tabeli producenta albo numery ch1..ch32.
- Kanały treningowe: wybór kanałów z kontaktem dla każdego protokołu; BIAS ustawiany jest automatycznie.

Zdejmij kwarantannę z SDK w `vendor/` (Gatekeeper). Okno desktopowe jest responsywne; układ telefonu poniżej ok. 900 dp.
`libbacore.dylib` jest dołączana do pakietu aplikacji przy każdym buildzie (faza „Embed libbacore” z `vendor/`), więc gotowy `.app` (`flutter build macos --release`, wynik w `app/build/macos/Build/Products/Release/`) działa samodzielnie, także w piaskownicy. Przy pierwszym połączeniu macOS zapyta o zgodę na Bluetooth.

## Android

```
cd app && flutter run -d <telefon>
```

Czepek obsługuje SDK Kotlin (BrainAccessKit 2.2.0) przez most `BrainAccessBridge.kt` i kanał platformy. Gradle sam rozpakowuje bibliotekę z `archive/BrainAccessKit-2.2.0.zip` do `vendor/android/libs` (poza gitem). Konfiguracja jest w tym samym ekranie Ustawienia: „Szukaj czepka” prosi o zgodę na Bluetooth i skanuje, reszta jak na macOS. Na Androidzie nie ma pola ścieżki biblioteki.

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
