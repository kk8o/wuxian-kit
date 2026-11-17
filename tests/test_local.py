"""The two halves of an extension (0.7): what a game extension knows of its part on this computer, and how the window
finds and shows it. ext:Local() ({known, listed, on, running, version, options}) from 无限工坊's list (kit.local.set,
with running and addons), by the one rule (ns.LocalOf: the same id, or its addon among those the local extension
brings), and the bus event kit.local {extension} when that answer changed; the addon an extension is in, read off the
call stack when it does not say; an option kept by the extension itself (get, set); WuxianKit:Window(id) for a local
extension's row and for one row of both halves, also when the row comes a moment later; an app of a local extension
无限工坊 has not listed (yet) on the game extension of that id; and the list: the name before the marks, no row cut at
the edge, the chosen row in sight, a fill that lets nothing through."""
import unittest

from kitmock import click, lupa, py, texts
from test_app_panel import labels, marks, rows, shown
from test_app_reconcile import Case
from test_apps_driver import DRIVEN

NONE = {"known": False, "listed": False, "on": False, "running": False, "options": {}}


class Base(Case):
    def set(self, s, *entries):
        return self.call(s, "kit.local.set", "{ extensions = { " + ", ".join(entries) + " } }")

    def ext(self, s, ext, info="{}"):
        s.lua.execute(f"__ext = WuxianKit:Extension({ext!r}, {info})".encode())
        s.run(0.5)

    def local(self, s, ext):
        return self.lua(s, f"WuxianKit:Extension({ext!r}):Local()")

    def told(self, s):
        return [e["extension"] for e in self.events(s, "kit.local")]

    def window(self, s, page=None):
        s.lua.execute(f"__found = WuxianKit:Window({'nil' if page is None else repr(page)})".encode())
        return s.g("WuxianKitWindow")


