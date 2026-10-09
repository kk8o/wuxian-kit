"""Installs WuxianKit into the game: the WuxianKit folder of this repo replaces Interface\\AddOns\\WuxianKit (what is not in
the repo goes, so no file of an older layout lingers). The game finds new or moved files only when it starts: restart
it fully after an install that added or moved files; a /reload is enough when only .lua files changed.

  python tools\\install.py [--game "<the game's folder: the one with Interface>"]
"""
import argparse
import shutil
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parents[1]
DEFAULT_GAME = Path(r"C:\Program Files (x86)\World of Warcraft\_cn_beta_")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--game", type=Path, default=DEFAULT_GAME)
    a = ap.parse_args()
    addons = a.game / "Interface" / "AddOns"
    if not addons.is_dir():
        print(f"no Interface\\AddOns in {a.game}", file=sys.stderr)
        return 1
    source, target = REPO / "WuxianKit", addons / "WuxianKit"
    if target.exists():
        shutil.rmtree(target)
    shutil.copytree(source, target, ignore=shutil.ignore_patterns("*.bak", "__pycache__"))
    files = sorted(p.relative_to(target).as_posix() for p in target.rglob("*") if p.is_file())
    print(f"installed {len(files)} files into {target}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
