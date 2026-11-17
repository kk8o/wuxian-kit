"""Apps, who drives one (ARCHITECTURE section 10). The declaration's driver (agent, the default and no mark; local only
with local, as 无限工坊 declares a local extension's app; else refused): by "local" in the status, the rows of kit.apps,
describe and the manifest, no start line, and a run that has no end (no minutes, in the declaration or at
kit.app.open; its lease alone ends it) and tells the chat nothing but a lease that ran out. Its card: no 交给 AI and no
word of an agent; 本机端运行中, 本机端未运行, 已停止 with 开始 (the player's to start again while that program runs:
kit.app on = true as ever), 本机端无响应，已停止. kit.local.set's options (kept in order, the ones that are not so
skipped; no step: not rounded); on the page the ones the player changes (a change is kit.local.option, shown at once
and marked until the next list confirms it, back by itself after ten seconds; dim and not to be changed while 无限工坊
is not linked), then the texts, a line each under where they are changed; 游戏选项 and 本机选项 on the row of an
extension in the game too. And the bus: kit.* and app.* are the core's own topics."""
import unittest

from kitmock import click, lupa, py, texts, type_into
from test_app_panel import button, labels, shown
from test_app_reconcile import Case

LOCAL = "['local'] = { id = 'cocreate', title = 'Co-create' }"
DRIVEN = (f"{{ app = 'cc', title = 'Data', {LOCAL}, driver = 'local', prompt = 'cc-skill', hear = {{ 'bus:demo.*' }}, "
          f"controls = {{ 'stop', {{ cmd = 'submit', label = 'Submit' }} }}, lease = 0 }}")
LEASED = DRIVEN.replace("lease = 0", "lease = 60")

OPTIONS = """{
	{ name = 'auto', kind = 'boolean', title = 'Sync by itself', value = true, default = true, hint = 'After each snapshot' },
	{ name = 'every', kind = 'number', title = 'Every', value = 10, min = 5, max = 60, step = 5, unit = 'min' },
	{ name = 'folder', kind = 'text', title = 'Folder', value = 'C:/data', hint = 'Where it saves' },
	{ name = 'mode', kind = 'choice', title = 'Mode', value = 'fast', choices = { { value = 'fast', label = 'Fast' },
		{ value = 'full', label = 'Full' } } },
}"""


class Base(Case):
    def roster(self, s, running=True, on=True, options=None, more=""):
        """无限工坊's list with the local extension cocreate in it"""
        options = f"options = {options}," if options else ""
        return self.call(s, "kit.local.set", f"{{ extensions = {{ {{ id = 'cocreate', title = 'Co-create', "
                                             f"version = '1.2.0', where = 'local', on = {str(on).lower()}, "
                                             f"running = {str(running).lower()}, {options} {more} }} }} }}")

    def online(self, s, on=True):
        s.lua.execute(f"function WuxianKit:AgentOnline() return {str(on).lower()} end".encode())


