"""Apps, reports (0.7, Core/Apps/Report.lua; ARCHITECTURE section 10): what the program that drives an app tells the
game. kit.app.report (only for an app with driver local; checked) keeps the last report of each of the app's last 8
keys for this character, oldest first by the time it was given; the app's card shows the newest one's text in the
colour of its state; ext:OnReport gives each to the game half of the app's local extension (the same id, or its addon
among those 无限工坊's list says the local extension brings) as it comes, and those kept once when it is known to be
that half and is on."""
import unittest

from kitmock import lupa, py, texts
from test_app_reconcile import Case, ME
from test_apps_driver import DRIVEN, LOCAL

AGENT = f"{{ app = 'ag', title = 'Agent', {LOCAL}, prompt = 'ag' }}"
HEARS = b"""
__heard = {}
function __hears(ext, app)
	ext:OnReport(app, function(r, replay)
		__heard[#__heard + 1] = { ext = ext.id, key = r.key, state = r.state, text = r.text, at = r.at, late = r.late,
			replay = replay }
		r.key = 'changed'                               -- (a copy: what is kept stays)
	end)
end
"""


class Base(Case):
    def start(self, s=None, **kw):
        s = super().start(s, **kw)
        s.lua.execute(HEARS)
        return s

    def report(self, s, key, state="run", more="", app="cc"):
        return self.agent(s, "kit.app.report", f"{{ app = {app!r}, key = {key!r}, state = {state!r}, {more} }}")

    def kept(self, s, app="cc"):
        return self.lua(s, f"WuxianKitDB.apps.{app}.chars[{ME!r}].reports") or []

    def heard(self, s):
        return py(s.g("__heard")) or []

    def game_half(self, s, ext="cocreate", info="{ title = 'Co-create' }"):
        """the addon of the extension's game half loads (on a moment later)"""
        s.lua.execute(f"__ext = WuxianKit:Extension({ext!r}, {info})".encode())
        s.run(0.5)


