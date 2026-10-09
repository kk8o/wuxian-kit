-- 感知 (Sense): what the game shows of the player, read at once: sense.character, sense.position, sense.bags,
-- sense.quests, sense.professions, sense.reputation, sense.currency, sense.group. Nothing here reads what the client
-- keeps secret on purpose (health and power are secret to addons on this client); a value that comes back secret (in
-- combat, an encounter, a PvP match) is left out.
local Kit = WuxianKit
local issecret = issecretvalue or function() return false end

local L = Kit:Words {
	zhCN = { TITLE = "角色信息", CHARACTER = "角色", POSITION = "位置", BAGS = "背包", QUESTS = "任务日志",
		PROFESSIONS = "专业技能", REPUTATION = "声望", CURRENCY = "货币", GROUP = "队伍" },
	enUS = { TITLE = "Character info", CHARACTER = "Character", POSITION = "Location", BAGS = "Bags", QUESTS = "Quest log",
		PROFESSIONS = "Professions", REPUTATION = "Reputation", CURRENCY = "Currencies", GROUP = "Group" },
}

local sense = Kit:Extension("sense", { title = L"TITLE", version = Kit.VERSION, docs = "Extensions/Sense" })

-- a value, or nil when the client keeps it secret
local function V(v)
	if issecret(v) then return nil end
	return v
end

local function Round(v, places)
	v = V(v)
	if type(v) ~= "number" then return nil end
	local m = 10 ^ (places or 0)
	return math.floor(v * m + 0.5) / m
end

local function Count(limit, default, most)
	return math.max(1, math.min(tonumber(limit) or default, most))
end

sense:See("character", { title = L"CHARACTER",
	doc = "the player's character: name, realm, level, class and classToken, race, faction, xp and xpMax, rested (xp), "
		.. "money (copper), itemLevel, spec {id, name}, guild {name, rank}, resting",
	run = function()
		local className, classToken = UnitClass("player")
		local out = { name = V(UnitName("player")), realm = V(GetRealmName()), level = V(UnitLevel("player")),
			class = V(className), classToken = V(classToken), race = V((UnitRace("player"))),
			faction = V((UnitFactionGroup("player"))), xp = V(UnitXP("player")), xpMax = V(UnitXPMax("player")),
			rested = GetXPExhaustion and V(GetXPExhaustion()) or nil, money = V(GetMoney()), resting = V(IsResting()) or nil,
			itemLevel = GetAverageItemLevel and Round((GetAverageItemLevel()), 1) or nil }
		local ok, id, name = pcall(function()
			local index = C_SpecializationInfo.GetSpecialization()
			if not V(index) then return nil end
			return C_SpecializationInfo.GetSpecializationInfo(index)
		end)
		if ok and V(id) then out.spec = { id = id, name = V(name) } end
		local guild, rank = GetGuildInfo("player")
		if V(guild) then out.guild = { name = guild, rank = V(rank) } end
		return out
	end })

sense:See("position", { title = L"POSITION",
	doc = "where the player is: map {id, name}, zone, subzone, x and y on that map (0-100), instance {name, type, "
		.. "difficulty} when inside one",
	run = function()
		local out = { zone = V(GetZoneText()), subzone = V(GetSubZoneText()) }
		if out.subzone == "" then out.subzone = nil end
		local map = V(C_Map.GetBestMapForUnit("player"))
		if map then
			local info = C_Map.GetMapInfo(map)
			out.map = { id = map, name = info and V(info.name) or nil }
			local pos = C_Map.GetPlayerMapPosition(map, "player")
			if pos then
				local x, y = pos:GetXY()
				out.x, out.y = Round(x and V(x) and x * 100, 1), Round(y and V(y) and y * 100, 1)
			end
		end
		local inside, kind = IsInInstance()
		if V(inside) then
			local name, _, _, difficulty = GetInstanceInfo()
			out.instance = { name = V(name), type = V(kind), difficulty = V(difficulty) }
		end
		return out
	end })

local function ItemName(link)
	return type(link) == "string" and link:match("|h%[(.-)%]|h") or nil
end

