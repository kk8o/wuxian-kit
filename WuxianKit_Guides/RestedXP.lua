-- 任务指引适配 · RestedXP: the adapter "rxp" for RXPGuides, ported from 游戏动态's old topic guide (Guide.lua, itself
-- from 无限陪玩's RXP.lua). As measured (RestedXP v4.11.29, Chinese): a step's elements are step.elements (each knows
-- its step: element.step); several steps go active at once, the current one is RXPCData.currentStep; the guide is the
-- last RXP_STEP_ACTIVATED's or RXP_GUIDE_LOADED's, else RestedXP's own (its AceAddon object's currentGuide, read only).
-- While it is the provider read (Start .. Stop) it hears RestedXP's AceEvent messages through
-- LibStub("AceEvent-3.0").RegisterMessage on a table of its own: a step activated tells the core once the activations
-- have been quiet for 0.3 s, an element of the current step completed at once (a goto: "arrive", with its place).
-- Elements become goals by their tag (RestedXP's functions.lua):
--   goto, groundgoto, flygoto -> go (one: the first not reached; place { map = element.zone, x, y })
--   zone -> go (place { map }); accept, turnin -> accept, turnin (quest { id = questId, name = title });
--   complete -> its objective's (quest questId, objective obj): kill (the client's objective type monster, or the step
--   names mobs), collect (item), else other; collect -> collect (target the item, need qty, have the bags' count);
--   home, fp, vendor, trainer, train, stable, gossip and skipgossip ... -> talk; use, usespell, cast, hs -> use;
--   mob, unitscan, target: the names of the step's kill and talk targets (a kill goal of their own when no complete is
--   one, a talk goal when the step has no other); the conditions (isOnQuest, zoneskip, itemcount ...) nothing; any
--   other element with text of its own -> other. Every line of text is in the step's text. Guide text is data.
local addonName, ns = ...
local Kit = WuxianKit
if not ns.Adapter then return end

local MESSAGES = { "RXP_STEP_ACTIVATED", "RXP_STEP_COMPLETE", "RXP_OBJECTIVE_COMPLETE", "RXP_TARGET_LIST_UPDATE",
	"RXP_GUIDE_LOADED" }

local GO = { ["goto"] = true, groundgoto = true, flygoto = true }
local TALK = { home = true, fp = true, vendor = true, trainer = true, train = true, stable = true, gossip = true,
	skipgossip = true, skipgossipid = true, gossipoption = true }
local USE = { use = true, usespell = true, cast = true, hs = true }
local NAMES = { mob = "mobs", unitscan = "mobs", target = "npcs" }
local CONDITIONS = { isOnQuest = true, isNotOnQuest = true, isQuestTurnedIn = true, isQuestComplete = true,
	isQuestNotComplete = true, isQuestAvailable = true, zoneskip = true, subzoneskip = true, subzone = true,
	itemcount = true, itemStat = true, dungeon = true, maxlevel = true, group = true, solo = true, skill = true,
	money = true, cooldown = true, timer = true, disablecheckbox = true, link = true, line = true, loop = true,
	waypoint = true, pin = true, wpradius = true, bindlocation = true, questcount = true, spellmissing = true,
	istrained = true, aura = true, label = true, clicknext = true }
local OBJECTIVE_OPS = { monster = "kill", item = "collect" }

local listener = {}                               -- the object RegisterMessage keeps: only a table of ours
local hooked                                      -- the AceEvent we registered with, while we are
local guideNow                                    -- the guide of the last RXP_STEP_ACTIVATED / RXP_GUIDE_LOADED
local heard = { mobs = {}, npcs = {} }            -- the last RXP_TARGET_LIST_UPDATE's names
local quietGen = 0                                -- a new activation within 0.3 s starts the wait again
local told                                        -- the core's changed, while it reads us

-- guide text as one plain line: RestedXP's colour placeholders (|cRXP_FRIENDLY_, put in when a step is shown) out too
local function Text(v)
	v = Kit:Value(v)
	if type(v) == "string" then v = v:gsub("|cRXP_%u+_", "") end
	return Kit:Clean(v)
end

local function Read(fn, ...)
	if type(fn) ~= "function" then return nil end
	local ok, v = pcall(fn, ...)
	if ok then return Kit:Value(v) end
end

-- RestedXP's AceAddon object (read only), or nil
local function Addon()
	local ok, ace = pcall(function() return LibStub and LibStub("AceAddon-3.0", true) end)
	if not ok or type(ace) ~= "table" or type(ace.GetAddon) ~= "function" then return nil end
	local got, rxp = pcall(ace.GetAddon, ace, "RXPGuides", true)
	return got and type(rxp) == "table" and rxp or nil
