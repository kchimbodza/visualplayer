#!/bin/sh
# Phase 0 button test for Visual Player.
#
# Opens a video with a small test interface drawn on top of it, to check
# that hovering, clicking, and dragging work before we build the real UI.
#
# Usage:
#   ./tools/spike/run-button-test.sh VIDEO_FILE
#
# Press q to quit when you're done.

set -eu

if [ $# -lt 1 ]; then
    echo "Usage: $0 VIDEO_FILE"
    exit 1
fi

if [ ! -f "$1" ]; then
    echo "Can't find the video file: $1"
    exit 1
fi

script_folder=$(cd "$(dirname "$0")" && pwd)

# --border=no removes the window frame, like Visual Player will, so we can
# check that dragging our own title bar moves the window.
# --keep-open=yes stops the window closing when a short clip ends.
exec mpv --no-config \
    --vo=gpu-next \
    --hwdec=auto-safe \
    --osc=no \
    --border=no \
    --keep-open=yes \
    --script="$script_folder/button-test.lua" \
    "$1"