@unittest.skipIf(lupa is None, "lupa (Lua 5.1 for Python) is not installed")
class Driver(Base):
    def test_agent_local_or_refused(self):
        s = self.start()
        st = self.agent(s, "kit.app.declare", DRIVEN)
        self.assertEqual((st["driver"], st["by"]), ("local", "local"))
        self.assertNotIn("start", st)                                     # no agent hands it on: no start line
        row = self.row(s, "cc")
        self.assertEqual((row["driver"], row["by"], row["prompt"]), ("local", "local", "cc-skill"))
        self.assertNotIn("start", row)
        described = self.agent(s, "kit.app.describe", "{ app = 'cc' }")
        self.assertEqual((described["by"], described["decl"]["driver"]), ("local", "local"))
        self.assertNotIn("minutes", described["decl"])                    # its run has no end
        self.assertFalse(self.agent(s, "kit.app.declare", DRIVEN)["changed"])
        m = next(a for a in self.lua(s, "WuxianKit:Manifest()")["apps"] if a["id"] == "cc")
        self.assertEqual((m["driver"], m["by"]), ("local", "local"))
        self.assertNotIn("start", m)
        for decl in (f"{{ app = 'ag', {LOCAL}, prompt = 'ag' }}", f"{{ app = 'ag', {LOCAL}, prompt = 'ag', driver = 'agent' }}"):
            st = self.agent(s, "kit.app.declare", decl)
            self.assertNotIn("driver", st, decl)                          # agent is no mark at all
            self.assertEqual((st["by"], self.row(s, "ag")["by"]), ("agent", "agent"), decl)
            self.assertNotIn("driver", self.row(s, "ag"), decl)
            described = self.agent(s, "kit.app.describe", "{ app = 'ag' }")["decl"]
            self.assertNotIn("driver", described, decl)
            self.assertEqual(described["minutes"], 120, decl)
            self.assertIn("ag", st["start"], decl)
        self.assertFalse(st["changed"])                                   # agent given is none given
        st = self.agent(s, "kit.app.declare", f"{{ app = 'cc', title = 'Data', {LOCAL} }}")   # whole: the mark goes
        self.assertTrue(st["changed"])
        self.assertNotIn("driver", st)
        self.assertEqual(st["by"], "agent")
        s2 = self.start(s.reload())                                       # kept through a reload
        self.agent(s2, "kit.app.declare", DRIVEN)
        s3 = self.start(s2.reload())
        self.assertEqual((self.row(s3, "cc")["driver"], self.row(s3, "cc")["by"]), ("local", "local"))
        self.assertEqual(s3.chat().count("no longer holds"), 0)

    def test_refused(self):
        s = self.start()
        for value in ("'program'", "'prompt'", "'LOCAL'", "''", "true", "{}"):
            self.assertIn("driver", self.fails(s, "kit.app.declare", f"{{ app = 'x', {LOCAL}, driver = {value} }}"), value)
        err = self.fails(s, "kit.app.declare", "{ app = 'x', driver = 'local' }")   # an agent's own: no local label
        self.assertIn("driver local is for an app 无限工坊 declares for a local extension", err)
        self.assertIn("driver local is for", self.fails(s, "kit.app.open", "{ app = 't', temp = { driver = 'local' } }"))
        self.assertIn("no argument driver", self.fails(s, "kit.app.open", "{ app = 'x', driver = 'local' }"))
        err = self.fails(s, "kit.app.declare", f"{{ app = 'x', {LOCAL}, driver = 'local', minutes = 30 }}")
        self.assertIn("minutes does not go with driver local", err)       # it does not end by the clock
        self.assertEqual([a["id"] for a in py(s.ns.AppList())], [])
        ok, err = s.lua.eval(b"pcall(WuxianKit.App, WuxianKit, 'mine', { title = 'Mine', driver = 'local' })")
        self.assertFalse(ok)
        self.assertIn("driver local is for", err.decode())
        s.lua.execute(f"WuxianKit:App('mine', {{ title = 'Mine', {LOCAL}, driver = 'local' }})".encode())
        st = self.agent(s, "kit.app.status", "{ app = 'mine' }")
        self.assertEqual((st["driver"], st["by"]), ("local", "local"))

    def test_a_run_without_an_end(self):
        """no ends in the status, the row or kit.app, and no line in the chat when it starts; it runs on past any
        number of minutes; kit.app.open takes no minutes for it"""
        s = self.start()
        self.agent(s, "kit.app.declare", DRIVEN)
        s.lines.clear()
        st = self.agent(s, "kit.app.open", "{ app = 'cc' }")
        self.assertEqual((st["on"], st["driver"], st["by"]), (True, "local", "local"))
        self.assertNotIn("ends", st)
        self.assertNotIn("ends", self.row(s, "cc"))
        self.assertEqual(self.app_events(s, "cc"), [{"app": "cc", "on": True}])
        self.assertEqual(s.chat(), "")
        s.run(13 * 3600, dt=1)                                            # (an agent's app ends after 12 hours at most)
        self.assertIs(self.status(s, "cc")["on"], True)
        s.lua.execute(b"WuxianKit:Emit('demo.a', 1)")
        self.assertEqual(len(self.wakes(s, "cc")), 1)                     # and it hears
        self.assertIn("so no minutes", self.fails(s, "kit.app.open", "{ app = 'cc', minutes = 30 }"))
        s2 = self.start(s.reload())                                       # through a reload too
        self.assertIs(self.status(s2, "cc")["on"], True)
        self.assertEqual(self.app_events(s2, "cc"), [])

    def test_its_controls_and_stops(self):
        """controls and stop as any other's; of its stops the chat has no line (its card tells)"""
        s = self.start()
        self.agent(s, "kit.app.declare", DRIVEN)
        self.agent(s, "kit.app.open", "{ app = 'cc' }")
        s.lines.clear()
        self.assertTrue(s.lua.eval(b"(WuxianKit:AppControl('cc', 'submit'))"))
        self.assertTrue(s.lua.eval(b"(WuxianKit:AppControl('cc', 'stop'))"))
        self.assertEqual(self.app_events(s, "cc")[-1], {"app": "cc", "on": False, "why": "player"})
        st = self.agent(s, "kit.app.status", "{ app = 'cc' }")
        self.assertEqual((st["on"], st["why"], st["driver"]), (False, "player", "local"))
        self.agent(s, "kit.app.open", "{ app = 'cc' }")
        self.agent(s, "kit.app.stop", "{ app = 'cc' }")
        self.assertEqual(self.app_events(s, "cc")[-1], {"app": "cc", "on": False, "why": "stopped"})
        self.agent(s, "kit.app.open", "{ app = 'cc' }")
        st = self.agent(s, "kit.app.stop", "{ app = 'cc', why = 'extension' }")   # 无限工坊's: its program stopped
        self.assertEqual((st["on"], st["why"]), (False, "extension"))
        self.assertEqual(self.app_events(s, "cc")[-1], {"app": "cc", "on": False, "why": "extension"})
        self.assertIn("why is stopped", self.fails(s, "kit.app.stop", "{ app = 'cc', why = 'player' }"))
        self.agent(s, "kit.app.open", "{ app = 'cc' }")
        self.agent(s, "kit.app.forget", "{ app = 'cc' }")
        self.assertEqual(s.chat(), "")

    def test_its_lease(self):
        """the lease as ever: no heartbeat within it and the run stops, why left, which the chat says in the local
        part's words (no agent); a run kept from the last session that lapsed meanwhile stops without a line"""
        s = self.start()
        self.agent(s, "kit.app.declare", LEASED)
        self.agent(s, "kit.app.open", "{ app = 'cc' }")
        s.lines.clear()
        for _ in range(5):                                                # heartbeats: it runs on
            s.run(40)
            self.assertIs(self.agent(s, "kit.app.status", "{ app = 'cc' }")["on"], True)
        s.run(70)
        self.assertEqual(self.app_events(s, "cc")[-1], {"app": "cc", "on": False, "why": "left"})
        self.assertEqual(s.lines, ["|cffd8a85a[WuxianKit]|r Data: its local program does not answer, stopped"])
        s.ns.SetLanguage(b"zhCN")
        self.agent(s, "kit.app.open", "{ app = 'cc' }")
        s.lines.clear()
        s.run(70)
        self.assertEqual(s.lines, ["|cffd8a85a[扩展框架]|r Data：本机端无响应，已停止"])
        self.assertNotIn("Agent", s.chat())
        self.agent(s, "kit.app.open", "{ app = 'cc' }")
        s2 = s.reload(t0=s.now() + 600)                                   # back ten minutes later: lapsed meanwhile
        self.start(s2)
        self.assertEqual(self.app_events(s2, "cc"), [{"app": "cc", "on": False, "why": "left"}])
        self.assertEqual(self.status(s2, "cc")["why"], "left")
        self.assertEqual([line for line in s2.lines if "Data" in line], [])


