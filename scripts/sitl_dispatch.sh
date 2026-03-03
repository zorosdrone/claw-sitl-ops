#!/usr/bin/env bash
set -euo pipefail

# Discord/chat command dispatcher for sitl_mav.py
# Examples:
#   bash skills/sitl-ops/scripts/sitl_dispatch.sh "!sitl status"
#   bash skills/sitl-ops/scripts/sitl_dispatch.sh "!sitl arm"
#   bash skills/sitl-ops/scripts/sitl_dispatch.sh "!sitl takeoff 10"
#   bash skills/sitl-ops/scripts/sitl_dispatch.sh "!sitl mode GUIDED"
#   bash skills/sitl-ops/scripts/sitl_dispatch.sh "!sitl param get ARMING_CHECK"
#   bash skills/sitl-ops/scripts/sitl_dispatch.sh "!sitl param set ARMING_CHECK 1"

ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
PY="$ROOT/skills/sitl-ops/scripts/sitl_mav.py"
MASTER="${SITL_MASTER:-udp:127.0.0.1:14550}"
VENV_PY="${SITL_VENV_PYTHON:-$ROOT/.venv/bin/python}"

cmd="${1:-}"
if [[ -z "$cmd" ]]; then
  echo '{"ok":false,"error":"empty command"}'
  exit 1
fi

# Normalize spaces
cmd="$(echo "$cmd" | xargs)"

PY_CMD="python3"
if [[ -x "$VENV_PY" ]]; then
  PY_CMD="$VENV_PY"
fi

if [[ "$cmd" =~ ^!sitl[[:space:]]+status$ ]]; then
  "$PY_CMD" "$PY" --master "$MASTER" status
elif [[ "$cmd" =~ ^!sitl[[:space:]]+arm$ ]]; then
  "$PY_CMD" "$PY" --master "$MASTER" arm
elif [[ "$cmd" =~ ^!sitl[[:space:]]+takeoff[[:space:]]+([0-9]+([.][0-9]+)?)$ ]]; then
  alt="${BASH_REMATCH[1]}"
  "$PY_CMD" "$PY" --master "$MASTER" takeoff --alt "$alt"
elif [[ "$cmd" =~ ^!sitl[[:space:]]+mode[[:space:]]+([A-Za-z0-9_]+)$ ]]; then
  mode="${BASH_REMATCH[1]}"
  "$PY_CMD" "$PY" --master "$MASTER" mode --name "$mode"
elif [[ "$cmd" =~ ^!sitl[[:space:]]+param[[:space:]]+get[[:space:]]+([A-Za-z0-9_]+)$ ]]; then
  p="${BASH_REMATCH[1]}"
  "$PY_CMD" "$PY" --master "$MASTER" param-get --name "$p"
elif [[ "$cmd" =~ ^!sitl[[:space:]]+param[[:space:]]+set[[:space:]]+([A-Za-z0-9_]+)[[:space:]]+(-?[0-9]+([.][0-9]+)?)$ ]]; then
  p="${BASH_REMATCH[1]}"
  v="${BASH_REMATCH[2]}"
  "$PY_CMD" "$PY" --master "$MASTER" param-set --name "$p" --value "$v"
else
  cat <<'JSON'
{"ok":false,"error":"unsupported command","help":["!sitl status","!sitl arm","!sitl takeoff <alt_m>","!sitl mode <MODE>","!sitl param get <NAME>","!sitl param set <NAME> <VALUE>"]}
JSON
  exit 2
fi
