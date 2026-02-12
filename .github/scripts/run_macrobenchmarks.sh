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

TEMP_DIR="$(mktemp -d)"
trap 'rm -rf "${TEMP_DIR}"' EXIT

install_apk() {
  local apk_path="${1}"
  echo "Installing: ${apk_path}"
  adb install -r "${apk_path}"

  sleep 2

  adb shell pm clear "$APP_PKG" || true
  adb shell pm clear "${BENCHMARK_PKG}" || true
}

run_benchmark() {
  echo "Running benchmark..."
  adb shell am instrument -w \
    -e class com.google.samples.apps.nowinandroid.startup.StartupBenchmark#startupPrecompiledWithBaselineProfile \
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
  adb shell "su 0 cp -R /storage/emulated/0/Android/media/${BENCHMARK_PKG}/. ${BRIDGE}/ 2>/dev/null || true"
  adb shell "su 0 cp -R /storage/emulated/0/Android/data/${BENCHMARK_PKG}/files/. ${BRIDGE}/ 2>/dev/null || true"
  adb shell "su 0 cp -R /data/data/${BENCHMARK_PKG}/files/. ${BRIDGE}/ 2>/dev/null || true"
  adb shell "su 0 chmod -R 777 ${BRIDGE}"

  # List what we found
  echo "Debug: Contents of bridge folder on device:"
  adb shell "ls -R -l ${BRIDGE}"

  adb pull "${BRIDGE}/." "${TEMP_DIR}/"

  JSON_FILE=$(find "${TEMP_DIR}" -name "*.json" | head -n 1)
  if [[ -n "$JSON_FILE" ]]; then
    mv "$JSON_FILE" "${output_path}"
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
  output_filename="${BENCHMARK_PKG}_${timestamp}.json"
  baseline_output_path="${OUTPUT_DIR}/baseline/${output_filename}"
  candidate_output_path="${OUTPUT_DIR}/candidate/${output_filename}"

  echo "=============================="
  echo "Start iteration (${i} / ${NUMBER_OF_RUNS})"
  echo "=============================="

  echo "Starting Baseline Benchmark:"
  echo "    >> APK file        : ${PATH_APK_BASELINE}"
  echo "    >> Output file path: ${baseline_output_path}"

  install_apk "${PATH_APK_BASELINE}"
  run_benchmark
  write_benchmark_result "${baseline_output_path}"

  echo "Starting Candidate Benchmark:"
  echo "    >> APK file        : ${PATH_APK_CANDIDATE}"
  echo "    >> Output file path: ${candidate_output_path}"

  install_apk "${PATH_APK_CANDIDATE}"
  run_benchmark
  write_benchmark_result "${candidate_output_path}"

  end_time=$(date +%s)
  duration=$((end_time - start_time))

  echo "=============================="
  echo "End iteration (${i} / ${NUMBER_OF_RUNS}) took ${duration}s"
  echo "=============================="
done
