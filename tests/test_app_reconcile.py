"""Apps, what the release review added (ARCHITECTURE section 10): Reconcile, the one place that decides whether an app's
run runs, waits or stops (a run kept through a reload waits for a source, a facet, an extension or its check that is not
there yet, heard once it is, stopped half a minute on; an open that cannot start is an answer; a temporary app reopened
the second its time ends); kit.app.forget and kit.app.describe; kit.app.declare as the whole declaration; the places of
a local extension's apps; a declaration that no longer holds; present; said by the day; a character's runs untouched by
another's; the manifest's revision."""
from kitmock import py
from test_apps import AppCase, FAKES, SALON
from test_facets import PROBE
from test_sources import RADIO

ME, OTHER = "Player-1-00000001", "Player-1-00000002"


class Case(AppCase):
    def radio(self, s):
        """the radio's addon loads (another addon's extension: on a moment later)"""
        s.lua.execute(RADIO)
        s.run(0.5)
        return s

    def row(self, s, app):
        return next((a for a in py(s.ns.AppList()) if a["id"] == app), None)

    def status(self, s, app):
        return py(s.ns.AppStatus(app.encode()))               # (no heartbeat)

    def app_events(self, s, app):
        return [e for e in self.events(s, "kit.app") if e["app"] == app]

    def run_of(self, s, app, guid=ME):
        return self.lua(s, f"(function() local c = (WuxianKitDB.apps[{app!r}] or {{}}).chars or {{}} "
                           f"return (c[{guid!r}] or {{}}).run end)()")


