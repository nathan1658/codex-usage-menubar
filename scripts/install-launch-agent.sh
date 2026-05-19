#!/usr/bin/env bash
set -euo pipefail

project_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
app_support="$HOME/Library/Application Support/CodexUsageMenuBar"
apps_dir="$HOME/Applications"
app_bundle="$apps_dir/CodexUsageMenuBar.app"
contents_dir="$app_bundle/Contents"
macos_dir="$contents_dir/MacOS"
log_dir="$HOME/Library/Logs/CodexUsageMenuBar"
launch_agents="$HOME/Library/LaunchAgents"
plist_path="$launch_agents/com.nathancheng.codex-usage-menubar.plist"
config_dir="$HOME/.config/codex-usage-menubar"
uid="$(id -u)"

cd "$project_dir"
swift build -c release

mkdir -p "$app_support" "$apps_dir" "$macos_dir" "$contents_dir/Resources" "$log_dir" "$launch_agents" "$config_dir"
cp "$project_dir/.build/release/CodexUsageMenuBar" "$macos_dir/CodexUsageMenuBar"
chmod +x "$macos_dir/CodexUsageMenuBar"

cat > "$contents_dir/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>en</string>
  <key>CFBundleExecutable</key>
  <string>CodexUsageMenuBar</string>
  <key>CFBundleIdentifier</key>
  <string>com.nathancheng.CodexUsageMenuBar</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleName</key>
  <string>CodexUsageMenuBar</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>0.1.0</string>
  <key>CFBundleVersion</key>
  <string>1</string>
  <key>LSMinimumSystemVersion</key>
  <string>14.0</string>
  <key>LSUIElement</key>
  <true/>
  <key>NSPrincipalClass</key>
  <string>NSApplication</string>
</dict>
</plist>
PLIST

if [ ! -f "$config_dir/config.json" ]; then
  cp "$project_dir/examples/config.example.json" "$config_dir/config.json"
fi

cat > "$plist_path" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>com.nathancheng.codex-usage-menubar</string>
  <key>ProgramArguments</key>
  <array>
    <string>$macos_dir/CodexUsageMenuBar</string>
  </array>
  <key>AssociatedBundleIdentifiers</key>
  <string>com.nathancheng.CodexUsageMenuBar</string>
  <key>LimitLoadToSessionType</key>
  <string>Aqua</string>
  <key>ProcessType</key>
  <string>Interactive</string>
  <key>RunAtLoad</key>
  <true/>
  <key>KeepAlive</key>
  <true/>
  <key>StandardOutPath</key>
  <string>$log_dir/stdout.log</string>
  <key>StandardErrorPath</key>
  <string>$log_dir/stderr.log</string>
</dict>
</plist>
PLIST

launchctl bootout "gui/$uid" "$plist_path" >/dev/null 2>&1 || true
launchctl bootstrap "gui/$uid" "$plist_path"
launchctl kickstart -k "gui/$uid/com.nathancheng.codex-usage-menubar"

echo "Installed CodexUsageMenuBar launch agent."
echo "App: $app_bundle"
echo "Config: $config_dir/config.json"
echo "Logs: $log_dir"
