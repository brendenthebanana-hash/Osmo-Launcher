#!/usr/bin/env bash
# Osmo Launcher installer - no root needed.
set -euo pipefail
REPO="YOURUSER/osmo-launcher"   # <- change to your GitHub user/repo
DIR="$HOME/.local/share/osmo-launcher"
BIN="$HOME/.local/bin"
APPS="$HOME/.local/share/applications"
ICONS="$HOME/.local/share/icons/hicolor/scalable/apps"

command -v python3 >/dev/null || { echo "python3 is required."; exit 1; }
mkdir -p "$DIR" "$BIN" "$APPS" "$ICONS"

echo "→ Downloading Osmo Launcher…"
if [ -f "./osmo_launcher.py" ]; then
  cp ./osmo_launcher.py "$DIR/osmo_launcher.py"
else
  curl -fsSL "https://raw.githubusercontent.com/$REPO/main/osmo_launcher.py" -o "$DIR/osmo_launcher.py"
fi

echo "→ Setting up Python environment (PyQt6)…"
if ! python3 -m venv "$DIR/venv" 2>/dev/null; then
  echo "python3-venv missing; falling back to pip --user"
  python3 -m pip install --user --break-system-packages PyQt6
  PY="python3"
else
  "$DIR/venv/bin/pip" install --quiet --upgrade pip PyQt6
  PY="$DIR/venv/bin/python"
fi

cat > "$BIN/osmo-launcher" <<LAUNCH
#!/usr/bin/env bash
exec "$PY" "$DIR/osmo_launcher.py" "\$@"
LAUNCH
chmod +x "$BIN/osmo-launcher"

cat > "$ICONS/osmo-launcher.svg" <<'SVG'
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 128 128"><defs><linearGradient id="g" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#6fcbff"/><stop offset="1" stop-color="#1565d8"/></linearGradient></defs><circle cx="64" cy="64" r="60" fill="url(#g)"/><path d="M64 22C64 22 38 54 38 74a26 26 0 0 0 52 0C90 54 64 22 64 22z" fill="#fff"/></svg>
SVG

cat > "$APPS/osmo-launcher.desktop" <<DESK
[Desktop Entry]
Type=Application
Name=Osmo Launcher
Comment=Water-themed Steam game launcher
Exec=$BIN/osmo-launcher
Icon=osmo-launcher
Categories=Game;
Terminal=false
DESK
update-desktop-database "$APPS" 2>/dev/null || true

echo "✓ Installed! Run: osmo-launcher"
case ":$PATH:" in *":$BIN:"*) ;; *) echo "Note: add $BIN to your PATH (e.g. echo 'export PATH=\"\$HOME/.local/bin:\$PATH\"' >> ~/.bashrc)";; esac
