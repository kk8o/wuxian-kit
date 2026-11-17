"""Apps, 0.6.1 (ARCHITECTURE section 10 and section 16): who drives an app. The declaration's driver (agent, the default
and no mark; local only with local, as 无限工坊 declares a local extension's app; else refused) in the status, the rows
of kit.apps, describe and the manifest, with no start line for a local driver; its card (no 交给 AI, run by the local
extension, or not running and how its last run ended; stop and the controls as any other's); kit.local.set's options
(kept in order, the ones that are not so skipped); the window's 本机选项 on a local extension's page and on the row of one
in the game too (boolean, number and choice changed there: kit.local.option, shown at once, the next list confirms or
puts back; a text shown with where it is changed); and kit.local.option, which only the core sends."""
import unittest

from kitmock import click, lupa, py, texts, type_into
from test_app_panel import button, labels, shown
from test_app_reconcile import Case

LOCAL = "['local'] = { id = 'cocreate', title = 'Co-create' }"
DRIVEN = (f"{{ app = 'cc', title = 'Data', {LOCAL}, driver = 'local', prompt = 'cc-skill', hear = {{ 'bus:demo.*' }}, "
          f"controls = {{ 'stop', {{ cmd = 'submit', label = 'Submit' }} }}, lease = 0 }}")

OPTIONS = """{
	{ name = 'auto', kind = 'boolean', title = 'Sync by itself', value = true, default = true, hint = 'After each snapshot' },
	{ name = 'every', kind = 'number', title = 'Every', value = 10, min = 5, max = 60, step = 5, unit = 'min' },
	{ name = 'mode', kind = 'choice', title = 'Mode', value = 'fast', choices = { { value = 'fast', label = 'Fast' },
		{ value = 'full', label = 'Full' } } },
	{ name = 'folder', kind = 'text', title = 'Folder', value = 'C:/data', hint = 'Where it saves' },
}"""


class Base(Case):
    def start(self, s=None, **kw):
        s = super().start(s, **kw)
        s.lua.execute(b"local ns = ... __ns = ns", s.ns)                 # (the core's private table, as __ns)
        return s