end

local function Guide()
	if type(guideNow) == "table" then return guideNow end
	local rxp = Addon()
	return rxp and type(rxp.currentGuide) == "table" and rxp.currentGuide or nil
end

local function Index()
	return type(RXPCData) == "table" and tonumber(RXPCData.currentStep) or nil
end

-- the guide, the current step's index and the step, or nil
local function Now()
	local guide, index = Guide(), Index()
	local step = guide and index and type(guide.steps) == "table" and guide.steps[index]
	if type(step) ~= "table" then return nil end
	return guide, index, step
end

local function Elements(step)
	return type(step.elements) == "table" and step.elements or step
end

-- the names of a list (one not resolved yet is an NPC id: left out), none twice, at most 5
local function Names(list, out)
	for _, v in ipairs(type(list) == "table" and list or {}) do
		local name = Text(v)
		if name and not name:match("^%d+$") and #out < 5 then
			local seen = false
			for _, x in ipairs(out) do seen = seen or x == name end
			if not seen then out[#out + 1] = name end
		end
	end
	return out
end

local function Place(e)
	if type(e.x) ~= "number" or type(e.y) ~= "number" then return nil end
	local map = tonumber(e.zone)
	return { map = map, zone = not map and Kit:Clean(e.zone) or nil, x = e.x, y = e.y }
end

local function Quest(e)
	local id = tonumber(e.questId)
	if not id then return nil end
	local name = Text(e.title)
	return { id = math.abs(id), name = name }
end

local function ItemName(id)
	id = tonumber(id)
	if not id then return nil end
	local name = C_Item and Read(C_Item.GetItemNameByID, id)
	if not name and C_Item then name = Read(C_Item.GetItemInfo, id) end
	if not name then name = Read(GetItemInfo, id) end
	return Kit:Clean(name)
end

local function ItemCount(id)
	id = tonumber(id)
	if not id then return nil end
	local n = C_Item and Read(C_Item.GetItemCount, id)
	if n == nil then n = Read(GetItemCount, id) end
	return type(n) == "number" and n or nil
end

-- what a quest objective asks, by the client's type
local function ObjectiveOp(quest, index)
	local list = quest and index and C_QuestLog and Read(C_QuestLog.GetQuestObjectives, quest.id)
	local o = type(list) == "table" and list[index]
	return type(o) == "table" and OBJECTIVE_OPS[Kit:Value(o.type)] or nil
end

local function Lines(step)
	local out = {}
	for _, e in ipairs(Elements(step)) do
		local text = type(e) == "table" and Text(e.text)
		if text then
			out[#out + 1] = text
			if #out >= 6 then break end
		end
	end
	return out
end

local function Done(e)
	return e.completed and true or false
end

local function Goals(step)
	local els = Elements(step)
	local mobs, npcs, mobText = {}, {}, nil
	for _, e in ipairs(els) do
		local kind = type(e) == "table" and NAMES[e.tag]
		if kind == "mobs" then
			Names(e.mobs or e.unitscan or e.unitlist, mobs)
			mobText = mobText or Text(e.text)
		elseif kind == "npcs" then
			Names(e.targets or e.unitlist, npcs)
		end
	end
	if #mobs == 0 then Names(heard.mobs, mobs) end
	if #npcs == 0 then Names(heard.npcs, npcs) end
	local goals, kill, talk = {}, false, false
	local go, goAt, lastGoto
	for _, e in ipairs(els) do
		local tag = type(e) == "table" and e.tag
		local g
		if not tag then
			if type(e) == "table" and not e.textOnly and Text(e.text) then
				g = { op = "other", done = Done(e), text = Text(e.text) }
			end
		elseif GO[tag] then
			local place = Place(e)
			if place and not go then
				goAt = goAt or #goals + 1
				lastGoto = place
				if not e.completed then go = { op = "go", place = place, done = false } end
			end
		elseif tag == "zone" then
			g = { op = "go", place = { map = tonumber(e.map) }, done = Done(e), text = Text(e.text) }
		elseif tag == "accept" or tag == "turnin" then
			g = { op = tag, quest = Quest(e), target = npcs[1], done = Done(e), text = Text(e.text) }
			talk = true
		elseif tag == "complete" then
			local quest = Quest(e)
			local op = ObjectiveOp(quest, tonumber(e.obj)) or (#mobs > 0 and "kill") or "other"
			g = { op = op, quest = quest, objective = tonumber(e.obj), target = op == "kill" and mobs[1] or nil,
				need = tonumber(e.objMax), done = Done(e), text = Text(e.text) }
			kill = kill or op == "kill"
		elseif tag == "collect" then
			local need = tonumber(e.qty)
			g = { op = "collect", target = ItemName(e.id) or e.itemName, need = need, have = ItemCount(e.id),
				quest = Quest(e), text = Text(e.text), done = Done(e) }
		elseif TALK[tag] then
			g = { op = "talk", target = npcs[1], done = Done(e), text = Text(e.text) }
			talk = true
		elseif USE[tag] then
			local item
			for id in pairs(type(e.activeItems) == "table" and e.activeItems or {}) do
				item = item or ItemName(id)
			end
			g = { op = "use", target = item, done = Done(e), text = Text(e.text) }
		elseif not NAMES[tag] and not CONDITIONS[tag] and not e.textOnly and Text(e.text) then
			g = { op = "other", done = Done(e), text = Text(e.text) }
		end
		if g then goals[#goals + 1] = g end
	end
	if goAt then
		go = go or { op = "go", place = lastGoto, done = true }
		table.insert(goals, goAt, go)
	end
	if not kill and #mobs > 0 then
		goals[#goals + 1] = { op = "kill", target = mobs[1], text = mobText }
	elseif not kill and not talk and #npcs > 0 then
		goals[#goals + 1] = { op = "talk", target = npcs[1] }
	end
	return goals
end

local function Current()
	local guide, index, step = Now()
	if not step then return nil end
	local name = Kit:Clean(guide.name)
	return { guide = Text(guide.displayname) or name, index = index, key = tostring(name) .. "|" .. index,
		goals = Goals(step), text = Lines(step) }
end

------------------------------------------------------------------------------------------------------------------------
-- RestedXP's messages, while the core reads us

local function Tell(why, place)
	if told then ns.Safe(told, why, place) end
end

-- the core is told once RestedXP has been quiet for 0.3 s (several steps go active at once, the target lists with them)
local function Quiet()
	quietGen = quietGen + 1
	local gen = quietGen
	C_Timer.After(0.3, function()
		if gen == quietGen then Tell() end
	end)
end

local function OnStepActivated(_, _, guide)
	if type(guide) == "table" then guideNow = guide end
	Quiet()
end

local function OnObjectiveComplete(_, element, guide)
	if type(element) ~= "table" then return end
	if type(guide) == "table" then guideNow = guide end
	local _, index, step = Now()
	local own = element.step
	if not (step and own and (own == step or (type(own) == "table" and tonumber(own.index) == index))) then return end
	if GO[element.tag] then Tell("arrive", Place(element)) else Tell() end
end

local function OnTargets(_, unitscan, mobs, targets)
	heard = { mobs = Names(mobs, Names(unitscan, {})), npcs = Names(targets, {}) }
	Quiet()
end

local function OnGuideLoaded(_, guide)
	if type(guide) == "table" then guideNow = guide end
	Tell()
end

local HANDLERS = { RXP_STEP_ACTIVATED = OnStepActivated, RXP_STEP_COMPLETE = function() Tell() end,
	RXP_OBJECTIVE_COMPLETE = OnObjectiveComplete, RXP_TARGET_LIST_UPDATE = OnTargets, RXP_GUIDE_LOADED = OnGuideLoaded }

local function Hook()
	if hooked or not ns.Loaded("RXPGuides") then return end
	local ok, lib = pcall(function() return LibStub and LibStub("AceEvent-3.0", true) end)
	if not ok or type(lib) ~= "table" or type(lib.RegisterMessage) ~= "function" then return end
	hooked = lib
	for _, msg in ipairs(MESSAGES) do
		local fn = HANDLERS[msg]
		pcall(lib.RegisterMessage, listener, msg, function(...)
			if told then ns.Safe(fn, ...) end
		end)
	end
end

-- AceEvent can let go of us; one that cannot (UnregisterMessage missing) keeps calling and is ignored while stopped
local function Unhook()
	local lib = hooked
	if not lib or type(lib.UnregisterMessage) ~= "function" then return end
	for _, msg in ipairs(MESSAGES) do pcall(lib.UnregisterMessage, listener, msg) end
	hooked = nil
end

ns.Adapter("rxp", "RXPGuides", {
	title = "RestedXP", addon = "RXPGuides",
	Active = function() return ns.Loaded("RXPGuides") and Now() ~= nil end,
	Current = Current,
	Start = function(changed)
		told = changed
		heard = { mobs = {}, npcs = {} }
		Hook()
	end,
	Stop = function()
		told = nil
		Unhook()
		guideNow = nil                            -- RestedXP's own guide is read until we hear again
		quietGen = quietGen + 1                   -- a wait going on tells nothing
	end,
})
