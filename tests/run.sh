#!/usr/bin/env bash
# Builds the place and runs every automated check in Lune.
#   shared_smoke  - catalogs, grid math, formatting, every procedural model
#   server_sim    - full server with mocked Roblox services: join, build,
#                   economy, logistics, production, research, strikes, PvP,
#                   capture, purchases, rewards, save + rejoin
#   client_sim    - the real client UI driven against the simulated server
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build
rojo build default.project.json -o build/ForgeAndFrontline.rbxlx
status=0
for t in shared_smoke server_sim client_sim; do
	echo "=== $t"
	if ! lune run "tests/$t.luau" build/ForgeAndFrontline.rbxlx > "build/$t.log" 2>&1; then
		status=1
		echo "FAILED (see build/$t.log)"
		grep -E "FAIL|ERROR|WARN" "build/$t.log" | head -20 || true
	else
		tail -1 "build/$t.log"
	fi
done
exit $status
