"""游戏动态 · Growth.lua, Quest.lua and Travel.lua (topics growth, quest, travel), ported from 无限陪玩's tests: xp,
level, talent, spell.new, quests accepted / objective done / ready / turned in, zone, taxi, rest."""
import unittest

from kitmock import py
from test_game import GameTest


class Progress(GameTest):
    def fight(self, g, on):
        g.lua.execute(f"UnitHealthMax = UnitHealthMax or function() return 100 end __combat({'true' if on else 'false'})".encode())

    def xp(self, g, value):
        g.lua.execute(f"__player.xp = {value}".encode())
        g.fire("PLAYER_XP_UPDATE", "player")
        g.run(0.5)

    def test_xp_crossing_a_mark_or_a_big_gain_and_where_it_came_from(self):
        g = self.game()
        g.listen()
        self.xp(g, 300)                                   # 3.5% -> 5.6%: nothing
        self.xp(g, 1400)                                  # crosses 25%
        self.fight(g, True)
        self.xp(g, 1500)
        self.fight(g, False)
        g.run(1)
        self.xp(g, 2800)                                  # crosses 50%, 1.5 s after the fight
        g.fire("QUEST_TURNED_IN", 3002, 2100, 0)
        self.xp(g, 4900)                                  # crosses 75% and 90%
        g.run(5)
        self.xp(g, 5100)                                  # 3.7%: nothing
        self.assertEqual([m["data"] for m in g.moments("xp")], [
            {"gained": 1100, "pct": 25, "from": "other"},
            {"gained": 1300, "pct": 51, "from": "kill"},
            {"gained": 2100, "pct": 90, "from": "quest"}])

    def test_xp_gain_of_five_percent_counts_and_nobody_listening_keeps_the_baseline(self):
        g = self.game()
        self.xp(g, 1000)                                  # not listening: only the baseline moves
        g.listen()
        self.xp(g, 1100)
        self.xp(g, 1100 + 300)                            # 5.6% in one go
        self.assertEqual([m["data"]["gained"] for m in g.moments("xp")], [300])

    def test_level_up_sends_level_not_xp(self):
        g = self.game()
        g.listen()
        g.lua.execute(b"__player.xp = 5300")
        g.fire("PLAYER_XP_UPDATE", "player")
        g.run(0.5)
        g.fire("PLAYER_LEVEL_UP", 9)
        g.lua.execute(b"__player.level = 9 __player.xp = 2000 __player.xpMax = 6000")
        g.fire("PLAYER_XP_UPDATE", "player")
        g.run(1)
        self.assertEqual([m["data"] for m in g.moments("level")], [{"level": 9}])     # talent points unreadable
        self.assertEqual([m["data"]["pct"] for m in g.moments("xp")], [98])          # 5300/5400, before the level
        self.xp(g, 2100)                                  # the new level is the baseline
        self.assertEqual(len(g.moments("xp")), 1)

    def test_level_up_tells_unspent_talent_points(self):
        g = self.game()
        g.listen()
        g.lua.execute(b"function UnitCharacterPoints() return 1 end")
        g.fire("PLAYER_LEVEL_UP", 10)
        g.run(1)
        self.assertEqual([m["data"] for m in g.moments("level")], [{"level": 10, "talentPoints": 1}])

    def test_talent_learned_with_its_name_after_combat_once_in_30_seconds(self):
        g = self.game()
        g.listen()
        g.lua.execute("""
            __tal = { { "强化火球术", 0 }, { "冰霜之心", 0 } }
            __points = 2
            function UnitCharacterPoints() return __points end
            function GetNumTalentTabs() return 1 end
            function GetNumTalents() return #__tal end
            function GetTalentInfo(tab, i) return __tal[i][1], 0, 1, i, __tal[i][2], 5 end
        """.encode())
        g.fire("PLAYER_ENTERING_WORLD")                   # snapshot with the talent page readable
        g.lua.execute(b"__tal[2][2] = 1 __points = 1")
        self.fight(g, True)
        g.fire("CHARACTER_POINTS_CHANGED", -1)
        g.run(1)
        self.assertEqual(g.moments("talent"), [])          # in combat: waits
        self.fight(g, False)
        self.assertEqual([m["data"] for m in g.moments("talent")], [{"name": "冰霜之心", "points": 1}])
        g.lua.execute(b"__tal[1][2] = 1 __points = 0")
        g.fire("PLAYER_TALENT_UPDATE")
        g.run(1)
        self.assertEqual(len(g.moments("talent")), 1)      # 30 s apart
        g.lua.execute(b"__points = 1")                     # a level: a point more, nothing learned
        g.fire("CHARACTER_POINTS_CHANGED", 1)
        g.run(31)
        self.assertEqual(len(g.moments("talent")), 1)

    def test_new_spell(self):
        g = self.game()
        g.listen()
        g.lua.execute("""
            C_Spell.GetSpellName = function(id) if id == 133 then return "火球术" end end
            function GetSpellInfo(id) if id == 116 then return "寒冰箭" end end
        """.encode())
        g.fire("LEARNED_SPELL_IN_SKILL_LINE", 133, 2, False)
        g.fire("LEARNED_SPELL_IN_TAB", 116, 3, False)
        g.fire("LEARNED_SPELL_IN_TAB", 999, 3, False)     # no name: nothing
        self.assertEqual([m["data"] for m in g.moments("spell.new")],
                         [{"spell": "火球术", "id": 133}, {"spell": "寒冰箭", "id": 116}])

    def test_quest_accept_both_argument_forms(self):
        g = self.game()
        g.listen()
        g.lua.execute("""C_QuestLog.GetTitleForQuestID = function(id)
            if id == 194 then return "猎杀迅猛龙" end end""".encode())
        g.fire("QUEST_ACCEPTED", 194)
        g.fire("QUEST_ACCEPTED", 3, 3001)                  # old form: (logIndex, questID); title from the log
        g.run(2)
        self.assertEqual([m["data"] for m in g.moments("quest.accept")],
                         [{"quest": "猎杀迅猛龙", "id": 194}, {"quest": "Healing Herbs", "id": 3001}])

    def test_objective_done_then_quest_ready_after_a_baseline(self):
        g = self.game()
        g.listen()
        for _ in range(3):
            g.fire("QUEST_LOG_UPDATE")
        g.run(0.5)                                         # baseline only
        self.assertEqual(g.moments("quest.progress") + g.moments("quest.ready"), [])
        g.lua.execute(b"__quests[2].objectives[1] = { text = '|cffffffffPeacebloom: 5/5|r', finished = true } "
                      b"__quests[2].complete = true")
        for _ in range(3):
            g.fire("QUEST_LOG_UPDATE")
        g.run(0.5)
        self.assertEqual([m["data"] for m in g.moments("quest.progress")],
                         [{"quest": "Healing Herbs", "id": 3001, "objective": "Peacebloom: 5/5"}])
        self.assertEqual([m["data"] for m in g.moments("quest.ready")], [{"quest": "Healing Herbs", "id": 3001}])

    def test_quest_changes_while_nobody_listens_are_not_told_later(self):
        g = self.game()
        g.fire("QUEST_LOG_UPDATE")
        g.lua.execute(b"__quests[2].objectives[1].finished = true __quests[2].complete = true")
        g.fire("QUEST_LOG_UPDATE")
        g.run(1)
        g.listen()                                         # the baseline is read as the topic turns on
        g.fire("QUEST_LOG_UPDATE")
        g.run(0.5)
        self.assertEqual(g.moments(), [])
        g.lua.execute(b"__quests[2].objectives = { { text = 'A', finished = true }, { text = 'B', finished = false } }")
        g.fire("QUEST_LOG_UPDATE")                         # objectives changed in number: a new baseline
        g.run(0.5)
        g.lua.execute(b"__quests[2].objectives[2].finished = true")
        g.fire("QUEST_LOG_UPDATE")
        g.run(0.5)
        self.assertEqual([m["data"]["objective"] for m in g.moments("quest.progress")], ["B"])
        self.assertEqual(g.moments("quest.ready"), [])

    def test_quest_turnin(self):
        g = self.game()
        g.listen()
        g.fire("QUEST_TURNED_IN", 3001, 2150, 1500)
        g.fire("QUEST_TURNED_IN", 4242, 0, 0)
        self.assertEqual([m["data"] for m in g.moments("quest.turnin")],
                         [{"quest": "Healing Herbs", "id": 3001, "xp": 2150, "money": 1500}, {"id": 4242}])

    def test_zone_and_first_visit(self):
        g = self.game()
        g.listen()
        g.lua.execute(b"__zone = 'Zephyr Isle' function GetZoneText() return __zone end")
        g.fire("ZONE_CHANGED_NEW_AREA")                    # where it was: nothing
        for zone in ["荆棘谷", "荆棘谷", "藏宝海湾"]:
            g.lua.execute(f"__zone = '{zone}'".encode())
            g.fire("ZONE_CHANGED_NEW_AREA")
        g.run(31)
        g.lua.execute("__zone = '荆棘谷'".encode())
        g.fire("ZONE_CHANGED_NEW_AREA")
        self.assertEqual([m["data"] for m in g.moments("zone")],
                         [{"zone": "荆棘谷", "first": True}, {"zone": "藏宝海湾", "first": True},
                          {"zone": "荆棘谷", "first": False}])
        zones = py(g.lua.eval(b"WuxianKitDB.ext.game.chars[UnitGUID('player')].zones"))
        self.assertLessEqual({"荆棘谷", "藏宝海湾"}, set(zones))

    def test_zones_are_kept_while_nobody_listens(self):
        g = self.game()
        g.lua.execute(b"__zone = 'Zephyr Isle' function GetZoneText() return __zone end")
        g.lua.execute("__zone = '荆棘谷'".encode())
        g.fire("ZONE_CHANGED_NEW_AREA")                    # unheard, but been there
        g.lua.execute(b"__zone = 'Zephyr Isle'")
        g.fire("ZONE_CHANGED_NEW_AREA")
        g.listen(topics=["travel"])
        g.lua.execute("__zone = '荆棘谷'".encode())
        g.fire("ZONE_CHANGED_NEW_AREA")
        self.assertEqual([m["data"] for m in g.moments("zone")], [{"zone": "荆棘谷", "first": False}])

    def test_taxi_with_and_without_where_to(self):
        g = self.game()
        g.lua.execute("""
            __taxi = false
            function UnitOnTaxi() return __taxi end
            function TaxiNodeName(i) return i == 3 and "藏宝海湾，荆棘谷" or "?" end
            function TakeTaxiNode(i) end
            function hooksecurefunc(name, fn)
                local old = _G[name]
                _G[name] = function(...) local r = old(...) fn(...) return r end
            end
        """.encode())
        g.listen()                                         # TakeTaxiNode is hooked as travel first runs
        g.fire("PLAYER_CONTROL_LOST")                      # a stun: not on a taxi
        g.run(0.5)
        g.lua.execute(b"TakeTaxiNode(3) __taxi = true")
        g.fire("PLAYER_CONTROL_LOST")
        g.run(11)
        g.fire("PLAYER_CONTROL_LOST")                      # on a taxi with no node taken: no to
        g.run(0.5)
        self.assertEqual([m["data"] for m in g.moments("taxi")], [{"to": "藏宝海湾，荆棘谷"}, {}])

    def test_rest_when_resting_starts(self):
        g = self.game()
        g.listen()
        g.lua.execute(b"__resting = true function IsResting() return __resting end")
        g.fire("PLAYER_UPDATE_RESTING")
        g.fire("PLAYER_UPDATE_RESTING")
        g.lua.execute(b"__resting = false")
        g.fire("PLAYER_UPDATE_RESTING")
        g.run(31)
        g.lua.execute(b"__resting = true")
        g.fire("PLAYER_UPDATE_RESTING")
        self.assertEqual(len(g.moments("rest")), 2)


if __name__ == "__main__":
    unittest.main()
