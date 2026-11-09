"""Feed items in 0.5 (ARCHITECTURE section 5): ids and times, the ring a feed keeps (keep = n, <name>.recent, through
reloads, afresh for another character), the digest (urgent, full, batch and idle wakes, its parameters changed in place,
a wake kept under its size), the status counters and when the agent last called (seen, from an agent's call through a
WoWBridge stub), and the digest's ticker, which runs only while a digest feed does."""
import unittest

from kitmock import Session, lupa, py
from test_standalone import bridge

DEFINE = b"""
local x = WuxianKit:Extension('dg', { title = 'DG' })
__x = x
__f = x:Feed('talk', { title = 'Talk', event = 'said', keep = 5, events = { 'CHAT_MSG_SAY' },
	doc = 'hears /say', eventDoc = 'a line said: {text}', options = { quiet = 'number?' },
	read = function(self, ev, text) return { text = text } end,
	digest = { gather = 3, every = 20, most = 4,
		urgent = function(self, o, item) return type(item.text) == 'string' and item.text:find('!') ~= nil end } })
__p = x:Feed('plain', { title = 'Plain', keep = 3, read = function() end })
"""

TICKERS = b"""
__tickers = {}
local new = C_Timer.NewTicker
C_Timer.NewTicker = function(d, fn)
	local t = new(d, fn)
	local rec = { d = d, live = true }
	__tickers[#__tickers + 1] = rec
	local cancel = t.Cancel
	t.Cancel = function(...) rec.live = false return cancel(...) end
	return t
end
"""


