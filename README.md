# Codex Usage Menu Bar

Native macOS menu-bar app for showing remaining AI coding quota across multiple Codex, Claude, and Claude relay accounts.

## What It Shows

The menu-bar item renders one compact column per configured account:

```text
Cx 67  C1 75  C2 99
4h 88 30m 90  2h 98
```

Each account column has one provider label, its floor-rounded 5h reset countdown, and two stacked remaining-quota values:

- Top value: 5h remaining quota
- Bottom value: 1w remaining quota
- Bottom-left value: time until the 5h counter resets, rounded down to one unit (`4h30m` shows as `4h`; `30m` shows as `30m`)
- `Cx`: Codex
- `C1`: Claude Code / Anthropic OAuth usage
- `C2`: Claude relay endpoint

Percentages are remaining quota, not used quota. If the upstream provider reports 0% used, the menu bar shows 100.

Remaining values are color-coded:

- Red: below 20
- Yellow: below 50
- White: 50 through 100

Click the menu-bar item to open a dropdown with account names, reset times, plan names when available, last refresh errors, and a manual refresh action.

## Supported Providers

### Codex

Codex accounts are read through the local Codex app-server protocol:

```text
codex app-server --listen stdio://
```

For each Codex account, the app sets `CODEX_HOME` to the configured home directory and reads `account/rateLimits/read`.

The Codex executable is resolved in this order:

- `CODEX_BINARY` environment variable
- `/opt/homebrew/bin/codex`
- `/usr/local/bin/codex`
- `~/.bun/bin/codex`
- newest executable under `~/.nvm/versions/node/*/bin/codex`

### Claude Code

Claude usage is read from Anthropic's OAuth usage endpoint. The app finds the Claude OAuth token in this order:

- `CLAUDE_CODE_OAUTH_TOKEN` environment variable
- macOS Keychain item named `Claude Code-credentials`
- `~/.claude/.credentials.json`, or the configured `claudeHome` equivalent

### Claude Relay

Relay accounts support Claude relay usage responses without committing private endpoint data to this repository.

Configure relay accounts with:

- `relayApiID`: relay API ID
- `relayStatsURL`: stats endpoint URL
- `relayReferrer`: optional referrer header, if your relay requires one

The same values can also come from environment variables:

```bash
CLAUDE_STATUSLINE_RELAY_API_ID=your-relay-api-id
CLAUDE_STATUSLINE_RELAY_STATS_URL=https://relay.example.com/apiStats/api/user-stats
CLAUDE_STATUSLINE_RELAY_REFERRER='https://relay.example.com/admin-next/api-stats?apiId=your-relay-api-id'
```

The relay request is a `POST` with JSON body:

```json
{ "apiId": "your-relay-api-id" }
```

The parser reads:

- `data.limits.currentWindowRequests / data.limits.rateLimitRequests` for 5h usage
- `data.limits.weeklyOpusCost / data.limits.weeklyOpusCostLimit` for 1w usage
- `data.limits.windowEndTime` for the 5h reset time
- `data.limits.weeklyResetDay` and `data.limits.weeklyResetHour` for the weekly reset time
- `data.name` for the plan/account name

## Install

```bash
cd ~/codex-usage-menubar
chmod +x scripts/install-launch-agent.sh scripts/uninstall-launch-agent.sh
scripts/install-launch-agent.sh
```

The installer:

- Builds a release binary
- Packages it as a menu-bar-only app at `~/Applications/CodexUsageMenuBar.app`
- Installs a LaunchAgent at `~/Library/LaunchAgents/com.nathancheng.codex-usage-menubar.plist`
- Starts or restarts the menu-bar app

Logs are written to:

```text
~/Library/Logs/CodexUsageMenuBar/
```

To uninstall the LaunchAgent:

```bash
cd ~/codex-usage-menubar
scripts/uninstall-launch-agent.sh
```

## Run Manually

```bash
cd ~/codex-usage-menubar
swift run CodexUsageMenuBar
```

Print one usage snapshot without starting the menu-bar app:

```bash
swift run CodexUsageMenuBar --print-once
```

## Configuration

The app reads:

```text
~/.config/codex-usage-menubar/config.json
```

Start from:

```text
examples/config.example.json
```

Example:

```json
{
  "refreshSeconds": 300,
  "accounts": [
    {
      "provider": "codex",
      "label": "main",
      "codexHome": "~/.codex"
    },
    {
      "provider": "claude",
      "label": "main",
      "claudeHome": "~/.claude"
    },
    {
      "provider": "claudeRelay",
      "label": "relay",
      "relayApiID": "your-relay-api-id",
      "relayStatsURL": "https://relay.example.com/apiStats/api/user-stats",
      "relayReferrer": "https://relay.example.com/admin-next/api-stats?apiId=your-relay-api-id"
    }
  ]
}
```

Supported account fields:

- `provider`: `codex`, `claude`, or `claudeRelay`
- `label`: short account name shown in the dropdown
- `codexHome`: Codex home directory for `codex` accounts
- `claudeHome`: Claude home directory for `claude` accounts
- `relayApiID`: relay API ID for `claudeRelay` accounts
- `relayStatsURL`: relay stats endpoint URL for `claudeRelay` accounts
- `relayReferrer`: optional relay referrer header

If no config file exists, the app auto-detects local Codex and Claude homes:

```text
~/.codex
~/.codex/homes/pooi
~/.codex/homes/wai
~/.claude
```

Relay accounts are not auto-detected because they require private endpoint configuration.

## Development

Build:

```bash
swift build
```

Test:

```bash
swift test
```

Run the app from source:

```bash
swift run CodexUsageMenuBar
```

The project is a Swift Package with:

- `Sources/UsageCore`: provider models, normalization, and response parsers
- `Sources/CodexUsageMenuBar`: macOS app, menu-bar rendering, provider clients, config loading
- `Tests/UsageCoreTests`: parser and normalization tests
- `scripts/`: LaunchAgent install and uninstall scripts

## Public Repo Safety

Do not commit local config files, OAuth tokens, API IDs, relay URLs, logs, or build artifacts.

Private values belong in:

```text
~/.config/codex-usage-menubar/config.json
```

or in environment variables. The public example config only contains placeholders.

## Troubleshooting

If the menu-bar item is missing:

```bash
launchctl print gui/$(id -u)/com.nathancheng.codex-usage-menubar
```

Then reinstall:

```bash
scripts/install-launch-agent.sh
```

If a provider shows `?`, open the dropdown. The last refresh error is shown per account.

If Codex fails, check that the configured `codexHome` exists and that the `codex` executable can be resolved.

If Claude fails, check that Claude Code is logged in and that the OAuth token is available from the Keychain, credentials file, or `CLAUDE_CODE_OAUTH_TOKEN`.

If relay fails, check `relayApiID`, `relayStatsURL`, and `relayReferrer` in your local config or environment.
