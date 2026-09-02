#!/usr/bin/env bash
#
# runfg.sh - launch FlightGear as a passive out-the-window visualiser for the
# Citation Simulink model on macOS.
#
# The model's "FlightGear Visualisation" block (Aerospace Blockset, not
# Simulink 3D Animation) streams net_fdm packets to localhost:5502.
# FlightGear just renders them - it runs no dynamics of its own here.
#
#   1. Start this script and wait until FlightGear is sitting on the runway.
#   2. Then start the Simulink simulation. The aircraft will follow the model.
#
# FlightGear is optional: the model runs headless without it, and the
# toolbox-free "Cockpit View" block (matlab/setup/add_cockpit_view.m) is a
# lighter alternative.
#
# Install:  brew install --cask flightgear      (~2 GB with base scenery)
#
# Env overrides:
#   FG_BIN       path to the fgfs binary
#   FG_AIRCRAFT  FlightGear aircraft id            (default c172p, ships with FG)
#   FG_AIRPORT   ICAO to place the aircraft at     (default EHAM, Schiphol)
#   FG_ALT_FT    start altitude, feet              (default 24600 ~ 7500 m trim)
#   FG_EXTRA     extra args, word-split
#
set -euo pipefail

# --- locate the FlightGear binary --------------------------------------
# The macOS app bundle ships it as .../MacOS/FlightGear (not "fgfs");
# Homebrew/MacPorts and Linux builds call it "fgfs". Same CLI either way.
CANDIDATES=(
  "${FG_BIN:-}"
  /Applications/FlightGear*.app/Contents/MacOS/FlightGear
  /Applications/FlightGear*.app/Contents/MacOS/fgfs
  "$(command -v fgfs 2>/dev/null || true)"
  /opt/homebrew/bin/fgfs
  /opt/local/bin/fgfs
)
FG_BIN=""
for c in "${CANDIDATES[@]}"; do
  [[ -n "$c" && -x "$c" ]] && { FG_BIN="$c"; break; }
done
if [[ -z "$FG_BIN" ]]; then
  cat >&2 <<'EOF'
fgfs not found. Install FlightGear:

    brew install --cask flightgear

or download from https://www.flightgear.org/download/ , or set FG_BIN to your
fgfs binary. The Simulink model still runs without FlightGear.
EOF
  exit 1
fi

FG_AIRCRAFT="${FG_AIRCRAFT:-c172p}"
FG_AIRPORT="${FG_AIRPORT:-EHAM}"
FG_ALT_FT="${FG_ALT_FT:-24600}"
FG_EXTRA_ARR=()
[[ -n "${FG_EXTRA:-}" ]] && read -r -a FG_EXTRA_ARR <<< "${FG_EXTRA}"

echo "binary      : $FG_BIN"
echo "listening   : net_fdm on udp/5502  (start the Simulink sim once FG is loaded)"
echo

# --- run ---------------------------------------------------------------
# --fdm=network,<host>,<out>,<in>,<cmd> : receive net_fdm on 5502 from Simulink
exec "$FG_BIN" \
  --fdm=network,localhost,5501,5502,5503 \
  --max-fps=60 \
  --aircraft="$FG_AIRCRAFT" \
  --airport="$FG_AIRPORT" \
  --altitude="$FG_ALT_FT" \
  --timeofday=noon \
  --disable-clouds --disable-sound --disable-ai-models \
  --disable-random-objects --disable-real-weather-fetch \
  --prop:/sim/frame-rate-throttle-hz=60 \
  ${FG_EXTRA_ARR[@]+"${FG_EXTRA_ARR[@]}"}
