-- Addon messages: data between players' clients, WuxianKit's building block for talking across clients (the remote
-- extension's proposals use it, and other addons may).
--   WuxianKit.Comm.Send(prefix, data, channel[, target]): data (strings, numbers, booleans and tables of them)
--     serialized, cut to what one message carries (MAX bytes) and paced as the server allows (a prefix sends BURST at once,
--     then RATE a second), in order; channel "GUILD", "PARTY", "RAID", "INSTANCE_CHAT" or "WHISPER" (target: the player)
--   WuxianKit.Comm.Listen(prefix, fn(data, sender, channel)): fn hears each message whole, once all its parts came
--   WuxianKit.Comm.Serialize(v) / .Deserialize(s): the format on its own
-- A message is its parts, each "<mark><bytes>": mark 4 = the whole of it, 1 = its first part, 2 = a middle one, 3 = the
-- last; a sender's parts come in order. The format: s<length>:<bytes>, n<number>;, T, F, z (nil), t ... e (a table: key,
-- value, key, value), with byte 0 written \1\2 and byte 1 \1\1; a number only in the decimal form Serialize writes.
-- Nothing here is a capability: an addon message reaches only clients with an addon listening to its prefix, and only
-- an addon of the player's own sends one. A whisper to the player themself is handed over in the client (the server
-- never brings one back: measured on 1.60.1.70245). A part the server holds back (throttled, chat lockdown) is sent
-- again later; one it refuses takes the rest of its message with it. A message heard in parts is dropped past PARTS_MAX
-- bytes or PARTS_TIME seconds.
local _, ns = ...

local Comm = {}
ns.Kit.Comm = Comm
ns.Comm = Comm

local MAX, BURST, RATE = 255, 10, 1          -- bytes of a message (its mark included); messages a prefix sends at once; a second
local PARTS_MAX, PARTS_TIME = 64 * 1024, 30
local SINGLE, FIRST, MIDDLE, LAST = "\4", "\1", "\2", "\3"
local RESULT = Enum and Enum.SendAddonMessageResult or {}
local SENT = RESULT.Success or 0
local LATER = { [RESULT.AddonMessageThrottle or 3] = true, [RESULT.ChannelThrottle or 8] = true,
	[RESULT.AddOnMessageLockdown or 11] = true }  -- held back: the same part again later

------------------------------------------------------------------------------------------------------------------------
-- the format