class Waits(Case):
    def mix(self):
        """a run of mix (it hears the radio) kept through a reload: the radio's addon has not loaded"""
        s = self.radio(self.start())
        self.agent(s, "kit.app.declare", "{ app = 'fan', title = 'Fan', hear = { 'radio:news' }, lease = 0 }")
        st = self.opens(s, "{ app = 'mix', title = 'Mix', hear = { 'radio:jazz', 'bus:demo.*' }, lease = 0 }")
        return self.start(s.reload()), st["ends"]

    def test_a_run_waits_for_its_source_and_is_heard_once_it_is_there(self):
        s, ends = self.mix()
        waiting = {"app": "mix", "on": True, "ends": ends, "waiting": "Needs the source radio"}
        self.assertEqual(self.app_events(s, "mix"), [waiting])             # told once, at the login
        st = self.agent(s, "kit.app.status", "{ app = 'mix' }")
        self.assertEqual((st["on"], st["waiting"], st["ends"]), (True, "Needs the source radio", ends))
        self.assertNotIn("blocked", st)
        row = self.row(s, "mix")
        self.assertEqual((row["on"], row["waiting"], row["temp"]), (True, "Needs the source radio", False))
        self.assertNotIn("blocked", row)
        s.lua.execute(b"WuxianKit:Emit('demo.a', 1)")                      # nothing is heard while it waits
        self.assertEqual(self.wakes(s, "mix"), [])
        s.run(10)
        self.assertEqual(self.app_events(s, "mix"), [waiting])             # nor told again each second
        self.radio(s)                                                      # the radio's addon loads after all
        self.assertEqual(self.app_events(s, "mix"), [waiting, {"app": "mix", "on": True, "ends": ends}])
        self.assertNotIn("waiting", self.agent(s, "kit.app.status", "{ app = 'mix' }"))
        self.assertNotIn("waiting", self.row(s, "mix"))
        s.lua.execute(b"__radio('jazz', { tune = 'late' }) WuxianKit:Emit('demo.b', 2)")
        self.assertEqual([w["items"][0]["source"] for w in self.wakes(s, "mix")], ["radio", "bus"])
        s.run(40)                                                          # and it runs on
        self.assertIs(self.status(s, "mix")["on"], True)

    def test_a_run_that_still_waits_half_a_minute_on_stops(self):
        s, ends = self.mix()
        s.lines.clear()
        s.run(27)                                                          # 28 seconds after the login
        self.assertEqual(self.status(s, "mix")["waiting"], "Needs the source radio")
        s.run(3.5)
        self.assertEqual(self.app_events(s, "mix")[-1], {"app": "mix", "on": False, "why": "extension"})
        self.assertIn("Mix: stopped. Needs the source radio", s.chat())
        st = self.status(s, "mix")
        self.assertEqual((st["on"], st["why"], st["blocked"]), (False, "extension", "Needs the source radio"))
        self.assertNotIn("waiting", st)
        self.radio(s)                                                      # too late: it does not start by itself
        st = self.status(s, "mix")
        self.assertEqual((st["on"], st["why"]), (False, "extension"))
        self.assertNotIn("blocked", st)
        self.assertEqual(len(self.app_events(s, "mix")), 2)

    def test_an_open_that_cannot_start_is_an_answer(self):
        s, ends = self.mix()
        told = len(self.events(s, "kit.app"))
        s.lines.clear()
        st = self.agent(s, "kit.app.open", "{ app = 'fan' }")              # not running: it does not start
        self.assertEqual((st["on"], st["blocked"]), (False, "Needs the source radio"))
        self.assertNotIn("waiting", st)
        self.assertEqual(len(self.events(s, "kit.app")), told)             # nothing happened: nothing told
        self.assertEqual(s.chat(), "")
        self.assertIsNone(self.run_of(s, "fan"))
        now = s.lua.eval(b"time()")
        st = self.agent(s, "kit.app.open", "{ app = 'mix', minutes = 5 }")   # one that waits goes on waiting
        self.assertEqual((st["on"], st["waiting"], st["ends"]), (True, "Needs the source radio", now + 300))
        self.assertNotIn("blocked", st)
        self.assertEqual(self.events(s, "kit.app")[-1],
                         {"app": "mix", "on": True, "ends": now + 300, "waiting": "Needs the source radio"})
        self.radio(s)
        self.assertEqual(self.agent(s, "kit.app.open", "{ app = 'fan' }")["on"], True)
        self.assertEqual(self.events(s, "kit.app")[-2:], [{"app": "mix", "on": True, "ends": now + 300},
                                                          {"app": "fan", "on": True, "ends": now + 7200}])

    def test_the_source_s_extension_kept_off_stops_it_at_once(self):
        s, ends = self.mix()
        s.ns.Switch(b"rx", False)                                          # the player keeps the radio off
        self.assertEqual(self.status(s, "mix")["waiting"], "Needs the source radio")
        s.lines.clear()
        self.radio(s)                                                      # its addon loads: off, so not on its way
        self.assertEqual(self.app_events(s, "mix")[-1], {"app": "mix", "on": False, "why": "extension"})
        self.assertIn("Mix: stopped. Needs the Radio extension on", s.chat())
        s.ns.Switch(b"rx", True)
        st = self.status(s, "mix")
        self.assertEqual((st["on"], st["why"]), (False, "extension"))      # the player's to start again
        self.assertNotIn("blocked", st)

    def test_a_run_waits_for_its_facet(self):
        s = self.start()
        s.lua.execute(PROBE)
        s.run(0.1)
        ends = self.opens(s, "{ app = 'look', hear = { 'bus:demo.*' }, see = { 'probe' }, lease = 0 }")["ends"]
        self.assertEqual(self.lua(s, "__ons"), 1)
        s2 = self.start(s.reload())
        waiting = {"app": "look", "on": True, "ends": ends, "waiting": "Needs the state probe"}
        self.assertEqual(self.app_events(s2, "look"), [waiting])
        self.assertEqual(self.agent(s2, "kit.app.state", "{ app = 'look' }")["state"], {})
        s2.lua.execute(b"WuxianKit:Emit('demo.a', 1)")
        self.assertEqual(self.wakes(s2, "look"), [])
        s2.lua.execute(PROBE)
        s2.run(0.1)
        self.assertEqual(self.app_events(s2, "look"), [waiting, {"app": "look", "on": True, "ends": ends}])
        self.assertEqual((self.lua(s2, "__ons"), self.lua(s2, "__offs")), (1, 0))   # looked at once it runs
        s2.lua.execute(b"WuxianKit:Emit('demo.b', 2)")
        self.assertEqual(self.wakes(s2, "look")[0]["state"], {"probe": {"n": 1}})

    APP = b"WuxianKit:App('xa', { title = 'XA', extension = 'xg', hear = { 'bus:xg.*' } })"

    def test_a_run_waits_for_the_extension_it_belongs_to(self):
        s = self.start()
        s.lua.execute(b"WuxianKit:Extension('xg', { title = 'XG' })")
        s.run(0.5)
        s.lua.execute(self.APP)
        ends = self.call(s, "kit.app.open", "{ app = 'xa' }")["ends"]
        s2 = self.start(s.reload())
        s2.lua.execute(self.APP)                                           # its addon's app file ran, the extension's not
        waiting = {"app": "xa", "on": True, "ends": ends, "waiting": "Its extension xg is not loaded"}
        self.assertEqual(self.app_events(s2, "xa"), [waiting])
        st = self.status(s2, "xa")
        self.assertEqual((st["on"], st["extension"], st["waiting"]), (True, False, "Its extension xg is not loaded"))
        s2.lua.execute(b"WuxianKit:Extension('xg', { title = 'XG' })")
        self.assertEqual(self.app_events(s2, "xa"), [waiting])             # registered, on a frame later: one reason
        s2.run(0.5)
        self.assertEqual(self.app_events(s2, "xa"), [waiting, {"app": "xa", "on": True, "ends": ends}])
        s2.lua.execute(b"WuxianKit:Emit('xg.a', 1)")
        self.assertEqual(len(self.wakes(s2, "xa")), 1)
        s3 = self.start(s2.reload())                                       # never there: an open is refused, with why
        s3.lua.execute(self.APP)
        s3.run(31)
        self.assertEqual(self.app_events(s3, "xa")[-1], {"app": "xa", "on": False, "why": "extension"})
        self.assertIn("XA: stopped. Its extension xg is not loaded", s3.chat())
        st = self.call(s3, "kit.app.open", "{ app = 'xa' }")
        self.assertEqual((st["on"], st["blocked"]), (False, "Its extension xg is not loaded"))

    CLUB = b"""
WuxianKit:App('club', { title = 'Club', hear = { 'bus:demo.*' },
	check = function() __asked = (__asked or 0) + 1 if not __inguild then return 'Not in a guild' end end })
"""

    def club(self, inguild):
        """a run of an addon's app kept through a reload; its check reads what the client may not have yet"""
        s = self.start()
        s.lua.execute(b"__inguild = true")
        s.lua.execute(self.CLUB)
        ends = self.call(s, "kit.app.open", "{ app = 'club' }")["ends"]
        s2 = s.reload()
        s2.lua.execute(f"__inguild = {inguild}".encode())
        s2.lua.execute(self.CLUB)                                          # declared before the login, as an addon does
        return self.start(s2), ends

    def test_a_check_that_says_no_right_after_the_login_waits(self):
        s, ends = self.club("false")
        waiting = {"app": "club", "on": True, "ends": ends, "waiting": "Not in a guild"}
        self.assertEqual(self.app_events(s, "club"), [waiting])
        s.lua.execute(b"WuxianKit:Emit('demo.a', 1)")
        self.assertEqual(self.wakes(s, "club"), [])
        s.lua.execute(b"__inguild = true")                                 # the guild's roster arrived
        s.run(1.5)                                                         # asked again each second while it waits
        self.assertEqual(self.app_events(s, "club"), [waiting, {"app": "club", "on": True, "ends": ends}])
        s.lua.execute(b"WuxianKit:Emit('demo.b', 2)")
        self.assertEqual(len(self.wakes(s, "club")), 1)
        asked = self.lua(s, "__asked")
        s.run(5)
        self.assertEqual(self.lua(s, "__asked"), asked)                    # and not each second once it runs

    def test_a_check_that_still_says_no_half_a_minute_on_stops_it(self):
        s, ends = self.club("false")
        s.run(27)
        self.assertEqual(self.status(s, "club")["waiting"], "Not in a guild")
        s.run(3.5)
        self.assertEqual(self.app_events(s, "club")[-1], {"app": "club", "on": False, "why": "extension"})
        self.assertIn("Club: stopped. Not in a guild", s.chat())
        st = self.call(s, "kit.app.open", "{ app = 'club' }")              # later a no is a no at once
        self.assertEqual((st["on"], st["blocked"]), (False, "Not in a guild"))
        self.assertNotIn("waiting", st)

    def test_a_check_that_says_yes_runs_at_the_login(self):
        s, ends = self.club("true")
        self.assertEqual(self.app_events(s, "club"), [])                   # it went on: nothing to tell
        s.lua.execute(b"WuxianKit:Emit('demo.a', 1)")
        self.assertEqual(len(self.wakes(s, "club")), 1)

    def test_declared_again_into_what_it_cannot_hear_stops(self):
        s = self.start()
        self.opens(s, "{ app = 'r', title = 'R', hear = { 'bus:demo.*' }, lease = 0 }")
        s.ns.Switch(b"chat", False)
        s.lines.clear()
        st = self.agent(s, "kit.app.declare", "{ app = 'r', title = 'R', hear = { 'chat:guild' }, lease = 0 }")
        self.assertEqual((st["on"], st["why"], st["changed"], st["blocked"]),
                         (False, "extension", True, "Needs the Chat extension on"))
        self.assertIn("R: stopped. Needs the Chat extension on", s.chat())
        self.assertEqual(self.app_events(s, "r")[-1], {"app": "r", "on": False, "why": "extension"})

    def test_a_temporary_app_reopened_the_second_its_time_ends(self):
        s = self.start()
        temp = "{ app = 't', lease = 0, minutes = 1, temp = { title = 'T', hear = { 'bus:demo.*' } } }"
        self.agent(s, "kit.app.open", temp)
        s.lua.execute(b"WuxianKit:App('t').mem.chars[UnitGUID('player')].run.ends = time()")   # the ticker has not run
        st = self.agent(s, "kit.app.open", temp)
        now = s.lua.eval(b"time()")
        self.assertEqual((st["on"], st["temp"], st["ends"], st["heard"]), (True, True, now + 60, 0))   # a new run
        self.assertEqual([(e["on"], e.get("why")) for e in self.app_events(s, "t")],
                         [(True, None), (False, "expired"), (True, None)])
        self.assertEqual([a["id"] for a in self.agent(s, "kit.apps")].count("t"), 1)
        self.assertIs(self.row(s, "t")["on"], True)
        s.lua.execute(b"WuxianKit:Emit('demo.a', 1)")
        self.assertEqual(len(self.wakes(s, "t")), 1)                       # the one listed is the one that hears
        s.run(61)
        self.assertIsNone(self.row(s, "t"))                                # and it goes with its run
        self.assertEqual(self.app_events(s, "t")[-1], {"app": "t", "on": False, "why": "expired"})


