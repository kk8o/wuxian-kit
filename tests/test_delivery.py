"""Reliable delivery of an app's items (Core/Digest.lua, Core/Apps/Deliver.lua, Core/Bridge.lua's ns.SendWake): a wake
WoWBridge does not take is sent again with nothing twice and nothing missing, the bus hears a wake once and only when it
went; seq, after and next chain through a run, an idle wake and a new run; the buffer's cap and skipped; quiet hours
(no full wake, the buffer at most `most`, a mention still wakes); an item is the core's copy with the core's id (the
source's as ref), the same one in the ring and the wake, within its size; a wake within WoWBridge's line whatever the
state; a character's ring is its own and reading makes none."""
import unittest

from kitmock import Session, lupa, py
from test_apps import AppCase
from test_apps_pace import CHAT, at
from test_digest import DEFINE
from test_standalone import bridge

# WoWBridge's Emit for the stub: it takes an app's wake (kept in __got, as the agent gets it) unless __take is false
# (counted in __refused: no room, as its queue answers)
TAKE = ("if topic:sub(1, 4) == 'app.' then if __take == false then __refused = (__refused or 0) + 1 return false end "
        "__got = __got or {} __got[#__got + 1] = data end return true")

ME, OTHER = "Player-1-00000001", "Player-1-00000002"


@unittest.skipIf(lupa is None, "lupa (Lua 5.1 for Python) is not installed")
class DeliveryCase(AppCase):
    def start(self, s=None, guid=None, **kw):
        if s is None:
            kw.setdefault("saved", {"WoWBridge": bridge("0.9.7", emit=TAKE)})
            s = Session(self, **kw)
        s.lua.execute(DEFINE)
        return super().start(s, guid=guid)

    def push(self, s, *texts):
        for t in texts:
            s.lua.execute(f"__push('a', {{ text = {t!r} }})".encode())

    def take(self, s, yes):
        s.lua.execute(b"__take = nil" if yes else b"__take = false")

    def got(self, s, app):
        """the wakes the agent got (the bus's are self.wakes)"""
        return [w for w in py(s.g("__got")) or [] if w["app"] == app]

    def texts(self, ws):
        return [[i["text"] for i in w["items"]] for w in ws]

    def state(self, s, app, guid=None):
        who = f"'{guid}'" if guid else "UnitGUID('player')"
        return self.lua(s, f"WuxianKitDB.apps.{app}.chars[{who}].run")

    def ring(self, s, app, guid=None):
        who = f"'{guid}'" if guid else "UnitGUID('player')"
        return self.lua(s, f"WuxianKitDB.apps.{app}.chars[{who}].recent.items")

    def chained(self, ws):
        """seq from 1 without a gap, each wake from where the one before ended, its items within (after, next]"""
        for n, w in enumerate(ws):
            ids = [i["id"] for i in w["items"]]
            self.assertEqual(w["seq"], n + 1)
            if n:
                self.assertEqual(w["after"], ws[n - 1]["next"])
            self.assertEqual(ids, sorted(set(ids)))
            self.assertTrue(all(w["after"] < i <= w["next"] for i in ids), w)
            self.assertEqual(w["next"], ids[-1] if ids else w["after"])


