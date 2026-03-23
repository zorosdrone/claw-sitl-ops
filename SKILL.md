---
name: sitl-ops
description: Operate ArduPilot SITL via MAVLink (start/stop/status, arm, takeoff, mode, param get/set) and report concise state for Discord or chat. Use when user asks to control SITL vehicle or query live vehicle telemetry/state.
---

# SITL Ops (ArduPilot MAVLink)

Use this skill for **SITL only** operations.

## Safety Defaults
- Target endpoint is local by default: `udp:127.0.0.1:14550`
- Do not send control commands unless user explicitly asks.
- For potentially risky commands (arm/takeoff/mode/param set), confirm intent if ambiguous.

If `~/.openclaw/workspace/.sitl-ops.env` exists, dispatcher loads it automatically before resolving endpoints or start/stop settings.

## Setup (one-time)

```bash
bash skills/sitl-ops/scripts/setup_venv.sh
```

## Commands (via bundled script)

Use:

```bash
python3 skills/sitl-ops/scripts/sitl_mav.py --help
```

For Discord/chat command-style input, use dispatcher:

```bash
bash skills/sitl-ops/scripts/sitl_dispatch.sh "!sitl status"
```

### State query
```bash
python3 skills/sitl-ops/scripts/sitl_mav.py status
```
Returns: mode, armed, battery, lat/lon/alt, roll/pitch/yaw, map_url (Google Maps pin).

### Arm
```bash
python3 skills/sitl-ops/scripts/sitl_mav.py arm
```

### Takeoff (meters)
```bash
python3 skills/sitl-ops/scripts/sitl_mav.py takeoff --alt 10
```
Important:
- Use `MAV_CMD_NAV_TAKEOFF` flow (`sitl_mav.py takeoff`) for liftoff from ground.
- Do **not** use only position-target commands for initial liftoff from disarmed/just-armed state (can trigger auto-disarm race and no climb).
- After takeoff command, wait 3–5s then run `status` to verify climb.

### Mode change
```bash
python3 skills/sitl-ops/scripts/sitl_mav.py mode --name GUIDED
```

### Parameter get/set
```bash
python3 skills/sitl-ops/scripts/sitl_mav.py param-get --name ARMING_CHECK
python3 skills/sitl-ops/scripts/sitl_mav.py param-set --name ARMING_CHECK --value 1
```

## Discord handling style
When request comes from Discord, keep responses short:
- Action result (OK/NG)
- Key state line (mode/armed/battery/position)
- Error reason (if any)

Recommended Discord command mapping:
- `!sitl start`
- `!sitl stop`
- `!sitl status`
- `!sitl arm`
- `!sitl takeoff 10`
- `!sitl mode GUIDED`
- `!sitl param get ARMING_CHECK`
- `!sitl param set ARMING_CHECK 1`

Execution pattern:
1. Parse user message (if starts with `!sitl`)
2. Run `bash skills/sitl-ops/scripts/sitl_dispatch.sh "<user_message>"`
3. Return concise result + one-line state summary

### Persistent config file

You can persist settings without `export` by creating:

```bash
~/.openclaw/workspace/.sitl-ops.env
```

Start from one of these:

```bash
cp skills/sitl-ops/sitl-ops.local.env.example ~/.openclaw/workspace/.sitl-ops.env
cp skills/sitl-ops/sitl-ops.remote.env.example ~/.openclaw/workspace/.sitl-ops.env
```

Use `sitl-ops.local.env.example` for same-host Linux operation.

Use `sitl-ops.remote.env.example` for VPS + WSL split operation.

Typical remote WSL settings:

```bash
SITL_MASTER="udp:100.64.10.20:14550"
SITL_REMOTE_SSH_TARGET="user@100.64.10.20"
SITL_REMOTE_AP_ROOT="$HOME/ardupilot"
SITL_REMOTE_AP_VENV_ACTIVATE="$HOME/venv-ardupilot/bin/activate"
SITL_REMOTE_START_ARGS="-v Copter -L Kawachi --no-mavproxy --out=0.0.0.0:14550"
```

