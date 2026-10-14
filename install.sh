#!/usr/bin/env bash
# Osmo Launcher installer - no root needed.
set -euo pipefail
REPO="brendenthebanana-hash/Osmo-Launcher"
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

qt_ok() { QT_QPA_PLATFORM=offscreen "$PY" -c "from PyQt6.QtCore import Qt" >/dev/null 2>&1; }
EXTRA=""

if ! qt_ok; then
  echo "→ A system library is missing. Fetching it (no root needed)…"
  case "$(uname -m)" in
    x86_64) MM="linux-64" ;;
    aarch64|arm64) MM="linux-aarch64" ;;
    *) echo "Unsupported CPU: $(uname -m). See the README troubleshooting."; exit 1 ;;
  esac
  cd "$DIR"
  curl -fsSL "https://micro.mamba.pm/api/micromamba/$MM/latest" | tar -xj bin/micromamba
  MAMBA_ROOT_PREFIX="$DIR/mamba" ./bin/micromamba create -y -q -p "$DIR/libs" -c conda-forge \
    libglib libxcb xcb-util-cursor xcb-util-image xcb-util-keysyms xcb-util-renderutil xcb-util-wm \
    libxkbcommon libgl >/dev/null
  EXTRA="export LD_LIBRARY_PATH=\"$DIR/libs/lib:\${LD_LIBRARY_PATH:-}\""
  export LD_LIBRARY_PATH="$DIR/libs/lib:${LD_LIBRARY_PATH:-}"
  if ! qt_ok; then
    echo "✗ Qt still can't start. See the Troubleshooting section of the README:"
    echo "  https://github.com/$REPO#troubleshooting"
    QT_QPA_PLATFORM=offscreen "$PY" -c "from PyQt6.QtCore import Qt" || true
    exit 1
  fi
fi

cat > "$BIN/osmo-launcher" <<LAUNCH
#!/usr/bin/env bash
$EXTRA
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