class Resend(DeliveryCase):
    def test_a_wake_that_does_not_go_is_sent_again(self):
        s = self.start()
        self.opens(s, "{ app = 'p', hear = { 'dg:a' }, lease = 0 }")
        self.push(s, "one")
        self.assertEqual(self.texts(self.got(s, "p")), [["one"]])
        one = self.got(s, "p")[0]["next"]
        self.take(s, False)
        self.push(s, "two", "three")
        s.run(3.5)
        self.assertGreaterEqual(self.lua(s, "__refused"), 3)             # asked again every second
        self.assertEqual((len(self.got(s, "p")), len(self.wakes(s, "p"))), (1, 1))   # nobody heard one that did not go
        run = self.state(s, "p")
        self.assertEqual((run["wakes"], run["sent"], [i["text"] for i in run["buffer"]], run["reason"]),
                         (1, one, ["two", "three"], "item"))
        st = self.agent(s, "kit.app.status", "{ app = 'p' }")
        self.assertEqual((st["heard"], st["wakes"]), (3, 1))
        self.assertEqual(st["next"], run["buffer"][1]["id"])              # (the ring has them meanwhile)
        self.take(s, True)
        s.run(1.5)
        ws = self.got(s, "p")
        self.assertEqual(self.texts(ws), [["one"], ["two", "three"]])     # nothing twice, nothing missing
        self.assertEqual([(w["reason"], w["skipped"]) for w in ws], [("item", 0), ("item", 0)])
        self.chained(ws)
        self.assertEqual(self.wakes(s, "p"), ws)                          # the bus: each once, as the agent got it
        s.run(5)
        self.assertEqual(len(self.got(s, "p")), 2)
        run = self.state(s, "p")
        self.assertEqual((run["wakes"], run["sent"], run["buffer"]), (2, ws[1]["next"], {}))
        self.assertFalse("retry" in run or "reason" in run)
        self.assertEqual(self.agent(s, "kit.app.status", "{ app = 'p' }")["wakes"], 2)

    def test_a_gathered_wake_that_does_not_go(self):
        s = self.start()
        self.opens(s, "{ app = 'd', hear = { 'dg:a' }, lease = 0, urgent = { 'now' }, "
                       "digest = { gather = 0, every = 5, most = 10 } }")
        self.take(s, False)
        self.push(s, "a", "b")
        s.run(7)                                                          # its batch did not go
        s.lua.execute(b"__push('a', { text = 'c', why = 'now' })")        # an urgent one meanwhile: with it
        s.run(2)
        self.assertEqual(self.got(s, "d"), [])
        self.assertEqual(self.state(s, "d").get("wakes", 0), 0)
        self.take(s, True)
        s.run(1.5)
        ws = self.got(s, "d")
        self.assertEqual([(w["reason"], [i["text"] for i in w["items"]], w["after"]) for w in ws],
                         [("urgent", ["a", "b", "c"], 0)])
        self.chained(ws)
        s.run(12)
        self.assertEqual(len(self.got(s, "d")), 1)

    def test_many_at_once_wait_for_room(self):
        s = self.start()
        self.opens(s, "{ app = 'p', hear = { 'dg:a' }, lease = 0 }")
        texts = [f"t{i}" for i in range(1, 31)]
        self.push(s, *texts)                                              # more than the bridge takes at once
        first = self.got(s, "p")
        self.assertTrue(0 < len(first) < 30)
        self.assertTrue(all(len(w["items"]) == 1 for w in first))
        s.run(3)
        ws = self.got(s, "p")
        self.assertEqual([t for w in self.texts(ws) for t in w], texts)   # each once, in order
        self.assertEqual(len(ws), len(first) + 1)                         # the rest: one wake
        self.assertEqual({(w["reason"], w["skipped"]) for w in ws}, {("item", 0)})
        self.chained(ws)
        self.assertEqual(self.wakes(s, "p"), ws)
        s.run(6)
        self.assertEqual(self.events(s, "kit.dropped"), [])               # a wake is not dropped: it waited

    def test_a_wake_waiting_through_a_reload(self):
        s = self.start()
        self.opens(s, "{ app = 'p', hear = { 'dg:a' }, lease = 0 }")
        self.push(s, "one")
        one = self.got(s, "p")[0]["next"]
        self.take(s, False)
        self.push(s, "two", "three")
        s2 = self.start(s.reload())                                       # (the bridge takes them again)
        s2.run(2)
        ws = self.got(s2, "p")
        self.assertEqual([(w["seq"], w["reason"], w["after"], [i["text"] for i in w["items"]]) for w in ws],
                         [(2, "item", one, ["two", "three"])])
        s2.run(5)
        self.assertEqual(len(self.got(s2, "p")), 1)

    def test_heard_while_its_own_wake_is_told(self):
        s = self.start()
        s.lua.execute(b"""
		__a = WuxianKit:App('echo', { title = 'Echo' })
		WuxianKit:On('app.echo', function(_, w)
			if w.items[1].data == 'first' then __a:Push('again') end
		end)""")
        self.call(s, "kit.app.open", "{ app = 'echo' }")
        s.lua.execute(b"__a:Push('first')")
        self.assertEqual([[i["data"] for i in w["items"]] for w in self.got(s, "echo")], [["first"]])
        s.run(1.5)
        ws = self.got(s, "echo")
        self.assertEqual([[i["data"] for i in w["items"]] for w in ws], [["first"], ["again"]])
        self.chained(ws)
        s.run(3)
        self.assertEqual(len(self.got(s, "echo")), 2)


