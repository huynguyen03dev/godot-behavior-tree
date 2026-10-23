#!/usr/bin/env bash
# CI-friendly test orchestrator for Godot Behavior Tree test suites.
# Discovers and runs all tests/test_*.gd standalone suites headless in Godot.
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Resolve Godot binary: override via GODOT_BIN > PATH 'godot' > ~/.local/bin/godot
if [ -n "${GODOT_BIN:-}" ]; then
    GODOT="$GODOT_BIN"
elif command -v godot >/dev/null 2>&1; then
    GODOT="godot"
elif [ -x "$HOME/.local/bin/godot" ]; then
    GODOT="$HOME/.local/bin/godot"
else
    echo "Error: Godot binary not found. Set GODOT_BIN or install godot." >&2
    exit 1
fi

echo "================================================================================"
echo " Godot Behavior Tree - Test Orchestrator"
echo " Engine: $($GODOT --version 2>/dev/null || echo "$GODOT")"
echo " Path:   $REPO_ROOT"
echo "================================================================================"

# Load minimum baseline check counts if configured
BASELINES_FILE="$SCRIPT_DIR/suite_baselines.txt"
declare -A suite_baselines
if [ -f "$BASELINES_FILE" ]; then
    while read -r b_name b_count || [ -n "$b_name" ]; do
        [[ -z "$b_name" || "$b_name" =~ ^# ]] && continue
        suite_baselines["$b_name"]="$b_count"
    done < "$BASELINES_FILE"
fi

# Discover all test suites dynamically via globbing (do not hardcode)
suites=()
for suite_path in "$SCRIPT_DIR"/test_*.gd; do
    if [ -f "$suite_path" ]; then
        suites+=("$suite_path")
    fi
done

if [ ${#suites[@]} -eq 0 ]; then
    echo "Error: No test suites found matching tests/test_*.gd" >&2
    exit 1
fi

total_suites=${#suites[@]}
passed_suites=0
failed_suites=0

# Arrays to store per-suite summary data
suite_names=()
suite_statuses=()
suite_exit_codes=()
suite_details=()
failure_logs=()

SUITE_TIMEOUT="${SUITE_TIMEOUT:-60s}"

for suite in "${suites[@]}"; do
    suite_name="$(basename "$suite")"
    res_path="res://tests/$suite_name"

    echo -n "Running $suite_name ... "

    # Run suite headless with timeout and capture output and exit code
    output=$(timeout "$SUITE_TIMEOUT" "$GODOT" --headless --path "$REPO_ROOT" -s "$res_path" 2>&1)
    exit_code=$?

    # Handle timeout specifically
    if [ $exit_code -eq 124 ]; then
        status="FAIL"
        ((failed_suites++))
        echo "TIMEOUT (> $SUITE_TIMEOUT)"
        failure_logs+=("=== TIMEOUT: $suite_name (exceeded $SUITE_TIMEOUT) ===\n$output\n")
        suite_names+=("$suite_name")
        suite_statuses+=("$status")
        suite_exit_codes+=("$exit_code")
        suite_details+=("timed out after $SUITE_TIMEOUT")
        continue
    fi

    # Extract details line from output if available
    detail=""
    # Check format 1: 'Results: X total, Y passed, Z failed'
    if echo "$output" | grep -qE "Results: [0-9]+ total, [0-9]+ passed, [0-9]+ failed"; then
        detail=$(echo "$output" | grep -oE "Results: [0-9]+ total, [0-9]+ passed, [0-9]+ failed" | head -n 1 | sed 's/Results: //')
    # Check format 2: 'X checks, Y failures'
    elif echo "$output" | grep -qE "[0-9]+ checks?, [0-9]+ failures?"; then
        detail=$(echo "$output" | grep -oE "[0-9]+ checks?, [0-9]+ failures?" | tail -n 1)
    # Check format 3: 'X passed, Y failed'
    elif echo "$output" | grep -qE "[0-9]+ passed, [0-9]+ failed"; then
        detail=$(echo "$output" | grep -oE "[0-9]+ passed, [0-9]+ failed" | tail -n 1)
    fi

    # Determine pass/fail relying on exit code, output errors, and baseline checks
    has_script_error=false
    if echo "$output" | grep -qE "(SCRIPT ERROR|Parse Error)"; then
        has_script_error=true
    fi

    has_output_failures=false
    if echo "$output" | grep -qE "([1-9][0-9]* failures?|[1-9][0-9]* failed|❌ FAIL)"; then
        has_output_failures=true
    fi

    below_baseline=false
    baseline_expected=""
    actual_checks=0
    if [ -n "${suite_baselines[$suite_name]:-}" ]; then
        baseline_expected="${suite_baselines[$suite_name]}"
        if [[ "$detail" =~ ^([0-9]+) ]]; then
            actual_checks="${BASH_REMATCH[1]}"
            if [ "$actual_checks" -lt "$baseline_expected" ]; then
                below_baseline=true
            fi
        else
            below_baseline=true
        fi
    fi

    if [ $exit_code -eq 0 ] && [ "$has_output_failures" = false ] && [ "$has_script_error" = false ] && [ "$below_baseline" = false ]; then
        status="PASS"
        ((passed_suites++))
        echo "PASS ($exit_code)"
    else
        status="FAIL"
        ((failed_suites++))
        fail_reasons=()
        [ $exit_code -ne 0 ] && fail_reasons+=("exit $exit_code")
        [ "$has_output_failures" = true ] && fail_reasons+=("failures in output")
        [ "$has_script_error" = true ] && fail_reasons+=("SCRIPT/Parse ERROR")
        [ "$below_baseline" = true ] && fail_reasons+=("checks $actual_checks < baseline $baseline_expected")

        reasons_str=$(IFS=", "; echo "${fail_reasons[*]}")
        echo "FAIL ($reasons_str)"
        failure_logs+=("=== FAIL: $suite_name ($reasons_str) ===\n$output\n")
    fi

    if [ -z "$detail" ]; then
        if [ "$status" = "PASS" ]; then
            detail="completed successfully"
        else
            detail="failed (exit $exit_code)"
        fi
    elif [ "$status" = "FAIL" ]; then
        if [ "$below_baseline" = true ]; then
            detail="$detail (below baseline $baseline_expected)"
        elif [ "$has_script_error" = true ]; then
            detail="$detail (SCRIPT/Parse ERROR)"
        fi
    fi

    suite_names+=("$suite_name")
    suite_statuses+=("$status")
    suite_exit_codes+=("$exit_code")
    suite_details+=("$detail")
done

echo ""
echo "================================================================================"
echo " Test Suite Summary Table"
echo "================================================================================"
printf "%-32s | %-6s | %-4s | %s\n" "Suite" "Status" "Exit" "Details"
echo "---------------------------------+--------+------+------------------------------"

for i in "${!suite_names[@]}"; do
    printf "%-32s | %-6s | %-4s | %s\n" \
        "${suite_names[$i]}" \
        "${suite_statuses[$i]}" \
        "${suite_exit_codes[$i]}" \
        "${suite_details[$i]}"
done

echo "================================================================================"
echo "Aggregate Results: Total Suites: $total_suites | Passed: $passed_suites | Total Failures: $failed_suites"
echo "================================================================================"

if [ $failed_suites -gt 0 ]; then
    echo ""
    echo "================================================================================"
    echo " Failure Details"
    echo "================================================================================"
    for log in "${failure_logs[@]}"; do
        echo -e "$log"
    done
    exit 1
fi

exit 0
