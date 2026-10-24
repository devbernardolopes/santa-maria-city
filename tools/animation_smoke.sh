#!/usr/bin/env bash
# Headless entity animation test: resources, state machine, and visual wiring.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

GODOT="$("$ROOT/tools/godot_bin.sh")"
LOG="$(mktemp "${TMPDIR:-/tmp}/santa-maria-animation-smoke.XXXXXX.log")"
trap 'rm -f "$LOG"' EXIT

echo "== Animation smoke test"
if ! timeout 180 "$GODOT" --headless --path "$ROOT" res://tests/animation_smoke.tscn >"$LOG" 2>&1; then
	cat "$LOG" >&2
	exit 1
fi
grep -vE \
	'^(Initialize godot-rust|Godot Engine v|\[godot_ai game_helper\])|^WARNING: [0-9]+ ObjectDB instances were leaked at exit|^ERROR: [0-9]+ resources still in use at exit|^   at: (cleanup \(core/object/object\.cpp|clear \(core/io/resource\.cpp)' \
	"$LOG" || true
