#!/bin/zsh
set -e
cd "$(dirname "$0")/../app"
B=test/benchmark/bench_app.dart
case "$1" in
  testy)
    flutter test
    ;;
  jakosc)
    flutter test test/core/quality_latency_test.dart --reporter expanded
    ;;
  zgodnosc)
    flutter test test/core/dsp_accuracy_test.dart test/core/replay_feature_test.dart test/core/dsp_reference_test.dart --reporter expanded
    ;;
  rozlaczenia)
    flutter test test/core/spec_constants_test.dart test/core/disconnect_timing_test.dart test/core/session_test.dart --reporter expanded
    ;;
  historia)
    flutter run --profile -d "${2:-macos}" -t $B --dart-define=BENCH=history
    ;;
  dsp)
    flutter run --profile -d "${2:-macos}" -t $B --dart-define=BENCH=dsp
    ;;
  zapis)
    flutter run --profile -d "${2:-macos}" -t $B --dart-define=BENCH=writer --dart-define=WRITER_MIN=60
    ;;
  zapis-realtime)
    flutter run --profile -d "${2:-macos}" -t $B --dart-define=BENCH=writer --dart-define=WRITER_MIN=60 --dart-define=REALTIME=true
    ;;
  fps)
    flutter run --profile -d "${2:-macos}" -t $B --dart-define=BENCH=fps --dart-define=TRAIN_S=190
    ;;
  opoznienia)
    flutter run --profile -d "${2:-macos}" -t $B --dart-define=BENCH=latency --dart-define=LAT_S=120
    ;;
  *)
    echo "uzycie: scripts/pomiary.sh testy|jakosc|zgodnosc|rozlaczenia|historia|dsp|zapis|zapis-realtime|fps|opoznienia [id urzadzenia]"
    exit 1
    ;;
esac
