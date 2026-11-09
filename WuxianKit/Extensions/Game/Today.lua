-- 游戏动态 · Today: the facet today, what this character did today: { date, levels, quests, kills, deaths, xp, zones }
-- (date: the local date, YYYY-MM-DD; xp: gained today; zones: zones been to for the first time ever, today). Kept in the
-- extension's storage for the character (ext:Char().today), so a reload keeps it; a new local date starts it again at 0.
-- Counted only while the facet is watched: then it hears the topics combat, growth, quest and travel through subscribers
-- of its own (their detectors run) and takes the facts the detectors hand G.Tally; when nobody watches any more it lets
-- them go. ext:Facet is the core's (0.6); a core without it: no facet, the rest stays idle.
--
-- For tests and the other files (ns.game.today = T):
--   T.Read() -> table        today's tally (a copy; a new day: all 0)
--   T.Count(what, n)         adds n (default 1) to a count; only while watched (what is a field name)
--   T.On(), T.Off()          watched / not any more (the facet's on and off)
--   T.watching               true while watched
--   T.Register()             the facet, through game:Facet (when the core has it)
local addonName, ns = ...
local Kit = WuxianKit
local G = ns.game
local game = G.ext
local Game = Kit.Game

local TOPICS = { "combat", "growth", "quest", "travel" }     -- what the counts come from
local COUNTS = { "levels", "quests", "kills", "deaths", "xp", "zones" }
local IS_COUNT = {}
for _, k in ipairs(COUNTS) do IS_COUNT[k] = true end

local L = Kit:Words {
	zhCN = { TITLE = "今日" },
	enUS = { TITLE = "Today" },
}

local T = { watching = false }
G.today = T

local tokens = {}                                 -- the subscribers that keep the topics running

local function Day()
	return date("%Y-%m-%d")
end

-- the stored tally, started again on a new day
local function Stored()
	local char = game:Char()
	local t, day = char.today, Day()
	if type(t) ~= "table" or t.date ~= day then
		t = { date = day }
		for _, k in ipairs(COUNTS) do t[k] = 0 end
		char.today = t
	end
	for _, k in ipairs(COUNTS) do
		if type(t[k]) ~= "number" then t[k] = 0 end
	end
	return t
end

function T.Read()
	local t, out = Stored(), {}
	out.date = t.date
	for _, k in ipairs(COUNTS) do out[k] = t[k] end
	return out
end

function T.Count(what, n)
	if not T.watching or not IS_COUNT[what] then return end
	n = type(n) == "number" and n or 1
	if n <= 0 then return end
	local t = Stored()
	t[what] = t[what] + math.floor(n)
end

local function Nothing() end

function T.On()
	if T.watching then return end
	T.watching = true
	G.tally = T.Count
	for _, topic in ipairs(TOPICS) do
		tokens[#tokens + 1] = Game:On(topic, Nothing)
	end
	Stored()                                      -- a new day starts now
end

function T.Off()
	if not T.watching then return end
	T.watching = false
	if G.tally == T.Count then G.tally = nil end
	local list = tokens
	tokens = {}
	for _, t in ipairs(list) do Game:Off(t) end
end

function T.Register()
	if not game.Facet then return nil end
	return game:Facet("today", {
		title = L"TITLE",
		doc = "today: what this character did today (by the local date): {date (YYYY-MM-DD), levels, quests (turned in), "
			.. "kills, deaths, xp (gained today), zones (zones been to for the first time ever, today)}; counted only "
			.. "while an app sees it, kept across reloads, back to 0 on a new day",
		fields = { date = "string", levels = "number", quests = "number", kills = "number", deaths = "number",
			xp = "number", zones = "number" },
		read = function() return T.Read() end,
		on = function() T.On() end,
		off = function() T.Off() end,
	})
end

T.Register()
