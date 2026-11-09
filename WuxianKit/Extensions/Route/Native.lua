-- 任务指引 · Native: the provider "game" (游戏自带), the game's own quest tracking. The quest is the super-tracked one
-- (C_SuperTrack.GetSuperTrackedQuestID), else the first on the watch list; its goals are its objectives
-- (C_QuestLog.GetQuestObjectives: monster -> kill, item -> collect, else other; target taken from the objective's text), or, once they are all done, one turnin
-- goal (a new step: key game|<id>|turnin); the next waypoint (C_QuestLog.GetNextWaypoint) is the place of its first goal
-- not done. Each read leaves out what the client does not give. Its events are registered only while it is the provider
-- read (Start .. Stop).
local addonName, ns = ...
local Kit = WuxianKit
local R = ns.route
local L, Read, Num = R.Words, R.Read, R.Num

local TYPES = { monster = "kill", item = "collect" }
local EVENTS = { "QUEST_LOG_UPDATE", "SUPER_TRACKING_CHANGED", "QUEST_ACCEPTED", "QUEST_TURNED_IN",
	"QUEST_WATCH_LIST_CHANGED" }

local function Id(v)
	v = Num(v)
	return v and v > 0 and v or nil
end

local function InLog(id)
	if not (C_QuestLog and C_QuestLog.GetLogIndexForQuestID) then return true end
	return Read(C_QuestLog.GetLogIndexForQuestID, id) ~= nil
end

-- the quest followed now: super-tracked, else the first watched
local function Tracked()
	local id = C_SuperTrack and Id(Read(C_SuperTrack.GetSuperTrackedQuestID))
	if id and InLog(id) then return id end
	local n = C_QuestLog and Num(Read(C_QuestLog.GetNumQuestWatches)) or 0
	for i = 1, n do
		id = Id(Read(C_QuestLog.GetQuestIDForQuestWatchIndex, i))
		if id then return id end
	end
end

local function Waypoint(id)
	if not (C_QuestLog and type(C_QuestLog.GetNextWaypoint) == "function") then return nil end
	local ok, map, x, y = pcall(C_QuestLog.GetNextWaypoint, id)
	map, x, y = ok and Id(map), Num(x), Num(y)
	if not map then return nil end
	local place = { map = map, zone = R.MapName(map) }
	if x and y then place.x, place.y = x * 100, y * 100 end
	return place
end

-- the monster's or item's name in an objective's text ("0/12 消灭加拉克斥候", "钢齿土狼的肋骨：0/1", "Kobold slain: 3/10"):
-- the count, the colon and a kill verb taken off; nil when nothing is left. The client gives no name of its own.
local KILL_HEAD = { "消灭", "杀死", "击杀", "击败", "Slay ", "Kill ", "Defeat " }
local KILL_TAIL = { "被杀", "已杀死", "已消灭", " slain", " killed", " defeated" }
local function Target(text, op)
	if type(text) ~= "string" then return nil end
	local t = text:gsub("%d+%s*/%s*%d+", ""):gsub(":", " "):gsub("\239\188\154", " ")   -- the full-width colon
	t = t:gsub("^%s+", ""):gsub("%s+$", "")
	if op == "kill" then
		for _, w in ipairs(KILL_HEAD) do
			if t:sub(1, #w) == w then t = t:sub(#w + 1) break end
		end
		for _, w in ipairs(KILL_TAIL) do
			if #t > #w and t:sub(-#w) == w then t = t:sub(1, -#w - 1) break end
		end
		t = t:gsub("^%s+", ""):gsub("%s+$", "")
	end
	return t ~= "" and t or nil
end

local function Current()
	local id = C_QuestLog and Tracked()
	if not id then return nil end
	local quest = { id = id, name = Kit:Clean(Read(C_QuestLog.GetTitleForQuestID, id)) }
	local goals, all = {}, true
	local list = Read(C_QuestLog.GetQuestObjectives, id)
	for j, o in ipairs(type(list) == "table" and list or {}) do
		if type(o) == "table" then
			local done = Kit:Value(o.finished) and true or false
			if not done then all = false end
			local op, text = TYPES[Kit:Value(o.type)] or "other", Kit:Clean(o.text)
			goals[#goals + 1] = { op = op, target = op ~= "other" and Target(text, op) or nil, quest = quest,
				objective = j, done = done, text = text }
		end
	end
	local ready = (#goals > 0 and all) or Read(C_QuestLog.IsComplete, id) and true or false
	local key = "game|" .. id
	if ready or #goals == 0 then
		goals = { { op = ready and "turnin" or "other", quest = quest } }
		if ready then key = key .. "|turnin" end
	end
	local place = Waypoint(id)
	if place then
		for _, g in ipairs(goals) do
			if not g.done then
				g.place = place
				break
			end
		end
	end
	return { key = key, goals = goals }
end

local frame = CreateFrame("Frame")
local told
R.native = frame

frame:SetScript("OnEvent", function()
	if told then told() end
end)

Kit.Route:Provide("game", {
	title = L"GAME",
	Active = function() return C_QuestLog ~= nil end,
	Current = Current,
	Start = function(changed)
		told = changed
		for _, e in ipairs(EVENTS) do pcall(frame.RegisterEvent, frame, e) end
	end,
	Stop = function()
		told = nil
		frame:UnregisterAllEvents()
	end,
})
