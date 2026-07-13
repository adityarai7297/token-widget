# Claude Cloud Usage Widget for macOS — Token Widget

**Token Widget** is an open-source **Claude cloud usage widget** for the Mac menu bar. It is a lightweight **cloud usage display** and **cloud usage shortcut** so you can see Claude **usage**, limits, and reset timers without opening the Anthropic dashboard.

If you searched for a **cloud usage widget**, **Claude usage widget**, **Claude Code usage**, **Anthropic usage monitor**, or a **menu bar cloud usage display**, this project is built for that.

<p align="center">
  <img src="https://raw.githubusercontent.com/adityarai7297/token-widget/main/docs/claude-cloud-usage-menubar-widget.png" alt="Claude cloud usage widget in the macOS menu bar — live usage bar and cooldown timer" width="320" />
</p>

<p align="center">
  <img src="https://raw.githubusercontent.com/adityarai7297/token-widget/main/docs/claude-cloud-usage-widget-dropdown.png" alt="Claude cloud usage display dropdown — 5-hour, weekly, and model usage bars with reset countdowns" width="360" />
</p>

## Download (no Terminal needed)

**[↓ Download Token Widget for Mac (Apple Silicon)](https://github.com/adityarai7297/token-widget/releases/latest/download/Token-Widget-macOS.zip)**

1. Download the zip from the link above (or the [Releases](https://github.com/adityarai7297/token-widget/releases) page)
2. Double-click the zip to unpack **Token Widget.app**
3. Drag **Token Widget** into your **Applications** folder
4. Double-click to open — **v1.2.1+ is Developer ID signed and notarized by Apple**
5. Look for the Claude usage widget in the **menu bar** (top-right)

### First open on macOS (Gatekeeper)

Prefer the **notarized** build from [Releases](https://github.com/adityarai7297/token-widget/releases/latest) — it should open with a normal double-click.

If macOS still warns (older non-notarized zip):

- **Finder** → right-click **Token Widget** → **Open** → **Open**
- Or: **System Settings → Privacy & Security** → **Open Anyway**

Maintainers: see [docs/NOTARIZE.md](docs/NOTARIZE.md) for Developer ID + notarization.

Optional: **System Settings → General → Login Items** → add Token Widget so the cloud usage shortcut starts at login.

**Requirements:** macOS 14+, Apple Silicon Mac (M1/M2/M3/M4…), a Claude account. Having [Claude Code](https://claude.ai/code) already signed in makes setup easiest.

## Why this Claude cloud usage widget?

Claude’s web **cloud usage** page works, but it is slow to check while you are coding. Token Widget keeps a **cloud usage shortcut** in your menu bar:

- Live **cloud usage display** for the **5-hour** session limit
- **Weekly** cloud usage and model-scoped usage (for example Fable)
- Progress bars instead of hunting through the dashboard
- Second-accurate “resets in …” timers
- One-click refresh — a practical **cloud usage shortcut** next to your clock

## Features

| Feature | What you get |
| --- | --- |
| Menu bar **cloud usage widget** | Usage bar, percent, cooldown ring |
| Dropdown **cloud usage display** | 5-hour / Weekly / model rows with bars |
| Reset timers | Second-accurate local countdown from Claude’s reset timestamps |
| Sign-in | Imports **Claude Code** credentials when available, or browser OAuth |
| Footprint | Menu bar only — no Dock icon |

## Sign in (connect Claude cloud usage)

1. Click the menu bar **cloud usage shortcut** → **Sign In…**
2. Prefer the automatic path: if Claude Code is logged in, credentials are imported
3. Or finish browser OAuth, copy the code (**⌘C**), and Token Widget picks it up
4. Your **cloud usage display** updates in the menu bar

**Sign Out** is in the same menu.

## How the cloud usage display works

| Surface | Cloud usage information |
| --- | --- |
| Menu bar widget | Session usage bar · `%` · cooldown · time left |
| Dropdown | Each limit with progress bar · `%` · `resets in …` |
| **Refresh Now** (`⌘R`) | Force refresh from Claude’s usage API |
| Hover tooltip | Quick 5-hour cloud usage summary |

Usage percentages refresh about every **60 seconds** (and when you open the menu if data is stale). Countdown text updates every **second** locally.

## Privacy

- OAuth tokens stay on your Mac: `~/Library/Application Support/TokenWidget/credentials.json` (`600`)
- Cache and logs stay in that folder
- Network traffic is only Claude / Anthropic OAuth + usage APIs
- No analytics SDK and no third-party tracking

## Build from source (developers)

```bash
git clone https://github.com/adityarai7297/token-widget.git
cd token-widget
brew install xcodegen
xcode-select --install   # if needed
./build.sh
open "/Applications/Token Widget.app"
```

Optional env vars: `DEVELOPMENT_TEAM`, `CODE_SIGN_IDENTITY`, `SKIP_INSTALL=1`.

Ship a zip for Releases:

```bash
./scripts/make-release-zip.sh
```

## Troubleshooting

| Problem | Fix |
| --- | --- |
| “App can’t be opened” / unidentified developer | Right-click → **Open**, or **Open Anyway** in Privacy & Security |
| Not signed in | Sign In again; confirm Claude Code login or finish OAuth + copy code |
| Rate limited | Wait; avoid hammering **Refresh Now** |
| Stale cloud usage display | **Refresh Now**, or quit and reopen |
| Intel Mac | Current release zip is **Apple Silicon only**; build from source on Intel for now |

## Contributing

Issues and PRs welcome — especially **Developer ID + notarization**, Intel builds, preferences, and onboarding.

## Related searches

Claude cloud usage · cloud usage widget · cloud usage display · cloud usage shortcut · Claude usage menu bar · Anthropic usage limits · Claude Max usage · Claude Code usage tracker · macOS Claude usage monitor

## License

[MIT](LICENSE) — free to use, share, and modify.

---

**Not affiliated with Anthropic.** Claude® is a trademark of Anthropic PBC. Unofficial community **cloud usage widget**.