class Forget(Case):
    DECL = ("{ app = 'x', title = 'X', hear = { 'bus:demo.*' }, lease = 0, "
            "options = { volume = { kind = 'number', default = 3 } } }")

    def test_forget_stops_it_and_keeps_what_the_player_set(self):
        s = self.start()
        self.opens(s, self.DECL)
        s.ns.SetAppOption(b"x", b"volume", 7)
        s.lua.execute(b"WuxianKit:Emit('demo.a', 1)")
        s.lines.clear()
        self.assertEqual(self.agent(s, "kit.app.forget", "{ app = 'x' }"), {"app": "x", "forgotten": True})
        self.assertEqual(self.app_events(s, "x")[-1], {"app": "x", "on": False, "why": "forgotten"})
        self.assertIn("X: stopped", s.chat())
        self.assertIsNone(self.row(s, "x"))
        self.assertEqual([a["id"] for a in self.agent(s, "kit.apps")], [])
        self.assertNotIn("x", [a["id"] for a in self.lua(s, "WuxianKit:Manifest()")["apps"]])
        self.assertIsNone(s.lua.eval(b"WuxianKitDB.apps.x.decl"))
        self.assertEqual(s.lua.eval(b"WuxianKitDB.apps.x.options.volume"), 7)
        self.assertIsNone(self.run_of(s, "x"))
        for cap in ("kit.app.status", "kit.app.open", "kit.app.forget", "kit.app.describe"):
            self.assertIn("no app x", self.fails(s, cap, "{ app = 'x' }"))
        s.lua.execute(b"WuxianKit:Emit('demo.b', 2)")
        self.assertEqual(len(self.wakes(s, "x")), 1)                       # nothing hears for it

        s2 = self.start(s.reload())                                        # it stays forgotten
        self.assertIsNone(self.row(s2, "x"))
        self.assertNotIn("declaration no longer holds", s2.chat())
        st = self.agent(s2, "kit.app.declare", self.DECL)                  # declared again: what was set is there
        self.assertEqual((st["on"], st["changed"], st["why"]), (False, True, "forgotten"))
        self.assertEqual(py(s2.ns.AppOptionList(b"x"))["volume"]["value"], 7)
        self.assertEqual([i["data"] for i in self.agent(s2, "kit.app.recent", "{ app = 'x' }")["items"]], [1])

    def test_forget_ends_every_character_s_run(self):
        s = self.start()
        self.opens(s, self.DECL)
        s2 = self.start(s.reload(), guid=OTHER)                            # another character withdraws it
        self.assertIsNotNone(self.run_of(s2, "x"))
        self.agent(s2, "kit.app.forget", "{ app = 'x' }")
        self.assertEqual(self.app_events(s2, "x"), [])                     # it was not on here
        self.assertIsNone(self.run_of(s2, "x"))
        self.assertEqual(self.lua(s2, f"WuxianKitDB.apps.x.chars[{ME!r}].last.why"), "forgotten")
        self.agent(s2, "kit.app.declare", self.DECL)
        s3 = self.start(s2.reload(), guid=ME)                              # back: declared again is not running again
        st = self.agent(s3, "kit.app.status", "{ app = 'x' }")
        self.assertEqual((st["on"], st["why"]), (False, "forgotten"))

    def test_forget_is_for_an_agent_s_apps(self):
        s = self.start()
        s.lua.execute(SALON)
        self.assertIn("app salon is an addon's (WxSalon): only an app an agent declared is forgotten",
                      self.fails(s, "kit.app.forget", "{ app = 'salon' }"))
        self.assertIsNotNone(self.row(s, "salon"))
        self.agent(s, "kit.app.open", "{ app = 't', lease = 0, temp = { hear = { 'bus:demo.*' } } }")
        self.agent(s, "kit.app.forget", "{ app = 't' }")                   # a temporary one: as a stop
        self.assertEqual(self.app_events(s, "t")[-1], {"app": "t", "on": False, "why": "forgotten"})
        self.assertIsNone(self.row(s, "t"))
        self.assertIsNone(s.lua.eval(b"WuxianKitDB.apps.t"))
        self.assertEqual(self.lua(s, "WuxianKit:Capability('kit.app.forget').kind"), "keep")


