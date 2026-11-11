"""The window's rows beyond the game's own extensions (Core/UI/Window.lua, kit.local.set in Core/Builtins.lua): the
extensions on this computer as 无限工坊 names them (a row each in 已添加, where it runs after its name, its page with
what 无限工坊 said of it and no switch: 无限工坊's App turns it on and off), one that is in the game too marked on its
row there, the apps a local extension adds to named on both pages; and an app on the page of the extension it came with
(tests/fixtures/MyGuildTools, the real runtime), the row marked while it runs."""
import unittest

from kitmock import Session, click, lupa, py, texts
from test_app_panel import labels, shown, start


class Rows(unittest.TestCase):
    def call(self, s, cap, args="{}"):
        s.lua.execute(f"__answer = WuxianKit:Call({cap!r}, {args})".encode())
        return py(s.g("__answer"))

    def window(self, s, page="kit"):
        s.lua.execute(f"WuxianKit:Window({page!r})".encode())
        return s.g("WuxianKitWindow")

    def item(self, w, title):
        return next(b for b in shown(w[b"items"]) if b[b"label"][b"text"].decode() == title)

    def titles(self, w):
        return [b[b"label"][b"text"].decode() for b in shown(w[b"items"])]

    def tags(self, w, *titles):
        return [self.item(w, t)[b"state"][b"text"].decode() for t in titles]

    def pills(self, w):
        return [p[b"text"][b"text"].decode() for p in (w[b"pill"], w[b"where"]) if p[b"shown"]]

    def ink(self, s, fs, name):
        want = py(s.lua.eval(f"WuxianKit.Skin.C.{name}".encode()))
        self.assertEqual([round(x, 3) for x in py(fs[b"color"])], [round(x, 3) for x in want])

    def switches(self, w):
        return [c[b"label"][b"text"].decode() for c in shown(w[b"checks"])]


