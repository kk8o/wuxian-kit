"""Apps and their drivers (the layered kit): driver (prompt, program) and docs in the declaration, kit.app.declare (kept
without starting, no heartbeat, launch), kit.app.launch and ns.AppLaunch (only while 无限工坊 is linked; launching
until the app starts or 30 s pass), ns.WorkshopOnline, and temporary apps (kit.app.open temp = true: not kept, at most
4, not one of the 8, gone once stopped or reloaded)."""
import unittest

from kitmock import Session, lupa, py
from test_standalone import bridge


@unittest.skipIf(lupa is None, "lupa (Lua 5.1 for Python) is not installed")
class Programs(unittest.TestCase):
    def start(self, s=None, online=True, **kw):
        if s is None:
            kw.setdefault("saved", {"WoWBridge": bridge("0.9.7", online=True)})
            s = Session(self, **kw)
        s.lua.execute(f"__online = {'true' if online else 'false'}".encode())
        s.lua.execute(b"__events = {} WuxianKit:On('*', function(topic, data) "
                      b"__events[#__events + 1] = { topic = topic, data = data } end) __ns_changes = 0")
        s.login()
        s.run(1)
        s.ns.OnChange(s.lua.eval(b"function(what) if what == 'app' then __ns_changes = __ns_changes + 1 end end"))
        self.addCleanup(lambda: self.assertEqual(s.errors(), []))
        return s

    def agent(self, s, cap, args="{}"):
        s.lua.execute(f"__r = __fns[{cap!r}]({args})".encode())
        return py(s.g("__r"))

    def fails(self, s, cap, args="{}"):
        ok, err = s.lua.eval(f"pcall(__fns[{cap!r}], {args})".encode())
        self.assertFalse(ok, args)
        return err.decode()

    def events(self, s, topic):
        return [e["data"] for e in py(s.g("__events")) or [] if e["topic"] == topic]

    def listed(self, s, app):
        return next((a for a in self.agent(s, "kit.apps") if a["id"] == app), None)

    def launch(self, s, app):
        got = s.ns.AppLaunch(app.encode())
        ok, why = got if isinstance(got, tuple) else (got, None)          # (lupa: one value, not a tuple)
        return ok, why.decode() if isinstance(why, bytes) else why

    def test_the_driver(self):
        s = self.start()
        self.assertEqual(self.agent(s, "kit.app.open", "{ app = 'p', prompt = 'p-skill' }")["driver"], "prompt")
        self.assertEqual(self.agent(s, "kit.app.declare", "{ app = 'g', driver = 'program', hear = { 'game:combat' } }")
                         ["driver"], "program")
        self.assertNotIn("driver", self.agent(s, "kit.app.open", "{ app = 'n', title = 'N' }"))   # neither: none
        self.assertIn('driver "prompt" goes with prompt', self.fails(s, "kit.app.open", "{ app = 'x', driver = 'prompt' }"))
        self.assertIn("no argument docs", self.fails(s, "kit.app.open", "{ app = 'x', docs = 'Apps/X' }"))   # addons only
        s.lua.execute(b"WuxianKit:App('ad', { title = 'AD', addon = 'WxAd', docs = '\\\\Apps\\\\Ad\\\\', driver = 'program' })")
        ad = next(a for a in py(s.lua.eval(b"WuxianKit:Manifest()"))["apps"] if a["id"] == "ad")
        self.assertEqual((ad["docs"], ad["driver"], ad["launch"], ad["temp"]), ("WxAd/Apps/Ad", "program", False, False))
        guild = next(a for a in py(s.lua.eval(b"WuxianKit:Manifest()"))["apps"] if a["id"] == "guild")
        self.assertEqual((guild["docs"], guild["driver"]), ("WuxianKit/Apps/Guild", "prompt"))

    def test_declare_keeps_without_starting_and_is_no_heartbeat(self):
        s = self.start()
        rev = py(s.lua.eval(b"WuxianKit:Manifest()"))["revision"]
        decl = "{ app = 'comp', title = 'Companion', driver = 'program', hear = { 'game:combat' }, see = { 'me' }, lease = 60 }"
        st = self.agent(s, "kit.app.declare", decl)
        self.assertEqual((st["on"], st["by"], st["driver"], st["launch"], st["lease"]), (False, "agent", "program", False, 60))
        self.assertNotIn("seen", st)
        self.assertEqual(self.events(s, "kit.app"), [])                        # not started
        self.assertIsNotNone(s.lua.eval(b"WuxianKitDB.apps.comp.decl"))        # kept
        s.run(1)
        rev2 = py(s.lua.eval(b"WuxianKit:Manifest()"))["revision"]
        self.assertNotEqual(rev2, rev)
        changed = len(self.events(s, "kit.changed"))
        self.agent(s, "kit.app.declare", decl)                                 # the same again: nothing changed
        s.run(1)
        self.assertEqual(len(self.events(s, "kit.changed")), changed)
        self.assertIn("no app ghost: kit.app.declare gives", self.fails(s, "kit.app.declare", "{ app = 'ghost' }"))

        st = self.agent(s, "kit.app.open", "{ app = 'comp' }")                 # the program starts it
        self.assertEqual((st["on"], st["seen"]), (True, s.lua.eval(b"time()")))
        s.run(50)
        self.agent(s, "kit.app.declare", "{ app = 'comp', launch = true }")    # no heartbeat
        s.run(15)
        st = self.agent(s, "kit.app.declare", "{ app = 'comp' }")
        self.assertEqual((st["on"], st["why"], st["launch"]), (False, "left", True))

    def test_declare_while_running_hears_the_new_declaration(self):
        s = self.start()
        self.agent(s, "kit.app.open", "{ app = 'r', hear = { 'bus:demo.*' }, lease = 0 }")
        st = self.agent(s, "kit.app.declare", "{ app = 'r', hear = { 'bus:other.*' }, lease = 0 }")
        self.assertEqual((st["on"], st["hear"]), (True, ["bus:other.*"]))      # it runs on
        s.lua.execute(b"WuxianKit:Emit('demo.a', 1) WuxianKit:Emit('other.b', 2)")
        heard = [i["topic"] for w in self.events(s, "app.r") for i in w["items"]]
        self.assertEqual(heard, ["other.b"])
        self.assertEqual([e["on"] for e in self.events(s, "kit.app")], [True])   # no stop, no new start

    def test_declare_an_addons_app(self):
        s = self.start()
        st = self.agent(s, "kit.app.declare", "{ app = 'guild', title = 'Mine', hear = { 'bus:x' }, launch = true }")
        self.assertEqual((st["title"], st["by"], st["ignored"], st["launch"]), ("Guild chat", "addon", ["hear", "title"], True))
        self.assertIs(self.listed(s, "guild")["launch"], True)

    def test_launch(self):
        s = self.start(online=False)
        self.agent(s, "kit.app.declare", "{ app = 'comp', title = 'Companion', driver = 'program', "
                                         "hear = { 'game:combat' }, lease = 0 }")
        self.assertEqual(self.launch(s, "comp"), (False, "Driven by a program on this computer"))   # no launch
        self.assertEqual(self.launch(s, "nope"), (False, "No app nope"))
        self.agent(s, "kit.app.declare", "{ app = 'comp', launch = true }")
        self.assertIs(s.ns.WorkshopOnline(), False)
        self.assertEqual(self.launch(s, "comp"), (False, "Needs 无限工坊 running"))
        self.assertEqual(self.events(s, "kit.app.launch"), [])
        s.lua.execute(b"__online = true")
        self.assertIs(s.ns.WorkshopOnline(), True)
        before = s.lua.eval(b"__ns_changes")
        self.assertEqual(self.launch(s, "comp"), (True, None))
        self.assertEqual(self.events(s, "kit.app.launch"), [{"app": "comp"}])
        self.assertGreater(s.lua.eval(b"__ns_changes"), before)                # the window hears launching start
        self.assertIs(self.listed(s, "comp")["launching"], True)
        self.assertEqual(self.launch(s, "comp"), (False, "Starting…"))
        s.run(31)
        self.assertIs(self.listed(s, "comp")["launching"], False)              # 30 s and no start: over
        self.assertEqual(self.launch(s, "comp"), (True, None))
        self.agent(s, "kit.app.open", "{ app = 'comp' }")                      # the program started it
        self.assertIs(self.listed(s, "comp")["launching"], False)
        self.assertEqual(self.launch(s, "comp"), (False, "Already running"))
        self.assertEqual(len(self.events(s, "kit.app.launch")), 2)
        s.run(31)                                                              # the old timer clears nothing new
        self.agent(s, "kit.app.stop", "{ app = 'comp' }")
        s.ns.Switch(b"game", False)                                           # blocked: refused with its reason
        self.assertEqual(self.launch(s, "comp"), (False, "Needs the Game events extension on"))
        s.ns.Switch(b"game", True)
        self.agent(s, "kit.app.declare", "{ app = 'comp', launch = false }")
        self.assertEqual(self.launch(s, "comp"), (False, "Driven by a program on this computer"))
        self.agent(s, "kit.app.declare", "{ app = 'comp', launch = true }")
        s2 = self.start(s.reload())                                            # launch is in memory: declared again
        self.assertIs(self.listed(s2, "comp")["launch"], False)
        self.assertEqual(self.listed(s2, "comp")["driver"], "program")

    def test_temporary_apps(self):
        s = self.start()
        for i in range(8):
            self.agent(s, "kit.app.open", f"{{ app = 'k{i}', title = 'K{i}' }}")
        for i in range(4):                                                     # not one of the 8
            st = self.agent(s, "kit.app.open", f"{{ app = 't{i}', temp = true, hear = {{ 'bus:t{i}' }}, lease = 0 }}")
            self.assertEqual((st["on"], st["temp"]), (True, True))
        self.assertIn("at most 4 temporary apps",
                      self.fails(s, "kit.app.open", "{ app = 't4', temp = true, hear = { 'bus:t4' } }"))
        self.assertIsNone(s.lua.eval(b"WuxianKitDB.apps.t0"))                 # not kept
        self.assertIs(self.listed(s, "t0")["temp"], True)
        s.lua.execute(b"WuxianKit:Emit('t0', 'hi')")
        self.assertEqual(self.agent(s, "kit.app.recent", "{ app = 't0' }")["items"][0]["data"], "hi")
        st = self.agent(s, "kit.app.stop", "{ app = 't0' }")                   # gone once stopped
        self.assertEqual((st["on"], st["why"]), (False, "stopped"))
        self.assertIsNone(self.listed(s, "t0"))
        self.assertIn("no app t0", self.fails(s, "kit.app.status", "{ app = 't0' }"))
        st = self.agent(s, "kit.app.open", "{ app = 't1', temp = true, hear = { 'bus:t1' }, lease = 0 }")
        self.assertEqual(st["on"], True)                                       # the same again: it goes on
        self.assertIn("at most 8 apps an agent declared",                     # kept now: the 8 are there
                      self.fails(s, "kit.app.open", "{ app = 't1', hear = { 'bus:t1' }, lease = 0 }"))
        self.assertIs(self.listed(s, "t1")["temp"], True)
        st = self.agent(s, "kit.app.open", "{ app = 'k0', temp = true }")      # temp without a declaration: ignored
        self.assertEqual((st["on"], st["temp"], st["ignored"]), (True, False, ["temp"]))
        s2 = self.start(s.reload())                                            # a reload ends the others
        ids = [a["id"] for a in self.agent(s2, "kit.apps")]
        self.assertEqual([i for i in ids if i.startswith("t")], [])
        st = self.agent(s2, "kit.app.open", "{ app = 'guild', temp = true }")   # an addon's app: ignored
        self.assertEqual((st["temp"], st["ignored"]), (False, ["temp"]))

    def test_a_blocked_temporary_app_is_not_kept(self):
        s = self.start()
        s.ns.Switch(b"game", False)
        st = self.agent(s, "kit.app.open", "{ app = 'tmp', temp = true, hear = { 'game:quest' } }")
        self.assertEqual((st["on"], st["temp"], st["blocked"]), (False, True, "Needs the Game events extension on"))
        self.assertIsNone(self.listed(s, "tmp"))

    def test_kept_and_temporary_swap(self):
        s = self.start()
        self.agent(s, "kit.app.open", "{ app = 'sw', title = 'Kept', hear = { 'bus:a' }, lease = 0 }")
        self.assertIsNotNone(s.lua.eval(b"WuxianKitDB.apps.sw"))
        st = self.agent(s, "kit.app.open", "{ app = 'sw', title = 'Temp', hear = { 'bus:a' }, temp = true, lease = 0 }")
        self.assertEqual((st["on"], st["temp"], st["title"]), (True, True, "Temp"))
        self.assertIsNone(s.lua.eval(b"WuxianKitDB.apps.sw"))                 # what was kept of it went
        self.assertEqual([e.get("why") for e in self.events(s, "kit.app")], [None, "replaced", None])
        st = self.agent(s, "kit.app.open", "{ app = 'sw', title = 'Kept again', hear = { 'bus:a' }, lease = 0 }")
        self.assertEqual((st["on"], st["temp"]), (True, False))
        self.assertEqual(s.lua.eval(b"WuxianKitDB.apps.sw.decl.title"), b"Kept again")


if __name__ == "__main__":
    unittest.main()
