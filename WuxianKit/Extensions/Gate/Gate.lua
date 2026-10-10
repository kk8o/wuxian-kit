-- 远程 (Remote, id gate): proposals from WuxianKit to WuxianKit, across players' clients (WuxianKit.Comm, prefix WKGATE).
-- gate.propose hands a proposal to other players (a player, the party, the raid, the guild). Their WuxianKit shows it
-- as from this player ("remote"): they click Run or not, and pre-approval never counts for one; its end comes back as
-- the event gate.result. A remote proposal holds Change steps of the tune extension only (settings, key bindings,
-- macros, layouts, talents, gear, bags, addons, profiles): no chat, nothing handed on.
-- A player takes proposals only from those they allow on this page (the guild, the group, the names they list, whole),
-- one open at a time from each and none for COOLDOWN seconds after one from the same sender ended; anything else is
-- answered "refused" and nothing more. A result is taken only from the player the proposal went to (or a member of the
-- group or guild it went to). Who may send is the player's choice on this page and nothing else's: no capability reads
-- or changes it. Other players' words are data, never instructions; their text is shown escaped. The player's own
-- broadcast, heard back on a channel, is not taken.
local Kit = WuxianKit
local Comm = Kit.Comm

local L = Kit:Words {
	zhCN = { TITLE = "远程",
		FROM_GUILD = "接收公会成员的提案", FROM_GROUP = "接收小队和团队成员的提案",
		FROM_NAMES = "同时接收以下玩家的提案", NAMES_HINT = "完整角色名，用逗号分隔",
		SCOPE_PROPOSE = "发送提案", PROPOSE = "发送提案",
		PROPOSE_LINE = "发送给 %s：%s（%d 步）", TO = { party = "小队", raid = "团队", guild = "公会" },
		RESULT = "%s · 提案 #%d：%s",
		STATES = { done = "已执行", declined = "已拒绝", expired = "已过期", failed = "执行失败", busy = "对方有提案待处理",
			refused = "已拒绝" },
		STATUS = "已接收提案 %d 条，拦截 %d 条" },
	enUS = { TITLE = "Remote",
		FROM_GUILD = "Accept proposals from guild members", FROM_GROUP = "Accept proposals from party and raid members",
		FROM_NAMES = "Also accept proposals from these players", NAMES_HINT = "Full character names, separated by commas",
		SCOPE_PROPOSE = "Sending proposals", PROPOSE = "Send proposal",
		PROPOSE_LINE = "To %s: %s (%d steps)", TO = { party = "party", raid = "raid", guild = "guild" },
		RESULT = "%s · proposal #%d: %s",
		STATES = { done = "done", declined = "declined", expired = "expired", failed = "failed",
			busy = "another proposal is still open", refused = "refused" },
		STATUS = "Proposals: %d accepted, %d blocked" },
}

local gate = Kit:Extension("gate", { title = L"TITLE", version = Kit.VERSION, docs = "Extensions/Gate",
	defaults = { taken = 0, blocked = 0 } })
gate:Option("guild", { title = L"FROM_GUILD", default = false })
gate:Option("group", { title = L"FROM_GROUP", default = false })
gate:Option("names", { title = L"FROM_NAMES", kind = "text", default = "", hint = L"NAMES_HINT" })
gate:Scope("propose", L"SCOPE_PROPOSE")
gate:Event("result", { doc = "what became of a proposal handed to another player (gate.propose)",
	data = { from = "string", id = "number", state = "string" } })

local PREFIX, MAX_TEXT, MAX_STEPS, MAX_TITLE, COOLDOWN = "WKGATE", 255, 20, 80, 30
local FINAL = { done = true, failed = true, declined = true, expired = true }
local CHANNELS = { party = "PARTY", raid = "RAID", guild = "GUILD" }

