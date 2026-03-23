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
CONFIG_FILE="${SITL_OPS_CONFIG:-}"

if [[ -z "$CONFIG_FILE" ]]; then
  for candidate in "$ROOT/.sitl-ops.env" "$ROOT/skills/sitl-ops/.sitl-ops.env"; do
    if [[ -f "$candidate" ]]; then
      CONFIG_FILE="$candidate"
      break
    fi
  done
fi

if [[ -n "$CONFIG_FILE" ]]; then
  if [[ ! -f "$CONFIG_FILE" ]]; then
    echo "{\"ok\":false,\"error\":\"config file not found: $CONFIG_FILE\"}"
    exit 1
  fi
  set -a
  # shellcheck disable=SC1090
  source "$CONFIG_FILE"
  set +a
fi

PY="$ROOT/skills/sitl-ops/scripts/sitl_mav.py"
MASTER="${SITL_MASTER:-udp:127.0.0.1:14550}"
VENV_PY="${SITL_VENV_PYTHON:-$ROOT/.venv/bin/python}"
AP_ROOT="${SITL_AP_ROOT:-$ROOT/GitHub/ardupilot}"
AP_VENV_ACTIVATE="${SITL_AP_VENV_ACTIVATE:-/home/hfuji/venv-ardupilot/bin/activate}"
SITL_START_ARGS="${SITL_START_ARGS:--v Copter -L Kawachi --no-mavproxy}"
SITL_LOG="${SITL_LOG:-/tmp/sitl_copter.log}"
REMOTE_SSH_TARGET="${SITL_REMOTE_SSH_TARGET:-}"
REMOTE_SSH_PORT="${SITL_REMOTE_SSH_PORT:-22}"
REMOTE_AP_ROOT="${SITL_REMOTE_AP_ROOT:-$AP_ROOT}"
REMOTE_AP_VENV_ACTIVATE="${SITL_REMOTE_AP_VENV_ACTIVATE:-$AP_VENV_ACTIVATE}"
REMOTE_START_ARGS="${SITL_REMOTE_START_ARGS:-$SITL_START_ARGS}"
REMOTE_LOG="${SITL_REMOTE_LOG:-$SITL_LOG}"

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

use_remote_start_stop() {
  [[ -n "$REMOTE_SSH_TARGET" ]]
}

ensure_ssh_available() {
  if ! command -v ssh >/dev/null 2>&1; then
    echo '{"ok":false,"error":"ssh command not found"}'
    exit 1
  fi
}

remote_start() {
  ensure_ssh_available

  ssh \
    -o BatchMode=yes \
    -o StrictHostKeyChecking=accept-new \
    -p "$REMOTE_SSH_PORT" \
    "$REMOTE_SSH_TARGET" \
    bash -s -- "$REMOTE_AP_ROOT" "$REMOTE_AP_VENV_ACTIVATE" "$REMOTE_START_ARGS" "$REMOTE_LOG" <<'EOF'
set -euo pipefail

ap_root="$1"
ap_venv_activate="$2"
sitl_start_args="$3"
sitl_log="$4"

if pgrep -f "[s]im_vehicle.py.*-v[[:space:]]+Copter" >/dev/null || pgrep -f "[a]rducopter" >/dev/null; then
  echo '{"ok":true,"action":"start","status":"already_running","mode":"remote"}'
  exit 0
fi

if [[ ! -d "$ap_root" ]]; then
  echo "{\"ok\":false,\"error\":\"remote AP_ROOT not found: $ap_root\",\"mode\":\"remote\"}"
  exit 1
fi

nohup bash -lc "cd '$ap_root' && source '$ap_venv_activate' && ./Tools/autotest/sim_vehicle.py $sitl_start_args" >"$sitl_log" 2>&1 &
sleep 1

if pgrep -f "[s]im_vehicle.py.*-v[[:space:]]+Copter" >/dev/null || pgrep -f "[a]rducopter" >/dev/null; then
  echo "{\"ok\":true,\"action\":\"start\",\"status\":\"started\",\"mode\":\"remote\",\"log\":\"$sitl_log\"}"
else
  echo "{\"ok\":false,\"action\":\"start\",\"status\":\"failed\",\"mode\":\"remote\",\"log\":\"$sitl_log\"}"
  exit 1
fi
EOF
}

remote_stop() {
  ensure_ssh_available

  ssh \
    -o BatchMode=yes \
    -o StrictHostKeyChecking=accept-new \
    -p "$REMOTE_SSH_PORT" \
    "$REMOTE_SSH_TARGET" \
    bash -s -- <<'EOF'
set -euo pipefail

pkill -f "[s]im_vehicle.py.*-v[[:space:]]+Copter" || true
pkill -f "[a]rducopter" || true
pkill -f "[m]avproxy.py" || true
sleep 1

if pgrep -f "[s]im_vehicle.py|[a]rducopter|[m]avproxy.py" >/dev/null; then
  echo '{"ok":false,"action":"stop","status":"still_running","mode":"remote"}'
  exit 1
fi

echo '{"ok":true,"action":"stop","status":"stopped","mode":"remote"}'
EOF
}

if [[ "$cmd" =~ ^!?sitl[[:space:]]+start$ ]]; then
  if use_remote_start_stop; then
    remote_start
    exit 0
  fi
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
  if use_remote_start_stop; then
    remote_stop
    exit 0
  fi
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
