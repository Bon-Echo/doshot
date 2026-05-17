# DoShot

Single-hotkey screenshot → Claude → action. Save into an organized folder, post to Slack, or both — driven by a natural-language instruction.

DoShot is a macOS menu-bar app (no Dock icon). You press the hotkey, drag-select a region, type what you want done, and Claude executes the action.

## Requirements

- macOS 13+
- The `claude` CLI on your `$PATH` (Claude Code), authenticated with your Claude account
- For Slack actions: a Slack bot token with `files:write`, `chat:write`, `channels:read` scopes

## Install (DMG)

DoShot ships as a **signed + notarized** DMG (Developer ID: Labeeb Khan, Team `33L6SC5Z5J`). Gatekeeper accepts it on first launch — no right-click → Open dance required.

1. Open `DoShot-<version>.dmg` and drag `DoShot.app` into `Applications`.
2. Double-click `DoShot.app`.
3. Grant Accessibility permission when prompted (or in Onboarding card 3).

## Onboarding

On first launch you'll see three cards (each independently skippable):

1. **Slack** — paste an `xoxb-…` bot token, test the connection, pick a default channel.
2. **Screenshot folder** — pick where DoShot organizes saved screenshots. Defaults to `~/Desktop/DoShot/`.
3. **Accessibility permission** — required for the global hotkey to fire from any app. Without this, the hotkey is dead.

If `claude` is not on your `PATH`, a fourth card appears with install instructions.

## Usage

1. Press the hotkey (default `⌃⇧4`). Drag-select a region.
2. The modal opens in the bottom-right of the active screen with the captured image and a text field.
3. Type what you'd like to do, e.g.:
   - `save this as a bug report`
   - `post to #design with a caption "color contrast issue"`
   - `save this as design feedback and post to #design`
4. Press `⌘↩` to run, `⌘W` to cancel.
5. A macOS notification confirms success or surfaces the error. Click a success notification to reveal the saved file in Finder.

## Slack bot setup

1. Go to <https://api.slack.com/apps> → **Create New App** → **From scratch**.
2. **OAuth & Permissions** → Bot Token Scopes: `files:write`, `chat:write`, `channels:read`.
3. **Install to Workspace**, then copy the `xoxb-…` token.
4. Invite the bot into the channels you want DoShot to post to (`/invite @YourBot` in Slack).
5. Paste the token in DoShot's Slack onboarding card and click **Test connection**.

## Claude CLI

DoShot drives Claude Code via the `claude` CLI. Install it from <https://docs.anthropic.com/claude/docs/claude-code>.

DoShot uses your existing Claude Code auth — calls bill against your Claude subscription, not a separate API key.

## Build from source

Requires Xcode 15+ and `brew install create-dmg`.

```bash
# Build the .app bundle (signs with Developer ID if available in keychain,
# otherwise falls back to ad-hoc)
bash Scripts/build-app.sh

# Open the .app to test
open dist/DoShot.app

# Package into a DMG
bash Scripts/dmg.sh

# Notarize + staple .app and .dmg (requires Developer ID signature and a
# notarytool keychain profile named AC_PASSWORD)
bash Scripts/notarize.sh
```

### One-time notarization setup

```bash
xcrun notarytool store-credentials AC_PASSWORD \
  --apple-id <your-apple-id> \
  --team-id 33L6SC5Z5J \
  --password <app-specific-password-from-appleid.apple.com>
```

For day-to-day development, open `Package.swift` in Xcode — SPM packages are first-class. Press `⌘R` to build & run.

## Per-run sandbox

Every run creates a directory at `~/.doshot/runs/<ISO8601-timestamp>/` containing:

- `capture.png` — the screenshot
- `meta.json` — hotkey + instruction metadata
- `transcript.jsonl` — raw stream-json output from Claude
- `result.json` — `{summary, actions: [{kind, target, ok}]}` (written by Claude)

If something looks wrong, this is where to look first.

## Troubleshooting

- **Hotkey does nothing** → Accessibility permission is not granted. Settings → Accessibility → re-grant.
- **`claude` CLI not found** → Set an explicit path in Settings → Advanced → Claude binary.
- **Slack action fails** → Bot isn't a member of the channel. `/invite @YourBot` in that channel.
- **First launch refuses to open** → Should not happen on the signed/notarized DMG; if it does, the ticket may have been stripped. Try `xattr -dr com.apple.quarantine /Applications/DoShot.app`.

## License

TBD by founder before public release.