When `SITL_REMOTE_SSH_TARGET` is set, `!sitl start` and `!sitl stop` are executed over SSH on that remote host.

## Build/Dependency Recovery Playbook (mandatory when build fails)
When SITL build/start fails due missing Python package(s), attempt auto-recovery before reporting failure.

1. Capture last error log:
```bash
tail -n 120 /tmp/sitl_copter.log
```
2. If error contains `you need to install empy`, `ModuleNotFoundError`, or `No such file or directory: 'mavproxy.py'`:
```bash
bash skills/sitl-ops/scripts/setup_venv.sh
```
3. If system python still complains (PEP668 / externally-managed env), run fallback install command:
```bash
python3 -m pip install --user --break-system-packages empy==3.3.4 pymavlink MAVProxy
```
4. Never delete `build/` or run `waf clean` during routine recovery. Preserve incremental build cache.
5. Preflight-check `mavproxy.py` before `sim_vehicle.py` launch:
```bash
cd /home/hfuji/.openclaw/workspace/GitHub/ardupilot
./.venv/bin/mavproxy.py --help >/dev/null
```
If this fails, run:
```bash
./.venv/bin/python -m pip install MAVProxy
```
6. Ensure `.venv/bin` is on PATH when launching sim_vehicle (so `mavproxy.py` is found).
7. For restart-only cases (no source/config change), start with `-N` to skip rebuild:
```bash
cd /home/hfuji/.openclaw/workspace/GitHub/ardupilot
nohup env PATH="/home/hfuji/.openclaw/workspace/GitHub/ardupilot/.venv/bin:$PATH" ./Tools/autotest/sim_vehicle.py -N -v Copter -L Kawachi --out=100.76.194.34:14550 > /tmp/sitl_copter.log 2>&1 &
```
8. Only if binary missing or build actually required, run normal start (rebuild allowed):
```bash
cd /home/hfuji/.openclaw/workspace/GitHub/ardupilot
nohup env PATH="/home/hfuji/.openclaw/workspace/GitHub/ardupilot/.venv/bin:$PATH" ./Tools/autotest/sim_vehicle.py -v Copter -L Kawachi --out=100.76.194.34:14550 > /tmp/sitl_copter.log 2>&1 &
```
9. Re-check heartbeat and report result.

## Notes
- Requires `pymavlink` in runtime (`pip install pymavlink`).
- `setup_venv.sh` installs `pymavlink`, `empy==3.3.4`, and `MAVProxy`.
- Dispatcher prefers `~/.openclaw/workspace/.venv/bin/python` when present.
- Override Python with `SITL_VENV_PYTHON=/path/to/python`.
- `!sitl start/stop` uses `sim_vehicle.py` and supports:
  - `SITL_AP_ROOT` (default: `/home/hfuji/.openclaw/workspace/GitHub/ardupilot`)
  - `SITL_AP_VENV_ACTIVATE` (default: `/home/hfuji/venv-ardupilot/bin/activate`)
  - `SITL_START_ARGS` (default: `-v Copter -L Kawachi --no-mavproxy`)
  - `SITL_LOG` (default: `/tmp/sitl_copter.log`)
- Remote `!sitl start/stop` over SSH is enabled when these are set:
  - `SITL_REMOTE_SSH_TARGET` (example: `user@100.64.10.20`)
  - `SITL_REMOTE_SSH_PORT` (default: `22`)
  - `SITL_REMOTE_AP_ROOT`
  - `SITL_REMOTE_AP_VENV_ACTIVATE`
  - `SITL_REMOTE_START_ARGS`
  - `SITL_REMOTE_LOG`
- Command endpoint auto-resolution (when `SITL_MASTER` unset):
  - if `mavproxy.py` is running: `udp:127.0.0.1:14550`
  - else if SITL TCP is listening: `tcp:127.0.0.1:5760`
- Override endpoint with `SITL_MASTER=udp:127.0.0.1:14551` (or tcp).
- Dispatcher auto-loads config from `~/.openclaw/workspace/.sitl-ops.env` or `~/.openclaw/workspace/skills/sitl-ops/.sitl-ops.env`.
