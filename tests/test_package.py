"""tools/package.py: what stays out of the zip (by the parts of a file's path inside the addon, never by where the
checkout lies), and what a catalog entry asks for: min_app (无限工坊, by default the one this WuxianKit is written
for) and, for another addon of this repo, min_kit (the oldest WuxianKit it works with)."""
import contextlib
import importlib.util
import io
import json
import sys
import tempfile
import unittest
import zipfile
from pathlib import Path
from unittest import mock

from kitmock import lupa

REPO = Path(__file__).resolve().parents[1]


def load_package():
    spec = importlib.util.spec_from_file_location("kit_package", REPO / "tools" / "package.py")
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


package = load_package()


class Skip(unittest.TestCase):
    def test_by_the_parts_of_the_path(self):
        for rel in ("__pycache__/x.lua", "Core/__pycache__/kit.cpython-312.pyc", "Core/Kit.lua.bak", "Core/Kit.pyc",
                    "Old.bak/Kit.lua", "Core/KIT.LUA.BAK"):
            self.assertTrue(package.skipped(Path(rel)), rel)
        # a part that only holds the letters is not one of them
        for rel in ("Core/Kit.lua", "Core/my.bakery.lua", "Core/x.bak.lua", "Core/pycache/x.lua",
                    "Core/__pycache__.lua", "Core/a.pyc.md", "skills/kit-app.md"):
            self.assertFalse(package.skipped(Path(rel)), rel)

    def addon(self, root):
        """a small addon in root, with what is packed and what is not"""
        addon = root / "Tiny"
        for rel, text in (("Tiny.toc", "## Version: 0.1.0\r\n"), ("Tiny.lua", "local x = 1\r\n"),
                          ("Core/my.bakery.lua", "-- kept\n"), ("Core/Old.lua.bak", "-- out\n"),
                          ("Core/__pycache__/x.pyc", "out"), ("Saved.bak/Tiny.lua", "-- out\n")):
            p = addon / rel
            p.parent.mkdir(parents=True, exist_ok=True)
            p.write_bytes(text.encode())
        return addon

    def test_where_the_checkout_lies_does_not_matter(self):
        """the same addon under a folder whose name holds .bak, .pyc and __pycache__ packs the same files (the old
        test on the whole path packed nothing there)"""
        with tempfile.TemporaryDirectory() as plain, tempfile.TemporaryDirectory(suffix=".bak") as bak:
            odd = Path(bak) / "__pycache__" / "work.pyc"
            odd.mkdir(parents=True)
            zips = []
            for root in (Path(plain), odd):
                addon = self.addon(root)
                self.assertEqual([p.relative_to(addon).as_posix() for p in package.files(addon)],
                                 ["Core/my.bakery.lua", "Tiny.lua", "Tiny.toc"])
                zips.append(package.pack(addon))
            self.assertEqual(zips[0], zips[1])                 # the same bytes, wherever it lies
            z = zipfile.ZipFile(io.BytesIO(zips[1]))
            self.assertEqual(z.namelist(), ["Tiny/Core/my.bakery.lua", "Tiny/Tiny.lua", "Tiny/Tiny.toc"])
            self.assertEqual(z.read("Tiny/Tiny.lua"), b"local x = 1\n")

    def test_the_kit_itself(self):
        rels = [p.relative_to(package.ADDON).as_posix() for p in package.files()]
        self.assertIn("WuxianKit.toc", rels)
        self.assertIn("skills/kit-app.md", rels)
        self.assertEqual([r for r in rels if "__pycache__" in r or r.endswith((".bak", ".pyc"))], [])


class Needs(unittest.TestCase):
    def test_the_workshop_this_kit_is_written_for(self):
        """the default is the workshop the skills ask for (wuxian listen came with 0.9.13), not an older one"""
        self.assertEqual(package.MIN_APP, "0.9.13")
        skill = (package.ADDON / "skills" / "kit-app.md").read_text(encoding="utf-8")
        self.assertIn("wuxian listen", skill)
        self.assertIn("--min-app " + package.MIN_APP, package.__doc__)

    def test_the_kit_another_addon_needs(self):
        guides = REPO / "WuxianKit_Guides"
        version = package.kit_version()
        self.assertRegex(version, r"^\d+\.\d+\.\d+$")
        self.assertIsNone(package.min_kit({}))                                    # WuxianKit does not need itself
        self.assertIsNone(package.min_kit({"X-Wuxian-Kit": "0.5.0"}, package.ADDON, "0.5.0"))
        self.assertEqual(package.min_kit({}, guides), version)                    # the one it was tried with
        self.assertEqual(package.min_kit({"X-Wuxian-Kit": "0.5.2"}, guides), "0.5.2")
        self.assertEqual(package.min_kit({"X-Wuxian-Kit": "0.5.2"}, guides, "0.5.9"), "0.5.9")


@unittest.skipIf(lupa is None, "lupa (Lua 5.1 for Python) is not installed")
class Catalog(unittest.TestCase):
    def run_main(self, out, *args):
        text = io.StringIO()
        with mock.patch.object(sys, "argv", ["package.py", "--out", str(out), *args]), \
                contextlib.redirect_stdout(text):
            self.assertEqual(package.main(), 0)
        catalog = json.loads((Path(out) / "extensions.json").read_text(encoding="utf-8"))
        return {e["id"]: e for e in catalog["addons"]}, text.getvalue()

    def test_the_entries(self):
        with tempfile.TemporaryDirectory() as out:
            entries, said = self.run_main(out)
            kit = entries["wuxiankit"]
            self.assertEqual(kit["min_app"], "0.9.13")                 # nothing given: not an older workshop
            self.assertNotIn("min_kit", kit)
            self.assertIn("needs 无限工坊 0.9.13 ->", said)
            self.assertTrue((Path(out) / kit["file"]).exists())

            entries, said = self.run_main(out, "--addon", "WuxianKit_Guides")
            guides = next(e for e in entries.values() if e["folder"] == "WuxianKit_Guides")
            toc = package.toc_fields(REPO / "WuxianKit_Guides" / "WuxianKit_Guides.toc")
            self.assertEqual(guides["min_kit"], toc.get("X-Wuxian-Kit") or kit["version"])
            self.assertEqual(guides["min_app"], "0.9.13")
            self.assertIn(f"needs 无限工坊 0.9.13, WuxianKit {guides['min_kit']} ->", said)
            self.assertIn("wuxiankit", entries)                        # the kit's entry stays beside it

            entries, _ = self.run_main(out, "--addon", "WuxianKit_Guides", "--min-kit", "0.7.0", "--min-app", "0.9.14")
            guides = next(e for e in entries.values() if e["folder"] == "WuxianKit_Guides")
            self.assertEqual((guides["min_kit"], guides["min_app"]), ("0.7.0", "0.9.14"))

    def test_the_kit_does_not_need_itself(self):
        with tempfile.TemporaryDirectory() as out:
            with self.assertRaises(SystemExit) as stop:
                self.run_main(out, "--min-kit", "0.6.0")
            self.assertIn("--min-kit", str(stop.exception))
            self.assertFalse((Path(out) / "extensions.json").exists())


if __name__ == "__main__":
    unittest.main()