class Cursor(DeliveryCase):
    def test_seq_after_and_next(self):
        s = self.start()
        opened = "{ app = 'c', hear = { 'dg:a' }, lease = 0, digest = { every = 5, idle = 20, most = 10 } }"
        self.opens(s, opened)
        self.push(s, "a", "b")
        s.run(6)
        self.push(s, "c")
        s.run(6)
        s.run(21)                                                         # a lull: nothing new, the cursor stays
        ws = self.got(s, "c")
        self.assertEqual([(w["reason"], [i["text"] for i in w["items"]]) for w in ws],
                         [("batch", ["a", "b"]), ("batch", ["c"]), ("idle", [])])
        self.assertEqual((ws[0]["after"], ws[2]["after"], ws[2]["next"]), (0, ws[1]["next"], ws[1]["next"]))
        self.chained(ws)
        self.assertEqual(self.agent(s, "kit.app.status", "{ app = 'c' }")["next"], ws[2]["next"])

        self.push(s, "d")                                                 # gathered, never sent: the run stops
        self.agent(s, "kit.app.stop", "{ app = 'c' }")
        self.agent(s, "kit.app.open", "{ app = 'c' }")       # remembered: just the id
        d = self.agent(s, "kit.app.status", "{ app = 'c' }")["next"]
        self.push(s, "e")
        s.run(6)
        again = self.got(s, "c")[3:]
        self.assertEqual([(w["seq"], w["after"], [i["text"] for i in w["items"]]) for w in again], [(1, d, ["e"])])
        self.chained(again)
        # after is past the listener's cursor: what it missed is in the ring
        missed = self.agent(s, "kit.app.recent", f"{{ app = 'c', since = {ws[2]['next']} }}")
        self.assertEqual(([i["text"] for i in missed["items"]], missed["next"]), (["d", "e"], again[0]["next"]))

    def test_status_says_where_the_wakes_are(self):
        """sent: the next of the run's last wake that went. The ring has an item at once, the wake later, so next runs
        ahead of sent while items are gathered; one who joins a run starts from sent"""
        s = self.start()
        self.opens(s, "{ app = 'c', hear = { 'dg:a' }, lease = 0, digest = { every = 5, most = 10 } }")
        st = self.agent(s, "kit.app.status", "{ app = 'c' }")
        self.assertEqual((st["sent"], st["next"]), (0, 0))                # nothing yet
        self.push(s, "a", "b")
        st = self.agent(s, "kit.app.status", "{ app = 'c' }")             # gathered, not sent
        ring = self.agent(s, "kit.app.recent", "{ app = 'c' }")
        self.assertEqual((st["sent"], st["next"]), (0, ring["next"]))
        self.assertLess(st["sent"], st["next"])
        self.assertEqual(self.got(s, "c"), [])
        s.run(6)
        ws = self.got(s, "c")
        st = self.agent(s, "kit.app.status", "{ app = 'c' }")
        self.assertEqual((st["sent"], st["next"]), (ws[0]["next"], ws[0]["next"]))
        # from sent on, the wakes bring everything: what was gathered when it was read is in the next wake
        self.push(s, "c")
        joined = self.agent(s, "kit.app.status", "{ app = 'c' }")["sent"]
        self.take(s, False)                                               # a wake that does not go: sent stays
        s.run(6)
        st = self.agent(s, "kit.app.status", "{ app = 'c' }")
        self.assertEqual((st["sent"], st["sent"] < st["next"]), (joined, True))
        self.take(s, True)
        s.run(2)
        ws = self.got(s, "c")
        self.assertEqual((ws[1]["after"], self.texts(ws[1:])), (joined, [["c"]]))
        self.assertEqual(self.agent(s, "kit.app.status", "{ app = 'c' }")["sent"], ws[1]["next"])

        self.push(s, "d")                                                 # gathered, never sent: the run stops
        self.assertNotIn("sent", self.agent(s, "kit.app.stop", "{ app = 'c' }"))
        st = self.agent(s, "kit.app.status", "{ app = 'c' }")
        self.assertNotIn("sent", st)                                      # not running: no wakes, no cursor of them
        opened = self.agent(s, "kit.app.open", "{ app = 'c' }")           # a new run begins where the ring is
        self.assertEqual((opened["sent"], opened["next"]), (st["next"], st["next"]))
        self.assertEqual(self.state(s, "c")["sent"], st["next"])
        self.push(s, "e")
        s.run(6)
        self.assertEqual(self.got(s, "c")[2]["after"], opened["sent"])

    def test_the_buffer_is_capped(self):
        s = self.start()
        self.opens(s, "{ app = 'b', hear = { 'dg:a' }, lease = 0, digest = { every = false, most = 3 } }")
        self.take(s, False)
        texts = [f"t{i}" for i in range(1, 16)]
        self.push(s, *texts)
        s.run(2.5)
        run = self.state(s, "b")
        self.assertEqual((len(run["buffer"]), run["skipped"], run["reason"], run.get("wakes", 0), run["sent"]),
                         (12, 3, "full", 0, 0))                           # four times `most` wait, the oldest went
        self.take(s, True)
        s.run(1.5)
        ws = self.got(s, "b")
        self.assertEqual([(w["reason"], w["skipped"], w["after"], [i["text"] for i in w["items"]]) for w in ws],
                         [("full", 3, 0, texts[3:])])
        self.chained(ws)
        covered = self.agent(s, "kit.app.recent", "{ app = 'b', since = 0, limit = 100 }")["items"]
        self.assertEqual([i["text"] for i in covered], texts)             # the skipped ones: in the ring
        self.assertEqual(len([i for i in covered if ws[0]["after"] < i["id"] <= ws[0]["next"]]),
                         len(ws[0]["items"]) + ws[0]["skipped"])
        self.assertNotIn("skipped", self.state(s, "b"))
        self.push(s, "u", "v", "w")
        ws = self.got(s, "b")
        self.assertEqual([(w["reason"], w["skipped"], len(w["items"])) for w in ws][1:], [("full", 0, 3)])
        self.chained(ws)

    def test_what_does_not_fit_goes_with_the_next(self):
        s = self.start()
        self.opens(s, "{ app = 'big', hear = { 'dg:a' }, lease = 0, "
                       "digest = { every = 3, most = 100 } }")
        for i in range(40):
            s.lua.execute(f"__push('a', {{ text = ('x'):rep(450), n = {i} }})".encode())
        s.run(10)
        ws = self.got(s, "big")
        self.assertGreater(len(ws), 1)
        self.assertEqual([i["n"] for w in ws for i in w["items"]], list(range(40)))
        self.assertEqual({(w["reason"], w["skipped"]) for w in ws}, {("batch", 0)})
        self.chained(ws)
        for w in s.lua.eval(b"__got").values():                           # WoWBridge cuts an event of more than 8000
            self.assertLessEqual(s.ns.WireSize(w), 7200)


