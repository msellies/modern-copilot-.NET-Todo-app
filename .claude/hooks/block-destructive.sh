#!/bin/bash
# PreToolUse guardrail: exit 2 blocks the Bash call and shows stderr to Claude.
COMMAND=$(jq -r '.tool_input.command // empty')

if echo "$COMMAND" | grep -qE 'git push.*(--force| -f)|git reset --hard|rm -rf|dotnet ef database drop'; then
  echo "Blocked by hook: '$COMMAND' is destructive. Find a non-destructive way, or ask the user." >&2
  exit 2
fi
exit 0
