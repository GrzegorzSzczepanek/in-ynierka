# Fakty o BrainAccess SDK (EegSource)

Źródła: nagłówki SDK `BrainAccessCore-4.0.0-macos/include/*.h` ("dok."), nagranie `probe_dump.csv` z `probe.py`, metadane `probe_meta.json`, analiza `analyze.py` ("pomiar"). Nagranie: 26.10.2026, BA MAXI 012, 250 Hz, 60 s, czepek **bez kontaktu z głową** (wszystkie kontakty = False), więc zakres wartości nie jest reprezentatywny.

Uwaga: SDK na macOS to biblioteka C (`libbacore` 4.0.0), bez wrappera Pythona. Pytanie o model: sprzęt to **MAXI, 32 kanały EEG**, nie MIDI.

| Fakt | Wartość | Źródło | Pewność |
|---|---|---|---|
| Model, HW, FW, numer seryjny | MAXI (id 2), HW 2.0.0, FW 3.6.0, serial 12 | `probe_meta.json` | pomiar |
| Liczba elektrod | 32 | `probe_meta.json`, log SDK | pomiar |
| Próbek w pakiecie BLE | 12 | `probe_meta.json` (`sample_per_packet`) | pomiar |
| Format chunka | `const void* const*`, kolumna wg `ba_eeg_manager_get_channel_index(id)`, `chunk_size` próbek w kolumnie | `callbacks.h`, `eeg_manager.h` | dok. + pomiar |
| Kolejność kolumn | 0: SAMPLE_NUMBER, 1..32: pomiar kanałów, 33..64: kontakt kanałów | `probe_meta.json` | pomiar |
| Rozmiar chunka | stały 25 próbek (601 chunków x 25 = 15025 próbek). Konfigurowalny 1 do 100 przez `ba_core_set_config.chunk_size` | `analyze.py`, `bacore.h` | pomiar + dok. |
| Odstęp między chunkami | średnia 0,1015 s, odch. std 0,041 s, max 0,271 s, min 0,9 ms. 9 odstępów powyżej 0,2 s | `analyze.py` | pomiar |
| Rzeczywista częstotliwość | 246,3 Hz (próbki/czas odbioru, 60,9 s), 246,7 Hz wg przyrostu SAMPLE_NUMBER. Nominalnie 250 Hz. Przyczyna różnicy 1,5 % nieznana | `analyze.py` | pomiar |
| Licznik próbek | kanał SAMPLE_NUMBER (`size_t`), od 0, **nie jest włączony domyślnie**, trzeba go włączyć. Brak luk: wszystkie 15024 kroki = 1 | `eeg_channel.h`, `analyze.py` | pomiar |
| Licznik pakietów | nieznane, SDK go nie wystawia | nagłówki | z dokumentacji |
| Znacznik czasu źródła | brak. Jedyny czas to czas odbioru po stronie hosta | nagłówki | z dokumentacji |
| Jednostka | µV, `double`. Dane są już przeskalowane gainem. Domyślny gain 8, w logu kod gainu 4 = `BA_GAIN_MODE_X8` | `eeg_channel.h`, `eeg_manager.h`, `gain_mode.h`, log | dok. |
| Zakres surowych wartości | bez głowy: clip na ±562500 µV (= 4,5 V / 8, pełna skala przy gain 8). Na głowie: od -27887 do +88927 µV, odch. std ok. 6300 do 9400 µV na kanał, to nie jest poziom EEG (dziesiątki µV). Dane wymagają usunięcia składowej stałej i filtracji, a jakość kontaktu jest niepewna | `analyze.py`, `probe_dump_head.csv` | pomiar |
| Nazwy kanałów | SDK nie podaje nazw elektrod, tylko indeksy 1..32. Mapowanie na 10/20 musi być po stronie aplikacji | `eeg_channel.h` | z dokumentacji |
| Kontakt elektrody | kanał `ELECTRODE_CONTACT` (bool). W obu nagraniach (także przy czepku na głowie) wszystkie 32 kanały miały False przez cały czas. Nieznane, czy to brak realnego kontaktu, czy detekcja kontaktu nie działa na FW 3.6.0 | `analyze.py`, `probe_dump_head.csv` | pomiar (nieznana przyczyna) |
| Impedancja | brak wartości w omach. Tryby testowe 7,8 Hz, 31,2 Hz, fs/4 przez `set_impedance_mode`, amplitudę liczy się samemu | `impedance_measurement_mode.h` | dok. |
| Akcelerometr | `has_accel` = true, `has_gyro` = false. Kanały `ACCELEROMETER` +0..+2 (3 osie, `float`) dały indeksy kolumn 65 do 67 i dane. Wartości 0 do 7,4, tylko 18 do 19 unikalnych wartości na oś, zmieniają się w ok. 9 % próbek, czyli akcelerometr odświeża się wyraźnie rzadziej niż 250 Hz (wartości są powtarzane). Jednostka nieznana (nie wyglądają na g) | `probe_dump_head.csv` | pomiar (częstotliwość i jednostka: nieznane) |
| Bateria | callback `ba_callback_battery`: poziom 0 do 100, ładowanie. Nie testowano | `callbacks.h`, `battery_info.h` | z dokumentacji |
| Wejście cyfrowe | kanał `DIGITAL_INPUT`, nie testowano | `eeg_channel.h` | z dokumentacji |
| Callback rozłączenia | wywoływany przy zamierzonym `disconnect` i przy nagłej utracie (czepek wyłączony). Log SDK: "DISCONNECTED UNEXPECTEDLY" | `eeg_manager.h`, `probe_meta*.json`, `disconnect_test.json` | pomiar |
| Opóźnienie wykrycia utraty | callback po 0,77 s od ostatniego chunka, `is_connected` = false po 0,83 s. Brak wyjątku. Jednorazowy pomiar | `disconnect_test.json` | pomiar (n=1) |
| Po utracie | `stop_stream` zwraca 3 (`BA_ERROR_WRONG_VALUE`) i loguje, że strumień nie działa. Chunki przestają przychodzić | `disconnect_test.json`, log SDK | pomiar |
| Ponowne połączenie | działa w tym samym procesie na tym samym managerze: `connect` (ok. 7,3 s), ponowna konfiguracja kanałów, `load_config`, `start_stream`. Po 10 s 100 chunków, `SAMPLE_NUMBER` zaczyna od 0. Konfigurację kanałów trzeba ustawić od nowa | `disconnect_test.json` | pomiar (n=1) |
| Nagłe rozłączenie w trakcie nagrania | podczas nagrania na głowie (`_head`) czepek rozłączył się sam po 14 s (log "DISCONNECTED UNEXPECTEDLY"), nagranie ma 122 chunki (3050 próbek). Przyczyna nieznana | `probe_meta_head.json`, log SDK | pomiar |
| Wątek callbacka chunków | nie gwarantowany, krótki callback, bez blokowania | `eeg_manager.h` | z dokumentacji |
| `get_stream_channel_data_types` | zwróciło pustą tablicę | `probe_meta.json` | pomiar |
| Tryb wyjścia (`set_output_mode`) | FW 3.6.0 nie ma tej charakterystyki ("characteristic not found"), nieszkodliwe | `bacore.log` | pomiar |

