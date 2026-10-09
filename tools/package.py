r"""Packs WuxianKit for 无限工坊's extension catalog (wuxianwow.com/workshop/data/extensions.json, which the app's 扩展 page
reads): WuxianKit-<version>.zip, the WuxianKit folder as the AddOns folder holds it, and its catalog entry. The entry is
made from what the addon itself says: the .toc (version, titles, notes) and the manifest it gives in the test client, in
Chinese and in English (the extensions it holds with their titles, how many tools and events each has), plus the skills
in their folders. Both go into --out (dist\ in this repo by default; for a release, the folder the website serves as
/workshop/data): the zip beside extensions.json, the entry replacing the one of the same id there. A version
that is already in the catalog with another file is refused: a published file never changes (the site caches it for
good), so a change needs a new version.

  python tools\package.py [--out <folder>] [--notes-zh "..."] [--notes-en "..."] [--min-app 0.9.7] [--replace]
"""
import argparse
import datetime
import hashlib
import io
import json
import re
import sys
import zipfile
from pathlib import Path

REPO = Path(__file__).resolve().parents[1]
ADDON = REPO / "WuxianKit"
OUT = REPO / "dist"
SKIP = ("__pycache__", ".bak", ".pyc")

sys.path.insert(0, str(REPO / "tests"))


def toc_fields(path):
    out = {}
    for line in path.read_text(encoding="utf-8-sig").splitlines():
        m = re.match(r"##\s*([^:]+?)\s*:\s*(.*?)\s*$", line)
        if m:
            out[m.group(1)] = m.group(2)
    return out


def files():
    for p in sorted(ADDON.rglob("*")):
        if p.is_file() and not any(s in p.as_posix() for s in SKIP):
            yield p


TEXT = (".lua", ".toc", ".xml", ".md", ".txt", ".json")


def contents(p):
    """a file as it goes in the zip: a text file with LF line ends, whatever the checkout made of them"""
    data = p.read_bytes()
    return data.replace(b"\r\n", b"\n") if p.suffix.lower() in TEXT else data


def pack():
    """the zip's bytes: WuxianKit/... with fixed times and LF text, so the same files make the same zip on any checkout
    (the compression is the Python's zlib: check a release against the catalog, not by rebuilding it elsewhere)"""
    buf = io.BytesIO()
    with zipfile.ZipFile(buf, "w", zipfile.ZIP_DEFLATED, compresslevel=9) as z:
        for p in files():
            info = zipfile.ZipInfo("WuxianKit/" + p.relative_to(ADDON).as_posix(), date_time=(2026, 1, 1, 0, 0, 0))
            info.compress_type = zipfile.ZIP_DEFLATED
            z.writestr(info, contents(p))
    return buf.getvalue()


class Checks:
    def assertIsNone(self, value, msg=None):
        if value is not None:
            raise SystemExit(f"the addon does not load in the test client: {msg or value}")


def manifest(locale):
    from kitmock import Session, py
    s = Session(Checks(), locale=locale)
    s.login()
    s.run(1)
    return py(s.lua.eval(b"WuxianKit:Manifest()"))


def skills():
    out = []
    for p in sorted(ADDON.glob("skills/*.md")) + sorted(ADDON.glob("Extensions/*/skills/*.md")):   # the core's first
        text = p.read_text(encoding="utf-8")
        m = re.match(r"^---\r?\n(.*?)\r?\n---", text, re.S)
        meta = {}
        for line in (m.group(1).splitlines() if m else []):
            k, sep, v = line.partition(":")
            if sep:
                meta[k.strip().lower()] = v.strip()
        name = meta.get("name") or p.stem
        out.append({"name": name, "extension": "kit" if p.parent.parent == ADDON else p.parents[1].name.lower(),
                    "title": {"zh": meta.get("title-zh") or name, "en": meta.get("title") or name},
                    "description": {"zh": meta.get("description-zh") or meta.get("description", ""),
                                    "en": meta.get("description", "")}})
    return out


def entry(toc, data, name, notes, min_app):
    zh, en = manifest("zhCN"), manifest("enUS")
    titles = {e["id"]: e["title"] for e in zh["extensions"]}
    exts = []
    for e in en["extensions"]:
        if e["id"] == "kit" or not e.get("builtin"):
            continue
        exts.append({"id": e["id"], "title": {"zh": titles.get(e["id"], e["title"]), "en": e["title"]},
                     "tools": len([c for c in e.get("capabilities") or [] if c["id"] not in ("kit.manifest", "kit.revision")]),
                     "events": len(e.get("events") or [])})
    plain = lambda t: re.sub(r"\s*\(WuxianKit\)$", "", t)
    return {
        "id": toc.get("X-Wuxian-ID", "wuxiankit"), "folder": "WuxianKit", "version": toc["Version"],
        "title": {"zh": plain(toc.get("Title-zhCN", "")), "en": plain(toc.get("Title", ""))},
        "summary": {"zh": toc.get("Notes-zhCN", ""), "en": toc.get("Notes", "")},
        "file": name, "size": len(data), "sha256": hashlib.sha256(data).hexdigest(),
        "min_app": min_app, "protocol": en.get("protocol"),
        "extensions": exts, "skills": skills(),
        "notes": notes, "released": datetime.date.today().isoformat(),
        "homepage": toc.get("X-Website", "https://wuxianwow.com/workshop/extensions"),
    }


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", type=Path, default=OUT)
    ap.add_argument("--notes-zh", default="")
    ap.add_argument("--notes-en", default="")
    ap.add_argument("--min-app", default="0.9.7")
    ap.add_argument("--replace", action="store_true", help="replace the same version (only one not uploaded yet)")
    a = ap.parse_args()
    toc = toc_fields(ADDON / "WuxianKit.toc")
    data = pack()
    name = f"WuxianKit-{toc['Version']}.zip"
    a.out.mkdir(parents=True, exist_ok=True)
    catalog_path = a.out / "extensions.json"
    try:
        catalog = json.loads(catalog_path.read_text(encoding="utf-8"))
    except (OSError, ValueError):
        catalog = {"format": 1, "addons": []}
    new = entry(toc, data, name, {"zh": a.notes_zh, "en": a.notes_en}, a.min_app)
    old = next((e for e in catalog.get("addons", []) if e.get("id") == new["id"]), None)
    if old and old.get("version") == new["version"] and old.get("sha256") != new["sha256"] and not a.replace:
        raise SystemExit(f"{name} is in the catalog with other contents: give WuxianKit a new version")
    there = a.out / name
    if there.exists() and there.read_bytes() != data and not a.replace:
        raise SystemExit(f"{there} is there with other contents: give WuxianKit a new version (or --replace one never "
                         "uploaded)")
    there.write_bytes(data)
    catalog["addons"] = [e for e in catalog.get("addons", []) if e.get("id") != new["id"]] + [new]
    catalog["format"], catalog["updated"] = 1, datetime.datetime.now().astimezone().isoformat(timespec="seconds")
    catalog_path.write_text(json.dumps(catalog, ensure_ascii=False, indent=1) + "\n", encoding="utf-8")
    print(f"{name}: {len(data)} bytes, sha256 {new['sha256'][:12]}..., {len(new['extensions'])} extensions, "
          f"{len(new['skills'])} skills -> {a.out}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
