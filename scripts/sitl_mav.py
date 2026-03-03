#!/usr/bin/env python3
import argparse
import json
import math
import sys
import time
from pymavlink import mavutil


def connect(master: str, timeout: int = 15):
    m = mavutil.mavlink_connection(master)
    hb = m.wait_heartbeat(timeout=timeout)
    if hb is None:
        raise RuntimeError("No heartbeat from vehicle")
    return m


def get_mode_name(m):
    return mavutil.mode_string_v10(m.messages.get("HEARTBEAT")) if m.messages.get("HEARTBEAT") else "UNKNOWN"


def wait_msg(m, msg_type, timeout=5):
    return m.recv_match(type=msg_type, blocking=True, timeout=timeout)


def read_status(m):
    # Pull a few messages
    att = wait_msg(m, "ATTITUDE", 2)
    gps = wait_msg(m, "GLOBAL_POSITION_INT", 2)
    syss = wait_msg(m, "SYS_STATUS", 2)
    hb = m.messages.get("HEARTBEAT")

    armed = bool(hb.base_mode & mavutil.mavlink.MAV_MODE_FLAG_SAFETY_ARMED) if hb else False
    mode = get_mode_name(m)

    lat = lon = rel_alt = None
    if gps:
        lat = gps.lat / 1e7
        lon = gps.lon / 1e7
        rel_alt = gps.relative_alt / 1000.0

    roll = pitch = yaw = None
    if att:
        roll = math.degrees(att.roll)
        pitch = math.degrees(att.pitch)
        yaw = (math.degrees(att.yaw) + 360) % 360

    batt = None
    if syss and syss.battery_remaining != -1:
        batt = int(syss.battery_remaining)

    map_url = None
    if lat is not None and lon is not None:
        map_url = f"https://maps.google.com/?q={lat},{lon}"

    return {
        "mode": mode,
        "armed": armed,
        "battery_remaining_pct": batt,
        "position": {"lat": lat, "lon": lon, "relative_alt_m": rel_alt},
        "attitude_deg": {"roll": roll, "pitch": pitch, "yaw": yaw},
        "map_url": map_url,
    }


def cmd_arm(m):
    m.arducopter_arm()
    m.motors_armed_wait()
    return True


def cmd_takeoff(m, alt):
    # Must be in GUIDED for ArduCopter SITL usually
    m.set_mode_apm("GUIDED")
    time.sleep(0.3)
    if not m.motors_armed():
        m.arducopter_arm()
        m.motors_armed_wait()

    m.mav.command_long_send(
        m.target_system,
        m.target_component,
        mavutil.mavlink.MAV_CMD_NAV_TAKEOFF,
        0,
        0, 0, 0, 0,
        0, 0, float(alt),
    )
    return True


def cmd_mode(m, name):
    ok = m.set_mode_apm(name.upper())
    if ok is False:
        raise RuntimeError(f"Failed to set mode: {name}")
    return True


def cmd_param_get(m, name):
    m.mav.param_request_read_send(
        m.target_system,
        m.target_component,
        name.encode("utf-8"),
        -1,
    )
    rsp = m.recv_match(type="PARAM_VALUE", blocking=True, timeout=5)
    if not rsp:
        raise RuntimeError(f"Param not found or timeout: {name}")
    return rsp.param_value


def cmd_param_set(m, name, value):
    m.mav.param_set_send(
        m.target_system,
        m.target_component,
        name.encode("utf-8"),
        float(value),
        mavutil.mavlink.MAV_PARAM_TYPE_REAL32,
    )
    time.sleep(0.2)
    return cmd_param_get(m, name)


def main():
    p = argparse.ArgumentParser(description="SITL MAVLink ops")
    p.add_argument("--master", default="udp:127.0.0.1:14550", help="MAVLink endpoint")

    sub = p.add_subparsers(dest="cmd", required=True)
    sub.add_parser("status")
    sub.add_parser("arm")

    tk = sub.add_parser("takeoff")
    tk.add_argument("--alt", type=float, required=True)

    md = sub.add_parser("mode")
    md.add_argument("--name", required=True)

    pg = sub.add_parser("param-get")
    pg.add_argument("--name", required=True)

    ps = sub.add_parser("param-set")
    ps.add_argument("--name", required=True)
    ps.add_argument("--value", required=True, type=float)

    args = p.parse_args()

    try:
        m = connect(args.master)
        if args.cmd == "status":
            out = read_status(m)
        elif args.cmd == "arm":
            cmd_arm(m)
            out = {"ok": True, "action": "arm", "status": read_status(m)}
        elif args.cmd == "takeoff":
            cmd_takeoff(m, args.alt)
            out = {"ok": True, "action": "takeoff", "target_alt_m": args.alt, "status": read_status(m)}
        elif args.cmd == "mode":
            cmd_mode(m, args.name)
            out = {"ok": True, "action": "mode", "mode": args.name.upper(), "status": read_status(m)}
        elif args.cmd == "param-get":
            val = cmd_param_get(m, args.name)
            out = {"ok": True, "action": "param-get", "name": args.name, "value": val}
        elif args.cmd == "param-set":
            val = cmd_param_set(m, args.name, args.value)
            out = {"ok": True, "action": "param-set", "name": args.name, "value": val}
        else:
            raise RuntimeError("Unknown command")

        print(json.dumps(out, ensure_ascii=False))
    except Exception as e:
        print(json.dumps({"ok": False, "error": str(e)}, ensure_ascii=False))
        sys.exit(1)


if __name__ == "__main__":
    main()
