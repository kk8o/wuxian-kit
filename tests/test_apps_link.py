"""Apps, 0.6.1 (ARCHITECTURE section 10 and section 16): the declaration's link (live, standby or none; only live is
kept) in the status, the rows of kit.apps, describe and the kit.app event (with pace, the activity now, beside it); and
the player's less and more, which the core carries out for an app with pace (the activity a step, kit.option, then the
control item {cmd, activity, was, edge?}) and only tells an app without."""
import unittest

from kitmock import lupa, py
from test_app_reconcile import Case

PACED = ("{ app = 'g', title = 'Guild', hear = { 'bus:demo.*' }, pace = true, controls = { 'less', 'more', 'stop' }, "
         "lease = 0 }")


def control(wake):
    """the last control item of a wake, without what every item has (id, time, source)"""
    item = [i for i in wake["items"] if i["source"] == "control"][-1]
    return {k: v for k, v in item.items() if k not in ("id", "time", "source")}


@unittest.skipIf(lupa is None, "lupa (Lua 5.1 for Python) is not installed")
class Link(Case):
    def test_live_standby_or_none(self):
        s = self.start()
        st = self.agent(s, "kit.app.declare", "{ app = 'voice', title = 'Voice', link = 'live' }")
        self.assertEqual(st["link"], "live")
        self.assertEqual(self.row(s, "voice")["link"], "live")
        self.assertEqual(self.agent(s, "kit.app.describe", "{ app = 'voice' }")["decl"]["link"], "live")
        again = self.agent(s, "kit.app.declare", "{ app = 'voice', title = 'Voice', link = 'live' }")
        self.assertFalse(again["changed"])
        for decl in ("{ app = 'chat', title = 'Chat' }", "{ app = 'chat', title = 'Chat', link = 'standby' }"):
            st = self.agent(s, "kit.app.declare", decl)
            self.assertNotIn("link", st, decl)                            # standby is no mark at all
            self.assertNotIn("link", self.row(s, "chat"), decl)
            self.assertNotIn("link", self.agent(s, "kit.app.describe", "{ app = 'chat' }")["decl"], decl)
        self.assertFalse(st["changed"])                                   # standby given is none given
        st = self.agent(s, "kit.app.declare", "{ app = 'voice', title = 'Voice' }")   # the whole declaration: gone
        self.assertTrue(st["changed"])
        self.assertNotIn("link", st)
        m = self.lua(s, "WuxianKit:Manifest()")["apps"]
        self.assertNotIn("link", next(a for a in m if a["id"] == "voice"))

    def test_refused(self):
        s = self.start()
        for value in ("'always'", "'LIVE'", "''"):
            err = self.fails(s, "kit.app.declare", f"{{ app = 'x', link = {value} }}")
            self.assertIn("link is live or standby", err, value)
        for value in ("true", "1", "{}"):
            self.assertIn("link", self.fails(s, "kit.app.declare", f"{{ app = 'x', link = {value} }}"), value)
        self.assertIn("link is live or standby",
                      self.fails(s, "kit.app.open", "{ app = 'tmp', temp = { link = 'open' } }"))
        self.assertEqual([a["id"] for a in py(s.ns.AppList())], [])
        ok, err = s.lua.eval(b"pcall(WuxianKit.App, WuxianKit, 'bad', { title = 'Bad', link = 'yes' })")
        self.assertFalse(ok)
        self.assertIn("link is live or standby", err.decode())

    def test_an_addons_and_a_temporary_app(self):
        s = self.start()
        s.lua.execute(b"WuxianKit:App('mine', { title = 'Mine', link = 'live', pace = true })")
        self.assertEqual(self.agent(s, "kit.app.status", "{ app = 'mine' }")["link"], "live")
        self.assertEqual(self.lua(s, "WuxianKit:Manifest()")["apps"][0]["link"], "live")   # the lists carry it
        st = self.agent(s, "kit.app.open",
                        "{ app = 'peek', lease = 0, temp = { hear = { 'bus:demo.*' }, link = 'live' } }")
        self.assertEqual(st["link"], "live")
        self.assertEqual(self.app_events(s, "peek")[-1]["link"], "live")

    def test_the_event(self):
        """kit.app on = true has link (live) and pace (the activity now) beside it; a stop has neither"""
        s = self.start()
        now = s.lua.eval(b"time()")
        self.opens(s, "{ app = 'plain', hear = { 'bus:demo.*' }, lease = 0 }")
        self.assertEqual(self.app_events(s, "plain"), [{"app": "plain", "on": True, "ends": now + 7200}])
        self.opens(s, "{ app = 'voice', hear = { 'bus:demo.*' }, link = 'live', lease = 0 }")
        self.assertEqual(self.app_events(s, "voice"),
                         [{"app": "voice", "on": True, "ends": now + 7200, "link": "live"}])
        self.agent(s, "kit.app.declare",
                   "{ app = 'both', hear = { 'bus:demo.*' }, link = 'live', pace = true, lease = 0 }")
        s.ns.SetAppOption(b"both", b"activity", b"lively")
        self.agent(s, "kit.app.open", "{ app = 'both' }")
        self.assertEqual(self.app_events(s, "both"), [{"app": "both", "on": True, "ends": now + 7200, "link": "live",
                                                       "pace": "lively"}])
        self.agent(s, "kit.app.open", "{ app = 'both', minutes = 5 }")    # goes on: told again, as it is now
        self.assertEqual(self.app_events(s, "both")[-1], {"app": "both", "on": True, "ends": now + 300, "link": "live",
                                                          "pace": "lively"})
        self.agent(s, "kit.app.stop", "{ app = 'both' }")
        self.assertEqual(self.app_events(s, "both")[-1], {"app": "both", "on": False, "why": "stopped"})

    def test_the_event_while_it_waits(self):
        """a run kept through a reload that waits for its source: both kit.app events (waiting, then heard) carry
        them"""
        s = self.radio(self.start())
        st = self.opens(s, "{ app = 'mix', hear = { 'radio:jazz' }, link = 'live', pace = true, lease = 0 }")
        s.ns.SetAppOption(b"mix", b"activity", b"quiet")
        s = self.start(s.reload())
        base = {"app": "mix", "on": True, "ends": st["ends"], "link": "live", "pace": "quiet"}
        self.assertEqual(self.app_events(s, "mix"), [dict(base, waiting="Needs the source radio")])
        self.assertEqual(self.row(s, "mix")["link"], "live")
        self.radio(s)
        self.assertEqual(self.app_events(s, "mix")[-1], base)

    def test_pace_in_the_rows(self):
        s = self.start()
        self.agent(s, "kit.app.declare", PACED)
        self.agent(s, "kit.app.declare", "{ app = 'flat', hear = { 'bus:demo.*' } }")
        self.assertEqual(self.row(s, "g")["pace"], "normal")             # off: the player's option
        self.assertNotIn("pace", self.row(s, "flat"))
        s.ns.SetAppOption(b"g", b"activity", b"lively")
        self.assertEqual(self.row(s, "g")["pace"], "lively")
        self.agent(s, "kit.app.open", "{ app = 'g' }")
        self.assertEqual((self.row(s, "g")["pace"], self.status(s, "g")["pace"]), ("lively", "lively"))
        s.ns.SetAppOption(b"g", b"activity", b"quiet")
        self.assertEqual((self.row(s, "g")["pace"], self.status(s, "g")["pace"]), ("quiet", "quiet"))

    def test_the_docs_tell_it(self):
        """what the agent reads: kit.app.declare's fields, the rows, the status and the event"""
        s = self.start()
        m = self.lua(s, "WuxianKit:Manifest()")
        kit = next(e for e in m["extensions"] if e["id"] == "kit")
        caps = {c["id"]: c for c in kit["capabilities"]}
        declare = caps["kit.app.declare"]
        self.assertIn("link (live:", declare["doc"])
        self.assertEqual(declare["args"]["link"], "string?")
        self.assertIn("link?", caps["kit.apps"]["doc"])
        self.assertIn("pace?", caps["kit.apps"]["doc"])
        self.assertIn("link?", caps["kit.app.status"]["doc"])
        self.assertIn("less and more", declare["doc"])
        self.assertIn("edge?", declare["doc"])
        event = next(e for e in kit["events"] if e["topic"] == "kit.app")
        self.assertIn("link (on", event["doc"])
        self.assertIn("pace (on", event["doc"])


