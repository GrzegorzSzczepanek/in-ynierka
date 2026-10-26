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
docs/diagrams/      — diagramy (draw.io, PlantUML, DBML, schematy bazy)
docs/formalities/   — wnioski do komisji bioetycznej: szablony i wypełnione
praca/              — źródła pracy (LaTeX); praca_overleaf/ to jej kopia z Overleafa
neurotchi-design/   — makiety UI
notes-and-work/     — szablony dyplomowe, plan literatury
archive/            — stare notebooki i paczki zip
vendor/             — lokalne binaria BrainAccess (ignorowane w git)
```
