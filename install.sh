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
#!/usr/bin/env python3
"""Osmo Launcher - a water-themed Steam game launcher."""
import glob, json, math, os, random, re, subprocess, sys
from pathlib import Path
from PyQt6.QtCore import QPointF, QSize, Qt, QTimer
from PyQt6.QtGui import QColor, QFont, QIcon, QLinearGradient, QPainter, QPainterPath, QPen, QPixmap
from PyQt6.QtWidgets import (QApplication, QCheckBox, QColorDialog, QComboBox, QDialog, QFormLayout,
    QHBoxLayout, QLabel, QLineEdit, QListWidget, QListWidgetItem, QMainWindow,
    QMessageBox, QPushButton, QVBoxLayout, QWidget)

CONF = Path(os.environ.get("XDG_CONFIG_HOME", Path.home() / ".config")) / "osmo-launcher"
THEMES_DIR = CONF / "themes"
SETTINGS = CONF / "settings.json"
KEYS = {"bg": "Background", "panel": "Sidebar / panels", "card": "Game cards",
        "text": "Text", "muted": "Muted text", "accent": "Accent", "accent_text": "Text on accent"}
BUILTIN = {
    "Water": dict(bg="#f3f9ff", panel="#ffffff", card="#e1f0ff", text="#0b3b66",
                  muted="#5f8db8", accent="#1e90ff", accent_text="#ffffff"),
    "Deep Ocean": dict(bg="#06182b", panel="#0a2540", card="#0f3256", text="#e8f4ff",
                       muted="#7fb0dc", accent="#38b6ff", accent_text="#04182b"),
    "Lagoon": dict(bg="#ffffff", panel="#eaf7fb", card="#d3eef7", text="#0a4f66",
                   muted="#4f94aa", accent="#00a8cc", accent_text="#ffffff"),
}

def load_settings():
    try: return json.loads(SETTINGS.read_text())
    except Exception: return {}

def save_settings(d):
    CONF.mkdir(parents=True, exist_ok=True); SETTINGS.write_text(json.dumps(d))

def all_themes():
    t = dict(BUILTIN)
    for f in sorted(THEMES_DIR.glob("*.json")) if THEMES_DIR.exists() else []:
        try:
            d = json.loads(f.read_text())
            t[d.get("name", f.stem)] = {**BUILTIN["Water"], **d.get("colors", {})}
        except Exception: pass
    return t

def qss(c):
    return f"""
    QMainWindow, QDialog, #root {{ background:{c['bg']}; }}
    QWidget {{ color:{c['text']}; font-size:14px; }}
    #side {{ background:{c['panel']}; border-right:1px solid {c['card']}; }}
    #logo {{ font-size:26px; font-weight:700; color:{c['accent']}; }}
    #sub {{ color:{c['muted']}; }}
    QLineEdit, QComboBox {{ background:{c['card']}; border:1px solid transparent; border-radius:10px; padding:8px 12px; }}
    QLineEdit:focus, QComboBox:focus {{ border:1px solid {c['accent']}; }}
    QComboBox QAbstractItemView {{ background:{c['panel']}; selection-background-color:{c['accent']}; selection-color:{c['accent_text']}; }}
    QPushButton {{ background:{c['card']}; border:none; border-radius:10px; padding:9px 14px; }}
    QPushButton:hover {{ background:{c['muted']}; color:{c['accent_text']}; }}
    QPushButton#play {{ background:{c['accent']}; color:{c['accent_text']}; font-weight:700; font-size:15px; }}
    QPushButton#play:hover {{ background:{c['text']}; }}
    QListWidget {{ background:transparent; border:none; outline:none; }}
    QListWidget::item {{ background:{c['card']}; border-radius:14px; margin:8px; padding:8px; color:{c['text']}; }}
    QListWidget::item:hover {{ border:2px solid {c['muted']}; }}
    QListWidget::item:selected {{ border:2px solid {c['accent']}; background:{c['card']}; color:{c['text']}; }}
    QCheckBox::indicator {{ width:18px; height:18px; border-radius:5px; background:{c['card']}; }}
    QCheckBox::indicator:checked {{ background:{c['accent']}; }}
    QScrollBar:vertical {{ background:transparent; width:10px; }}
    QScrollBar::handle:vertical {{ background:{c['muted']}; border-radius:5px; min-height:30px; }}
    QScrollBar::add-line, QScrollBar::sub-line {{ height:0; }}
    """