class Describe(Case):
    def again(self, s, app):
        """kit.app.describe's decl given back to kit.app.declare: what it answers"""
        s.lua.execute(f"local d = __fns['kit.app.describe']({{ app = {app!r} }}).decl d.app = {app!r} "
                      f"__r = __fns['kit.app.declare'](d)".encode())
        return py(s.g("__r"))

    def test_describe_gives_the_declaration_as_it_is_kept(self):
        s = self.start()
        self.agent(s, "kit.app.declare", "{ app = 'plain' }")
        d = self.agent(s, "kit.app.describe", "{ app = 'plain' }")
        self.assertEqual((d["app"], d["by"], d["temp"]), ("plain", "agent", False))
        self.assertEqual(d["decl"], {"title": "plain", "hear": {}, "see": {}, "controls": {}, "say": False,
                                     "lease": 600, "minutes": 120, "options": {}})   # the defaults filled in
        self.assertIs(self.again(s, "plain")["changed"], False)
        self.assertEqual(self.lua(s, "WuxianKit:Capability('kit.app.describe').kind"), "see")
        self.opens(s, "{ app = 'beat', lease = 60 }")                      # not a heartbeat
        s.run(50)
        self.agent(s, "kit.app.describe", "{ app = 'beat' }")
        s.run(20)
        self.assertEqual(self.status(s, "beat")["why"], "left")

    def test_what_describe_gives_declares_the_same(self):
        s = self.start()
        for app, decl in (
                ("paced", "title = 'Paced', hear = { 'chat:guild', 'bus:demo.*' }, see = { 'me' }, lease = 0, "
                          "minutes = 30, say = true, prompt = 'paced-skill', "
                          "pace = { normal = { every = 10, wake = { 'question' } } }, "
                          "controls = { 'test', { cmd = 'brief', label = 'Brief' }, 'stop' }, "
                          "options = { volume = { kind = 'number', min = 0, max = 10, default = 3, unit = 'pt' }, "
                          "mode = { kind = 'choice', choices = { { value = 'a', label = 'A' }, { value = 'b' } } }, "
                          "topics = { kind = 'list', title = 'Topics', order = 1 } }, "
                          "['local'] = { id = 'voice', title = 'Voice' }"),
                ("dig", "hear = { 'game:quest' }, digest = { gather = 2, every = false }, urgent = { 'mention' }, "
                        "lease = 120"),
                ("all", "hear = { 'bus:x' }, digest = true, pace = false, hidden = false"),
        ):
            st = self.agent(s, "kit.app.declare", f"{{ app = {app!r}, {decl} }}")
            self.assertIs(st["changed"], True, app)
            self.assertIs(self.again(s, app)["changed"], False, app)
            self.assertIs(self.agent(s, "kit.app.declare", f"{{ app = {app!r}, {decl} }}")["changed"], False, app)
        d = self.agent(s, "kit.app.describe", "{ app = 'paced' }")["decl"]
        self.assertEqual((d["title"], d["lease"], d["minutes"], d["say"], d["prompt"], d["local"], d["see"]),
                         ("Paced", 0, 30, True, "paced-skill", {"id": "voice", "title": "Voice"}, ["me"]))
        self.assertEqual(d["controls"], ["test", {"cmd": "brief", "label": "Brief"}, "stop"])
        self.assertEqual(self.agent(s, "kit.app.describe", "{ app = 'dig' }")["decl"]["urgent"], ["mention"])

    def test_a_temporary_app_s_and_an_addon_s(self):
        s = self.start(locale="zhCN")
        self.agent(s, "kit.app.open", "{ app = 't', lease = 0, temp = { hear = { 'bus:demo.*' }, hidden = true } }")
        d = self.agent(s, "kit.app.describe", "{ app = 't' }")
        self.assertEqual((d["by"], d["temp"], d["decl"]["hidden"], d["decl"]["hear"]),
                         ("agent", True, True, ["bus:demo.*"]))
        s.lua.execute(b"__fns['kit.app.open']({ app = 't', lease = 0, "
                      b"temp = __fns['kit.app.describe']({ app = 't' }).decl })")
        self.assertEqual([e["on"] for e in self.app_events(s, "t")], [True, True])   # the same: it goes on
        s.lua.execute(SALON)
        d = self.agent(s, "kit.app.describe", "{ app = 'salon' }")
        self.assertEqual((d["by"], d["temp"], d["decl"]["title"], d["decl"]["addon"], d["decl"]["extension"]),
                         ("addon", False, "沙龙", "WxSalon", "chat"))         # its texts in the language in force
        self.assertEqual([k for k in d["decl"] if k in ("check", "enrich")], [])
        self.assertTrue(self.lua(s, "(function() local function data(v) if type(v) == 'function' then return false end "
                                    "if type(v) == 'table' then for _, x in pairs(v) do if not data(x) then return false "
                                    "end end end return true end return data(__fns['kit.app.describe']({ app = 'salon' })) "
                                    "end)()"))