@unittest.skipIf(lupa is None, "lupa (Lua 5.1 for Python) is not installed")
class LessMore(Case):
    def control(self, s, app, word):
        self.assertIs(s.lua.eval(f"WuxianKit:AppControl({app!r}, {word!r})".encode()), True, word)
        return self.wakes(s, app)[-1]

    def options(self, s):
        return [e for e in self.events(s, "kit.option") if e.get("app") == "g"]

    def digest(self, s):
        return self.lua(s, "WuxianKitDB.apps.g.chars[UnitGUID('player')].run.options.digest")

    def test_a_step_at_a_time_and_the_ends(self):
        s = self.start()
        self.opens(s, PACED)
        w = self.control(s, "g", "less")
        self.assertEqual(control(w), {"cmd": "less", "activity": "quiet", "was": "normal"})
        self.assertEqual((w["reason"], w["pace"]), ("urgent", "quiet"))  # the wake goes at the new pace
        self.assertEqual(self.options(s), [{"app": "g", "name": "activity", "value": "quiet"}])
        self.assertEqual(self.digest(s)["every"], False)                  # retuned: quiet's
        self.assertEqual(self.agent(s, "kit.app.status", "{ app = 'g' }")["pace"], "quiet")
        self.assertEqual(py(s.ns.AppOptionList(b"g"))["activity"]["value"], "quiet")   # the player's option
        w = self.control(s, "g", "less")                                  # at the end: it stays
        self.assertEqual(control(w), {"cmd": "less", "activity": "quiet", "was": "quiet", "edge": True})
        self.assertEqual(w["pace"], "quiet")
        self.assertEqual(len(self.options(s)), 1)                         # nothing changed, nothing told
        self.assertEqual(control(self.control(s, "g", "more")), {"cmd": "more", "activity": "normal", "was": "quiet"})
        self.assertEqual(self.digest(s)["every"], 60)
        w = self.control(s, "g", "多说")                                   # the word works as the cmd
        self.assertEqual(control(w), {"cmd": "more", "activity": "lively", "was": "normal"})
        self.assertEqual((w["pace"], self.digest(s)["every"]), ("lively", 20))
        w = self.control(s, "g", "more")
        self.assertEqual(control(w), {"cmd": "more", "activity": "lively", "was": "lively", "edge": True})
        self.assertEqual([e["value"] for e in self.options(s)], ["quiet", "normal", "lively"])
        self.assertEqual(control(self.control(s, "g", "less")), {"cmd": "less", "activity": "normal", "was": "lively"})

    def test_kept_through_a_reload(self):
        s = self.start()
        self.opens(s, PACED)
        self.control(s, "g", "more")
        s2 = self.start(s.reload())
        self.assertEqual(self.agent(s2, "kit.app.status", "{ app = 'g' }")["pace"], "lively")
        self.assertEqual(control(self.control(s2, "g", "more")),
                         {"cmd": "more", "activity": "lively", "was": "lively", "edge": True})

    def test_an_app_without_pace_is_only_told(self):
        s = self.start()
        for decl in ("{ app = 'v', controls = { 'less', 'more' }, hear = { 'bus:demo.*' } }",
                     "{ app = 'd', controls = { 'less', 'more' }, hear = { 'bus:demo.*' }, digest = { every = 30 } }"):
            app = decl.split("'")[1]
            self.opens(s, decl)
            for word in ("less", "more", "less"):
                self.assertEqual(control(self.control(s, app, word)), {"cmd": word}, (app, word))
            self.assertNotIn("pace", self.wakes(s, app)[-1])
        self.assertEqual(self.events(s, "kit.option"), [])

    def test_only_less_and_more(self):
        """the other controls of an app with pace are told as they were, and change nothing"""
        s = self.start()
        self.opens(s, "{ app = 'g', hear = { 'bus:demo.*' }, pace = true, controls = { 'mute', 'test', "
                      "{ cmd = 'louder', label = 'Louder' }, 'stop' }, lease = 0 }")
        for word in ("mute", "test", "louder"):
            self.assertEqual(control(self.control(s, "g", word)), {"cmd": word})
        self.assertIs(s.lua.eval(b"WuxianKit:AppControl('g', 'less')"), False)   # not one of its controls
        self.assertEqual(self.events(s, "kit.option"), [])
        self.assertEqual(self.agent(s, "kit.app.status", "{ app = 'g' }")["pace"], "normal")

    def test_not_while_it_is_off(self):
        s = self.start()
        self.agent(s, "kit.app.declare", PACED)
        self.assertIs(s.lua.eval(b"WuxianKit:AppControl('g', 'less')"), False)
        self.assertEqual(self.events(s, "kit.option"), [])
        self.assertEqual(py(s.ns.AppOptionList(b"g"))["activity"]["value"], "normal")


if __name__ == "__main__":
    unittest.main()
