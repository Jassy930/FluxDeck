#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

failures=0

echo "[check] docs/plans 根目录是否残留普通计划文档"
root_plan_files="$(find docs/plans -maxdepth 1 -type f -name '*.md' ! -name 'README.md' | sort)"
if [[ -n "$root_plan_files" ]]; then
  failures=1
  echo "发现未归档的根目录计划文档："
  echo "$root_plan_files"
else
  echo "ok"
fi

echo
echo "[check] docs/plans/active 是否混入完成态文档"
active_completed_matches="$(
  rg -n \
    -e 'Status: completed and locally verified' \
    -e '^## Verification Results' \
    -e '^## 实施结果$' \
    docs/plans/active || true
)"
if [[ -n "$active_completed_matches" ]]; then
  failures=1
  echo "发现 active 目录中疑似已完成的文档信号："
  echo "$active_completed_matches"
else
  echo "ok"
fi

echo
if [[ "$failures" -ne 0 ]]; then
  echo "docs/plans 布局检查失败" >&2
  exit 1
fi

echo "docs/plans 布局检查通过"
