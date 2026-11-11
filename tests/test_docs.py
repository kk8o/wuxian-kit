"""What the kit's texts for agents and developers (the skills, every AGENT.md, ARCHITECTURE.md) must keep to: the wake
and the rules of waiting are written whole in one place (the skill kit-app) and pointed to from the others, the words
of the commands and capabilities are the present ones, and the files are LF."""
import re
import unittest
from pathlib import Path

KIT = Path(__file__).resolve().parents[1] / "WuxianKit"
WHYS = ("stopped", "player", "expired", "left", "extension", "replaced", "forgotten")
# what an older kit or workshop said, and no text may say again
GONE = (
    (r"--open\b", "wuxian listen only joins: the app is opened with kit.app.open first"),
    (r"listen[^\n]*--(replace|minutes)\b", "wuxian listen has --once, --since and --max only"),
    (r"""["']?temp["']?\s*[:=]\s*true""", "temp is the declaration of a temporary app, a table"),
    (r"`(annotate|extends)`|\b(annotate|extends)\s*[:=]", "a local extension adds to an app with the manifest's adds"),
    (r"they win on this machine", "a local section is information, not permission: the skill's own rules win"),
    (r"\bApps\.lua\b", "Core/Apps.lua is now Core/Apps/Decl.lua, Deliver.lua, Run.lua and Api.lua"),
    (r"`ignored`", "kit.app.open takes no fields of a declaration, so it lists none as ignored"),
)


def docs():
    return sorted(KIT.rglob("*.md"))


def text(*parts):
    return KIT.joinpath(*parts).read_text(encoding="utf-8")


def section(doc, heading):
    """the text under a "## heading", up to the next one of that level"""
    m = re.search(rf"^## {re.escape(heading)}\n(.*?)(?=^## |\Z)", doc, re.M | re.S)
    return m and m.group(1)


class Docs(unittest.TestCase):
    def test_they_are_there_and_lf(self):
        names = {p.relative_to(KIT).as_posix() for p in docs()}
        for name in ("AGENT.md", "ARCHITECTURE.md", "skills/kit-app.md", "skills/kit-extension.md",
                     "Extensions/Chat/AGENT.md", "Extensions/Game/AGENT.md",
                     "Extensions/Route/AGENT.md", "Extensions/Sense/AGENT.md"):
            self.assertIn(name, names)
        for p in docs():
            data = p.read_bytes()
            self.assertNotIn(b"\r", data, p.name)
            self.assertTrue(data.endswith(b"\n"), p.name)

    def test_nothing_of_the_old_words(self):
        for p in docs():
            body = p.read_text(encoding="utf-8")
            for pattern, why in GONE:
                found = re.search(pattern, body)
                self.assertIsNone(found, f"{p.relative_to(KIT).as_posix()}: {found and found.group(0)!r} ({why})")

    def test_the_wake_is_written_whole_once(self):
        skill = text("skills", "kit-app.md")
        wake = section(skill, "The wake")
        self.assertTrue(wake)
        shape = "{app, seq, reason, items, skipped, after, next, state?, pace?, quiet?, notes?}"
        self.assertIn(shape, wake)
        for field in ("app", "seq", "reason", "items", "id", "time", "source", "after", "skipped", "state", "pace",
                      "quiet", "notes"):
            self.assertRegex(wake, rf"(?m)^\s*- `{field}`", field)
        for reason in ("item", "urgent", "batch", "full", "idle", "catchup"):
            self.assertRegex(wake, rf"(?m)^\s*- `{reason}`:", reason)
        self.assertIn("never in quiet hours", wake)             # full does not wake there
        self.assertIn("`ref`", wake)                            # a source's own number is not the id
        # the others name what they use and point here; none writes the whole shape again
        for parts in (("AGENT.md",),):
            other = text(*parts)
            self.assertNotIn(shape, other, parts[-1])
            self.assertRegex(other, r"`kit-app`|\"skill\": \"kit-app\"", parts[-1])
            self.assertIn("The wake", other, parts[-1])

    def test_the_rules_of_waiting(self):
        skill = text("skills", "kit-app.md")
        waiting = section(skill, "Waiting for wakes")
        self.assertTrue(waiting)
        self.assertIn("wuxian listen <id> [--once] [--since <N>] [--max <seconds>]", waiting)
        self.assertIn("it never opens one", waiting)
        for line in ("`OPEN <status>`", "`NEXT <N>`", "`TIMEOUT`", "`END <why>`"):
            self.assertIn(line, waiting)
        self.assertIn("Start no new wait and do not stop it", waiting)
        end = waiting[waiting.index("`END <why>`"):]
        self.assertEqual(tuple(re.findall(r"`([a-z]+)`\s+\(", end)), WHYS)       # every why, each said once
        self.assertLess(waiting.index("wk_kit_app_open"), waiting.index("in the background"))   # open, then wait
        for parts in (("AGENT.md",),):
            other = text(*parts)
            self.assertRegex(other, r"wuxian listen \S+ (\[)?--once", parts[-1])
            self.assertIn("--since", other, parts[-1])
        guide = text("AGENT.md")
        self.assertIn("Waiting for wakes", guide)
        for why in WHYS:
            self.assertIn(f"`{why}`", guide, why)

    def test_the_app_capabilities(self):
        guide, arch = text("AGENT.md"), text("ARCHITECTURE.md")
        for cap in ("kit.app.declare", "kit.app.open", "kit.app.stop", "kit.app.forget", "kit.app.describe",
                    "kit.app.status", "kit.app.state", "kit.app.recent", "kit.apps"):
            self.assertIn(cap, arch, cap)
            self.assertIn("wk_" + cap.replace(".", "_"), guide, cap)
        for word in ("blocked", "waiting", "hidden", "forgotten", "temp"):
            self.assertIn(word, guide, word)
            self.assertIn(word, arch, word)
        for name in ("Decl.lua", "Deliver.lua", "Run.lua", "Api.lua"):
            self.assertIn(name, arch)
            self.assertTrue((KIT / "Core" / "Apps" / name).exists(), name)

    def test_the_words_with_two_meanings(self):
        arch = text("ARCHITECTURE.md")
        m = re.search(r"^### 词汇表[^\n]*\n(.*?)(?=^#{2,3} )", arch, re.M | re.S)
        self.assertTrue(m)
        rows = [r for r in m.group(1).splitlines() if r.startswith("|")][2:]
        words, last = {}, None
        for r in rows:
            cells = [c.strip() for c in r.strip("|").split("|")]
            last = cells[0].strip("`") or last
            words[last] = words.get(last, 0) + 1
        for word in ("notes", "see", "say", "source", "state", "options", "local"):
            self.assertIn(word, words)
        for word in ("notes", "see", "say", "source", "state", "options"):
            self.assertGreaterEqual(words[word], 2, word)       # a word is here because it means two things


if __name__ == "__main__":
    unittest.main()
