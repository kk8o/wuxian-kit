"""Apps with pace (ARCHITECTURE section 10): the core's three presets (quiet, normal, lively) and a declaration's own,
the options activity and quiet the core adds, quiet hours (the parser: full-width colon, ～, 至, 到, hours alone, across
midnight; in them only a mention wakes and nothing batches), and the retune on an option change, at the quiet hours'
edges and after a reload."""
import time as clock
import unittest

from kitmock import Session, lupa, py
from test_apps import AppCase
from test_standalone import bridge

CHAT = "{ app = 'g', title = 'Guild', hear = { 'chat:guild' }, pace = true, lease = 0 }"


def at(hour, minute=0):
    """a session's start whose local time is hour:minute"""
    return float(clock.mktime((2026, 11, 9, hour, minute, 0, 0, 0, -1)))


@unittest.skipIf(lupa is None, "lupa (Lua 5.1 for Python) is not installed")
class Pace(AppCase):
    def say(self, s, plain, why=None):
        w = f", why = {why!r}" if why else ""
        s.lua.execute(f"__say('guild', {{ plain = {plain!r}{w} }})".encode())

    def reasons(self, s):
        return [(w["reason"], [i["plain"] for i in w["items"]]) for w in self.wakes(s, "g")]

    def test_normal_then_quiet_then_lively(self):
        s = self.start()
        st = self.opens(s, CHAT)
        self.assertEqual((st["pace"], st["quiet"]), ("normal", False))
        o = py(s.ns.AppOptionList(b"g"))
        self.assertEqual((o["activity"]["value"], o["activity"]["kind"], [c["value"] for c in o["activity"]["choices"]],
                          o["quiet"]["value"], o["quiet"]["title"]), ("normal", "choice", ["quiet", "normal", "lively"],
                                                                      "", "Quiet hours"))
        self.assertEqual(self.lua(s, "WuxianKit:App('g').optionOrder"), ["activity", "quiet"])
        self.say(s, "how do I get there?", "question")                    # normal: a question wakes, 5 s later
        s.run(4)
        self.assertEqual(self.wakes(s, "g"), [])
        s.run(3)
        w = self.wakes(s, "g")[0]
        self.assertEqual((w["reason"], w["pace"], w["quiet"], w["app"]), ("urgent", "normal", False, "g"))
        self.say(s, "chatter")                                            # the rest every 60 s
        s.run(58)
        self.assertEqual(len(self.wakes(s, "g")), 1)
        s.run(3)
        self.assertEqual(self.reasons(s)[-1], ("batch", ["chatter"]))
        s.run(1200)                                                       # nothing for 1200 s: a lull
        self.assertEqual(self.reasons(s)[-1], ("idle", []))

        self.assertEqual(s.ns.SetAppOption(b"g", b"activity", b"quiet"), (True, b"quiet"))
        self.assertEqual(self.events(s, "kit.option")[-1], {"app": "g", "name": "activity", "value": "quiet"})
        st = self.agent(s, "kit.app.status", "{ app = 'g' }")
        self.assertEqual(st["pace"], "quiet")
        n = len(self.wakes(s, "g"))
        self.say(s, "anyone?", "question")                                # quiet: questions wait, nothing batches
        s.run(1300)
        self.assertEqual(len(self.wakes(s, "g")), n)
        self.say(s, "hey you", "mention")                                 # a mention: 6 s
        s.run(5)
        self.assertEqual(len(self.wakes(s, "g")), n)
        s.run(2)
        self.assertEqual(self.reasons(s)[-1], ("urgent", ["anyone?", "hey you"]))
        self.assertEqual(self.wakes(s, "g")[-1]["pace"], "quiet")

        s.ns.SetAppOption(b"g", b"activity", b"lively")
        self.say(s, "so hot", "burst")                                    # lively: a burst, 3 s
        s.run(4.5)
        self.assertEqual(self.reasons(s)[-1], ("urgent", ["so hot"]))
        self.say(s, "more")
        s.run(22)
        self.assertEqual(self.reasons(s)[-1], ("batch", ["more"]))         # every 20 s
        self.assertEqual(s.ns.SetAppOption(b"g", b"activity", b"loud"), (True, b"normal"))   # not a choice: default

    def test_its_own_pace(self):
        s = self.start()
        self.opens(s, "{ app = 'g', hear = { 'chat:guild' }, lease = 0, "
                                      "pace = { normal = { every = 10, wake = { 'question', 'guild.join' } } } }")
        self.say(s, "plain")
        s.run(12)
        self.assertEqual(self.reasons(s), [("batch", ["plain"])])
        self.say(s, "hey", "mention")                                     # not in its normal's wake
        s.run(4)
        self.assertEqual(len(self.wakes(s, "g")), 1)
        s.ns.SetAppOption(b"g", b"activity", b"quiet")                    # the core's quiet, as it gave none
        run = self.lua(s, "WuxianKitDB.apps.g.chars[UnitGUID('player')].run.options.digest")
        self.assertEqual(run, {"gather": 6, "every": False, "idle": False, "most": 30})

    def test_retuned_after_a_reload(self):
        s = self.start()
        self.opens(s, CHAT)
        s.ns.SetAppOption(b"g", b"activity", b"lively")
        s.lua.execute(b"WuxianKitDB.apps.g.chars[UnitGUID('player')].run.options.digest.every = 999")   # as an older version kept it
        s2 = self.start(s.reload())
        self.assertEqual(self.lua(s2, "WuxianKitDB.apps.g.chars[UnitGUID('player')].run.options.digest.every"), 20)
        self.assertEqual(self.agent(s2, "kit.app.status", "{ app = 'g' }")["pace"], "lively")


