#!/bin/sh
# Phase 0 spike for Visual Player.
#
# Plays a video for a few seconds with the same mpv settings Visual Player
# will use, then writes a report showing whether HDR output, hardware
# decoding, audio passthrough, and display detection work on this machine.
#
# Usage:
#   ./tools/spike/run-spike.sh VIDEO_FILE [--device AUDIO_DEVICE] [--passthrough]
#
# To list your audio devices:
#   mpv --audio-device=help

set -eu

print_usage() {
    echo "Usage: $0 VIDEO_FILE [--device AUDIO_DEVICE] [--passthrough]"
}

if [ $# -lt 1 ]; then
    print_usage
    exit 1
fi

video_file=$1
shift

audio_device="auto"
use_passthrough="no"

while [ $# -gt 0 ]; do
    case $1 in
        --device)
            audio_device=$2
            shift 2
            ;;
        --passthrough)
            use_passthrough="yes"
            shift
            ;;
        *)
            print_usage
            exit 1
            ;;
    esac
done

if [ ! -f "$video_file" ]; then
    echo "Can't find the video file: $video_file"
    exit 1
fi

script_folder=$(cd "$(dirname "$0")" && pwd)
report_file="$PWD/spike-report-$(uname -n)-$(date +%Y%m%d-%H%M%S).txt"

# Collect information about the system before playing anything.
{
    echo "Visual Player spike report"
    echo "=========================="
    echo
    echo "== System =="
    . /etc/os-release
    echo "Distro:  $PRETTY_NAME"
    echo "Desktop: ${XDG_CURRENT_DESKTOP:-unknown}"
    echo "Session: ${XDG_SESSION_TYPE:-unknown}"
    echo "Kernel:  $(uname -r)"
    echo
    echo "== Graphics card =="
    if command -v lspci > /dev/null; then
        lspci | grep -Ei 'vga|3d|display' || echo "No graphics card listed"
    else
        echo "lspci isn't installed, so the graphics card is unknown"
    fi
    echo
    echo "== mpv =="
    mpv --version | head -n 1
    echo
    echo "== Test settings =="
    echo "Video file:   $video_file"
    echo "Audio device: $audio_device"
    echo "Passthrough:  $use_passthrough"
    echo
} > "$report_file"

# Receivers decode Atmos and DTS:X themselves, so passthrough sends the
# untouched audio bitstream instead of decoding it inside mpv.
passthrough_option=""
if [ "$use_passthrough" = "yes" ]; then
    passthrough_option="--audio-spdif=ac3,eac3,dts,dts-hd,truehd"
fi

echo "Playing for a few seconds. The window closes by itself."

# --no-config keeps your personal mpv settings from affecting the test.
# shellcheck disable=SC2086
mpv --no-config \
    --vo=gpu-next \
    --hwdec=auto-safe \
    --target-colorspace-hint=yes \
    --audio-device="$audio_device" \
    $passthrough_option \
    --script="$script_folder/spike.lua" \
    --script-opts="spike-report=$report_file" \
    --really-quiet \
    "$video_file"

echo
echo "Done. Report saved to:"
echo "  $report_file"