class Quiet(DeliveryCase):
    def say(self, s, plain, why=None):
        w = f", why = {why!r}" if why else ""
        s.lua.execute(f"__say('guild', {{ plain = {plain!r}{w} }})".encode())

    def test_quiet_hours_send_no_full_wake(self):
        s = self.start(Session(self, saved={"WoWBridge": bridge("0.9.7", emit=TAKE)}, t0=at(2, 0)))
        self.opens(s, CHAT)
        s.ns.SetAppOption(b"g", b"quiet", b"23:00-07:00")
        self.assertTrue(self.state(s, "g")["quiet"])
        for i in range(1, 41):                                            # more than a wake's 30
            self.say(s, f"m{i}")
        s.run(70)
        self.assertEqual(self.got(s, "g"), [])
        run = self.state(s, "g")
        self.assertEqual((len(run["buffer"]), run["skipped"]), (30, 10))  # the newest 30 wait
        self.say(s, "you there?", "mention")                              # a mention still wakes
        s.run(7)
        ws = self.got(s, "g")
        self.assertEqual([(w["reason"], w["quiet"], w["skipped"]) for w in ws], [("urgent", True, 11)])
        self.assertEqual([i["plain"] for i in ws[0]["items"]], [f"m{i}" for i in range(12, 41)] + ["you there?"])
        self.chained(ws)
        self.assertEqual(len(self.agent(s, "kit.app.recent", "{ app = 'g', limit = 100 }")["items"]), 41)

    def test_the_quiet_pace_still_does(self):
        s = self.start()
        self.opens(s, CHAT)
        s.ns.SetAppOption(b"g", b"activity", b"quiet")                    # a pace, not the hours
        for i in range(1, 31):
            self.say(s, f"m{i}")
        s.run(3)
        ws = self.got(s, "g")
        self.assertEqual([(w["reason"], w["quiet"]) for w in ws], [("full", False)] * len(ws))
        self.assertEqual([i["plain"] for w in ws for i in w["items"]], [f"m{i}" for i in range(1, 31)])


