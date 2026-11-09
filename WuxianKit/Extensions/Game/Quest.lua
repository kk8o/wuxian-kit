-- 游戏动态 · Quest: the topic quest (quest.accept, quest.progress, quest.ready, quest.turnin). Ported from 无限陪玩 (the
-- companion's Progress.lua). The quest log is read when the topic turns on (the baseline) and after each
-- QUEST_LOG_UPDATE (once for several at the same moment); a quest new to the log, or whose objectives changed in number,
-- only goes into the baseline.
local addonName, ns = ...
local Kit = WuxianKit
local G = ns.game
local Read, Num = G.Read, G.Num

local quests = nil          -- the last read: questID -> { title, done = { objective finished }, texts, complete }

local function QuestTitle(id)
	local title = C_QuestLog and Kit:Clean(Read(C_QuestLog.GetTitleForQuestID, id))
	if title then return title end
	if quests and quests[id] then return quests[id].title end
	local n = C_QuestLog and Num(Read(C_QuestLog.GetNumQuestLogEntries)) or 0
	for i = 1, n do
		local info = Read(C_QuestLog.GetInfo, i)
		if type(info) == "table" and info.questID == id then return Kit:Clean(info.title) end
	end
end

local function QuestRead()
	local out = {}
	local n = C_QuestLog and Num(Read(C_QuestLog.GetNumQuestLogEntries)) or 0
	for i = 1, n do
		local info = Read(C_QuestLog.GetInfo, i)
		local id = type(info) == "table" and not info.isHeader and not info.isHidden and Num(info.questID)
		if id then
			local q = { title = Kit:Clean(info.title), done = {}, texts = {},
				complete = Read(C_QuestLog.IsComplete, id) and true or false }
			local objectives = Read(C_QuestLog.GetQuestObjectives, id)
			for j, o in ipairs(type(objectives) == "table" and objectives or {}) do
				q.done[j] = Kit:Value(o.finished) and true or false
				q.texts[j] = Kit:Clean(o.text)
			end
			out[id] = q
		end
	end
	return out
end

local function QuestScan()
	local now = QuestRead()
	local before = quests
	quests = now
	if not before then return end
	for id, q in pairs(now) do
		local was = before[id]
		if was and #was.done == #q.done then
			for j, done in ipairs(q.done) do
				if done and not was.done[j] then
					G.Moment("quest.progress", { quest = q.title, id = id, objective = q.texts[j] },
						{ key = id .. ":" .. j, every = 1 })
				end
			end
			if q.complete and not was.complete then
				G.Moment("quest.ready", { quest = q.title, id = id }, { key = id, every = 5 })
			end
		end
	end
end

local scanSoon = false

local function QuestSoon()
	if scanSoon then return end
	scanSoon = true
	C_Timer.After(0.2, function()                -- several updates at one moment: one read
		scanSoon = false
		if G.active.quest then QuestScan() end
	end)
end

local function QuestAccepted(id, tries)
	if not G.active.quest then return end
	local title = QuestTitle(id)
	if not title and tries < 2 then               -- the title may come a moment later
		C_Timer.After(0.5, function() QuestAccepted(id, tries + 1) end)
		return
	end
	G.Moment("quest.accept", { quest = title, id = id }, { key = id, every = 5 })
end

G.Topic("quest", {
	events = {
		QUEST_LOG_UPDATE = QuestSoon,
		QUEST_ACCEPTED = function(_, a, b)
			local id = Num(b) or Num(a)               -- older clients: (logIndex, questID); now: questID
			if id then QuestAccepted(id, 0) end
		end,
		QUEST_TURNED_IN = function(_, id, xp, money)
			id = Num(id)
			if not id then return end
			xp, money = Num(xp), Num(money)
			G.Moment("quest.turnin", { quest = QuestTitle(id), id = id, xp = xp and xp > 0 and xp or nil,
				money = money and money > 0 and money or nil }, { key = id, every = 5 })
			if quests then quests[id] = nil end
		end,
	},
	on = function()
		quests = nil
		local ok, now = pcall(QuestRead)
		quests = ok and now or nil
	end,
	off = function() quests = nil end,
})