@unittest.skipIf(lupa is None, "lupa (Lua 5.1 for Python) is not installed")
class Local(Base):
    def test_what_an_extension_knows_of_its_local_part(self):
        s = self.start()
        self.ext(s, "cocreate")
        self.ext(s, "voice")
        self.ext(s, "lone")
        self.assertEqual(self.local(s, "cocreate"), NONE)                 # no list yet: nothing is known
        self.assertEqual(self.local(s, "lone"), NONE)
        self.assertEqual(self.told(s), [])
        self.set(s, "{ id = 'cocreate', title = 'Co-create', version = '1.2.0', on = true, running = true, options = { "
                    "{ name = 'auto', kind = 'boolean', value = true }, { name = 'folder', kind = 'text', value = 'C:/d' } } }",
                 "{ id = 'voice', title = 'Voice', on = false }")
        self.assertEqual(self.local(s, "cocreate"), {"known": True, "listed": True, "on": True, "running": True,
                                                     "version": "1.2.0", "options": {"auto": True, "folder": "C:/d"}})
        self.assertEqual(self.local(s, "voice"), {"known": True, "listed": True, "on": False, "running": False,
                                                  "options": {}})
        self.assertEqual(self.local(s, "lone"), {"known": True, "listed": False, "on": False, "running": False,
                                                 "options": {}})
        # told: the ones that asked (lone too: it now knows it has none) and the ones listed; no other
        self.assertEqual(sorted(self.told(s)), ["cocreate", "lone", "voice"])
        s2 = self.start(s.reload())                                       # a reload: nothing known until the list again
        self.ext(s2, "cocreate")
        self.assertEqual(self.local(s2, "cocreate"), NONE)

    def test_the_event_when_the_answer_changed(self):
        s = self.start()
        self.ext(s, "cocreate")
        self.ext(s, "voice")
        entry = lambda more: "{ id = 'cocreate', title = 'Co-create', " + more + " }"
        option = lambda v: f"options = {{ {{ name = 'auto', kind = 'boolean', value = {v} }} }}"
        steps = (("on = true", ["cocreate"]),                             # listed (and nothing known before)
                 ("on = true", []),                                       # the same list again
                 ("on = true, running = true", ["cocreate"]),             # its program started
                 ("on = true, running = true, version = '2'", ["cocreate"]),
                 ("on = true, running = true, version = '2', " + option("true"), ["cocreate"]),
                 ("on = true, running = true, version = '2', " + option("false"), ["cocreate"]),
                 ("on = true, running = true, version = '2', title = 'Renamed', " + option("false"), []),
                 ("on = false, running = false, version = '2', " + option("false"), ["cocreate"]))
        for more, want in steps:
            s.lua.execute(b"__events = {}")
            self.set(s, entry(more))
            self.assertEqual(self.told(s), want, more)
        s.lua.execute(b"__events = {}")
        self.set(s)                                                       # gone from the list
        self.assertEqual(self.told(s), ["cocreate"])
        self.assertEqual(self.local(s, "cocreate")["listed"], False)
        s.lua.execute(b"__events = {} __heard = {} "
                      b"WuxianKit:On('kit.local', function(_, d) __heard[#__heard + 1] = d.extension end)")
        self.set(s, "{ id = 'voice', title = 'Voice', running = true }")
        self.assertEqual(py(s.g("__heard")), ["voice"])                   # WuxianKit:On hears it

    def test_the_one_rule_the_same_id_or_its_addon(self):
        """a game extension of another id is the local extension's half when its addon is among those the local one
        brings (folders compare without case); the same id comes first"""
        s = self.start()
        self.ext(s, "ccgame", "{ addon = 'WuxianCoCreate' }")
        self.ext(s, "cocreate", "{ addon = 'Another' }")
        self.ext(s, "third", "{ addon = 'Third' }")
        self.set(s, "{ id = 'data', title = 'Data', running = true, addons = { 'wuxiancocreate', 'Another' } }",
                 "{ id = 'cocreate', title = 'Co-create', version = '9' }")
        self.assertEqual((self.local(s, "ccgame")["listed"], self.local(s, "ccgame")["running"]), (True, True))
        self.assertEqual(self.local(s, "cocreate")["version"], "9")       # its own id, not the one that brings its addon
        self.assertEqual(self.local(s, "third")["listed"], False)
        self.assertEqual(self.lua(s, "__ns.LocalOf('ccgame', 'WUXIANCOCREATE').id"), "data")
        self.assertIsNone(s.lua.eval(b"__ns.LocalOf('nope', nil)"))
        self.assertIsNone(s.lua.eval(b"__ns.LocalOf('nope', '')"))

    def test_the_addon_an_extension_is_in(self):
        """info.addon says it; else the call stack does (the first frame that is not WuxianKit's own); else none"""
        s = self.start()
        s.lua.execute(b"WuxianKit:Extension('plain', {})")
        self.assertIsNone(s.lua.eval(b"__ns.extensions.plain.addon"))     # (this client: no debugstack)
        s.lua.execute(b"""
			function debugstack() return __stack end
			__stack = "[Interface/AddOns/WuxianKit/Core/Kit.lua]:1: in function 'Safe'\\n"
				.. "[Interface/AddOns/WuxianCoCreate/Core.lua]:12: in main chunk\\n"
			WuxianKit:Extension('seen', {})
			WuxianKit:Extension('said', { addon = 'Named' })
			__stack = "Interface\\\\AddOns\\\\OldStyle\\\\Main.lua:3: in main chunk"
			WuxianKit:Extension('old', {})
			__stack = "[string \\"*:OnLoad\\"]:1: in function <[string \\"*:OnLoad\\"]:1>"
			WuxianKit:Extension('typed', {})
		""")
        got = self.lua(s, "{ __ns.extensions.seen.addon, __ns.extensions.said.addon, __ns.extensions.old.addon, "
                          "__ns.extensions.typed.addon or false }")
        self.assertEqual(got, ["WuxianCoCreate", "Named", "OldStyle", False])
        s.run(0.5)
        self.set(s, "{ id = 'data', title = 'Data', addons = { 'WuxianCoCreate' } }")
        self.assertTrue(self.local(s, "seen")["listed"])                  # so the list ties it without the addon saying