@unittest.skipIf(lupa is None, "lupa (Lua 5.1 for Python) is not installed")
class LocalRows(Rows):
    def test_the_local_extensions(self):
        """无限工坊's list: a row each after the game's, where it runs after its name, one that is off dimmed; its
        page: version, state, author, notes, that 无限工坊's App manages it, the apps it adds to; no switch, no
        button. The app's page names the ones that add to it while they are on. A new list takes the place of the
        old; an empty one takes the rows away"""
        s = start(self)
        s.lua.execute(b"__add('voice', { addon = 'WxVoice', decl = { title = 'Voice' }, "
                      b"status = { app = 'voice', on = true, said = 0 } })")
        w = self.window(s)
        self.assertEqual(texts(w[b"list"]), ["Built-in", "Added"])
        answer = self.call(s, "kit.local.set", """{ extensions = {
			{ id = 'facts', title = 'Codex facts', version = '1.2', author = 'Tim', notes = 'Quick\\nanswers',
				where = 'local', on = true, adds = { 'voice', 'Bad Id', 7 } },
			{ id = 'sound', title = 'Sound |cffff0000x|r', where = 'elsewhere', on = false },
			{ id = 'facts', title = 'Again' }, { id = 'Bad Id', title = 'Bad' }, { title = 'No id' }, 'text',
		} }""")
        self.assertEqual(answer, {"count": 2})
        kept = py(s.lua.eval(b"__ns.LocalList()"))
        self.assertEqual(kept[0], {"id": "facts", "title": "Codex facts", "version": "1.2", "author": "Tim",
                                   "notes": "Quick answers", "where": "local", "on": True, "game": {},
                                   "adds": ["voice"]})
        self.assertEqual((kept[1]["title"], kept[1]["where"], kept[1]["on"]), ("Sound |cffff0000x|r", "local", False))
        s.run(0.1)                                                              # the window: drawn again by itself
        self.assertEqual(texts(w[b"list"]), ["Built-in", "Added"])
        self.assertEqual(self.titles(w)[-3:], ["Codex facts", "Sound ||cffff0000x||r", "WxVoice"])
        self.assertEqual(self.tags(w, "Codex facts", "Sound ||cffff0000x||r", "WxVoice"), ["Local", "Local", "Game"])
        self.ink(s, self.item(w, "Codex facts")[b"label"], "fg")
        self.ink(s, self.item(w, "Sound ||cffff0000x||r")[b"label"], "muted")       # off
        self.assertFalse(self.item(w, "Codex facts")[b"dot"][b"shown"])
        click(self.item(w, "Codex facts"))
        self.assertEqual(texts(w[b"body"]), ["Codex facts", "v1.2 · Enabled · by Tim", "Quick answers",
                                             "Managed in the Wuxian Workshop app", "Adds to the apps: Voice"])
        self.assertEqual(self.pills(w), ["Added", "Local"])
        self.assertEqual((self.switches(w), labels(w)), ([], []))               # nothing to press: not the game's
        click(self.item(w, "Sound ||cffff0000x||r"))
        self.assertEqual(texts(w[b"body"]),
                         ["Sound ||cffff0000x||r", "Disabled", "Managed in the Wuxian Workshop app"])
        click(self.item(w, "WxVoice"))
        self.assertEqual(texts(w[b"body"])[-1], "Additions: Codex facts")       # under the app's card
        s.lua.execute(b"__ns.SetLanguage('zhCN')")
        self.assertEqual(texts(w[b"body"])[-1], "补充：Codex facts")
        self.assertEqual(self.tags(w, "Codex facts", "WxVoice"), ["本机", "游戏"])
        self.window(s, "local:facts")                                           # a row's own id opens it
        self.assertEqual(texts(w[b"body"])[1:], ["版本 1.2 · 已启用 · 作者 Tim", "Quick answers",
                                                 "在无限工坊 App 中管理", "补充到应用：Voice"])
        self.assertEqual(self.pills(w), ["已添加", "本机"])
        s.lua.execute(b"__ns.SetLanguage('enUS')")
        self.call(s, "kit.local.set", "{ extensions = { { id = 'facts', title = 'Codex facts', on = false, "
                                      "adds = { 'voice' } } } }")                # the whole list again: one, off
        s.run(0.1)
        self.assertEqual(self.titles(w)[-2:], ["Codex facts", "WxVoice"])
        self.assertEqual(texts(w[b"body"])[:2], ["Codex facts", "Disabled"])
        self.ink(s, self.item(w, "Codex facts")[b"label"], "muted")
        click(self.item(w, "WxVoice"))
        self.assertFalse([t for t in texts(w[b"body"]) if t.startswith("Additions")])   # off: it adds nothing
        click(self.item(w, "Codex facts"))
        self.assertEqual(self.call(s, "kit.local.set", "{ extensions = {} }"), {"count": 0})
        s.run(0.1)
        self.assertNotIn("Codex facts", self.titles(w))
        self.assertEqual(texts(w[b"body"])[0], "WxVoice")                       # its page gone: the first that runs

    def test_the_list_is_bounded(self):
        """at most 32 extensions kept, 16 ids in one's adds, texts cut"""
        s = start(self)
        answer = self.call(s, "kit.local.set", """(function()
			local list, adds = {}, {}
			for i = 1, 20 do adds[i] = 'app' .. i end
			for i = 1, 40 do list[i] = { id = 'x' .. i, title = ('t'):rep(100), adds = adds } end
			return { extensions = list }
		end)()""")
        self.assertEqual(answer, {"count": 32})
        kept = py(s.lua.eval(b"__ns.LocalList()"))
        self.assertEqual((len(kept), len(kept[0]["adds"]), kept[0]["title"]), (32, 16, "t" * 60 + "…"))
        w = self.window(s)
        self.assertEqual(len(self.titles(w)), len([t for t in self.titles(w) if not t.startswith("t")]) + 32)

    def test_an_app_names_its_local_extension(self):
        """an app a local extension declared (无限工坊's label on it) sits on that extension's row of the list
        无限工坊 gave, not on one of its own"""
        s = start(self)
        s.lua.execute(b"__add('pal', { by = 'agent', decl = { title = 'Pal', prompt = 'pal-run' }, "
                      b"['local'] = { id = 'pals', title = 'Label' }, status = { app = 'pal', on = true, said = 0 } })")
        self.call(s, "kit.local.set", "{ extensions = { { id = 'pals', title = 'Pals', version = '2', where = 'local' } } }")
        w = self.window(s, "pal")
        self.assertEqual(self.titles(w).count("Pals"), 1)
        self.assertNotIn("Label", self.titles(w))
        self.assertEqual(texts(w[b"list"]), ["Built-in", "Added"])              # no group of an agent's own
        self.assertEqual(texts(w[b"body"])[:4], ["Pals", "v2 · Enabled", "Managed in the Wuxian Workshop app", "App · Pal"])
        self.assertTrue(self.item(w, "Pals")[b"dot"][b"shown"])
        self.assertNotIn("Remove", labels(w))


