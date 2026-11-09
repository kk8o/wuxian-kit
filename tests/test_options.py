"""0.5's options and what goes with them, under Lua 5.1 in the mock client: the option kinds (boolean, text, number,
choice, list) and how each keeps a value, kit.options and the kit.option event, WuxianKit:Requires, scopes with a
suggested budget (ns.ScopeBudget), the copy box (WuxianKit:Copy), WuxianKit:OptionsPanel, and the window's page: the new
controls, "connect an agent", the line under a running feed, the budget button of a ticked scope."""
import unittest
from unittest import mock

import kitmock
from kitmock import Session, click, lupa, py, texts, type_into

# the client's pieces the mock does not have: whether Ctrl is down, and a highlight that can be seen
MOCKS = b"""
__ctrl = false
function IsControlKeyDown() return __ctrl end
getmetatable(UIParent).HighlightText = function(self, a, b) self.highlighted = not (a == 0 and b == 0) end
"""

DEMO = """
local L = WuxianKit:Words { enUS = { MIN = "min" }, zhCN = { MIN = "分钟" } }
local x = WuxianKit:Extension('opt', { title = 'Opt', prompt = 'opt-setup' })
x:Option('take', { title = 'Take them', default = false })
x:Option('names', { title = 'Names', kind = 'text', default = '' })
x:Option('every', { title = 'Every', kind = 'number', min = 0, max = 100, step = 5, default = 12, unit = L"MIN",
	changed = function(self, v) __changed = v end })
x:Option('fine', { title = 'Fine', kind = 'number', min = 0, max = 1, step = 0.1, default = 0.5 })
x:Option('mood', { title = 'Mood', kind = 'choice', default = 'nope',
	choices = { { 'low', 'Low' }, { value = 'high', label = 'High' } } })
x:Option('who', { title = 'Who', kind = 'list', default = 'Ann, Bob' })
x:Option('odd', { title = 'Odd', kind = 'weird' })
x:Scope('guild.reply', { title = 'Replies', budget = { per = 600, most = 3 } })
x:Scope('guild', 'Guild chat')
x:Scope('bad', { title = 'Bad', budget = { per = 0, most = 3 } })
x:Feed('hear', { title = 'Hear', events = { 'CHAT_MSG_SAY' }, read = function(self, ev, text) return { text = text } end })
WuxianKit:Extension('bare', { title = 'Bare' })
__x = x
"""


