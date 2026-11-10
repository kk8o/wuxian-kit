"""任务指引 (Quest guide, Extensions/Route): the source route (route.step / progress / arrive / done), the state route,
WuxianKit.Route:Provide and the choice of provider, and the provider game (Native.lua: the game's own quest tracking).
RouteApp drives it through a temporary app (kit.app.open temp = true) named probe; test_guides.py uses it for RestedXP."""
import unittest

from kitmock import ROUTE, Session, lupa, py


class RouteApp:
    """one UI session, logged in, the quest guide's mock (kitmock.ROUTE) in, every bus event caught; before: Lua run
    before the login (RestedXP's fakes)"""

    def __init__(self, test, before="", **kw):
        self.test = test
        self.s = Session(test, **kw)
        self.lua = self.s.lua
        self.lua.execute(ROUTE.encode())
        if before:
            self.lua.execute(before.encode())
        self.lua.execute(b"__events = {} WuxianKit:On('*', function(topic, data) "
                         b"__events[#__events + 1] = { topic = topic, data = data } end)")
        self.lua.globals()[b"__ns"] = self.s.ns          # the core's private table, for the tests' Lua
        self.s.login()
        self.s.run(1)

    def call(self, cap, args="{}"):
        self.lua.execute(f"__answer = WuxianKit:Call({cap!r}, {args})".encode())
        return py(self.s.g("__answer"))

    def try_call(self, cap, args="{}"):
        self.lua.execute(f"__ok, __answer = pcall(WuxianKit.Call, WuxianKit, {cap!r}, {args})".encode())
        return bool(self.s.g("__ok")), py(self.s.g("__answer"))

    def listen(self, hear=("route:*",), app="probe"):
        hears = ", ".join(repr(h) for h in hear)
        answer = self.call("kit.app.open", f"{{ app = {app!r}, minutes = 60, lease = 0, temp = true, hear = {{ {hears} }} }}")
        self.run(0.5)
        return answer

    def stop(self, app="probe"):
        return self.call("kit.app.stop", f"{{ app = {app!r} }}")

    def items(self, kind=None, app="probe"):
        """the items of the app's wakes (each wake one item: no digest)"""
        out = []
        for e in py(self.s.g("__events")) or []:
            if e["topic"] == "app." + app:
                out += [m for m in e["data"]["items"] if kind is None or m["kind"] == kind]
        return out

    def data(self, kind=None, app="probe"):
        return [m["data"] for m in self.items(kind, app)]

    def kinds(self, app="probe"):
        return [m["kind"] for m in self.items(app=app)]

    def lua_(self, code):
        self.lua.execute(code.encode())

    def eval(self, code):
        return py(self.lua.eval(code.encode()))

    def route(self):
        return self.s.ns[b"route"]

    def registered(self, which="frame"):
        """the events a frame of the extension (frame: the core's; native: the provider game's) has registered now"""
        return sorted(k.decode() for k in (self.route()[which.encode()][b"events"] or {}).keys())

    def fire(self, event, *args):
        self.s.fire(event, *args)

    def run(self, seconds, dt=0.05):
        self.s.run(seconds, dt)

    def errors(self):
        return self.s.errors()


class RouteTest(unittest.TestCase):
    """each test ends with no Lua error"""

    def setUp(self):
        if lupa is None:
            self.skipTest("pip install lupa")
        self.apps = []

    def app(self, **kw):
        a = RouteApp(self, **kw)
        self.apps.append(a)
        return a

    def tearDown(self):
        for a in getattr(self, "apps", []):
            self.assertEqual(a.errors(), [])


HERBS = {"provider": "game", "key": "game|3001", "goals": [
    {"op": "collect", "target": "Peacebloom", "quest": {"id": 3001, "name": "Healing Herbs"}, "objective": 1, "need": 5, "have": 3,
     "done": False, "text": "Peacebloom: 3/5"}]}


