-- 游戏动态 · Guide: the topic guide (guide.step, guide.arrive): RestedXP's steps. Ported from 无限陪玩 (the companion's
-- RXP.lua). Nothing at all without RXPGuides: its AceEvent messages (RXP_STEP_ACTIVATED, RXP_OBJECTIVE_COMPLETE,
-- RXP_TARGET_LIST_UPDATE, RXP_GUIDE_LOADED) are heard through LibStub("AceEvent-3.0").RegisterMessage on a table of our
-- own, from when the topic turns on (RestedXP loaded) until it turns off. As measured (RestedXP v4.11.29, Chinese):
-- a step's elements are step.elements; several steps go active at once, the current one is RXPCData.currentStep; the
-- step is read once the activations have been quiet for 0.3 s; RXP_TARGET_LIST_UPDATE(unitscan, mobs, targets) are three
-- lists of names. Game and guide text is data.
local addonName, ns = ...
local Kit = WuxianKit
local G = ns.game

local MESSAGES = { "RXP_STEP_ACTIVATED", "RXP_OBJECTIVE_COMPLETE", "RXP_TARGET_LIST_UPDATE", "RXP_GUIDE_LOADED" }

local listener = {}                               -- the object RegisterMessage keeps: only a table of ours
local hooked                                      -- the AceEvent we registered with, while we are
local guideNow                                    -- the guide of the last RXP_STEP_ACTIVATED
local lastKey                                     -- "guide|index" last told
local targets = {}                                -- the names of the last RXP_TARGET_LIST_UPDATE (at most 5, none twice)
local quietGen = 0                                -- a new activation within 0.3 s starts the wait again

local function Loaded()
	local f = C_AddOns and C_AddOns.IsAddOnLoaded or IsAddOnLoaded
	if type(f) ~= "function" then return false end
	local ok, loaded = pcall(f, "RXPGuides")
	return ok and loaded and true or false
end

local function Elements(step)
	if type(step) ~= "table" then return {} end
	return type(step.elements) == "table" and step.elements or step
end

local function CurrentIndex()
	return type(RXPCData) == "table" and tonumber(RXPCData.currentStep) or nil
end

local function GuideName(guide)
	return type(guide) == "table" and Kit:Clean(guide.name) or nil
end

local function Round1(v)
	return math.floor(v * 10 + 0.5) / 10
end

local function Goto(step)
	for _, e in ipairs(Elements(step)) do
		if type(e) == "table" and e.tag == "goto" and type(e.x) == "number" and type(e.y) == "number" then
			local out = { x = Round1(e.x), y = Round1(e.y) }
			local map = tonumber(e.zone)
			if map then
				out.map = map
				local ok, info = pcall(C_Map.GetMapInfo, map)
				out.zone = ok and type(info) == "table" and Kit:Clean(info.name) or nil
			else
				out.zone = Kit:Clean(e.zone)
			end
			return out
		end
	end
end

local function Lines(step)
	local out = {}
	for _, e in ipairs(Elements(step)) do
		local text = type(e) == "table" and Kit:Clean(e.text)
		if text then
			out[#out + 1] = text
			if #out >= 6 then break end
		end
	end
	return out
end

local function StepReport()
	local guide, index = guideNow, CurrentIndex()
	if not (G.active.guide and type(guide) == "table" and index) then return end
	local step = type(guide.steps) == "table" and guide.steps[index]
	if type(step) ~= "table" then return end
	local name = GuideName(guide)
	local key = tostring(name) .. "|" .. index
	if key == lastKey then return end             -- the same step: nothing
	local list
	if #targets > 0 then
		list = {}
		for i, v in ipairs(targets) do list[i] = v end
	end
	if G.Moment("guide.step", { guide = name, index = index, lines = Lines(step), ["goto"] = Goto(step),
		targets = list }, { every = 1 }) then lastKey = key end
end

local function OnStepActivated(_, _, guide)
	if not G.active.guide then return end
	if type(guide) == "table" then guideNow = guide end
	quietGen = quietGen + 1
	local gen = quietGen
	C_Timer.After(0.3, function()                -- several steps at once: the current one once it is quiet
		if gen == quietGen then ns.Safe(StepReport) end
	end)
end

local function OnObjectiveComplete(_, element, guide)
	if not G.active.guide or type(element) ~= "table" or element.tag ~= "goto" then return end
	guide = type(guide) == "table" and guide or guideNow
	local index = CurrentIndex()
	local step = index and type(guide) == "table" and type(guide.steps) == "table" and guide.steps[index]
	local own = element.step
	if not (step and own and (own == step or (type(own) == "table" and tonumber(own.index) == index))) then return end
	G.Moment("guide.arrive", { guide = GuideName(guide), index = index }, { key = index, every = 5 })
end

local function OnTargets(_, ...)
	if not G.active.guide then return end
	local out, seen = {}, {}
	for i = 1, 3 do
		local list = select(i, ...)
		for _, v in ipairs(type(list) == "table" and list or {}) do
			local name = Kit:Clean(v)
			if name and not seen[name] and #out < 5 then
				seen[name] = true
				out[#out + 1] = name
			end
		end
	end
	targets = out
end

local function OnGuideLoaded(_, guide)
	if not G.active.guide then return end
	if type(guide) == "table" then guideNow = guide end
	lastKey = nil
end

local HANDLERS = { RXP_STEP_ACTIVATED = OnStepActivated, RXP_OBJECTIVE_COMPLETE = OnObjectiveComplete,
	RXP_TARGET_LIST_UPDATE = OnTargets, RXP_GUIDE_LOADED = OnGuideLoaded }

local function Hook()
	if hooked or not G.active.guide or not Loaded() then return end
	local lib = LibStub and select(2, pcall(LibStub, "AceEvent-3.0", true))
	if type(lib) ~= "table" or type(lib.RegisterMessage) ~= "function" then return end
	hooked = lib
	for _, msg in ipairs(MESSAGES) do
		local fn = HANDLERS[msg]
		pcall(lib.RegisterMessage, listener, msg, function(...) ns.Safe(fn, ...) end)
	end
end

-- AceEvent can let go of us; one that cannot (UnregisterMessage missing) keeps calling and is ignored while off
local function Unhook()
	local lib = hooked
	if not lib or type(lib.UnregisterMessage) ~= "function" then return end
	for _, msg in ipairs(MESSAGES) do pcall(lib.UnregisterMessage, listener, msg) end
	hooked = nil
end

G.Topic("guide", {
	events = {
		ADDON_LOADED = function(_, name)          -- RestedXP loaded after the topic turned on
			if Kit:Value(name) == "RXPGuides" then Hook() end
		end,
		PLAYER_ENTERING_WORLD = Hook,
	},
	on = function()
		lastKey, targets = nil, {}
		Hook()
	end,
	off = function()
		Unhook()
		quietGen = quietGen + 1                   -- a wait going on tells nothing
	end,
})
