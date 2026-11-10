"""Declarations (the layered kit): docs in the declaration, no driver or launch (an agent drives every app),
kit.app.declare (the whole declaration, kept without starting, no heartbeat; 无限工坊 declares a local extension's apps
so), and temporary apps (kit.app.open's temp, a table: the whole declaration of this run's; not kept, at most 4, not
one of the 8, gone once stopped or reloaded)."""
import unittest

from kitmock import Session, lupa, py
from test_standalone import bridge


@unittest.skipIf(lupa is None, "lupa (Lua 5.1 for Python) is not installed")
class Declared(unittest.TestCase):
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

    def test_docs_and_no_driver(self):
        s = self.start()
        self.agent(s, "kit.app.declare", "{ app = 'p', prompt = 'p-skill' }")
        st = self.agent(s, "kit.app.open", "{ app = 'p' }")
        self.assertEqual(st["start"].count("p-skill"), 1)
        for gone in ("driver", "launch", "launching"):                          # an agent drives every app
            self.assertNotIn(gone, st)
            self.assertNotIn(gone, self.listed(s, "p"))
        self.assertIn("no argument driver", self.fails(s, "kit.app.open", "{ app = 'x', driver = 'prompt' }"))
        self.assertIn("no argument driver", self.fails(s, "kit.app.declare", "{ app = 'x', driver = 'program' }"))
        self.assertIn("no argument launch", self.fails(s, "kit.app.declare", "{ app = 'x', launch = true }"))
        self.assertIsNone(self.listed(s, "x"))
        self.assertIn("no argument docs", self.fails(s, "kit.app.declare", "{ app = 'x', docs = 'Apps/X' }"))   # addons only
        self.assertIn("the declaration: no field docs",
                      self.fails(s, "kit.app.open", "{ app = 'x', temp = { docs = 'Apps/X' } }"))
        s.lua.execute(b"WuxianKit:App('ad', { title = 'AD', addon = 'WxAd', docs = '\\\\Apps\\\\Ad\\\\', driver = 'program' })")
        ad = next(a for a in py(s.lua.eval(b"WuxianKit:Manifest()"))["apps"] if a["id"] == "ad")
        self.assertEqual((ad["docs"], ad["temp"]), ("WxAd/Apps/Ad", False))
        self.assertNotIn("driver", ad)                                         # an addon's Lua: an unknown field, unread
        self.assertNotIn("launch", ad)
        guild = next(a for a in py(s.lua.eval(b"WuxianKit:Manifest()"))["apps"] if a["id"] == "guild")
        self.assertEqual(guild["docs"], "WuxianKit/Apps/Guild")

    def test_a_remembered_declaration_with_a_driver_is_dropped(self):
        s = self.start()
        self.agent(s, "kit.app.declare", "{ app = 'old', title = 'Old', hear = { 'game:combat' } }")
        s.lua.execute(b"WuxianKitDB.apps.old.decl.driver = 'program'")         # kept by a kit before 0.6's release
        s2 = self.start(s.reload())
        self.assertIsNone(self.listed(s2, "old"))
        self.assertIsNone(s2.lua.eval(b"WuxianKitDB.apps.old"))                # nothing of it is left behind
        self.assertIn("The app old's declaration no longer holds: removed", s2.chat())   # and the player is told

    def test_declare_keeps_without_starting_and_is_no_heartbeat(self):
        s = self.start()
        rev = py(s.lua.eval(b"WuxianKit:Manifest()"))["revision"]
        decl = ("{ app = 'comp', title = 'Companion', prompt = 'companion', hear = { 'game:combat' }, see = { 'me' }, "
                "lease = 60 }")
        st = self.agent(s, "kit.app.declare", decl)
        self.assertEqual((st["on"], st["by"], st["lease"]), (False, "agent", 60))
        self.assertIn("companion", st["start"])                                # its card: 交给 AI
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

        st = self.agent(s, "kit.app.open", "{ app = 'comp' }")                 # the agent opens it
        self.assertEqual((st["on"], st["seen"]), (True, s.lua.eval(b"time()")))
        s.run(50)
        self.agent(s, "kit.app.declare", decl)                                 # no heartbeat
        s.run(15)
        st = self.agent(s, "kit.app.declare", decl)
        self.assertEqual((st["on"], st["why"], st["changed"]), (False, "left", False))

    def test_declare_while_running_hears_the_new_declaration(self):
        s = self.start()
        self.agent(s, "kit.app.declare", "{ app = 'r', hear = { 'bus:demo.*' }, lease = 0 }")
        self.agent(s, "kit.app.open", "{ app = 'r' }")
        st = self.agent(s, "kit.app.declare", "{ app = 'r', hear = { 'bus:other.*' }, lease = 0 }")
        self.assertEqual((st["on"], st["hear"], st["changed"]), (True, ["bus:other.*"], True))   # it runs on
        s.lua.execute(b"WuxianKit:Emit('demo.a', 1) WuxianKit:Emit('other.b', 2)")
        heard = [i["topic"] for w in self.events(s, "app.r") for i in w["items"]]
        self.assertEqual(heard, ["other.b"])
        self.assertEqual([e["on"] for e in self.events(s, "kit.app")], [True])   # no stop, no new start

    def test_declare_an_addons_app(self):
        s = self.start()
        self.assertIn("app guild is an addon's (WuxianKit): its declaration is the addon's",   # an error, nothing ignored
                      self.fails(s, "kit.app.declare", "{ app = 'guild', title = 'Mine', hear = { 'bus:x' } }"))
        self.assertEqual(self.listed(s, "guild")["title"], "Guild chat")

    def test_a_local_extensions_app(self):
        """local {id, title}: a label, listed with it; the player removes such an app as any other of an agent's"""
        s = self.start()
        self.agent(s, "kit.app.declare", "{ app = 'buddy', title = 'Buddy', hear = { 'bus:x' }, "
                                         "['local'] = { id = 'voice', title = 'Voice' } }")
        self.assertEqual(self.listed(s, "buddy")["local"], {"id": "voice", "title": "Voice"})
        self.assertEqual(py(s.ns.AppStatus(b"buddy"))["local"], {"id": "voice", "title": "Voice"})
        self.assertIn("local is {id, title}", self.fails(s, "kit.app.declare",
                                                         "{ app = 'b2', title = 'B', ['local'] = { id = 'Bad Id' } }"))
        self.agent(s, "kit.app.declare", "{ app = 'b3', title = 'B3', hear = { 'bus:x' } }")
        for app in (b"buddy", b"b3"):                                  # the player's remove: all of it
            self.assertIs(s.ns.ForgetApp(app, True), True)
            self.assertIsNone(self.listed(s, app.decode()))
            self.assertIsNone(s.lua.eval(b"WuxianKitDB.apps." + app))
        self.assertIs(s.ns.ForgetApp(b"guild", True), False)           # an addon's stays

    def test_temporary_apps(self):
        s = self.start()
        for i in range(8):
            self.agent(s, "kit.app.declare", f"{{ app = 'k{i}', title = 'K{i}' }}")
            self.agent(s, "kit.app.open", f"{{ app = 'k{i}' }}")
        for i in range(4):                                                     # not one of the 8
            st = self.agent(s, "kit.app.open", f"{{ app = 't{i}', lease = 0, temp = {{ hear = {{ 'bus:t{i}' }} }} }}")
            self.assertEqual((st["on"], st["temp"]), (True, True))
        self.assertIn("at most 4 temporary apps",
                      self.fails(s, "kit.app.open", "{ app = 't4', temp = { hear = { 'bus:t4' } } }"))
        self.assertIsNone(s.lua.eval(b"WuxianKitDB.apps.t0"))                 # not kept
        self.assertIs(self.listed(s, "t0")["temp"], True)
        s.lua.execute(b"WuxianKit:Emit('t0', 'hi')")
        self.assertEqual(self.agent(s, "kit.app.recent", "{ app = 't0' }")["items"][0]["data"], "hi")
        st = self.agent(s, "kit.app.stop", "{ app = 't0' }")                   # gone once stopped
        self.assertEqual((st["on"], st["why"]), (False, "stopped"))
        self.assertIsNone(self.listed(s, "t0"))
        self.assertIn("no app t0", self.fails(s, "kit.app.status", "{ app = 't0' }"))
        st = self.agent(s, "kit.app.open", "{ app = 't1', lease = 0, temp = { hear = { 'bus:t1' } } }")
        self.assertEqual(st["on"], True)                                       # the same again: it goes on
        self.assertEqual([e["on"] for e in self.events(s, "kit.app") if e["app"] == "t1"], [True, True])
        self.assertIn("at most 8 apps an agent declared",                     # kept now: the 8 are there
                      self.fails(s, "kit.app.declare", "{ app = 't1', hear = { 'bus:t1' }, lease = 0 }"))
        self.assertIs(self.listed(s, "t1")["temp"], True)
        self.assertIn("temp is a table", self.fails(s, "kit.app.open", "{ app = 'k0', temp = true }"))   # a declaration
        self.assertIs(self.listed(s, "k0")["temp"], False)
        s2 = self.start(s.reload())                                            # a reload ends the others
        ids = [a["id"] for a in self.agent(s2, "kit.apps")]
        self.assertEqual([i for i in ids if i.startswith("t")], [])
        self.assertIn("app guild is an addon's",                               # an addon's app is never temporary
                      self.fails(s2, "kit.app.open", "{ app = 'guild', temp = {} }"))
        self.assertIs(self.listed(s2, "guild")["temp"], False)

    def test_a_blocked_temporary_app_is_not_kept(self):
        s = self.start()
        s.ns.Switch(b"game", False)
        st = self.agent(s, "kit.app.open", "{ app = 'tmp', temp = { hear = { 'game:quest' } } }")
        self.assertEqual((st["on"], st["temp"], st["blocked"]), (False, True, "Needs the Game events extension on"))
        self.assertIsNone(self.listed(s, "tmp"))
        self.assertEqual(self.events(s, "kit.app"), [])                        # never on: nothing to tell

    def test_kept_and_temporary_swap(self):
        s = self.start()
        self.agent(s, "kit.app.declare", "{ app = 'sw', title = 'Kept', hear = { 'bus:a' }, lease = 0 }")
        self.agent(s, "kit.app.open", "{ app = 'sw' }")
        self.assertIsNotNone(s.lua.eval(b"WuxianKitDB.apps.sw.decl"))
        st = self.agent(s, "kit.app.open", "{ app = 'sw', lease = 0, temp = { title = 'Temp', hear = { 'bus:a' } } }")
        self.assertEqual((st["on"], st["temp"], st["title"]), (True, True, "Temp"))
        self.assertIsNone(s.lua.eval(b"WuxianKitDB.apps.sw.decl"))            # the declaration kept of it went
        self.assertEqual([e.get("why") for e in self.events(s, "kit.app")], [None, "replaced", None])
        st = self.agent(s, "kit.app.declare", "{ app = 'sw', title = 'Kept again', hear = { 'bus:a' }, lease = 0 }")
        self.assertEqual((st["on"], st["temp"], st["why"]), (False, False, "replaced"))   # the temporary run ended
        st = self.agent(s, "kit.app.open", "{ app = 'sw' }")
        self.assertEqual((st["on"], st["temp"]), (True, False))
        self.assertEqual(s.lua.eval(b"WuxianKitDB.apps.sw.decl.title"), b"Kept again")
        self.assertEqual([e.get("why") for e in self.events(s, "kit.app")], [None, "replaced", None, "replaced", None])


if __name__ == "__main__":
    unittest.main()