@unittest.skipIf(lupa is None, "lupa (Lua 5.1 for Python) is not installed")
class OptionOfItsOwn(Base):
    def test_get_and_set(self):
        """an option with get and set: its value is the extension's own (the addon's saved variables), read and
        written through them; the core keeps none; changed and kit.option as for any option"""
        s = self.start()
        s.lua.execute(b"""
			__show, __changed = nil, {}
			__ext = WuxianKit:Extension('cocreate', { title = 'Co-create' })
			__ext:Option('show', { title = 'Show my name', default = true,
				get = function() return __show end, set = function(v) __show = v end,
				changed = function(self, v) __changed[#__changed + 1] = v end })
			__ext:Option('rate', { kind = 'number', min = 1, max = 9, default = 3,
				get = function() return __rate end, set = function(v) __rate = v end })
		""")
        s.run(0.5)
        get = lambda name: s.lua.eval(f"__ext:Get({name!r})".encode())
        self.assertEqual((get("show"), get("rate")), (True, 3))           # none kept yet: the default
        s.lua.execute(b"__show, __rate = false, 20")
        self.assertEqual((get("show"), get("rate")), (False, 9))          # the extension's value, as its kind keeps it
        self.assertEqual(self.call(s, "kit.options", "{ extension = 'cocreate' }")["show"]["value"], False)
        s.lua.execute(b"WuxianKit:Window('cocreate')")
        w = s.g("WuxianKitWindow")
        check = next(c for c in shown(w[b"checks"]) if c[b"label"][b"text"] == b"Show my name")
        self.assertFalse(check[b"checked"])
        click(check)
        self.assertEqual((s.g("__show"), py(s.g("__changed"))), (True, [True]))
        self.assertEqual(self.events(s, "kit.option")[-1], {"extension": "cocreate", "name": "show", "value": True})
        self.assertEqual(self.lua(s, "{ __ns.SetOption(__ext, 'rate', 4.4) }"), [True, 4])
        self.assertEqual(s.g("__rate"), 4)
        self.assertIsNone(self.lua(s, "(WuxianKitDB.ext.cocreate or {}).options"))   # nothing of them in the core's storage
        told = len(self.events(s, "kit.option"))
        self.assertEqual(self.lua(s, "{ __ns.SetOption(__ext, 'rate', 4) }"), [True, 4])   # the same: nothing told
        self.assertEqual(len(self.events(s, "kit.option")), told)
        for spec in ("{ get = function() end }", "{ set = function() end }", "{ get = 1, set = 2 }"):
            ok, err = s.lua.eval(f"pcall(__ext.Option, __ext, 'bad', {spec})".encode())
            self.assertFalse(ok, spec)
            self.assertIn("get and set are functions, given together", err.decode())


