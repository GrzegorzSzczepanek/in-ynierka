# Pomiary i weryfikacja względem kodu (NEUROtchi)

Data: 2026-11-16. Sprzęt: MacBook Air M3 (8 rdzeni), macOS 15.6. Flutter 3.47.7, Dart 3.13.5, sqlite3 (pakiet) 3.8.0, SciPy 1.16.3.
Kod produkcyjny nie był zmieniany. Dodane pliki: `app/test/benchmark/`, `app/test/core/{quality_latency,spec_constants,dsp_accuracy,replay_feature,disconnect_timing}_test.dart`, `app/test/fixtures/{dsp_reference_3hz.json,generate_fixtures_3hz.py,fake_bacore_full.c}`, `scripts/pomiary.sh`.
Powtórzenie każdego pomiaru: `scripts/pomiary.sh <nazwa> [id urządzenia]` (nazwy w tabeli).

**Pixel 9a (GrapheneOS, Android 17, API 37)** został podłączony później i zmierzony w trybie profile przy włączonym i odblokowanym ekranie. Uwaga: pierwszy przebieg DSP przy wygaszonym ekranie dał 15 razy gorsze wyniki (p50 9,5 ms zamiast 0,6 ms), więc ekran musi być włączony; wyniki z wygaszonym ekranem odrzucono. Logcat ucinał długie linie, dlatego `bench_app.dart` dzieli wyniki na kawałki.
**Pomiary UI na macOS (FPS, render) nie udały się**: ekran Maca był zablokowany (`IOConsoleLocked = true`), więc okno aplikacji jest zasłonięte, a macOS usypia aplikację (App Nap) i nie renderuje klatek. Dwa podejścia kończyły się timeoutem (sesja nie przechodziła dalej niż kalibracja). Potrzebny jest odblokowany ekran i okno na wierzchu.

## Tabela do wklejenia

Tryb: profile (AOT) tam, gdzie podano; „test” = `flutter test` (JIT, deterministyczne, bez zegara ściennego).

