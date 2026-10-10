-- What an extension can do: capabilities of five kinds, and two patterns built on them.
--   ext:See(name, spec)    Read (读取) reads the game: run(self, args) answers at once
--   ext:Keep(name, spec)   Store (存储) keeps data on this computer: run(self, args) answers at once
--   ext:Point(name, spec)  Guide (指引) points at something for the player to do (a highlight, a waypoint): run,
--                          changes nothing
--   ext:Say(name, spec)    Send (发送) sends a message: a proposal; apply(self, args); held while chat is locked down
--   ext:Do(name, spec)     Change (更改) changes the game: a proposal; apply(self, args); snapshot(self, args) taken
--                          before it makes it undoable (restore(self, snapshot), or apply of the snapshot); held in combat
-- A preview shows what it would do: everything of it that comes from the args goes through WuxianKit:Escape.
-- A spec: title (the player's words), doc (the agent's), args ({ name = spec }, Schema.lua), and for a proposal scope (a
-- name of the extension's scopes, or function(self, args)), check(self, args) -> why it cannot be (refused at once),
-- preview(self, args) -> a line or lines, ready(self, args) -> why it cannot run now (Run stays off), combat = true for
-- a Do that may run in combat, settled(self, args, result) -> true once the game shows what apply asked for (the
-- client does some things a moment later: a macro, a talent loadout, gear; asked every 0.1 s for settleTime, 5 s, or
-- the step fails), reload = true for a change that takes effect after a reload, notes = false for a Do whose preview
-- needs no word from the core (it cannot be undone, a reload). run(self, args, opts) gets the call's options too
-- (source, title, ttl, after).
--   ext:Setting(name, spec)  a value the game keeps: <name>.get (See) and <name>.set (Do) from get / set
--   ext:Feed(name, spec)     game events heard for a while: <name> (start), <name>.stop, <name>.status (See), and the
--                            bus event <ext>.<spec.event> for each event it reads
-- WuxianKit:Call(id, args, opts) does one; WuxianKit:Propose(steps, opts) bundles Say / Do steps into one proposal.
local _, ns = ...
local Kit, L, Schema, Extension = ns.Kit, ns.L, ns.Schema, ns.Extension

local function ChatLocked()
	if C_ChatInfo and C_ChatInfo.InChatMessagingLockdown and C_ChatInfo.InChatMessagingLockdown() then return L.LOCKDOWN end
end

-- what a kind brings by itself: a proposal, waiting for the end of combat, a reason it cannot run now
local KINDS = {
	see = {}, keep = {}, point = {},
	say = { proposed = true, ready = ChatLocked },
	["do"] = { proposed = true, peace = true },
}
ns.KINDS = KINDS

local function Declare(ext, kind, name, spec)
	if type(name) ~= "string" or not name:match("^[a-z][a-z0-9_.]*$") then
		error(("%s: a capability's name is lowercase letters, digits, _ and ."):format(ext.id), 3)
	end
	if type(spec) ~= "table" then error(("%s.%s: its spec is a table"):format(ext.id, name), 3) end
	local id = ext.id .. "." .. name
	if #id > ns.NAME_MAX then error(("%s: a capability's id is at most %d bytes"):format(id, ns.NAME_MAX), 3) end
	local args, argText = Schema.Parse(spec.args)
	local cap = { id = id, ext = ext, name = name, kind = kind, title = spec.title or name, doc = spec.doc or "",
		args = args, argText = argText, spec = spec }
	if KINDS[kind].proposed then
		if type(spec.apply) ~= "function" then error(("%s: a %s capability has apply(self, args)"):format(id, kind), 3) end
		cap.undoable = kind == "do" and type(spec.snapshot) == "function" or nil
	elseif type(spec.run) ~= "function" then
		error(("%s: a %s capability has run(self, args)"):format(id, kind), 3)
	else
		cap.proposes = spec.proposes and true or nil     -- runs at once and answers with a proposal (tune.profile.apply)
	end
	if not ext.caps[name] then ext.capOrder[#ext.capOrder + 1] = name end
	ext.caps[name] = cap
	if ext.active then
		ns.caps[id] = cap
		ns.Changed("capability", cap)
	end
	return cap
end

function Extension:See(name, spec) return Declare(self, "see", name, spec) end
function Extension:Keep(name, spec) return Declare(self, "keep", name, spec) end
function Extension:Point(name, spec) return Declare(self, "point", name, spec) end
function Extension:Say(name, spec) return Declare(self, "say", name, spec) end
function Extension:Do(name, spec) return Declare(self, "do", name, spec) end

-- the scope a step falls under: the extension's scope its spec names, else the capability's own id
function ns.ScopeOf(cap, args)
	local s = cap.spec.scope
	if type(s) == "function" then
		local ok, v = pcall(s, cap.ext, args)
		s = ok and v or nil
	end
	if type(s) == "string" and s ~= "" then return cap.ext.id .. "." .. s end
	return cap.id
end

function ns.ScopeLabel(id)
	for _, eid in ipairs(ns.order) do
		local label = ns.extensions[eid].scopes[id]
		if label then return label end
	end
	return id
end

------------------------------------------------------------------------------------------------------------------------
-- Setting(name, spec): a value the game keeps, named by `key` (the args that name one: { name = "string" }) and set to
-- `value` (a spec, "any" by default; an optional one, "string?": no value removes it). From get(self, key) and
-- set(self, key, value) the core makes
--   <name>.get  (See)  { value, ...info(self, key) }
--   <name>.set  (Do)   the preview "label: old → new" (and explain(self, key, value) under it), the old value as the
--                      snapshot, the value read back after set (a value the game did not keep fails the step), undo = the old one
-- More of the spec: title / titleGet, doc (what the setting is: both docs have it), change (what only changing it
-- involves, for .set's doc: what no value does, limits, that the game shows it later), scope, check(self, key, reading) -> why it cannot be
-- changed (or read, when reading), validate(self, key, value) -> why it cannot take that value, normalize(self, value,
-- key) -> the value as the game keeps it, label(self, key), format(self, value, key) -> how a value reads (none reads as
-- such), info(self, key) -> more fields for .get, same(a, b) -> whether two match; settle = true when the game shows a
-- change a moment later (read back until it does, settleTime); keep(self, key) -> what else undo needs, and
-- restore(self, key, value, kept) puts it all back (else set does); reload = true (or reload(self, key) -> true) when it
-- takes effect after a reload. A value it already has previews as unchanged and its step leaves the game alone, unless
-- always = true (talents: loading the loadout in use again drops its unsaved edits). A step's result is {value}, or
-- {none = true} when the setting is left without one.

local function Same(a, b)
	local x, y = tonumber(a), tonumber(b)
	if x and y then return math.abs(x - y) < 1e-6 end
	return a == b
end

function Extension:Setting(name, spec)
	local keys = {}
	for k in pairs(spec.key or {}) do keys[#keys + 1] = k end
	table.sort(keys)
	local function Key(a)
		local k = {}
		for _, n in ipairs(keys) do k[n] = a[n] end
		return k
	end
	local function Value(self, v, k)
		if spec.normalize then return spec.normalize(self, v, k) end
		return v
	end
	local function Shown(self, v, k)                      -- (a spec's format escapes what it shows of v itself)
		if v == nil then return L.NONE end
		if spec.format then return spec.format(self, v, k) end
		return ns.Escape(v)
	end
	local function Result(v) return { value = v, none = v == nil or nil } end
	local function Matches(a, b) return (spec.same or Same)(a, b) end
	local function Label(self, k)                         -- (so does a spec's label)
		if spec.label then return spec.label(self, k) end
		local parts = {}
		for _, n in ipairs(keys) do parts[#parts + 1] = ns.Escape(k[n]) end
		if #parts == 0 then return ns.T(spec.title) or name end    -- one value, no key: its title names it
		return table.concat(parts, " ")
	end
	local getArgs, setArgs = {}, { value = spec.value or "any" }
	for k, v in pairs(spec.key or {}) do getArgs[k], setArgs[k] = v, v end
	self:See(name .. ".get", { title = spec.titleGet or spec.title, args = getArgs,
		doc = ("reads %s: answers {value}%s ({none = true} when it has no value)"):format(spec.doc or name,
			spec.info and " and more fields about it" or ""),
		run = function(self, a)
			local why = spec.check and spec.check(self, a, true)
			if why then error(("%s.%s.get: %s"):format(self.id, name, why), 0) end
			local out = spec.info and spec.info(self, a) or {}
			out.value = spec.get(self, a)
			if out.value == nil then out.none = true end      -- else an empty answer reads as a list to the agent
			return out
		end })
	local function Kept(self, k, v)                       -- the game has v now, or an error that says what it has
		local now = spec.get(self, k)
		if not Matches(now, v) then error(("the game kept %s at %s"):format(Label(self, k), Shown(self, now, k)), 0) end
		return now
	end
	local reload = spec.reload
	if type(reload) == "function" then reload = function(self, a) return spec.reload(self, Key(a)) end end
	return self:Do(name .. ".set", { title = spec.title, args = setArgs, reload = reload, settleTime = spec.settleTime,
		scope = spec.scope and function(self, a)
			if type(spec.scope) == "function" then return spec.scope(self, Key(a)) end
			return spec.scope
		end,
		doc = ("proposes to change %s%s; the old value is kept, so the change can be undone"):format(spec.doc or name,
			spec.change and ("; " .. spec.change) or ""),
		check = function(self, a)
			local k = Key(a)
			local why = spec.check and spec.check(self, k)
			if why then return why end
			return spec.validate and spec.validate(self, k, Value(self, a.value, k))
		end,
		preview = function(self, a)
			local k = Key(a)
			local v = Value(self, a.value, k)
			local now = spec.get(self, k)
			local lines = { not spec.always and Matches(now, v) and L.UNCHANGED:format(Label(self, k), Shown(self, v, k))
				or L.CHANGE:format(Label(self, k), Shown(self, now, k), Shown(self, v, k)) }
			local more = spec.explain and spec.explain(self, k, v)
			for line in (more and ns.Text(more) .. "\n" or ""):gmatch("([^\r\n]*)\r?\n") do   -- a line each, escaped
				if line ~= "" then lines[#lines + 1] = "|cff9c9ea6" .. ns.Escape(line) .. "|r" end
			end
			return lines
		end,
		snapshot = function(self, a)                          -- the key's args, value = the old one, kept = keep's
			local snap = Key(a)
			snap.value = spec.get(self, snap)
			if spec.keep then snap.kept = spec.keep(self, Key(a)) end
			return snap
		end,
		apply = function(self, a)
			local k = Key(a)
			local v = Value(self, a.value, k)
			if not spec.always and Matches(spec.get(self, k), v) then   -- (a profile's step that agrees)
				local out = Result(v)
				out.unchanged = true
				return out
			end
			spec.set(self, k, v)
			if spec.settle then return Result(v) end         -- read back once it shows (settled)
			return Result(Kept(self, k, v))
		end,
		settled = spec.settle and function(self, a)
			local k = Key(a)
			local v = Value(self, a.value, k)
			local now = spec.get(self, k)
			if Matches(now, v) then return true end
			return false, ("the game shows %s at %s"):format(Label(self, k), Shown(self, now, k))
		end or nil,
		restore = function(self, snap)
			local k = Key(snap)
			if spec.restore then spec.restore(self, k, snap.value, snap.kept) else spec.set(self, k, snap.value) end
			if not spec.settle then Kept(self, k, snap.value) end
		end })
end

------------------------------------------------------------------------------------------------------------------------
-- Feed(name, spec): game events heard for a while. The core makes
--   <name>          (See)  start, with the spec's options and `minutes` (spec.minutes, 60; at most spec.most, 720);
--                          starting again replaces what was heard
--   <name>.stop     (See)  stop
--   <name>.status   (See)  { on, ends, ...options }
-- and while it runs (kept in the extension's storage, so through a /reload, until it ends) each of spec.events that
-- read(self, event, ...) turns into data, and accept(self, options, data) lets through, is the bus event
-- <ext>.<spec.event> (the feed's name when the spec gives no event). More of the spec: title, doc, options ({ name =
-- spec }), prepare(self, options) -> the options to keep (or an error), describe(self, options) -> what the window and
-- the chat line say it hears. The window shows a running feed with a stop button; the player hears when it starts and
-- stops (by itself too, when its time is up); the bus says so ("kit.feed"). A feed is the character's that started it:
-- another character logging in neither hears through it nor stops it.

local function Me()
	return UnitGUID and UnitGUID("player") or nil
end

local function FeedState(feed)
	local db = feed.ext.db
	local s = db and type(db.feeds) == "table" and db.feeds[feed.name]
	if type(s) == "table" and s.ends and s.ends > time() and s.who == Me() then return s end
end
ns.FeedState = FeedState

local function FeedText(feed, s)
	local ok, text = true, ""
	if feed.spec.describe then ok, text = pcall(feed.spec.describe, feed.ext, s.options) end
	return ok and ns.Text(text) or ""
end
ns.FeedText = FeedText

-- stops a feed of this character's; quiet: no chat line; any: whoever started it (its extension is going off)
function ns.FeedStop(feed, quiet, any)
	local db = feed.ext.db
	local s = db and type(db.feeds) == "table" and db.feeds[feed.name]
	if type(s) ~= "table" or not (any or s.who == Me()) then return end
	db.feeds[feed.name] = nil
	if not quiet then feed.ext:Tell(L.FEED_STOPPED:format(ns.T(feed.spec.title) or feed.name)) end
	Kit:Emit("kit.feed", { extension = feed.ext.id, feed = feed.name, on = false })
end

local function Status(feed)
	local s = FeedState(feed)
	local out = { on = s ~= nil, ends = s and s.ends or nil }
	for k, v in pairs(s and s.options or {}) do out[k] = v end
	return out
end

function Extension:Feed(name, spec)
	if type(spec) ~= "table" or type(spec.read) ~= "function" then
		error(("%s.%s: a feed's spec has read(self, event, ...)"):format(self.id, ns.Text(name)), 2)
	end
	local feed = { ext = self, name = name, spec = spec, id = self.id .. "." .. name }
	if not self.feeds[name] then self.feedOrder[#self.feedOrder + 1] = name end
	self.feeds[name] = feed
	local topic = spec.event or name
	for _, event in ipairs(spec.events or {}) do
		self:On(event, function(self, ev, ...)
			local s = FeedState(feed)
			if not s then return end
			local data = spec.read(self, ev, ...)
			if data ~= nil and (not spec.accept or spec.accept(self, s.options, data)) then self:Emit(topic, data) end
		end)
	end
	local args = { minutes = "number?" }
	for k, v in pairs(spec.options or {}) do args[k] = v end
	local title = spec.title or name
	self:Event(topic, { doc = spec.eventDoc or spec.doc, data = spec.data })
	self:See(name, { title = title, args = args,
		doc = ("starts a feed that %s, for `minutes` (default %d, at most %d); calling it again replaces the running "
			.. "one. Each item is the event %s.%s: read it with the events tool (addon \"WuxianKit\", topic \"%s.%s\")"):format(
			spec.doc or name, spec.minutes or 60, spec.most or 720, self.id, topic, self.id, topic),
		run = function(self, a)
			local o = {}
			for k in pairs(spec.options or {}) do o[k] = a[k] end
			if spec.prepare then o = spec.prepare(self, o) end
			local minutes = tonumber(a.minutes)
			minutes = math.max(1, math.min(ns.Finite(minutes) and minutes or spec.minutes or 60, spec.most or 720))
			self.db.feeds = type(self.db.feeds) == "table" and self.db.feeds or {}
			local s = { options = o, ends = time() + math.floor(minutes * 60), who = Me() }
			self.db.feeds[name] = s
			self:Tell(L.FEED_STARTED:format(ns.T(title), FeedText(feed, s), date("%H:%M", s.ends)))
			Kit:Emit("kit.feed", { extension = self.id, feed = name, on = true, ends = s.ends, options = o })
			return Status(feed)
		end })
	self:See(name .. ".stop", { title = function() return L.STOP .. " · " .. ns.T(title) end,
		doc = ("stops the feed %s.%s; answers its status"):format(self.id, name),
		run = function()
			ns.FeedStop(feed)
			return Status(feed)
		end })
	self:See(name .. ".status", { title = title, doc = "answers whether the feed runs: {on, ends (Unix time), and its options}",
		run = function() return Status(feed) end })
	return feed
end

-- every few seconds: a feed of this character's whose time is up stops (the player and the bus hear it); one kept from
-- before feeds were a character's goes quietly
C_Timer.NewTicker(5, function()
	local now, me = time(), Me()
	if not me then return end
	for _, eid in ipairs(ns.order) do
		local ext = ns.extensions[eid]
		local feeds = ext.active and type(ext.db) == "table" and type(ext.db.feeds) == "table" and ext.db.feeds
		for _, name in ipairs(feeds and ext.feedOrder or {}) do
			local s = feeds[name]
			if type(s) == "table" and s.who == nil then
				feeds[name] = nil
			elseif type(s) == "table" and s.who == me and (tonumber(s.ends) or 0) <= now then
				ns.FeedStop(ext.feeds[name])
			end
		end
	end
end)

------------------------------------------------------------------------------------------------------------------------
-- calls

-- does capability `id`: a See / Keep / Point answers at once, a Say / Do answers with its proposal (Proposals.lua).
-- opts: { source = "agent" | "addon:<name>" | "rule:<name>" | "remote:<player>", title, ttl = seconds it waits for the
-- player (10..600, 300), after = the time() before which it may not run }
function Kit:Call(id, args, opts)
	local cap = ns.caps[id]
	if not cap then
		error(("no capability %s (WuxianKit:Capabilities() lists them; its extension may be off)"):format(ns.Text(id)), 2)
	end
	local a = Schema.Check(cap, args)
	if KINDS[cap.kind].proposed then return ns.Propose({ { cap = cap, args = a } }, opts) end
	return cap.spec.run(cap.ext, a, type(opts) == "table" and opts or {})
end

-- why a Say / Do step would be refused if it were proposed now (its args, then its capability's check), or nil: a dry
-- run, nothing is proposed
function Kit:Check(id, args)
	local cap = ns.caps[id]
	if not cap then return ("no capability %s (its extension may be off)"):format(ns.Text(id)) end
	local ok, a = pcall(Schema.Check, cap, args)
	if not ok then return ns.Text(a) end
	if type(cap.spec.check) ~= "function" then return nil end
	local fine, why = pcall(cap.spec.check, cap.ext, a)
	if not fine or why then return ns.Text(why) end
end

-- one proposal of several Say / Do steps, each { "<capability>", args } (or { cap = ..., args = ... }), confirmed once
function Kit:Propose(steps, opts)
	if type(steps) ~= "table" or #steps == 0 then error("WuxianKit:Propose(steps, opts): steps is a list of { id, args }", 2) end
	local list = {}
	for i, s in ipairs(steps) do
		if type(s) ~= "table" then error(("step %d is { id, args }"):format(i), 2) end
		local id, args = s[1] or s.cap, s[2] or s.args
		local cap = ns.caps[id]
		if not cap then error(("step %d: no capability %s"):format(i, ns.Text(id)), 2) end
		if not KINDS[cap.kind].proposed then
			error(("step %d: %s is a %s capability; a proposal holds Say and Do ones"):format(i, id, cap.kind), 2)
		end
		list[i] = { cap = cap, args = Schema.Check(cap, args) }
	end
	return ns.Propose(list, opts)
end

local function About(c)
	local args = {}
	for k, s in pairs(c.args) do args[k] = s.text end
	return { id = c.id, kind = c.kind, title = ns.T(c.title), doc = c.doc, args = args, undoable = c.undoable,
		proposes = c.proposes }
end

-- every live capability: { id, kind, title, doc, args = { name = spec text }, undoable, proposes }, extension by extension
function Kit:Capabilities()
	local out = {}
	for _, eid in ipairs(ns.order) do
		local ext = ns.extensions[eid]
		if ext.active then
			for _, name in ipairs(ext.capOrder) do out[#out + 1] = About(ext.caps[name]) end
		end
	end
	return out
end

-- a live capability as Capabilities lists it, or nil
function Kit:Capability(id)
	local c = ns.caps[id]
	return c and About(c) or nil
end

------------------------------------------------------------------------------------------------------------------------
-- the manifest (the Agent access spec): what 无限工坊's app turns into MCP tools, docs and prompts. protocol, the core's
-- version, the language, every extension (the core first) with its state and docs (the folder under Interface\AddOns
-- of its AGENT.md and skills/); the capabilities and events of those that are on; a revision that changes whenever any
-- of it does (kit.changed tells it half a second after a change, with whatever changed in that half second)

ns.PROTOCOL = 1

local function Hash(s)                                   -- djb2, 8 hex digits
	local h = 5381
	for i = 1, #s do h = (h * 33 + s:byte(i)) % 4294967296 end
	return ("%08x"):format(h)
end

local function Specs(t)                                  -- {name = spec text} in one sorted line
	local out = {}
	for k, v in pairs(type(t) == "table" and t or {}) do out[#out + 1] = tostring(k) .. "=" .. tostring(v) end
	table.sort(out)
	return table.concat(out, ",")
end

local function Revision(m)
	local parts = { m.protocol, m.kit or "", m.language }
	for _, e in ipairs(m.extensions) do
		parts[#parts + 1] = table.concat({ e.id, e.version or "", e.state, e.title or "", e.docs or "" }, "\1")
		for _, c in ipairs(e.capabilities or {}) do
			parts[#parts + 1] = table.concat({ c.id, c.kind, c.title or "", c.doc, Specs(c.args), tostring(c.undoable),
				tostring(c.proposes) }, "\1")
		end
		for _, v in ipairs(e.events or {}) do parts[#parts + 1] = table.concat({ v.topic, v.doc, Specs(v.data) }, "\1") end
	end
	return Hash(table.concat(parts, "\2"))
end

function Kit:Manifest()
	local installed = ns.Installed()
	local m = { protocol = ns.PROTOCOL, kit = Kit.VERSION, language = ns.Lang(), extensions = {} }
	for _, e in ipairs(ns.ExtensionList()) do
		local ext = ns.extensions[e.id]
		local addon = e.addon or (installed[e.id] or {}).addon
		local entry = { id = e.id, title = e.title, version = e.version, addon = addon, builtin = e.builtin, state = e.state }
		if addon then entry.docs = ext and ext.docs and ext.docs ~= "" and (addon .. "/" .. ext.docs) or addon end
		if ext and ext.active then
			entry.capabilities, entry.events = {}, {}
			for _, name in ipairs(ext.capOrder) do entry.capabilities[#entry.capabilities + 1] = About(ext.caps[name]) end
			for _, topic in ipairs(ext.emitOrder) do
				local v = ext.emits[topic]
				entry.events[#entry.events + 1] = { topic = v.topic, doc = v.doc, data = v.data }
			end
		end
		m.extensions[#m.extensions + 1] = entry
	end
	m.revision = Revision(m)
	return m
end

local announced, pending                                -- the revision told last; a look on its way

local function Announce()
	pending = false
	local revision = Kit:Manifest().revision
	if revision ~= announced then
		announced = revision
		Kit:Emit("kit.changed", { revision = revision })
	end
end

-- the revision kit.ready carries (after a login or reload); from then on every change is told by kit.changed
function ns.ManifestReady()
	announced = Kit:Manifest().revision
	return announced
end

ns.OnChange(function()
	if announced and not pending then
		pending = true
		C_Timer.After(0.5, Announce)
	end
end)
