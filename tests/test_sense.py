"""感知 (Sense) under Lua 5.1 in the mock client: the character, where it is, its bags, quests, professions,
reputations, currencies and group, read at once; a value the client keeps secret is left out."""
import unittest

from kitmock import Session, lupa, py


@unittest.skipIf(lupa is None, "lupa (Lua 5.1 for Python) is not installed")
class Sense(unittest.TestCase):
    def start(self):
        s = Session(self)
        s.login()
        s.run(1)
        self.addCleanup(lambda: self.assertEqual(s.errors(), []))
        return s

    def call(self, s, cap, args="{}"):
        s.lua.execute(f"__answer = WuxianKit:Call({cap!r}, {args})".encode())
        return py(s.g("__answer"))

    def test_the_character_and_where_it_is(self):
        s = self.start()
        c = self.call(s, "sense.character")
        self.assertEqual({k: c.get(k) for k in ("name", "realm", "level", "class", "classToken", "race", "faction", "xp",
                                                "xpMax", "money", "itemLevel", "spec", "guild")},
                         {"name": "Wuxian", "realm": "Forever", "level": 8, "class": "Priest", "classToken": "PRIEST",
                          "race": "Night Elf", "faction": "Alliance", "xp": 190, "xpMax": 5400, "money": 480,
                          "itemLevel": 9.5, "spec": {"id": 1484, "name": "Holy"},
                          "guild": {"name": "Wuxian Guild", "rank": "Member"}})
        self.assertFalse({"health", "resting", "rested"} & set(c))
        s.lua.execute(b"__player.level = '<secret>'")                     # what the client keeps secret is left out
        self.assertNotIn("level", self.call(s, "sense.character"))
        self.assertEqual(self.call(s, "sense.position"),
                         {"zone": "Zephyr Isle", "map": {"id": 2521, "name": "Zephyr Isle"}, "x": 41.8, "y": 62.3})

    def test_bags_quests_and_the_rest(self):
        s = self.start()
        bags = self.call(s, "sense.bags")
        self.assertEqual((bags["free"], bags["total"], bags["bags"]),
                         (19, 22, [{"bag": 0, "slots": 16, "free": 13}, {"bag": 1, "slots": 6, "free": 6}]))
        self.assertEqual(bags["items"], [{"id": 2589, "name": "Linen Cloth", "count": 20, "quality": 1},
                                         {"id": 7166, "name": "Copper Dagger", "count": 1, "quality": 1}])
        found = self.call(s, "sense.bags", "{ text = 'dagger' }")["items"]
        self.assertEqual([(i["bag"], i["slot"], i["name"], i["count"]) for i in found], [(0, 1, "Copper Dagger", 1)])
        self.assertEqual(self.call(s, "sense.quests"), [
            {"id": 3001, "title": "Healing Herbs", "level": 7, "objectives": [{"text": "Peacebloom: 3/5", "have": 3, "need": 5}]},
            {"id": 3002, "title": "A Letter", "level": 8, "complete": True, "objectives": {}}])
        self.assertEqual(self.call(s, "sense.professions"), [
            {"name": "Leatherworking", "level": 37, "max": 75, "skillLine": 165},
            {"name": "Skinning", "level": 73, "max": 75, "skillLine": 393},
            {"name": "Fishing", "level": 1, "max": 75, "skillLine": 356}])
        self.assertEqual(self.call(s, "sense.reputation"), [
            {"name": "Darnassus", "id": 69, "standing": "Friendly", "value": 1200, "max": 6000, "watched": True},
            {"name": "Stormwind", "id": 72, "standing": "Neutral", "value": 100, "max": 3000}])
        self.assertEqual([r["name"] for r in self.call(s, "sense.reputation", "{ text = 'storm' }")], ["Stormwind"])
        self.assertEqual(self.call(s, "sense.currency"), [{"name": "Honor", "count": 10}])
        self.assertEqual(self.call(s, "sense.group"), {"kind": "none", "members": {}})
        s.lua.execute(b"__group = { { name = 'Ally', class = 'MAGE', level = 9, role = 'DAMAGER' } }")
        self.assertEqual(self.call(s, "sense.group"), {"kind": "party", "members": [
            {"name": "Wuxian", "class": "PRIEST", "level": 8, "role": "NONE", "online": True, "leader": True},
            {"name": "Ally", "class": "MAGE", "level": 9, "role": "DAMAGER", "online": True}]})


if __name__ == "__main__":
    unittest.main()