| Wymaganie | Wartość zmierzona | Jednostka | Platforma, tryb | Metoda |
|---|---|---|---|---|
| WN 2.3 klatki/s na ekranie treningu (190 s, 1882 klatki) | 10,0 (UI odświeża się przy każdej paczce, 10/s) | kl./s | Pixel 9a, profile | `bench_app fps`, Mock realtime |
| WN 2.3 build klatki (Pixel) | p50 6,5 / p95 9,3 / max 13,4 | ms | Pixel 9a, profile | j.w. |
| WN 2.3 raster klatki (Pixel) | p50 11,8 / p95 14,5 / max 15,6 | ms | Pixel 9a, profile | j.w. |
| WN 2.3 klatki z build lub raster >16,7 ms (Pixel) | 0% (z całkowitym czasem klatki, wliczając vsync: 74,5%) | % | Pixel 9a, profile | j.w. |
| WN 2.3 macOS | **nie zmierzono** (ekran zablokowany) | — | macOS | — |
| WN 2.2 czas obliczeń DSP na okno (filtr+jakość+Welch+EMA), 2 kanały, n=461 | p50 0,38 / p95 0,46 / max 5,07 | ms | macOS, profile | `bench_app dsp`, MockSource 120 s |
| WN 2.2 to samo, 4 kanały, n=461 | p50 0,76 / p95 0,86 / max 1,48 | ms | macOS, profile | j.w. |
| WN 2.2 test opóźnień z aplikacji (`ResearchMonitor.runTest`, 30 s, n=110) | p50 0,37 / p95 0,40 | ms | macOS, profile | j.w. |
| WN 2.2 czas przetworzenia jednej paczki 25 próbek (n=1200) | p50 0,10 / p95 0,24 / max 5,28 | ms | macOS, profile | j.w. |
| WN 2.2 na żywo w trybie badacza: DSP razem (Pixel, n=462) | p50 7,3 / p95 9,9 / max 11,3 | ms | Pixel 9a, profile | `bench_app latency`, ekran badacza 120 s |
| WN 2.2 render (setState → koniec klatki, ekran badacza, Pixel, n=749) | p50 33,1 / p95 42,5 / max 46,1 | ms | Pixel 9a, profile | j.w. |
| WN 2.2 DSP izolowane, Pixel, 2 kanały (n=461) | p50 0,62 / p95 0,93 / max 3,48 | ms | Pixel 9a, profile | `bench_app dsp` |
| WN 2.2 DSP izolowane, Pixel, 4 kanały | p50 1,26 / p95 1,80 / max 2,82 | ms | Pixel 9a, profile | j.w. |
| WN 2.2 pakiet 25 próbek → przetworzony, opóźnienie pakiet→koniec klatki treningu (Pixel, n=1901) | p50 20,8 / p95 29,9 / max 43,5 | ms | Pixel 9a, profile | `bench_app fps` |
| WN 2.2 render macOS | **nie zmierzono** (ekran zablokowany) | — | macOS | — |
| WF-7 od próbki do werdyktu okna (czas próbek, bez renderu) | p50 0,18 / p95 0,30 / max 0,35 | s | z kodu + test | wyliczenie z okna/kroku/paczki, potwierdzone `quality_latency_test` |
| WF-7 dochodzi render ≤ 1 klatka | ≤ 16,7 (przy 60 Hz) | ms | macOS | z częstotliwości odświeżania, nie zmierzone |
| WF-3 wykrycie artefaktu (nasycenie, seria >100 µV, impuls ≥1000 µV) | max 0,35–0,37 (p50 0,18–0,20) | s | test | `quality_latency_test` |
| WF-3 wykrycie płaskiej linii | 2,01–2,34 | s | test | j.w. |
| WF-3 wykrycie luki w numeracji próbek | max 0,40 | s | test | j.w. |
| WF-3 etykieta „średni” na pasku jakości (ciągły artefakt) | 1,04–1,38 (płaska linia 3,03–3,36) | s | test | j.w. |
| WF-12 / WN 2.5 `history()`, 200 sesji, n=300 | p50 0,32 / p95 0,37 / max 0,40 | ms | macOS, profile | `bench_app history` |
| WF-12 / WN 2.5 `progressData()` (dane ekranu Postęp), n=300 | p50 0,48 / p95 0,55 / max 1,07 | ms | macOS, profile | j.w. |
| WF-12 / WN 2.5 `homeData()`, n=300 | p50 0,23 / p95 0,27 / max 0,39 | ms | macOS, profile | j.w. |
| WF-12 / WN 2.5 `history()`, 200 sesji (Pixel) | p50 0,52 / p95 0,72 / max 1,06 | ms | Pixel 9a, profile | j.w. |
| WF-12 / WN 2.5 `progressData()` (Pixel) | p50 0,79 / p95 1,00 / max 1,23 | ms | Pixel 9a, profile | j.w. |
| WN 2.4 zapis 60 min, 32 kanały, przyspieszony | 900000 próbek wysłanych = 900000 wierszy CSV, numeracja ciągła, 0 braków | próbki | macOS, profile | `bench_app writer` |
| WN 2.4 czas zapisu (przyspieszony) | 25,1 (strumień 7,2 + zamknięcie 17,9); 143× szybciej niż czas rzeczywisty | s | macOS, profile | j.w. |
| WN 2.4 zapis 60 min, 32 kanały, przyspieszony (Pixel) | 900000 = 900000 wierszy, ciągła numeracja, 0 braków, 192 s (strumień 17,2 s), plik 550,7 MB, max RSS 897 MB | próbki | Pixel 9a, profile | `bench_app writer` |
| WN 2.4 przebieg w czasie rzeczywistym | **nie zmierzono** (przerwany po ok. 15 min) | — | macOS, profile | `scripts/pomiary.sh zapis-realtime` |
| WF-9 próby ponownego połączenia | 3, odstęp 15 s **przed każdą próbą** | — | kod + test | `spec_constants_test` |
| WF-9 próg ciszy = rozłączenie (macOS) | 3,0 (wykryte po 3,07) | s | test z atrapą C | `disconnect_timing_test` |
| WN 3.1 filtr vs SciPy (lowHz 1 / lowHz 3) | max \|Δ\| 2,4e-12 / 9,3e-13 | µV | test | `dsp_accuracy_test` |
| WN 3.1 Welch, max błąd względny po binach (1 / 3) | 3,1e-9 / 2,3e-8 | — | test | j.w. |
| WN 3.1 moc alfa, błąd względny (1 / 3) | 4,2e-16 / 5,5e-16 | — | test | j.w. |
| WN 3.2 replay: różnica cechy | 0 (identyczne bitowo), 460 okien | — | test | `replay_feature_test` |
| Pełny `flutter test` | 115 testów, wszystkie przeszły, 61 s (z równoległym pomiarem w tle) | — | macOS, JIT | `flutter test` |

