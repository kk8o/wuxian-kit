-- 游戏动态 · Growth: the topic growth (xp, level, talent, spell.new). Ported from 无限陪玩 (the companion's
-- Progress.lua). The xp, level and talent baselines are taken when the topic turns on, so the first change after it is
-- measured against then.
local addonName, ns = ...
local Kit = WuxianKit
local G = ns.game
local Read, Num = G.Read, G.Num

local function InCombat()
	return (InCombatLockdown and InCombatLockdown()) or Read(UnitAffectingCombat, "player") and true or false
end

-- when the last fight ended and a quest was turned in: where xp came from
local leftCombatAt, turnedInAt = -100, -100

------------------------------------------------------------------------------------------------------------------------
-- xp and level

local XP_MARKS = { 25, 50, 75, 90 }
local xpLast, xpMaxLast, levelLast              -- the baseline: xp, its max, the level
local xpPending, xpAt, xpFight                  -- a change being gathered: when it began, whether in combat
local leveledAt = -100

local function XPNow()
	return Num(Read(UnitXP, "player")), Num(Read(UnitXPMax, "player")), Num(Read(UnitLevel, "player"))
end

local function XPBase()
	xpLast, xpMaxLast, levelLast = XPNow()
end

local function XPFlush()
	xpPending = false
	if not G.active.growth then return end
	local xp, max, level = XPNow()
	local before, beforeMax, beforeLevel = xpLast, xpMaxLast, levelLast
	xpLast, xpMaxLast, levelLast = xp, max, level
	if not (xp and max and max > 0 and before and beforeMax and beforeMax > 0) then return end
	if level ~= beforeLevel or xp < before or GetTime() - leveledAt < 1.5 then return end   -- a level: only level
	local gained = xp - before
	if gained <= 0 then return end
	local was, now = before * 100 / max, xp * 100 / max
	local crossed = gained * 100 / max >= 5
	for _, mark in ipairs(XP_MARKS) do
		if was < mark and now >= mark then crossed = true end
	end
	if not crossed then return end
	local from = "other"
	if math.abs(xpAt - turnedInAt) <= 1 then from = "quest"
	elseif xpFight or xpAt - leftCombatAt <= 2 then from = "kill" end
	G.Moment("xp", { gained = gained, pct = math.floor(now), from = from })
end

local function XPUpdate(_, unit)
	if unit and Kit:Value(unit) ~= "player" then return end
	if not xpLast then XPBase() return end
	if xpPending then return end
	xpPending, xpAt, xpFight = true, GetTime(), InCombat()
	C_Timer.After(0.3, XPFlush)                  -- the turn-in and level events may come a moment later
end

-- unspent talent points: the Trait trees' currencies summed, else the classic UnitCharacterPoints
local function UnspentPoints()
	local ok, n = pcall(function()
		if C_ClassTalents and C_ClassTalents.GetActiveConfigID and C_Traits and C_Traits.GetTreeCurrencyInfo then
			local cfg = C_ClassTalents.GetActiveConfigID()
			local info = cfg and C_Traits.GetConfigInfo(cfg)
			if info and type(info.treeIDs) == "table" then
				local sum, any = 0, false
				for _, tree in ipairs(info.treeIDs) do
					for _, cur in ipairs(C_Traits.GetTreeCurrencyInfo(cfg, tree, false) or {}) do
						local q = Num(cur.quantity)
						if q then sum, any = sum + q, true end
					end
				end
				if any then return sum end
			end
		end
		if UnitCharacterPoints then return (UnitCharacterPoints("player")) end
	end)
	n = ok and Num(n) or nil
	return n and n >= 0 and n or nil
end

local function LevelUp(_, level)
	leveledAt = GetTime()
	level = Num(level)
	C_Timer.After(0.5, function()                -- talent points come a moment later
		if not G.active.growth then return end
		XPBase()
		level = level or levelLast
		if not level then return end
		G.Moment("level", { level = level, talentPoints = UnspentPoints() }, { key = level, every = 5 })
	end)
end

------------------------------------------------------------------------------------------------------------------------
-- talent: each talent's rank before and after; the one that went up was learned

local function SpellName(id)
	id = Num(id)
	if not id then return nil end
	local name = C_Spell and Kit:Clean(Read(C_Spell.GetSpellName, id))
	if not name and C_Spell and C_Spell.GetSpellInfo then
		local ok, info = pcall(C_Spell.GetSpellInfo, id)
		name = ok and type(info) == "table" and Kit:Clean(info.name) or nil
	end
	if not name and GetSpellInfo then name = Kit:Clean(Read(GetSpellInfo, id)) end
	return name
