#!/usr/bin/env bash
set -euo pipefail

uid="$(id -u)"
plist_path="$HOME/Library/LaunchAgents/com.nathancheng.codex-usage-menubar.plist"
app_bundle="$HOME/Applications/CodexUsageMenuBar.app"

launchctl bootout "gui/$uid" "$plist_path" >/dev/null 2>&1 || true
rm -f "$plist_path"

echo "Removed CodexUsageMenuBar launch agent."
echo "App bundle remains at: $app_bundle"
