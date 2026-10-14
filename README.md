# 💧 Osmo Launcher
A water-themed (blue & white) launcher for your installed Steam games. Linux, no root.

## Install
    curl -fsSL https://github.com/brendenthebanana-hash/Osmo-Launcher.git
Then run `osmo-launcher` or find it in your app menu.

## Features
- Finds games across all Steam libraries (native and Flatpak Steam)
- Cover art from Steam's local cache, search, double-click to play
- Themes: Water, Deep Ocean, Lagoon + a custom theme editor
- Custom themes are JSON files in `~/.config/osmo-launcher/themes/`:
      {"name": "Mine", "colors": {"bg": "#fff", "accent": "#0af"}}
  Keys: bg, panel, card, text, muted, accent, accent_text

## Uninstall
    curl -fsSL https://raw.githubusercontent.com/YOURUSER/osmo-launcher/main/uninstall.sh | bash