class Whole(Case):
    def test_declare_is_the_whole_declaration(self):
        s = self.start()
        st = self.agent(s, "kit.app.declare", "{ app = 'w', title = 'W', hear = { 'bus:demo.*' }, say = true, "
                                              "lease = 0, minutes = 30, controls = { 'stop' } }")
        self.assertEqual((st["title"], st["say"], st["lease"], st["controls"]), ("W", True, 0, ["stop"]))
        st = self.agent(s, "kit.app.declare", "{ app = 'w', hear = { 'bus:demo.*' } }")   # the rest: defaults again
        self.assertEqual((st["title"], st["say"], st["lease"], st["controls"], st["changed"]),
                         ("w", False, 600, {}, True))
        self.assertEqual(self.agent(s, "kit.app.describe", "{ app = 'w' }")["decl"]["minutes"], 120)
        self.assertEqual(self.lua(s, "WuxianKit:Capability('kit.app.declare').kind"), "keep")
        for cap in ("kit.app.open", "kit.app.stop"):
            self.assertEqual(self.lua(s, f"WuxianKit:Capability({cap!r}).kind"), "keep")

    def test_minutes_and_lease_of_a_run(self):
        s = self.start()
        self.agent(s, "kit.app.declare", "{ app = 'w', lease = 120, minutes = 30 }")
        now = s.lua.eval(b"time()")
        st = self.agent(s, "kit.app.open", "{ app = 'w' }")                # the declaration's
        self.assertEqual((st["ends"], st["lease"]), (now + 1800, 120))
        st = self.agent(s, "kit.app.open", "{ app = 'w', minutes = 5, lease = 0 }")   # this run's
        self.assertEqual((st["ends"], st["lease"]), (now + 300, 0))
        self.assertEqual(self.agent(s, "kit.app.describe", "{ app = 'w' }")["decl"]["lease"], 120)
        self.agent(s, "kit.app.stop", "{ app = 'w' }")
        self.assertEqual(self.agent(s, "kit.app.status", "{ app = 'w' }")["lease"], 120)

    def test_the_fields_come_from_one_table(self):
        s = self.start()
        cap = self.lua(s, "WuxianKit:Capability('kit.app.declare')")
        names = [f.decode() for f in s.lua.eval(b"function(ns) local t = {} for _, f in ipairs(ns.apps.FIELDS) do "
                                                b"if f.type then t[#t + 1] = f.name end end return t end")(s.ns).values()]
        self.assertEqual(sorted(cap["args"]), sorted(names + ["app"]))     # the arguments
        at = -1
        for name in names:                                                 # the doc, each in the table's order
            found = cap["doc"].find(f"{name} (", at + 1)
            self.assertGreater(found, at, name)
            at = found
        self.assertIn("at most 8 (kit.app.forget withdraws one)", cap["doc"])
        self.assertIn("default 600, 0 none, at least 60", cap["doc"])
        s.lua.execute(SALON)
        described = self.agent(s, "kit.app.describe", "{ app = 'salon' }")["decl"]
        self.assertEqual([k for k in described if k not in names + ["addon", "extension", "docs"]], [])
        self.assertIn("no argument color", self.fails(s, "kit.app.declare", "{ app = 'c', color = 'red' }"))


