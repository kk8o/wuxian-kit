"""游戏动态 · Combat.lua (topics combat and aura), ported from 无限陪玩's tests: fights, danger (adds only: since 70790
UNIT_COMBAT's amount is secret), casts at you, kills, death and coming back, big cooldowns, notable targets, auras; nothing
while nobody hears, no error on secret values."""
import unittest

from test_game import GameTest

# unit APIs the mock client lacks: __units[unit] = { guid, name, second, level, cls, creature, player, hostile, dead, threat }
UNITS = r"""
__units = {}
__maxhp = 1000
__ghost = false
__cds, __spells = {}, {}
local guid0, name0, level0 = UnitGUID, UnitName, UnitLevel
function UnitExists(u) return u == "player" or __units[u] ~= nil end
function UnitGUID(u) local x = __units[u] if x then return x.guid end return guid0(u) end
function UnitName(u) local x = __units[u] if x then return x.name, x.second end return name0(u) end
function UnitLevel(u) local x = __units[u] if x then return x.level or 10 end return level0(u) end
function UnitClassification(u) local x = __units[u] return x and x.cls or "normal" end
function UnitCreatureType(u) local x = __units[u] return x and x.creature end
function UnitIsPlayer(u) if u == "player" then return true end local x = __units[u] return x ~= nil and x.player == true end
function UnitCanAttack(_, u) local x = __units[u] return x ~= nil and x.hostile == true end
function UnitIsDead(u) local x = __units[u] return x ~= nil and x.dead == true end
function UnitIsUnit(a, b) local ga, gb = UnitGUID(a), UnitGUID(b) return ga ~= nil and ga == gb end
function UnitThreatSituation(_, u) local x = __units[u] return x and x.threat end
function UnitHealthMax(u) if u == "player" then return __maxhp end end
function UnitIsGhost(u) return u == "player" and __ghost end
function GetSpellBaseCooldown(id) return __cds[id], 1500 end
C_Spell.GetSpellName = function(id) return __spells[id] end
function __mob(units, fields)
	for u in units:gmatch("%S+") do
		local x = {}
		for k, v in pairs(fields) do x[k] = v end
		__units[u] = x
	end
end
function __set(guid, k, v)
	for _, x in pairs(__units) do if x.guid == guid then x[k] = v end end
end
"""


