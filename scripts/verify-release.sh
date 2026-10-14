#!/bin/bash
set -euo pipefail
exec python3 "$(dirname "$0")/verify-release.py" "$@"