sense:See("bags", { title = L"BAGS", args = { text = "string?", limit = "number?" },
	doc = "the bags: free and total slots, and each bag's; with `text`, the stacks whose item name holds it (no case) "
		.. "{bag, slot, id, name, count, quality, link}; without, the items summed {id, name, count, quality}, most first; "
		.. "at most `limit` (50, up to 200)",
	run = function(_, a)
		local want, limit = a.text and a.text:lower(), Count(a.limit, 50, 200)
		local out = { free = 0, total = 0, bags = {}, items = {} }
		local sums, order = {}, {}
		for bag = 0, NUM_TOTAL_EQUIPPED_BAG_SLOTS or NUM_BAG_SLOTS or 4 do
			local size = C_Container.GetContainerNumSlots(bag) or 0
			if size > 0 then
				local free = C_Container.GetContainerNumFreeSlots(bag) or 0
				out.free, out.total = out.free + free, out.total + size
				out.bags[#out.bags + 1] = { bag = bag, slots = size, free = free }
				for slot = 1, size do
					local i = C_Container.GetContainerItemInfo(bag, slot)
					if i and i.itemID then
						local name = ItemName(i.hyperlink)
						if want then
							if name and name:lower():find(want, 1, true) and #out.items < limit then
								out.items[#out.items + 1] = { bag = bag, slot = slot, id = i.itemID, name = name,
									count = i.stackCount, quality = i.quality, link = i.hyperlink }
							end
						else
							local s = sums[i.itemID]
							if not s then
								s = { id = i.itemID, name = name, count = 0, quality = i.quality }
								sums[i.itemID], order[#order + 1] = s, s
							end
							s.count = s.count + (i.stackCount or 1)
						end
					end
				end
			end
		end
		if not want then
			table.sort(order, function(x, y) return x.count > y.count end)
			for n = 1, math.min(limit, #order) do out.items[n] = order[n] end
		end
		return out
	end })

sense:See("quests", { title = L"QUESTS", args = { limit = "number?" },
	doc = "the quest log (headers left out): {id, title, level, complete, objectives [{text, done, have, need}]}; at "
		.. "most `limit` (25, up to 50)",
	run = function(_, a)
		local out, limit = {}, Count(a.limit, 25, 50)
		for i = 1, C_QuestLog.GetNumQuestLogEntries() do
			local q = C_QuestLog.GetInfo(i)
			if q and not q.isHeader and not q.isHidden and q.questID then
				local objectives = {}
				for _, o in ipairs(C_QuestLog.GetQuestObjectives(q.questID) or {}) do
					objectives[#objectives + 1] = { text = V(o.text), done = o.finished or nil, have = o.numFulfilled,
						need = o.numRequired }
				end
				out[#out + 1] = { id = q.questID, title = V(q.title), level = q.level,
					complete = C_QuestLog.IsComplete(q.questID) or nil, objectives = objectives }
				if #out >= limit then break end
			end
		end
		return out
	end })

sense:See("professions", { title = L"PROFESSIONS",
	doc = "the professions and secondary skills: {name, level, max, skillLine}",
	run = function()
		local out, list = {}, { GetProfessions() }
		for n = 1, select("#", GetProfessions()) do
			local i = list[n]
			if i then
				local name, _, level, max, _, _, skillLine = GetProfessionInfo(i)
				if name then out[#out + 1] = { name = name, level = level, max = max, skillLine = skillLine } end
			end
		end
		return out
	end })

sense:See("reputation", { title = L"REPUTATION", args = { text = "string?" },
	doc = "the reputations as the reputation window lists them (a collapsed group hides its own), those whose name holds "
		.. "`text`: {name, id, standing, value, max (within the standing), watched, atWar}",
	run = function(_, a)
		local want, out = a.text and a.text:lower(), {}
		for i = 1, C_Reputation.GetNumFactions() do
			local f = C_Reputation.GetFactionDataByIndex(i)
			if f and (not f.isHeader or f.isHeaderWithRep) and (not want or (f.name or ""):lower():find(want, 1, true)) then
				local low, high = f.currentReactionThreshold or 0, f.nextReactionThreshold or 0
				out[#out + 1] = { name = f.name, id = f.factionID, standing = _G["FACTION_STANDING_LABEL" .. tostring(f.reaction)],
					value = (f.currentStanding or 0) - low, max = high > low and high - low or nil,
					watched = f.isWatched or nil, atWar = f.atWarWith or nil }
			end
		end
		return out
	end })

sense:See("currency", { title = L"CURRENCY",
	doc = "the currencies as the currency window lists them: {name, count, max}",
	run = function()
		local out = {}
		for i = 1, C_CurrencyInfo.GetCurrencyListSize() do
			local c = C_CurrencyInfo.GetCurrencyListInfo(i)
			if c and not c.isHeader then
				out[#out + 1] = { name = c.name, count = c.quantity, max = (c.maxQuantity or 0) > 0 and c.maxQuantity or nil }
			end
		end
		return out
	end })

sense:See("group", { title = L"GROUP",
	doc = "the group: kind (none, party, raid) and members {name, class, level, role, online, leader}",
	run = function()
		if not IsInGroup() then return { kind = "none", members = {} } end
		local raid, members = IsInRaid(), {}
		for i = 1, GetNumGroupMembers() do
			local unit = raid and ("raid" .. i) or (i == 1 and "player" or ("party" .. (i - 1)))
			local name = V(UnitName(unit))
			if name then
				local _, class = UnitClass(unit)
				members[#members + 1] = { name = name, class = V(class), level = V(UnitLevel(unit)),
					role = V(UnitGroupRolesAssigned(unit)), online = V(UnitIsConnected(unit)),
					leader = V(UnitIsGroupLeader(unit)) or nil }
			end
		end
		return { kind = raid and "raid" or "party", members = members }
	end })
