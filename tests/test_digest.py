"""The digest and what goes with it (Core/Digest.lua), as apps use it: ids and times of the items a source gives (an
item's own id moves the core's one counter on; the rings move it on at load), urgent, full, batch and idle wakes, the
ticker that runs only while an app does, the lease kept through a reload; and the helpers themselves (ns.Digest.Params,
ns.Digest.Small, ns.UrgentList, ns.Lease, ns.RingRecent)."""
import unittest

from kitmock import Session, lupa, py
from test_standalone import bridge

# a source of the test's own: dg:a, dg:b or dg:*; __push(what, item) hands an item to whoever subscribed
DEFINE = b"""
local x = WuxianKit:Extension('dg', { title = 'DG' })
__x, __subs, __n = x, {}, 0
x:Source('dg', { title = 'DG items', doc = 'dg:a, dg:b or dg:*: what the test pushes', values = { 'a', 'b' },
	check = function(what) if what ~= 'a' and what ~= 'b' and what ~= '*' then return 'a dg source is a, b or *' end end,
	covers = function(a, b) return a == '*' and b ~= '*' end,
	on = function(self, what, fn) __n = __n + 1 __subs[__n] = { what = what, fn = fn } return __n end,
	off = function(self, t) __subs[t] = nil end })
function __push(what, item)
	for _, s in pairs(__subs) do if s.what == what or s.what == '*' then s.fn(item) end end
end
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
        s.lua.execute(DEFINE)
        s.login()
        s.run(1)
        self.addCleanup(lambda: self.assertEqual(s.errors(), []))
        return s

    def call(self, s, cap, args="{}"):
        s.lua.execute(f"__answer = WuxianKit:Call({cap!r}, {args})".encode())
        return py(s.g("__answer"))

    def agent(self, s, cap, args="{}"):
        s.lua.execute(f"__answer = __fns[{cap!r}]({args})".encode())
        return py(s.g("__answer"))

    def wakes(self, s, app):
        return [e["data"] for e in py(s.g("__events")) or [] if e["topic"] == "app." + app]

    def push(self, s, what, *texts, **fields):
        for t in texts:
            extra = "".join(f", {k} = {v!r}" for k, v in fields.items())
            s.lua.execute(f"__push({what!r}, {{ text = {t!r}{extra} }})".encode())

    def live(self, s):
        return [t["live"] for t in py(s.g("__tickers")) or [] if t["d"] == 1]

    def test_ids_and_times(self):
        s = self.start()
        self.call(s, "kit.app.open", "{ app = 'p', hear = { 'dg:a' }, lease = 0 }")
        a = s.lua.eval(b"WuxianKit:NewId()")
        for item in ("{ a = 1 }", "{ id = 500 }", "{ b = 2 }", "{ time = 5 }"):
            s.lua.execute(f"__push('a', {item})".encode())
        now = s.lua.eval(b"time()")
        items = [w["items"][0] for w in self.wakes(s, "p")]
        self.assertEqual([(i["id"], i["time"], i["source"]) for i in items],
                         [(a + 1, now, "dg"), (500, now, "dg"), (501, now, "dg"), (502, 5, "dg")])
        self.assertEqual(s.lua.eval(b"WuxianKit:NewId()"), 503)             # an item's own id moved the counter on
        recent = self.call(s, "kit.app.recent", "{ app = 'p', since = 500, limit = 1 }")
        self.assertEqual((recent["items"][0]["id"], recent["next"]), (502, 502))

    def test_ids_go_on_from_the_rings(self):
        saved = {"WuxianKitDB": b"{ apps = { old = { recent = { who = 'Player-1-00000001', n = 900, items = {} } } } }"}
        s = self.start(saved=saved)
        self.assertEqual(s.lua.eval(b"WuxianKit:NewId()"), 901)

    def test_urgent_full_and_batch(self):
        s = self.start()
        self.call(s, "kit.app.open", "{ app = 't', hear = { 'dg:a' }, lease = 0, urgent = { 'question' }, "
                                     "digest = { gather = 3, every = 20, most = 4 } }")
        self.push(s, "a", "hi")
        self.push(s, "a", "help?", why="question")
        s.run(1.5)
        self.assertEqual(self.wakes(s, "t"), [])                         # gather: 3 s to finish talking
        s.run(3)
        self.assertEqual([(w["reason"], [i["text"] for i in w["items"]], w["skipped"]) for w in self.wakes(s, "t")],
                         [("urgent", ["hi", "help?"], 0)])
        self.push(s, "a", "a", "b", "c", "d")                            # at most 4: at once
        self.assertEqual([(w["reason"], len(w["items"])) for w in self.wakes(s, "t")][1:], [("full", 4)])
        self.push(s, "a", "later")
        s.run(18)
        self.assertEqual(len(self.wakes(s, "t")), 2)
        s.run(3)                                                         # every 20 s after the first gathered
        self.assertEqual([(w["reason"], [i["text"] for i in w["items"]]) for w in self.wakes(s, "t")][2:],
                         [("batch", ["later"])])
        status = self.call(s, "kit.app.status", "{ app = 't' }")
        self.assertEqual((status["heard"], status["wakes"]), (7, 3))
        self.assertAlmostEqual(status["lastWake"], s.now(), delta=4)

    def test_every_false_and_idle(self):
        s = self.start()
        self.call(s, "kit.app.open", "{ app = 'q', hear = { 'dg:b' }, lease = 0, "
                                     "digest = { every = false, idle = 30, most = 2 } }")
        self.push(s, "b", "x")
        s.run(25)
        self.assertEqual(self.wakes(s, "q"), [])                         # only full, urgent or idle
        self.push(s, "b", "y")
        self.assertEqual([(w["reason"], len(w["items"])) for w in self.wakes(s, "q")], [("full", 2)])
        s.run(28)
        self.assertEqual(len(self.wakes(s, "q")), 1)
        s.run(3)                                                         # 30 s without an item or a wake
        self.assertEqual([(w["reason"], len(w["items"])) for w in self.wakes(s, "q")][1:], [("idle", 0)])
        s.run(30)                                                        # and again after another 30
        self.assertEqual([w["reason"] for w in self.wakes(s, "q")], ["full", "idle", "idle"])

    def test_the_ticker_runs_only_while_an_app_does(self):
        s = Session(self)
        s.lua.execute(TICKERS)
        s = self.start(s)
        self.assertEqual(self.live(s), [])                              # no app runs
        self.call(s, "kit.app.open", "{ app = 'p', hear = { 'dg:a' }, lease = 0 }")
        self.assertEqual(self.live(s), [True])
        self.call(s, "kit.app.open", "{ app = 'q', hear = { 'dg:b' }, lease = 0, digest = { every = 20 } }")
        self.call(s, "kit.app.open", "{ app = 'p' }")                    # one, however many run
        self.assertEqual(self.live(s), [True])
        self.call(s, "kit.app.stop", "{ app = 'p' }")
        self.call(s, "kit.app.stop", "{ app = 'q' }")
        s.run(1.5)
        self.assertEqual(self.live(s), [False])                          # gone once none runs
        self.call(s, "kit.app.open", "{ app = 'q', minutes = 1 }")
        self.push(s, "b", "before the reload")
        s2 = s.reload()                                                  # it runs on after a reload, gathered and all
        s2.lua.execute(TICKERS)
        s2 = self.start(s2)
        self.assertEqual(self.live(s2), [True])
        s2.run(30)
        self.assertEqual([[i["text"] for i in w["items"]] for w in self.wakes(s2, "q")], [["before the reload"]])
        s2.run(40)                                                       # its minute is over
        self.assertEqual(self.live(s2), [False])
        self.assertFalse(self.call(s2, "kit.app.status", "{ app = 'q' }")["on"])

    def test_the_lease_through_a_reload(self):
        s = self.start(saved={"WoWBridge": bridge("0.9.7")})
        self.agent(s, "kit.app.open", "{ app = 'l', title = 'L', hear = { 'dg:a' }, lease = 60 }")
        s.run(40)
        self.agent(s, "kit.app.status", "{ app = 'l' }")                 # the heartbeat, kept in its run
        s2 = self.start(s.reload())
        self.assertTrue(self.call(s2, "kit.app.status", "{ app = 'l' }")["present"])
        s2.run(40)
        self.assertTrue(self.call(s2, "kit.app.status", "{ app = 'l' }")["on"])
        s2.run(25)
        st = self.call(s2, "kit.app.status", "{ app = 'l' }")
        self.assertEqual((st["on"], st["why"]), (False, "left"))

    def test_the_helpers(self):
        s = self.start()
        ns = s.ns
        self.assertEqual([ns.Lease(v) for v in (0, 30, 90.7, b"x", -5)], [None, 60, 90, None, None])
        urgent = ns.UrgentList(s.lua.table_from({1: b"question", b"mention": True}))
        self.assertEqual([urgent(None, None, s.lua.table_from(t)) for t in
                          ({b"why": b"question"}, {b"kind": b"mention"}, {b"why": b"burst"})], [True, True, False])
        host = s.lua.eval(b"{ spec = { digest = { every = 45 } } }")
        run = s.lua.eval(b"{ options = { digest = { gather = -1, idle = false, most = 500 } } }")
        self.assertEqual(py(ns.Digest.Params(host, run)), {"gather": 0, "every": 45, "idle": False, "most": 200})
        self.assertEqual(py(ns.Digest.Params(s.lua.eval(b"{ spec = {} }"), s.lua.eval(b"{}"))),
                         {"gather": 5, "every": 60, "idle": False, "most": 30})
        small = py(ns.Digest.Small(s.lua.eval(b"{ text = string.rep('x', 600), a = { b = { c = { d = { e = { f = { g = 1 } } } } } }, "
                                               b"f = print }")))
        self.assertLessEqual(len(small["text"].encode()), 503)
        self.assertEqual((small["a"]["b"]["c"]["d"]["e"], "f" in small), ({}, False))    # six levels deep, data only
        items = s.lua.eval(b"{ { id = 3 }, { id = 4 }, { id = 7 } }")
        self.assertEqual(py(ns.RingRecent(items, 3, None, 100)), {"items": [{"id": 4}, {"id": 7}], "next": 7})
        self.assertEqual(py(ns.RingRecent(items, 0, 1, 100))["items"], [{"id": 7}])
        self.assertEqual(py(ns.RingRecent(s.lua.eval(b"{}"), 9, None, 100)), {"items": {}, "next": 9})


if __name__ == "__main__":
    unittest.main()
