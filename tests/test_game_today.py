"""游戏动态 · Today.lua (the facet today) and the kill's streak (Combat.lua): what this character did today, counted only
while watched (the facet's on: the topics combat, growth, quest and travel run), kept per character across reloads, back
to 0 on a new local date. ext:Facet is the core's (K4); here the counting and read are driven through ns.game.today, and
the facet's spec through a stand-in Facet."""
import unittest

from kitmock import py
from test_game import Game, GameTest
from test_game_combat import UNITS

DAY = r"""
__day = __day or "2026-11-10"
date = function(fmt, ...) if fmt == "%Y-%m-%d" then return __day end return os.date(fmt, ...) end
__zone = "Zephyr Isle"
function GetZoneText() return __zone end
"""

ZEROS = {"levels": 0, "quests": 0, "kills": 0, "deaths": 0, "xp": 0, "zones": 0}


class Today(GameTest):
    def start(self, session=None):
        g = Game(self, session=session) if session else self.game()
        if session:
            self.games.append(g)
        g.lua.execute(UNITS.encode())
        g.lua.execute(DAY.encode())
        return g

    def today(self, g):
        return g.s.ns[b"game"][b"today"]

    def on(self, g):
        self.today(g)[b"On"]()

    def off(self, g):
        self.today(g)[b"Off"]()

    def read(self, g):
        return py(self.today(g)[b"Read"]())

    def kill(self, g, guid, unit):
        g.lua.execute(f'__set("{guid}", "dead", true)'.encode())
        g.fire("UNIT_HEALTH", unit)

    def mobs(self, g, n, first=1):
        """n mobs on nameplates first.., each with a little threat (in the fight, not hitting you)"""
        for i in range(first, first + n):
            g.lua.execute(f'__mob("nameplate{i}", {{ guid = "Creature-{i}", name = "Raptor", hostile = true, '
                          f'threat = 1 }})'.encode())

    # ---------------------------------------------------------------------------------------------------------------

    def test_nothing_counted_and_nothing_running_while_not_watched(self):
        g = self.start()
        g.listen(topics=["quest"])
        g.fire("QUEST_TURNED_IN", 3001, 100, 0)
        self.assertEqual(self.read(g), {"date": "2026-11-10", **ZEROS})
        self.assertEqual(g.active(), ["quest"])
        self.assertIsNone(g.s.ns[b"game"][b"tally"])

    def test_watched_runs_the_topics_and_off_lets_them_go(self):
        g = self.start()
        g.listen(topics=["combat"])
        self.on(g)
        self.on(g)                                                               # twice: once
        self.assertEqual(g.active(), ["combat", "growth", "quest", "travel"])
        self.assertTrue(self.today(g)[b"watching"])
        self.off(g)
        self.assertEqual(g.active(), ["combat"])                                 # the app still hears combat
        self.assertFalse(self.today(g)[b"watching"])
        g.fire("QUEST_TURNED_IN", 3001, 0, 0)
        self.assertEqual(self.read(g)["quests"], 0)

    def test_the_counts(self):
        g = self.start()
        self.on(g)
        g.fire("QUEST_TURNED_IN", 3001, 100, 0)
        g.fire("QUEST_TURNED_IN", 3002, 100, 0)
        g.lua.execute(b"__player.xp = 300")                                     # 190 -> 300
        g.fire("PLAYER_XP_UPDATE", "player")
        g.run(0.5)
        g.lua.execute(b"__player.xp = 5300")                                    # 300 -> 5300
        g.fire("PLAYER_XP_UPDATE", "player")
        g.run(0.5)
        g.fire("PLAYER_LEVEL_UP", 9)                                            # 5300/5400 at 8 -> 2000 at 9
        g.lua.execute(b"__player.level = 9 __player.xp = 2000 __player.xpMax = 6000")
        g.fire("PLAYER_XP_UPDATE", "player")
        g.run(1)
        g.fire("PLAYER_DEAD")
        g.fire("PLAYER_DEAD")                                                   # still dead: once
        g.run(10)
        g.fire("PLAYER_UNGHOST")
        g.lua.execute(b'__zone = "Elwynn Forest"')                              # a zone never been to
        g.fire("ZONE_CHANGED_NEW_AREA")
        g.lua.execute(b'__zone = "Zephyr Isle"')                                # been there (at login)
        g.fire("ZONE_CHANGED_NEW_AREA")
        g.lua.execute(b'__zone = "Elwynn Forest"')                              # not the first time any more
        g.fire("ZONE_CHANGED_NEW_AREA")
        self.mobs(g, 2)
        g.lua.execute(b"__combat(true)")
        g.run(0.6)
        self.kill(g, "Creature-1", "nameplate1")
        self.kill(g, "Creature-2", "nameplate2")
        g.lua.execute(b"__combat(false)")
        self.assertEqual(self.read(g), {"date": "2026-11-10", "levels": 1, "quests": 2, "kills": 2, "deaths": 1,
                                        "xp": 110 + 5000 + 100 + 2000, "zones": 1})

    def test_kept_across_a_reload_and_a_new_day_starts_at_zero(self):
        g = self.start()
        self.on(g)
        g.fire("QUEST_TURNED_IN", 3001, 0, 0)
        self.assertEqual(self.read(g)["quests"], 1)
        self.assertEqual(py(g.lua.eval(b"WuxianKit:Extension('game'):Char().today"))["quests"], 1)   # where it is kept
        g2 = self.start(session=g.s.reload())
        self.assertEqual(self.read(g2)["quests"], 1)                             # watched or not, read gives today's
        self.assertFalse(self.today(g2)[b"watching"])
        self.on(g2)
        g2.fire("QUEST_TURNED_IN", 3002, 0, 0)
        self.assertEqual(self.read(g2)["quests"], 2)
        g2.lua.execute(b'__day = "2026-11-11"')
        self.assertEqual(self.read(g2), {"date": "2026-11-11", **ZEROS})
        g2.fire("QUEST_TURNED_IN", 3003, 0, 0)
        self.assertEqual(self.read(g2)["quests"], 1)

    def test_the_extension_off_counts_nothing(self):
        g = self.start()
        self.on(g)
        g.s.ns[b"Switch"](b"game", False)
        self.assertEqual(g.active(), [])
        g.s.ns[b"game"][b"Tally"](b"quests")                                    # the detectors' way: not while off
        self.assertEqual(self.read(g)["quests"], 0)
        g.s.ns[b"Switch"](b"game", True)
        self.assertEqual(g.active(), ["combat", "growth", "quest", "travel"])
        g.fire("QUEST_TURNED_IN", 3002, 0, 0)
        self.assertEqual(self.read(g)["quests"], 1)

    def test_the_facet_spec(self):
        g = self.start()
        g.lua.execute(b"__facets = {} WuxianKit:Extension('game').Facet = function(self, name, spec) "
                      b"__facets[name] = spec return spec end")
        self.today(g)[b"Register"]()
        spec = g.lua.eval(b"__facets.today")
        self.assertEqual(py(spec[b"fields"]), {"date": "string", "levels": "number", "quests": "number",
                                               "kills": "number", "deaths": "number", "xp": "number",
                                               "zones": "number"})
        self.assertEqual(g.s.ns[b"T"](spec[b"title"]).decode(), "Today")    # a word, by the locale
        self.assertIn(b"zones been to for the first time ever", spec[b"doc"])
        spec[b"on"](spec)
        self.assertEqual(g.active(), ["combat", "growth", "quest", "travel"])
        g.fire("QUEST_TURNED_IN", 3001, 0, 0)
        self.assertEqual(py(spec[b"read"](spec)), {"date": "2026-11-10", **ZEROS, "quests": 1})
        spec[b"off"](spec)
        self.assertEqual(g.active(), [])


