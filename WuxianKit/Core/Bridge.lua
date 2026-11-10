-- The core and the AI agent, through 无限工坊's WoWBridge when it is there (## OptionalDeps: WoWBridge): every capability
-- that goes live is exposed under its id (the agent calls it with `call`, addon "WuxianKit"; `addon_api WuxianKit`
-- lists them with what they do), every bus event goes to the agent as an event of the same topic (`events`, addon
-- "WuxianKit"), and "kit.propose" bundles steps into one proposal. A Say / Do the agent calls answers with its
-- proposal; the player confirms it in the game and its end comes as the event "kit.proposal". A single call's proposal
-- options ride in its args as _title, _ttl and _after. A capability of an extension that went off stays exposed (WoWBridge
-- has no way back) and refuses the call. Without WoWBridge nothing here does anything: the core runs the same for addons.
-- It binds to WoWBridge 0.9.7 or later only: the first whose calls come as data (an agent's call runs here as addon code,
-- with hot loading off too); an older one leaves the core on its own (ns.bound false), as no WoWBridge does. Nothing
-- WoWBridge does may break the core: every call into it is protected, and what it refuses is left out.
-- WoWBridge carries 10 events a second for an addon (20 at once) and drops the rest: the core's own events (kit.*,
-- a proposal's end above all) wait here (the last KEPT) and are sent again when there is room, and the extensions' (a
-- busy app) take at most FEED_RATE a second of it, so the core's find room; what was dropped is told every
-- DROPPED_EVERY seconds (kit.dropped). While 无限工坊 is not linked, WoWBridge itself keeps only its last few events.
-- An app's wake (app.<id>) is neither kept here nor dropped: ns.SendWake answers whether it went, and its digest
-- (Digest.lua) holds the items of one that did not and sends them again.
--   ns.WireSize(v, depth)      the bytes of v as WoWBridge writes an event's data (JSON, to `depth` levels: 6)
--   ns.Forward(topic, data)    a bus event to the agent; for app.*: whether it went (true without WoWBridge)
--   ns.SendWake(topic, data)   an app's wake to the agent, then to the bus; false (and told to nobody) when it did not go
local addonName, ns = ...
local Kit = ns.Kit

local function Supported(v)                              -- "0.9.7" or later
	local a, b, c = tostring(v or ""):match("^(%d+)%.(%d+)%.(%d+)")
	a, b, c = tonumber(a), tonumber(b), tonumber(c)
	return a ~= nil and (a > 0 or b > 9 or (b == 9 and c >= 7))
end

local WB
if type(WoWBridge) == "table" and type(WoWBridge.Bind) == "function" and Supported(WoWBridge.VERSION) then
	local ok, handle = pcall(WoWBridge.Bind, addonName)
	if ok and type(handle) == "table" then WB = handle end
end
ns.bound = WB ~= nil
local FEED_RATE, FEED_BURST, KEPT, DROPPED_EVERY = 6, 12, 50, 5
local OPTIONS = { _title = "title", _ttl = "ttl", _after = "after" }
local KIND_DOC = { see = "Read: runs at once, changes nothing.", keep = "Store: runs at once.",
	point = "Guide: runs at once, changes no setting.", say = "Send: a proposal.", ["do"] = "Change: a proposal." }
local exposed = {}

-- the args of an agent's call without the proposal options, and the options
local function Split(args)
	local opts = { source = "agent" }
	if type(args) ~= "table" then return args, opts end
	local clean = {}
	for k, v in pairs(args) do
		if OPTIONS[k] then opts[OPTIONS[k]] = v else clean[k] = v end
	end
	return clean, opts
end

local function Doc(cap)
	local kind = cap.proposes and "Proposal: runs at once and answers with a proposal of other steps." or KIND_DOC[cap.kind]
	local text = ("[%s] %s Args: %s."):format(kind, cap.doc, cap.argText)
	if ns.KINDS[cap.kind].proposed or cap.proposes then
		text = text .. " Answers with the proposal {id, state, steps}: the player confirms it in the game, unless they"
			.. " pre-approved its category; its end is the event kit.proposal. Options: _title, _ttl (10-600 s), _after"
			.. " (a Unix time before which it may not run; not a delay)."
	end
	return text
end

-- a proposal (or an entry of kit.history) as the agent reads it: its steps' previews as plain text (ns.Plain), without
-- the color codes and escapes the window and the other addons get
local function Plainly(p)
	if type(p) ~= "table" or type(p.steps) ~= "table" then return p end
	local copy, steps = {}, {}
	for k, v in pairs(p) do copy[k] = v end
	for i, s in ipairs(p.steps) do
		local step = {}
		for k, v in pairs(s) do step[k] = v end
		step.preview = ns.Plain(s.preview)
		steps[i] = step
	end
	copy.steps = steps
	return copy
end

local LISTS = { ["kit.proposals"] = true, ["kit.history"] = true }

local function ForAgent(cap, result)
	if ns.KINDS[cap.kind].proposed or cap.proposes or cap.id == "kit.proposal" then return Plainly(result) end
	if LISTS[cap.id] and type(result) == "table" then
		local out = {}
		for i, p in ipairs(result) do out[i] = Plainly(p) end
		return out
	end
	return result
end