@unittest.skipIf(lupa is None, "lupa (Lua 5.1 for Python) is not installed")
class AddonRows(Rows):
    def start(self):
        s = Session(self, fixtures=("MyGuildTools",))
        s.login()
        s.run(1)
        self.addCleanup(lambda: self.assertEqual(s.errors(), []))
        return s

    def test_an_app_on_its_extensions_page(self):
        """an addon's extension with an app: one row (已添加, in the game), the app's card on its page under the
        app's name; /wk <app> and Window(<app>) open that page; the row's dot while the app runs; the extension off:
        the row dimmed. 无限工坊 saying the extension is on this computer too: the same row, marked"""
        s = self.start()
        rows = {e["id"]: e for e in self.call(s, "kit.extensions")}
        self.assertEqual((rows["chat"].get("official"), rows["myguild"].get("official"), rows["chat"].get("author")),
                         (True, None, None))
        w = self.window(s, "officers")
        self.assertEqual(texts(w[b"list"]), ["Built-in", "Added"])
        self.assertEqual((self.titles(w)[-1], self.titles(w).count("Guild tools")), ("Guild tools", 1))
        self.assertNotIn("官员频道", self.titles(w))
        body = texts(w[b"body"])
        self.assertEqual(body[:2], ["Guild tools", "v1.0.0 · Enabled · MyGuildTools"])
        self.assertIn("App · 官员频道", body)
        self.assertEqual(self.pills(w), ["Added", "Game"])
        self.assertEqual(self.switches(w)[0], "Enabled")
        row = lambda: self.item(w, "Guild tools")
        self.assertEqual((self.tags(w, "Guild tools"), row()[b"dot"][b"shown"]), (["Game"], False))
        self.assertTrue(self.call(s, "kit.app.open", "{ app = 'officers' }")["on"])
        s.run(0.1)
        self.assertTrue(row()[b"dot"][b"shown"])
        self.assertEqual(py(row()[b"dot"][b"rgb"]), py(s.lua.eval(b"WuxianKit.Skin.C.ok")))
        self.call(s, "kit.local.set", """{ extensions = {
			{ id = 'guildkit', title = 'Guild kit', author = 'Ann', where = 'both', game = { 'myguild' } },
			{ id = 'facts', title = 'Codex facts', where = 'local', adds = { 'officers', 'nothere' } },
			{ id = 'pair', title = 'Pair', where = 'both', game = { 'absent' } },
		} }""")
        s.run(0.1)
        self.assertEqual(self.titles(w)[-3:], ["Guild tools", "Codex facts", "Pair"])   # no second row for the first
        self.assertEqual(self.tags(w, "Guild tools", "Codex facts", "Pair"), ["Game · Local", "Local", "Game · Local"])
        body = texts(w[b"body"])
        self.assertEqual(body[:2], ["Guild tools", "v1.0.0 · Enabled · MyGuildTools · by Ann"])
        self.assertIn("Additions: Codex facts", body)
        self.assertEqual(self.pills(w), ["Added", "Game · Local"])
        self.assertEqual(self.switches(w)[0], "Enabled")                        # the game's part: still switched here
        click(self.item(w, "Codex facts"))
        self.assertEqual(texts(w[b"body"])[-1], "Adds to the apps: 官员频道, nothere")
        click(self.item(w, "Pair"))                                             # its game part is not here: a row of its own
        self.assertEqual(texts(w[b"body"]), ["Pair", "Enabled", "Managed in the Wuxian Workshop app"])
        self.assertEqual(self.pills(w), ["Added", "Game · Local"])
        s.g("SlashCmdList")[b"WUXIANKIT"](b"officers")                          # /wk <app>: the page its card is on
        self.assertEqual(texts(w[b"body"])[0], "Guild tools")
        s.ns.Switch(b"myguild", False)
        s.run(0.1)
        self.ink(s, row()[b"label"], "muted")
        self.assertFalse(row()[b"dot"][b"shown"])                               # its app stopped with it
        self.assertIn("App · 官员频道", texts(w[b"body"]))


if __name__ == "__main__":
    unittest.main()