class Streak(GameTest):
    def test_kills_within_30_seconds_across_fights(self):
        g = self.game()
        g.lua.execute(UNITS.encode())
        g.listen(topics=["combat"])
        t = Today.mobs
        t(self, g, 3)
        g.lua.execute(b"__combat(true)")
        g.run(0.6)
        Today.kill(self, g, "Creature-1", "nameplate1")
        g.run(0.3)
        Today.kill(self, g, "Creature-2", "nameplate2")                         # within a second: told with the first
        self.assertEqual(g.moments("kill"), [])                                  # (when the second is over)
        g.run(5)
        Today.kill(self, g, "Creature-3", "nameplate3")
        g.lua.execute(b"__combat(false)")
        g.run(25)
        t(self, g, 1, first=4)                                                   # the next pull, 31 s after the first
        g.lua.execute(b"__combat(true)")
        g.run(0.6)
        Today.kill(self, g, "Creature-4", "nameplate4")
        g.lua.execute(b"__combat(false)")
        g.run(30)
        t(self, g, 1, first=5)
        g.lua.execute(b"__combat(true)")
        g.run(0.6)
        Today.kill(self, g, "Creature-5", "nameplate5")                          # 30 s and more after the others
        g.lua.execute(b"__combat(false)")
        kills = g.moments("kill")
        self.assertEqual([k["data"]["count"] for k in kills], [2, 1, 1, 1])
        self.assertEqual([k["data"]["streak"] for k in kills], [2, 3, 2, 1])     # the 4th: only the 3rd within 30 s
        self.assertEqual(kills[0]["data"]["unit"]["name"], "Raptor")

    def test_the_kills_of_a_second_are_one_moment(self):
        g = self.game()
        g.lua.execute(UNITS.encode())
        g.listen(topics=["combat"])
        Today.mobs(self, g, 6)
        g.lua.execute(b'__set("Creature-1", "name", "Boar") __combat(true)')
        g.run(0.6)
        for i in (1, 2, 3):                                                      # an area spell: three at once
            Today.kill(self, g, f"Creature-{i}", f"nameplate{i}")
        g.run(0.5)
        Today.kill(self, g, f"Creature-4", "nameplate4")
        self.assertEqual(g.moments("kill"), [])
        g.run(0.6)                                                               # the window is over: one moment
        [k] = g.moments("kill")
        self.assertEqual((k["data"]["unit"]["name"], k["data"]["count"], k["data"]["streak"]), ("Boar", 4, 4))
        Today.kill(self, g, "Creature-5", "nameplate5")                          # the next window
        g.run(0.5)
        Today.kill(self, g, "Creature-6", "nameplate6")
        g.lua.execute(b"__combat(false)")                                        # the fight ends within it: told first
        self.assertEqual([(m["kind"], m["data"].get("count"), m["data"].get("streak")) for m in g.moments()][-2:],
                         [("kill", 2, 6), ("combat.end", None, None)])
        self.assertEqual(g.moments("combat.end")[0]["data"]["kills"], 6)
        g.run(2)
        self.assertEqual(len(g.moments("kill")), 2)                              # none told twice


if __name__ == "__main__":
    unittest.main()