# ---------- Steam ----------
def steam_roots():
    h = Path.home()
    cands = [h/".steam/steam", h/".local/share/Steam", h/".var/app/com.valvesoftware.Steam/.local/share/Steam"]
    seen, out = set(), []
    for p in cands:
        r = p.resolve()
        if r.exists() and r not in seen: seen.add(r); out.append(p)
    return out

SKIP = re.compile(r"Proton|Steam Linux Runtime|Steamworks Common|Steam Controller", re.I)

def find_games():
    games = {}
    for root in steam_roots():
        libs = {root}
        vdf = root/"steamapps/libraryfolders.vdf"
        if vdf.exists():
            libs |= {Path(m) for m in re.findall(r'"path"\s+"([^"]+)"', vdf.read_text(errors="ignore"))}
        for lib in libs:
            for acf in glob.glob(str(lib/"steamapps/appmanifest_*.acf")):
                t = Path(acf).read_text(errors="ignore")
                i = re.search(r'"appid"\s+"(\d+)"', t); n = re.search(r'"name"\s+"([^"]+)"', t)
                if i and n and not SKIP.search(n.group(1)):
                    games[i.group(1)] = (n.group(1), root)
    return sorted(((a, n, r) for a, (n, r) in games.items()), key=lambda g: g[1].lower())

def cover(appid, name, root, size=QSize(150, 225)):
    cache = Path(root)/"appcache/librarycache"
    for p in [cache/f"{appid}_library_600x900.jpg", cache/appid/"library_600x900.jpg",
              *glob.glob(str(cache/appid/"**/library_600x900.jpg"), recursive=True)]:
        if Path(p).exists():
            pm = QPixmap(str(p))
            if not pm.isNull():
                return pm.scaled(size, Qt.AspectRatioMode.KeepAspectRatioByExpanding,
                                 Qt.TransformationMode.SmoothTransformation).copy(0, 0, size.width(), size.height())
    pm = QPixmap(size); pm.fill(Qt.GlobalColor.transparent)
    p = QPainter(pm); g = QLinearGradient(0, 0, 0, size.height())
    g.setColorAt(0, QColor("#4db8ff")); g.setColorAt(1, QColor("#0b4f9c"))
    p.fillRect(pm.rect(), g); p.setPen(QColor("white")); p.setFont(QFont("Sans", 54, QFont.Weight.Bold))
    p.drawText(pm.rect(), Qt.AlignmentFlag.AlignCenter, name[:1].upper()); p.end()
    return pm

def launch(appid, root):
    url = f"steam://rungameid/{appid}"
    if "com.valvesoftware.Steam" in str(root):
        cmd = ["flatpak", "run", "com.valvesoftware.Steam", url]
    else:
        cmd = ["steam", url]
    env = os.environ.copy()  # keep Osmo's bundled libs away from Steam
    env["LD_LIBRARY_PATH"] = ":".join(x for x in env.get("LD_LIBRARY_PATH", "").split(":") if x and "osmo-launcher/libs" not in x)
    try: subprocess.Popen(cmd, start_new_session=True, env=env)
    except FileNotFoundError: subprocess.Popen(["xdg-open", url], start_new_session=True, env=env)

def add_desktop_shortcut():
    try: d = subprocess.run(["xdg-user-dir", "DESKTOP"], capture_output=True, text=True).stdout.strip()
    except Exception: d = ""
    desk = Path(d) if d else Path.home() / "Desktop"
    desk.mkdir(parents=True, exist_ok=True)
    f = desk / "osmo-launcher.desktop"
    f.write_text("[Desktop Entry]\nType=Application\nName=Osmo Launcher\n"
                 "Comment=Water-themed Steam game launcher\n"
                 f"Exec={Path.home() / '.local/bin/osmo-launcher'}\nIcon=osmo-launcher\n"
                 "Categories=Game;\nTerminal=false\n")
    f.chmod(0o755)
    subprocess.run(["gio", "set", str(f), "metadata::trusted", "true"], capture_output=True)
    return f

# ---------- Animated water background ----------
def mix(a, b, t):
    return QColor(*(int(x*(1-t) + y*t) for x, y in zip(a.getRgb()[:3], b.getRgb()[:3])))