@unittest.skipIf(lupa is None, "lupa (Lua 5.1 for Python) is not installed")
class Card(Base):
    def start(self, s=None, **kw):
        s = super().start(s, **kw)
        self.online(s)
        return s

    def panel(self, s, app):
        s.lua.execute(f"__host = __host or CreateFrame('Frame', nil, UIParent) "
                      f"__p = WuxianKit:AppPanel({app!r}, __host, 320)".encode())
        return s.g("__p")

    def redraw(self, s):
        s.lua.execute(b"__p:Refresh()")
        return texts(s.g("__p"))

    def test_the_states(self):
        """its program not running (no list yet, or the list says so); running and about to open it; open; stopped by
        the player, with 开始; its lease ran out; never 交给 AI, never a word of an agent"""
        s = self.start()
        self.agent(s, "kit.app.declare", LEASED)
        self.agent(s, "kit.app.declare", f"{{ app = 'ag', title = 'Agent', {LOCAL}, prompt = 'ag' }}")
        p = self.panel(s, "ag")
        self.assertEqual((texts(p)[0], labels(p)), ("Ready to connect an agent", ["Hand to AI"]))   # an agent's: as ever
        seen = []

        def card():
            seen.extend(self.redraw(s) + labels(p))
            return self.redraw(s), labels(p)
        p = self.panel(s, "cc")
        self.assertEqual(card(), (["Local part not running"], []))        # no list yet
        self.roster(s, running=False)
        self.assertEqual(card(), (["Local part not running"], []))
        self.roster(s)
        self.assertEqual(card(), (["Waiting"], []))                       # its program runs: it opens the app next
        self.agent(s, "kit.app.open", "{ app = 'cc' }")
        self.assertEqual(card(), (["Local part running"], ["Stop", "Submit"]))
        s.ns.SetLanguage(b"zhCN")
        self.assertEqual(card(), (["本机端运行中"], ["停止", "Submit"]))
        click(button(p, "停止"))
        self.assertEqual(card(), (["已停止"], ["开始"]))
        self.assertTrue(button(p, "开始")[b"primary"])
        self.roster(s, running=False)                                     # its program is not there: nobody would drive it
        self.assertEqual(card(), (["已停止", "本机端未运行"], ["开始"]))
        self.assertIs(button(p, "开始")[b"enabled"], False)
        click(button(p, "开始"))
        self.assertIs(self.status(s, "cc")["on"], False)
        s.ns.SetLanguage(b"enUS")
        self.assertEqual(card(), (["Stopped", "Local part not running"], ["Start"]))
        self.roster(s, on=False)                                          # nor one turned off in 无限工坊's App
        self.assertIs(button(p, "Start")[b"enabled"], False)
        self.roster(s)
        self.agent(s, "kit.app.open", "{ app = 'cc' }")
        s.run(70)
        self.call(s, "kit.app.status", "{ app = 'cc' }")                  # (an addon's call: no heartbeat)
        self.assertEqual(card(), (["Local part not responding, stopped"], []))
        s.ns.SetLanguage(b"zhCN")
        self.assertEqual(card(), (["本机端无响应，已停止"], []))
        self.agent(s, "kit.app.open", "{ app = 'cc' }")
        self.agent(s, "kit.app.stop", "{ app = 'cc', why = 'extension' }")   # stopped with its program
        self.roster(s, running=False)
        self.assertEqual(card(), (["本机端未运行"], []))
        for text in seen:
            self.assertNotIn("Agent", text)
            self.assertNotIn("AI", text)
            self.assertNotIn("本机扩展", text)

    def test_the_player_starts_it_again(self):
        """开始, after the player's own stop and while its program runs: the run begins, kit.app on = true as ever
        (无限工坊 sees it and goes on feeding it), nothing in the chat; its lease counts from then"""
        s = self.start()
        self.agent(s, "kit.app.declare", LEASED)
        self.roster(s)
        self.agent(s, "kit.app.open", "{ app = 'cc' }")
        p = self.panel(s, "cc")
        click(button(p, "Stop"))
        told = len(self.app_events(s, "cc"))
        s.lines.clear()
        self.assertEqual(self.lua(s, "{ __ns.AppStartable('cc') }"), [True])
        click(button(p, "Start"))
        self.assertEqual(self.app_events(s, "cc")[told:], [{"app": "cc", "on": True}])
        self.assertEqual(s.chat(), "")
        st = self.status(s, "cc")
        self.assertEqual((st["on"], st["present"], st["lease"]), (True, False, 60))   # nobody heard from yet
        self.assertNotIn("seen", st)
        self.assertEqual((self.redraw(s), labels(p)), (["Local part running"], ["Stop", "Submit"]))
        self.assertEqual(self.lua(s, "{ __ns.AppStartable('cc') }"), [False])          # it runs
        s.run(40)
        self.agent(s, "kit.app.status", "{ app = 'cc' }")                 # 无限工坊's heartbeat: it goes on
        s.run(40)
        self.assertIs(self.status(s, "cc")["on"], True)
        s.run(70)                                                         # none: its lease
        self.assertEqual(self.app_events(s, "cc")[-1], {"app": "cc", "on": False, "why": "left"})

    def test_only_one_a_program_drives(self):
        s = self.start()
        self.roster(s)
        self.opens(s, f"{{ app = 'ag', title = 'Agent', {LOCAL}, hear = {{ 'bus:demo.*' }}, controls = {{ 'stop' }} }}")
        s.lua.execute(b"WuxianKit:AppControl('ag', 'stop')")
        self.assertEqual(self.lua(s, "{ __ns.AppStartable('ag') }"), [False])
        self.assertIs(s.ns.AppStart(b"ag"), False)
        self.assertIs(self.status(s, "ag")["on"], False)
        self.assertEqual(self.lua(s, "{ __ns.AppStartable('nope') }"), [False])
        self.radio(s)
        self.agent(s, "kit.app.declare", DRIVEN.replace("'bus:demo.*'", "'radio:news'"))
        self.assertEqual(self.lua(s, "{ __ns.AppStartable('cc') }"), [True])
        s.ns.Switch(b"rx", False)                                         # what it hears is off
        st = self.status(s, "cc")
        self.assertEqual(st["blocked"], "Needs the Radio extension on")
        self.assertEqual(self.lua(s, "{ __ns.AppStartable('cc') }"), [False, "blocked"])
        self.assertIs(s.ns.AppStart(b"cc"), False)
        self.call(s, "kit.local.set", "{ extensions = {} }")
        self.assertEqual(self.lua(s, "{ __ns.AppStartable('cc') }"), [False, "local"])

    def test_no_link_first(self):
        s = self.start()
        self.agent(s, "kit.app.declare", DRIVEN)
        self.online(s, False)
        self.assertEqual(texts(self.panel(s, "cc"))[0], "Wuxian Workshop not connected")

    def test_less_and_more_are_not_drawn_with_the_activity(self):
        """an app with pace has its 活跃度 among its options: no 少说 / 多说 on its card (the slash command has them);
        one without pace has the buttons"""
        s = self.start()
        self.opens(s, "{ app = 'g', title = 'Guild', hear = { 'bus:demo.*' }, pace = true, "
                      "controls = { 'less', 'more', 'mute', 'stop' }, lease = 0 }")
        p = self.panel(s, "g")
        self.assertEqual(labels(p), ["Stop", "Mute", "Quiet", "Normal", "Lively"])
        self.opens(s, "{ app = 'v', title = 'Voice', hear = { 'bus:demo.*' }, controls = { 'less', 'more', 'stop' }, "
                      "lease = 0 }")
        self.assertEqual(labels(self.panel(s, "v")), ["Stop", "Less", "More"])