@unittest.skipIf(lupa is None, "lupa (Lua 5.1 for Python) is not installed")
class Driver(Base):
    def test_agent_local_or_refused(self):
        s = self.start()
        st = self.agent(s, "kit.app.declare", DRIVEN)
        self.assertEqual(st["driver"], "local")
        self.assertNotIn("start", st)                                     # no agent hands it on: no start line
        row = self.row(s, "cc")
        self.assertEqual((row["driver"], row["prompt"]), ("local", "cc-skill"))
        self.assertNotIn("start", row)
        self.assertEqual(self.agent(s, "kit.app.describe", "{ app = 'cc' }")["decl"]["driver"], "local")
        self.assertFalse(self.agent(s, "kit.app.declare", DRIVEN)["changed"])
        m = next(a for a in self.lua(s, "WuxianKit:Manifest()")["apps"] if a["id"] == "cc")
        self.assertEqual(m["driver"], "local")
        self.assertNotIn("start", m)
        for decl in (f"{{ app = 'ag', {LOCAL}, prompt = 'ag' }}", f"{{ app = 'ag', {LOCAL}, prompt = 'ag', driver = 'agent' }}"):
            st = self.agent(s, "kit.app.declare", decl)
            self.assertNotIn("driver", st, decl)                          # agent is no mark at all
            self.assertNotIn("driver", self.row(s, "ag"), decl)
            self.assertNotIn("driver", self.agent(s, "kit.app.describe", "{ app = 'ag' }")["decl"], decl)
            self.assertIn("ag", st["start"], decl)
        self.assertFalse(st["changed"])                                   # agent given is none given
        st = self.agent(s, "kit.app.declare", f"{{ app = 'cc', title = 'Data', {LOCAL} }}")   # whole: the mark goes
        self.assertTrue(st["changed"])
        self.assertNotIn("driver", st)
        s2 = self.start(s.reload())                                       # kept through a reload
        self.agent(s2, "kit.app.declare", DRIVEN)
        s3 = self.start(s2.reload())
        self.assertEqual(self.row(s3, "cc")["driver"], "local")
        self.assertEqual(s3.chat().count("no longer holds"), 0)

    def test_refused(self):
        s = self.start()
        for value in ("'program'", "'prompt'", "'LOCAL'", "''", "true", "{}"):
            self.assertIn("driver", self.fails(s, "kit.app.declare", f"{{ app = 'x', {LOCAL}, driver = {value} }}"), value)
        err = self.fails(s, "kit.app.declare", "{ app = 'x', driver = 'local' }")   # an agent's own: no local label
        self.assertIn("driver local is for an app 无限工坊 declares for a local extension", err)
        self.assertIn("driver local is for", self.fails(s, "kit.app.open", "{ app = 't', temp = { driver = 'local' } }"))
        self.assertIn("no argument driver", self.fails(s, "kit.app.open", "{ app = 'x', driver = 'local' }"))
        self.assertEqual([a["id"] for a in py(s.ns.AppList())], [])
        ok, err = s.lua.eval(b"pcall(WuxianKit.App, WuxianKit, 'mine', { title = 'Mine', driver = 'local' })")
        self.assertFalse(ok)
        self.assertIn("driver local is for", err.decode())
        s.lua.execute(f"WuxianKit:App('mine', {{ title = 'Mine', {LOCAL}, driver = 'local' }})".encode())
        self.assertEqual(self.agent(s, "kit.app.status", "{ app = 'mine' }")["driver"], "local")

    def test_its_runs(self):
        """a local driver changes nothing of a run: open, status (heartbeat), controls, stop as any other"""
        s = self.start()
        self.agent(s, "kit.app.declare", DRIVEN)
        st = self.agent(s, "kit.app.open", "{ app = 'cc' }")
        self.assertEqual((st["on"], st["driver"]), (True, "local"))
        self.assertEqual(self.app_events(s, "cc")[-1]["on"], True)
        self.assertTrue(s.lua.eval(b"WuxianKit:AppControl('cc', 'submit')"))
        self.assertTrue(s.lua.eval(b"WuxianKit:AppControl('cc', 'stop')"))
        self.assertEqual(self.app_events(s, "cc")[-1], {"app": "cc", "on": False, "why": "player"})
        st = self.agent(s, "kit.app.status", "{ app = 'cc' }")
        self.assertEqual((st["on"], st["why"], st["driver"]), (False, "player", "local"))


