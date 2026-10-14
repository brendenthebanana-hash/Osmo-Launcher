# 💧 Osmo Launcher

A water-themed (blue and white) launcher for your installed Steam games on Linux. Installs with one command, no root needed.

## Install

```bash
curl -fsSL https://raw.githubusercontent.com/brendenthebanana-hash/Osmo-Launcher/main/install.sh | bash
```

Then run `osmo-launcher` or find **Osmo Launcher** in your app menu.

Requirements: `python3` and Steam (run it at least once).
If `osmo-launcher` isn't found, add `~/.local/bin` to your PATH:

```bash
echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.bashrc && source ~/.bashrc
```

## Features

- Finds games across all Steam libraries (native and Flatpak Steam)
- Cover art from Steam's local cache, search, double-click to play
- Themes: Water, Deep Ocean, Lagoon, plus a custom theme editor

## Custom themes

Click **＋ Custom theme** in the app, or add a JSON file to `~/.config/osmo-launcher/themes/`:

```json
{"name": "Mine", "colors": {"bg": "#ffffff", "accent": "#00aaff"}}
```

Keys: `bg`, `panel`, `card`, `text`, `muted`, `accent`, `accent_text`.

## Troubleshooting

### `ImportError: libgthread-2.0.so.0: cannot open shared object file`

Qt needs the system glib library. Pick one fix.

**No root (works anywhere):**

```bash
cd ~/.local/share/osmo-launcher
curl -Ls https://micro.mamba.pm/api/micromamba/linux-64/latest | tar -xj bin/micromamba
MAMBA_ROOT_PREFIX=$PWD/mamba ./bin/micromamba create -y -p $PWD/libs -c conda-forge libglib
sed -i '2i export LD_LIBRARY_PATH="$HOME/.local/share/osmo-launcher/libs/lib:${LD_LIBRARY_PATH:-}"' ~/.local/bin/osmo-launcher
osmo-launcher
```

On ARM (aarch64) replace `linux-64` with `linux-aarch64` in the URL.

**With root:**

| Distro | Command |
|---|---|
| openSUSE | `sudo zypper install libglib-2_0-0` |
| Ubuntu / Debian | `sudo apt install libglib2.0-0` |
| Fedora | `sudo dnf install glib2` |

### Other missing libraries

List anything else Qt still needs:

```bash
ldd ~/.local/share/osmo-launcher/venv/lib/python3*/site-packages/PyQt6/QtCore*.so | grep "not found"
```

Common extras: `libxcb-cursor0`, `libxkbcommon-x11-0`, `libgl1`.

### 404 right after editing files on GitHub

GitHub's raw links can serve the old version for a few minutes. Wait about 5 minutes and try again.

### A game won't start after using the no-root fix

The fix puts extra libraries on `LD_LIBRARY_PATH`, which Steam can inherit. Open an issue and it can be cleared before launching.

## Uninstall

```bash
curl -fsSL https://raw.githubusercontent.com/brendenthebanana-hash/Osmo-Launcher/main/uninstall.sh | bash
```

Your themes stay in `~/.config/osmo-launcher`.
