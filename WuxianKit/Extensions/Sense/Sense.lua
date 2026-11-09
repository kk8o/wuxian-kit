-- 角色信息 (Character info): what the game shows of the player, read at once: sense.character, sense.position, sense.bags,
-- sense.quests, sense.professions, sense.reputation, sense.currency, sense.group, sense.guild; and the facet group that
-- apps see (size, kind, instance). Nothing here reads what
-- the client keeps secret on purpose (health and power are secret to addons on this client); a value that comes back
-- secret (in combat, an encounter, a PvP match) is left out. sense.guild never reads public or officer notes.
local Kit = WuxianKit

local L = Kit:Words {
	zhCN = { TITLE = "角色信息", CHARACTER = "角色", POSITION = "位置", BAGS = "背包", QUESTS = "任务日志",
		PROFESSIONS = "专业技能", REPUTATION = "声望", CURRENCY = "货币", GROUP = "队伍", GUILD = "公会" },
	enUS = { TITLE = "Character info", CHARACTER = "Character", POSITION = "Location", BAGS = "Bags", QUESTS = "Quest log",
		PROFESSIONS = "Professions", REPUTATION = "Reputation", CURRENCY = "Currencies", GROUP = "Group",
		GUILD = "Guild" },
}

local sense = Kit:Extension("sense", { title = L"TITLE", version = Kit.VERSION, docs = "Extensions/Sense" })

-- a value, or nil when the client keeps it secret
local function V(v)
	return Kit:Value(v)
end

-- a player's name as other players address them, what a whisper (chat.send) takes: whole where this client gives a
-- name two parts ("Name Surname"), with the realm of a player from another one ("Name-Realm")
local function FullName(unit)
	if GetUnitName then return V(GetUnitName(unit, true)) end
	return V((UnitName(unit)))
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
	doc = "the player's character: name (whole, as other players address it: a whisper's target), realm, level, class and "
		.. "classToken, race, faction, xp and xpMax, rested (xp), "
		.. "money (copper), itemLevel, spec {id, name}, guild {name, rank}, resting",
	run = function()
		local className, classToken = UnitClass("player")
		local out = { name = FullName("player"), realm = V(GetRealmName()), level = V(UnitLevel("player")),
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
	doc = "the group: kind (none, party, raid) and members {name (whole, as for a whisper), class, level, role, online, "
		.. "leader}",
	run = function()
		if not IsInGroup() then return { kind = "none", members = {} } end
		local raid, members = IsInRaid(), {}
		for i = 1, GetNumGroupMembers() do
			local unit = raid and ("raid" .. i) or (i == 1 and "player" or ("party" .. (i - 1)))
			local name = FullName(unit)
			if name then
				local _, class = UnitClass(unit)
				members[#members + 1] = { name = name, class = V(class), level = V(UnitLevel(unit)),
					role = V(UnitGroupRolesAssigned(unit)), online = V(UnitIsConnected(unit)),
					leader = V(UnitIsGroupLeader(unit)) or nil }
			end
		end
		return { kind = raid and "raid" or "party", members = members }
	end })

-- the group now, as a facet apps see (see = { "group" }): small, read at each wake
sense:Facet("group", { title = L"GROUP",
	doc = "the player's group now: size (1 alone), kind (solo, party, raid), instance (its name, inside one), instanceType "
		.. "(party, raid, pvp, arena, scenario, inside one)",
	fields = { size = "number", kind = "string", instance = "string?", instanceType = "string?" },
	read = function()
		local grouped = IsInGroup and V(IsInGroup())
		local size = grouped and V(GetNumGroupMembers()) or nil
		local out = { kind = not grouped and "solo" or (V(IsInRaid()) and "raid" or "party"),
			size = type(size) == "number" and size > 0 and size or 1 }
		local inside, kind = IsInInstance()
		if V(inside) then
			local name = V((GetInstanceInfo()))
			out.instance = type(name) == "string" and name ~= "" and name or nil
			kind = V(kind)
			out.instanceType = type(kind) == "string" and kind ~= "none" and kind or nil
		end
		return out
	end })

-- the guild's roster as the guild window has it (asking the server for a fresh one: it answers a moment later)
local function GuildRoster()
	if C_GuildInfo and C_GuildInfo.GuildRoster then pcall(C_GuildInfo.GuildRoster) end
end

sense:See("guild", { title = L"GUILD", args = { members = "boolean?", limit = "number?" },
	doc = "the player's guild: name, rank (the player's), motd, total and online members, classes {[classFile] = n}, "
		.. "levels {avg, median, atMax} of all members; with members (default true) the online members {name (whole, as "
		.. "for a whisper), level, class (classFile), zone, rank, online}, highest level first, at most `limit` (100, up "
		.. "to 300). Not in a guild: {guild = false}. Notes are never read",
	run = function(_, a)
		local name, rank = GetGuildInfo("player")
		name, rank = V(name), V(rank)
		if type(name) ~= "string" or name == "" then return { guild = false } end
		GuildRoster()
		local motd = GetGuildRosterMOTD and V(GetGuildRosterMOTD()) or nil
		local out = { name = name, rank = rank, motd = motd ~= "" and motd or nil, classes = {} }
		local total = GetNumGuildMembers and V((GetNumGuildMembers())) or 0
		total = type(total) == "number" and total or 0
		local max = GetMaxLevelForPlayerExpansion and V(GetMaxLevelForPlayerExpansion()) or nil
		max = type(max) == "number" and max > 0 and max or 60
		local online, levels, sum, atMax = {}, {}, 0, 0
		for i = 1, total do
			-- name, rankName, rankIndex, level, classDisplayName, zone, publicNote, officerNote, isOnline, status,
			-- classFile: the notes are skipped
			local who, rankName, _, level, _, zone, _, _, isOnline, _, classFile = GetGuildRosterInfo(i)
			who, isOnline, level, classFile = V(who), V(isOnline), V(level), V(classFile)
			if type(who) == "string" then
				if type(level) == "number" and level > 0 then
					levels[#levels + 1], sum = level, sum + level
					if level >= max then atMax = atMax + 1 end
				end
				if type(classFile) == "string" then out.classes[classFile] = (out.classes[classFile] or 0) + 1 end
			end
			if type(who) == "string" and isOnline then
				zone = V(zone)
				online[#online + 1] = { name = Ambiguate(who, "none"), level = type(level) == "number" and level or nil,
					class = classFile, zone = zone ~= "" and zone or nil, rank = V(rankName), online = true }
			end
		end
		out.total, out.online = total, #online
		table.sort(levels)
		local n = #levels
		out.levels = { atMax = atMax }
		if n > 0 then
			out.levels.avg = Round(sum / n, 1)
			out.levels.median = n % 2 == 1 and levels[(n + 1) / 2] or (levels[n / 2] + levels[n / 2 + 1]) / 2
		end
		if a.members ~= false then
			table.sort(online, function(x, y)
				if (x.level or 0) ~= (y.level or 0) then return (x.level or 0) > (y.level or 0) end
				return x.name < y.name
			end)
			local members = {}
			for i = 1, math.min(Count(a.limit, 100, 300), #online) do members[i] = online[i] end
			out.members = members
		end
		return out
	end })
