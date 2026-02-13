#!/usr/bin/env bash

set -euo pipefail

# TODO: pass number of runs as a commandline argument
NUMBER_OF_RUNS=2

APP_PKG="com.google.samples.apps.nowinandroid.demo"
BENCHMARK_PKG="com.google.samples.apps.nowinandroid.benchmarks"
TEST_RUNNER="androidx.test.runner.AndroidJUnitRunner"

PATH_APK_BASELINE="${1:-}"
PATH_APK_CANDIDATE="${2:-}"
OUTPUT_DIR="${3:-./macrobenchmark_results}"

CLASS_STARTUP="com.google.samples.apps.nowinandroid.startup.StartupBenchmark#startupPrecompiledWithBaselineProfile"
CLASS_SCROLL="com.google.samples.apps.nowinandroid.foryou.ScrollForYouFeedBenchmark#scrollFeedCompilationBaselineProfile"

echo "Debug: Saving results to: ${OUTPUT_DIR}"

TEMP_DIR="$(mktemp -d)"
trap 'rm -rf "${TEMP_DIR}"' EXIT

install_apk() {
  local apk_path="${1}"
  echo "Installing: ${apk_path}"
  adb install -r "${apk_path}"

  sleep 2

  # 'pm clear' alone sometimes leaves a 'ghost' process. 'force-stop' ensures a true Cold Start
  adb shell am force-stop "$APP_PKG" || true
  adb shell pm clear "$APP_PKG" || true
  adb shell am force-stop "${BENCHMARK_PKG}" || true
  adb shell pm clear "${BENCHMARK_PKG}" || true
}

run_benchmark() {
  local class_method="${1}"

  echo "Running benchmark: ${class_method}"
  adb shell am instrument -w \
    -e class "${class_method}" \
    -e androidx.benchmark.suppressErrors EMULATOR \
    -e androidx.benchmark.profiling.mode none \
    -e no-isolated-storage true \
    "$BENCHMARK_PKG/$TEST_RUNNER"
}

write_benchmark_result() {
  local output_path="${1}"
  mkdir -p "$(dirname "${output_path}")"

  echo "Searching for results..."

  BRIDGE="/data/local/tmp/bridge"
  adb shell "rm -rf ${BRIDGE} && mkdir -p ${BRIDGE} && chmod 777 ${BRIDGE}"

  echo "Looking in default storage locations..."
  # Macrobenchmark libraries change their output directory depending on the version and API level.
  adb shell "su 0 find /storage/emulated/0/Android/data/${BENCHMARK_PKG}/ /storage/emulated/0/Android/media/${BENCHMARK_PKG}/ /data/data/${BENCHMARK_PKG}/ -name '*benchmarkData.json' -exec cp {} ${BRIDGE}/data.json \;" 2>/dev/null || true
  adb shell "su 0 chmod -R 777 ${BRIDGE}"

  adb pull "${BRIDGE}/data.json" "${TEMP_DIR}/data.json" || echo "Warning: JSON pull failed"

  if [[ -f "${TEMP_DIR}/data.json" ]]; then
    mv "${TEMP_DIR}/data.json" "${output_path}"
    echo "Success: Saved to ${output_path}"
  else
    echo "ERROR: No results found. The benchmark likely crashed or wrote somewhere unexpected."
    exit 1
  fi
    
  adb shell "rm -rf ${BRIDGE}"
  rm -rf "${TEMP_DIR:?}"/*
}

if [[ -z "${PATH_APK_BASELINE}" || -z "${PATH_APK_CANDIDATE}" ]]; then
    echo "Usage: $0 <path_to_baseline.apk> <path_to_candidate.apk> [output_dir]"
    exit 1
fi

mkdir -p "${OUTPUT_DIR}/baseline" "${OUTPUT_DIR}/candidate"

# Alternate runs: v1, v2, v1, v2 ...
for ((i=1; i<=${NUMBER_OF_RUNS}; i++)); do
  start_time=$(date +%s)

  timestamp=$(date +"%Y-%m-%dT%H-%M-%S")
  
  echo "=============================="
  echo "Start iteration (${i} / ${NUMBER_OF_RUNS})"
  echo "=============================="

  
  # --- BASELINE ---
  install_apk "${PATH_APK_BASELINE}"

  # run startup baseline
  run_benchmark "${CLASS_STARTUP}"
  write_benchmark_result "${OUTPUT_DIR}/baseline/startup_${timestamp}.json"

  # run scroll baseline
  run_benchmark "${CLASS_SCROLL}"
  write_benchmark_result "${OUTPUT_DIR}/baseline/scroll_${timestamp}.json"


  # --- CANDIDATE ---
  install_apk "${PATH_APK_CANDIDATE}"
  
  # 1. Run Startup
  run_benchmark "${CLASS_STARTUP}"
  write_benchmark_result "${OUTPUT_DIR}/candidate/startup_${timestamp}.json"

  # 2. Run Scroll
  run_benchmark "${CLASS_SCROLL}"
  write_benchmark_result "${OUTPUT_DIR}/candidate/scroll_${timestamp}.json"

  end_time=$(date +%s)
  duration=$((end_time - start_time))

  echo "=============================="
  echo "End iteration (${i} / ${NUMBER_OF_RUNS}) took ${duration}s"
  echo "=============================="
done
