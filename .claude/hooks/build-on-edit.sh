#!/bin/bash
# PostToolUse feedback: rebuild after a C# edit. Exit 2, because Claude never sees output of a hook that exits 0.
FILE=$(jq -r '.tool_input.file_path // empty')
[[ "$FILE" == *.cs ]] || exit 0
cd "$CLAUDE_PROJECT_DIR" || exit 0

if ! OUT=$(dotnet build TodoApp.sln --nologo -v quiet 2>&1); then
  echo "Build failed after editing $FILE:" >&2
  echo "$OUT" | grep -E ': error ' | sort -u | head -20 >&2
  exit 2
fi
exit 0
