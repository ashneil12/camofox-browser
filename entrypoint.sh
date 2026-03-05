#!/bin/bash
# entrypoint.sh — Start VNC services + Camofox browser server.
#
# When ENABLE_VNC=1 (default), launches:
#   1. Xvfb  — virtual X display on :99
#   2. x11vnc — VNC server exposing :99 on port 5900
#   3. noVNC  — WebSocket proxy (port 6080 → VNC 5900)
#   4. Camofox server — renders Firefox to :99, REST API on $CAMOFOX_PORT
#
# Set ENABLE_VNC=0 to run headless (no VNC layer), matching upstream behavior.
set -e

ENABLE_VNC="${ENABLE_VNC:-1}"
VNC_PORT="${VNC_PORT:-5900}"
NOVNC_PORT="${NOVNC_PORT:-6080}"
DISPLAY_NUM="${DISPLAY_NUM:-99}"
SCREEN_RESOLUTION="${SCREEN_RESOLUTION:-1280x720x24}"

if [ "$ENABLE_VNC" = "1" ]; then
    echo "[entrypoint] Starting VNC layer (display=:${DISPLAY_NUM}, resolution=${SCREEN_RESOLUTION})"

    # Start virtual framebuffer
    Xvfb ":${DISPLAY_NUM}" -screen 0 "${SCREEN_RESOLUTION}" -ac +extension GLX +render -noreset &
    XVFB_PID=$!
    export DISPLAY=":${DISPLAY_NUM}"

    # Wait for Xvfb to be ready
    for i in $(seq 1 20); do
        if xdpyinfo -display ":${DISPLAY_NUM}" >/dev/null 2>&1; then
            break
        fi
        sleep 0.25
    done

    # Start VNC server (no password, shared mode, background)
    x11vnc -display ":${DISPLAY_NUM}" -nopw -forever -shared \
           -rfbport "${VNC_PORT}" -bg -o /tmp/x11vnc.log 2>&1

    # Determine noVNC web directory
    NOVNC_WEB="/usr/share/novnc"
    if [ ! -d "$NOVNC_WEB" ]; then
        NOVNC_WEB="/usr/share/novnc/utils/../"
    fi

    # Start noVNC websocket proxy
    websockify --web "${NOVNC_WEB}" "${NOVNC_PORT}" "localhost:${VNC_PORT}" &
    WEBSOCKIFY_PID=$!

    echo "[entrypoint] VNC ready — noVNC at http://0.0.0.0:${NOVNC_PORT}/vnc.html"

    # Cleanup on exit
    trap "kill $XVFB_PID $WEBSOCKIFY_PID 2>/dev/null || true" EXIT
else
    echo "[entrypoint] VNC disabled (ENABLE_VNC=0), running headless"
    export DISPLAY=":${DISPLAY_NUM}"
    Xvfb ":${DISPLAY_NUM}" -screen 0 "${SCREEN_RESOLUTION}" -ac +extension GLX +render -noreset &
    trap "kill $! 2>/dev/null || true" EXIT

    # Wait for Xvfb
    for i in $(seq 1 20); do
        if xdpyinfo -display ":${DISPLAY_NUM}" >/dev/null 2>&1; then
            break
        fi
        sleep 0.25
    done
fi

# Start Camofox server (foreground — container dies if this exits)
exec node --max-old-space-size="${MAX_OLD_SPACE_SIZE:-128}" server.js