@unittest.skipIf(lupa is None, "lupa (Lua 5.1 for Python) is not installed")
class Card(Base):
    def start(self, s=None, **kw):
        s = super().start(s, **kw)
        s.lua.execute(b"function WuxianKit:AgentOnline() return true end")
        return s

    def panel(self, s, app):
        s.lua.execute(f"__host = __host or CreateFrame('Frame', nil, UIParent) "
                      f"__p = WuxianKit:AppPanel({app!r}, __host, 320)".encode())
        return s.g("__p")

    def redraw(self, s):
        s.lua.execute(b"__p:Refresh()")
        return texts(s.g("__p"))

    def test_no_hand_to_ai(self):
        """stopped: not running (no 交给 AI though it has a prompt); running: run by its local extension, with stop and
        its controls; stopped by the player: said so, and when it starts again; a lease that ran out, time that is up"""
        s = self.start()
        self.agent(s, "kit.app.declare", DRIVEN)
        self.agent(s, "kit.app.declare", f"{{ app = 'ag', title = 'Agent', {LOCAL}, prompt = 'ag' }}")
        p = self.panel(s, "ag")
        self.assertEqual((texts(p)[0], labels(p)), ("Ready to connect an agent", ["Hand to AI"]))   # an agent's: as ever
        p = self.panel(s, "cc")
        self.assertEqual(texts(p)[0], "Local extension not running")
        self.assertEqual(labels(p), [])
        self.agent(s, "kit.app.open", "{ app = 'cc' }")
        self.assertEqual(self.redraw(s)[0], "Run by the local extension Co-create")
        self.assertEqual(labels(p), ["Stop", "Submit"])
        s.lua.execute(b"__ns.SetLanguage('zhCN')")
        self.assertEqual(self.redraw(s)[0], "由本机扩展「Co-create」运行")
        self.assertEqual(labels(p), ["停止", "Submit"])
        click(button(p, "停止"))
        self.assertEqual(self.redraw(s)[:2], ["已手动停止", "重载界面或重新登录后自动开始"])
        self.assertEqual(labels(p), [])
        s.lua.execute(b"__ns.SetLanguage('enUS')")
        self.assertEqual(self.redraw(s)[:2], ["Stopped by you", "Starts again after a UI reload or login"])
        self.agent(s, "kit.app.open", "{ app = 'cc', minutes = 1 }")
        s.run(61)
        self.assertEqual(self.redraw(s)[0], "Time is up")
        self.agent(s, "kit.app.open", "{ app = 'cc', lease = 60 }")
        s.run(70)
        self.call(s, "kit.app.status", "{ app = 'cc' }")                  # (an addon's call: no heartbeat)
        self.assertEqual(self.redraw(s)[0], "Local extension not responding")
        self.agent(s, "kit.app.open", "{ app = 'cc' }")
        self.agent(s, "kit.app.stop", "{ app = 'cc' }")                   # stopped by its program: not running
        self.assertEqual(self.redraw(s)[0], "Local extension not running")

    def test_no_link_first(self):
        s = self.start()
        self.agent(s, "kit.app.declare", DRIVEN)
        s.lua.execute(b"function WuxianKit:AgentOnline() return false end")
        self.assertEqual(texts(self.panel(s, "cc"))[0], "Wuxian Workshop not connected")


