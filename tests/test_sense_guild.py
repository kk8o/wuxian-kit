"""感知 (Sense) sense.guild under Lua 5.1 in the mock client, over a roster defined here: the guild's name, the player's
rank, the message of the day, counts, classes and levels of all members, the online members highest level first;
notes never read; not in a guild; a secret value left out."""
import unittest

from kitmock import Session, lupa, py

# the guild API as the client has it: GetGuildRosterInfo(i) -> name, rankName, rankIndex, level, classDisplayName, zone,
# publicNote, officerNote, isOnline, status, classFile; reading a note counts in __notesRead
ROSTER = r"""
__inGuild = true
__roster = {
	{ "看淡生死死后 依然从容施法-无限", "会长", 0, 60, "法师", "暴风城", "pub", "officer", true, 0, "MAGE" },
	{ "Ally-Forever", "Member", 3, 42, "Warrior", "Westfall", "", "", true, 0, "WARRIOR" },
	{ "Gone-Forever", "Member", 3, 60, "Priest", "", "", "", false, 0, "PRIEST" },
	{ "Bob-Forever", "Officer", 1, 60, "Priest", "Ironforge", "", "", true, 1, "PRIEST" },
	{ "Low-Forever", "Initiate", 4, 12, "Rogue", "", "", "", true, 0, "ROGUE" },
}
__notesRead = 0
function GetGuildInfo(unit)
	if unit == "player" and __inGuild then return "Wuxian Guild", "Member", 3 end
end
function GetGuildRosterMOTD() return "raid at 8" end
function GetNumGuildMembers()
	if not __inGuild then return 0, 0, 0 end
	local online = 0
	for _, m in ipairs(__roster) do if m[9] then online = online + 1 end end
	return #__roster, online, online
end
function GetGuildRosterInfo(i)
	local m = __roster[i]
	if not m then return nil end
	return m[1], m[2], m[3], m[4], m[5], m[6], setmetatable({}, { __tostring = function() __notesRead = __notesRead + 1 end }),
		setmetatable({}, { __tostring = function() __notesRead = __notesRead + 1 end }), m[9], m[10], m[11]
end
function GetMaxLevelForPlayerExpansion() return 60 end
"""


@unittest.skipIf(lupa is None, "lupa (Lua 5.1 for Python) is not installed")
class SenseGuild(unittest.TestCase):
    def start(self):
        s = Session(self)
        s.lua.execute(ROSTER.encode())
        s.login()
        s.run(1)
        self.addCleanup(lambda: self.assertEqual(s.errors(), []))
        return s

    def call(self, s, cap, args="{}"):
        s.lua.execute(f"__answer = WuxianKit:Call({cap!r}, {args})".encode())
        return py(s.g("__answer"))

    def test_the_guild(self):
        s = self.start()
        g = self.call(s, "sense.guild")
        self.assertEqual({k: g[k] for k in ("name", "rank", "motd", "total", "online", "classes", "levels")},
                         {"name": "Wuxian Guild", "rank": "Member", "motd": "raid at 8", "total": 5, "online": 4,
                          "classes": {"MAGE": 1, "WARRIOR": 1, "PRIEST": 2, "ROGUE": 1},
                          "levels": {"avg": 46.8, "median": 60, "atMax": 3}})
        self.assertEqual(g["members"], [
            {"name": "Bob", "level": 60, "class": "PRIEST", "zone": "Ironforge", "rank": "Officer", "online": True},
            {"name": "看淡生死死后 依然从容施法", "level": 60, "class": "MAGE", "zone": "暴风城", "rank": "会长",
             "online": True},
            {"name": "Ally", "level": 42, "class": "WARRIOR", "zone": "Westfall", "rank": "Member", "online": True},
            {"name": "Low", "level": 12, "class": "ROGUE", "rank": "Initiate", "online": True}])
        self.assertEqual(s.g("__notesRead"), 0)                             # notes never read
        self.assertEqual([m["name"] for m in self.call(s, "sense.guild", "{ limit = 2 }")["members"]],
                         ["Bob", "看淡生死死后 依然从容施法"])
        self.assertNotIn("members", self.call(s, "sense.guild", "{ members = false }"))
        self.assertEqual(len(self.call(s, "sense.guild", "{ limit = 0 }")["members"]), 1)     # at least one
        self.assertEqual(s.g("__notesRead"), 0)

    def test_secret_and_no_guild(self):
        s = self.start()
        s.lua.execute(b"__roster[2][4] = '<secret>' __roster[4][1] = '<secret>' "
                      b"GetGuildRosterMOTD = function() return '<secret>' end")
        g = self.call(s, "sense.guild")
        self.assertNotIn("motd", g)
        self.assertEqual([(m["name"], m.get("level")) for m in g["members"]],
                         [("看淡生死死后 依然从容施法", 60), ("Low", 12), ("Ally", None)])
        self.assertEqual((g["online"], g["levels"]), (3, {"avg": 44, "median": 60, "atMax": 2}))
        s.lua.execute(b"GetMaxLevelForPlayerExpansion = nil __roster = { __roster[5] }")
        self.assertEqual(self.call(s, "sense.guild")["levels"], {"avg": 12, "median": 12, "atMax": 0})   # 60 by default
        s.lua.execute(b"__inGuild = false")
        self.assertEqual(self.call(s, "sense.guild"), {"guild": False})


if __name__ == "__main__":
    unittest.main()