@unittest.skipIf(lupa is None, "lupa (Lua 5.1 for Python) is not installed")
class Digest(unittest.TestCase):
    def start(self, s=None, **kw):
        s = s or Session(self, **kw)
        s.lua.execute(b"__events = {} WuxianKit:On('*', function(topic, data) "
                      b"__events[#__events + 1] = { topic = topic, data = data } end)")
        s.login()
        s.lua.execute(DEFINE)
        s.run(1)                                                   # on once its file has run
        self.addCleanup(lambda: self.assertEqual(s.errors(), []))
        return s

    def call(self, s, cap, args="{}"):
        s.lua.execute(f"__answer = WuxianKit:Call({cap!r}, {args})".encode())
        return py(s.g("__answer"))

    def wakes(self, s):
        return [e["data"] for e in py(s.g("__events")) or [] if e["topic"] == "dg.said"]

    def push(self, s, *texts):
        for t in texts:
            self.assertTrue(s.lua.eval(f"__f:Push({{ text = {t!r} }})".encode()))

    def live(self, s):
        return [t["live"] for t in py(s.g("__tickers")) or [] if t["d"] == 1]

    def test_ids_times_and_the_ring(self):
        s = self.start()
        self.call(s, "dg.plain")
        for item in ("{ a = 1 }", "{ id = 50 }", "{ b = 2 }", "{ time = 5 }"):
            self.assertTrue(s.lua.eval(f"__p:Push({item})".encode()))
        now = s.lua.eval(b"time()")
        heard = [e["data"] for e in py(s.g("__events")) if e["topic"] == "dg.plain"]
        self.assertEqual([(h["id"], h["time"]) for h in heard], [(1, now), (50, now), (51, now), (52, 5)])
        self.assertEqual(self.call(s, "dg.plain.recent"), {"items": [{"id": 50, "time": now}, {"id": 51, "b": 2,
                                                                      "time": now}, {"id": 52, "time": 5}], "next": 52})
        self.assertEqual(self.call(s, "dg.plain.recent", "{ since = 50, limit = 1 }")["items"], [{"id": 52, "time": 5}])
        empty = self.call(s, "dg.plain.recent", "{ since = 52 }")
        self.assertEqual((empty["items"], empty["next"]), ({}, 52))
        self.assertEqual(py(s.lua.eval(b"__p:Recent(52)"))["next"], 52)
        self.assertEqual(py(s.lua.eval(b"__p:Item(51)"))["b"], 2)
        self.assertIsNone(s.lua.eval(b"__p:Item(1)"))                  # out of the ring
        self.call(s, "dg.plain.stop")
        self.assertEqual(self.call(s, "dg.plain.recent")["next"], 52)   # the ring stays after a stop
        self.assertIsNone(s.lua.eval(b"WuxianKit:Capability('dg.nothing.recent')"))
        s.lua.execute(b"__x:Feed('nokeep', { read = function() end })")
        self.assertIsNone(s.lua.eval(b"WuxianKit:Capability('dg.nokeep.recent')"))   # no keep, no recent

        s2 = s.reload()                                                 # through a reload: the ring and its counter
        s2 = self.start(s2)
        self.assertEqual(self.call(s2, "dg.plain.recent")["next"], 52)
        self.call(s2, "dg.plain")
        s2.lua.eval(b"__p:Push({})")
        self.assertEqual(self.call(s2, "dg.plain.recent", "{ since = 52 }")["items"][0]["id"], 53)

        s3 = s2.reload()                                                # another character starts the ring afresh
        s3.lua.execute(b"__guid = 'Player-1-00000002'")
        s3 = self.start(s3)
        recent = self.call(s3, "dg.plain.recent", "{ since = 53 }")
        self.assertEqual(py(s3.lua.eval(b"#__p:Recent().items")), 0)
        self.assertEqual(recent["next"], 53)                            # (since, when it has none)
        self.call(s3, "dg.plain")
        s3.lua.eval(b"__p:Push({})")
        self.assertEqual(self.call(s3, "dg.plain.recent")["items"][0]["id"], 54)   # the core's one counter goes on

    def test_urgent_full_and_batch(self):
        s = self.start()
        status = self.call(s, "dg.talk")
        self.assertEqual((status["on"], status["heard"], status["wakes"], status.get("lastWake")), (True, 0, 0, None))
        s.fire("CHAT_MSG_SAY", "hi")
        self.push(s, "help!")
        s.run(1.5)
        self.assertEqual(self.wakes(s), [])                             # gather: 3 s to finish talking
        s.run(3)
        w = self.wakes(s)
        self.assertEqual([(x["reason"], [i["text"] for i in x["items"]], x["skipped"]) for x in w],
                         [("urgent", ["hi", "help!"], 0)])
        self.assertEqual([i["id"] for i in w[0]["items"]], [1, 2])
        self.push(s, "a", "b", "c", "d")                                # at most 4: at once
        self.assertEqual([(x["reason"], len(x["items"])) for x in self.wakes(s)][1:], [("full", 4)])
        self.push(s, "later")
        s.run(18)
        self.assertEqual(len(self.wakes(s)), 2)
        s.run(3)                                                        # every 20 s after the first gathered
        self.assertEqual([(x["reason"], [i["text"] for i in x["items"]]) for x in self.wakes(s)][2:],
                         [("batch", ["later"])])
        status = self.call(s, "dg.talk.status")
        self.assertEqual((status["heard"], status["wakes"]), (7, 3))
        self.assertAlmostEqual(status["lastWake"], s.now(), delta=4)
        self.assertNotIn("seen", status)                                # no agent call yet
        self.assertEqual([i["text"] for i in self.call(s, "dg.talk.recent")["items"]], ["a", "b", "c", "d", "later"])

    def test_changed_in_place_every_false_and_idle(self):
        s = self.start()
        self.call(s, "dg.talk")
        s.lua.execute(b"__f:Running().digest.every = false")
        self.push(s, "x")
        s.run(60)
        self.assertEqual(self.wakes(s), [])                             # only urgent or full now
        s.lua.execute(b"__f:Running().digest.most = 2")
        self.push(s, "y")
        self.assertEqual([(w["reason"], len(w["items"])) for w in self.wakes(s)], [("full", 2)])
        s.lua.execute(b"__f:Running().digest.idle = 30")
        s.run(29)
        self.assertEqual(len(self.wakes(s)), 1)
        s.run(2)                                                        # 30 s without an item or a wake
        s.run(28)
        self.assertEqual([(w["reason"], w["items"]) for w in self.wakes(s)][1:], [("idle", {})])
        s.run(3)                                                        # and again after another 30
        w = self.wakes(s)
        self.assertEqual([x["reason"] for x in w], ["full", "idle", "idle"])
        status = self.call(s, "dg.talk.status")
        self.assertEqual((status["wakes"], status["digest"]), (3, {"every": False, "most": 2, "idle": 30}))
        self.call(s, "dg.talk")                                         # started again: the run afresh
        status = self.call(s, "dg.talk.status")
        self.assertEqual((status["heard"], status["wakes"], status["digest"]), (0, 0, {}))
        self.push(s, "z")
        self.call(s, "dg.talk")
        s.run(25)
        self.assertEqual(len(self.wakes(s)), 3)                         # what was gathered went with the old run
        self.assertEqual(self.call(s, "dg.talk.recent")["items"][-1]["text"], "z")   # the ring keeps it

    def test_prepare_fills_digest(self):
        s = self.start()
        s.lua.execute(b"__q = __x:Feed('quick', { event = 'q', options = { gather = 'number?' }, read = function() end, "
                      b"digest = { every = 50 }, prepare = function(self, o) return { digest = { every = o.gather } } end })")
        self.call(s, "dg.quick", "{ gather = 2 }")
        s.lua.eval(b"__q:Push({ n = 1 })")
        s.run(3.5)
        self.assertEqual([e["data"]["reason"] for e in py(s.g("__events")) if e["topic"] == "dg.q"], ["batch"])

    def test_a_wake_kept_under_its_size(self):
        s = self.start()
        self.call(s, "dg.talk")
        s.lua.execute(b"__f:Running().digest.most = 10")
        for i in range(8):
            s.lua.eval(f"__f:Push({{ text = '{i}' .. string.rep('x', 1000) }})".encode())
        s.run(21)
        w = self.wakes(s)[0]
        self.assertEqual(w["reason"], "batch")
        self.assertGreater(w["skipped"], 0)
        self.assertEqual(len(w["items"]) + w["skipped"], 8)
        self.assertEqual(w["items"][-1]["text"][0], "7")                # the oldest go
        self.assertEqual(w["items"][0]["id"], w["skipped"] + 1)
        size = s.lua.eval(b"#WuxianKit.Comm.Serialize(__events[#__events].data)")
        self.assertLessEqual(size, 5500)
        kept = self.call(s, "dg.talk.recent")["items"]                  # the ring keeps them, cut small
        self.assertEqual(len(kept), 5)
        self.assertTrue(all(len(i["text"].encode()) <= 503 for i in kept))

    def test_declared_event_and_doc(self):
        s = self.start()
        doc = py(s.lua.eval(b"WuxianKit:Capability('dg.talk')"))["doc"]
        self.assertIn("Items are gathered", doc)
        events = next(e for e in py(s.lua.eval(b"WuxianKit:Manifest()"))["extensions"] if e["id"] == "dg")["events"]
        said = next(e for e in events if e["topic"] == "dg.said")
        self.assertEqual(said["data"], {"reason": "urgent|full|batch|idle", "items": "table", "skipped": "number"})
        self.assertIn("a line said: {text}", said["doc"])
        plain = next(e for e in events if e["topic"] == "dg.plain")
        self.assertNotIn("data", plain)
        self.assertEqual(py(s.lua.eval(b"WuxianKit:Capability('dg.talk.recent')"))["args"],
                         {"since": "number?", "limit": "number?"})

    def test_seen_from_an_agent_call(self):
        s = self.start(saved={"WoWBridge": bridge("0.9.7")})
        self.call(s, "dg.talk")
        self.assertNotIn("seen", self.call(s, "dg.talk.status"))         # an addon's call is not the agent's
        s.run(10)
        s.lua.execute(b"__agent = __fns['dg.talk.recent']({ since = 0 })")
        at = int(s.now())
        status = self.call(s, "dg.talk.status")
        self.assertEqual(status["seen"], at)
        s.run(5)
        s.lua.execute(b"__x:Do('poke', { title = 'Poke', apply = function() end })")
        s.lua.execute(b"__fns['kit.propose']({ title = 'poke', steps = { { cap = 'dg.poke', args = {} } } })")
        self.assertEqual(self.call(s, "dg.talk.status")["seen"], at + 5)  # a step of kit.propose reaches it too

    def test_the_ticker_runs_only_while_a_digest_feed_does(self):
        s = Session(self)
        s.lua.execute(TICKERS)
        s = self.start(s)
        self.call(s, "dg.plain")
        self.assertEqual(self.live(s), [])                             # a feed without digest needs none
        self.call(s, "dg.talk")
        self.assertEqual(self.live(s), [True])
        self.call(s, "dg.talk")                                         # one, started again or not
        self.assertEqual(self.live(s), [True])
        self.call(s, "dg.talk.stop")
        self.assertEqual(self.live(s), [False])
        self.call(s, "dg.talk", "{ minutes = 1 }")
        self.push(s, "before the reload")
        self.assertEqual(self.live(s), [False, True])
        s2 = s.reload()                                                 # it runs on after a reload, gathered and all
        s2.lua.execute(TICKERS)
        s2 = self.start(s2)
        s2.run(6)
        self.assertEqual(self.live(s2), [True])
        s2.run(20)
        self.assertEqual([[i["text"] for i in w["items"]] for w in self.wakes(s2)], [["before the reload"]])
        s2.run(40)                                                      # its minute is over
        self.assertEqual(self.live(s2), [False])
        self.assertFalse(self.call(s2, "dg.talk.status")["on"])


if __name__ == "__main__":
    unittest.main()