@unittest.skipIf(lupa is None, "lupa (Lua 5.1 for Python) is not installed")
class LocalOptions(Base):
    def set(self, s, options, where="local", game="", extra=""):
        return self.call(s, "kit.local.set", f"{{ extensions = {{ {{ id = 'cocreate', title = 'Co-create', "
                                             f"where = {where!r}, on = true, {game} options = {options} }}, {extra} }} }}")

    def kept(self, s):
        return py(s.lua.eval(b"__ns.LocalList()"))

    def window(self, s, page):
        s.lua.execute(f"WuxianKit:Window({page!r})".encode())
        return s.g("WuxianKitWindow")

    def test_kept_and_skipped(self):
        s = self.start()
        self.assertEqual(self.set(s, OPTIONS), {"count": 1})
        kept = self.kept(s)[0]["options"]
        self.assertEqual([o["name"] for o in kept], ["auto", "every", "mode", "folder"])   # in their order
        self.assertEqual(kept[0], {"name": "auto", "kind": "boolean", "title": "Sync by itself", "value": True,
                                   "default": True, "hint": "After each snapshot"})
        self.assertEqual(kept[1], {"name": "every", "kind": "number", "title": "Every", "value": 10, "min": 5,
                                   "max": 60, "step": 5, "unit": "min"})
        self.assertEqual(kept[2]["choices"], [{"value": "fast", "label": "Fast"}, {"value": "full", "label": "Full"}])
        self.assertEqual(kept[3], {"name": "folder", "kind": "text", "title": "Folder", "value": "C:/data",
                                   "hint": "Where it saves"})
        self.set(s, """{
			{ name = 'list', kind = 'list', value = {} },                            -- not a kind it takes
			{ name = 'Bad Name', kind = 'boolean', value = true },
			{ kind = 'boolean', value = true },
			{ name = 'b', kind = 'boolean', value = 'yes' },                       -- a value not of its kind
			{ name = 'n', kind = 'number', value = 1, default = 'x' },             -- nor a default
			{ name = 'n2', kind = 'number', value = 1, step = 0 },
			{ name = 'n3', kind = 'number', value = 1, min = 'low' },
			{ name = 'c', kind = 'choice', value = 'z', choices = { { value = 'a' } } },   -- its value not among them
			{ name = 'c2', kind = 'choice', value = 'a' },
			{ name = 't', kind = 'text', value = 3 },
			'text', 7,
			{ name = 'ok', kind = 'boolean', value = false },
			{ name = 'ok', kind = 'boolean', value = true },                       -- a name once
			{ name = 'c3', kind = 'choice', value = 2, choices = { { value = 1, label = 'One' }, { value = 2 }, 'x' } },
		}""")
        kept = self.kept(s)[0]["options"]
        self.assertEqual([o["name"] for o in kept], ["ok", "c3"])
        self.assertEqual((kept[0]["value"], kept[0]["title"]), (False, "ok"))
        self.assertEqual(kept[1]["choices"], [{"value": 1, "label": "One"}, {"value": 2, "label": "2"}])
        for options in ("{}", "{ { name = 'x' } }", "'auto'"):              # none that holds: no options at all
            self.set(s, options)
            self.assertNotIn("options", self.kept(s)[0], options)
        self.call(s, "kit.local.set", "{ extensions = { { id = 'plain', title = 'Plain' } } }")
        self.assertNotIn("options", self.kept(s)[0])

    def test_the_page(self):
        """a local extension's page: 本机选项 last, a check, a number box with its unit, a row of choices, a text with
        its value and where it is changed (no box)"""
        s = self.start()
        self.set(s, OPTIONS)
        w = self.window(s, "local:cocreate")
        body = texts(w[b"body"])
        at = body.index("Local options")
        self.assertEqual(body[at:], ["Local options", "After each snapshot", "Every", "min", "Mode", "Folder", "C:/data",
                                     "Change it in the Wuxian Workshop app"])
        self.assertEqual([c[b"label"][b"text"].decode() for c in shown(w[b"checks"])], ["Sync by itself"])
        self.assertEqual([e[b"text"].decode() for e in shown(w[b"edits"])], ["10"])   # the number's; no text box
        self.assertEqual(labels(w), ["Fast", "Full"])
        self.assertTrue(button(w, "Fast")[b"primary"])
        s.lua.execute(b"__ns.SetLanguage('zhCN')")
        body = texts(w[b"body"])
        self.assertEqual(body[body.index("本机选项"):][-3:], ["Folder", "C:/data", "在无限工坊 App 中修改"])
        self.set(s, "{ { name = 'folder', kind = 'text', title = 'Folder |cffff0000x|r', value = '' } }")
        s.run(0.1)
        self.assertEqual(texts(w[b"body"])[-3:], ["Folder ||cffff0000x||r", "未设置", "在无限工坊 App 中修改"])

    def test_a_change_goes_to_the_workshop(self):
        """the player changes one: kit.local.option {extension, name, value} (to 无限工坊 too), the new value shown at
        once; the next list confirms it, or puts back what 无限工坊 holds"""
        s = self.start()
        self.set(s, OPTIONS)
        w = self.window(s, "local:cocreate")
        s.lua.execute(b"__events = {} __emitted = {}")
        click(shown(w[b"checks"])[0])
        self.assertEqual(self.events(s, "kit.local.option"), [{"extension": "cocreate", "name": "auto", "value": False}])
        self.assertIn("kit.local.option", py(s.g("__emitted")))          # forwarded to 无限工坊
        self.assertFalse(shown(w[b"checks"])[0][b"checked"])              # shown at once
        self.assertFalse(self.kept(s)[0]["options"][0]["value"])
        click(button(w, "Full"))
        type_into(shown(w[b"edits"])[0], "23")                            # on its step, in its range
        type_into(shown(w[b"edits"])[0], "many")                          # not a number: nothing
        type_into(shown(w[b"edits"])[0], "900")
        click(button(w, "Full"))                                          # the same again: nothing
        self.assertEqual([(e["name"], e["value"]) for e in self.events(s, "kit.local.option")],
                         [("auto", False), ("mode", "full"), ("every", 25), ("every", 60)])
        self.assertTrue(button(w, "Full")[b"primary"])
        self.set(s, OPTIONS)                                              # 无限工坊 did not take them: put back
        s.run(0.1)
        self.assertTrue(shown(w[b"checks"])[0][b"checked"])
        self.assertTrue(button(w, "Fast")[b"primary"])
        self.assertEqual([e[b"text"].decode() for e in shown(w[b"edits"])], ["10"])
        self.assertEqual(len(self.events(s, "kit.local.option")), 4)      # the list itself tells nothing
        self.assertEqual(py(s.lua.eval(b"{ __ns.SetLocalOption('cocreate', 'folder', 'D:/x') }")), [False])   # a text
        self.assertEqual(py(s.lua.eval(b"{ __ns.SetLocalOption('cocreate', 'nope', true) }")), [False])
        self.assertEqual(py(s.lua.eval(b"{ __ns.SetLocalOption('other', 'auto', true) }")), [False])
        self.assertEqual(len(self.events(s, "kit.local.option")), 4)

    def test_the_row_of_one_in_the_game_too(self):
        """where both: the game's extension's row, its options under 选项, then 本机选项"""
        s = self.start()
        s.lua.execute(b"local e = WuxianKit:Extension('cocreate', { title = 'Co-create' }) "
                      b"e:Option('show', { title = 'Show my name', default = true })")
        s.run(0.5)
        self.set(s, "{ { name = 'auto', kind = 'boolean', title = 'Sync by itself', value = true } }", where="both",
                 game="game = { 'cocreate' },")
        w = self.window(s, "cocreate")
        body = texts(w[b"body"])
        self.assertLess(body.index("Options"), body.index("Local options"))
        self.assertLess(body.index("Local options"), body.index("Capabilities"))   # the game's options, then these
        checks = [c[b"label"][b"text"].decode() for c in shown(w[b"checks"])]
        self.assertEqual(checks[-2:], ["Show my name", "Sync by itself"])
        click(shown(w[b"checks"])[-1])
        self.assertEqual(self.events(s, "kit.local.option")[-1], {"extension": "cocreate", "name": "auto",
                                                                   "value": False})
        self.assertNotIn({"extension": "cocreate", "name": "auto", "value": False}, self.events(s, "kit.option"))


@unittest.skipIf(lupa is None, "lupa (Lua 5.1 for Python) is not installed")
class CoreOnly(Base):
    def test_only_the_core_sends_it(self):
        s = self.start()
        ok, err = s.lua.eval(b"pcall(WuxianKit.Emit, WuxianKit, 'kit.local.option', { extension = 'x', name = 'a', "
                             b"value = true })")
        self.assertFalse(ok)
        self.assertIn("only WuxianKit itself sends kit.local.option", err.decode())
        ok, err = s.lua.eval(b"pcall(function() WuxianKit:Extension('kit'):Emit('local.option', {}) end)")
        self.assertFalse(ok)
        self.assertEqual(self.events(s, "kit.local.option"), [])
        s.lua.execute(b"WuxianKit:Emit('kit.local.optional', {}) WuxianKit:Emit('demo.local.option', {})")   # others go
        self.assertEqual(len(self.events(s, "kit.local.optional")) + len(self.events(s, "demo.local.option")), 2)
        ev = next(e for e in self.lua(s, "WuxianKit:Manifest()")["extensions"] if e["id"] == "kit")["events"]
        self.assertIn("kit.local.option", [e["topic"] for e in ev])


if __name__ == "__main__":
    unittest.main()