class Native(RouteTest):
    def test_the_tracked_quest_is_the_step_and_its_objectives_the_goals(self):
        a = self.app()
        a.lua_("__track(3001)")
        a.listen()
        [item] = a.items()
        self.assertEqual((item["kind"], item["source"]), ("route.step", "route"))
        self.assertIsInstance(item["time"], int)
        self.assertEqual(item["data"], HERBS)
        self.assertEqual(a.eval("WuxianKit.Route:State()"), {"provider": "game", "key": "game|3001", "since": item["time"],
                         "goals": [{"op": "collect", "target": "Peacebloom", "quest": {"name": "Healing Herbs"}, "need": 5, "have": 3,
                                    "done": False}]})

    def test_the_target_is_the_objectives_text_without_its_count(self):
        a = self.app()
        a.lua_("__quests[2].objectives = { "
               "{ type = 'monster', text = '0/12 消灭加拉克斥候', numFulfilled = 0, numRequired = 12, finished = false }, "
               "{ type = 'item', text = '钢齿土狼的肋骨：0/1', numFulfilled = 0, numRequired = 1, finished = false }, "
               "{ type = 'monster', text = 'Kobold Vermin slain: 3/10', numFulfilled = 3, numRequired = 10, finished = false }, "
               "{ type = 'event', text = '找到营地', finished = false } } "
               "__track(3001)")
        a.listen()
        goals = a.data("route.step")[-1]["goals"]
        self.assertEqual([(g["op"], g.get("target")) for g in goals],
                         [("kill", "加拉克斥候"), ("collect", "钢齿土狼的肋骨"), ("kill", "Kobold Vermin"), ("other", None)])
        self.assertEqual(goals[0]["text"], "0/12 消灭加拉克斥候")      # the text stays as the client gave it

    def test_the_recent_items_keep_a_goals_quest(self):
        a = self.app()
        a.lua_("__track(3001)")
        a.listen()
        recent = a.call("kit.app.recent", "{ app = 'probe' }")
        self.assertEqual(recent["items"][-1]["data"], HERBS)    # saved whole: the goal's quest is 5 levels down

    def test_progress_then_done_and_the_turnin_step_then_turned_in(self):
        a = self.app()
        a.lua_("__track(3001)")
        a.listen()
        a.lua_("__objective(3001, 1, 4)")
        a.run(0.5)
        self.assertEqual(a.data("route.progress"), [{"key": "game|3001", "goal": 1, "have": 4, "need": 5, "done": False}])
        a.lua_("__objective(3001, 1, 5)")                 # all done: the step is done, the turnin is a new one
        a.run(0.5)
        self.assertEqual(a.kinds()[2:], ["route.done", "route.step"])
        self.assertEqual(a.data("route.done"), [{"key": "game|3001", "why": "complete"}])
        self.assertEqual(a.data("route.step")[-1], {"provider": "game", "key": "game|3001|turnin", "goals": [
            {"op": "turnin", "quest": {"id": 3001, "name": "Healing Herbs"}}]})
        a.lua_("__watched = { 3002 } __turnin(3001)")
        a.run(0.5)
        self.assertEqual(a.data("route.done")[-1], {"key": "game|3001|turnin", "why": "turnin"})
        self.assertEqual(a.data("route.step")[-1]["key"], "game|3002|turnin")     # the watch list's first: done already

    def test_the_watch_list_when_nothing_is_super_tracked_and_nothing_without_either(self):
        a = self.app()
        a.listen()
        self.assertEqual(a.items(), [])
        self.assertIsNone(a.eval("WuxianKit.Route:State()"))
        a.lua_("__watched = { 3001 } __fire('QUEST_WATCH_LIST_CHANGED')")
        a.run(0.5)
        self.assertEqual(a.data("route.step"), [HERBS])
        a.lua_("__track(3002)")                            # another quest followed: the step goes undone
        a.run(0.5)
        self.assertEqual(a.data("route.done"), [{"key": "game|3001", "why": "replaced"}])
        self.assertEqual(a.data("route.step")[-1]["key"], "game|3002|turnin")
        a.lua_("__watched = {} __track(0)")
        a.run(0.5)
        self.assertEqual(a.data("route.done")[-1], {"key": "game|3002|turnin", "why": "replaced"})
        self.assertIsNone(a.eval("WuxianKit.Route:State()"))

    def test_the_next_waypoint_is_the_place_of_the_first_goal_not_done(self):
        a = self.app()
        a.lua_("__track(3001) __waypoints[3001] = { 1434, 0.41234, 0.5555 }")
        a.listen()
        [step] = a.data("route.step")
        self.assertEqual(step["goals"][0]["place"], {"map": 1434, "x": 41.2, "y": 55.6, "zone": "Zephyr Isle"})
        self.assertEqual(a.eval("WuxianKit.Route:State()")["goals"][0]["place"], {"zone": "Zephyr Isle"})

    def test_read_only_while_in_use(self):
        a = self.app()
        a.lua_("__track(3001)")
        self.assertEqual((a.registered(), a.registered("native")), ([], []))
        self.assertEqual(a.eval("WuxianKit.Route:Current()"), HERBS)      # asked: read now, all the same
        a.listen(["route:progress"])
        self.assertEqual(a.registered(), ["QUEST_ACCEPTED", "QUEST_LOG_UPDATE", "QUEST_REMOVED", "QUEST_TURNED_IN"])
        self.assertEqual(a.registered("native"), ["QUEST_ACCEPTED", "QUEST_LOG_UPDATE", "QUEST_TURNED_IN",
                                                  "QUEST_WATCH_LIST_CHANGED", "SUPER_TRACKING_CHANGED"])
        self.assertEqual(a.items(), [])                    # it hears progress only
        a.stop()
        self.assertEqual((a.registered(), a.registered("native")), ([], []))
        a.lua_("__objective(3001, 1, 4)")
        a.run(1)
        self.assertEqual(a.items(), [])

    def test_one_who_starts_hearing_later_gets_the_current_step(self):
        a = self.app()
        a.lua_("__track(3001)")
        a.listen()
        a.listen(app="late")
        self.assertEqual(a.data("route.step", app="late"), [HERBS])
        self.assertEqual(len(a.data("route.step")), 1)    # the first one heard it once

    def test_what_a_hear_entry_takes(self):
        a = self.app()
        ok, why = a.try_call("kit.app.open", "{ app = 'p', temp = true, hear = { 'route:steps' } }")
        self.assertFalse(ok)
        self.assertIn("a route source is step, progress, arrive, done or *", why)
        self.assertTrue(a.listen(["route:*", "route:done"])["on"])

    def test_the_extension_off(self):
        a = self.app()
        a.lua_("__track(3001)")
        a.listen()
        a.s.ns[b"Switch"](b"route", False)               # its app stops, nothing is read
        self.assertEqual((a.registered(), a.registered("native")), ([], []))
        self.assertFalse(a.try_call("kit.app.status", "{ app = 'probe' }")[0])     # (a temporary one: gone)
        a.s.ns[b"Switch"](b"route", True)
        a.listen()
        self.assertEqual(a.data("route.step"), [HERBS, HERBS])