## 1. WN 2.3 (FPS)
**Pixel 9a, profile, ekran treningu z `MockSource(realtime)` przez 188 s (1882 klatki):**
```
fps 10,01 (pakiety w oknie: 1901, czyli UI przerysowuje się przy każdej paczce, 10/s; Flutter nie renderuje bez zmian)
build   p50 6,53 p95 9,31 p99 10,91 max 13,45 ms
raster  p50 11,80 p95 14,47 p99 14,80 max 15,60 ms
totalSpan p50 20,05 p95 24,09 max 37,39 ms
klatki z build >16,7 ms: 0%; raster >16,7 ms: 0%; max(build, raster) >16,7 ms: 0%
klatki z totalSpan >16,7 ms: 74,5% (totalSpan zawiera czas oczekiwania na vsync i kolejkę, nie jest miarą janku wg Flutter)
opóźnienie od dojścia paczki do końca klatki UI: p50 20,8 p95 29,9 max 43,5 ms (n=1901)
RSS 328 → 341 MB; odświeżanie ekranu 60 Hz, 1080x2424, dpr 2,625
```
macOS niezmierzone (ekran zablokowany). Kod: `app/test/benchmark/bench_app.dart` tryb `fps` uruchamia prawdziwy `SessionFlowScreen` z `MockSource(realtime)`, mierzy w oknie treningu 190 s: liczbę klatek/s, build i raster (p50, p95, p99, max), odsetek klatek >16,7 ms oraz opóźnienie pakiet→koniec klatki UI. Komenda: `scripts/pomiary.sh fps macos` (odblokowany ekran) lub `scripts/pomiary.sh fps <id Pixela>`.

## 2. WN 2.2 i WF-7 (opóźnienie)
Surowe wyjście (macOS, profile, `BENCH=dsp`):
```
2ch n=461: filter p50 .257 p95 .276 | quality .066/.077 | welch .055/.094 (max 4.735) | total p50 .382 p95 .462 max 5.074 ms
4ch n=461: total p50 .76 p95 .855 max 1.479 ms
runTest_30s_app (n=110): Razem DSP p50 0.3675 p95 0.39575; krok okna 256 ms; Odbiór→bufor i Render: brak danych
```
**Pixel 9a, profile, DSP izolowane** (`BENCH=dsp`): 2 kanały razem p50 0,62 / p95 0,93 / max 3,48 ms (n=461; filtr p50 0,43), 4 kanały p50 1,26 / p95 1,80 / max 2,82 ms, `runTest` 30 s p50 0,65 / p95 0,97 ms.
**Pixel 9a, profile, tryb badacza na żywo** (`BENCH=latency`, ekran badacza z Mock realtime przez 120 s): DSP razem p50 7,26 / p95 9,86 / max 11,27 ms (n=462; filtr p50 4,67, jakość 1,60, Welch 0,89), czyli ok. 12 razy więcej niż w pomiarze izolowanym, bo wątek UI jednocześnie rysuje ekran badacza. Render (setState → koniec klatki, raport aplikacji „Render (Flutter)”) p50 33,6 / p95 42,8 ms, w moim zapisie n=749: p50 33,1 / p95 42,5 / max 46,1 ms; build klatki p50 22,4 / p95 27,2 ms, raster p50 7,8 / p95 11,6 ms. Przybliżony koszt „DSP + render” na tym ekranie to ≈ 41 ms w medianie, co jest rzędu wcześniej podawanych 76/124 ms (tylko podobny rząd wielkości; nie wiem, jak je zmierzono).
Test JIT (`flutter test`, 60 s): razem p50 0,368 / p95 0,490 ms, czyli te same rzędy wielkości co w AOT.
**Poprzednich 76 ms (p50) i 124 ms (p95) nie udało się odtworzyć** w obliczeniach DSP (0,4 ms). Nie wiem, co wtedy mierzono (w repozytorium nie ma tych liczb). Możliwe, że był to czas obejmujący render albo inny tryb; to tylko hipoteza. Na macOS render nie został zmierzony (ekran zablokowany); `scripts/pomiary.sh opoznienia macos` przy odblokowanym ekranie.

Składowe opóźnienia od próbki do reakcji (z kodu): wyniki liczone są co 64 próbki (256 ms, `processing_config.dart:9`), a paczka niesie 25 próbek (100 ms). Wyliczenie dla każdej próbki (okno kończy się co 64 próbki, wynik po dojściu paczki): min 0,004, p50 0,18, p95 0,30, max 0,352 s, średnio 0,178 s. Do tego obliczenia ≈0,4 ms i render ≤1 klatka. **Wymaganie „≤ 0,2 s” (WF-7) jest spełnione w medianie, ale nie w p95 ani w maksimum (0,35 s)**; ponadto sama cecha obejmuje 2 s sygnału (opóźnienie grupowe okna). Dla czepka dochodzi opóźnienie BLE, które da się zmierzyć tylko z czepkiem (etap „Odbiór → bufor” działa dla źródeł z czasem epoch).

