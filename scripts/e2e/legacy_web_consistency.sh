#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

if [[ $# -ne 1 ]]; then
  echo "usage: ./scripts/e2e/legacy_web_consistency.sh <admin-url>" >&2
  exit 1
fi

echo "running legacy-check: cli vs apps/desktop consistency"
bun "$ROOT_DIR/scripts/e2e/validate_cli_desktop_consistency.ts" "$1"