## Czego SDK nie dostarcza

- Znacznika czasu źródła (czas próbki z zegara urządzenia).
- Licznika pakietów BLE, jest tylko licznik próbek (i tylko po jego włączeniu).
- Nazw elektrod i ich pozycji 10/20.
- Impedancji w omach (tylko tryby testowe, obliczenia po stronie aplikacji).
- Typów danych kolumn przez `get_stream_channel_data_types` (puste).
- Gwarancji wątku callbacka i stałych odstępów: chunki przychodzą w seriach (min 0,9 ms, max 0,27 s).
- Wrappera Pythona dla macOS (tylko C).

## Lista możliwości SDK (z nagłówków 4.0.0, bez pomiaru)

Źródło: `BrainAccessCore-4.0.0-macos/include/*.h`.

| Obszar | Co jest |
|---|---|
| Cykl życia | `ba_core_init`, `ba_core_scan` (ok. 5 s, zwraca tylko urządzenia "BA ..."), `ba_core_close`, `ba_core_get/set_config` (`chunk_size` 1 do 100, `adapter_index`, logi), `ba_core_get_version` |
| Manager | `ba_eeg_manager_new/free/connect/disconnect/is_connected/start_stream/stop_stream/load_config`, manager nie jest thread-safe |
| Callbacki | chunk (`ba_callback_chunk`), bateria, rozłączenie, wyniki przyszłości (void, bool, float, bateria pełna), OTA |
| Kanały strumienia | SAMPLE_NUMBER 0 (`size_t`), ELECTRODE_MEASUREMENT 1 (`double`, µV), ELECTRODE_CONTACT_P 513, ELECTRODE_CONTACT 1025, ELECTRODE_CONTACT_N 1537 (`bool`), DIGITAL_INPUT 2049 (`bool`), GYROSCOPE 2497 (`float`), ACCELEROMETER 2561 (`float`), STREAMING 2625 (`bool`) |
| Konfiguracja kanałów | `set_channel_enabled`, `set_channel_gain` (x1, x2, x4, x6, x8, x12; domyślnie x8), `set_channel_bias_feedback`, `set_channel_bias` (polaryzacja: none, both, positive, negative). Efekt na następny start, kasowany przez stop |
| Częstotliwość | `set_data_stream_rate` (stałe 16 kHz do 250 Hz, MAXI/MIDI: 250 i 500 Hz, domyślnie 250), `read_sample_frequency` |
| Tryby | impedancja: off, 7,8 Hz, 31,2 Hz, fs/4. Wyjście: normalne lub fala prostokątna (nie działa na FW 3.6.0) |
| Informacje | `get_device_info` (model, HW, FW, serial, próbek na pakiet), `ba_core_device_features_get` (`has_accel`, `has_gyro`, `is_bipolar`, liczba elektrod), `get_channel_index`, `get_stream_channel_data_types` |
| Modele | MINI V2 (0), MIDI (1, 16 kanałów), MAXI (2, 32 kanały), EMG (3), HALO (4), HALO V2 (5), EXG8 (6), HALO V3 (7) |
| Bateria | callback `ba_battery_info` (poziom 0 do 100, ładowarka, ładowanie), `ba_full_battery_info`, ustawienia ładowania |
| Adnotacje | `annotate`, `get_annotations`, `clear_annotations` (nie działają powyżej 250 Hz) |
| Aktualizacja | OTA firmware (`start_update`) |
| Błędy | `ba_error` 0 do 18 i 0xFF (m.in. 1 CONNECTION, 3 WRONG_VALUE, 11 NO_DEVICES_FOUND, 17 STREAM_START_FAILED, 18 NOT_STREAMING) |

## Do sprawdzenia

1. Nagranie na głowie przez pełne 60 s lub dłużej (to z `_head` urwało się po 14 s): realny std per kanał, kontakt.
2. Dlaczego `ELECTRODE_CONTACT` jest zawsze False (żel/kontakt, czy nieobsługiwane na FW 3.6.0).
3. Dlaczego czepek rozłączył się sam po 14 s (bateria, odległość, zakłócenia BLE).
4. Częstotliwość i jednostka akcelerometru (w tym teście zmienia się tylko ok. 9 % próbek).
5. Czy 246,3 Hz (235 Hz w krótkim nagraniu) to zegar urządzenia, czy tempo dostarczania BLE: dłuższe nagranie (np. 10 min) i porównanie z zegarem hosta.
6. Powtórzenie testu rozłączenia (n=1), w tym utrata przez oddalenie, a nie wyłączenie.