## 3. WF-3 (czas zmiany stanu jakości)
Skąd wynika: okno 2 s (500 próbek), ocena co 64 próbki (256 ms), paczka 25 próbek (100 ms); ocena jakości jest binarna, bez wygładzania (`alpha_pipeline.dart:244-275`). Pasek jakości w UI to udział ważnych okien w ostatnich 20 (≈5,1 s): `session_controller.dart:353`; etykieta „średni” od <0,8, „słaby” od <0,5 (`format.dart:17-23`); pasek czerwony przy ≤2 z 5 segmentów. Ekran treningu pokazuje „sygnał niewiarygodny” od pierwszego nieważnego okna.
Test (`quality_latency_test.dart`, sygnał 10 Hz + szum, artefakt w 229 położeniach względem siatki okien; czas = czas próbek, bez renderu):
```
impuls_300uV   : niewykryty (64/64)
impuls_1000uV  : wykrycie p50 0.186 max 0.336 s, powod=amplitude
impuls_10000uV : wykrycie p50 0.174 max 0.336 s
seria_200uV_1s : wykrycie p50 0.196 p95 0.318 max 0.368 s; powrot do waznych okien 2.02-2.36 s po koncu; etykieta "srednio" po 1.04-1.38 s, "slabo" po 2.58-2.92 s
nasycenie_0_4s : wykrycie p50 0.176 max 0.348 s (saturation); powrot 3.18-3.52 s po koncu
plaska_linia   : wykrycie 2.012-2.340 s (flat); etykieta "srednio" po 3.03-3.36 s
miesnie_35Hz_25uV: wykrycie 0.508-0.856 s (muscle)
luka_1_paczki  : wykrycie p50 0.300 max 0.400 s; powrot do waznych okien 3.30 s od luki
```
Wnioski: werdykt „okno nieważne” pojawia się w ≤0,4 s dla amplitudy, nasycenia, luki i mięśni, ale **płaska linia dopiero po ≈2,0–2,3 s** (okno musi być całe płaskie), a etykieta paska dla niej po ≈3,0–3,4 s, czyli powyżej 3 s z pracy. **Impuls 300 µV nie jest wykrywany**: progi 100 µV działają na sygnale po filtrze 3–40 Hz, który tłumi krótkie piki. Powrót do stanu poprawnego trwa 2–3,5 s (okno 2 s + filtr) i do 3,3 s po luce (reset filtrów, `alpha_pipeline.dart:91`).

## 4. WF-12 i WN 2.5 (historia i wykresy)
Baza plikowa, 200 sesji po 3 bloki (600 bloków, 7200 zdarzeń, 3600 przedziałów nieważnych, 200 statystyk), 540 KB, wygenerowana w 209 ms. macOS, profile, n=300 po 30 rozgrzewkowych:
```
history()      cold 0.692 | p50 0.320 p95 0.369 p99 0.378 max 0.404 ms
dailyStats()   p50 0.111 p95 0.132 max 0.175
progressData() p50 0.484 p95 0.545 max 1.074 (cold 0.515)
homeData()     p50 0.226 p95 0.268 max 0.389
```
To tylko czas zapytań i przygotowania danych; **w aplikacji nie ma wykresów postępu** (rozdz. B), więc „wykres w 1 s” nie ma czego dotyczyć; czas renderu listy nie zmierzony. Pixel 9a, profile, te same dane: `history()` p50 0,516 / p95 0,716 / max 1,06 ms (zimne pierwsze wywołanie 2,8 ms), `progressData()` p50 0,792 / p95 0,997 / max 1,23 ms, `homeData()` p50 0,384 / p95 0,457 ms, wygenerowanie bazy 532 ms.

## 5. WN 2.4 (zapis surowego EEG)
Ścieżka produkcyjna `SessionPersistence` → `RecordingWriter`, MockSource 32 kanały (jak MAXI), 250 Hz, 60 min = 36000 paczek.
**Przebieg przyspieszony** (writer nie zależy od zegara; Mock generuje bez czekania): wysłano 900000 próbek, w CSV 900000 wierszy, pierwszy numer 0, ostatni 899999, 0 nieciągłości, 0 wierszy o złej liczbie kolumn, sumy kontrolne kanałów 1 i 32 identyczne bit w bit. Czas 25,06 s (strumień 7,24 s, zamknięcie i zapis na dysk do końca 17,8 s), plik 550,7 MB. Pamięć rosła liniowo (149 MB w 2. min sygnału → 714 MB max): przy przyspieszeniu bufor `IOSink` nie ma przeciwciśnienia; w czasie rzeczywistym nie powinno to występować (hipoteza, niezweryfikowana).
**Pixel 9a, profile, przebieg przyspieszony:** 900000 wysłanych, 900000 wierszy, numeracja 0–899999 bez nieciągłości, 0 wierszy o złej liczbie kolumn, sumy kontrolne zgodne; strumień 17,2 s, całość z zamknięciem pliku 191,8 s (zapis na pamięć telefonu), plik 550,7 MB, RSS max 897 MB (przy przyspieszeniu bufor rośnie bez przeciwciśnienia).
**Przebieg w czasie rzeczywistym, w tle** (60 min, ekran zablokowany, więc to też test pracy w tle):
**Przerwany po ok. 15 min na prośbę użytkownika, wynik niedostępny** (nie weryfikowano ciągłości ani liczby próbek). Komenda do powtórzenia: `scripts/pomiary.sh zapis-realtime macos` (ok. 65 min).

