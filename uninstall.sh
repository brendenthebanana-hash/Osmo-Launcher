#!/usr/bin/env bash
rm -rf "$HOME/.local/share/osmo-launcher" "$HOME/.local/bin/osmo-launcher" \
  "$HOME/.local/share/applications/osmo-launcher.desktop" \
  "$HOME/.local/share/icons/hicolor/scalable/apps/osmo-launcher.svg"
echo "Osmo Launcher removed (themes kept in ~/.config/osmo-launcher)."
