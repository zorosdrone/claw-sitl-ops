#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
cd "$ROOT"

python3 -m venv .venv
source .venv/bin/activate
python -m pip install -U pip
python -m pip install pymavlink empy==3.3.4 MAVProxy

echo "OK: .venv ready with pymavlink + empy + MAVProxy"
echo "Use: export SITL_VENV_PYTHON=$ROOT/.venv/bin/python"