class WaterBG(QWidget):
    LAYERS = [(14, 320, 1.0, 50, .80), (18, 420, -0.7, 40, .86), (12, 260, 1.4, 70, .92)]
    def __init__(self):
        super().__init__(); self.bg = QColor("#f3f9ff"); self.ac = QColor("#1e90ff"); self.t = 0.0; self.on = True
        self.bubbles = [[random.random(), random.random(), random.uniform(3, 9), random.uniform(.03, .08)] for _ in range(14)]
        self.timer = QTimer(self); self.timer.timeout.connect(self.tick)
    def set_colors(self, bg, ac): self.bg, self.ac = QColor(bg), QColor(ac); self.update()
    def set_animated(self, on):
        self.on = on
        if on and self.isVisible(): self.timer.start(33)
        else: self.timer.stop()
        self.update()
    def showEvent(self, e):
        if self.on: self.timer.start(33)
    def hideEvent(self, e): self.timer.stop()
    def tick(self):
        self.t += 0.033
        for b in self.bubbles:
            b[1] -= b[3] * 0.033 * 6
            if b[1] < -0.05: b[0], b[1] = random.random(), 1.05
        self.update()
    def paintEvent(self, e):
        p = QPainter(self); p.setRenderHint(QPainter.RenderHint.Antialiasing)
        w, h = self.width(), self.height()
        g = QLinearGradient(0, 0, 0, h); g.setColorAt(0, self.bg); g.setColorAt(1, mix(self.bg, self.ac, .18))
        p.fillRect(self.rect(), g)
        for i, (amp, wl, sp, alpha, base) in enumerate(self.LAYERS):
            path = QPainterPath(); path.moveTo(0, h); x = 0
            while x <= w + 6:
                path.lineTo(x, h*base + amp*math.sin(2*math.pi*x/wl + self.t*sp + i*1.7)); x += 6
            path.lineTo(w, h); path.closeSubpath()
            c = QColor(self.ac); c.setAlpha(alpha); p.fillPath(path, c)
        c = QColor(self.ac); c.setAlpha(80); p.setPen(QPen(c, 1.5)); p.setBrush(Qt.BrushStyle.NoBrush)
        for bx, by, r, _ in self.bubbles:
            p.drawEllipse(QPointF(bx*w + 6*math.sin(self.t*2 + r), by*h), r, r)
        p.end()

# ---------- Theme editor ----------
class ThemeEditor(QDialog):
    def __init__(self, base, parent=None):
        super().__init__(parent); self.setWindowTitle("Custom theme"); self.colors = dict(base)
        lay = QVBoxLayout(self); form = QFormLayout()
        self.name = QLineEdit("My Theme"); form.addRow("Name", self.name)
        self.btns = {}
        for k, label in KEYS.items():
            b = QPushButton(); b.clicked.connect(lambda _, k=k: self.pick(k)); self.btns[k] = b
            form.addRow(label, b); self.paint(k)
        lay.addLayout(form)
        save = QPushButton("Save theme"); save.setObjectName("play"); save.clicked.connect(self.save)
        lay.addWidget(save)
    def paint(self, k):
        c = self.colors[k]; self.btns[k].setText(c)
        self.btns[k].setStyleSheet(f"background:{c}; color:{'#000' if QColor(c).lightness()>128 else '#fff'};")
    def pick(self, k):
        c = QColorDialog.getColor(QColor(self.colors[k]), self)
        if c.isValid(): self.colors[k] = c.name(); self.paint(k)
    def save(self):
        n = self.name.text().strip() or "My Theme"
        THEMES_DIR.mkdir(parents=True, exist_ok=True)
        (THEMES_DIR/(re.sub(r"\W+", "_", n)+".json")).write_text(json.dumps({"name": n, "colors": self.colors}, indent=2))
        self.accepted_name = n; self.accept()