## 6. WF-9 i WF-1 (rozłączenia)
Stałe (kod, potwierdzone `spec_constants_test.dart`): `connectAttempts = 3`, `reconnectAttempts = 3`, `reconnectIntervalS = 15` (`session_models.dart:37-39`). **15 s to odstęp czekania przed każdą próbą ponownego połączenia** (`session_controller.dart:241-242`), nie limit czasu próby. Test z licznikiem opóźnień: odstępy `[15, 15, 15, 15]` s (3 próby nieudane, ręczne ponowienie, 1 udana), fabryka źródła wywołana 5 razy. Pierwsze połączenie ma 3 próby bez odstępu. Czas samej próby: macOS brak limitu w aplikacji (blokujące `connect` SDK), Android skan do 12 s (`BrainAccessBridge.kt`, `CONNECT_SCAN_MS = 12000`). Zatem po utracie przed ekranem „ponów” mija ≥45 s plus czasy łączenia.
Próg ciszy: `_silenceLimit = 3 s` (`brainaccess_mac_source.dart:261`), sprawdzany timerem co 500 ms (linia 300). Test z atrapą biblioteki C (`disconnect_timing_test.dart`): 250 próbek, potem cisza, zdarzenie `data_timeout` po **3,067 s**; więc wykrycie 3,0–3,5 s. **Android nie ma takiego strażnika** (kod `brainaccess_android_source.dart`: brak timera), polega na stanie SDK.
Maksymalna utrata próbek: (a) przed wykryciem do 3,5 s ≈ 875 próbek (3 s ≈ 750) nie dotrze do aplikacji; (b) **od rozłączenia do ponownego połączenia nic nie jest zapisywane** (nowy segment/plik, `session_persistence.dart:55`), czyli ≥15 s ≈ 3750 próbek plus czas łączenia (SDK: ok. 7,3 s, pomiar n=1 w `fakty_brainaccess.md`). Twierdzenie „utrata danych nie przekracza 3 s” jest więc prawdziwe tylko dla okna wykrycia, nie dla całej przerwy. Próbki odebrane przed rozłączeniem są zapisane.
Nowy test z `session_test.dart` („rozłączenie w drugim bloku: trening idzie dalej od kolejnego bloku”): **przeszedł**; cały plik 11/11. Test opiera się na Twojej niezatwierdzonej zmianie `_blockNo = _blocks.length` (`session_controller.dart:345`); w zatwierdzonej wersji po powrocie numeracja bloków zaczynała się od 0.

## 7. WN 3.1 i WN 3.2 (zgodność)
`dsp_reference_test` (istniejący, próg 1e-6): 2/2 przeszły; nie wypisuje błędów, więc dodano `dsp_accuracy_test.dart`:
```
[dsp_reference.json, lowHz=1.0]  filtr 2000 próbek: max|d|=2.359e-12 rms=1.06e-12 (7.97e-14 szczytu)
  Welch: max bezwzgl. 8.5e-14, max wzgl. po binach 3.14e-9; alfa 4.2e-16; 30-40 Hz 8.9e-16; 1-40 Hz 4.1e-16
[dsp_reference_3hz.json, lowHz=3.0] filtr 4000 próbek: max|d|=9.288e-13 rms=2.49e-13
  Welch: max wzgl. 2.32e-8; alfa 5.5e-16; 30-40 Hz 8.7e-16; 3-40 Hz 2.1e-16; cecha ln(P+eps): różnica 1.8e-15
```
Dodatkowo potok produkcyjny kontra ręczna implementacja (Welch 250/125/512, alfa 8–12 Hz): różnica cechy 0,0 w 40 oknach.
**Uwaga**: filtr w aplikacji to kaskada górnoprzepustowego 4. rzędu i dolnoprzepustowego 4. rzędu (`biquad.dart`), nie `butter(4,[3,40],'band')`. Różnią się o max 3,41 µV = 8,0% szczytu sygnału testowego (moc alfa 1,3e-4 względnie). Zgodność z SciPy dotyczy kaskady.
Replay: wcześniej był tylko test równości pakietów (`recording_writer_test`). Dodano `replay_feature_test.dart`: sesja 120 s z lukami i artefaktem zapisana przez `RecordingWriter`, wczytana i odtworzona: 460 okien (425 ważnych, 35 nieważnych), te same `sampleEnd`, powody, cechy i pik; **max różnica 0**. Na poziomie `SessionController`: identyczne baseline, progi, `meanY`, nagrody, zdarzenia, `yTrace` (różnica 0).

## 8. Pełny `flutter test`
115 testów, wszystkie przeszły, 61 s (wcześniej 98 testów w 15 s; nowy `quality_latency_test` trwa ≈57 s). Pomiar wykonany przy równoległym przebiegu w czasie rzeczywistym w tle, więc czas jest zawyżony.

## Część B: twierdzenia a kod

