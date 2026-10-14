#!/usr/bin/env bash
# Osmo Launcher installer - self-contained, no root needed.
# Usage: bash install.sh [--desktop | --no-desktop]
set -euo pipefail
VERSION="1.1.0"
DIR="$HOME/.local/share/osmo-launcher"
BIN="$HOME/.local/bin"
APPS="$HOME/.local/share/applications"
ICONS="$HOME/.local/share/icons/hicolor/scalable/apps"
PNGDIR="$HOME/.local/share/icons/hicolor/256x256/apps"

WANT_DESKTOP=""
for a in "$@"; do
  case "$a" in --desktop) WANT_DESKTOP=yes ;; --no-desktop) WANT_DESKTOP=no ;; esac
done

command -v python3 >/dev/null || { echo "python3 is required."; exit 1; }
mkdir -p "$DIR" "$BIN" "$APPS" "$ICONS" "$PNGDIR"

echo "→ Installing Osmo Launcher $VERSION…"
cat > "$DIR/osmo_launcher.py" <<'OSMO_PY_EOF'
@@PY@@
OSMO_PY_EOF

cat > "$ICONS/osmo-launcher.svg" <<'OSMO_SVG_EOF'
@@SVG@@
OSMO_SVG_EOF

python3 -c 'import base64,sys; sys.stdout.buffer.write(base64.b64decode(sys.stdin.read()))' > "$PNGDIR/osmo-launcher.png" <<'OSMO_PNG_EOF'
@@PNG_B64@@
OSMO_PNG_EOF

echo "→ Setting up Python environment (PyQt6)…"
if ! python3 -m venv "$DIR/venv" 2>/dev/null; then
  echo "  python3-venv missing; falling back to pip --user"
  python3 -m pip install --user --break-system-packages PyQt6
  PY="python3"
else
  "$DIR/venv/bin/pip" install --quiet --upgrade pip PyQt6
  PY="$DIR/venv/bin/python"
fi

# ---- Check that Qt can start; fetch missing system libraries without root ----
qt_import_ok() { QT_QPA_PLATFORM=offscreen "$PY" -c "from PyQt6.QtWidgets import QApplication" >/dev/null 2>&1; }
qt_xcb_missing() {
  command -v ldd >/dev/null || return 1
  local qd plug
  qd="$("$PY" -c "import os,PyQt6;print(os.path.dirname(PyQt6.__file__))" 2>/dev/null)" || return 1
  plug="$qd/Qt6/plugins/platforms/libqxcb.so"
  [ -f "$plug" ] || return 1
  ldd "$plug" 2>/dev/null | grep -q "not found"
}
needs_fix() { ! qt_import_ok || qt_xcb_missing; }

EXTRA=""
fix_libs() {
  case "$(uname -m)" in
    x86_64) MM="linux-64" ;;
    aarch64|arm64) MM="linux-aarch64" ;;
    *) echo "  Unsupported CPU: $(uname -m)"; return 1 ;;
  esac
  curl -fsSL "https://micro.mamba.pm/api/micromamba/$MM/latest" -o "$DIR/mm.tar.bz2" || return 1
  python3 - "$DIR" <<'PYEOF' || return 1
import sys, tarfile
d = sys.argv[1]
with tarfile.open(d + "/mm.tar.bz2") as t:
    t.extract("bin/micromamba", d)
PYEOF
  rm -f "$DIR/mm.tar.bz2"; chmod +x "$DIR/bin/micromamba"
  export MAMBA_ROOT_PREFIX="$DIR/mamba"
  "$DIR/bin/micromamba" create -y -q -p "$DIR/libs" -c conda-forge libglib || return 1
  export LD_LIBRARY_PATH="$DIR/libs/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
  EXTRA="export LD_LIBRARY_PATH=\"$DIR/libs/lib\${LD_LIBRARY_PATH:+:\$LD_LIBRARY_PATH}\""
  if needs_fix; then
    echo "→ Fetching a few more libraries…"
    for pkg in libxcb xcb-util-cursor xcb-util-image xcb-util-keysyms xcb-util-renderutil xcb-util-wm libxkbcommon libgl; do
      "$DIR/bin/micromamba" install -y -q -p "$DIR/libs" -c conda-forge "$pkg" >/dev/null 2>&1 || true
    done
  fi
  return 0
}

if needs_fix; then
  echo "→ A system library is missing. Fetching it (no root needed)…"
  if ! fix_libs; then
    echo "⚠ Couldn't fetch the libraries automatically (no internet, or an unsupported system)."
    echo "  Osmo is installed, but may not start. Fix: https://github.com/brendenthebanana-hash/Osmo-Launcher#troubleshooting"
  elif ! qt_import_ok; then
    echo "⚠ Qt still can't start. Error:"
    QT_QPA_PLATFORM=offscreen "$PY" -c "from PyQt6.QtWidgets import QApplication" 2>&1 | tail -3 || true
    echo "  See: https://github.com/brendenthebanana-hash/Osmo-Launcher#troubleshooting"
  elif qt_xcb_missing; then
    echo "  (note: some X11 libraries are still missing; fine on Wayland, see the README if the window doesn't open)"
  fi
fi

cat > "$BIN/osmo-launcher" <<LAUNCH
#!/usr/bin/env bash
$EXTRA
exec "$PY" "$DIR/osmo_launcher.py" "\$@"
LAUNCH
chmod +x "$BIN/osmo-launcher"

cat > "$APPS/osmo-launcher.desktop" <<DESK
[Desktop Entry]
Type=Application
Name=Osmo Launcher
GenericName=Game Launcher
Comment=Water-themed Steam game launcher
Exec=$BIN/osmo-launcher
Icon=osmo-launcher
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
  printf "Add a shortcut to your Desktop? [y/N] " > /dev/tty 2>/dev/null || true
  read -r ans < /dev/tty 2>/dev/null || ans=""
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

echo "✓ Installed Osmo Launcher $VERSION! Find it in your app menu (search \"Osmo\"), or run: osmo-launcher"
case ":$PATH:" in *":$BIN:"*) ;; *) echo "Note: add $BIN to your PATH:  echo 'export PATH=\"\$HOME/.local/bin:\$PATH\"' >> ~/.bashrc";; esac
echo "Not in the menu yet? Log out and back in once."