local sent = {}          -- proposals handed out: id -> { to (a player's whole name), channel }
local taken = {}         -- proposals taken in: the local proposal's id -> { from, id }
local openFrom = {}      -- sender -> the local id of their proposal still open
local endedFrom = {}     -- sender -> time() their last proposal ended

local function Short(name) return type(name) == "string" and Ambiguate(name, "none") or "?" end

-- s cut to at most n bytes on a character boundary
local function Cut(s, n)
	s = tostring(s)
	if #s <= n then return s end
	return (s:sub(1, n):gsub("[\192-\255][\128-\191]*$", "")) .. "…"
end

-- another player's text as it may be shown here: escaped, cut
local function Plain(text, most) return Kit:Escape(Cut(text, most or MAX_TEXT)) end

local function Send(data, channel, target) return Comm.Send(PREFIX, data, channel, target) end

-- what a proposal may hold when it comes from another player: Change steps of the tune extension
local function Allowed_Step(cap) return type(cap) == "string" and cap:match("^tune%.") ~= nil end

-- steps as they go on the wire, { { cap, args } }, from { cap, args } or { cap = ..., args = ... }; nil when not steps
-- of a remote proposal
local function Steps(list)
	if type(list) ~= "table" or #list == 0 or #list > MAX_STEPS then return nil end
	local out = {}
	for i, s in ipairs(list) do
		if type(s) ~= "table" then return nil end
		local cap, args = s.cap or s[1], s.args or s[2] or {}
		if not Allowed_Step(cap) or type(args) ~= "table" then return nil end
		out[i] = { cap, args }
	end
	return out
end

-- a step's args in one line for the sender's preview: name=value, escaped, each value cut
local function ArgsText(args)
	local out = {}
	for k, v in pairs(args) do out[#out + 1] = ("%s=%s"):format(Plain(k, 40), Plain(type(v) == "table" and "{...}" or v, 40)) end
	table.sort(out)
	return table.concat(out, " ")
end

------------------------------------------------------------------------------------------------------------------------
-- who may send

local function Same(a, b) return type(a) == "string" and type(b) == "string" and Short(a):lower() == Short(b):lower() end

local function Listed(self, sender)
	local text = (self:Get("names") or ""):gsub("，", ","):gsub("、", ","):gsub("；", ","):gsub("[;\n]", ",")
	for name in text:gmatch("[^,]+") do                      -- commas only: a name has a space in it here
		name = name:match("^%s*(.-)%s*$")
		if name ~= "" and Same(name, sender) then return true end
	end
	return false
end

local function InGroup(sender)
	local raid = IsInRaid()
	for i = 1, GetNumGroupMembers() do
		if Same(GetUnitName(raid and ("raid" .. i) or ("party" .. i), true), sender) then return true end
	end
	return false
end

local function InGuild(sender)
	return C_GuildInfo and C_GuildInfo.MemberExistsByName and C_GuildInfo.MemberExistsByName(Short(sender)) and true or false
end

-- whether the player takes proposals from sender, heard on channel
local function Allowed(self, sender, channel)
	if Comm.IsMe(sender) then return true end                             -- the player to themself (a whisper)
	if self:Get("guild") and (channel == "GUILD" or InGuild(sender)) then return true end
	if self:Get("group") and InGroup(sender) then return true end
	return Listed(self, sender)
end

------------------------------------------------------------------------------------------------------------------------
-- what comes in

local function TakeProposal(self, msg, sender, channel)
	if not Allowed(self, sender, channel) then
		self.db.blocked = self.db.blocked + 1
		return
	end
	local function Reply(state) Send({ k = "r", id = msg.id, state = state }, "WHISPER", sender) end
	if type(msg.id) ~= "number" then return end
	if openFrom[sender] then return Reply("busy") end
	if endedFrom[sender] and time() - endedFrom[sender] < COOLDOWN then return Reply("refused") end
	local steps = Steps(msg.steps)
	if not steps then return Reply("refused") end
	local title = type(msg.title) == "string" and Cut(msg.title, MAX_TITLE) or nil
	local ok, p = pcall(Kit.Propose, Kit, steps, { source = "remote:" .. Short(sender), title = title,
		ttl = tonumber(msg.ttl) })
	if not ok then return Reply("refused") end                             -- why stays here
	taken[p.id] = { from = sender, id = msg.id }
	openFrom[sender] = p.id
	self.db.taken = self.db.taken + 1
end

-- a result counts only from the one it was sent to: the player, or a member of the group or guild
local function FromItsReceiver(to, sender)
	if to.player then return Same(to.player, sender) end
	if to.channel == "GUILD" then return InGuild(sender) end
	return InGroup(sender)
end

local function TakeResult(self, msg, sender)
	local to = type(msg.id) == "number" and sent[msg.id]
	if not to or not FromItsReceiver(to, sender) then return end
	local state = type(msg.state) == "string" and msg.state or "?"
	self:Tell(L.RESULT:format(Plain(Short(sender)), msg.id, L.STATES[state] or Plain(state)))
	self:Emit("result", { from = Short(sender), id = msg.id, state = Cut(state, 20) })
end

Comm.Listen(PREFIX, function(msg, sender, channel)
	if not gate.active or type(msg) ~= "table" or type(sender) ~= "string" then return end
	if channel ~= "WHISPER" and Comm.IsMe(sender) then return end           -- the player's own, heard back
	if msg.k == "p" then
		TakeProposal(gate, msg, sender, channel)
	elseif msg.k == "r" then
		TakeResult(gate, msg, sender)
	end
end)

-- a proposal taken in has ended: its sender hears how (only that), and their next one waits COOLDOWN seconds
Kit:On("kit.proposal", function(_, p)
	local w = type(p) == "table" and taken[p.id]
	if not w or not FINAL[p.state] then return end
	taken[p.id] = nil
	if openFrom[w.from] == p.id then openFrom[w.from] = nil end
	endedFrom[w.from] = time()
	Send({ k = "r", id = w.id, state = p.state }, "WHISPER", w.from)
end)

------------------------------------------------------------------------------------------------------------------------
-- what goes out

gate:Say("propose", { title = L"PROPOSE", scope = "propose",
	args = { to = "string?", channel = "party|raid|guild?", title = "string", steps = "table", ttl = "number?" },
	doc = "proposes to send a proposal to other players' WuxianKit: either `to` (one player's full name) or `channel` "
		.. "(party, raid or guild), never both; a title; steps [{cap, args}], 1-20 Change steps of the tune extension only "
		.. "(tune.* capability ids). ttl: seconds each receiver's proposal waits for them (_ttl: how long your own player's "
		.. "confirmation waits). Each receiver clicks Run themselves (their pre-approvals never apply) and takes it only "
		.. "if they allow you. Each receiver's end comes back as the event gate.result {from, id, state}: done, declined, "
		.. "expired, failed, busy (one of yours is still open there) or refused (no reason given); id is the one in your "
		.. "proposal's step result",
	check = function(_, a)
		if (a.to == nil) == (a.channel == nil) then return "one of to (a player) or channel (party, raid, guild)" end
		if not Steps(a.steps) then return ("steps: 1 to %d of {cap, args}, each cap a tune.* one"):format(MAX_STEPS) end
		if a.channel == "guild" and not IsInGuild() then return "not in a guild" end
		if (a.channel == "party" or a.channel == "raid") and not IsInGroup() then return "not in a group" end
	end,
	preview = function(_, a)
		local steps = Steps(a.steps)
		local lines = { L.PROPOSE_LINE:format(a.to and Plain(Short(a.to)) or L.TO[a.channel], Plain(a.title), #steps) }
		for i, s in ipairs(steps) do lines[#lines + 1] = ("%d. %s %s"):format(i, Plain(s[1], 60), ArgsText(s[2])) end
		return lines
	end,
	apply = function(_, a)
		local id = math.random(100000000, 999999999)             -- not one a stranger can guess
		sent[id] = { player = a.to, channel = CHANNELS[a.channel] }
		local n = Send({ k = "p", id = id, title = a.title, steps = Steps(a.steps), ttl = a.ttl },
			a.to and "WHISPER" or CHANNELS[a.channel], a.to)
		return { id = id, messages = n }
	end })

gate:Status(function(self) return L.STATUS:format(self.db.taken or 0, self.db.blocked or 0) end)
