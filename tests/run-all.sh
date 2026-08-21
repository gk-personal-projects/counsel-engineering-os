#!/usr/bin/env bash
# run-all.sh - run every test suite in this repository.
# Provenance: ORIGINAL (Apache-2.0). Same contract as run-all.ps1 (POSIX port).
# Dependencies: bash 3.2+ (each suite carries its own dependency list).
# Exit codes: 0 if every suite exits 0, otherwise 1.
#
# WHY THIS EXISTS. Before this file, the suites could only be run one at a time, by
# name, from memory. "Run the tests" therefore meant "run the suites you happen to
# remember" - and a suite nobody remembers is a suite that does not gate anything.
# 0.1.6 shipped a version-coherence defect partly for this reason: the check did not
# exist, and there was no single place that would have made its absence obvious.
#
# Adding a suite means adding one line here. If you add a suite and do not add the
# line, it does not run in any release, and this comment is the reason you will be
# annoyed later.
#
# Usage:
#   ./run-all.sh            # run everything, summarise
#   ./run-all.sh -Quiet     # drop the per-suite banners and suite output
#
# Note vs run-all.ps1: bash captures suite output cleanly, so -Quiet here really is
# quiet (the .ps1 could not suppress Write-Host output; this port can and does).
# The summary at the end is the part to read either way.

set -u

QUIET=0
while [ $# -gt 0 ]; do
  case "$1" in
    -Quiet|--quiet) QUIET=1; shift ;;
    *) echo "Unknown argument: $1" >&2; exit 1 ;;
  esac
done

TESTS_ROOT=$(cd "$(dirname "$0")" && pwd -P)

SUITE_NAMES="release doctor continuity install lifecycle"
suite_path() {
  case "$1" in
    release)    echo "release/run-manifest-tests.sh" ;;
    doctor)     echo "doctor/run-credential-tests.sh" ;;
    continuity) echo "continuity/run-tests.sh" ;;
    install)    echo "install/run-install-tests.sh" ;;
    lifecycle)  echo "install/run-lifecycle-tests.sh" ;;
  esac
}

# Parallel indexed arrays (bash 3.2: no associative arrays).
r_suite=(); r_exit=(); r_status=(); r_detail=()
n=0

for name in $SUITE_NAMES; do
  rel=$(suite_path "$name")
  full="$TESTS_ROOT/$rel"
  if [ ! -f "$full" ]; then
    echo "MISSING SUITE: $rel"
    r_suite[$n]="$name"; r_exit[$n]=127; r_status[$n]="MISSING"; r_detail[$n]=""
    n=$((n+1))
    continue
  fi
  if [ "$QUIET" -ne 1 ]; then
    echo ""
    echo "===== $name ====="
  fi
  out=$(bash "$full" 2>&1)
  code=$?
  if [ "$QUIET" -ne 1 ]; then
    printf '%s\n' "$out"
  fi
  # Suites report their own counts; capture the tail line that carries them.
  tail_line=$(printf '%s\n' "$out" | grep -E 'passed,[[:space:]]*[0-9]+[[:space:]]*failed' | tail -n 1 | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')
  status="FAIL"
  [ "$code" -eq 0 ] && status="PASS"
  r_suite[$n]="$name"; r_exit[$n]="$code"; r_status[$n]="$status"; r_detail[$n]="$tail_line"
  n=$((n+1))
done

echo ""
echo "===== SUMMARY ====="
failed=0
i=0
while [ "$i" -lt "$n" ]; do
  printf '  %-11s %-5s exit=%s  %s\n' "${r_suite[$i]}" "${r_status[$i]}" "${r_exit[$i]}" "${r_detail[$i]}"
  [ "${r_exit[$i]}" -ne 0 ] && failed=$((failed+1))
  i=$((i+1))
done
echo ""
if [ "$failed" -gt 0 ]; then
  echo "SUITES FAILED: $failed of $n"
  exit 1
fi
echo "ALL $n SUITES PASSED"
exit 0