class Places(Case):
    def test_a_local_extension_s_apps_have_their_own_places(self):
        s = self.start()
        local = lambda i: f"{{ app = 'l{i}', ['local'] = {{ id = 'voice', title = 'Voice' }} }}"
        for i in range(8):
            self.agent(s, "kit.app.declare", f"{{ app = 'k{i}' }}")
        self.assertIn("at most 8 apps an agent declared", self.fails(s, "kit.app.declare", "{ app = 'k8' }"))
        for i in range(16):                                                # not among the 8
            self.agent(s, "kit.app.declare", local(i))
        self.assertIn("at most 16 apps of local extensions are kept: withdraw one (kit.app.forget)",
                      self.fails(s, "kit.app.declare", local(16)))
        self.assertIsNone(self.row(s, "l16"))
        self.assertIsNone(s.lua.eval(b"WuxianKitDB.apps.l16"))
        self.assertIn("at most 8 apps an agent declared",                  # without the label it is one of the 8
                      self.fails(s, "kit.app.declare", "{ app = 'l0' }"))
        self.assertEqual(self.row(s, "l0")["local"], {"id": "voice", "title": "Voice"})
        self.assertIn("at most 16 apps of local extensions",               # and the other way
                      self.fails(s, "kit.app.declare", "{ app = 'k0', ['local'] = { id = 'voice' } }"))
        self.agent(s, "kit.app.forget", "{ app = 'k0' }")
        self.assertIs(self.agent(s, "kit.app.declare", "{ app = 'l0' }")["changed"], True)
        self.assertNotIn("local", self.row(s, "l0"))
        self.assertEqual(self.agent(s, "kit.app.declare", local(16))["local"], {"id": "voice", "title": "Voice"})
        s2 = self.start(s.reload())                                        # all of them back
        self.assertEqual(len(py(s2.ns.AppList())), 8 + 16)
        self.assertEqual(s2.chat().count("declaration no longer holds"), 0)

    def test_the_revision_follows_the_label(self):
        s = self.start()
        rev = lambda: self.lua(s, "WuxianKit:Manifest().revision")
        self.agent(s, "kit.app.declare", "{ app = 'b', title = 'B' }")
        seen = [rev()]
        for label in ("{ id = 'voice', title = 'Voice' }", "{ id = 'voice', title = 'Voice 2' }",
                      "{ id = 'echo', title = 'Voice 2' }"):
            self.agent(s, "kit.app.declare", f"{{ app = 'b', title = 'B', ['local'] = {label} }}")
            seen.append(rev())
        self.assertEqual(len(set(seen)), 4)
        self.agent(s, "kit.app.declare", "{ app = 'b', title = 'B' }")
        self.assertEqual(rev(), seen[0])