# ---------- Main window ----------
class Osmo(QMainWindow):
    def __init__(self):
        super().__init__(); self.setWindowTitle("Osmo Launcher"); self.resize(1100, 700)
        root = QWidget(); root.setObjectName("root"); self.setCentralWidget(root)
        h = QHBoxLayout(root); h.setContentsMargins(0, 0, 0, 0); h.setSpacing(0)
        side = QWidget(); side.setObjectName("side"); side.setFixedWidth(230)
        s = QVBoxLayout(side); s.setContentsMargins(18, 22, 18, 18); s.setSpacing(10)
        logo = QLabel("💧 Osmo"); logo.setObjectName("logo"); sub = QLabel("Steam launcher"); sub.setObjectName("sub")
        s.addWidget(logo); s.addWidget(sub); s.addSpacing(14)
        s.addWidget(QLabel("Theme")); self.theme_box = QComboBox(); s.addWidget(self.theme_box)
        new = QPushButton("＋ Custom theme"); new.clicked.connect(self.new_theme); s.addWidget(new)
        anim = QCheckBox("Animated background"); anim.setChecked(load_settings().get("anim", True))
        anim.toggled.connect(self.toggle_anim); s.addWidget(anim)
        desk = QPushButton("🖥 Add to desktop"); desk.clicked.connect(self.to_desktop); s.addWidget(desk)
        s.addStretch()
        self.count = QLabel(); self.count.setObjectName("sub"); s.addWidget(self.count)
        ref = QPushButton("⟳ Refresh library"); ref.clicked.connect(self.load); s.addWidget(ref)
        h.addWidget(side)
        self.bg = WaterBG(); self.bg.set_animated(load_settings().get("anim", True))
        main = QVBoxLayout(self.bg); main.setContentsMargins(22, 20, 22, 20)
        self.search = QLineEdit(); self.search.setPlaceholderText("Search games…"); self.search.textChanged.connect(self.filter)
        main.addWidget(self.search)
        self.list = QListWidget(); self.list.setViewMode(QListWidget.ViewMode.IconMode)
        self.list.setIconSize(QSize(150, 225)); self.list.setResizeMode(QListWidget.ResizeMode.Adjust)
        self.list.setMovement(QListWidget.Movement.Static); self.list.setWordWrap(True)
        self.list.setGridSize(QSize(190, 300)); self.list.itemDoubleClicked.connect(self.play)
        main.addWidget(self.list)
        self.play_btn = QPushButton("▶  Play selected"); self.play_btn.setObjectName("play")
        self.play_btn.clicked.connect(lambda: self.list.currentItem() and self.play(self.list.currentItem()))
        main.addWidget(self.play_btn); h.addWidget(self.bg, 1)
        self.fill_themes(load_settings().get("theme", "Water")); self.theme_box.currentTextChanged.connect(self.apply)
        self.load()

    def fill_themes(self, select):
        self.theme_box.blockSignals(True); self.theme_box.clear()
        self.themes = all_themes(); self.theme_box.addItems(self.themes)
        if select in self.themes: self.theme_box.setCurrentText(select)
        self.theme_box.blockSignals(False); self.apply(self.theme_box.currentText())

    def apply(self, name):
        if name in self.themes:
            QApplication.instance().setStyleSheet(qss(self.themes[name]))
            self.bg.set_colors(self.themes[name]['bg'], self.themes[name]['accent'])
            save_settings({**load_settings(), "theme": name})

    def toggle_anim(self, on):
        self.bg.set_animated(on); save_settings({**load_settings(), "anim": on})

    def to_desktop(self):
        try:
            f = add_desktop_shortcut()
            QMessageBox.information(self, "Osmo", f"Shortcut added:\n{f}\n\nIf it shows as untrusted, right-click it and choose Allow Launching.")
        except Exception as e:
            QMessageBox.warning(self, "Osmo", f"Couldn't add the shortcut: {e}")

    def new_theme(self):
        d = ThemeEditor(self.themes[self.theme_box.currentText()], self)
        if d.exec(): self.fill_themes(d.accepted_name)

    def load(self):
        self.list.clear(); self.games = find_games()
        for appid, name, root in self.games:
            it = QListWidgetItem(QIcon(cover(appid, name, root)), name)
            it.setData(Qt.ItemDataRole.UserRole, (appid, str(root))); it.setTextAlignment(Qt.AlignmentFlag.AlignHCenter)
            self.list.addItem(it)
        self.count.setText(f"{len(self.games)} games")
        if not self.games:
            QMessageBox.information(self, "Osmo", "No installed Steam games found.")
        self.filter(self.search.text())

    def filter(self, t):
        for i in range(self.list.count()):
            self.list.item(i).setHidden(t.lower() not in self.list.item(i).text().lower())

    def play(self, item):
        appid, root = item.data(Qt.ItemDataRole.UserRole); launch(appid, root)