| Twierdzenie | Wartość w kodzie | Plik:linia | Zgodne |
|---|---|---|---|
| 6 stadiów awatara: 0, 10, 30, 60, 100, 150 min | soma 0, neuron 10, dwa neurony 30, mała sieć 60, większa sieć 100, sieć w zarysie mózgu 150 | `schema.dart:237-243` | tak |
| schemaVersion 3, migracje przez `PRAGMA user_version` | `schemaVersion = 3`; migracje 2 i 3 w mapie; wersja czytana i zapisywana PRAGMA | `schema.dart:2,207-218`; `app_database.dart:19-40` | tak |
| `mood_after` usunięte | migracja 3 `DROP COLUMN`; brak w `schemaSql` i w kodzie | `schema.dart:216-218` | tak |
| nagłówek „wersja 5” | komentarz w kodzie `schema.dart:1` („Schemat wersja 5 (docs/diagrams/schema_v5.dbml)”), `docs/diagrams/schema_v5.dbml:2`, `README.md:14`; pliki `schemat_bd_5.png/svg`, `Claude outputs/przypadki_uzycia_v5.drawio`. To numer wersji dokumentacji, nie `user_version` (3) | j.w. | **niespójne nazewnictwo** |
| `mood_after` w dokumentach | `docs/notatki.tex`, `schema_v4.dbml`, `schemat.svg`, `database-model.svg`, `przypadki_uzycia(_v2).drawio` (starsze wersje); w `schema_v5.dbml` brak | — | nieaktualne tylko starsze pliki |
| wzmocnienie kanałów | w `app/` i `android/` brak wywołań `set_channel_gain`/`setChannelGain`; `native/` nie istnieje. Android: `cfg.copy(active, bias, srate)` zachowuje `gain` z `currentConfig()` (`BrainAccessBridge.kt:123-131`; `DeviceConfig` ma pole `gain`). Domyślne 8 ustawia czepek/SDK (poza kodem aplikacji: kod gainu 4 = X8 w logu, `scripts/brainaccess_probe/fakty_brainaccess.md`); wartości na Androidzie nie odczytano | — | tak (aplikacja gainu nie zmienia) |
| Butterworth 4. rzędu 3–40 Hz | HP4 + LP4 w kaskadzie, nie filtr pasmowy | `processing_config.dart:5-7`, `biquad.dart` | częściowo (sformułowanie) |
| notch 50 Hz, okno 2 s, krok 64 | 50, 2,0, 64 | `processing_config.dart:9,17` | tak |
| Welch segment 250, nfft 512 | segment 1 s = 250, nfft = 2 × 256 = 512, overlap 0,5 | `alpha_pipeline.dart:105-113` | tak |
| pasmo alfa 8–12 Hz | 8,0–12,0 (pik szukany w 7–13) | `processing_config.dart:20-21`, `alpha_pipeline.dart:236` | tak |
| ε, P0, s_min, a, b, λ | 1e-6, 1,0, 0,05, −2, 2, 0,1 | `processing_config.dart:10-16` | tak |
| percentyl 60, utrzymanie 1,5 s | 60, 1,5; nagroda po 6 oknach = 1,536 s | `processing_config.dart:26-27`, `calibration.dart:126` | tak |
| blokada nagrody | `_armed`, ponowne uzbrojenie po spadku poniżej progu | `calibration.dart:116-128` | tak |
| próg amplitudy 100 µV, skok 100 µV | oba na sygnale po filtrze | `alpha_pipeline.dart:261-262` | tak (uwaga: filtr tłumi krótkie piki) |
| udział 30–40 Hz >0,25 | licznik 30–40, mianownik `filterLowHz`–`filterHighHz` = 3–40 (komentarz w `processing_config.dart` mówi 1–40) | `alpha_pipeline.dart:266-272` | tak, komentarz nieaktualny |
| nasycenie 562000 µV, płaska linia 0,5 µV | 562000,0 i 0,5 (zakres surowy w oknie) | `alpha_pipeline.dart:55-56,249,253` | tak |
| pominięcie pierwszych 5 s kalibracji | okna, których **początek** ≥5 s (`tSec − windowS ≥ 5`) | `calibration.dart:73` | tak |
| ważność kalibracji 0,9 | 0,9 | `calibration.dart:82` | tak |
| reaktywność alfa min 1,2, max 2 powtórzenia | 1,2 i 2 | `session_models.dart:42-43` | tak |
| kalibracja 60 s otwarte, 30 s zamknięte | 60 i 30 (limit 150 s) | `session_models.dart:30-31,40` | tak |
| 3 bloki po 3 minuty | 3 × 180 s, przerwa 30 s (wartości mogą nadpisać ustawienia w bazie) | `session_models.dart:32-34` | tak |
| minSdk 21 | `minSdk = flutter.minSdkVersion` = **24** w Flutter 3.47.7; APK 0.1.4: `minSdkVersion:'24'`, targetSdk 36 | `android/app/build.gradle.kts:22`, aapt2 | **nie (24)** |
| macOS deployment target 12.0 | 12.0; `libbacore` minos 11.0; zbudowana aplikacja min 12.0 | `project.pbxproj:494,576,626` | tak |
| najniższa wersja, na której się buduje | Android API 24 (buduje się; uruchomienia poniżej Androida 17 nie testowano), macOS 12.0 | j.w. | — |
| wyciszanie dźwięku nagrody | w aplikacji nie ma żadnego dźwięku (brak audio, brak ustawienia) | brak trafień w `lib/` | **brak** |
| pliki lokalizacji, domyślnie polski | brak `l10n`, `intl`, plików `.arb`; teksty zapisane na stałe po polsku | `lib/` | **brak** |
| eksport CSV | `S-NNNN_events.tsv` (kalibracje, bloki, zdarzenia, przedziały nieważne, luki), `S-NNNN_segK_raw.csv`, `S-NNNN_segK_raw.json`; **TSV, nie CSV; bez osobnej cechy w czasie i bez pliku statystyk** | `session_exporter.dart:20-41` | częściowo |
| usuwanie danych użytkownika (WN 5.3) | brak funkcji | brak trafień | **brak** |
| kopia zapasowa (WN 5.4) | brak (jest tylko eksport sesji) | brak | **brak** |
| `device_identifier` | tabela `devices.device_identifier TEXT UNIQUE`, wypełniana nazwą BLE czepka (np. „BA MAXI 012”), nie numerem seryjnym | `schema.dart:72`, `session_repository.dart:160-179` | tak (z zastrzeżeniem) |
| stała luminancja ekranu treningu, ciągła informacja zwrotna | ciągły jest pasek i liczba wyniku (`PkBar(value: y)`) oraz wykres; mimika neuronka dyskretna (4 nastroje wg progu); brak mapowania wyniku na rozmiar, ruch ani luminancję | `training_screen.dart:46-52,155` | częściowo |
| WF-3: jakość „dla każdego kanału” (kontakt, płaska linia, amplituda, szum) | kontakt per kanał z urządzenia; kontrola płaska/amplituda/szum to jeden werdykt okna dla kanałów treningowych, bez stanu per kanał | `alpha_pipeline.dart:244-275`, `head_map.dart` | częściowo |
| WF-3: zmiana stanu w 3 s | patrz sekcja 3; płaska linia i etykieta paska ≈3,0–3,4 s | — | częściowo |
| WF-7: opóźnienie ≤0,2 s | p50 0,18 s, p95 0,30, max 0,35 (+ render) | sekcja 2 | **nie** (p95, max) |
| WF-9: 3 próby „trwające po 15 s” | 15 s to odstęp przed próbą; długość próby bez limitu (macOS) lub skan 12 s (Android) | `session_controller.dart:241` | częściowo |
| WF-9: utrata danych ≤3 s | wykrycie ciszy 3,0–3,5 s (tylko macOS); przerwa do ponownego połączenia ≥15 s niezapisana | sekcja 6 | częściowo |
| WF-1: limit czasu połączenia 15 s | nie ma limitu czasu połączenia na poziomie aplikacji | `session_controller.dart:234-258` | **nie** |
| WF-11: sortowanie i filtrowanie po datach, czas powyżej progu i nagrody w liście | lista `recent.take(8)` z czasem ważnym i liczbą bloków; brak sortowania, filtra, nagród i czasu nad progiem w liście | `progress_screen.dart:178`, `SessionRow` | **nie** |
| WF-12: wykresy czasu ważnego, nad progiem, wskaźnika alfa; „w 1 s” | ekran Postęp: stadia awatara, pasek tygodnia, lista 8 sesji; brak wykresów | `view_data.dart:27-52` | **nie** (dane w 0,5 ms) |
| WF-6: statystyka bloku (czas planowany i faktyczny, próg, ważny sygnał, nad progiem, nagrody) | zapisywane w `blocks` | `session_repository.dart:288-305` | tak |
| WN 2.1: zmierzone 246,3 Hz | patrz niżej | — | tylko inne nagranie |