# an adapter of the tests' own: __fake.step is its step, __fake.changed what Start was given
FAKE = r"""
__fake = { starts = 0, stops = 0, active = true }
WuxianKit.Route:Provide("fake", {
	title = "Fake guide", addon = "FakeGuide",
	Active = function() return __fake.active end,
	Current = function()
		if __fake.boom then error("fake boom") end
		return __fake.step
	end,
	Start = function(changed) __fake.starts = __fake.starts + 1 __fake.changed = changed end,
	Stop = function() __fake.stops = __fake.stops + 1 __fake.changed = nil end,
})
"""

STEP = """__fake.step = { guide = "|cffff0000Demo|r guide", index = 3, key = "demo|3", text = { "Go there", "", "Kill |cff00ff00four|r" },
	goals = { { op = "go", place = { map = 1434, x = 37.512, y = 3.249 } },
		{ op = "kill", target = "Raptor", quest = { id = 3001 }, objective = 1, need = 10, have = 0 },
		{ op = "dance", text = "an op not known", done = 1 }, "not a goal" } }"""


class Adapters(RouteTest):
    def test_provide_providers_and_the_option(self):
        a = self.app()
        a.lua_(FAKE)
        self.assertEqual(a.eval("WuxianKit.Route:Providers()"), [
            {"id": "game", "title": "The game's own", "active": True},
            {"id": "fake", "title": "Fake guide", "addon": "FakeGuide", "active": True}])
        options = a.call("kit.options", "{ extension = 'route' }")
        self.assertEqual([c["value"] for c in options["provider"]["choices"]], ["auto", "game", "fake"])
        for bad in ("'Bad'", "'a_very_long_provider_name_x'", "1"):
            self.assertFalse(a.eval(f"(pcall(WuxianKit.Route.Provide, WuxianKit.Route, {bad}, {{ Current = print }}))"))
        self.assertFalse(a.eval("(pcall(WuxianKit.Route.Provide, WuxianKit.Route, 'x', {}))"))
        self.assertFalse(a.eval("(pcall(WuxianKit.Route.Provide, WuxianKit.Route, 'x', { Current = print, extension = 1 }))"))
        a.lua_("WuxianKit.Route:Provide('fake', nil)")    # taken back
        self.assertEqual([p["id"] for p in a.eval("WuxianKit.Route:Providers()")], ["game"])

    def choice(self, a, value=None):
        route = a.s.ns[b"extensions"][b"route"]
        if value is not None:
            a.s.ns[b"SetOption"](route, b"provider", value.encode())
        return a.eval("WuxianKit:Extension('route'):Get('provider')")

    def test_one_provided_late_is_taken_up(self):
        a = self.app()
        a.lua_("__track(3001)")
        a.listen()
        self.assertEqual([s["provider"] for s in a.data("route.step")], ["game"])
        a.lua_(FAKE + STEP)                                # auto, in use: the choice is made again at once
        a.run(0.5)
        self.assertEqual([s["provider"] for s in a.data("route.step")], ["game", "fake"])
        self.assertEqual(a.eval("__fake.starts"), 1)

    def test_the_players_choice_is_kept_while_its_provider_is_taken_away(self):
        a = self.app()
        a.lua_(FAKE + STEP + "__fake.active = false __track(3001)")     # (not active: auto would not take it)
        self.assertEqual(self.choice(a, "fake"), "fake")
        a.listen()
        self.assertEqual([s["provider"] for s in a.data("route.step")], ["fake"])
        a.lua_("__adapter = __ns.route.providers.fake.adapter WuxianKit.Route:Provide('fake', nil)")
        self.assertEqual(a.eval("__fake.stops"), 1)       # read: stopped at once
        a.run(0.5)
        self.assertEqual(self.choice(a), "auto")          # no choice of the option's meanwhile
        self.assertEqual(a.data("route.done"), [{"key": "demo|3", "why": "replaced"}])
        self.assertEqual([s["provider"] for s in a.data("route.step")], ["fake", "game"])
        a.lua_("WuxianKit.Route:Provide('fake', __adapter)")            # back: the player's choice again
        a.run(0.5)
        self.assertEqual(self.choice(a), "fake")
        self.assertEqual([s["provider"] for s in a.data("route.step")], ["fake", "game", "fake"])
        self.assertEqual((a.eval("__fake.starts"), a.eval("__fake.stops")), (2, 1))

    def test_a_provider_is_away_while_its_extension_is_off(self):
        a = self.app()
        a.lua_("WuxianKit:Extension('fakes', { title = 'Fakes' })")     # provided once, outside its setup
        a.lua_(FAKE.replace('addon = "FakeGuide"', 'extension = "fakes"') + STEP + "__track(3001)")
        self.assertEqual(a.eval("WuxianKit.Route:Providers()")[1],     # the extension is not on yet
                         {"id": "fake", "title": "Fake guide", "active": False, "away": True})
        a.run(0.1)
        self.assertEqual(a.eval("WuxianKit.Route:Providers()")[1], {"id": "fake", "title": "Fake guide", "active": True})
        self.assertEqual(self.choice(a, "fake"), "fake")
        a.listen()
        self.assertEqual([s["provider"] for s in a.data("route.step")], ["fake"])
        a.s.ns[b"Switch"](b"fakes", False)
        self.assertEqual(a.eval("__fake.stops"), 1)       # stopped at once
        a.run(0.5)
        self.assertEqual(a.data("route.done"), [{"key": "demo|3", "why": "replaced"}])
        self.assertEqual([s["provider"] for s in a.data("route.step")], ["fake", "game"])      # the game's own meanwhile
        self.assertEqual(self.choice(a), "fake")          # still the player's choice, and said to be off
        choices = a.call("kit.options", "{ extension = 'route' }")["provider"]["choices"]
        self.assertEqual([(c["value"], c["label"]) for c in choices][1:],
                         [("game", "The game's own"), ("fake", "Fake guide · off")])
        self.assertTrue(a.eval("WuxianKit:Extension('route'):status()").startswith("The game's own"))
        a.run(6)                                           # (nothing looks at it while it is away)
        self.assertEqual(a.eval("__fake.starts"), 1)
        a.s.ns[b"Switch"](b"fakes", True)
        a.run(0.5)
        self.assertEqual([s["provider"] for s in a.data("route.step")], ["fake", "game", "fake"])
        self.assertEqual((a.eval("__fake.starts"), a.eval("__fake.stops")), (2, 1))
        self.assertEqual(a.call("kit.options", "{ extension = 'route' }")["provider"]["choices"][2]["label"], "Fake guide")

    def test_auto_leaves_out_a_provider_that_is_away(self):
        a = self.app()
        a.lua_("WuxianKit:Extension('fakes', { title = 'Fakes' })")
        a.lua_(FAKE.replace('addon = "FakeGuide"', 'extension = "fakes"') + STEP + "__track(3001)")
        a.run(0.1)
        a.listen()
        self.assertEqual([s["provider"] for s in a.data("route.step")], ["fake"])
        a.s.ns[b"Switch"](b"fakes", False)
        a.run(6)
        self.assertEqual([s["provider"] for s in a.data("route.step")], ["fake", "game"])
        self.assertEqual((a.eval("__fake.starts"), a.eval("__fake.stops")), (1, 1))

    def test_auto_takes_an_adapter_with_a_step_and_the_shape_it_gets(self):
        a = self.app()
        a.lua_(FAKE + "__track(3001)")
        a.listen()
        self.assertEqual(a.data("route.step"), [HERBS])   # the adapter has no step: game
        self.assertEqual(a.eval("__fake.starts"), 0)
        a.lua_(STEP)
        a.run(5)                                           # looked at again every 5 s
        self.assertEqual(a.data("route.done"), [{"key": "game|3001", "why": "replaced"}])
        self.assertEqual(a.data("route.step")[-1], {"provider": "fake", "guide": "Demo guide", "index": 3, "key": "demo|3",
                         "text": ["Go there", "Kill four"], "goals": [
                             {"op": "go", "place": {"map": 1434, "x": 37.5, "y": 3.2, "zone": "Zephyr Isle"}},
                             {"op": "kill", "target": "Raptor", "quest": {"id": 3001, "name": "Healing Herbs"},
                              "objective": 1, "need": 5, "have": 3, "done": False},      # the client's word
                             {"op": "other", "text": "an op not known", "done": True}]})
        self.assertEqual(a.eval("__fake.starts"), 1)
        a.lua_("__fake.step = nil __fake.changed()")      # its step gone: game again, the adapter stopped
        a.run(0.5)
        self.assertEqual(a.data("route.done")[-1], {"key": "demo|3", "why": "replaced"})
        self.assertEqual(a.data("route.step")[-1]["provider"], "game")
        self.assertEqual(a.eval("__fake.stops"), 1)

    def test_the_option_picks_one_and_a_step_without_a_key_is_none(self):
        a = self.app()
        a.lua_(FAKE + STEP + "__track(3001)")
        a.s.ns[b"SetOption"](a.s.ns[b"extensions"][b"route"], b"provider", b"game")
        a.listen()
        self.assertEqual([s["provider"] for s in a.data("route.step")], ["game"])
        a.s.ns[b"SetOption"](a.s.ns[b"extensions"][b"route"], b"provider", b"fake")
        a.run(0.5)
        self.assertEqual([s["provider"] for s in a.data("route.step")], ["game", "fake"])
        a.lua_("__fake.step = { goals = {} } __fake.changed()")
        a.run(0.5)
        self.assertEqual(a.data("route.done")[-1], {"key": "demo|3", "why": "replaced"})
        self.assertIsNone(a.eval("WuxianKit.Route:State()"))

    def test_progress_arrive_and_done_from_the_adapter(self):
        a = self.app()
        a.lua_(FAKE + """__fake.step = { key = "k", goals = {
            { op = "go", place = { map = 1434, x = 50, y = 50 } }, { op = "collect", target = "Herb", need = 3, have = 1 } } }""")
        a.listen()
        a.lua_("__fake.changed('arrive')")
        a.lua_("__fake.changed('arrive')")                 # once in 5 s
        self.assertEqual(a.data("route.arrive"), [{"key": "k", "place": {"map": 1434, "x": 50, "y": 50,
                                                                         "zone": "Zephyr Isle"}}])
        a.lua_("__fake.step.goals[1].done = true __fake.step.goals[2].have = 3 __fake.step.goals[2].done = true "
               "__fake.changed()")
        a.run(0.5)
        self.assertEqual(a.data("route.progress"), [{"key": "k", "goal": 1, "done": True},
                                                    {"key": "k", "goal": 2, "have": 3, "need": 3, "done": True}])
        self.assertEqual(a.data("route.done"), [{"key": "k", "why": "complete"}])
        a.run(6)
        a.lua_("__fake.changed('arrive', { map = 1434, x = 10, y = 20 })")
        self.assertEqual(a.data("route.arrive")[-1], {"key": "k", "place": {"map": 1434, "x": 10, "y": 20,
                                                                            "zone": "Zephyr Isle"}})
        a.lua_("__fake.step = { key = 'k2', goals = {} } __fake.changed()")    # done already: not again
        a.run(0.5)
        self.assertEqual(len(a.data("route.done")), 1)

    def test_the_same_step_with_other_goals_is_told_again(self):
        a = self.app()
        a.lua_(FAKE + """__fake.step = { key = "k", goals = {
            { op = "go", place = { map = 1434, x = 10, y = 10 } },
            { op = "collect", target = "Herb", need = 3, have = 1, place = { map = 1434, x = 1, y = 1 }, text = "Herb 1/3" } } }""")
        a.listen()
        self.assertEqual(len(a.data("route.step")), 1)
        a.lua_("local g = __fake.step.goals[2] g.have, g.text, g.place.x = 2, 'Herb 2/3', 2 __fake.changed()")
        a.run(0.5)                                         # progress, its text, a hint of where: the same goals
        self.assertEqual(a.data("route.progress"), [{"key": "k", "goal": 2, "have": 2, "need": 3, "done": False}])
        self.assertEqual(len(a.data("route.step")), 1)
        a.lua_("__fake.step.goals[1].place.x = 20 __fake.step.goals[2].have = 3 __fake.changed()")
        a.run(0.5)                                         # the waypoint is another: the step again, whole
        self.assertEqual(a.kinds()[-2:], ["route.progress", "route.step"])
        again = a.data("route.step")[-1]
        self.assertEqual((again["key"], again["again"], again["goals"][0]["place"]["x"], again["goals"][1]["have"]),
                         ("k", True, 20, 3))
        a.lua_("__fake.step.goals[2] = { op = 'kill', target = 'Boar', done = true } __fake.changed()")
        a.run(0.5)                                         # another goal in its place: no progress of the old one's
        self.assertEqual(len(a.data("route.progress")), 2)
        self.assertEqual([g["op"] for g in a.data("route.step")[-1]["goals"]], ["go", "kill"])
        a.lua_("__fake.step.goals[1].done = true __fake.changed()")
        a.run(0.5)
        self.assertEqual(a.data("route.done"), [{"key": "k", "why": "complete"}])
        a.lua_("__fake.step.goals[3] = { op = 'talk', target = 'Innkeeper' } __fake.changed()")
        a.run(0.5)                                         # one more goal: again, and not done any more
        self.assertEqual((len(a.data("route.step")), a.data("route.step")[-1]["again"]), (4, True))
        self.assertEqual(a.eval("WuxianKit.Route:State().since == __ns.route.cur.since"), True)
        a.lua_("__fake.step.goals[3].done = true __fake.changed()")
        a.run(0.5)
        self.assertEqual(a.data("route.done"), [{"key": "k", "why": "complete"}] * 2)
        self.assertNotIn("again", a.data("route.step")[0])

    def test_an_adapter_that_fails_is_no_step(self):
        a = self.app()
        a.lua_(FAKE + STEP)
        a.listen()
        a.lua_("__fake.boom = true __fake.changed()")
        a.run(0.5)
        self.assertTrue(any("fake boom" in e for e in a.errors()))      # the error handler has it
        a.lua_("for k in pairs(__errors) do __errors[k] = nil end")
        self.assertEqual(a.data("route.done"), [{"key": "demo|3", "why": "replaced"}])


class State(RouteTest):
    def test_the_state_reads_small_and_counts_as_a_user(self):
        a = self.app()
        a.lua_("__track(3001)")
        facet = a.route()[b"facet"]
        self.assertEqual(py(facet[b"fields"])["key"], "string")
        facet[b"on"](facet)
        a.run(0.5)
        self.assertEqual(a.registered("native")[:1], ["QUEST_ACCEPTED"])
        state = py(facet[b"read"](facet))
        self.assertEqual((state["provider"], state["key"], len(state["goals"])), ("game", "game|3001", 1))
        facet[b"off"](facet)
        self.assertEqual(a.registered("native"), [])

    def test_seen_by_an_app(self):
        a = self.app()
        a.lua_("__track(3001)")
        a.call("kit.app.open", "{ app = 'viewer', temp = true, minutes = 60, lease = 0, see = { 'route' }, "
                               "hear = { 'route:done' } }")
        a.run(0.5)
        state = a.call("kit.app.state", "{ app = 'viewer' }")["state"]["route"]
        self.assertEqual((state["provider"], state["key"]), ("game", "game|3001"))


if __name__ == "__main__":
    unittest.main()
