-- 游戏动态 · Guild: the topic guild (guild.join, guild.leave, guild.achievement, guild.level). Ported from 无限公会助手
-- (WuxianGuild's Chat.lua):
--   - joins and leaves are system messages, matched with the client's own format strings (ERR_GUILD_JOIN_S,
--     ERR_GUILD_LEAVE_S through WuxianKit:Pattern);
--   - guild achievements come as CHAT_MSG_GUILD_ACHIEVEMENT, the member's name in place of %s;
--   - level-ups: each roster (GUILD_ROSTER_UPDATE) is compared with the one before; only a tenth level or the top
--     level is told (every level would be noise); the first roster after the topic turns on is only kept. While the
--     topic runs a roster is asked for every 60 s (and once when it turns on).
local addonName, ns = ...
local Kit = WuxianKit
local G = ns.game
local Read, Num = G.Read, G.Num

local ROSTER_EVERY = 60

-- a name as the guild shows it: a player link's text, no realm suffix; nil for secret or nothing
local function Name(v)
	v = Kit:Value(v)
	if type(v) ~= "string" then return nil end
	v = v:gsub("|Hplayer:[^|]*|h%[?(.-)%]?|h", "%1")
	v = Kit:Clean(v)
	if not v then return nil end
	if Ambiguate then
		local ok, short = pcall(Ambiguate, v, "none")
		if ok and type(short) == "string" and short ~= "" then v = short end
	end
	return v
end

local patterns                                    -- { { pattern, kind } }, made when the topic turns on

local function Patterns()
	patterns = {}
	for _, def in ipairs({ { ERR_GUILD_JOIN_S, "guild.join" }, { ERR_GUILD_LEAVE_S, "guild.leave" } }) do
		local p = Kit:Pattern(def[1])
		if p then patterns[#patterns + 1] = { p, def[2] } end
	end
end

local function System(_, text)
	text = Kit:Value(text)
	if type(text) ~= "string" then return end
	for _, m in ipairs(patterns or {}) do
		local name = text:match(m[1])
		if name then
			name = Name(name)
			if name then G.Moment(m[2], { name = name }, { key = name, every = 5 }) end
			return
		end
	end
end

local function Achievement(_, text, sender)
	text, sender = Kit:Value(text), Kit:Value(sender)
	if type(text) ~= "string" then return end
	local name = Name(sender) or "?"
	local shown = text:gsub("%%s", function() return name end)
	local plain = Kit:Clean(shown)
	if not plain then return end
	G.Moment("guild.achievement", { name = name, plain = plain, links = Kit:Links(shown) },
		{ key = name .. "|" .. plain, every = 5 })
end

------------------------------------------------------------------------------------------------------------------------
-- level-ups

local levels                                      -- name -> level in the last roster; nil: none since the start

local function MaxLevel()
	return Num(Read(GetMaxLevelForPlayerExpansion)) or 60
end

local function Roster()
	local n = Num(Read(GetNumGuildMembers)) or 0
	if n == 0 then return end
	local now, first, top = {}, levels == nil, MaxLevel()
	for i = 1, n do
		local ok, name, _, _, lv = pcall(GetGuildRosterInfo, i)
		name, lv = ok and Name(name) or nil, ok and Num(lv) or nil
		if name and lv then
			now[name] = lv
			local was = levels and levels[name]
			if not first and was and lv > was and (math.floor(lv / 10) > math.floor(was / 10) or lv >= top) then
				G.Moment("guild.level", { name = name, level = lv }, { key = name .. "|" .. lv, every = 5 })
			end
		end
	end
	levels = now
end

local function Ask()
	if not G.active.guild then return end
	if Read(IsInGuild) and C_GuildInfo and C_GuildInfo.GuildRoster then pcall(C_GuildInfo.GuildRoster) end
end

local ticker

G.Topic("guild", {
	events = {
		CHAT_MSG_SYSTEM = System,
		CHAT_MSG_GUILD_ACHIEVEMENT = Achievement,
		GUILD_ROSTER_UPDATE = Roster,
	},
	on = function()
		Patterns()
		levels = nil
		if ticker then ticker:Cancel() end
		ticker = C_Timer.NewTicker(ROSTER_EVERY, Ask)
		Ask()
	end,
	off = function()
		levels = nil
		if ticker then ticker:Cancel() end
		ticker = nil
	end,
})