class Combat(GameTest):
    def start(self, listen=True):
        g = self.game()
        g.lua.execute(UNITS.encode())
        if listen:
            g.listen()
        return g

    def lua(self, g, code):
        g.lua.execute(code.encode())

    def mob(self, g, units, guid, **f):
        fields = {"guid": guid, "name": f.pop("name", "Raptor"), "hostile": f.pop("hostile", True), **f}
        body = ", ".join(f"{k} = {self.lit(v)}" for k, v in fields.items())
        self.lua(g, f"__mob({units!r}, {{ {body} }})")

    @staticmethod
    def lit(v):
        if isinstance(v, bool):
            return "true" if v else "false"
        if isinstance(v, (int, float)):
            return repr(v)
        if v is None:
            return "nil"
        return '"' + str(v).replace("\\", "\\\\").replace('"', '\\"') + '"'

    def combat(self, g, on):
        self.lua(g, f"__combat({'true' if on else 'false'})")

    def hit(self, g, unit="player", event="WOUND", flag="<secret>", amount="<secret>"):
        """UNIT_COMBAT as on 70790: the flag and the amount are secret"""
        g.fire("UNIT_COMBAT", unit, event, flag, amount, 1)

    def kinds(self, g):
        return [m["kind"] for m in g.moments()]

    # ---------------------------------------------------------------------------------------------------------------

    def test_combat_start_counts_foes_half_a_second_later(self):
        g = self.start()
        self.mob(g, "target nameplate1", "Creature-A", name="Raptor", level=23, creature="Beast")
        self.mob(g, "nameplate2", "Creature-B", threat=3)
        self.mob(g, "nameplate3", "Creature-C", threat=0)                     # 0: not on you, does not count
        self.combat(g, True)
        g.run(0.3)
        self.assertEqual(g.moments("combat.start"), [])
        self.lua(g, '__set("Creature-A", "threat", 3)')                        # the threat only now
        g.run(0.3)
        [m] = g.moments("combat.start")
        self.assertEqual(m["data"]["foes"], 2)
        self.assertEqual(m["data"]["target"], {"name": "Raptor", "fullName": "Raptor", "level": 23,
                                               "classification": "normal", "creature": "Beast", "hostile": True})

    def test_combat_start_needs_at_least_one_foe_and_no_quick_exit(self):
        g = self.start()
        self.combat(g, True)
        g.run(0.2)
        self.combat(g, False)                                                  # out again within 0.5 s: nothing
        g.run(2)
        self.assertEqual(g.moments(), [])
        self.combat(g, True)
        g.run(0.6)
        [m] = g.moments("combat.start")
        self.assertEqual(m["data"], {"foes": 1})

    def test_combat_end_sums_up_the_fight(self):
        g = self.start()
        self.mob(g, "target nameplate1", "Creature-A", threat=3)
        self.mob(g, "nameplate2", "Creature-B", threat=3)
        self.combat(g, True)
        g.run(0.6)
        self.hit(g)
        g.run(1)
        self.hit(g, unit="target")
        self.hit(g, unit="nameplate1")
        self.hit(g, event="HEAL")
        g.run(5)
        self.lua(g, '__set("Creature-A", "dead", true)')
        g.fire("UNIT_HEALTH", "target")
        g.run(0.4)
        self.combat(g, False)
        [m] = g.moments("combat.end")
        self.assertEqual(m["data"], {"secs": 7, "kills": 1, "foes": 2})       # no taken, peak, crits: secret now
        self.assertEqual(self.kinds(g), ["combat.start", "kill", "combat.end"])

    def test_no_danger_from_damage(self):
        g = self.start()
        self.mob(g, "target", "Creature-A", threat=3)
        self.combat(g, True)
        g.run(0.6)
        for _ in range(5):
            self.hit(g)
            self.hit(g, amount=500, flag="CRITICAL")                           # even a plain amount tells nothing
        g.run(2)
        self.assertEqual(self.kinds(g), ["combat.start"])

    def test_danger_adds_when_three_hit_you(self):
        g = self.start()
        self.mob(g, "target nameplate1", "Creature-A", threat=3)
        self.mob(g, "nameplate2", "Creature-B", threat=2)
        self.mob(g, "nameplate3", "Creature-C", threat=1)                      # high threat, not hitting you
        self.combat(g, True)
        g.run(2)
        self.assertEqual(g.moments("danger"), [])
        self.lua(g, '__set("Creature-C", "threat", 3)')
        g.run(1)
        [m] = g.moments("danger")
        self.assertEqual(m["data"], {"why": "adds", "foes": 3})
        g.run(3)
        self.assertEqual(len(g.moments("danger")), 1)
        self.combat(g, False)
        self.assertEqual(g.moments("combat.end")[0]["data"]["foes"], 3)

    def test_kill_once_per_unit_and_only_ones_you_fought(self):
        g = self.start()
        self.mob(g, "target", "Creature-A", name="Boar")                       # no threat: counts once hit
        self.mob(g, "nameplate2", "Creature-B", name="Wolf")                   # never touched
        self.combat(g, True)
        g.run(0.6)
        self.hit(g, unit="target")
        self.lua(g, '__set("Creature-A", "dead", true) __set("Creature-B", "dead", true)')
        g.fire("UNIT_HEALTH", "nameplate2")
        g.fire("UNIT_HEALTH", "target")
        g.run(1.5)
        g.fire("UNIT_HEALTH", "target")
        g.fire("NAME_PLATE_UNIT_REMOVED", "nameplate2")
        g.fire("PLAYER_TARGET_CHANGED")
        kills = g.moments("kill")
        self.assertEqual([k["data"]["unit"]["name"] for k in kills], ["Boar"])

    def test_kill_found_when_combat_ends_first(self):
        g = self.start()
        self.mob(g, "target", "Creature-A", threat=3)
        self.combat(g, True)
        g.run(1.5)
        self.lua(g, '__set("Creature-A", "dead", true)')
        self.combat(g, False)
        self.assertEqual(self.kinds(g), ["combat.start", "kill", "combat.end"])
        self.assertEqual(g.moments("combat.end")[0]["data"]["kills"], 1)

    def test_cast_at_me(self):
        g = self.start()
        self.mob(g, "target", "Creature-A", name="Shaman", cls="elite")
        self.lua(g, '__units.targettarget = { guid = UnitGUID("player") }')
        g.fire("UNIT_SPELLCAST_START", "target", "Cast-1", "<secret>")
        g.fire("UNIT_SPELLCAST_CHANNEL_START", "target", "Cast-2", "<secret>")   # the same target once in 6 s
        g.fire("UNIT_SPELLCAST_START", "nameplate1", "Cast-3", "<secret>")
        [m] = g.moments("cast.at_me")
        self.assertEqual(m["data"]["caster"]["name"], "Shaman")
        g.run(7)
        self.lua(g, '__units.targettarget = { guid = "Creature-Z" }')
        g.fire("UNIT_SPELLCAST_START", "target", "Cast-4", "<secret>")
        self.assertEqual(len(g.moments("cast.at_me")), 1)
        self.lua(g, '__units.targettarget = { guid = UnitGUID("player") }')
        g.fire("UNIT_SPELLCAST_CHANNEL_START", "target", "Cast-5", "<secret>")
        self.assertEqual(len(g.moments("cast.at_me")), 2)

    def test_death_and_alive(self):
        g = self.start()
        g.fire("PLAYER_ALIVE")                                                 # not dead: nothing
        g.fire("PLAYER_DEAD")
        self.lua(g, "__ghost = true")
        g.fire("PLAYER_ALIVE")                                                 # released
        g.run(30)
        self.lua(g, "__ghost = false")
        g.fire("PLAYER_UNGHOST")
        g.run(10)
        g.fire("PLAYER_DEAD")
        g.run(3)
        g.fire("RESURRECT_REQUEST", "Aya")
        g.fire("PLAYER_ALIVE")
        g.run(10)
        g.fire("PLAYER_DEAD")
        self.lua(g, "__ghost = true")
        g.fire("PLAYER_ALIVE")
        g.run(20)
        g.fire("RESURRECT_REQUEST", "Aya")
        self.lua(g, "__ghost = false")
        g.fire("PLAYER_UNGHOST")
        out = [(m["kind"], m["data"].get("how")) for m in g.moments()]
        self.assertEqual(out, [("death", None), ("alive", "spirit"), ("death", None), ("alive", "revive"),
                               ("death", None), ("alive", "revive")])

    def test_spell_big(self):
        g = self.start()
        self.lua(g, '__cds[12472] = 180000 __cds[133] = 0 __cds[2139] = 24000 __spells[12472] = "Icy Veins"')
        g.fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-1", 133)
        g.fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-2", 2139)
        g.fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-3", 999)          # no cooldown known
        g.fire("UNIT_SPELLCAST_SUCCEEDED", "pet", "Cast-4", 12472)
        g.fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-5", 12472)
        [m] = g.moments()
        self.assertEqual((m["kind"], m["data"]), ("spell.big", {"spell": "Icy Veins", "id": 12472, "cd": 180}))

    def test_target_notable_once_a_minute(self):
        g = self.start()
        self.mob(g, "target", "Creature-R", name="Shadowfang", cls="rare", level=-1)
        g.fire("PLAYER_TARGET_CHANGED")
        g.fire("PLAYER_TARGET_CHANGED")
        g.run(2)
        self.mob(g, "target", "Creature-N", name="Boar")                       # a normal mob
        g.fire("PLAYER_TARGET_CHANGED")
        self.mob(g, "target", "Creature-G", name="Guard", cls="elite", hostile=False)   # a friendly elite
        g.fire("PLAYER_TARGET_CHANGED")
        self.mob(g, "target", "Player-2", name="Orc", second="Forever", player=True)
        g.fire("PLAYER_TARGET_CHANGED")
        g.run(2)
        self.mob(g, "target", "Creature-R", name="Shadowfang", cls="rare", level=-1)
        g.fire("PLAYER_TARGET_CHANGED")                                        # the same one within 60 s
        g.run(60)
        g.fire("PLAYER_TARGET_CHANGED")
        names = [m["data"]["unit"]["name"] for m in g.moments("target")]
        self.assertEqual(names, ["Shadowfang", "Orc", "Shadowfang"])
        self.assertEqual(g.moments("target")[0]["data"]["unit"],
                         {"name": "Shadowfang", "fullName": "Shadowfang", "level": -1, "classification": "rare",
                          "hostile": True})

    def test_auras_out_of_combat(self):
        g = self.start()
        self.lua(g, '__units.party1 = { guid = "Player-3", name = "Aya", second = "Forever", player = true }')
        fire = lambda info: self.lua(g, f'__fire("UNIT_AURA", "player", {info})')
        fire('{ addedAuras = { { name = "Fortitude", spellId = 1243, isHelpful = true, sourceUnit = "party1" },'
             ' { name = "Ice Armor", spellId = 7302, isHelpful = true, sourceUnit = "player" },'
             ' { name = "Well Fed", spellId = 1, isHelpful = true } } }')
        g.run(1.5)
        fire('{ addedAuras = { { name = "Venom", spellId = 744, isHarmful = true, dispelName = "Poison" },'
             ' { name = "Sunder", spellId = 7386, isHarmful = true } } }')
        g.run(1.5)
        fire('{ isFullUpdate = true, addedAuras = { { name = "Curse", spellId = 5, isHarmful = true,'
             ' dispelName = "Curse" } } }')
        g.run(1.5)
        fire('{ addedAuras = { { name = "Venom", spellId = 744, isHarmful = true, dispelName = "Poison" } } }')
        g.fire("UNIT_AURA", "target")
        self.combat(g, True)
        fire('{ addedAuras = { { name = "Hex", spellId = 6, isHarmful = true, dispelName = "Magic" } } }')
        out = [(m["kind"], m["data"]) for m in g.moments() if m["kind"].startswith("aura.")]
        self.assertEqual(out, [("aura.gift", {"spell": "Fortitude", "from": "Aya Forever"}),
                               ("aura.bad", {"spell": "Venom", "type": "Poison"})])

    def test_nothing_goes_out_while_nobody_listens(self):
        g = self.start(listen=False)
        self.mob(g, "target nameplate1", "Creature-A", cls="elite", threat=3)
        self.mob(g, "nameplate2 nameplate3", "Creature-B", threat=3)
        self.lua(g, '__units.targettarget = { guid = UnitGUID("player") } __cds[1] = 120000')
        g.fire("PLAYER_TARGET_CHANGED")
        self.combat(g, True)
        g.run(1)
        self.hit(g)
        g.fire("UNIT_SPELLCAST_START", "target")
        g.fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-1", 1)
        self.lua(g, '__set("Creature-A", "dead", true)')
        g.fire("UNIT_HEALTH", "target")
        g.fire("PLAYER_DEAD")
        self.combat(g, False)
        self.lua(g, '__fire("UNIT_AURA", "player", { addedAuras = { { name = "V", spellId = 2, isHarmful = true,'
                    ' dispelName = "Poison" } } })')
        g.run(2)
        self.assertEqual(g.moments(), [])
        self.combat(g, True)                                                   # a fight begun unheard is not told when hearing starts midway
        g.run(0.2)
        g.listen()
        g.run(2)
        self.hit(g)
        self.combat(g, False)
        self.assertEqual(g.moments(), [])

    def test_secret_values_do_not_break_anything(self):
        g = self.start()
        self.lua(g, r'''
            __maxhp = "<secret>"
            __mob("target nameplate1", { guid = "<secret>", name = "<secret>", level = "<secret>", cls = "<secret>",
                hostile = true, threat = "<secret>", creature = "<secret>" })
            __mob("nameplate2", { guid = "Creature-B", name = "Wolf", hostile = true, threat = "<secret>" })
            __cds[1] = "<secret>"
            function UnitIsUnit() return "<secret>" end
            function UnitIsDead(u) return "<secret>" end
        ''')
        g.fire("PLAYER_TARGET_CHANGED")
        self.combat(g, True)
        g.run(1.5)
        self.hit(g)
        self.hit(g, amount=300)
        self.hit(g, unit="target")
        g.fire("UNIT_SPELLCAST_START", "target")
        g.fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-1", 1)
        g.fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-2", "<secret>")
        g.fire("UNIT_HEALTH", "target")
        g.fire("UNIT_COMBAT", "<secret>", "<secret>", "<secret>", "<secret>", "<secret>")
        g.run(2.5)
        self.combat(g, False)
        self.lua(g, r'''
            local secret = setmetatable({}, { __index = function() error("attempt to index a secret table") end })
            __fire("UNIT_AURA", "player", secret)
            __fire("UNIT_AURA", "player", { addedAuras = secret })
            __fire("UNIT_AURA", "player", { addedAuras = { { name = "<secret>", spellId = "<secret>",
                isHelpful = "<secret>", isHarmful = "<secret>", sourceUnit = "<secret>", dispelName = "<secret>" } } })
            __fire("UNIT_AURA", "<secret>", "<secret>")
        ''')
        self.assertEqual(self.kinds(g), ["combat.start", "combat.end"])
        start, end = g.moments("combat.start")[0]["data"], g.moments("combat.end")[0]["data"]
        self.assertEqual(start, {"foes": 1, "target": {"hostile": True}})
        self.assertEqual(end, {"secs": 4, "kills": 0, "foes": 1})


if __name__ == "__main__":
    unittest.main()