end

-- { [key] = rank }, and key -> a function that names the talent
local function TalentRanks()
	local ranks, names = {}, {}
	pcall(function()                              -- the Trait trees
		local cfg = C_ClassTalents.GetActiveConfigID()
		local info = cfg and C_Traits.GetConfigInfo(cfg)
		for _, tree in ipairs(info and info.treeIDs or {}) do
			for _, node in ipairs(C_Traits.GetTreeNodes(tree) or {}) do
				local n = C_Traits.GetNodeInfo(cfg, node)
				local r = n and Num(n.ranksPurchased or n.currentRank)
				if r then
					ranks["n" .. node] = r
					names["n" .. node] = function()
						local entry = n.activeEntry and C_Traits.GetEntryInfo(cfg, n.activeEntry.entryID)
						local def = entry and entry.definitionID and C_Traits.GetDefinitionInfo(entry.definitionID)
						return def and (Kit:Clean(def.overrideName) or SpellName(def.spellID))
					end
				end
			end
		end
	end)
	local tabs, count, info = GetNumTalentTabs, GetNumTalents, GetTalentInfo   -- the classic talent page
	if next(ranks) == nil and tabs and count and info then
		pcall(function()
			for tab = 1, tabs() do
				for i = 1, count(tab) do
					local name, _, _, _, rank = info(tab, i)
					rank = Num(rank)
					if rank then
						local key = "t" .. tab .. ":" .. i
						ranks[key] = rank
						names[key] = function() return Kit:Clean(name) end
					end
				end
			end
		end)
	end
	return ranks, names
end

local talentRanks, talentUnspent = nil, nil
local talentPending, talentSpent, talentHint, loadedAt = false, false, false, GetTime()

local function TalentBase()
	talentRanks, talentUnspent = TalentRanks(), UnspentPoints()
	talentPending, talentSpent, talentHint = false, false, false
end

local function TalentCheck()
	if InCombat() then return end                 -- compared out of combat
	talentPending = false
	local beforeRanks, beforeUnspent = talentRanks, talentUnspent
	local ranks, names = TalentRanks()
	local unspent = UnspentPoints()
	local spent, hint = talentSpent, talentHint
	talentRanks, talentUnspent, talentSpent, talentHint = ranks, unspent, false, false
	local name
	if beforeRanks then
		for key, r in pairs(ranks) do
			if r > (beforeRanks[key] or 0) then
				spent = true
				local ok, n = pcall(names[key])
				name = ok and n or nil
				break
			end
		end
	end
	if beforeUnspent and unspent and unspent < beforeUnspent then spent = true end
	-- nothing readable at all: trust the event itself (not in the first seconds in the world)
	if not spent and hint and next(ranks) == nil and not unspent and GetTime() - loadedAt > 10 then spent = true end
	if spent then G.Moment("talent", { name = name, points = unspent }, { every = 30 }) end
end

local function TalentChanged(event, delta)
	if event == "CHARACTER_POINTS_CHANGED" and Num(delta) and delta < 0 then talentSpent = true end
	if event == "TRAIT_CONFIG_UPDATED" then talentHint = true end
	if talentPending then return end
	talentPending = true
	C_Timer.After(0.5, function()
		if talentPending and G.active.growth then TalentCheck() end
	end)
end

------------------------------------------------------------------------------------------------------------------------
-- spell.new

local function SpellLearned(_, id)
	id = Num(id)
	local name = SpellName(id)
	if name then G.Moment("spell.new", { spell = name, id = id }, { key = id, every = 5 }) end
end

G.Topic("growth", {
	events = {
		PLAYER_XP_UPDATE = XPUpdate,
		PLAYER_LEVEL_UP = LevelUp,
		TRAIT_CONFIG_UPDATED = TalentChanged,
		CHARACTER_POINTS_CHANGED = TalentChanged,
		PLAYER_TALENT_UPDATE = TalentChanged,
		LEARNED_SPELL_IN_SKILL_LINE = SpellLearned,
		LEARNED_SPELL_IN_TAB = SpellLearned,
		QUEST_TURNED_IN = function() turnedInAt = GetTime() end,
		PLAYER_REGEN_ENABLED = function()
			leftCombatAt = GetTime()
			if talentPending then TalentCheck() end
		end,
		PLAYER_ENTERING_WORLD = function()
			loadedAt = GetTime()
			if not xpPending then XPBase() end
			TalentBase()
		end,
	},
	on = function()
		xpPending = false
		XPBase()
		TalentBase()
	end,
})
