-- 游戏动态 · Combat: the topics combat (combat.start, combat.end, danger, cast.at_me, kill, death, alive, spell.big,
-- target) and aura (aura.gift, aura.bad). Ported from 无限陪玩 (the companion's Combat.lua), as measured on 70790:
--   - UNIT_COMBAT's amount is a secret value: no damage taken, no burst, no crits; UNIT_COMBAT only marks the units in
--     the fight (the target hit, nameplates). danger is only why = "adds";
--   - the player's health and the target's health and cast (name, id) are secret; UnitThreatSituation on nameplates,
--     UnitIsUnit("targettarget", "player") and the player's own UNIT_SPELLCAST_SUCCEEDED are plain;
--   - right at PLAYER_REGEN_DISABLED the nameplates' threat is not there yet: foes are counted 0.5 s later;
--   - in instances a target's GUID and name may be secret: such kills go uncounted;
--   - auras are read only out of combat (in combat addedAuras may be a secret table).
-- Kills are told a window at a time: the first one opens KILL_WINDOW seconds, and what died in them goes out as one kill
-- { unit (the first of them), count, streak } when they are over, or at once when the fight ends before (so a kill is
-- told before its fight's combat.end). streak counts the kills within STREAK seconds up to the window's last, these
-- too, across fights. Kills and deaths go to the day's tally (G.Tally).
-- UNIT_COMBAT, UNIT_HEALTH and NAME_PLATE_UNIT_REMOVED are registered only during a fight that started while combat ran;
-- UNIT_AURA only out of combat while aura runs. Never COMBAT_LOG_EVENT_UNFILTERED.
local addonName, ns = ...
local Kit = WuxianKit
local G = ns.game
local Read, Num, Yes = G.Read, G.Num, G.Yes

local ADDS = 3               -- enemies hitting you at once: danger
local DANGER_GAP = 8         -- seconds between two dangers of one fight
local START_DELAY = 0.5      -- threat is not there right at the start of a fight
local PLATES = 40
local STREAK = 30            -- seconds a kill counts in the streak
local KILL_WINDOW = 1        -- seconds of kills told as one moment

local NOTABLE = { elite = true, rare = true, rareelite = true, worldboss = true }
local DISPELS = { Poison = true, Curse = true, Disease = true, Magic = true }
local IN_FIGHT = { UNIT_COMBAT = true, UNIT_HEALTH = true, NAME_PLATE_UNIT_REMOVED = true }

local fight                  -- this fight's count; nil: not in one (or it started while combat did not run)
local engaged = {}           -- GUIDs of the units of this fight: with threat on you, or hit as your target
local done, doneCount = {}, 0   -- GUIDs already told as kills
local dead = false
local rezAt                  -- when someone last offered to resurrect you
local paced = {}             -- kind -> GetTime() it last went out
local ticker                 -- counts the foes every second during a fight
local kills = {}             -- GetTime() of the kills within STREAK seconds, oldest first
local window                 -- the kills not told yet: { unit, count, streak }; nil: none

------------------------------------------------------------------------------------------------------------------------
-- reading units (all through Kit:Value)

local function Exists(unit)
	return UnitExists ~= nil and Yes(Read(UnitExists, unit))
end

local function Guid(unit)
	local g = Read(UnitGUID, unit)
	return type(g) == "string" and g ~= "" and g or nil
end

local function Threat(unit)
	return UnitThreatSituation and Num(Read(UnitThreatSituation, "player", unit)) or nil
end

local function Hostile(unit)
	return UnitCanAttack ~= nil and Yes(Read(UnitCanAttack, "player", unit))
end

local function Dead(unit)
	return UnitIsDead ~= nil and Yes(Read(UnitIsDead, unit))
end

local function Round(x)
	return math.floor(x + 0.5)
end

local function SpellName(id)
	local name = C_Spell and C_Spell.GetSpellName and Read(C_Spell.GetSpellName, id)
	if not name and GetSpellInfo then name = Read(GetSpellInfo, id) end
	return Kit:Clean(name)
end

-- one moment: the same kind at most once a second; every and key go to G.Moment
local function Send(kind, data, every, key)
	local now = GetTime()
	if paced[kind] and now - paced[kind] < 1 then return false end
	local sent = G.Moment(kind, data, { every = every, key = key })
	if sent then paced[kind] = now end
	return sent
end

------------------------------------------------------------------------------------------------------------------------
-- kills

-- the window's kills as one moment
local function TellKills()
	local w = window
	if not w then return end
	window = nil
	G.Moment("kill", { unit = w.unit, count = w.count, streak = w.streak })
end

local function CheckDead(unit)
	local guid = Guid(unit)
	if not (guid and engaged[guid]) or done[guid] or not Dead(unit) then return end
	if doneCount > 200 then done, doneCount = {}, 0 end
	done[guid], doneCount = true, doneCount + 1
	if fight then fight.kills = fight.kills + 1 end
	local now, recent = GetTime(), {}
	for _, at in ipairs(kills) do
		if now - at < STREAK then recent[#recent + 1] = at end
	end
	recent[#recent + 1] = now
	kills = recent
	G.Tally("kills")
	if window then
		window.count, window.streak = window.count + 1, #recent
		return
	end
	local w = { unit = Kit:Unit(unit), count = 1, streak = #recent }
	window = w
	C_Timer.After(KILL_WINDOW, function()
		if window == w then TellKills() end
	end)
end

-- a unit of this fight: one with threat; force (your target, hit) needs none
local function Engage(unit, force)
	local guid = Guid(unit)
	if not guid or engaged[guid] or Dead(unit) then return end
	if Threat(unit) or (force and Hostile(unit)) then engaged[guid] = true end
end

-- the target and the nameplates (each GUID once): any = enemies with threat on you (above 0), on = those hitting you
-- (2 or more); withTarget: a hostile target counts without threat (right at the start)
local function Scan(withTarget)
	local seen, any, on = {}, 0, 0
	local function Look(unit, isTarget)
		if not Exists(unit) then return end
		local guid = Guid(unit)
		if not guid or seen[guid] then return end
		seen[guid] = true
		if Dead(unit) then
			CheckDead(unit)
			return
		end
		local threat = Threat(unit)
		if threat then engaged[guid] = true end
		if (threat and threat > 0) or (isTarget and Hostile(unit) and (withTarget or threat)) then any = any + 1 end
		if threat and threat >= 2 then on = on + 1 end
	end
	Look("target", true)
	for i = 1, PLATES do Look("nameplate" .. i) end
	return any, on
end

local function Danger(foes)
	local f, now = fight, GetTime()
	if not (f and f.started) or (f.dangerAt and now - f.dangerAt < DANGER_GAP) then return end
	if G.Moment("danger", { why = "adds", foes = foes }) then f.dangerAt = now end
end

------------------------------------------------------------------------------------------------------------------------
-- into and out of a fight

local function EndFight()
	fight, engaged = nil, {}
	if ticker then ticker:Cancel() end
	ticker = nil
	for event in pairs(IN_FIGHT) do G.Unregister("combat", event) end
end

local function Count()
	local f = fight
	if not f then return end
	local any, on = Scan()
	f.foes, f.on = math.max(f.foes, any), on
	if on >= ADDS then Danger(on) end
end

local function FightStarts()
	EndFight()
	local f = { at = GetTime(), kills = 0, foes = 0, on = 0 }
	fight = f
	for event in pairs(IN_FIGHT) do G.Register("combat", event) end
	ticker = C_Timer.NewTicker(1, Count)
	C_Timer.After(START_DELAY, function()
		if fight ~= f then return end                    -- out of the fight again within that time
		local any, on = Scan(true)
		any = math.max(any, 1)
		f.foes, f.on = math.max(f.foes, any), on
		local target = Hostile("target") and Kit:Unit("target") or nil
		f.started = G.Moment("combat.start", { target = target, foes = any }, { every = 1 })
	end)
end

local function FightEnds()
	local f = fight
	if not f then return end
	Scan()                                               -- the last one may have died without a UNIT_HEALTH
	TellKills()                                          -- before the fight's end is told
	EndFight()
	if not f.started then return end
	G.Moment("combat.end", { secs = Round(GetTime() - f.at), kills = f.kills, foes = math.max(f.foes, 1) })
end

-- UNIT_COMBAT comes once for each of nameplateN, target, targettarget, player of one hit; its amount and flags are
-- secret: it only tells which units take part
local function UnitCombat(_, unit, event)
	if not fight then return end
	unit, event = Kit:Value(unit), Kit:Value(event)
	if unit == "target" or (type(unit) == "string" and unit:match("^nameplate%d+$")) then
		Engage(unit, event == "WOUND" and unit == "target")
	end
end

local function DeadCheck(_, unit)
	unit = Kit:Value(unit)
	if fight and type(unit) == "string" and unit ~= "player" then CheckDead(unit) end
end

------------------------------------------------------------------------------------------------------------------------
-- the target

local function TargetChanged()
	if fight then
		Engage("target")
		CheckDead("target")
	end
	if not Exists("target") or Dead("target") or not Hostile("target") then return end
	local cls = UnitClassification and Read(UnitClassification, "target")
	if not (NOTABLE[cls] or (UnitIsPlayer ~= nil and Yes(Read(UnitIsPlayer, "target")))) then return end
	local unit = Kit:Unit("target")
	Send("target", { unit = unit }, 60, Guid("target") or (unit and unit.name) or "?")
end

-- the target casts and its target is you (the spell's name and id are secret: not told)
local function CastAtMe(_, unit)
	if Kit:Value(unit) ~= "target" or not Hostile("target") then return end
	if not (UnitIsUnit and Yes(Read(UnitIsUnit, "targettarget", "player"))) then return end
	local caster = Kit:Unit("target")
	Send("cast.at_me", { caster = caster }, 6, Guid("target") or (caster and caster.name) or "?")
end

-- your own spell with a base cooldown of a minute or more
local function Succeeded(_, unit, _, spellID)
	if Kit:Value(unit) ~= "player" then return end
	local id = Num(spellID)
	local base = GetSpellBaseCooldown or (C_Spell and C_Spell.GetSpellBaseCooldown)
	if not (id and base) then return end
	local ms = Num(Read(base, id))
	if not ms or ms < 60000 then return end
	Send("spell.big", { spell = SpellName(id), id = id, cd = Round(ms / 1000) }, 30, id)
end

------------------------------------------------------------------------------------------------------------------------
-- death and coming back

local function Alive(how)
	if not dead then return end
	dead, rezAt = false, nil
	G.Moment("alive", { how = how }, { every = 5 })
end

G.Topic("combat", {
	events = {
		PLAYER_REGEN_DISABLED = FightStarts,
		PLAYER_REGEN_ENABLED = FightEnds,
		UNIT_COMBAT = UnitCombat,
		UNIT_HEALTH = DeadCheck,
		NAME_PLATE_UNIT_REMOVED = DeadCheck,
		PLAYER_TARGET_CHANGED = TargetChanged,
		UNIT_SPELLCAST_START = CastAtMe,
		UNIT_SPELLCAST_CHANNEL_START = CastAtMe,
		UNIT_SPELLCAST_SUCCEEDED = Succeeded,
		PLAYER_DEAD = function()
			if not dead then G.Tally("deaths") end
			dead, rezAt = true, nil
			G.Moment("death", {}, { every = 5 })
		end,
		RESURRECT_REQUEST = function() rezAt = GetTime() end,
		-- up without releasing (or by yourself); after a release PLAYER_ALIVE comes as a ghost: skipped
		PLAYER_ALIVE = function()
			if UnitIsGhost and Yes(Read(UnitIsGhost, "player")) then return end
			Alive("revive")
		end,
		-- up from a ghost: someone's resurrection within a minute, else a corpse run or the spirit healer
		PLAYER_UNGHOST = function() Alive(rezAt and GetTime() - rezAt < 60 and "revive" or "spirit") end,
	},
	units = { UNIT_SPELLCAST_START = { "target" }, UNIT_SPELLCAST_CHANNEL_START = { "target" },
		UNIT_SPELLCAST_SUCCEEDED = { "player" } },
	later = IN_FIGHT,
	on = function()
		EndFight()                                       -- a fight going on now started unheard: not told
		dead = UnitIsDeadOrGhost ~= nil and Yes(Read(UnitIsDeadOrGhost, "player"))
		rezAt, kills, window = nil, {}, nil
	end,
	off = function()
		EndFight()
		window = nil
	end,
})

------------------------------------------------------------------------------------------------------------------------
-- auras (out of combat only)

local function InCombat()
	return (InCombatLockdown and InCombatLockdown()) or (UnitAffectingCombat and Yes(Read(UnitAffectingCombat, "player")))
end

local function Aura(a)
	if type(a) ~= "table" then return end
	local spell = Kit:Clean(a.name)
	local id = Num(a.spellId)
	if not spell then return end
	if Yes(a.isHelpful) then
		local source = Kit:Value(a.sourceUnit)
		if type(source) ~= "string" or not (UnitIsPlayer and Yes(Read(UnitIsPlayer, source))) then return end
		if UnitIsUnit and Yes(Read(UnitIsUnit, source, "player")) then return end
		local from = Kit:Clean(GetUnitName and Read(GetUnitName, source, true)) or Kit:Clean((Read(UnitName, source)))
		if from then Send("aura.gift", { spell = spell, from = from }, 60, id or spell) end
	elseif Yes(a.isHarmful) then
		local kind = Kit:Value(a.dispelName)
		if DISPELS[kind] then Send("aura.bad", { spell = spell, type = kind }, 60, id or spell) end
	end
end

local function Auras(info)
	if type(info) ~= "table" or Kit:Value(info.isFullUpdate) then return end
	local added = info.addedAuras
	if type(added) ~= "table" then return end
	for _, a in ipairs(added) do Aura(a) end
end

G.Topic("aura", {
	events = {
		UNIT_AURA = function(_, unit, info)
			if Kit:Value(unit) ~= "player" or InCombat() then return end
			pcall(Auras, info)
		end,
		PLAYER_REGEN_DISABLED = function() G.Unregister("aura", "UNIT_AURA") end,
		PLAYER_REGEN_ENABLED = function() G.Register("aura", "UNIT_AURA") end,
	},
	units = { UNIT_AURA = { "player" } },
	later = { UNIT_AURA = true },
	on = function()
		if not InCombat() then G.Register("aura", "UNIT_AURA") end
	end,
})
