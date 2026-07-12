# Claude Cloud Usage Widget for macOS — Token Widget

**Token Widget** is an open-source **Claude cloud usage widget** for the Mac menu bar. It is a lightweight **cloud usage display** and **cloud usage shortcut** so you can see Claude **usage**, limits, and reset timers without opening the Anthropic dashboard.

If you searched for a **cloud usage widget**, **Claude usage widget**, **Claude Code usage**, **Anthropic usage monitor**, or a **menu bar cloud usage display**, this project is built for that.

<p align="center">
  <img src="https://raw.githubusercontent.com/adityarai7297/token-widget/main/docs/claude-cloud-usage-menubar-widget.png" alt="Claude cloud usage widget in the macOS menu bar — live usage bar and cooldown timer" width="320" />
</p>

<p align="center">
  <img src="https://raw.githubusercontent.com/adityarai7297/token-widget/main/docs/claude-cloud-usage-widget-dropdown.png" alt="Claude cloud usage display dropdown — 5-hour, weekly, and model usage bars with reset countdowns" width="360" />
</p>

## Why this Claude cloud usage widget?

Claude’s web **cloud usage** page works, but it is slow to check while you are coding. Token Widget keeps a **cloud usage shortcut** in your menu bar:

- Live **cloud usage display** for the **5-hour** session limit
- **Weekly** cloud usage and model-scoped usage (for example Fable)
- Progress bars instead of hunting through the dashboard
- Second-accurate “resets in …” timers
- One-click refresh — a practical **cloud usage shortcut** next to your clock

**Keywords people use for this kind of tool:** Claude usage, cloud usage, cloud usage widget, cloud usage display, cloud usage shortcut, Claude Max usage, Anthropic rate limits, Claude Code usage meter, macOS menu bar usage monitor.

## Features

| Feature | What you get |
| --- | --- |
| Menu bar **cloud usage widget** | Usage bar, percent, cooldown ring |
| Dropdown **cloud usage display** | 5-hour / Weekly / model rows with bars |
| Reset timers | Second-accurate local countdown from Claude’s reset timestamps |
| Sign-in | Imports **Claude Code** credentials when available, or browser OAuth |
| Footprint | Menu bar only — no Dock icon |

## Requirements

- macOS **14** (Sonoma) or later
- A Claude account with cloud usage limits (Pro, Max, etc.)
- Optional: [Claude Code](https://claude.ai/code) already signed in (fastest setup)

## Install this cloud usage widget

### Build from source

```bash
git clone https://github.com/adityarai7297/token-widget.git
cd token-widget
brew install xcodegen
xcode-select --install   # if needed
./build.sh
open "/Applications/Token Widget.app"
```

If macOS blocks the app: right-click → **Open** → **Open**, or allow it under **System Settings → Privacy & Security**.

### Prebuilt downloads

When available, grab a build from [Releases](https://github.com/adityarai7297/token-widget/releases), move **Token Widget** into `/Applications`, and launch it.

Add it under **System Settings → General → Login Items** if you want the cloud usage widget at login.

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

Usage percentages refresh about every **60 seconds** (and when you open the menu if data is stale). Countdown text updates every **second** locally — the timer stays accurate without constant API calls.

## Who is this for?

- Developers using **Claude** / **Claude Code** who watch **5-hour** and **weekly** limits
- Anyone who wants a **macOS cloud usage widget** instead of refreshing the website
- People searching for a **cloud usage shortcut**, **usage meter**, or **usage monitor** for Claude

## Privacy

- OAuth tokens stay on your Mac: `~/Library/Application Support/TokenWidget/credentials.json` (`600`)
- Cache and logs stay in that folder
- Network traffic is only Claude / Anthropic OAuth + usage APIs
- No analytics SDK and no third-party tracking

Delete that folder (or Sign Out) to clear local credentials.

## Build from source (contributors)

```bash
./build.sh
```

Optional environment variables:

```bash
export DEVELOPMENT_TEAM=XXXXXXXXXX
export CODE_SIGN_IDENTITY="Apple Development: Your Name (XXXXXXXXXX)"
export SKIP_INSTALL=1
```

Or open in Xcode:

```bash
xcodegen generate
open TokenWidget.xcodeproj
```

## Troubleshooting

| Problem | Fix |
| --- | --- |
| Unidentified developer | Right-click → **Open**, or allow in Privacy & Security |
| Not signed in | Sign In again; confirm Claude Code login or finish OAuth + copy code |
| Rate limited | Wait; avoid hammering **Refresh Now** |
| Stale cloud usage display | **Refresh Now**, or quit and reopen |
| Clean install | Quit app, delete `~/Library/Application Support/TokenWidget/`, relaunch |

## Contributing

Issues and PRs welcome — especially releases/notarization, Intel testing, preferences, and onboarding.

1. Fork → branch → focused PR  
2. Describe the problem and the fix  

## Related searches

Claude cloud usage · cloud usage widget · cloud usage display · cloud usage shortcut · Claude usage menu bar · Anthropic usage limits · Claude Max 20x usage · Claude Code usage tracker · macOS Claude usage monitor

## License

[MIT](LICENSE) — free to use, share, and modify.

---

**Not affiliated with Anthropic.** Claude® is a trademark of Anthropic PBC. Unofficial community **cloud usage widget**.