@unittest.skipIf(lupa is None, "lupa (Lua 5.1 for Python) is not installed")
class LocalOptions(Base):
    def start(self, s=None, **kw):
        s = super().start(s, **kw)
        self.online(s)
        return s

    def set(self, s, options, where="local", more="", extra=""):
        return self.call(s, "kit.local.set", f"{{ extensions = {{ {{ id = 'cocreate', title = 'Co-create', "
                                             f"where = {where!r}, on = true, {more} options = {options} }}, {extra} }} }}")

    def kept(self, s):
        return py(s.lua.eval(b"__ns.LocalList()"))

    def window(self, s, page):
        s.lua.execute(f"WuxianKit:Window({page!r})".encode())
        return s.g("WuxianKitWindow")

    def test_kept_and_skipped(self):
        s = self.start()
        self.assertEqual(self.set(s, OPTIONS), {"count": 1})
        kept = self.kept(s)[0]["options"]
        self.assertEqual([o["name"] for o in kept], ["auto", "every", "folder", "mode"])   # in their order
        self.assertEqual(kept[0], {"name": "auto", "kind": "boolean", "title": "Sync by itself", "value": True,
                                   "default": True, "hint": "After each snapshot"})
        self.assertEqual(kept[1], {"name": "every", "kind": "number", "title": "Every", "value": 10, "min": 5,
                                   "max": 60, "step": 5, "unit": "min"})
        self.assertEqual(kept[2], {"name": "folder", "kind": "text", "title": "Folder", "value": "C:/data",
                                   "hint": "Where it saves"})
        self.assertEqual(kept[3]["choices"], [{"value": "fast", "label": "Fast"}, {"value": "full", "label": "Full"}])
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
        """a local extension's page: its options last, under 选项 (they are all it has): a check, a number box with
        its unit, a row of choices; then the texts, under one line that says where they are changed, a line each
        (title: value; none set: its default, else 默认), no box"""
        s = self.start()
        self.set(s, OPTIONS)
        w = self.window(s, "local:cocreate")
        body = texts(w[b"body"])
        self.assertNotIn("Local options", body)
        self.assertEqual(body[body.index("Options"):],
                         ["Options", "After each snapshot", "Every", "min", "Mode",
                          "Changed in the Wuxian Workshop app", "Folder: C:/data"])
        self.assertEqual([c[b"label"][b"text"].decode() for c in shown(w[b"checks"])], ["Sync by itself"])
        self.assertEqual([e[b"text"].decode() for e in shown(w[b"edits"])], ["10"])   # the number's; no text box
        self.assertEqual(labels(w), ["Fast", "Full"])
        self.assertTrue(button(w, "Fast")[b"primary"])
        s.lua.execute(b"__ns.SetLanguage('zhCN')")
        self.assertEqual(texts(w[b"body"])[-3:], ["Mode", "以下在无限工坊 App 中修改", "Folder：C:/data"])
        self.set(s, """{ { name = 'folder', kind = 'text', title = 'Folder |cffff0000x|r', value = '' },
			{ name = 'name', kind = 'text', title = 'Name', value = '', default = 'Ann |cffff0000x|r' },
			{ name = 'note', kind = 'text', title = 'Note', value = 'kept', default = 'none' } }""")
        s.run(0.1)
        self.assertEqual(texts(w[b"body"])[-5:], ["选项", "以下在无限工坊 App 中修改", "Folder ||cffff0000x||r：默认",
                                                  "Name：Ann ||cffff0000x||r", "Note：kept"])
        self.assertEqual(shown(w[b"edits"]), [])

    def test_a_change_goes_to_the_workshop(self):
        """the player changes one: kit.local.option {extension, name, value} (to 无限工坊 too), the new value shown at
        once and marked; the next list confirms it, or puts back what 无限工坊 holds"""
        s = self.start()
        self.set(s, OPTIONS)
        w = self.window(s, "local:cocreate")
        s.lua.execute(b"__events = {} __emitted = {}")
        check = lambda: shown(w[b"checks"])[0]
        click(check())
        self.assertEqual(self.events(s, "kit.local.option"), [{"extension": "cocreate", "name": "auto", "value": False}])
        self.assertIn("kit.local.option", py(s.g("__emitted")))          # forwarded to 无限工坊
        self.assertFalse(check()[b"checked"])                             # shown at once
        self.assertEqual(check()[b"label"][b"text"].decode(), "Sync by itself  |cffd8a85aUnconfirmed|r")
        auto = self.kept(s)[0]["options"][0]
        self.assertEqual((auto["value"], auto["pending"]), (True, {"value": False}))   # what 无限工坊 gave is kept
        click(button(w, "Full"))
        type_into(shown(w[b"edits"])[0], "23")                            # on its step, in its range
        type_into(shown(w[b"edits"])[0], "many")                          # not a number: nothing
        type_into(shown(w[b"edits"])[0], "900")
        click(button(w, "Full"))                                          # the same again: nothing
        self.assertEqual([(e["name"], e["value"]) for e in self.events(s, "kit.local.option")],
                         [("auto", False), ("mode", "full"), ("every", 25), ("every", 60)])
        self.assertTrue(button(w, "Full")[b"primary"])
        self.assertIn("Every  |cffd8a85aUnconfirmed|r", texts(w[b"body"]))
        self.set(s, OPTIONS.replace("value = true", "value = false"))     # 无限工坊 took the first, not the others
        s.run(0.1)
        self.assertFalse(check()[b"checked"])
        self.assertEqual(check()[b"label"][b"text"].decode(), "Sync by itself")
        self.assertTrue(button(w, "Fast")[b"primary"])
        self.assertEqual([e[b"text"].decode() for e in shown(w[b"edits"])], ["10"])
        self.assertFalse([t for t in texts(w[b"body"]) if "Unconfirmed" in t])
        self.assertEqual(len(self.events(s, "kit.local.option")), 4)      # the list itself tells nothing
        self.assertEqual(py(s.lua.eval(b"{ __ns.SetLocalOption('cocreate', 'folder', 'D:/x') }")), [False])   # a text
        self.assertEqual(py(s.lua.eval(b"{ __ns.SetLocalOption('cocreate', 'nope', true) }")), [False])
        self.assertEqual(py(s.lua.eval(b"{ __ns.SetLocalOption('other', 'auto', true) }")), [False])
        self.assertEqual(len(self.events(s, "kit.local.option")), 4)

    def test_no_list_in_time_and_it_goes_back(self):
        """a value 无限工坊 does not confirm within ten seconds is back to what it gave, the mark gone; one changed
        again waits its own ten seconds"""
        s = self.start()
        self.set(s, OPTIONS)
        w = self.window(s, "local:cocreate")
        check = lambda: shown(w[b"checks"])[0]
        click(check())
        s.run(6)
        self.assertFalse(check()[b"checked"])
        click(button(w, "Full"))
        s.run(5)                                                          # 11 seconds after the first, 5 after the second
        self.assertTrue(check()[b"checked"])
        self.assertEqual(check()[b"label"][b"text"].decode(), "Sync by itself")
        self.assertTrue(button(w, "Full")[b"primary"])
        click(button(w, "Fast"))                                          # back to what 无限工坊 gave: told too
        self.assertEqual([(e["name"], e["value"]) for e in self.events(s, "kit.local.option")],
                         [("auto", False), ("mode", "full"), ("mode", "fast")])
        s.run(11)
        self.assertTrue(button(w, "Fast")[b"primary"])
        self.assertNotIn("pending", self.kept(s)[0]["options"][3])
        self.assertFalse([t for t in texts(w[b"body"]) if "Unconfirmed" in t])

    def test_a_number_without_a_step_is_not_rounded(self):
        s = self.start()
        self.set(s, "{ { name = 'rate', kind = 'number', title = 'Rate', value = 1.5, min = 0, max = 10 }, "
                    "{ name = 'free', kind = 'number', title = 'Free', value = 0 } }")
        w = self.window(s, "local:cocreate")
        type_into(shown(w[b"edits"])[0], "2.37")
        type_into(shown(w[b"edits"])[1], "-0.004")
        type_into(shown(w[b"edits"])[0], "12.5")                          # its range holds
        self.assertEqual([(e["name"], e["value"]) for e in self.events(s, "kit.local.option")],
                         [("rate", 2.37), ("free", -0.004), ("rate", 10)])

    def test_dim_while_the_workshop_is_not_linked(self):
        """无限工坊 not linked: a line says so, the options show dim and nothing changes them (nobody would take it)"""
        s = self.start()
        self.set(s, OPTIONS)
        self.online(s, False)
        w = self.window(s, "local:cocreate")
        body = texts(w[b"body"])
        self.assertEqual(body[body.index("Options"):][:2], ["Options", "Wuxian Workshop not connected"])
        check, edit = shown(w[b"checks"])[0], shown(w[b"edits"])[0]
        self.assertEqual((check[b"enabled"], edit[b"enabled"], button(w, "Full")[b"enabled"]), (False, False, False))
        click(check)
        click(button(w, "Full"))
        self.assertTrue(check[b"checked"])
        self.assertEqual(self.events(s, "kit.local.option"), [])
        self.assertEqual(py(s.lua.eval(b"{ __ns.SetLocalOption('cocreate', 'auto', false) }")), [False])
        s.ns.SetLanguage(b"zhCN")
        self.assertIn("无限工坊未连接", texts(w[b"body"]))
        self.online(s)
        s.lua.execute(b"WuxianKit:Window()")
        check, edit = shown(w[b"checks"])[0], shown(w[b"edits"])[0]
        self.assertEqual((check[b"enabled"], edit[b"enabled"], button(w, "Full")[b"enabled"]), (True, True, True))
        self.assertNotIn("无限工坊未连接", texts(w[b"body"]))
        click(check)
        self.assertEqual(len(self.events(s, "kit.local.option")), 1)

    def test_the_row_of_one_in_the_game_too(self):
        """one extension, both halves on one page: the game's options under 游戏选项, then 本机选项"""
        s = self.start()
        s.lua.execute(b"local e = WuxianKit:Extension('cocreate', { title = 'Co-create' }) "
                      b"e:Option('show', { title = 'Show my name', default = true })")
        s.run(0.5)
        w = self.window(s, "cocreate")
        self.assertIn("Options", texts(w[b"body"]))                       # by itself: 选项
        self.set(s, "{ { name = 'auto', kind = 'boolean', title = 'Sync by itself', value = true } }", where="both")
        s.run(0.1)
        body = texts(w[b"body"])
        self.assertNotIn("Options", body)
        self.assertLess(body.index("Game options"), body.index("Local options"))
        self.assertNotIn("Capabilities", body)        # on, and nothing to call: no heading (not "Shown when enabled")
        checks = [c[b"label"][b"text"].decode() for c in shown(w[b"checks"])]
        self.assertEqual(checks[-2:], ["Show my name", "Sync by itself"])
        click(shown(w[b"checks"])[-1])
        self.assertEqual(self.events(s, "kit.local.option")[-1], {"extension": "cocreate", "name": "auto",
                                                                   "value": False})
        self.assertNotIn({"extension": "cocreate", "name": "auto", "value": False}, self.events(s, "kit.option"))
        s.ns.SetLanguage(b"zhCN")
        body = texts(w[b"body"])
        self.assertLess(body.index("游戏选项"), body.index("本机选项"))


