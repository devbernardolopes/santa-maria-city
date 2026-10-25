#!/usr/bin/env bash
# Headless entity scaling benchmark: NPC CPU cost, frame pacing, node count, and memory.
# Never runs the main game scene.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

GODOT="$("$ROOT/tools/godot_bin.sh")"
LOG="$(mktemp "${TMPDIR:-/tmp}/santa-maria-entities-bench.XXXXXX.log")"
trap 'rm -f "$LOG"' EXIT

# Full city by default; override for a quick run, e.g.
#   ENTITIES_BENCH_MAP=res://data/map_test.json make entities-bench
export ENTITIES_BENCH_MAP="${ENTITIES_BENCH_MAP:-res://data/map.json}"

echo "== Entity scaling benchmark (map: $ENTITIES_BENCH_MAP${ENTITIES_BENCH_SWEEP:+, sweep: $ENTITIES_BENCH_SWEEP})"
if ! timeout 900 "$GODOT" --headless --path "$ROOT" res://tests/entities_benchmark.tscn >"$LOG" 2>&1; then
	cat "$LOG" >&2
	exit 1
fi

# Any runtime script error means the numbers below are measuring an error storm.
if grep -q 'SCRIPT ERROR' "$LOG"; then
	echo "Script errors during the entity benchmark (fix them before trusting timings):" >&2
	grep -n 'SCRIPT ERROR' "$LOG" | head -20 >&2
	exit 1
fi
if ! grep -q '^ENTITIES BENCH: done' "$LOG"; then
	echo "The benchmark did not finish:" >&2
	cat "$LOG" >&2
	exit 1
fi

grep -E '^ENTITIES BENCH:' "$LOG" || true