@unittest.skipIf(lupa is None, "lupa (Lua 5.1 for Python) is not installed")
class Quiet(AppCase):
    def test_the_window(self):
        s = self.start()
        q = lambda text: s.ns.QuietWindow(text.encode())
        self.assertEqual(q("01:00-08:00"), (60, 480))
        self.assertEqual(q("1：00～8：00"), (60, 480))
        self.assertEqual(q("23至7"), (1380, 420))
        self.assertEqual(q(" 22:30 到 06:15 "), (1350, 375))
        self.assertEqual(q("1-8"), (60, 480))
        self.assertEqual(q("0:00—24:00"), None)                           # the same minute: none
        for text in ("8-8", "25-3", "1:75-3", "soon", "", "1-"):
            self.assertIsNone(q(text), text)
        self.assertIsNone(s.ns.QuietWindow(None))

    def wake_reasons(self, s):
        return [(w["reason"], w["quiet"]) for w in self.wakes(s, "g")]

    def test_across_midnight_and_out_at_its_end(self):
        s = self.start(Session(self, saved={"WoWBridge": bridge("0.9.7")}, t0=at(6, 58)))
        self.opens(s, CHAT)
        s.ns.SetAppOption(b"g", b"quiet", b"23:00-07:00")                 # now: in it at once
        self.assertTrue(self.agent(s, "kit.app.status", "{ app = 'g' }")["quiet"])
        self.assertTrue(self.lua(s, "WuxianKitDB.apps.g.chars[UnitGUID('player')].run.quiet"))
        s.lua.execute(b"__say('guild', { plain = 'who?', why = 'question' })")
        s.run(65)
        self.assertEqual(self.wakes(s, "g"), [])                          # no question, no batch
        s.lua.execute(b"__say('guild', { plain = 'yo', why = 'mention' })")
        s.run(7)
        self.assertEqual(self.wakes(s, "g")[0]["reason"], "urgent")
        self.assertIs(self.wakes(s, "g")[0]["quiet"], True)
        s.lua.execute(b"__say('guild', { plain = 'later' })")
        s.run(40)                                                         # 07:00 is near; still quiet
        self.assertEqual(len(self.wakes(s, "g")), 1)
        s.run(25)                                                         # out of it: retuned, the batch goes
        self.assertEqual(self.wake_reasons(s)[-1], ("batch", False))
        self.assertFalse(self.agent(s, "kit.app.status", "{ app = 'g' }")["quiet"])

    def test_into_it_at_its_start(self):
        s = self.start(Session(self, saved={"WoWBridge": bridge("0.9.7")}, t0=at(0, 59)))
        self.opens(s, CHAT)
        s.ns.SetAppOption(b"g", b"quiet", b"1-8")
        self.assertFalse(self.agent(s, "kit.app.status", "{ app = 'g' }")["quiet"])
        s.run(65)                                                         # 01:00
        self.assertTrue(self.agent(s, "kit.app.status", "{ app = 'g' }")["quiet"])
        self.assertIs(self.lua(s, "WuxianKitDB.apps.g.chars[UnitGUID('player')].run.options.digest.every"), False)


if __name__ == "__main__":
    unittest.main()