@unittest.skipIf(lupa is None, "lupa (Lua 5.1 for Python) is not installed")
class CoreTopics(Base):
    def test_kit_and_app_are_the_cores_own(self):
        """WuxianKit:Emit refuses kit.* and app.* (an extension's ext:Emit too: no extension is named kit or app);
        the core's own events go on as ever"""
        s = self.start()
        for topic in ("kit.local.option", "kit.app", "kit.option", "kit.anything", "kit", "app.guild", "app"):
            ok, err = s.lua.eval(f"pcall(WuxianKit.Emit, WuxianKit, {topic!r}, {{ app = 'x', on = true }})".encode())
            self.assertFalse(ok, topic)
            self.assertIn(f"kit.* and app.* are WuxianKit's own topics (not {topic})", err.decode())
            self.assertEqual(self.events(s, topic), [], topic)
        ok, err = s.lua.eval(b"pcall(function() WuxianKit:Extension('kit'):Emit('local.option', {}) end)")
        self.assertFalse(ok)
        ok, err = s.lua.eval(b"pcall(WuxianKit.Extension, WuxianKit, 'app', { title = 'App' })")
        self.assertFalse(ok)
        self.assertIn("app is the apps' own", err.decode())
        s.lua.execute(b"WuxianKit:Emit('kitten.mew', {}) WuxianKit:Emit('apple.pie', {}) "
                      b"WuxianKit:Emit('demo.kit.app', {})")              # others go
        self.assertEqual([len(self.events(s, t)) for t in ("kitten.mew", "apple.pie", "demo.kit.app")], [1, 1, 1])
        self.opens(s, "{ app = 'notes', hear = { 'bus:demo.*' }, lease = 0 }")   # the core's own: as ever
        s.lua.execute(b"WuxianKit:Emit('demo.a', 1)")
        self.assertEqual(self.app_events(s, "notes")[-1]["on"], True)
        self.assertEqual(len(self.wakes(s, "notes")), 1)
        ev = next(e for e in self.lua(s, "WuxianKit:Manifest()")["extensions"] if e["id"] == "kit")["events"]
        self.assertIn("kit.local.option", [e["topic"] for e in ev])
        self.assertIn("kit.local", [e["topic"] for e in ev])


if __name__ == "__main__":
    unittest.main()
