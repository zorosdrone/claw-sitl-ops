#!/usr/bin/env bash
set -euo pipefail

# Discord/chat command dispatcher for sitl_mav.py
# Examples:
#   bash skills/sitl-ops/scripts/sitl_dispatch.sh "!sitl start"
#   bash skills/sitl-ops/scripts/sitl_dispatch.sh "!sitl stop"
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
AP_ROOT="${SITL_AP_ROOT:-$ROOT/GitHub/ardupilot}"
AP_VENV_ACTIVATE="${SITL_AP_VENV_ACTIVATE:-/home/hfuji/venv-ardupilot/bin/activate}"
SITL_START_ARGS="${SITL_START_ARGS:--v Copter -L Kawachi --no-mavproxy}"
SITL_LOG="${SITL_LOG:-/tmp/sitl_copter.log}"

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

resolve_master() {
  if [[ -n "${SITL_MASTER:-}" ]]; then
    echo "$SITL_MASTER"
    return
  fi
  if pgrep -f "[m]avproxy.py" >/dev/null; then
    echo "udp:127.0.0.1:14550"
    return
  fi
  if ss -ltn | grep -q ':5760'; then
    echo "tcp:127.0.0.1:5760"
    return
  fi
  echo "$MASTER"
}

if [[ "$cmd" =~ ^!?sitl[[:space:]]+start$ ]]; then
  if pgrep -f "[s]im_vehicle.py.*-v[[:space:]]+Copter" >/dev/null || pgrep -f "[a]rducopter" >/dev/null; then
    echo '{"ok":true,"action":"start","status":"already_running"}'
    exit 0
  fi
  if [[ ! -d "$AP_ROOT" ]]; then
    echo "{\"ok\":false,\"error\":\"AP_ROOT not found: $AP_ROOT\"}"
    exit 1
  fi
  nohup bash -lc "cd '$AP_ROOT' && source '$AP_VENV_ACTIVATE' && ./Tools/autotest/sim_vehicle.py $SITL_START_ARGS" >"$SITL_LOG" 2>&1 &
  sleep 1
  if pgrep -f "[s]im_vehicle.py.*-v[[:space:]]+Copter" >/dev/null || pgrep -f "[a]rducopter" >/dev/null; then
    echo "{\"ok\":true,\"action\":\"start\",\"status\":\"started\",\"log\":\"$SITL_LOG\"}"
  else
    echo "{\"ok\":false,\"action\":\"start\",\"status\":\"failed\",\"log\":\"$SITL_LOG\"}"
    exit 1
  fi
elif [[ "$cmd" =~ ^!?sitl[[:space:]]+stop$ ]]; then
  pkill -f "[s]im_vehicle.py.*-v[[:space:]]+Copter" || true
  pkill -f "[a]rducopter" || true
  pkill -f "[m]avproxy.py" || true
  sleep 1
  if pgrep -f "[s]im_vehicle.py|[a]rducopter|[m]avproxy.py" >/dev/null; then
    echo '{"ok":false,"action":"stop","status":"still_running"}'
    exit 1
  fi
  echo '{"ok":true,"action":"stop","status":"stopped"}'
elif [[ "$cmd" =~ ^!?sitl[[:space:]]+status$ ]]; then
  ACTIVE_MASTER="$(resolve_master)"
  "$PY_CMD" "$PY" --master "$ACTIVE_MASTER" status
elif [[ "$cmd" =~ ^!?sitl[[:space:]]+arm$ ]]; then
  ACTIVE_MASTER="$(resolve_master)"
  "$PY_CMD" "$PY" --master "$ACTIVE_MASTER" arm
elif [[ "$cmd" =~ ^!?sitl[[:space:]]+takeoff[[:space:]]+([0-9]+([.][0-9]+)?)$ ]]; then
  alt="${BASH_REMATCH[1]}"
  ACTIVE_MASTER="$(resolve_master)"
  "$PY_CMD" "$PY" --master "$ACTIVE_MASTER" takeoff --alt "$alt"
elif [[ "$cmd" =~ ^!?sitl[[:space:]]+mode[[:space:]]+([A-Za-z0-9_]+)$ ]]; then
  mode="${BASH_REMATCH[1]}"
  ACTIVE_MASTER="$(resolve_master)"
  "$PY_CMD" "$PY" --master "$ACTIVE_MASTER" mode --name "$mode"
elif [[ "$cmd" =~ ^!?sitl[[:space:]]+param[[:space:]]+get[[:space:]]+([A-Za-z0-9_]+)$ ]]; then
  p="${BASH_REMATCH[1]}"
  ACTIVE_MASTER="$(resolve_master)"
  "$PY_CMD" "$PY" --master "$ACTIVE_MASTER" param-get --name "$p"
elif [[ "$cmd" =~ ^!?sitl[[:space:]]+param[[:space:]]+set[[:space:]]+([A-Za-z0-9_]+)[[:space:]]+(-?[0-9]+([.][0-9]+)?)$ ]]; then
  p="${BASH_REMATCH[1]}"
  v="${BASH_REMATCH[2]}"
  ACTIVE_MASTER="$(resolve_master)"
  "$PY_CMD" "$PY" --master "$ACTIVE_MASTER" param-set --name "$p" --value "$v"
else
  cat <<'JSON'
{"ok":false,"error":"unsupported command","help":["!sitl start","!sitl stop","!sitl status","!sitl arm","!sitl takeoff <alt_m>","!sitl mode <MODE>","!sitl param get <NAME>","!sitl param set <NAME> <VALUE>"]}
JSON
  exit 2
fi
