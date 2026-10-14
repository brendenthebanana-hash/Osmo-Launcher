#!/usr/bin/env bash
# Osmo Launcher installer - no root needed.
set -euo pipefail
REPO="brendenthebanana-hash/Osmo-Launcher"
DIR="$HOME/.local/share/osmo-launcher"
BIN="$HOME/.local/bin"
APPS="$HOME/.local/share/applications"
ICONS="$HOME/.local/share/icons/hicolor/scalable/apps"

WANT_DESKTOP=""
for a in "$@"; do
  case "$a" in --desktop) WANT_DESKTOP=yes ;; --no-desktop) WANT_DESKTOP=no ;; esac
done

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

# Icon (SVG + PNG)
PNGDIR="$HOME/.local/share/icons/hicolor/256x256/apps"; mkdir -p "$PNGDIR"
for f in svg png; do
  dest="$ICONS/osmo-launcher.svg"; [ "$f" = png ] && dest="$PNGDIR/osmo-launcher.png"
  if [ -f "./osmo-launcher.$f" ]; then cp "./osmo-launcher.$f" "$dest"
  else curl -fsSL "https://raw.githubusercontent.com/$REPO/main/osmo-launcher.$f" -o "$dest" 2>/dev/null || rm -f "$dest"; fi
done
if [ ! -s "$ICONS/osmo-launcher.svg" ]; then   # fallback if the download failed
  cat > "$ICONS/osmo-launcher.svg" <<'SVG'
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 128 128"><defs><linearGradient id="g" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#6fcbff"/><stop offset="1" stop-color="#1565d8"/></linearGradient></defs><circle cx="64" cy="64" r="60" fill="url(#g)"/><path d="M64 22C64 22 38 54 38 74a26 26 0 0 0 52 0C90 54 64 22 64 22z" fill="#fff"/></svg>
SVG
fi

cat > "$APPS/osmo-launcher.desktop" <<DESK
[Desktop Entry]
Type=Application
Name=Osmo Launcher
Comment=Water-themed Steam game launcher
Exec=$BIN/osmo-launcher
Icon=osmo-launcher
GenericName=Game Launcher
Keywords=steam;games;launcher;osmo;
Categories=Game;
StartupWMClass=osmo-launcher
Terminal=false
DESK
chmod 644 "$APPS/osmo-launcher.desktop"

# Refresh menu and icon caches so the app shows up right away
update-desktop-database "$APPS" 2>/dev/null || true
gtk-update-icon-cache -f -t "$HOME/.local/share/icons/hicolor" 2>/dev/null || true
xdg-desktop-menu forceupdate 2>/dev/null || true
for k in kbuildsycoca6 kbuildsycoca5; do command -v "$k" >/dev/null && "$k" >/dev/null 2>&1 && break; done || true

if [ -z "$WANT_DESKTOP" ] && [ -r /dev/tty ]; then
  printf "Add a shortcut to your Desktop? [y/N] " > /dev/tty
  read -r ans < /dev/tty || ans=""
  case "$ans" in [yY]*) WANT_DESKTOP=yes ;; esac
fi
if [ "$WANT_DESKTOP" = "yes" ]; then
  DESK="$(xdg-user-dir DESKTOP 2>/dev/null || true)"; DESK="${DESK:-$HOME/Desktop}"
  mkdir -p "$DESK"
  cp "$APPS/osmo-launcher.desktop" "$DESK/osmo-launcher.desktop"
  chmod +x "$DESK/osmo-launcher.desktop"
  gio set "$DESK/osmo-launcher.desktop" metadata::trusted true 2>/dev/null || true
  echo "✓ Desktop shortcut added (if it looks untrusted, right-click → Allow Launching)"
fi

echo "✓ Installed! Find Osmo Launcher in your app menu (search \"Osmo\"), or run: osmo-launcher"
echo "  Not in the menu yet? Log out and back in once, or see the README."
case ":$PATH:" in *":$BIN:"*) ;; *) echo "Note: add $BIN to your PATH (e.g. echo 'export PATH=\"\$HOME/.local/bin:\$PATH\"' >> ~/.bashrc)";; esac
