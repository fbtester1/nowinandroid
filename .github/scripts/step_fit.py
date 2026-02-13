import argparse
import json
import math
import sys
from pathlib import Path

# # ----------- CONFIG -----------
# BENCHMARK_NAME = "startupPrecompiledWithBaselineProfile"
# METRIC_KEY = "timeToInitialDisplayMs"
# # ------------------------------

# ----------- CONFIG -----------
# (Benchmark Name, Metric Key, label)
BENCHMARK_CONFIGS = [
    # 1. Startup Test
    ("startupPrecompiledWithBaselineProfile", "timeToInitialDisplayMs", "STARTUP"),
    
    # 2. Scroll Test
    ("scrollFeedCompilationBaselineProfile", "frameDurationCpuMs", "SCROLL")
]
# ------------------------------

def step_fit(a, b):
    def sum_squared_error(values):
        avg = sum(values) / len(values)
        return sum((v - avg) ** 2 for v in values)

    if not a or not b:
            return 0.0

    total_squared_error = sum_squared_error(a) + sum_squared_error(b)
    step_error = math.sqrt(total_squared_error) / (len(a) + len(b))
    if step_error == 0.0:
        return 0.0

    return (sum(a) / len(a) - sum(b) / len(b)) / step_error

def extract_median_from_files(paths, bench_name, metric_key):
    medians = []

    for path in paths:
        with open(path, "r") as f:
            try:
                data = json.load(f)
            except json.JSONDecodeError:
                print(f"WARN: Could not decode JSON in {path}", file=sys.stderr)
                continue

        for bench in data.get("benchmarks", []):
            if bench.get("name") == bench_name:
                metrics = bench.get("metrics", {})
                if metric_key in metrics:
                    medians.append(metrics[metric_key].get("median"))
                    break
                
                sampled_metrics = bench.get("sampledMetrics", {})
                if metric_key in sampled_metrics:
                    medians.append(sampled_metrics[metric_key].get("P50"))
                    break
                    
    return medians

def main():
    parser = argparse.ArgumentParser(prog='Comperator', description='Compare between multiple macrobenchmark test results')
    parser.add_argument('baseline_dir', help='Baseline macrobenchmark reports directory')
    parser.add_argument('candidate_dir', help='Candidate macrobenchmark reports directory')
    args = parser.parse_args()

    baseline_dir = Path(args.baseline_dir)
    candidate_dir = Path(args.candidate_dir)
    baseline_files = sorted(baseline_dir.glob("*.json"))
    candidate_files = sorted(candidate_dir.glob("*.json"))

    if len(baseline_files) <= 0:
        print('ERR: baseline has no macrobenchmark results', file=sys.stderr)
        exit(1)

    if len(candidate_files) <= 0:
        print('ERR: candidate has no macrobenchmark results', file=sys.stderr)
        exit(1)

    min_len = min(len(baseline_files), len(candidate_files))
    if len(baseline_files) != len(candidate_files):
        print(f"WARN: Length mismatch, using first {min_len} samples. baseline: {len(baseline_files)}, candidate: {len(candidate_files)}")

    print('Macrobenchmark Result Mapping:')
    print('| Index | Baseline | Candidate |')
    print('--------------------------------')

    mismatch_count = 0
    for i in range(min_len):
        baseline_filename = baseline_files[i].name.upper()
        candidate_filename = candidate_files[i].name.upper()
        
        if baseline_filename != candidate_filename:
            mismatch_count += 1
            print('* ', end='')
        print(f'{i + 1} {baseline_files[i]} <-> {candidate_files[i]}')

    print('--------------------------------')
    print(f'# Match   : {min_len - mismatch_count}')
    print(f'# Mismatch: {mismatch_count}')
    if mismatch_count > 0:
        print("WARN: filename mapping mismatch detected. Output prediction may be incorrect")
    print()

    for bench_name, metric_key, label in BENCHMARK_CONFIGS:
        print(f"=== ANALYZING: {label} ===")
        print(f"Benchmark: {bench_name}")
        print(f"Metric   : {metric_key}")

        baseline_medians = extract_median_from_files(baseline_files, bench_name, metric_key)
        candidate_medians = extract_median_from_files(candidate_files, bench_name, metric_key)

        print(f"Baseline medians : {baseline_medians}")
        print(f"Candidate medians: {candidate_medians}")

        if not baseline_medians or not candidate_medians:
            print("WARN: No data found for this benchmark. Skipping calculation.")
            print("-" * 30)
            print()
            continue

        result = step_fit(baseline_medians, candidate_medians)
        
        print("Result: ", end="")
        if abs(result) <= 25:
            print("Within noise range", end="")
        elif result < 0:
            print("POSSIBLE REGRESSION", end="")
        else:
            print("POSSIBLE IMPROVEMENT", end="")
        print(f" (Step fit: {result:.4f})")
        print("-" * 30)
        print()

if __name__ == "__main__":
    main()