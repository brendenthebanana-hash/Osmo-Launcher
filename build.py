"""Builds the self-contained install.sh from the files in src/.  Run: python3 src/build.py"""
import base64, pathlib
src = pathlib.Path(__file__).parent; out = src.parent / "install.sh"
t = (src / "install.template.sh").read_text()
py = (src / "osmo_launcher.py").read_text().rstrip("\n")
svg = (src / "osmo-launcher.svg").read_text().rstrip("\n")
b = base64.b64encode((src / "osmo-launcher.png").read_bytes()).decode()
b = "\n".join(b[i:i+76] for i in range(0, len(b), 76))
for marker in ("OSMO_PY_EOF", "OSMO_SVG_EOF", "OSMO_PNG_EOF"):
    assert marker not in py + svg, marker
out.write_text(t.replace("@@PY@@", py).replace("@@SVG@@", svg).replace("@@PNG_B64@@", b) + "\n")
out.chmod(0o755); print("built", out)
