#!/usr/bin/env bash
set -euo pipefail
AIOS_HOME="${AIOS_HOME:-$HOME/aios}"
# set -a: everything sourced from aios.env is exported into the environment
# (uvicorn/python child), not just kept as shell-local variables.
set -a
source "$AIOS_HOME/config/aios.env" 2>/dev/null || true
set +a
source "$AIOS_HOME/.venv/bin/activate"
export AIOS_HOME PYTHONPATH="$AIOS_HOME/src"
export HF_HUB_ENABLE_HF_TRANSFER=1
cd "$AIOS_HOME/src"
exec uvicorn app:app \
  --host 127.0.0.1 \
  --port "${AIOS_PORT:-8778}" \
  --workers 1 \
  --no-access-log \
  --log-level warning
