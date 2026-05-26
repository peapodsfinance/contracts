#!/usr/bin/env bash
# Pre-commit guard: block `git commit` when staged .sol diff contains audit-prefix
# patterns. Reads Claude Code PreToolUse hook input on stdin and either exits 0
# (allow) or prints a JSON deny with permissionDecisionReason.
#
# Forbidden patterns (case-insensitive):
#   - audit #NNN
#   - audit 516da0a
#   - NEW-(LEV|GOV|ORC|FXL|REB|LP|VAULT|PRE)-NNN
#   - CDX-(LEV|GOV|VAULT|PRE|REB)-NNN
#   - HIGH-NN RES / HIGH-NN RESIDUAL / HIGH-15
#   - peapodsfinance/v4-contracts#NNN
#   - test_Audit / test_FIXED_ test names
#   - "remediation" / "remediated" inside // or /// comments
#
# Only checks the staged diff CONTENT (`git diff --cached -- '*.sol'`); the
# commit message itself is not scanned (legitimate audit-tracking commit
# messages remain allowed).
set -uo pipefail

# Read full stdin payload
payload=$(cat)
cmd=$(printf '%s' "$payload" | jq -r '.tool_input.command // empty' 2>/dev/null)

# Bail unless this is a `git commit` invocation (covers `-m`, `--amend`, `-a`, etc.)
if ! printf '%s' "$cmd" | grep -qE '(^|[[:space:]])git[[:space:]]+commit($|[[:space:]])'; then
  exit 0
fi

# Pull the staged diff for .sol files only, restrict to added lines.
diff_added=$(git diff --cached -- '*.sol' 2>/dev/null | grep '^+' | grep -v '^+++' || true)
if [ -z "$diff_added" ]; then
  exit 0
fi

forbidden_main='audit #[0-9]+|audit 516da0a|NEW-(LEV|GOV|ORC|FXL|REB|LP|VAULT|PRE)-[0-9]+|CDX-(LEV|GOV|VAULT|PRE|REB)-[0-9]+|HIGH-[0-9]+ (RES|RESIDUAL)|HIGH-15|peapodsfinance/v4-contracts#[0-9]+|test_Audit|test_FIXED_'

# Scan main forbidden patterns anywhere in added lines.
hits_main=$(printf '%s\n' "$diff_added" | grep -inE "$forbidden_main" || true)

# Scan "remediation"/"remediated" only when they appear inside a // or /// comment line.
hits_comments=$(printf '%s\n' "$diff_added" | grep -inE '^\+[[:space:]]*(///|//).*\b(remediation|remediated)\b' || true)

if [ -z "$hits_main" ] && [ -z "$hits_comments" ]; then
  exit 0
fi

# Build human-readable failure message
header="Commit blocked: forbidden audit-prefix patterns in staged .sol diff."
guidance="Strip audit/CR/issue references from comments and test names. See the header comment in .claude/hooks/check-audit-comments.sh for the full forbidden-pattern list. Run \`forge fmt\` after rewriting."

# Trim to first 30 hits to keep the reason readable.
all_hits=$(printf '%s\n%s\n' "$hits_main" "$hits_comments" | sed '/^$/d' | head -n 30)
reason="$header

$guidance

Offending lines (first 30):
$all_hits"

# Emit JSON deny. Claude Code reads hookSpecificOutput.permissionDecision = 'deny' and aborts the tool call.
jq -n --arg reason "$reason" '{
  hookSpecificOutput: {
    hookEventName: "PreToolUse",
    permissionDecision: "deny",
    permissionDecisionReason: $reason
  }
}'
