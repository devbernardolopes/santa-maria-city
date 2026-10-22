#!/usr/bin/env bash
# Prints the Godot 4 binary to use. Override with GODOT_BIN.
set -euo pipefail

if [[ -n "${GODOT_BIN:-}" ]]; then
	if [[ -x "$GODOT_BIN" ]]; then
		printf '%s\n' "$GODOT_BIN"
		exit 0
	fi
	printf 'godot_bin.sh: GODOT_BIN is set but not executable: %s\n' "$GODOT_BIN" >&2
	exit 1
fi

if command -v godot >/dev/null 2>&1; then
	command -v godot
	exit 0
fi

for name in godot4 godot4.7; do
	if command -v "$name" >/dev/null 2>&1; then
		command -v "$name"
		exit 0
	fi
done

# Common locations for this project and typical local installs.
CANDIDATES=(
	"$HOME/Godot/Godot_v4.7.2-stable_linux.x86_64"
	"$HOME/Godot/godot"
	"$HOME/.local/bin/godot"
	"/usr/local/bin/godot"
	"/usr/bin/godot"
)
for candidate in "${CANDIDATES[@]}"; do
	if [[ -x "$candidate" ]]; then
		printf '%s\n' "$candidate"
		exit 0
	fi
done

printf 'godot_bin.sh: Godot 4 not found. Set GODOT_BIN or put godot on PATH.\n' >&2
exit 1
