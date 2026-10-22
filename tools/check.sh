#!/usr/bin/env bash
# Syntax and compile validation. Never runs the main game scene.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

GODOT="$("$ROOT/tools/godot_bin.sh")"
IMPORT_LOG="$(mktemp "${TMPDIR:-/tmp}/santa-maria-import.XXXXXX.log")"
COMPILE_LOG="$(mktemp "${TMPDIR:-/tmp}/santa-maria-compile.XXXXXX.log")"
trap 'rm -f "$IMPORT_LOG" "$COMPILE_LOG"' EXIT

echo "== Godot: $("$GODOT" --version)"

echo "== Import and class-cache scan"
if ! timeout 180 "$GODOT" --headless --editor --quit --path "$ROOT" >"$IMPORT_LOG" 2>&1; then
	echo "Godot import failed:" >&2
	cat "$IMPORT_LOG" >&2
	exit 1
fi
if grep -Eq 'SCRIPT ERROR|Parse Error|Compile Error|Failed to load script' "$IMPORT_LOG"; then
	echo "Godot reported script errors during import:" >&2
	grep -nE 'SCRIPT ERROR|Parse Error|Compile Error|Failed to load script' "$IMPORT_LOG" >&2
	exit 1
fi

echo "== GDScript syntax"
mapfile -t FILES < <(
	find autoloaders resources scenes scripts tests \
		-type f -name '*.gd' 2>/dev/null | sort
)
if ((${#FILES[@]} == 0)); then
	echo "No GDScript files found." >&2
	exit 1
fi
uv run --python 3.13 --with gdtoolkit gdparse "${FILES[@]}"

echo "== GDScript compile (autoload aware)"
if ! timeout 180 "$GODOT" --headless --path "$ROOT" res://tests/compile_check.tscn >"$COMPILE_LOG" 2>&1; then
	cat "$COMPILE_LOG" >&2
	exit 1
fi
# The compile-all harness intentionally holds res:// script resources until exit.
grep -vE \
	'^(Initialize godot-rust|Godot Engine v|\[godot_ai game_helper\])|^WARNING: [0-9]+ ObjectDB instances were leaked at exit|^ERROR: [0-9]+ resources still in use at exit|^   at: (cleanup \(core/object/object\.cpp|clear \(core/io/resource\.cpp)' \
	"$COMPILE_LOG" || true
