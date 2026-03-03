---
name: sitl-ops
description: Operate ArduPilot SITL via MAVLink (status, arm, takeoff, mode, param get/set) and report concise state for Discord or chat. Use when user asks to control SITL vehicle or query live vehicle telemetry/state.
---

# SITL Ops (ArduPilot MAVLink)

Use this skill for **SITL only** operations.

## Safety Defaults
- Target endpoint is local by default: `udp:127.0.0.1:14550`
- Do not send control commands unless user explicitly asks.
- For potentially risky commands (arm/takeoff/mode/param set), confirm intent if ambiguous.

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
- Default MAVLink endpoint is `udp:127.0.0.1:14550`.
- Override endpoint with `SITL_MASTER=udp:127.0.0.1:14551`.