class Items(DeliveryCase):
    def test_an_item_is_the_cores_copy(self):
        s = self.start()
        self.opens(s, "{ app = 'p', hear = { 'dg:a' }, lease = 0 }")
        self.opens(s, "{ app = 'q', hear = { 'dg:a' }, lease = 0, digest = { every = 30 } }")
        a = self.lua(s, "WuxianKit:NewId()")
        s.lua.execute(b"__t = { text = 'x', deep = { n = 1 }, id = 77 } __push('a', __t) "
                      b"__t.text = 'changed' __t.deep.n = 2 __t.more = true")
        self.assertEqual(self.lua(s, "__t"), {"text": "changed", "deep": {"n": 2}, "id": 77, "more": True})   # untouched
        now = self.lua(s, "time()")
        kept = {"text": "x", "deep": {"n": 1}, "ref": 77, "source": "dg", "time": now}
        self.assertEqual(sorted((self.ring(s, "p") + self.ring(s, "q")), key=lambda i: i["id"]),
                         [dict(kept, id=a + 1), dict(kept, id=a + 2)])    # each app its own, numbered by the core
        self.assertEqual(self.lua(s, "WuxianKit:NewId()"), a + 3)
        ring = "WuxianKitDB.apps.%s.chars[UnitGUID('player')].recent.items[1]"
        self.assertIs(self.lua(s, f"{ring % 'p'} == __got[1].items[1]"), True)   # one copy: the ring's is the wake's
        self.assertIs(self.lua(s, f"{ring % 'q'} == WuxianKitDB.apps.q.chars[UnitGUID('player')].run.buffer[1]"), True)
        self.assertIs(self.lua(s, f"{ring % 'p'} ~= __t and {ring % 'p'}.deep ~= __t.deep"), True)

    def test_data_only(self):
        s = self.start()
        self.opens(s, "{ app = 'p', hear = { 'dg:a' }, lease = 0 }")
        s.lua.execute(b"__push('a', { who = 'me', text = '<secret>words', f = print, n = 0 / 0, "
                      b"in_it = { name = '<secret>name', level = 60 }, [true] = 1 })")
        [item] = self.ring(s, "p")
        self.assertEqual({k: v for k, v in item.items() if k not in ("id", "time")},
                         {"who": "me", "in_it": {"level": 60}, "source": "dg"})   # what is secret is left out, unread

    def test_an_item_within_its_size(self):
        s = self.start()
        self.opens(s, "{ app = 'p', hear = { 'dg:a' }, lease = 0 }")
        s.lua.execute(b"local t = { kind = 'wide' } for i = 1, 8 do t['f' .. i] = ('x'):rep(480) end __push('a', t)")
        s.lua.execute(b"local t = { kind = 'deep', list = {} } "
                      b"for i = 1, 40 do t.list[i] = { text = ('y'):rep(100) } end __push('a', t)")
        s.run(2)
        wide, deep = self.ring(s, "p")
        self.assertIs(wide["cut"], True)                                  # its texts shorter
        self.assertTrue(all(len(wide[f"f{i}"].encode()) <= 123 for i in range(1, 9)))
        self.assertEqual({k: v for k, v in deep.items() if k not in ("id", "time")},
                         {"kind": "deep", "source": "dg", "cut": True})  # then without its tables
        self.assertEqual([i["kind"] for w in self.got(s, "p") for i in w["items"]], ["wide", "deep"])
        for i in s.lua.eval(b"WuxianKitDB.apps.p.chars[UnitGUID('player')].recent.items").values():
            self.assertLessEqual(s.ns.WireSize(i, 4), 1700)

    def test_a_wake_within_the_line_whatever_the_state(self):
        s = self.start()
        s.lua.execute(b"""
		local px = WuxianKit:Extension('fat', { title = 'Fat' })
		for i = 1, 8 do
			px:Facet('fat' .. i, { read = function() return { text = ('"'):rep(180 + i) } end })   -- (six bytes each, written)
		end""")
        s.run(0.1)
        see = ", ".join(f"'fat{i}'" for i in range(1, 9))
        self.opens(s, f"{{ app = 'v', hear = {{ 'dg:a' }}, see = {{ {see} }}, lease = 0, "
                       f"digest = {{ every = 3, most = 100 }} }}")
        for i in range(10):
            s.lua.execute(f"__push('a', {{ text = ('x'):rep(450), n = {i} }})".encode())
        s.run(12)
        ws = self.got(s, "v")
        self.assertEqual([i["n"] for w in ws for i in w["items"]], list(range(10)))
        for w in ws:
            cut = [name for name, f in w["state"].items() if f == {"cut": True}]
            self.assertTrue(0 < len(cut) < 8, cut)                        # the largest go, the rest whole
            self.assertIn("fat8", cut)
        for w in s.lua.eval(b"__got").values():
            self.assertLessEqual(s.ns.WireSize(w), 7200)
        state = self.agent(s, "kit.app.state", "{ app = 'v' }")["state"]  # read whole there
        self.assertEqual(len(state["fat8"]["text"]), 188)