-- fn(...) for the agent: an error the core throws at its caller (level 2 points here) goes as its message alone, so the
-- App leaves out the stack WoWBridge adds; an error from deeper (an extension's bug) keeps its place
local function Called(fn, ...)
	local ok, res = pcall(fn, ...)
	if ok then return res end
	if type(res) == "string" then res = res:gsub("^[^\n]-Bridge%.lua:%d+: ", "", 1) end
	error(res, 0)
end

local function Expose(cap)
	if not WB or exposed[cap.id] == cap then return end
	local ok = pcall(WB.Expose, WB, cap.id, function(args)
		local clean, opts = Split(args)
		return ForAgent(cap, Called(Kit.Call, Kit, cap.id, clean, opts))
	end, Doc(cap))
	if ok then exposed[cap.id] = cap end                  -- one WoWBridge refused stays out of the agent's reach
end

-- an event to WoWBridge: "sent", "busy" (not now: try again) or "bad" (it refused this one: never again)
local function Send(topic, data)
	local ok, taken = pcall(WB.Emit, WB, topic, data)
	if not ok then return "bad" end
	return taken and "sent" or "busy"
end

local again = {}                                         -- the core's events WoWBridge could not take yet, in order
local tokens, at = FEED_BURST, 0                        -- the extensions' share
local dropped, droppedAt = {}, 0                        -- topic -> how many of the extensions' went unsent

-- the bytes of v as WoWBridge's Json.Encode writes it (an event's data goes to 6 levels; a table past them is
-- "<table>"): a table with a sequence (or empty) is an array, another an object with its keys as texts; a text has its
-- quotes, backslashes and bytes below 32 escaped (six bytes each). WoWBridge sends an event's data of more than 8000
-- such bytes as {cut = true}: what the digest keeps its wakes under
local function WireSize(v, depth)
	if issecretvalue and issecretvalue(v) then return 10 end
	local t = type(v)
	if t == "boolean" then return v and 4 or 5 end
	if t == "number" then
		if not ns.Finite(v) then return 4 end
		if v == math.floor(v) and math.abs(v) <= 9007199254740992 then return #("%.0f"):format(v) end
		return #("%.14g"):format(v)
	end
	if t == "string" then
		local _, escaped = v:gsub('[%z\1-\31"\\]', "")
		return #v + 2 + escaped * 5
	end
	if t ~= "table" then return t == "nil" and 4 or #ns.Text(v) + 2 end
	if depth <= 0 then return 9 end
	local n, size = #v, 1
	if n > 0 or next(v) == nil then
		for i = 1, n do size = size + WireSize(v[i], depth - 1) + 1 end
		return math.max(2, size)
	end
	for k, x in pairs(v) do size = size + WireSize(tostring(k), 0) + WireSize(x, depth - 1) + 2 end
	return size
end

function ns.WireSize(v, depth)
	return WireSize(v, depth or 6)
end

local told                                               -- the wake ns.SendWake is telling the bus: it went already

function ns.Forward(topic, data)
	if topic:sub(1, 4) == "app." then                     -- a wake: it goes now or not at all, and its sender hears which
		if not WB or (told ~= nil and told == data) then return true end
		local now = GetTime()
		tokens, at = math.min(FEED_BURST, tokens + (now - at) * FEED_RATE), now
		if tokens < 1 or Send(topic, data) ~= "sent" then return false end
		tokens = tokens - 1
		return true
	end
	if not WB then return end
	if topic == "kit.proposal" then data = Plainly(data) end
	if topic:sub(1, 4) == "kit." then
		if #again == 0 and Send(topic, data) ~= "busy" then return end
		if #again >= KEPT then table.remove(again, 1) end
		again[#again + 1] = { topic, data }
		return
	end
	local now = GetTime()
	tokens, at = math.min(FEED_BURST, tokens + (now - at) * FEED_RATE), now
	local sent = tokens >= 1 and Send(topic, data)
	if sent == "sent" then
		tokens = tokens - 1
	elseif sent ~= "bad" then
		dropped[topic] = (dropped[topic] or 0) + 1
	end
end

-- an app's wake: to the agent first, and to the bus (the addons that listen) only when it went, so that nobody hears
-- one twice when it is sent again
function ns.SendWake(topic, data)
	if not ns.Forward(topic, data) then return false end
	told = data
	Kit:Emit(topic, data)
	told = nil
	return true
end

if WB then
	C_Timer.NewTicker(0.25, function()
		while again[1] and Send(again[1][1], again[1][2]) ~= "busy" do table.remove(again, 1) end
		if next(dropped) and GetTime() - droppedAt >= DROPPED_EVERY then
			local count = 0
			for _, n in pairs(dropped) do count = count + n end
			droppedAt = GetTime()
			Kit:Emit("kit.dropped", { count = count, topics = dropped })
			dropped = {}
		end
	end)
end

if WB then
	pcall(WB.Expose, WB, "kit.propose", function(a)
		a = type(a) == "table" and a or {}
		local steps = {}
		for i, s in ipairs(type(a.steps) == "table" and a.steps or {}) do
			steps[i] = type(s) == "table" and { s.cap or s[1], s.args or s[2] } or s
		end
		return Plainly(Called(Kit.Propose, Kit, steps, { source = "agent", title = a.title, ttl = a.ttl, after = a.after }))
	end, "Several say / do steps in one proposal the player confirms once: {title, steps: [{cap, args}], ttl (10-600 s),"
		.. " after (time())}. Answers with the proposal; its end is the event kit.proposal.")
	for _, cap in pairs(ns.caps) do Expose(cap) end      -- what went live before this file loaded
	ns.OnChange(function(what, cap)
		if what == "capability" then Expose(cap) end
	end)
end

-- the agent hears that the core is up (after every login and /reload): its version and extensions
local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_ENTERING_WORLD")
events:SetScript("OnEvent", function(self)
	self:UnregisterAllEvents()
	Kit:Emit("kit.ready", { version = Kit.VERSION, extensions = ns.ExtensionList(), revision = ns.ManifestReady() })
end)