class Dropped(Case):
    def test_a_declaration_that_no_longer_holds_goes_whole(self):
        s = self.start(locale="zhCN")
        self.opens(s, "{ app = 'old', title = 'Old', hear = { 'bus:demo.*' }, lease = 0, "
                      "options = { volume = { kind = 'number', default = 3 } } }")
        self.agent(s, "kit.app.declare", "{ app = 'pipe', hear = { 'bus:demo.*' } }")
        self.agent(s, "kit.app.declare", "{ app = 'fine', hear = { 'bus:demo.*' } }")
        s.ns.SetAppOption(b"old", b"volume", 7)
        s.lua.execute(b"WuxianKit:Emit('demo.a', 1)")
        s.lua.execute(b"WuxianKitDB.apps.old.decl.hear = { 'nosuch' }")        # not <source>:<what>
        s.lua.execute(b"WuxianKitDB.apps.pipe.decl.hidden = true")             # kept by a kit before 0.6's release
        s2 = self.start(s.reload(locale="zhCN"))
        for app in ("old", "pipe"):
            self.assertIsNone(self.row(s2, app))
            self.assertIsNone(s2.lua.eval(f"WuxianKitDB.apps.{app}".encode()))   # run, ring, options: nothing left
            self.assertIn(f"应用「{app}」的声明已失效，已移除", s2.chat())
        self.assertIsNotNone(self.row(s2, "fine"))
        self.assertEqual(self.events(s2, "kit.app"), [])
        s2.lua.execute(b"WuxianKit:Emit('demo.b', 2)")
        self.assertEqual(self.wakes(s2, "old"), [])
        s3 = self.start(s2.reload(locale="zhCN"))                          # told once
        self.assertNotIn("声明已失效", s3.chat())


class Present(Case):
    def test_present_is_an_agent_that_called(self):
        s = self.start()
        self.agent(s, "kit.app.declare", "{ app = 'p', hear = { 'bus:demo.*' }, lease = 0 }")
        st = self.call(s, "kit.app.open", "{ app = 'p' }")                 # the player's card started it: no agent yet
        self.assertEqual((st["on"], st["present"]), (True, False))
        self.assertNotIn("seen", st)
        self.assertIs(self.row(s, "p")["present"], False)
        st = self.agent(s, "kit.app.status", "{ app = 'p' }")              # it calls: here
        self.assertEqual((st["present"], st["seen"]), (True, s.lua.eval(b"time()")))
        self.assertIs(self.row(s, "p")["present"], True)
        s.run(599, dt=0.5)
        self.assertIs(self.status(s, "p")["present"], True)                # no lease: within the default one
        s.run(3, dt=0.5)
        st = self.status(s, "p")
        self.assertEqual((st["on"], st["present"]), (True, False))         # it runs on, nobody listens
        self.assertIs(self.row(s, "p")["present"], False)
        self.agent(s, "kit.app.open", "{ app = 'p', lease = 60 }")         # with a lease: within it, then it stops
        s.run(59, dt=0.5)
        self.assertIs(self.status(s, "p")["present"], True)
        s.run(3, dt=0.5)
        st = self.status(s, "p")
        self.assertEqual((st["on"], st["present"], st["why"]), (False, False, "left"))


