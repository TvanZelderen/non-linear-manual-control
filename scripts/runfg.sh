#!/usr/bin/env bash
#
# runfg.sh - launch FlightGear as a passive visualiser for the Citation
# Simulink model. The model's "FlightGear Visualisation" block streams
# net_fdm packets to localhost:5501-5503; FlightGear just renders them.
#
# FlightGear is optional. The Simulink model runs fine headless without it.
#
# Override any of these with env vars, e.g.:
#   FG_AIRCRAFT=CitationX ./scripts/runfg.sh
#
set -euo pipefail

FG_BIN="${FG_BIN:-/Applications/FlightGear.app/Contents/MacOS/fgfs}"
FG_AIRCRAFT="${FG_AIRCRAFT:-c172p}"      # stock; use a Citation model if you have one
FG_AIRPORT="${FG_AIRPORT:-EHAM}"        # Schiphol
FG_ALT_FT="${FG_ALT_FT:-24600}"         # ~7500 m, matches the trim condition

if [[ ! -x "$FG_BIN" ]]; then
  echo "fgfs not found at: $FG_BIN" >&2
  echo "Install FlightGear (https://www.flightgear.org/download/)" >&2
  echo "or point FG_BIN at your fgfs binary." >&2
  exit 1
fi

exec "$FG_BIN" \
  --fdm=network,localhost,5501,5502,5503 \
  --aircraft="$FG_AIRCRAFT" \
  --airport="$FG_AIRPORT" \
  --altitude="$FG_ALT_FT" \
  --disable-clouds --disable-sound --disable-random-objects \
  --disable-ai-models --fog-fastest --timeofday=noon \
  --prop:/sim/frame-rate-throttle-hz=60
