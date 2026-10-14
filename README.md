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

Qt needs the system glib library, and your system doesn't have it. The installer tries to fetch it automatically. If you still see this error, fix it by hand.

**Option A: no root needed**

1. Download the library into Osmo's folder:

   ```bash
   cd ~/.local/share/osmo-launcher
   curl -Ls https://micro.mamba.pm/api/micromamba/linux-64/latest | tar -xj bin/micromamba
   MAMBA_ROOT_PREFIX=$PWD/mamba ./bin/micromamba create -y -p $PWD/libs -c conda-forge libglib
   ```

   On ARM (`uname -m` prints `aarch64`) use `linux-aarch64` instead of `linux-64`.

2. Check that it downloaded. This should print `libgthread-2.0.so.0`:

   ```bash
   ls libs/lib | grep gthread
   ```

3. Test that Qt starts. This should print `QT OK`:

   ```bash
   LD_LIBRARY_PATH=$PWD/libs/lib QT_QPA_PLATFORM=offscreen venv/bin/python -c "from PyQt6.QtCore import Qt; print('QT OK')"
   ```

4. Tell the launcher to use it (run this **once only**):

   ```bash
   sed -i '2i export LD_LIBRARY_PATH="$HOME/.local/share/osmo-launcher/libs/lib:${LD_LIBRARY_PATH:-}"' ~/.local/bin/osmo-launcher
   ```

5. Start it:

   ```bash
   osmo-launcher
   ```

**Option B: with root**

| Distro | Command |
|---|---|
| openSUSE | `sudo zypper install libglib-2_0-0` |
| Ubuntu / Debian | `sudo apt install libglib2.0-0` |
| Fedora | `sudo dnf install glib2` |

### Another library is missing (libxcb, libGL, libxkbcommon…)

List everything Qt still needs:

```bash
ldd ~/.local/share/osmo-launcher/venv/lib/python3*/site-packages/PyQt6/QtCore*.so | grep "not found"
```

Then install the matching package with your package manager, or add it to the micromamba command in step 1 (for example `libxcb xcb-util-cursor libxkbcommon libgl`).

### The error didn't change after the fix

Check that your launcher has the library line:

```bash
cat ~/.local/bin/osmo-launcher
```

It should contain a line starting with `export LD_LIBRARY_PATH=`. If it doesn't, redo step 4.

### 404 right after editing files on GitHub

GitHub's raw links can serve the old version for a few minutes. Wait about 5 minutes and try again.

## Uninstall

```bash
curl -fsSL https://raw.githubusercontent.com/brendenthebanana-hash/Osmo-Launcher/main/uninstall.sh | bash
```

Your themes stay in `~/.config/osmo-launcher`.