@unittest.skipIf(lupa is None, "lupa (Lua 5.1 for Python) is not installed")
class Kept(Base):
    def test_kept_by_key(self):
        s = self.start()
        self.agent(s, "kit.app.declare", DRIVEN)
        now = int(s.lua.eval(b"time()"))
        got = self.report(s, "1794938824:Horde", "run", "step = 'fetch', text = 'Fetching', done = 1, total = 3, "
                                                        f"data = {{ n = 5 }}, at = {now - 20}")
        self.assertEqual(got, {"kept": True})
        self.assertEqual(self.kept(s), [{"key": "1794938824:Horde", "state": "run", "step": "fetch", "text": "Fetching",
                                         "done": 1, "total": 3, "data": {"n": 5}, "at": now - 20}])
        self.assertEqual(py(s.ns.AppReport(b"cc")), self.kept(s)[0])
        self.report(s, "1794938824:Horde", "retry", f"text = 'Later', retry = {now + 300}, at = {now - 10}")
        self.assertEqual(self.kept(s), [{"key": "1794938824:Horde", "state": "retry", "text": "Later",
                                         "retry": now + 300, "at": now - 10}])       # a key once: the new one whole
        self.report(s, "b", "done", "text = 'B'")                         # no at: now
        self.report(s, "a", "failed", f"text = 'A', at = {now - 60}, late = true")   # handed on late: by its time
        self.assertEqual([(r["key"], r["at"], r.get("late")) for r in self.kept(s)],
                         [("a", now - 60, True), ("1794938824:Horde", now - 10, None), ("b", now, None)])
        self.assertEqual(py(s.ns.AppReport(b"cc"))["key"], "b")           # the newest
        for i in range(10):
            self.report(s, f"k{i}", "run", f"at = {now + 1 + i}")
        self.assertEqual([r["key"] for r in self.kept(s)], [f"k{i}" for i in range(2, 10)])   # the last 8 keys
        self.report(s, "old", "run", f"at = {now - 500}, late = true")    # older than all it keeps: not kept
        self.assertEqual([r["key"] for r in self.kept(s)], [f"k{i}" for i in range(2, 10)])
        s2 = self.start(s.reload())                                       # a character's, through a reload
        self.assertEqual([r["key"] for r in self.kept(s2)], [f"k{i}" for i in range(2, 10)])
        self.assertEqual(py(s2.ns.AppReport(b"cc"))["key"], "k9")
        s3 = self.start(s2.reload(), guid="Player-1-00000002")            # another character has none
        self.assertIsNone(s3.ns.AppReport(b"cc"))
        self.report(s3, "mine")
        self.assertEqual(py(s3.ns.AppReport(b"cc"))["key"], "mine")
        self.assertEqual(len(self.kept(s3)), 8)                           # (the first character's are as they were)

    def test_refused(self):
        s = self.start()
        self.agent(s, "kit.app.declare", DRIVEN)
        self.agent(s, "kit.app.declare", AGENT)
        self.assertIn("app ag is not driven by a local extension's program", self.fails(s, "kit.app.report",
                      "{ app = 'ag', key = 'k', state = 'run' }"))
        self.assertIn("no app nope", self.fails(s, "kit.app.report", "{ app = 'nope', key = 'k', state = 'run' }"))
        for args, why in (("key = '', state = 'run'", "key is a text of 1 to 64 bytes"),
                          (f"key = '{'k' * 65}', state = 'run'", "key is a text of 1 to 64 bytes"),
                          ("key = 'k', state = 'ok'", "state is run, done, failed or retry"),
                          ("key = 'k', state = 'run', step = 'Fetch It'", "step is lowercase letters"),
                          (f"key = 'k', state = 'run', step = '{'s' * 25}'", "step is lowercase letters"),
                          (f"key = 'k', state = 'run', text = '{'t' * 201}'", "text is one line of at most 200 bytes"),
                          ("key = 'k', state = 'run', done = -1", "done is a number, not negative"),
                          (f"key = 'k', state = 'run', data = {{ big = '{'d' * 300}', b2 = '{'d' * 400}', "
                           f"b3 = '{'d' * 400}', b4 = '{'d' * 400}', b5 = '{'d' * 400}', b6 = '{'d' * 400}', "
                           f"b7 = '{'d' * 400}', b8 = '{'d' * 400}', b9 = '{'d' * 400}', b10 = '{'d' * 400}', "
                           f"b11 = '{'d' * 400}' }}", "data is a small table"),
                          ("state = 'run'", "key"), ("key = 'k'", "state"), ("key = 'k', state = 'run', nope = 1", "nope"),
                          ("key = 'k', state = 'run', at = 'now'", "at")):
            self.assertIn(why, self.fails(s, "kit.app.report", f"{{ app = 'cc', {args} }}"), args)
        self.assertEqual(self.kept(s), [])
        self.assertIsNone(s.ns.AppReport(b"cc"))
        self.report(s, "k", "run", "text = 'two\\nlines', step = 'a_1'")   # a line break: a space
        self.assertEqual(py(s.ns.AppReport(b"cc"))["text"], "two lines")
        self.agent(s, "kit.app.declare", DRIVEN.replace("driver = 'local',", ""))   # no longer driven: none shown
        self.assertIsNone(s.ns.AppReport(b"cc"))

    def test_the_card_shows_the_newest(self):
        """under the state line, the newest report's text in the colour of its state (failed red, retry amber, done
        gold, run as any text), escaped; none, or one without a text: no line"""
        s = self.start()
        s.lua.execute(b"function WuxianKit:AgentOnline() return true end")
        self.agent(s, "kit.app.declare", DRIVEN)
        s.lua.execute(b"__host = CreateFrame('Frame', nil, UIParent) __p = WuxianKit:AppPanel('cc', __host, 320)")
        p = s.g("__p")
        self.assertEqual(texts(p), ["Local part not running"])
        now = int(s.lua.eval(b"time()"))
        for i, (state, ink) in enumerate((("run", "fg"), ("done", "gold"), ("failed", "bad"), ("retry", "amber"))):
            self.report(s, "k", state, f"text = 'Step |cffff0000{state}|r', at = {now + i}")
            s.run(0.1)                                                    # the card: drawn again by itself
            self.assertEqual(texts(p), ["Local part not running", f"Step ||cffff0000{state}||r"])
            line = [r for r in p[b"__regions"].values() if r[b"shown"] and r[b"text"]][1]
            want = py(s.lua.eval(f"WuxianKit.Skin.C.{ink}".encode()))
            self.assertEqual([round(x, 3) for x in py(line[b"color"])], [round(x, 3) for x in want], state)
        self.report(s, "older", "failed", f"text = 'Older', at = {now - 5}, late = true")
        s.run(0.1)
        self.assertEqual(texts(p)[1], "Step ||cffff0000retry||r")         # the newest by its time, not the last given
        self.agent(s, "kit.app.open", "{ app = 'cc' }")
        s.run(0.1)
        self.assertEqual(texts(p), ["Local part running", "Step ||cffff0000retry||r"])
        self.report(s, "z", "run", f"at = {now + 10}")                    # the newest has no text: no line
        s.run(0.1)
        self.assertEqual(texts(p), ["Local part running"])


