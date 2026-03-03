# openclaw-skill-sitl-ops

OpenClaw Skill for operating ArduPilot SITL over MAVLink (status, arm, takeoff, mode, param get/set).

## Files
- `SKILL.md`
- `scripts/sitl_mav.py`
- `scripts/sitl_dispatch.sh`
- `scripts/setup_venv.sh`

## Usage
Use this skill inside OpenClaw by placing this folder under your skills path.

Then follow `SKILL.md` instructions.

## How this skill was bootstrapped (OpenClaw TUI)

Initial implementation was created interactively in `openclaw tui` by asking the agent to generate a first working skill skeleton:

- Create `SKILL.md` and Python/dispatch scripts for MAVLink-based SITL control
- Define core commands first (`status`, `arm`, `takeoff`, `mode`, `param get/set`)
- Keep responses machine-readable (JSON) so Discord replies could be formatted reliably

The first goal was not feature-completeness, but a thin end-to-end path:
`command -> MAVLink action -> observable status`.

## How it was evolved from Discord conversations

After the initial TUI scaffold, most improvements were driven via Discord in a rapid Try & Error loop.

Typical flow:
1. Run command from chat (e.g. `!sitl status`, movement, mission upload/start)
2. Observe result/failure
3. Patch skill/scripts
4. Re-test from chat
5. Commit incremental fix

### Concrete examples from the logs

- Added Google Maps URL in status output (`map_url`) to make position checks one-click from Discord
- Switched/standardized initial takeoff flow to `NAV_TAKEOFF` (`sitl_mav.py takeoff`) to avoid arm/disarm race conditions
- Validated mission workflow from chat:
  - square mission upload
  - star mission upload
  - mission start (`AUTO`)
  - post-start telemetry/status reporting
- Added/adjusted periodic status reporting behavior and stop controls based on operator requests

In short: **TUI built the base, Discord usage shaped reliability and UX.**
