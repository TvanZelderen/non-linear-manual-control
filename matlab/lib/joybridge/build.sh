#!/bin/sh
# Build the joybridge HID->UDP helper. Needs only the Xcode Command Line Tools
# (swiftc + the macOS SDK); no full Xcode, no third-party packages.
set -e
cd "$(dirname "$0")"
swiftc -O joybridge.swift \
    -framework IOKit -framework CoreFoundation -framework Foundation \
    -o joybridge
echo "built: $(pwd)/joybridge"
