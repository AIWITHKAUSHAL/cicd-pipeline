#!/usr/bin/env bash
# Poll the LIVE service continuously and print what real users are getting.
# Leave this running in a side terminal, then run switch-color.sh in another:
# the flip shows up here on its own, which is the point being demonstrated.
#   ./scripts/watch-live.sh            # watches live  (:30080)
#   ./scripts/watch-live.sh 30081      # watches preview (:30081)
set -uo pipefail

PORT="${1:-30080}"
prev=""

printf 'Watching http://localhost:%s/api/info  (Ctrl-C to stop)\n\n' "$PORT"

while true; do
  # --fail so an HTTP error is not mistaken for a colour; || true so one
  # dropped request during the switch does not kill the watch.
  body=$(curl -fsS -m 2 "http://localhost:${PORT}/api/info" 2>/dev/null) || body=""

  if [ -z "$body" ]; then
    color="unreachable"; ver="-"; pod="-"
  else
    color=$(printf '%s' "$body" | sed -n 's/.*"color":"\([^"]*\)".*/\1/p')
    ver=$(printf   '%s' "$body" | sed -n 's/.*"version":"\([^"]*\)".*/\1/p')
    pod=$(printf   '%s' "$body" | sed -n 's/.*"pod":"\([^"]*\)".*/\1/p')
  fi

  # Colour the output so the change is unmissable on video.
  case "$color" in
    blue)  tint=$'\033[1;36m' ;;   # cyan
    green) tint=$'\033[1;32m' ;;   # green
    *)     tint=$'\033[1;31m' ;;   # red
  esac

  printf '%s  %s%-6s\033[0m  version=%-4s  pod=%s\n' \
    "$(date +%H:%M:%S)" "$tint" "$color" "$ver" "$pod"

  # Call out the exact moment traffic moves.
  if [ -n "$prev" ] && [ "$color" != "$prev" ]; then
    printf '   %s^^^ LIVE TRAFFIC MOVED: %s -> %s\033[0m\n' $'\033[1;33m' "$prev" "$color"
  fi
  prev="$color"

  sleep 1
done