local function Put(out, v, depth)
	local t = type(v)
	if v == nil then
		out[#out + 1] = "z"
	elseif t == "boolean" then
		out[#out + 1] = v and "T" or "F"
	elseif t == "number" then
		if v ~= v or v == math.huge or v == -math.huge then error("WuxianKit.Comm.Serialize: a number that is not finite", 0) end
		out[#out + 1] = ("n%.17g;"):format(v)
	elseif t == "string" then
		out[#out + 1] = "s" .. #v .. ":" .. v
	elseif t == "table" then
		if depth > 20 then error("WuxianKit.Comm.Serialize: tables nested deeper than 20", 0) end
		out[#out + 1] = "t"
		for k, x in pairs(v) do
			Put(out, k, depth + 1)
			Put(out, x, depth + 1)
		end
		out[#out + 1] = "e"
	else
		error(("WuxianKit.Comm.Serialize: a %s cannot go"):format(t), 0)
	end
end

function Comm.Serialize(v)
	local out = {}
	Put(out, v, 0)
	return (table.concat(out):gsub("[%z\1]", { ["\1"] = "\1\1", ["\0"] = "\1\2" }))
end

local function Take(s, i, depth)
	local tag = s:sub(i, i)
	if tag == "z" then return nil, i + 1 end
	if tag == "T" then return true, i + 1 end
	if tag == "F" then return false, i + 1 end
	if tag == "n" then                               -- as %.17g writes it: no nan, inf or hex
		local num, stop = s:match("^(%-?%d+%.?%d*[eE]?[%+%-]?%d*);()", i + 1)
		local v = tonumber(num)
		if not ns.Finite(v) then error("a bad number", 0) end
		return v, stop
	end
	if tag == "s" then
		local n, start = s:match("^(%d+):()", i + 1)
		if not n then error("a bad string", 0) end
		local stop = start + tonumber(n)
		if stop - 1 > #s then error("a string that runs past the end", 0) end
		return s:sub(start, stop - 1), stop
	end
	if tag == "t" then
		if depth > 20 then error("tables nested deeper than 20", 0) end
		local t, j = {}, i + 1
		while s:sub(j, j) ~= "e" do
			if j > #s then error("a table with no end", 0) end
			local k, x
			k, j = Take(s, j, depth + 1)
			x, j = Take(s, j, depth + 1)
			if k ~= nil then t[k] = x end
		end
		return t, j + 1
	end
	error(("an unknown tag %q"):format(tag), 0)
end

-- the value, or nil + what is wrong
function Comm.Deserialize(s)
	if type(s) ~= "string" then return nil, "not a string" end
	s = s:gsub("\1([\1\2])", { ["\1"] = "\1", ["\2"] = "\0" })
	local ok, v, stop = pcall(Take, s, 1, 0)
	if not ok then return nil, v end
	if stop <= #s then return nil, "text after the value" end
	return v
end

------------------------------------------------------------------------------------------------------------------------
-- sending

local queues = {}          -- prefix -> { tokens, at, list = { { text, channel, target, message } } }
local sent = 0             -- messages queued so far: a part knows its message by it

local function Queue(prefix)
	local q = queues[prefix]
	if not q then
		q = { tokens = BURST, at = GetTime(), list = {} }
		queues[prefix] = q
	end
	return q
end

local function Drain()
	local now = GetTime()
	for prefix, q in pairs(queues) do
		q.tokens, q.at = math.min(BURST, q.tokens + (now - q.at) * RATE), now
		while q.list[1] and q.tokens >= 1 do
			local m = q.list[1]
			local result = C_ChatInfo.SendAddonMessage(prefix, m[1], m[2], m[3])
			if LATER[result] then                    -- the server holds it back (it counts otherwise): later
				q.tokens = 0
				break
			end
			table.remove(q.list, 1)
			q.tokens = q.tokens - 1
			if result ~= nil and result ~= true and result ~= SENT then   -- refused: the rest of its message is no use
				while q.list[1] and q.list[1][4] == m[4] do table.remove(q.list, 1) end
			end
		end
	end
end

local Deliver

-- the player's whole name as addon messages name a sender (two words with a space on this client; "Name" or
-- "Name-Realm" elsewhere)
function Comm.Me()
	return GetUnitName and GetUnitName("player", true) or UnitName("player")
end

-- whether a name is the player's own (whole, or its first part)
function Comm.IsMe(name)
	if type(name) ~= "string" then return false end
	name = Ambiguate(name, "none")
	return name == Comm.Me() or name == UnitName("player")
end

-- data to the clients that listen to prefix on a channel; how many messages it takes
function Comm.Send(prefix, data, channel, target)
	if type(prefix) ~= "string" or prefix == "" or #prefix > 16 then error("WuxianKit.Comm.Send: prefix is 1-16 bytes", 2) end
	if type(channel) ~= "string" then
		error("WuxianKit.Comm.Send: channel is GUILD, PARTY, RAID, INSTANCE_CHAT or WHISPER", 2)
	end
	local body = Comm.Serialize(data)
	if channel == "WHISPER" and Comm.IsMe(target) then            -- to oneself: in the client, a moment later
		C_Timer.After(0, function() Deliver(prefix, body, Comm.Me(), "WHISPER") end)
		return 1
	end
	local q, room = Queue(prefix), MAX - 1
	local n = math.max(1, math.ceil(#body / room))
	sent = sent + 1
	if n == 1 then
		q.list[#q.list + 1] = { SINGLE .. body, channel, target, sent }
	else
		for i = 1, n do
			local mark = i == 1 and FIRST or i == n and LAST or MIDDLE
			q.list[#q.list + 1] = { mark .. body:sub((i - 1) * room + 1, i * room), channel, target, sent }
		end
	end
	Drain()
	return n
end

------------------------------------------------------------------------------------------------------------------------
-- hearing

local listeners = {}       -- prefix -> { fn, ... }
local partial = {}         -- prefix .. "\0" .. channel .. "\0" .. sender -> { parts, bytes, at }

function Comm.Listen(prefix, fn)
	if type(prefix) ~= "string" or prefix == "" or #prefix > 16 then error("WuxianKit.Comm.Listen: prefix is 1-16 bytes", 2) end
	if type(fn) ~= "function" then error("WuxianKit.Comm.Listen: fn is a function", 2) end
	C_ChatInfo.RegisterAddonMessagePrefix(prefix)
	listeners[prefix] = listeners[prefix] or {}
	table.insert(listeners[prefix], fn)
end

function Deliver(prefix, body, sender, channel)
	local data, err = Comm.Deserialize(body)
	if err then return end                             -- not ours, or broken on its way: nothing to hand on
	for _, fn in ipairs(listeners[prefix] or {}) do ns.Safe(fn, data, sender, channel) end
end

local function Heard(prefix, text, channel, sender)
	if not listeners[prefix] or type(text) ~= "string" or text == "" then return end
	local mark, body = text:sub(1, 1), text:sub(2)
	local key = prefix .. "\0" .. tostring(channel) .. "\0" .. tostring(sender)
	if mark == SINGLE then
		Deliver(prefix, body, sender, channel)
	elseif mark == FIRST then
		partial[key] = { parts = { body }, bytes = #body, at = GetTime() }
	elseif mark == MIDDLE or mark == LAST then
		local p = partial[key]
		if not p then return end                       -- its first part never came: the rest is no use
		p.parts[#p.parts + 1] = body
		p.bytes = p.bytes + #body
		if p.bytes > PARTS_MAX then                    -- more than any message of ours: dropped
			partial[key] = nil
		elseif mark == LAST then
			partial[key] = nil
			Deliver(prefix, table.concat(p.parts), sender, channel)
		end
	end
end

-- messages whose parts stopped coming are dropped
local function Forget()
	local now = GetTime()
	for key, p in pairs(partial) do
		if now - p.at > PARTS_TIME then partial[key] = nil end
	end
end

local frame = CreateFrame("Frame")
frame:RegisterEvent("CHAT_MSG_ADDON")
frame:SetScript("OnEvent", function(_, _, prefix, text, channel, sender)
	Heard(prefix, text, channel, sender)
end)
C_Timer.NewTicker(0.25, Drain)
C_Timer.NewTicker(10, Forget)