if __name__ == "__main__":
    app = QApplication(sys.argv); app.setApplicationName("Osmo Launcher")
    app.setDesktopFileName("osmo-launcher")
    for ic in (Path.home()/".local/share/icons/hicolor/256x256/apps/osmo-launcher.png",
               Path.home()/".local/share/icons/hicolor/scalable/apps/osmo-launcher.svg"):
        if ic.exists(): app.setWindowIcon(QIcon(str(ic))); break
    w = Osmo(); w.show(); sys.exit(app.exec())
OSMO_PY_EOF

cat > "$ICONS/osmo-launcher.svg" <<'OSMO_SVG_EOF'
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 256 256" width="256" height="256" xmlns:c2pa="http://c2pa.org/manifest"><metadata><c2pa:manifest>AAAWgmp1bWIAAAAeanVtZGMycGEAEQAQgAAAqgA4m3EDYzJwYQAAABZcanVtYgAAAEdqdW1kYzJtYQARABCAAACqADibcQN1cm46YzJwYTpkZDVkZDUxNC0xOGU3LTQ2MTAtODBiZS0yOThhMDA0OWFkZDEAAAADl2p1bWIAAAApanVtZGMyYXMAEQAQgAAAqgA4m3EDYzJwYS5hc3NlcnRpb25zAAAAALxqdW1iAAAARGp1bWRjYm9yABEAEIAAAKoAOJtxE2MycGEuaW5ncmVkaWVudC52MwAAAAAYYzJzaABygK/da65NMFcUYoy/eMgAAABwY2JvcqNpZGM6Zm9ybWF0bWltYWdlL3N2Zyt4bWxqaW5zdGFuY2VJRHgseG1wOmlpZDpjMDIyYjQ4OC1mZjY5LTRhNDYtYTUzNi05NzI3NjNhMjNiNzRscmVsYXRpb25zaGlwaHBhcmVudE9mAAAB4mp1bWIAAABBanVtZGNib3IAEQAQgAAAqgA4m3ETYzJwYS5hY3Rpb25zLnYyAAAAABhjMnNo3CmGfHK61bQrD0XApT3OQAAAAZljYm9yomdhY3Rpb25zgqJmYWN0aW9ua2MycGEub3BlbmVkanBhcmFtZXRlcnOha2luZ3JlZGllbnRzgaJjdXJseC1zZWxmI2p1bWJmPWMycGEuYXNzZXJ0aW9ucy9jMnBhLmluZ3JlZGllbnQudjNkaGFzaFggO3mdbe0qHMwZbIQ5gI5MywhLSGCbryNLYrzocNrwynykZmFjdGlvbngdY29tLmFudGhyb3BpYy5jbGF1ZGUucHJvdmlkZWRqcGFyYW1ldGVyc6F4H2NvbS5hbnRocm9waWMub3JpZ2luLWNvbmZpZGVuY2VndW5rbm93bmtkZXNjcmlwdGlvbnhmQ2xhdWRlIHByb3ZpZGVkIHRoaXMgZmlsZSBhdCB0aGUgcmVxdWVzdCBvZiBhIHVzZXIgYW5kIG1heSBoYXZlIGNyZWF0ZWQgb3IgbW9kaWZpZWQgdGhlIGZpbGUgY29udGVudHMubXNvZnR3YXJlQWdlbnShZG5hbWVmQ2xhdWRlcmFsbEFjdGlvbnNJbmNsdWRlZPUAAADIanVtYgAAAEBqdW1kY2JvcgARABCAAACqADibcRNjMnBhLmhhc2guZGF0YQAAAAAYYzJzaIdmulk9a9oAUlzKFa2FPnkAAACAY2JvcqVjYWxnZnNoYTI1NmNwYWRNAAAAAAAAAAAAAAAAAGRoYXNoWCDavBygTYyEDX2gPpxuujGqQzhe75QnB3RXcMu2fN8AFWRuYW1lbmp1bWJmIG1hbmlmZXN0amV4Y2x1c2lvbnOBomVzdGFydBiWZmxlbmd0aBkeBAAAAj5qdW1iAAAAJ2p1bWRjMmNsABEAEIAAAKoAOJtxA2MycGEuY2xhaW0udjIAAAACD2Nib3KlY2FsZ2ZzaGEyNTZpc2lnbmF0dXJleE1zZWxmI2p1bWJmPS9jMnBhL3VybjpjMnBhOmRkNWRkNTE0LTE4ZTctNDYxMC04MGJlLTI5OGEwMDQ5YWRkMS9jMnBhLnNpZ25hdHVyZWppbnN0YW5jZUlEeCx4bXA6aWlkOjdiOTU1ZTZmLTgyNjQtNDhkZS04MjhkLWRlNTI3M2YwMDI3YXJjcmVhdGVkX2Fzc2VydGlvbnODomN1cmx4LXNlbGYjanVtYmY9YzJwYS5hc3NlcnRpb25zL2MycGEuaW5ncmVkaWVudC52M2RoYXNoWCA7eZ1t7SoczBlshDmAjkzLCEtIYJuvI0tivOhw2vDKfKJjdXJseCpzZWxmI2p1bWJmPWMycGEuYXNzZXJ0aW9ucy9jMnBhLmFjdGlvbnMudjJkaGFzaFggql1v//cbjWatmwJnu3Ji8z3MswcXb5mx/vGQ9p+qb+miY3VybHgpc2VsZiNqdW1iZj1jMnBhLmFzc2VydGlvbnMvYzJwYS5oYXNoLmRhdGFkaGFzaFggHBag6McXY+4MOIGobnSr0xyo8l5v5mMJiWKL1aWpjd10Y2xhaW1fZ2VuZXJhdG9yX2luZm+jZG5hbWVvQW50aHJvcGljIEZpbGVzZ3ZlcnNpb25lMS4wLjBrc3BlY1ZlcnNpb25lMi40LjAAABA4anVtYgAAAChqdW1kYzJjcwARABCAAACqADibcQNjMnBhLnNpZ25hdHVyZQAAABAIY2JvctKEWQISogEmGCFZAgowggIGMIIBjaADAgECAhRA5aAK7sI50L64g/oGQgU9Z1UTADAKBggqhkjOPQQDAzBJMRcwFQYDVQQKEw5BbnRocm9waWMsIFBCQzEuMCwGA1UEAxMlQW50aHJvcGljIENvbnRlbnQgQ3JlZGVudGlhbHMgUm9vdCBDQTAeFw0yNjA4MDcxODQzNTZaFw0yODA4MDYxOTQzNTZaMEQxFzAVBgNVBAoTDkFudGhyb3BpYywgUEJDMSkwJwYDVQQDEyBBbnRocm9waWMgQ2xhdWRlIENvbnRlbnQgU2lnbmluZzBZMBMGByqGSM49AgEGCCqGSM49AwEHA0IABJh6CmvLUBgFFNU0vUKlOVtE6djd17L5SuwX0LemFisBM3dkd/3cyjxFA3Qo5S46fX0/ihY0VZ7mfb9KF703t5OjWDBWMA4GA1UdDwEB/wQEAwIHgDAVBgNVHSUEDjAMBgorBgEEAYPoXgIBMAwGA1UdEwEB/wQCMAAwHwYDVR0jBBgwFoAUzlHiBIFOZFsj+OPEz5o+nMHXXMIwCgYIKoZIzj0EAwMDZwAwZAIwMXMdFJ4BetLLVY7ORuE9noqbbAZOZn/aArXyTwFAZfKrPzxF2vPoJNf1+UCdg1XGAjBwX1zd9WGqYkqmL5SFqw1QySjr1zJfpJM9+1rdDwSPLMOPOjKuiXjoU/pUUeG9RwmhY3BhZFkNngAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAPZYQMKlj0m3kfTzJLdoD+mn5O3c13GA8MDhj8n+l+SRZNqW7P9dWis/idPHqbQCTRgOcEkMw5m553n+tFVk26Fhc48=</c2pa:manifest></metadata>
  <defs>
    <linearGradient id="bg" x1="0" y1="0" x2="0" y2="1">
      <stop offset="0" stop-color="#8fdcff"/>
      <stop offset="0.55" stop-color="#2a8cff"/>
      <stop offset="1" stop-color="#0b4fc4"/>
    </linearGradient>
    <linearGradient id="water" x1="0" y1="0" x2="0" y2="1">
      <stop offset="0" stop-color="#4db8ff"/>
      <stop offset="1" stop-color="#0a5cd6"/>
    </linearGradient>
    <clipPath id="drop">
      <path d="M128 36C128 36 66 108 66 150a62 62 0 0 0 124 0C190 108 128 36 128 36z"/>
    </clipPath>
  </defs>
  <rect width="256" height="256" rx="58" fill="url(#bg)"/>
  <ellipse cx="128" cy="30" rx="150" ry="40" fill="#fff" opacity="0.10"/>
  <path d="M128 36C128 36 66 108 66 150a62 62 0 0 0 124 0C190 108 128 36 128 36z" fill="#fff"/>
  <g clip-path="url(#drop)">
    <path d="M50 150Q89 126 128 150T206 150V220H50z" fill="url(#water)"/>
    <path d="M50 178Q89 158 128 178T206 178V220H50z" fill="#0b4fc4" opacity="0.35"/>
  </g>
  <path d="M92 118C98 104 108 92 118 82" stroke="#8fdcff" stroke-width="7" stroke-linecap="round" fill="none" opacity="0.8"/>