### Źródło 246,3 Hz i 249,84 Hz
- **246,3 Hz**: nagranie `scripts/brainaccess_probe/probe_dump.csv` (26.10.2026, BA MAXI 012, czepek bez kontaktu z głową), 60,9 s, liczone jako liczba próbek / czas odbioru na hoście (`analyze.py`); wg przyrostu `SAMPLE_NUMBER` 246,7 Hz; w krótkim nagraniu 235 Hz. To narzędzie pomiarowe w Pythonie, nie aplikacja. Odstęp paczek: średnio 0,1015 s, odch. std 0,041 s (`fakty_brainaccess.md:16`).
- **249,84 Hz**: baza aplikacji (wersja sandboxowana, `~/Library/Containers/pl.pwr.neurotchi.neurotchi/Data/Library/Application Support/pl.pwr.neurotchi.neurotchi/neurotchi.db`), tabela `segments`, sesja 3 z 2026-11-03 (`device`, completed): `fs_measured_hz = 249,838978956674`. Pozostałe sesje czepka tej bazy: sesja 1 = 249,24 Hz (przerwana), sesja 2 = 249,90 Hz. Liczone w `session_persistence.dart` (`_closeSegment`): (koniec ostatniej paczki − koniec pierwszej paczki) w próbkach / (tRecv ostatniej − tRecv pierwszej), gdzie tRecv to czas odbioru w callbacku na hoście. Baza niesandboxowa (`~/Library/Application Support/...`): sesja 4 czepka 250,02 Hz (krótka).
- Z tego wynika, że pomiar w aplikacji na macOS (≈249,2–249,9 Hz, 3 sesje) i 246,3 Hz z sondy Pythona to dwie różne metody i nagrania; WN 2.1 może podawać 249,84 Hz (sesja 3) z odnośnikiem do `segments.fs_measured_hz`, a 246,3 Hz jako wynik osobnego narzędzia.

