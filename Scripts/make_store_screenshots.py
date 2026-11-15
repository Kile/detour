#!/usr/bin/env python3
"""Builds App Store–style screenshots and a Devpost cover from raw simulator captures.

Usage:
  python3 Scripts/make_store_screenshots.py [RAW_DIR]   (default: Marketing/raw)

Raw captures come from the MarketingScreenshotTests UI tests (see README → Store screenshots).
Needs Google Chrome (headless) for rendering. No Python packages required.
"""
import pathlib
import subprocess
import sys
import tempfile
import time

ROOT = pathlib.Path(__file__).resolve().parent.parent
RAW = pathlib.Path(sys.argv[1]) if len(sys.argv) > 1 else ROOT / "Marketing" / "raw"
OUT = ROOT / "Marketing"
SOURCE = OUT / "_source"
CHROME = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"

ASPHALT, SIGNAL, CREAM = "#1E2233", "#FF6B2C", "#FFF6EA"
MARK = (ROOT / "Design" / "brand" / "detour-mark.svg").read_text()
MARK_PATHS = MARK[MARK.index("<g"):MARK.rindex("</g>") + 4].replace('fill="#000"', f'fill="{SIGNAL}"')

# (raw file, headline with <em> highlight, subline, dark background?)
SHOTS = [
    ("01-home", "Take a little <em>detour</em>.", "One tap gives you a real-world quest made for exactly where you are.", True),
    ("02-nearby-quest", "Built from <em>real places</em> around you", "Shops, plaques and landmarks within a short walk, straight from the map.", False),
    ("03-hard-people-quest", "Hard means <em>hard</em>.", "Find someone who's had 5 Monsters today. Faces are blurred on your phone.", True),
    ("04-photo-challenge", "Photo challenges that know the <em>weather</em>", "Rain means umbrellas and reflections. Sun means long shadows.", False),
    ("05-result", "Snap it. Get it <em>checked</em>.", "A friendly AI referee, plus +50% when you beat the clock.", True),
    ("06-journal", "Level up. Collect <em>badges</em>.", "Streaks, points and a journal of every detour you've taken.", False),
]

W, H = 1290, 2796   # 6.7" App Store screenshot size

BASE_CSS = f"""
* {{ margin: 0; padding: 0; box-sizing: border-box; }}
html, body {{ width: {W}px; height: {H}px; overflow: hidden; }}
body {{ font-family: -apple-system, "SF Pro Display", "Helvetica Neue", Helvetica, Arial, sans-serif; }}
.dark {{ background: radial-gradient(120% 70% at 50% 0%, #2B3150 0%, {ASPHALT} 60%); color: {CREAM}; }}
.light {{ background: radial-gradient(120% 70% at 50% 0%, #FFFFFF 0%, {CREAM} 65%); color: {ASPHALT}; }}
em {{ font-style: normal; color: {SIGNAL}; }}
.light em {{ color: #E0561B; }}
.head {{ position: absolute; top: 150px; left: 90px; right: 90px; text-align: center; }}
h1 {{ font-size: 104px; line-height: 1.05; font-weight: 800; letter-spacing: -2.5px; text-wrap: balance; }}
p {{ margin-top: 34px; font-size: 44px; line-height: 1.3; font-weight: 500; opacity: 0.78; text-wrap: balance; }}
.phone {{ position: absolute; left: 50%; transform: translateX(-50%); border-radius: 132px; background: #0B0C10;
          padding: 22px; box-shadow: 0 60px 120px rgba(10, 12, 20, 0.45), 0 0 0 3px rgba(255,255,255,0.08); }}
.phone img {{ display: block; border-radius: 112px; }}
.mark {{ position: absolute; width: 88px; height: 88px; }}
"""


def phone(img: str, width: int, top: int, left: str = "50%") -> str:
    return (f'<div class="phone" style="top:{top}px; left:{left}">'
            f'<img src="{img}" style="width:{width}px"></div>')