</svg>
OSMO_SVG_EOF

python3 -c 'import base64,sys; sys.stdout.buffer.write(base64.b64decode(sys.stdin.read()))' > "$PNGDIR/osmo-launcher.png" <<'OSMO_PNG_EOF'
iVBORw0KGgoAAAANSUhEUgAAAQAAAAEACAYAAABccqhmAAAWfmNhQlgAABZ+anVtYgAAAB5qdW1k
YzJwYQARABCAAACqADibcQNjMnBhAAAAFlhqdW1iAAAAR2p1bWRjMm1hABEAEIAAAKoAOJtxA3Vy
bjpjMnBhOmRjNmFjYWFlLTAwYjAtNDQ1Zi04Mjc3LWY4YTk5YzE2MGQ5ZAAAAAOTanVtYgAAAClq
dW1kYzJhcwARABCAAACqADibcQNjMnBhLmFzc2VydGlvbnMAAAAAuGp1bWIAAABEanVtZGNib3IA
EQAQgAAAqgA4m3ETYzJwYS5pbmdyZWRpZW50LnYzAAAAABhjMnNoH+apK6tRaUi40uH2hIMxuAAA
AGxjYm9yo2lkYzpmb3JtYXRpaW1hZ2UvcG5namluc3RhbmNlSUR4LHhtcDppaWQ6NTc5MTFjZTct
NWIzNC00NDVhLWJjNTctYWQ3MjBiYWIxMzRhbHJlbGF0aW9uc2hpcGhwYXJlbnRPZgAAAeJqdW1i
AAAAQWp1bWRjYm9yABEAEIAAAKoAOJtxE2MycGEuYWN0aW9ucy52MgAAAAAYYzJzaCJATbG3/7tI
DVMhI9hIMUEAAAGZY2JvcqJnYWN0aW9uc4KiZmFjdGlvbmtjMnBhLm9wZW5lZGpwYXJhbWV0ZXJz
oWtpbmdyZWRpZW50c4GiY3VybHgtc2VsZiNqdW1iZj1jMnBhLmFzc2VydGlvbnMvYzJwYS5pbmdy
ZWRpZW50LnYzZGhhc2hYIE49imQA+qIRsKzjNRqYPu8RGUABuRmbGeepjOj/9Ug7pGZhY3Rpb254
HWNvbS5hbnRocm9waWMuY2xhdWRlLnByb3ZpZGVkanBhcmFtZXRlcnOheB9jb20uYW50aHJvcGlj
Lm9yaWdpbi1jb25maWRlbmNlZ3Vua25vd25rZGVzY3JpcHRpb254ZkNsYXVkZSBwcm92aWRlZCB0
aGlzIGZpbGUgYXQgdGhlIHJlcXVlc3Qgb2YgYSB1c2VyIGFuZCBtYXkgaGF2ZSBjcmVhdGVkIG9y
IG1vZGlmaWVkIHRoZSBmaWxlIGNvbnRlbnRzLm1zb2Z0d2FyZUFnZW50oWRuYW1lZkNsYXVkZXJh
bGxBY3Rpb25zSW5jbHVkZWT1AAAAyGp1bWIAAABAanVtZGNib3IAEQAQgAAAqgA4m3ETYzJwYS5o
YXNoLmRhdGEAAAAAGGMyc2j63l+YhCOWA/uDHKD2gS+EAAAAgGNib3KlY2FsZ2ZzaGEyNTZjcGFk
TQAAAAAAAAAAAAAAAABkaGFzaFggFkn8Xm4R82GYG0q6pH02hlzu0aZatzNLqo2bXLFUqEtkbmFt
ZW5qdW1iZiBtYW5pZmVzdGpleGNsdXNpb25zgaJlc3RhcnQYIWZsZW5ndGgZFooAAAI+anVtYgAA
ACdqdW1kYzJjbAARABCAAACqADibcQNjMnBhLmNsYWltLnYyAAAAAg9jYm9ypWNhbGdmc2hhMjU2
aXNpZ25hdHVyZXhNc2VsZiNqdW1iZj0vYzJwYS91cm46YzJwYTpkYzZhY2FhZS0wMGIwLTQ0NWYt
ODI3Ny1mOGE5OWMxNjBkOWQvYzJwYS5zaWduYXR1cmVqaW5zdGFuY2VJRHgseG1wOmlpZDozN2I5
YzAyMy02YmU2LTQxMmEtODNlMy0xMDcyOTc3N2M4ZjJyY3JlYXRlZF9hc3NlcnRpb25zg6JjdXJs
eC1zZWxmI2p1bWJmPWMycGEuYXNzZXJ0aW9ucy9jMnBhLmluZ3JlZGllbnQudjNkaGFzaFggTj2K
ZAD6ohGwrOM1Gpg+7xEZQAG5GZsZ56mM6P/1SDuiY3VybHgqc2VsZiNqdW1iZj1jMnBhLmFzc2Vy
dGlvbnMvYzJwYS5hY3Rpb25zLnYyZGhhc2hYIH2MG5Q9mAHF0Tb9SqNQNlgxacDVTL7H+XzbaZGM
RUDcomN1cmx4KXNlbGYjanVtYmY9YzJwYS5hc3NlcnRpb25zL2MycGEuaGFzaC5kYXRhZGhhc2hY
IJHBflFkbFCmmdUik2PznI9SpTQpzKwv6KQ1VRvkVZcXdGNsYWltX2dlbmVyYXRvcl9pbmZvo2Ru
YW1lb0FudGhyb3BpYyBGaWxlc2d2ZXJzaW9uZTEuMC4wa3NwZWNWZXJzaW9uZTIuNC4wAAAQOGp1
bWIAAAAoanVtZGMyY3MAEQAQgAAAqgA4m3EDYzJwYS5zaWduYXR1cmUAAAAQCGNib3LShFkCEqIB
JhghWQIKMIICBjCCAY2gAwIBAgIUQOWgCu7COdC+uIP6BkIFPWdVEwAwCgYIKoZIzj0EAwMwSTEX
MBUGA1UEChMOQW50aHJvcGljLCBQQkMxLjAsBgNVBAMTJUFudGhyb3BpYyBDb250ZW50IENyZWRl
bnRpYWxzIFJvb3QgQ0EwHhcNMjYwODA3MTg0MzU2WhcNMjgwODA2MTk0MzU2WjBEMRcwFQYDVQQK
Ew5BbnRocm9waWMsIFBCQzEpMCcGA1UEAxMgQW50aHJvcGljIENsYXVkZSBDb250ZW50IFNpZ25p
bmcwWTATBgcqhkjOPQIBBggqhkjOPQMBBwNCAASYegpry1AYBRTVNL1CpTlbROnY3dey+UrsF9C3
phYrATN3ZHf93Mo8RQN0KOUuOn19P4oWNFWe5n2/She9N7eTo1gwVjAOBgNVHQ8BAf8EBAMCB4Aw
FQYDVR0lBA4wDAYKKwYBBAGD6F4CATAMBgNVHRMBAf8EAjAAMB8GA1UdIwQYMBaAFM5R4gSBTmRb
I/jjxM+aPpzB11zCMAoGCCqGSM49BAMDA2cAMGQCMDFzHRSeAXrSy1WOzkbhPZ6Km2wGTmZ/2gK1
8k8BQGXyqz88Rdrz6CTX9flAnYNVxgIwcF9c3fVhqmJKpi+UhasNUMko69cyX6STPfta3Q8EjyzD
jzoyrol46FP6VFHhvUcJoWNwYWRZDZ4AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
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
u/T6AAAAAElFTkSuQmCC
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