## Nie udało się zmierzyć
- Pixel: nie mierzono zapisu 60 min w czasie rzeczywistym ani niczego z czepkiem.
- FPS i render na macOS (ekran zablokowany).
- Zapis 60 min w czasie rzeczywistym (przerwany).
- Opóźnienie BLE i „Odbiór → bufor” (wymaga czepka).
- Maksymalna utrata próbek przy rozłączeniu na Androidzie (brak strażnika w kodzie, SDK nie testowany).
- Wartość gainu na Androidzie (aplikacja jej nie odczytuje).
- Pochodzenie liczb 76 ms i 124 ms (brak w repozytorium; obliczenia DSP dają 0,4 ms).

## Niezgodności praca – kod (do poprawy w pracy lub w kodzie)
1. minSdk to 24, nie 21.
2. WF-1: brak limitu czasu połączenia 15 s; 15 s to odstęp przed próbą ponowienia.
3. WF-3: stan jakości nie jest liczony per kanał (poza kontaktem); płaska linia wykrywana po ≈2–2,3 s, etykieta po ≈3–3,4 s; impuls 300 µV niewykrywany (progi na sygnale filtrowanym).
4. WF-7: opóźnienie ≤0,2 s niespełnione w p95 i max (0,30 i 0,35 s); informacja zwrotna ciągła tylko jako pasek i liczba, mimika dyskretna, brak rozmiaru i ruchu.
5. WF-9: utrata ≤3 s dotyczy tylko okna wykrycia (macOS); Android bez strażnika; przerwa do ponownego połączenia ≥15 s nie jest zapisywana.
6. WF-11 i WF-12: brak sortowania, filtrowania, wykresów; lista pokazuje 8 sesji.
7. WF-13: eksport to TSV zdarzeń + surowy CSV/JSON; brak CSV cech i statystyk.
8. WN 5.3 (usuwanie danych), WN 5.4 (kopia zapasowa), wyciszanie dźwięku, lokalizacja: brak w kodzie.
9. Schemat: kod ma wersję 3, a komentarz w `schema.dart`, README i `schema_v5.dbml` mówią o „wersji 5”.
10. Filtr: kaskada HP4+LP4, nie pasmowy 4. rzędu; komentarz w `processing_config.dart` (30–40 do 1–40 Hz) nie zgadza się z kodem (3–40 Hz).

## Streszczenie: co zmienić w pracy
Opóźnienie DSP wpisz jako ≈0,4 ms (p95 0,46 ms), a całkowite od próbki do werdyktu jako p50 0,18 s, p95 0,30 s, max 0,35 s (plus render), więc usuń „≤0,2 s” albo zmień na medianę. Zmień minSdk na 24, 246,3 Hz na 249,84 Hz (sesja 3, z zaznaczeniem różnych metod), „limit połączenia 15 s” na „odstęp 15 s przed każdą z 3 prób”, a „utrata ≤3 s” na „wykrycie ciszy po 3 s (macOS), przerwa do ponownego połączenia niezapisana”. Usuń lub oznacz jako niezaimplementowane: wykresy postępu, sortowanie i filtrowanie historii, usuwanie danych, kopię zapasową, wyciszanie dźwięku, lokalizację, informację zwrotną przez rozmiar i ruch. Pomiary 60 min zapisu (bez strat, 900000 = 900000), 115 testów, zgodność ze SciPy (≤1e-8) i identyczny replay (różnica 0) możesz wpisać jako potwierdzone. Pixel ma teraz FPS, render, historię, DSP i zapis; brakuje FPS i renderu na macOS oraz zapisu w czasie rzeczywistym.
