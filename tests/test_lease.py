"""Feeds in 0.6 (ARCHITECTURE section 5): the lease (stops when the agent has not called the extension for that long,
why "left"; present in the status; through a reload), why in every kit.feed stop (stopped, expired, left, extension),
feed:Push(data, { key, every }), ids from the core's one counter (an item's own id moves it on; the rings move it on at
load) and urgent as a list of whys and kinds."""
import unittest

from kitmock import Session, lupa, py
from test_standalone import bridge

DEFINE = b"""
local x = WuxianKit:Extension('lx', { title = 'LX' })
__x = x
__f = x:Feed('f', { title = 'Lf', keep = 5, lease = 60, options = { lease = 'number?' }, read = function() end })
__g = x:Feed('g', { title = 'Lg', keep = 5, read = function() end,
	digest = { gather = 2, every = false, urgent = { 'question', 'guild.join' } } })
x:See('ping', { title = 'Ping', run = function() return true end })
"""


@unittest.skipIf(lupa is None, "lupa (Lua 5.1 for Python) is not installed")
class Lease(unittest.TestCase):
    def start(self, s=None, **kw):
        kw.setdefault("saved", {"WoWBridge": bridge("0.9.7")})
        s = s or Session(self, **kw)
        s.lua.execute(b"__events = {} WuxianKit:On('*', function(topic, data) "
                      b"__events[#__events + 1] = { topic = topic, data = data } end)")
        s.login()
        s.lua.execute(DEFINE)
        s.run(1)
        self.addCleanup(lambda: self.assertEqual(s.errors(), []))
        return s

    def agent(self, s, cap, args="{}"):
        s.lua.execute(f"__r = __fns[{cap!r}]({args})".encode())
        return py(s.g("__r"))

    def call(self, s, cap, args="{}"):
        s.lua.execute(f"__r = WuxianKit:Call({cap!r}, {args})".encode())
        return py(s.g("__r"))

    def events(self, s, topic):
        return [e["data"] for e in py(s.g("__events")) or [] if e["topic"] == topic]

    def test_the_lease(self):
        s = self.start()
        st = self.agent(s, "lx.f")
        self.assertEqual((st["on"], st["lease"], st["present"]), (True, 60, True))
        self.assertIn("It stops by itself once you have not called", py(s.lua.eval(b"WuxianKit:Capability('lx.f')"))["doc"])
        s.run(50)
        self.agent(s, "lx.ping")                                          # any call of the extension's
        s.run(50)
        self.assertTrue(self.call(s, "lx.f.status")["present"])
        self.call(s, "lx.ping")                                           # an addon's call is no heartbeat
        s.run(15)
        st = self.call(s, "lx.f.status")
        self.assertFalse(st["on"])
        self.assertEqual(self.events(s, "kit.feed")[-1], {"extension": "lx", "feed": "f", "on": False, "why": "left"})
        self.assertIn("Lf: the agent left, stopped", s.chat())

        self.call(s, "lx.f", "{ lease = 0 }")                             # the running options' lease wins: none
        s.run(200)
        st = self.call(s, "lx.f.status")
        self.assertTrue(st["on"])
        self.assertNotIn("present", st)
        self.call(s, "lx.f", "{ lease = 10 }")                            # at least 60
        self.assertEqual(self.call(s, "lx.f.status")["lease"], 60)
        self.call(s, "lx.g")
        self.assertNotIn("lease", self.call(s, "lx.g.status"))            # no lease, no present

    def test_the_lease_through_a_reload(self):
        s = self.start()
        self.agent(s, "lx.f")
        s.run(40)
        self.agent(s, "lx.ping")
        s.run(6)                                                          # kept in the run (every 5 s)
        s2 = self.start(s.reload())                                       # 5 s later; ext.seen is gone
        self.assertTrue(self.call(s2, "lx.f.status")["present"])
        s2.run(40)
        self.assertTrue(self.call(s2, "lx.f.status")["on"])
        s2.run(20)
        self.assertEqual(self.events(s2, "kit.feed")[-1]["why"], "left")

    def test_why_it_stopped(self):
        s = self.start()
        self.call(s, "lx.g")
        self.call(s, "lx.g.stop")
        self.assertEqual(self.events(s, "kit.feed")[-1]["why"], "stopped")
        self.call(s, "lx.g", "{ minutes = 1 }")
        s.run(66)
        self.assertEqual(self.events(s, "kit.feed")[-1]["why"], "expired")
        self.call(s, "lx.g")
        s.ns.Switch(b"lx", False)
        self.assertEqual(self.events(s, "kit.feed")[-1], {"extension": "lx", "feed": "g", "on": False, "why": "extension"})
        starts = [e for e in self.events(s, "kit.feed") if e["on"]]
        self.assertTrue(all("why" not in e for e in starts))

    def test_push_throttle(self):
        s = self.start()
        self.call(s, "lx.f", "{ lease = 0 }")
        push = lambda args: s.lua.eval(f"__f:Push({{ n = 1 }}, {args})".encode())
        self.assertEqual([push("{ key = 'a', every = 10 }"), push("{ key = 'a', every = 10 }"),
                          push("{ key = 'b', every = 10 }"), push("nil")], [True, False, True, True])
        s.run(10.5)
        self.assertIs(push("{ key = 'a', every = 10 }"), True)
        self.assertEqual([push("{ every = 5 }"), push("{ every = 5 }")], [True, False])   # no key: the whole feed
        self.assertEqual(len(self.events(s, "lx.f")), 5)

    def test_ids_from_the_core(self):
        s = self.start()
        self.call(s, "lx.f", "{ lease = 0 }")
        a = s.lua.eval(b"WuxianKit:NewId()")
        s.lua.eval(b"__f:Push({})")
        s.lua.eval(b"__f:Push({ id = 500 })")
        b = s.lua.eval(b"WuxianKit:NewId()")
        s.lua.eval(b"__f:Push({})")
        ids = [e["id"] for e in self.events(s, "lx.f")]
        self.assertEqual(ids, [a + 1, 500, 502])
        self.assertEqual(b, 501)
        self.assertEqual(self.call(s, "lx.f.recent")["next"], 502)

    def test_ids_go_on_from_the_rings(self):
        saved = {"WoWBridge": bridge("0.9.7"),
                 "WuxianKitDB": b"{ ext = { lx = { recent = { f = { who = 'Player-1-00000001', n = 900, items = {} } } }, "
                                b"chat = { lastId = 950 } } }"}
        s = self.start(saved=saved)
        self.assertEqual(s.lua.eval(b"WuxianKit:NewId()"), 951)

    def test_urgent_as_a_list(self):
        s = self.start()
        self.call(s, "lx.g")
        s.lua.eval(b"__g:Push({ text = 'hi' })")
        s.run(30)
        self.assertEqual(self.events(s, "lx.g"), [])                      # every false: nothing batches
        s.lua.eval(b"__g:Push({ text = 'what?', why = 'question' })")
        s.run(3.5)
        self.assertEqual([w["reason"] for w in self.events(s, "lx.g")], ["urgent"])
        s.lua.eval(b"__g:Push({ kind = 'guild.join' })")                  # by its kind
        s.run(3.5)
        self.assertEqual([w["reason"] for w in self.events(s, "lx.g")], ["urgent", "urgent"])
        s.lua.eval(b"__g:Push({ why = 'burst', kind = 'say' })")
        s.run(10)
        self.assertEqual(len(self.events(s, "lx.g")), 2)


if __name__ == "__main__":
    unittest.main()