@unittest.skipIf(lupa is None, "lupa (Lua 5.1 for Python) is not installed")
class Window(Base):
    def start(self, s=None, **kw):
        s = super().start(s, **kw)
        s.lua.execute(b"function WuxianKit:AgentOnline() return true end")
        return s

    def page(self, w):
        return texts(w[b"body"])[0]

    def test_a_local_extensions_row_by_its_id(self):
        """WuxianKit:Window("voice"): the row of the local extension voice (as "local:voice"); true when it went
        there, false when there is no such page (the page it showed stays)"""
        s = self.start()
        self.set(s, "{ id = 'voice', title = 'Voice pal', running = true }", "{ id = 'facts', title = 'Facts' }")
        w = self.window(s, "kit")
        self.assertEqual((self.page(w), s.g("__found")), ("Framework", True))
        for page in ("voice", "local:voice"):
            self.window(s, "kit")
            w = self.window(s, page)
            self.assertEqual((self.page(w), s.g("__found")), ("Voice pal", True), page)
        w = self.window(s, "nothing")
        self.assertEqual((self.page(w), s.g("__found")), ("Voice pal", False))
        w = self.window(s)                                                # no page asked: the one it showed
        self.assertEqual((self.page(w), s.g("__found")), ("Voice pal", True))
        self.agent(s, "kit.app.declare", DRIVEN.replace("cocreate", "orphan"))   # one known by its app's label alone
        w = self.window(s, "orphan")
        self.assertEqual((self.page(w), texts(w[b"body"])[1], s.g("__found")),
                         ("Co-create", "Wuxian Workshop does not list this extension", True))

    def test_a_page_whose_row_comes_a_moment_later(self):
        """asked for before 无限工坊 gave its list (a reload, then the addon's slash command): the window opens where
        it was and goes there when the row comes; not minutes later, and not once the player chose a page"""
        s = self.start()
        w = self.window(s, "voice")
        self.assertEqual((self.page(w), s.g("__found")), ("Framework", False))
        s.run(3)
        self.set(s, "{ id = 'voice', title = 'Voice pal' }")
        s.run(0.1)
        self.assertEqual(self.page(w), "Voice pal")
        self.set(s)
        s.run(0.1)
        self.window(s, "kit")
        self.window(s, "voice")
        s.run(20)                                                         # too late: the player has moved on
        self.set(s, "{ id = 'voice', title = 'Voice pal' }")
        s.run(0.1)
        self.assertEqual(self.page(w), "Framework")
        self.set(s)
        self.window(s, "voice")
        click(next(b for b in shown(w[b"items"]) if b[b"label"][b"text"] == b"Chat"))   # the player's own choice
        self.set(s, "{ id = 'voice', title = 'Voice pal' }")
        s.run(0.1)
        self.assertEqual(self.page(w), "Chat")

    def test_an_app_before_the_list_is_on_the_game_extension_of_that_id(self):
        """无限工坊's list not there yet (or without it): a local extension's app is on the row of the game extension
        of that id, not on a row of its own; with the list and no such entry its card has the remove"""
        s = self.start()
        self.ext(s, "cocreate", "{ title = 'Co-create game' }")
        self.agent(s, "kit.app.declare", DRIVEN)
        w = self.window(s, "cc")
        self.assertEqual(rows(w).count("Co-create game"), 1)
        self.assertNotIn("Co-create", rows(w))                            # no second row from the app's label
        body = texts(w[b"body"])
        self.assertEqual(body[0], "Co-create game")
        self.assertIn("App · Data", body)
        self.assertNotIn("Wuxian Workshop does not list this extension", body)
        self.assertEqual(marks(next(b for b in shown(w[b"items"]) if b[b"label"][b"text"] == b"Co-create game")), "game")
        self.assertNotIn("Remove", labels(w))                             # the list may still come
        self.set(s, "{ id = 'other', title = 'Other' }")                  # it came, without it
        s.run(0.1)
        self.assertIn("Remove", labels(w))
        self.set(s, "{ id = 'cocreate', title = 'Co-create', version = '1.2.0', running = true }")
        s.run(0.1)
        self.assertNotIn("Remove", labels(w))
        self.assertEqual(texts(w[b"body"])[:2], ["Co-create game", "Game Enabled · Local part 1.2.0 Running"])

    def test_no_row_is_cut_at_the_edge(self):
        """a list longer than its place: every row that shows shows whole, a line under the list says how many are
        below, the wheel brings them, and at the end the line is gone; a list that fits has neither"""
        s = self.start()
        w = self.window(s, "kit")
        side, foot = w[b"side"], w[b"foot"]
        self.assertFalse(foot[b"shown"])
        self.assertEqual(len(shown(w[b"items"])), len(rows(w)))
        full = side[b"h"]
        self.set(s, *[f"{{ id = 'x{i}', title = 'X{i}' }}" for i in range(1, 13)])
        s.run(0.1)
        self.assertLess(side[b"h"], full)                                 # room under it for its line

        def whole():
            top, view = side[b"scrollTop"] or 0, side[b"h"]
            for b in shown(w[b"items"]):
                self.assertGreaterEqual(b[b"top"], top)
                self.assertLessEqual(b[b"top"] + 22, top + view)
            return len(shown(w[b"items"]))
        below = len(rows(w)) - whole()
        self.assertGreater(below, 0)
        self.assertEqual((foot[b"shown"], foot[b"text"].decode()), (True, f"{below} more"))
        s.ns.SetLanguage(b"zhCN")
        self.assertEqual(foot[b"text"].decode(), f"另有 {below} 项")
        wheel = side[b"scripts"][b"OnMouseWheel"]
        wheel(side, -1)
        self.assertGreater(side[b"scrollTop"], 0)
        whole()
        for _ in range(40):
            wheel(side, -1)
        whole()
        self.assertFalse(foot[b"shown"])                                  # at the end: nothing below
        last = w[b"items"][int(w[b"nItems"])]
        self.assertTrue(last[b"shown"])
        self.assertEqual(last[b"top"] + 22, side[b"scrollTop"] + side[b"h"] - 2)   # (the list's own gap under its last row)

    def test_the_chosen_row_comes_into_sight(self):
        s = self.start()
        self.set(s, *[f"{{ id = 'x{i}', title = 'X{i}' }}" for i in range(1, 21)])
        w = self.window(s, "kit")
        side = w[b"side"]
        self.assertEqual(side[b"scrollTop"] or 0, 0)
        self.assertNotIn("X20", [b[b"label"][b"text"].decode() for b in shown(w[b"items"])])
        w = self.window(s, "x20")                                         # an addon's button: its row is far down
        self.assertEqual(self.page(w), "X20")
        self.assertIn("X20", [b[b"label"][b"text"].decode() for b in shown(w[b"items"])])
        w = self.window(s, "kit")
        self.assertEqual(side[b"scrollTop"], 0)
        self.assertIn("Framework", [b[b"label"][b"text"].decode() for b in shown(w[b"items"])])

    def test_the_name_comes_first(self):
        """a row of 已添加 gives its marks a fixed small place whatever they are: the name has the rest"""
        s = self.start()
        self.ext(s, "cocreate", "{ title = 'Co-create game' }")
        self.set(s, "{ id = 'cocreate', title = 'Co-create', where = 'both' }", "{ id = 'voice', title = 'Voice pal' }")
        w = self.window(s, "kit")
        item = lambda title: next(b for b in shown(w[b"items"]) if b[b"label"][b"text"].decode() == title)
        both, local, core = item("Co-create game"), item("Voice pal"), item("Framework")
        self.assertEqual((marks(both), marks(local), marks(core)), ("game local", "local", ""))
        self.assertEqual(both[b"label"][b"w"], local[b"label"][b"w"])
        self.assertGreaterEqual(both[b"label"][b"w"], 140)                # of a row 192 wide
        self.assertGreater(core[b"label"][b"w"], both[b"label"][b"w"])
        self.assertFalse(both[b"state"][b"shown"])

    def test_nothing_shows_through(self):
        """the window's fill is solid (the chat frame behind it does not show through its pages), and the list and
        the page have a fill of their own"""
        s = self.start()
        w = self.window(s, "kit")
        fills = [r for r in w[b"__regions"].values() if r[b"kind"] == b"Texture" and r[b"rgb"]]
        self.assertEqual(py(fills[0][b"rgb"])[3], 1)
        for part in (w[b"side"], w[b"scroll"]):
            own = [r for r in part[b"__regions"].values() if r[b"kind"] == b"Texture" and r[b"rgb"]]
            self.assertEqual(py(own[0][b"rgb"])[3], 1)
        s.lua.execute(b"WuxianKit:Copy('text')")                          # (the small panels stay as they were)
        box = s.g("WuxianKitCopyWindow")
        fills = [r for r in box[b"__regions"].values() if r[b"kind"] == b"Texture" and r[b"rgb"]]
        self.assertLess(py(fills[0][b"rgb"])[3], 1)


if __name__ == "__main__":
    unittest.main()
