# 💧 Osmo Launcher

A water-themed (blue and white) launcher for your installed Steam games on Linux, with an animated water background and custom themes. Installs with one command, no root needed.

## Install

```bash
curl -fsSL https://raw.githubusercontent.com/brendenthebanana-hash/Osmo-Launcher/main/install.sh | bash
```

Then search **Osmo** in your app menu, or run `osmo-launcher`.

The installer is one self-contained file, so you can also download `install.sh` and run it directly:

```bash
bash install.sh
```

Options: `--desktop` adds a Desktop shortcut without asking, `--no-desktop` skips it.
Requirements: `python3` and Steam (run it at least once).

If `osmo-launcher` isn't found, add `~/.local/bin` to your PATH:

```bash
echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.bashrc && source ~/.bashrc
```

## Features

- Finds games across all Steam libraries (native and Flatpak Steam)
- Cover art from Steam's local cache, search, double-click to play
- Animated water background (flowing waves and bubbles), toggle it in the sidebar
- Themes: Water, Deep Ocean, Lagoon, plus a custom theme editor
- App menu entry, optional Desktop shortcut (or click **🖥 Add to desktop** in the app)

## Custom themes

Click **＋ Custom theme** in the app, or add a JSON file to `~/.config/osmo-launcher/themes/`:

```json
{"name": "Mine", "colors": {"bg": "#ffffff", "accent": "#00aaff"}}
```

Keys: `bg`, `panel`, `card`, `text`, `muted`, `accent`, `accent_text`.

## Update

Run the install command again. Your themes and settings are kept.

## Uninstall

```bash
curl -fsSL https://raw.githubusercontent.com/brendenthebanana-hash/Osmo-Launcher/main/uninstall.sh | bash
```

Your themes stay in `~/.config/osmo-launcher` (delete that folder to remove them too).

## Troubleshooting

### `ImportError: libgthread-2.0.so.0` (or another missing `.so` library)

Qt needs system libraries your distro doesn't have. The installer checks for this and fetches them into `~/.local/share/osmo-launcher/libs` automatically, no root needed. If that failed (for example, no internet), re-run the installer, or install the library yourself:

| Distro | Command |
|---|---|
| openSUSE | `sudo zypper install libglib-2_0-0 libgthread-2_0-0` |
| Ubuntu / Debian | `sudo apt install libglib2.0-0 libxcb-cursor0` |
| Fedora | `sudo dnf install glib2 xcb-util-cursor` |

To see everything Qt still needs:

```bash
ldd ~/.local/share/osmo-launcher/venv/lib/python3*/site-packages/PyQt6/Qt6/plugins/platforms/libqxcb.so | grep "not found"
```

### Osmo doesn't show up in my app menu

Refresh the menu, then log out and back in once:

```bash
update-desktop-database ~/.local/share/applications
xdg-desktop-menu forceupdate
gtk-update-icon-cache -f -t ~/.local/share/icons/hicolor
kbuildsycoca6 || kbuildsycoca5   # KDE only
```

### Desktop shortcut looks untrusted

Right-click it and choose **Allow Launching**.

### 404 when running the install command

Make sure `install.sh` is in the root of the repo on the `main` branch, and the repo is public. GitHub can serve an old version for a few minutes after you edit a file.

## For developers

`install.sh` contains the whole app. The sources live in `src/`; after editing `src/osmo_launcher.py` or the icons, rebuild it with:

```bash
python3 src/build.py
```