@unittest.skipIf(lupa is None, "lupa (Lua 5.1 for Python) is not installed")
class Options(unittest.TestCase):
    def start(self, **kw):
        real = kitmock.run_files

        def keep_ns(test, lua, folder, ns=None):          # the core's private table, as __ns
            ns = real(test, lua, folder, ns)
            if folder == kitmock.KIT_DIR:
                lua.globals()[b"__ns"] = ns
            return ns

        with mock.patch.object(kitmock, "run_files", keep_ns):
            s = Session(self, **kw)
        s.lua.execute(MOCKS)
        s.lua.execute(b"__events = {} WuxianKit:On('kit.option', function(topic, data) "
                      b"__events[#__events + 1] = data end)")
        s.login()
        s.run(1)
        s.lua.execute(DEMO.encode())
        s.run(0.1)
        self.addCleanup(lambda: self.assertEqual(s.errors(), []))
        return s

    def get(self, s, name):
        return py(s.lua.eval(f"__x:Get({name!r})".encode()))

    def set(self, s, name, value):
        s.lua.execute(f"__ns.SetOption(__x, {name!r}, {value})".encode())
        return self.get(s, name)

    def call(self, s, cap, args="{}"):
        s.lua.execute(f"__answer = WuxianKit:Call({cap!r}, {args})".encode())
        return py(s.g("__answer"))

    def window(self, s, page):
        s.lua.execute(f"WuxianKit:Window({page!r})".encode())
        return s.g("WuxianKitWindow")

    def shown(self, pool):
        return [pool[i] for i in range(1, len(pool) + 1) if pool[i][b"shown"]]

    def button(self, frame, label):
        return next(b for b in self.shown(frame[b"buttons"]) if b[b"label"][b"text"].decode() == label)

    def test_each_kind_keeps_its_values(self):
        """a number in its range on its step, one of the choices (else the default), a list split, trimmed, without
        empty ones or the same twice, at most 20 of at most 32 bytes, read as a copy; an unknown kind is a check box"""
        s = self.start()
        self.assertEqual([self.get(s, n) for n in ("every", "fine", "mood", "who")], [10, 0.5, "low", ["Ann", "Bob"]])
        for value, kept in (("47", 45), ("48", 50), ("200", 100), ("-3", 0), ("'abc'", 0), ("'35'", 35), ("nil", 35)):
            self.assertEqual(self.set(s, "every", value), kept, value)               # not a number: as it was
        self.assertEqual(self.set(s, "fine", "0.33"), 0.3)
        self.assertEqual(s.lua.eval(b"__x:Get('fine') == 0.3"), True)                 # no float's tail
        self.assertEqual(self.set(s, "mood", "'high'"), "high")
        self.assertEqual(self.set(s, "mood", "'loud'"), "low")
        self.assertEqual(self.set(s, "who", "' Ann , Bob，Cid、 Ann ,, '"), ["Ann", "Bob", "Cid"])
        self.assertEqual(self.set(s, "who", "{ 'a', ' b ', 'a', 3, {} }"), ["a", "b", "3"])
        self.assertEqual(len(self.set(s, "who", "'" + ",".join(f"n{i}" for i in range(25)) + "'")), 20)
        self.assertEqual(self.set(s, "who", "'" + "x" * 40 + "'"), ["x" * 32])
        self.assertEqual(self.set(s, "who", "'" + "公" * 11 + "'"), ["公" * 10])   # never inside a character
        s.lua.execute(b"table.insert(__x:Get('who'), 'more')")
        self.assertEqual(self.get(s, "who"), ["公" * 10])
        self.assertEqual(self.set(s, "odd", "'yes'"), True)
        self.assertEqual(self.set(s, "names", "5"), "5")
        s.lua.execute(b"__x.db.options.mood = 'gone'")                            # kept before the choices changed
        self.assertEqual(self.get(s, "mood"), "low")
        self.assertEqual(py(s.g("WuxianKitDB"))["ext"]["opt"]["options"]["who"], ["公" * 10])

    def test_kit_options_and_the_event(self):
        """kit.options reads an extension's options in the language in force; a change calls changed and emits
        kit.option, setting the same value again does neither"""
        s = self.start()
        got = self.call(s, "kit.options", "{ extension = 'opt' }")
        self.assertEqual(got["every"], {"title": "Every", "kind": "number", "value": 10, "default": 10, "min": 0,
                                        "max": 100, "unit": "min"})
        self.assertEqual(got["mood"], {"title": "Mood", "kind": "choice", "value": "low", "default": "low",
                                       "choices": [{"value": "low", "label": "Low"}, {"value": "high", "label": "High"}]})
        self.assertEqual((got["who"]["value"], got["take"]["kind"], got["odd"]["kind"]), (["Ann", "Bob"], "boolean", "boolean"))
        s.lua.execute(b"__ns.SetLanguage('zhCN')")
        self.assertEqual(self.call(s, "kit.options", "{ extension = 'opt' }")["every"]["unit"], "分钟")
        ok, err = s.lua.eval(b"pcall(function() WuxianKit:Call('kit.options', { extension = 'nope' }) end)")
        self.assertFalse(ok)
        self.assertIn("no extension nope", err.decode())
        self.assertEqual(self.call(s, "kit.options", "{ extension = 'bare' }"), {})
        self.set(s, "every", 30)
        self.set(s, "every", 30)
        self.set(s, "every", 31)                                                  # 30 again on its step
        self.assertEqual(py(s.g("__events")), [{"extension": "opt", "name": "every", "value": 30}])
        self.assertEqual(s.g("__changed"), 30)
        self.set(s, "who", "'Cid'")
        self.assertEqual(py(s.g("__events"))[-1], {"extension": "opt", "name": "who", "value": ["Cid"]})

    def test_requires(self):
        """WuxianKit:Requires(version): this version or newer; false when the version is unknown"""
        s = self.start()
        self.assertEqual(s.lua.eval(b"WuxianKit.VERSION"), b"0.6.0")
        for want, ok in (("0.6.0", True), ("0.5.9", True), ("0.6", True), ("0.5.12", True), ("0.6.1", False),
                         ("0.10.0", False), ("1.0", False), ("x", False)):
            self.assertEqual(s.lua.eval(f"WuxianKit:Requires({want!r})".encode()), ok, want)
        s.lua.execute(b"WuxianKit.VERSION = '?'")
        self.assertFalse(s.lua.eval(b"WuxianKit:Requires('0.1.0')"))

    def test_scopes_and_their_budgets(self):
        """a scope's name may have dots; its title as a string or in a table with a suggested budget, read with
        ns.ScopeBudget (a copy; nil for none or a budget that makes no sense)"""
        s = self.start()
        self.assertEqual(py(s.lua.eval(b"__x.scopes")), {"opt.guild.reply": "Replies", "opt.guild": "Guild chat",
                                                         "opt.bad": "Bad"})
        self.assertEqual(py(s.lua.eval(b"__ns.ScopeBudget('opt.guild.reply')")), {"per": 600, "most": 3})
        s.lua.execute(b"__ns.ScopeBudget('opt.guild.reply').most = 99")
        self.assertEqual(py(s.lua.eval(b"__ns.ScopeBudget('opt.guild.reply')")), {"per": 600, "most": 3})
        for scope in ("opt.guild", "opt.bad", "nope.x", "opt"):
            self.assertIsNone(s.lua.eval(f"__ns.ScopeBudget({scope!r})".encode()), scope)

    def test_the_copy_box(self):
        """the text selected with the keyboard in it; what is typed goes; Ctrl+C says so, and a moment later the box
        goes and done runs; a new text takes the place of the one shown; Esc closes it"""
        s = self.start()
        s.lua.execute(b"WuxianKit:Copy('hello', { title = 'Invite', hint = 'paste it', "
                      b"done = function() __done = (__done or 0) + 1 end })")
        f = s.g("WuxianKitCopyWindow")
        edit = f[b"edit"]
        self.assertTrue(f[b"shown"])
        self.assertIn(b"WuxianKitCopyWindow", list(s.g("UISpecialFrames").values()))
        self.assertEqual((edit[b"text"], edit[b"focus"], edit[b"highlighted"]), (b"hello", True, True))
        self.assertEqual(texts(f)[:3], ["Invite", "paste it", "Ctrl+C to copy"])
        edit[b"highlighted"] = False
        edit.SetText(edit, b"hellox")
        edit[b"scripts"][b"OnTextChanged"](edit, True)
        self.assertEqual((edit[b"text"], edit[b"highlighted"]), (b"hello", True))
        edit[b"scripts"][b"OnKeyDown"](edit, b"C")                            # no Ctrl
        self.assertNotIn("Copied", texts(f))
        s.lua.execute(b"__ctrl = true")
        edit[b"scripts"][b"OnKeyDown"](edit, b"C")
        self.assertIn("Copied", texts(f))
        self.assertTrue(f[b"shown"])                                            # the client copies first
        s.run(0.5)
        self.assertEqual((f[b"shown"], s.g("__done")), (False, 1))
        s.lua.execute(b"WuxianKit:Copy('one', { done = function() __one = true end }) "
                      b"WuxianKit:Copy('two', { done = function() __two = true end })")
        self.assertEqual(edit[b"text"], b"two")
        self.assertEqual(texts(f)[-1], "Ctrl+C to copy")
        edit[b"scripts"][b"OnKeyDown"](edit, b"C")
        s.run(0.5)
        self.assertEqual((s.g("__one"), s.g("__two")), (None, True))
        s.lua.execute(b"WuxianKit:Copy('three')")
        edit[b"scripts"][b"OnEscapePressed"](edit)
        self.assertFalse(f[b"shown"])

    def test_the_options_panel(self):
        """WuxianKit:OptionsPanel draws an extension's options in another window, its height as they take; a change
        there is the window's change and both redraw; nil for an extension without options or none at all"""
        s = self.start()
        s.lua.execute(b"__host = CreateFrame('Frame', nil, UIParent) __p = WuxianKit:OptionsPanel('opt', __host, 320)")
        p = s.g("__p")
        self.assertIsNotNone(p)
        self.assertEqual(p[b"w"], 320)
        self.assertGreater(p[b"h"], 100)
        shown = texts(p)
        for want in ("Names", "Every", "min", "Mood", "Who", "Separate with commas"):
            self.assertIn(want, shown)
        self.assertNotIn("Options", shown)                                       # the host's own heading, if any
        checks = {c[b"label"][b"text"].decode(): c for c in self.shown(p[b"checks"])}
        click(checks["Take them"])
        self.assertTrue(self.get(s, "take"))
        click(self.button(p, "High"))
        self.assertEqual(self.get(s, "mood"), "high")
        self.assertTrue(self.button(p, "High")[b"primary"])
        self.assertFalse(self.button(p, "Low")[b"primary"])
        edits = self.shown(p[b"edits"])
        self.assertEqual([e[b"text"].decode() for e in edits], ["", "10", "0.5", "Ann, Bob"])
        type_into(edits[1], "33")
        self.assertEqual((self.get(s, "every"), edits[1][b"text"]), (35, b"35"))   # redrawn as kept
        w = self.window(s, "opt")
        wedits = self.shown(w[b"edits"])
        self.assertEqual(wedits[1][b"text"], b"35")
        type_into(wedits[3], "Cid， Dan")
        self.assertEqual(self.shown(p[b"edits"])[3][b"text"].decode(), "Cid, Dan")   # the panel redrawn too
        s.lua.execute(b"__ns.SetOption(__x, 'every', 70) __p:Refresh()")
        self.assertEqual(self.shown(p[b"edits"])[1][b"text"], b"70")
        for code in (b"WuxianKit:OptionsPanel('bare', UIParent)", b"WuxianKit:OptionsPanel('nope', UIParent)",
                     b"WuxianKit:OptionsPanel(nil, UIParent)"):
            self.assertIsNone(s.lua.eval(code), code)
        self.assertEqual(s.lua.eval(b"WuxianKit:OptionsPanel('opt', __host).w"), 300)                 # no width: 300

    def test_the_page(self):
        """the page draws the new kinds (the list joined in the language in force, its hint), "connect an agent" opens
        the copy box with the prompt's command, a running feed says when the agent last answered"""
        s = self.start()
        w = self.window(s, "opt")
        body = texts(w[b"body"])
        for want in ("Every", "min", "Mood", "Who", "Separate with commas"):
            self.assertIn(want, body)
        self.assertEqual([e[b"text"].decode() for e in self.shown(w[b"edits"])], ["", "10", "0.5", "Ann, Bob"])
        click(self.button(w, "High"))
        self.assertEqual(self.get(s, "mood"), "high")
        s.lua.execute(b"__ns.SetLanguage('zhCN')")
        self.assertEqual(self.shown(w[b"edits"])[3][b"text"].decode(), "Ann、Bob")
        s.lua.execute(b"__ns.SetLanguage('enUS')")
        click(self.button(w, "Connect an agent"))
        f = s.g("WuxianKitCopyWindow")
        self.assertEqual((f[b"shown"], f[b"edit"][b"text"]), (True, b"/mcp__wuxian__opt-setup"))
        self.assertEqual(texts(f)[0], "Connect an agent")
        self.assertIn('"opt-setup"', texts(f)[1])
        self.assertNotIn("Connect an agent", [b[b"label"][b"text"].decode() for b in self.shown(self.window(s, "bare")[b"buttons"])])
        self.call(s, "opt.hear")
        w = self.window(s, "opt")
        self.assertIn("Agent has not answered yet", texts(w[b"body"]))
        s.lua.execute(b"function __ns.FeedInfo(feed) return { heard = 3, wakes = 2, seen = time() - 600 } end")
        s.lua.execute(b"WuxianKit:Window('opt')")
        self.assertIn("Agent last answered 10 min ago · Woken 2 times", texts(w[b"body"]))
        s.lua.execute(b"__ns.SetLanguage('zhCN')")
        self.assertIn("Agent 最近应答：10 分钟前 · 已唤醒 2 次",
                      texts(w[b"body"]))

    def test_budgets_on_the_page(self):
        """a ticked scope shows its budget on a button that goes through the scope's suggested one, the usual ones and
        no limit (none twice), as ns.Act("grant", scope, true, budget); an old grant (true) has no limit"""
        s = self.start()
        s.lua.execute(b"__grants, __acts = {}, {} "
                      b"function __ns.Grants() return __grants end "
                      b"__ns.AddAction('grant', function(scope, on, budget) "
                      b"  __acts[#__acts + 1] = { scope = scope, on = on, budget = budget == nil and 'nil' or budget } "
                      b"  __grants[scope] = on and (budget or true) or nil  __ns.UI.Refresh() return true end)")
        w = self.window(s, "opt")
        checks = {c[b"label"][b"text"].decode(): c for c in self.shown(w[b"checks"])}
        click(checks["Replies"])
        self.assertEqual(py(s.g("__acts"))[-1], {"scope": "opt.guild.reply", "on": True, "budget": "nil"})
        click(self.button(w, "No limit"))                                      # nil came back as true: no limit
        self.assertEqual(py(s.g("__acts"))[-1]["budget"], {"per": 600, "most": 3})
        s.lua.execute(b"__grants['opt.guild.reply'].used = 1 WuxianKit:Window('opt')")
        click(self.button(w, "Per 10 min: at most 3 · 1/3"))
        seen = [py(s.g("__acts"))[-1]["budget"]]
        for _ in range(4):
            label = next(b[b"label"][b"text"].decode() for b in self.shown(w[b"buttons"])
                         if b[b"label"][b"text"].decode().startswith(("Per", "No limit")))
            click(self.button(w, label))
            seen.append(py(s.g("__acts"))[-1]["budget"])
        self.assertEqual(seen, [{"per": 600, "most": 1}, {"per": 600, "most": 6}, {"per": 3600, "most": 10}, False,
                                {"per": 600, "most": 3}])
        s.lua.execute(b"__grants['opt.guild'] = true WuxianKit:Window('opt')")
        click(next(b for b in self.shown(w[b"buttons"]) if b[b"label"][b"text"] == b"No limit"))
        self.assertEqual(py(s.g("__acts"))[-1], {"scope": "opt.guild", "on": True, "budget": {"per": 600, "most": 1}})
        self.assertEqual(s.lua.eval(b"WuxianKit.Skin.Duration(45)"), b"45 s")
        self.assertEqual(s.lua.eval(b"WuxianKit.Skin.Duration(7300)"), b"2 h")


if __name__ == "__main__":
    unittest.main()
