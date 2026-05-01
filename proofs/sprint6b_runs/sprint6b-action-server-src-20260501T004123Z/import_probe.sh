#!/bin/sh
set -eu
/openhands/micromamba/bin/micromamba run -n openhands poetry run python - <<'PY'
import httpx, fastapi
import openhands.runtime.action_execution_server as s
print('imports_ok')
PY
