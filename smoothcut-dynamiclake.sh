#!/bin/sh
# SmoothCut for DynamicLake -- the plugin's executable.
#
# DynamicLake starts this with DYNAMICLAKE_JSON_SOCKET set. It is a relay and nothing else: the
# bytes DynamicLake sends go to SmoothCut, and the bytes SmoothCut sends go to DynamicLake.
# Everything that decides what the notch shows lives in SmoothCut (electron/dynamiclake), so there
# is one implementation of it and this file has no logic to get wrong.
#
# It uses only tools a stock Mac has (/bin/sh, nc, mkfifo, mktemp). No Python, no Node.
#
# SmoothCut offers a local socket only while Settings > Notch > "Show in the notch" is on. While it
# is not there, this script waits quietly: no connection to DynamicLake is made, so nothing is
# shown, and nothing is printed except on a real fault.
#
# The installed plugin package is never written to. The one temporary file (a named pipe) goes in
# $TMPDIR and is removed on exit.

PATH=/usr/bin:/bin
export PATH

dl_socket="${DYNAMICLAKE_JSON_SOCKET:-}"
if [ -z "$dl_socket" ]; then
	echo "DYNAMICLAKE_JSON_SOCKET is not set. Start this plugin from DynamicLake." >&2
	exit 2
fi

# The feature list DynamicLake supports ("numericText,presentSneakPeek,..."), passed on so
# SmoothCut only sends what this DynamicLake understands. Letters and commas only.
features=$(printf '%s' "${DYNAMICLAKE_PLUGIN_FEATURES:-}" | tr -cd 'A-Za-z,')

# Where SmoothCut says its socket is. Both folder names are tried because an install that could
# not migrate from the old product name keeps the old folder. SMOOTHCUT_DATA_DIR is for tests.
find_socket() {
	for dir in "${SMOOTHCUT_DATA_DIR:-}" \
		"$HOME/Library/Application Support/SmoothCut" \
		"$HOME/Library/Application Support/Smooth Cut"; do
		[ -n "$dir" ] || continue
		file="$dir/dynamiclake-endpoint"
		[ -r "$file" ] || continue
		path=""
		IFS= read -r path <"$file" || [ -n "$path" ] || continue
		if [ -S "$path" ]; then
			printf '%s' "$path"
			return 0
		fi
	done
	return 1
}

# Seconds between looks for SmoothCut while it is not there. SMOOTHCUT_RELAY_POLL is for tests.
poll="${SMOOTHCUT_RELAY_POLL:-2}"

pipe_dir=$(mktemp -d "${TMPDIR:-/tmp}/smoothcut-dynamiclake.XXXXXX") || exit 1
pipe="$pipe_dir/to-dynamiclake"
job=""

stop() {
	# The relay runs in its own process group (set -m below), so it does not die with us unless
	# we say so: left behind, it would hold DynamicLake's connection open with a stale activity.
	[ -n "$job" ] && kill -TERM "-$job" 2>/dev/null
	rm -rf "$pipe_dir"
	exit 0
}
trap stop TERM INT HUP
trap 'rm -rf "$pipe_dir"' EXIT

set -m

while :; do
	if app_socket=$(find_socket); then
		rm -f "$pipe"
		mkfifo "$pipe" || exit 1
		# hello line, then DynamicLake's bytes, into SmoothCut; SmoothCut's bytes, via the pipe,
		# into DynamicLake. When either side goes away the other is closed with it, so
		# DynamicLake drops the activity of a SmoothCut that has quit.
		{
			printf 'SMOOTHCUT-DYNAMICLAKE 1 %s\n' "$features"
			nc -U "$dl_socket" <"$pipe"
		} | nc -U "$app_socket" >"$pipe" 2>/dev/null &
		job=$(jobs -p | head -n 1)
		wait
		job=""
		# DynamicLake itself went away: nothing left to relay to.
		[ -S "$dl_socket" ] || exit 0
	fi
	sleep "$poll"
done
