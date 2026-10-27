# in-ynierka

Analiza sygnałów EEG ze zbioru [EEGMAT (PhysioNet)](https://physionet.org/content/eegmat/1.0.0/)
pod kątem klasyfikacji stanu poznawczego (spoczynek vs zadanie arytmetyczne) oraz redukcji
liczby elektrod do zestawu konsumenckiego.

## Struktura projektu

```
in-ynierka/
├── 01_eda_and_signal_quality.ipynb     — Rozdział 1: EDA, sygnał w czasie/częstotliwości, jakość danych
├── 02_ml_and_channel_reduction.ipynb   — Rozdział 2: ekstrakcja cech, PCA, ML, redukcja kanałów
├── eegmat/                             — pakiet z logiką obliczeniową
│   ├── io.py                            wczytywanie plików EDF
│   ├── preprocess.py                    czyszczenie kanałów, montaż 10/20
│   ├── dataset.py                       epokowanie i budowa (X, y, groups)
│   ├── features.py                      ekstrakcja cech (widmo, Hjorth, entropia) + wybór kanałów
│   ├── signal_analysis.py               spektrogramy, dashboardy Rest vs Task, analiza alfa ERD
│   ├── demographics.py                  wykresy demograficzne (płeć, jakość liczenia)
│   ├── plots.py                         wykresy rozkładu liczby odejmowań i podziałów zbioru
│   ├── quality.py                       weryfikacja artefaktów (peak-to-peak) i balansu klas
│   ├── models.py                        walidacja GroupKFold/StratifiedKFold, porównanie zestawów kanałów, PCA, Count quality
│   ├── connectivity.py                  łączność funkcjonalna między kanałami (korelacje, teoria grafów)
│   └── splits.py                        podział badanych na train/val/dev/holdout
└── datasets/                            dane wejściowe (nieśledzone w git)
```

Notebooki nie zawierają logiki obliczeniowej — wołają funkcje z `eegmat/` i komentują wyniki.
Kod eksploracyjny / roboczy trzymamy w modułach, żeby dało się go testować i reużywać.

## Uruchomienie

Wybierz kernel `Python (in-ynierka)` w Jupyterze / VS Code, upewnij się że dane EEGMAT są
w `datasets/physionet.org/files/eegmat/1.0.0/`, i odpal notebooki w kolejności 01 → 02.

## Pozostałe katalogi

```
docs/diagrams/      — diagramy (draw.io, PlantUML, DBML, schematy bazy); aktualne DSP: dsp_A_jakosc_v3, dsp_B_feedback_v3
docs/formalities/   — wnioski do komisji bioetycznej: szablony i wypełnione
praca/              — źródła pracy (LaTeX)
neurotchi-design/   — makiety UI
notes-and-work/     — szablony dyplomowe, plan literatury
scripts/brainaccess_probe/ — sonda SDK BrainAccess (ctypes, libbacore) i fakty_brainaccess.md
archive/            — stare notebooki i paczki zip (w tym kopia pracy z Overleafa)
vendor/             — lokalne binaria BrainAccess (ignorowane w git)
```

## Sonda BrainAccess

Skrypty w `scripts/brainaccess_probe/` mierzą, co faktycznie dostarcza SDK (`libbacore` 4.0.0, macOS).
Uruchamiaj z Terminal.app (aplikacja musi mieć uprawnienie Bluetooth), po zdjęciu kwarantanny z SDK w `vendor/`:

```
python3 -u probe.py --device "BA MAXI 012" --seconds 60 --accel --tag _head
python3 analyze.py --tag _head
python3 -u disconnect_test.py --device "BA MAXI 012"
```

Wyniki: `fakty_brainaccess.md`. Surowe nagrania `probe_dump*.csv` są poza gitem.