class Rings(DeliveryCase):
    def test_another_character_reading_leaves_this_ones_ring(self):
        s = self.start()
        self.opens(s, "{ app = 'p', title = 'P', hear = { 'dg:a' }, lease = 0 }")
        self.push(s, "one", "two", "three")
        mine = self.ring(s, "p")
        last = mine[-1]["id"]

        s2 = self.start(s.reload(), guid=OTHER)                           # another character only looks
        st = self.agent(s2, "kit.app.status", "{ app = 'p' }")
        self.assertEqual((st["on"], st["next"]), (False, 0))
        self.assertEqual(self.agent(s2, "kit.app.recent", "{ app = 'p' }"), {"items": {}, "next": 0})
        self.agent(s2, "kit.apps")
        self.assertEqual(self.ring(s2, "p", ME), mine)
        self.assertIs(self.lua(s2, f"(WuxianKitDB.apps.p.chars['{OTHER}'] or {{}}).recent == nil"), True)   # no ring made
        self.agent(s2, "kit.app.open", "{ app = 'p' }")                   # and then runs it: a ring of its own
        self.push(s2, "theirs")
        self.assertEqual([i["text"] for i in self.ring(s2, "p")], ["theirs"])
        self.assertEqual(self.ring(s2, "p", ME), mine)

        s3 = self.start(s2.reload(), guid=ME)                             # back: all there, the run goes on
        self.assertEqual(self.agent(s3, "kit.app.recent", "{ app = 'p' }"), {"items": mine, "next": last})
        self.push(s3, "four")
        w = self.got(s3, "p")[-1]
        self.assertEqual((w["seq"], w["after"], [i["text"] for i in w["items"]]), (4, last, ["four"]))
        self.assertEqual([i["text"] for i in self.ring(s3, "p", OTHER)], ["theirs"])


if __name__ == "__main__":
    unittest.main()
