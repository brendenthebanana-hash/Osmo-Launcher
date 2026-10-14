#!/usr/bin/env python3
"""Osmo Launcher - a water-themed Steam game launcher."""
import glob, json, os, re, subprocess, sys
from pathlib import Path
from PyQt6.QtCore import Qt, QSize
from PyQt6.QtGui import QColor, QFont, QIcon, QLinearGradient, QPainter, QPixmap
from PyQt6.QtWidgets import (QApplication, QColorDialog, QComboBox, QDialog, QFormLayout,
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
        desk = QPushButton("🖥 Add to desktop"); desk.clicked.connect(self.to_desktop); s.addWidget(desk)
        s.addStretch()
        self.count = QLabel(); self.count.setObjectName("sub"); s.addWidget(self.count)
        ref = QPushButton("⟳ Refresh library"); ref.clicked.connect(self.load); s.addWidget(ref)
        h.addWidget(side)
        main = QVBoxLayout(); main.setContentsMargins(22, 20, 22, 20)
        self.search = QLineEdit(); self.search.setPlaceholderText("Search games…"); self.search.textChanged.connect(self.filter)
        main.addWidget(self.search)
        self.list = QListWidget(); self.list.setViewMode(QListWidget.ViewMode.IconMode)
        self.list.setIconSize(QSize(150, 225)); self.list.setResizeMode(QListWidget.ResizeMode.Adjust)
        self.list.setMovement(QListWidget.Movement.Static); self.list.setWordWrap(True)
        self.list.setGridSize(QSize(190, 300)); self.list.itemDoubleClicked.connect(self.play)
        main.addWidget(self.list)
        self.play_btn = QPushButton("▶  Play selected"); self.play_btn.setObjectName("play")
        self.play_btn.clicked.connect(lambda: self.list.currentItem() and self.play(self.list.currentItem()))
        main.addWidget(self.play_btn); h.addLayout(main)
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
            save_settings({**load_settings(), "theme": name})

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