@unittest.skipIf(lupa is None, "lupa (Lua 5.1 for Python) is not installed")
class OnReport(Base):
    def test_each_as_it_comes_and_those_kept_once(self):
        s = self.start()
        self.agent(s, "kit.app.declare", DRIVEN)
        now = int(s.lua.eval(b"time()"))
        self.report(s, "b", "done", f"text = 'B', at = {now - 5}")
        self.report(s, "a", "run", f"text = 'A', at = {now - 9}, late = true")
        self.game_half(s)
        s.lua.execute(b"__hears(__ext, 'cc')")                            # registered: those kept, oldest first
        self.assertEqual(self.heard(s), [
            {"ext": "cocreate", "key": "a", "state": "run", "text": "A", "at": now - 9, "late": True, "replay": True},
            {"ext": "cocreate", "key": "b", "state": "done", "text": "B", "at": now - 5, "replay": True}])
        self.report(s, "b", "failed", f"text = 'B2', at = {now}")
        self.assertEqual(self.heard(s)[2:], [{"ext": "cocreate", "key": "b", "state": "failed", "text": "B2",
                                              "at": now, "replay": False}])
        self.assertEqual([r["key"] for r in self.kept(s)], ["a", "b"])    # what it was handed was a copy
        s.lua.execute(b"__ext:OnReport('cc', nil)")                       # no longer
        self.report(s, "c")
        self.assertEqual(len(self.heard(s)), 3)
        ok, err = s.lua.eval(b"pcall(__ext.OnReport, __ext, 'cc', 'fn')")
        self.assertFalse(ok)
        self.assertIn("ext:OnReport(app, fn)", err.decode())

    def test_registered_as_the_addon_loads(self):
        """the usual order: the addon's file registers before the login, its extension goes on a frame later; those
        kept come once all of that is there, once"""
        s = self.start()
        self.agent(s, "kit.app.declare", DRIVEN)
        self.report(s, "a", "done", "text = 'A'")
        s2 = s.reload()
        s2.lua.execute(HEARS)
        s2.lua.execute(b"__ext = WuxianKit:Extension('cocreate', { title = 'Co-create' }) __hears(__ext, 'cc')")
        self.assertEqual(self.heard(s2), [])                              # not on yet, nobody in the world
        Case.start(self, s2)                                              # (the login; HEARS is there already)
        self.assertEqual([(h["key"], h["replay"]) for h in self.heard(s2)], [("a", True)])
        s2.run(5)
        self.call(s2, "kit.local.set", "{ extensions = { { id = 'cocreate', title = 'Co-create', running = true } } }")
        self.assertEqual(len(self.heard(s2)), 1)                          # once
        self.report(s2, "b")
        self.assertEqual([(h["key"], h["replay"]) for h in self.heard(s2)], [("a", True), ("b", False)])

    def test_off_hears_nothing_and_on_again_has_them(self):
        s = self.start()
        self.agent(s, "kit.app.declare", DRIVEN)
        self.game_half(s)
        s.lua.execute(b"__hears(__ext, 'cc')")
        self.report(s, "a")
        s.ns.Switch(b"cocreate", False)
        self.report(s, "b")
        self.assertEqual([h["key"] for h in self.heard(s)], ["a"])
        s.ns.Switch(b"cocreate", True)
        self.assertEqual([(h["key"], h["replay"]) for h in self.heard(s)], [("a", False), ("a", True), ("b", True)])

    def test_only_the_game_half_of_its_local_extension(self):
        """the extension of the local extension's id; or one whose addon 无限工坊's list says that local extension
        brings (known once the list is there); another's is an error when that is known, and hears nothing before"""
        s = self.start()
        self.agent(s, "kit.app.declare", DRIVEN)
        self.agent(s, "kit.app.declare", AGENT)
        self.report(s, "a")
        self.game_half(s, "ccgame", "{ title = 'Game half', addon = 'WuxianCoCreate' }")
        s.lua.execute(b"__mine = __ext")
        self.game_half(s, "other", "{ title = 'Other', addon = 'OtherAddon' }")
        s.lua.execute(b"__hears(__mine, 'cc') __hears(__ext, 'cc')")      # no list yet: nobody knows, nothing heard
        self.report(s, "b")
        self.assertEqual(self.heard(s), [])
        self.call(s, "kit.local.set", "{ extensions = { { id = 'cocreate', title = 'Co-create', running = true, "
                                      "addons = { 'wuxiancocreate' } } } }")
        self.assertEqual([(h["ext"], h["key"], h["replay"]) for h in self.heard(s)],
                         [("ccgame", "a", True), ("ccgame", "b", True)])  # the list says whose it is
        self.report(s, "c")
        self.assertEqual([(h["ext"], h["key"], h["replay"]) for h in self.heard(s)][2:], [("ccgame", "c", False)])
        ok, err = s.lua.eval(b"pcall(__ext.OnReport, __ext, 'cc', function() end)")   # known now: an error
        self.assertFalse(ok)
        self.assertIn("the app comes with the local extension cocreate, which is not extension other's", err.decode())
        ok, err = s.lua.eval(b"pcall(__mine.OnReport, __mine, 'ag', function() end)")
        self.assertFalse(ok)
        self.assertIn("no local extension's program drives the app", err.decode())
        self.report(s, "d")
        self.assertEqual([h["ext"] for h in self.heard(s)][3:], ["ccgame"])   # the refused one is not registered

    def test_an_app_declared_later(self):
        """registered before 无限工坊 declared the app (the first session): heard once it is, and its reports come"""
        s = self.start()
        self.game_half(s)
        s.lua.execute(b"__hears(__ext, 'cc')")
        self.agent(s, "kit.app.declare", DRIVEN)
        self.report(s, "a")
        self.assertEqual([(h["key"], h["replay"]) for h in self.heard(s)], [("a", False)])


if __name__ == "__main__":
    unittest.main()