def store_page(name: str, title: str, sub: str, dark: bool) -> str:
    img = (RAW / f"{name}.png").resolve().as_uri()
    return f"""<!doctype html><html><head><meta charset="utf-8"><style>{BASE_CSS}</style></head>
<body class="{'dark' if dark else 'light'}">
  <div class="head"><h1>{title}</h1><p>{sub}</p></div>
  {phone(img, 950, 610)}
</body></html>"""


def cover_page() -> str:
    cw, ch = 2400, 1600
    shots = [(RAW / f"{n}.png").resolve().as_uri() for n in ("04-photo-challenge", "01-home", "05-result")]
    css = BASE_CSS.replace(f"width: {W}px; height: {H}px", f"width: {cw}px; height: {ch}px")
    return f"""<!doctype html><html><head><meta charset="utf-8"><style>{css}
.brand {{ position: absolute; left: 130px; top: 50%; transform: translateY(-50%); width: 860px; }}
.brand h1 {{ font-size: 150px; letter-spacing: -4px; }}
.brand p {{ font-size: 54px; margin-top: 30px; }}
.logo {{ width: 190px; height: 190px; border-radius: 46px; background: {ASPHALT}; display: grid; place-items: center;
         box-shadow: 0 0 0 3px rgba(255,107,44,0.35); margin-bottom: 54px; }}
.phone {{ transform: none; border-radius: 86px; padding: 15px; }}
.phone img {{ border-radius: 72px; }}
.tags {{ margin-top: 54px; display: flex; gap: 18px; flex-wrap: wrap; }}
.tags span {{ font-size: 32px; font-weight: 600; padding: 14px 26px; border-radius: 40px; background: rgba(255,107,44,0.14); color: {SIGNAL}; }}
</style></head>
<body class="dark">
  <div class="brand">
    <div class="logo"><svg viewBox="0 0 256 256" width="130" height="130">{MARK_PATHS}</svg></div>
    <h1>Detour</h1>
    <p>Tiny real-world quests and photo challenges, made by AI for exactly where you are.</p>
    <div class="tags"><span>Venue · Nearby · City</span><span>Photo challenges</span><span>Time trial</span><span>Faces blurred on-device</span></div>
  </div>
  {phone(shots[0], 440, 307, "1045px")}
  {phone(shots[2], 440, 307, "1875px")}
  {phone(shots[1], 530, 210, "1415px")}
</body></html>"""


def render(html: str, out: pathlib.Path, width: int, height: int) -> None:
    SOURCE.mkdir(parents=True, exist_ok=True)
    src = SOURCE / (out.stem + ".html")
    src.write_text(html)
    out.parent.mkdir(parents=True, exist_ok=True)
    out.unlink(missing_ok=True)
    # A fresh profile per render: back-to-back headless runs sharing one profile can fail.
    for attempt in range(3):
        with tempfile.TemporaryDirectory() as profile:
            subprocess.run([CHROME, "--headless=new", "--disable-gpu", "--hide-scrollbars",
                            "--force-device-scale-factor=1", "--allow-file-access-from-files",
                            "--no-first-run", "--no-default-browser-check", f"--user-data-dir={profile}",
                            f"--window-size={width},{height}", f"--screenshot={out}", src.as_uri()],
                           stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        # Chrome sometimes crashes on shutdown after writing the file, so check the file, not the exit code.
        if out.exists() and out.stat().st_size > 0:
            print("wrote", out.relative_to(ROOT))
            return
        time.sleep(1.5)
    sys.exit(f"Chrome couldn't render {out.name}")


if __name__ == "__main__":
    missing = [n for n, *_ in SHOTS if not (RAW / f"{n}.png").exists()]
    if missing:
        sys.exit(f"Missing raw captures in {RAW}: {', '.join(missing)}")
    for index, (name, title, sub, dark) in enumerate(SHOTS, start=1):
        render(store_page(name, title, sub, dark), OUT / "AppStore" / f"{index:02d}-{name.split('-', 1)[1]}.png", W, H)
    render(cover_page(), OUT / "Devpost" / "cover-3x2.png", 2400, 1600)