class Said(Case):
    EMIT = ("WuxianKit:Emit('kit.proposal', {{ id = {id}, state = 'done', source = 'agent', steps = {{ "
            "{{ cap = 'chat.send', args = {{ channel = 'guild', text = 'a' }} }} }} }})")

    def test_a_proposal_counts_once_a_day(self):
        s = self.start()
        self.agent(s, "kit.app.declare", "{ app = 'g', hear = { 'chat:guild' } }")
        said = lambda: self.status(s, "g")["said"]
        s.lua.execute(self.EMIT.format(id=101).encode())
        s.lua.execute(self.EMIT.format(id=101).encode())                   # told again: counted once
        s.lua.execute(self.EMIT.format(id=102).encode())
        self.assertEqual(said(), 2)
        day = self.lua(s, "date('%Y-%m-%d', time())")
        s.run(86400, dt=600)                                               # the next day
        self.assertNotEqual(self.lua(s, "date('%Y-%m-%d', time())"), day)
        self.assertEqual(said(), 0)
        s.lua.execute(self.EMIT.format(id=101).encode())                   # what was counted went with the day
        s.lua.execute(self.EMIT.format(id=101).encode())
        self.assertEqual(said(), 1)


class Characters(Case):
    def test_another_character_leaves_this_one_s_run_alone(self):
        s = self.start()
        self.opens(s, "{ app = 'keep', title = 'Keep', hear = { 'bus:demo.*' }, lease = 0 }")
        s.lua.execute(b"WuxianKit:Emit('demo.a', 1)")
        mine = self.run_of(s, "keep")
        ring = self.lua(s, f"WuxianKitDB.apps.keep.chars[{ME!r}].recent.n")

        s2 = self.start(s.reload(), guid=OTHER)
        for cap in ("kit.app.status", "kit.app.state", "kit.app.recent"):  # its calls are no heartbeat of mine
            self.agent(s2, cap, "{ app = 'keep' }")
        st = self.agent(s2, "kit.app.status", "{ app = 'keep' }")
        self.assertEqual((st["on"], st["present"], st["next"]), (False, False, 0))
        self.assertNotIn("why", st)
        self.agent(s2, "kit.app.open", "{ app = 'keep', minutes = 5 }")    # its own run, its own ring
        s2.lua.execute(b"WuxianKit:Emit('demo.b', 2) WuxianKit:Emit('demo.c', 3)")
        self.assertEqual(self.agent(s2, "kit.app.status", "{ app = 'keep' }")["heard"], 2)
        s2.run(30)
        self.agent(s2, "kit.app.stop", "{ app = 'keep' }")
        self.assertEqual(self.lua(s2, f"WuxianKitDB.apps.keep.chars[{OTHER!r}].last.why"), "stopped")
        theirs = self.run_of(s2, "keep", ME)
        self.assertEqual((theirs["seen"], theirs["heard"], theirs["ends"], theirs["started"]),
                         (mine["seen"], 1, mine["ends"], mine["started"]))
        self.assertEqual(self.lua(s2, f"WuxianKitDB.apps.keep.chars[{ME!r}].recent.n"), ring)
        self.assertIsNone(self.lua(s2, f"WuxianKitDB.apps.keep.chars[{ME!r}].last"))

        s3 = self.start(s2.reload(), guid=ME)                              # back: it ran on, with what it heard
        st = self.agent(s3, "kit.app.status", "{ app = 'keep' }")
        self.assertEqual((st["on"], st["heard"], st["ends"]), (True, 1, mine["ends"]))
        self.assertNotIn("why", st)
        self.assertEqual([i["data"] for i in self.agent(s3, "kit.app.recent", "{ app = 'keep' }")["items"]], [1])
        s3.lua.execute(b"WuxianKit:Emit('demo.d', 4)")
        self.assertEqual(self.agent(s3, "kit.app.status", "{ app = 'keep' }")["heard"], 2)
        s4 = self.start(s3.reload(), guid=OTHER)                           # and the other's is as it left it
        st = self.agent(s4, "kit.app.status", "{ app = 'keep' }")
        self.assertEqual((st["on"], st["why"]), (False, "stopped"))
        self.assertEqual([i["data"] for i in self.agent(s4, "kit.app.recent", "{ app = 'keep' }")["items"]], [2, 3])


if __name__ == "__main__":
    import unittest
    unittest.main()
