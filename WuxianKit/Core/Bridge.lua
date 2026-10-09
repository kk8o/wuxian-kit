-- The core and the AI agent, through 无限工坊's WoWBridge when it is there (## OptionalDeps: WoWBridge): every capability
-- that goes live is exposed under its id (the agent calls it with `call`, addon "WuxianKit"; `addon_api WuxianKit`
-- lists them with what they do), every bus event goes to the agent as an event of the same topic (`events`, addon
-- "WuxianKit"), and "kit.propose" bundles steps into one proposal. A Say / Do the agent calls answers with its
-- proposal; the player confirms it in the game and its end comes as the event "kit.proposal". A single call's proposal
-- options ride in its args as _title, _ttl and _after. A capability of an extension that went off stays exposed (WoWBridge
-- has no way back) and refuses the call. Without WoWBridge nothing here does anything: the core runs the same for addons.
-- WoWBridge carries 10 events a second for an addon (20 at once) and drops the rest: the core's own events (kit.*,
-- a proposal's end above all) are sent again until they go, and the extensions' (a busy chat feed) take at most
-- FEED_RATE a second of it, so the core's always find room; what was dropped is told every DROPPED_EVERY seconds
-- (kit.dropped).
local addonName, ns = ...
local Kit = ns.Kit

local WB = WoWBridge and WoWBridge.Bind and WoWBridge.Bind(addonName) or nil
local FEED_RATE, FEED_BURST, KEPT, DROPPED_EVERY = 6, 12, 50, 5
local OPTIONS = { _title = "title", _ttl = "ttl", _after = "after" }
local KIND_DOC = { see = "See: runs at once.", keep = "Keep: runs at once.", point = "Point: runs at once, changes nothing.",
	say = "Say: a proposal.", ["do"] = "Do: a proposal." }
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
	local kind = cap.proposes and "Proposes: runs at once and answers with a proposal of other steps." or KIND_DOC[cap.kind]
	local text = ("[%s] %s Args: %s."):format(kind, cap.doc, cap.argText)
	if ns.KINDS[cap.kind].proposed or cap.proposes then
		text = text .. " Answers with the proposal {id, state, steps}: the player confirms it in the game (unless they let"
			.. " its scope go without asking); its end is the event kit.proposal. Options: _title, _ttl (10-600 s), _after"
			.. " (a time() before which it may not run)."
	end
	return text
end

local function Expose(cap)
	if not WB or exposed[cap.id] == cap then return end
	exposed[cap.id] = cap
	WB:Expose(cap.id, function(args)
		local clean, opts = Split(args)
		return Kit:Call(cap.id, clean, opts)
	end, Doc(cap))
end

local again = {}                                         -- the core's events WoWBridge could not take yet, in order
local tokens, at = FEED_BURST, 0                        -- the extensions' share
local dropped, droppedAt = {}, 0                        -- topic -> how many of the extensions' went unsent

function ns.Forward(topic, data)
	if not WB then return end
	if topic:sub(1, 4) == "kit." then
		if #again == 0 and WB:Emit(topic, data) then return end
		if #again >= KEPT then table.remove(again, 1) end
		again[#again + 1] = { topic, data }
		return
	end
	local now = GetTime()
	tokens, at = math.min(FEED_BURST, tokens + (now - at) * FEED_RATE), now
	if tokens >= 1 and WB:Emit(topic, data) then
		tokens = tokens - 1
	else
		dropped[topic] = (dropped[topic] or 0) + 1
	end
end

if WB then
	C_Timer.NewTicker(0.25, function()
		while again[1] and WB:Emit(again[1][1], again[1][2]) do table.remove(again, 1) end
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
	WB:Expose("kit.propose", function(a)
		a = type(a) == "table" and a or {}
		local steps = {}
		for i, s in ipairs(type(a.steps) == "table" and a.steps or {}) do
			steps[i] = type(s) == "table" and { s.cap or s[1], s.args or s[2] } or s
		end
		return Kit:Propose(steps, { source = "agent", title = a.title, ttl = a.ttl, after = a.after })
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
