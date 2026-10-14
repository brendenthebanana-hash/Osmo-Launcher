#!/usr/bin/env bash
# Osmo Launcher uninstaller - removes everything the installer added.
rm -rf "$HOME/.local/share/osmo-launcher" "$HOME/.local/bin/osmo-launcher" \
  "$HOME/.local/share/applications/osmo-launcher.desktop" \
  "$HOME/.local/share/icons/hicolor/scalable/apps/osmo-launcher.svg" \
  "$HOME/.local/share/icons/hicolor/256x256/apps/osmo-launcher.png"
D="$(xdg-user-dir DESKTOP 2>/dev/null || echo "$HOME/Desktop")"; rm -f "$D/osmo-launcher.desktop"
update-desktop-database "$HOME/.local/share/applications" 2>/dev/null || true
gtk-update-icon-cache -f -t "$HOME/.local/share/icons/hicolor" 2>/dev/null || true
xdg-desktop-menu forceupdate 2>/dev/null || true
echo "Osmo Launcher removed. Your themes are kept in ~/.config/osmo-launcher"
echo "To delete them too: rm -rf ~/.config/osmo-launcher"
