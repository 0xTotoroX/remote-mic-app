#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

fail() {
  printf 'repository governance check failed: %s\n' "$1" >&2
  exit 1
}

require_heading() {
  local file="$1"
  local heading="$2"
  grep -Fqx -- "$heading" "$file" || fail "$file is missing $heading"
}

require_text() {
  local file="$1"
  local text="$2"
  grep -Fq -- "$text" "$file" || fail "$file is missing required rule: $text"
}

[[ -f BRANCH_MANAGEMENT.md ]] || fail 'BRANCH_MANAGEMENT.md is missing'
[[ -f AGENTS.md ]] || fail 'AGENTS.md is missing'
[[ -f RELEASING.md ]] || fail 'RELEASING.md is missing'

for heading in \
  '## 标准功能与 Bug 流程' \
  '## PR 创建门禁' \
  '## 工作区状态审计' \
  '## TODO-only 工作流程' \
  '## 独立工作项提交边界' \
  '## 规范变更隔离与防护'; do
  require_heading BRANCH_MANAGEMENT.md "$heading"
done

require_text BRANCH_MANAGEMENT.md '所有 TODO-only 记录统一使用长期分支 `codex/todo_list`'
require_text BRANCH_MANAGEMENT.md '每个 PR 必须且只能对应一项独立、可审查的功能'
require_text BRANCH_MANAGEMENT.md '发现 `ahead/behind`、未跟踪文件、未提交改动或已合入但仍保留的旧 worktree 时'
require_text BRANCH_MANAGEMENT.md '任何单个待提交文件超过 5 MB 时'
require_text BRANCH_MANAGEMENT.md '相关提交信息中包含 `[governance-change]`'
require_text BRANCH_MANAGEMENT.md '`Repository governance` 必须配置为 `main` 的 Required status check'
require_heading AGENTS.md '## 任务范围与等待治理'
require_text AGENTS.md '分析、审查、诊断或状态查询默认只做只读检查并给出证据和结论'
require_text AGENTS.md '当前任务之外的优化、重构、规范调整或历史清理必须拆成独立工作项'
require_text AGENTS.md '禁止使用无法可靠收回控制权的交互式 CI 等待命令'
require_text RELEASING.md '只记录普通用户能够看到或受益的功能、体验、兼容性和可靠性变化。'
require_text RELEASING.md '已撤回、删除或从未公开的版本不进入 App 内版本历史。'

base_ref="${1:-}"
if [[ -n "$base_ref" && "$base_ref" != 0000000000000000000000000000000000000000 ]]; then
  git rev-parse --verify "$base_ref^{commit}" >/dev/null 2>&1 || fail "base commit is unavailable: $base_ref"

  governance_changed=false
  scope_violation=false
  while IFS= read -r path; do
    [[ -n "$path" ]] || continue
    case "$path" in
      AGENTS.md|BRANCH_MANAGEMENT.md|FEATURE_DEVELOPMENT.md|.github/PULL_REQUEST_TEMPLATE.md|.github/workflows/repository-governance.yml|scripts/verify-repository-governance.sh)
        governance_changed=true
        ;;
    esac
  done < <(git diff --name-only "$base_ref...HEAD")

  if [[ "$governance_changed" == true ]]; then
    git log --format=%B "$base_ref..HEAD" | grep -Fq -- '[governance-change]' || \
      fail 'governance files changed without [governance-change]'

    while IFS= read -r path; do
      [[ -n "$path" ]] || continue
      case "$path" in
        AGENTS.md|BRANCH_MANAGEMENT.md|FEATURE_DEVELOPMENT.md|RELEASING.md|.github/PULL_REQUEST_TEMPLATE.md|.github/workflows/repository-governance.yml|scripts/verify-repository-governance.sh)
          ;;
        *)
          scope_violation=true
          printf 'out-of-scope governance path: %s\n' "$path" >&2
          ;;
      esac
    done < <(git diff --name-only "$base_ref...HEAD")

    if [[ "$scope_violation" == true ]]; then
      fail 'governance changes must use a dedicated PR without product, release implementation, or unrelated files'
    fi
  fi
fi

printf 'repository governance check passed\n'
