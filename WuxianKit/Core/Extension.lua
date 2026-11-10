-- An extension: one object per id, made by WuxianKit:Extension(id, info) when its file runs (its other files get it with
-- WuxianKit:Extension(id), no info). What it declares (capabilities and scopes, Kinds.lua; game events, timers, the
-- sources apps hear) is kept on it and goes live when the core turns it on: the built-in ones when the core's saved
-- variables come, another addon's once its files have run, each unless the player turned it off (WuxianKitDB.off[id]).
-- Turned off from the window, it stops at once: its game events are no longer handed to it, its timers stop, its
-- capabilities refuse calls, apps hear nothing of its sources (and one that hears them cannot start, Apps.lua), its
-- proposals not run yet go; what its proposals changed stays (the history undoes it), what it made of the UI stays until
-- a reload. Its storage is WuxianKitDB.ext[id], info.defaults filled in.
--   info: { title, version, notes, addon, docs, prompt, defaults = {...}, setup(self) when it goes on, teardown(self)
--           when it goes off }; docs: the folder (in its addon's) of its AGENT.md and skills/ for the agent (Agent access
--           spec); prompt: the name of one of its skills (ext.prompt; kept for the workshop, no button: an app's
--           card hands its start line to an AI)
--   ext:On(event, fn(self, event, ...))   a game event, handed over while it is on
--   ext:Every(seconds, fn(self))           a timer, running while it is on
--   ext:Emit(topic, data)                  the bus event "<id>.<topic>" (and so an agent event)
--   ext:Event(topic, { doc, data })        declares one it emits, for the agent's manifest (data: field -> spec text)
--   ext:Char()                             its storage for this character (ext.db.chars[GUID]), made when asked
--   ext:Tell(text)                         a chat line for the player, under its title
--   ext:Status(fn(self)), ext:Button(label, fn(self))   a line and buttons on its page in the window
--   ext:Scope(name, title | { title, budget = { per, most } })   a category the player may let go without asking;
--                                          name may have dots (guild.reply); budget: the limit suggested when it is
--                                          ticked (ns.ScopeBudget)
--   ext:Option(name, { title, kind, default, hint, changed(self, value), ... })   a choice the player makes on its page
--                                          (or an OptionsPanel), and only there: kit.options reads them, nothing else
--                                          changes them; ext:Get(name) is its value (a list: a copy). kind: boolean (the
--                                          default), text, number { min, max, step = 1, unit }, choice { choices =
--                                          { { value, label } ... } }, list (strings: split at , ， 、, trimmed, none
--                                          empty or twice, at most 20 of at most 32 bytes); a change calls changed and
--                                          emits kit.option { extension, name, value }
--   ext:Command(word, fn(self, rest), help)  "/wk <word> ..." runs fn while it is on; /wk help lists it
--   ext:Source(name, spec) -> source       what apps hear: the hear entries <name>:<what> (see "sources" below)
--   ext:Facet(name, spec) -> facet         what apps see: a state each of their wakes carries (see "facets" below)
local addonName, ns = ...
local Kit, L = ns.Kit, ns.L

local Extension = {}
Extension.__index = Extension
ns.Extension = Extension

local extensions, order, caps = {}, {}, {}        -- id -> extension; ids as defined; "<id>.<name>" -> live capability
ns.extensions, ns.order, ns.caps = extensions, order, caps
local started = false                             -- the built-in ones went on: one defined later goes on by itself
local handlers = {}                               -- game event -> { { ext, fn } }

local frame = CreateFrame("Frame")
frame:SetScript("OnEvent", function(_, event, ...)
	for _, h in ipairs(handlers[event] or {}) do
		if h.ext.active then ns.Safe(h.fn, h.ext, event, ...) end
	end
end)

-- why an addon cannot load, in the client's own words (ADDON_DEP_MISSING ...), else its code
function ns.ReasonText(reason)
	local text = type(reason) == "string" and _G["ADDON_" .. reason]
	return type(text) == "string" and text or ns.Text(reason)
end

-- whether the player left extension `id` on (the core itself always is)
function ns.IsOn(id)
	return id == "kit" or not (ns.db and ns.db.off and ns.db.off[id])
end

local function Copy(v)
	if type(v) ~= "table" then return v end
	local t = {}
	for k, x in pairs(v) do t[k] = Copy(x) end
	return t
end

local function Storage(ext)
	local db = ns.db
	if not db then return ext.db or {} end
	db.ext = type(db.ext) == "table" and db.ext or {}
	local t = type(db.ext[ext.id]) == "table" and db.ext[ext.id] or {}
	db.ext[ext.id] = t
	for k, v in pairs(ext.defaults or {}) do
		if t[k] == nil then t[k] = Copy(v) end
	end
	return t
end

------------------------------------------------------------------------------------------------------------------------
-- on and off

local function Start(ext, t)
	t.ticker = C_Timer.NewTicker(t.seconds, function()
		if ext.active then ns.Safe(t.fn, ext) end
	end)
end

function ns.Enable(ext)
	if ext.active then return end
	ext.db = Storage(ext)
	ext.active = true
	for _, name in ipairs(ext.capOrder) do
		local cap = ext.caps[name]
		caps[cap.id] = cap
		ns.Changed("capability", cap)
	end
	for _, t in ipairs(ext.timers) do Start(ext, t) end
	if ext.setup then ns.Safe(ext.setup, ext) end
	ns.FacetsLive(ext, true)                          -- (its facets that apps look at: on)
	ns.Changed("extension", ext)
	Kit:Emit("kit.extension", { id = ext.id, on = true })
end

function ns.Disable(ext)
	if not ext.active or ext.id == "kit" then return end
	ext.active = false
	for _, name in ipairs(ext.capOrder) do caps[ext.caps[name].id] = nil end
	if ns.ForgetExtension then ns.ForgetExtension(ext) end
	for _, t in ipairs(ext.timers) do
		if t.ticker then t.ticker:Cancel() end
		t.ticker = nil
	end
	ns.FacetsLive(ext, false)                         -- (its facets' off, before its teardown)
	if ext.teardown then ns.Safe(ext.teardown, ext) end
	ns.Changed("extension", ext)
	Kit:Emit("kit.extension", { id = ext.id, on = false })
end

------------------------------------------------------------------------------------------------------------------------
-- defining one

function Kit:Extension(id, info)
	if type(id) ~= "string" or not id:match("^[a-z][a-z0-9_]*$") then
		error("WuxianKit:Extension(id, info): id is lowercase letters, digits and _", 2)
	end
	local ext = extensions[id]
	if ext and info == nil then return ext end           -- another file of an extension defined before
	info = info or {}
	if not ext then
		ext = setmetatable({ id = id, caps = {}, capOrder = {}, scopes = {}, scopeOrder = {}, timers = {},
			sourceOrder = {}, facetOrder = {}, options = {}, optionOrder = {}, emits = {}, emitOrder = {}, budgets = {}, builtin = not started },
			Extension)
		extensions[id] = ext
		order[#order + 1] = id
	end
	ext.title, ext.version, ext.notes = info.title or id, info.version, info.notes
	ext.addon = info.addon or (ext.builtin and addonName) or nil
	ext.defaults, ext.setup, ext.teardown, ext.docs = info.defaults, info.setup, info.teardown, info.docs
	ext.prompt = type(info.prompt) == "string" and info.prompt ~= "" and info.prompt or nil
	ns.Changed("extension", ext)
	if started and not ext.active then                  -- another addon's: on once its files have run
		C_Timer.After(0, function()
			if not ext.active and ns.IsOn(id) then ns.Enable(ext) end
		end)
	end
	return ext
end

-- a budget as given: { per = seconds, most = times }, both positive, else nil
local function Budget(b)
	if type(b) ~= "table" then return nil end
	local per, most = tonumber(b.per), tonumber(b.most)
	if not (ns.Finite(per) and ns.Finite(most) and per > 0 and most >= 1) then return nil end
	return { per = per, most = math.floor(most) }
end

function Extension:Scope(name, label)
	local id = self.id .. "." .. name
	local budget
	if type(label) == "table" then label, budget = label.title, Budget(label.budget) end
	if not self.scopes[id] then self.scopeOrder[#self.scopeOrder + 1] = id end
	self.scopes[id] = label or name
	self.budgets = self.budgets or {}
	self.budgets[id] = budget
	ns.Changed("scope", id)
	return id
end

-- the budget a scope's extension suggests for it ({ per, most }, a copy), or nil
function ns.ScopeBudget(scope)
	local ext = type(scope) == "string" and extensions[scope:match("^([^.]+)%.") or ""]
	local b = ext and ext.budgets and ext.budgets[scope]
	return b and { per = b.per, most = b.most } or nil
end

function Extension:On(event, fn)
	if not handlers[event] then
		handlers[event] = {}
		frame:RegisterEvent(event)
	end
	table.insert(handlers[event], { ext = self, fn = fn })
end

function Extension:Every(seconds, fn)
	local t = { seconds = seconds, fn = fn }
	self.timers[#self.timers + 1] = t
	if self.active then Start(self, t) end
end

function Extension:Emit(topic, data)
	return Kit:Emit(self.id .. "." .. topic, data)
end

function Extension:Event(topic, spec)
	if type(topic) ~= "string" or not topic:match("^[a-z][a-z0-9_.]*$") then
		error("ext:Event(topic, spec): topic is lowercase letters, digits, _ and .", 2)
	end
	if #self.id + 1 + #topic > ns.NAME_MAX then
		error(("ext:Event(topic, spec): %s.%s is longer than %d bytes"):format(self.id, topic, ns.NAME_MAX), 2)
	end
	spec = spec or {}
	if not self.emits[topic] then self.emitOrder[#self.emitOrder + 1] = topic end
	self.emits[topic] = { topic = self.id .. "." .. topic, doc = spec.doc or "", data = spec.data }
	ns.Changed("event", self)
end

-- ext:Char(): its storage for this character (ext.db.chars[<player GUID>]), made when first asked; the GUID read in
-- plain text once and remembered (in combat it may be secret)
local myGUID
function Extension:Char()
	if not myGUID then
		local g = UnitGUID and Kit:Value(UnitGUID("player"))
		if type(g) == "string" and g ~= "" then myGUID = g end
	end
	self.db = self.db or Storage(self)
	self.db.chars = type(self.db.chars) == "table" and self.db.chars or {}
	local key = myGUID or "?"
	local t = self.db.chars[key]
	if type(t) ~= "table" then
		t = {}
		self.db.chars[key] = t
	end
	return t
end

function Extension:Tell(text)
	if DEFAULT_CHAT_FRAME then DEFAULT_CHAT_FRAME:AddMessage(("|cffd8a85a[%s]|r %s"):format(ns.T(self.title), text)) end
end

function Extension:Status(fn)
	self.status = fn
end

function Extension:Button(label, fn)
	self.buttons = self.buttons or {}
	self.buttons[#self.buttons + 1] = { label = label, fn = fn }
end

------------------------------------------------------------------------------------------------------------------------
-- options

local KINDS = { boolean = true, text = true, number = true, choice = true, list = true }
local LIST_MOST, ITEM_MOST = 20, 32

-- s cut to at most n bytes, never inside a character (UTF-8)
local function Clip(s, n)
	if #s <= n then return s end
	s = s:sub(1, n)
	local i = #s
	while i > 1 and s:byte(i) >= 128 and s:byte(i) < 192 do i = i - 1 end   -- the last character's first byte
	local lead = s:byte(i)
	local need = lead >= 240 and 4 or lead >= 224 and 3 or lead >= 192 and 2 or 1
	if #s - i + 1 < need then s = s:sub(1, i - 1) end
	return s
end

-- a list from a text (split at , ， 、) or a table of strings: trimmed, none empty or twice, at most LIST_MOST of at
-- most ITEM_MOST bytes
local function List(v)
	local parts = {}
	if type(v) == "string" then
		v = v:gsub("\239\188\140", ","):gsub("\227\128\129", ",")
		for part in (v .. ","):gmatch("([^,]*),") do parts[#parts + 1] = part end
	elseif type(v) == "table" then
		for _, x in ipairs(v) do
			if type(x) == "string" or type(x) == "number" then parts[#parts + 1] = tostring(x) end
		end
	end
	local out, seen = {}, {}
	for _, part in ipairs(parts) do
		local item = Clip(part:match("^%s*(.-)%s*$"), ITEM_MOST):match("^(.-)%s*$")
		if item ~= "" and not seen[item] and #out < LIST_MOST then
			seen[item] = true
			out[#out + 1] = item
		end
	end
	return out
end

-- value as option o keeps it: a number in its range on its step, one of its choices, a list (a new table); what does
-- not fit is the default
local function Normalize(o, value)
	local kind = o.kind
	if kind == "text" then return tostring(value == nil and "" or value) end
	if kind == "number" then
		local v = tonumber(value)
		if not ns.Finite(v) then return o.default end
		local base = o.min or 0
		v = base + math.floor((v - base) / o.step + 0.5) * o.step
		if o.max and v > o.max then v = o.max end
		if o.min and v < o.min then v = o.min end
		return tonumber(("%.10g"):format(v))               -- steps of 0.1 without the float's tail
	end
	if kind == "choice" then
		for _, c in ipairs(o.choices) do
			if c.value == value or (value ~= nil and tostring(c.value) == tostring(value)) then return c.value end
		end
		return o.default
	end
	if kind == "list" then return List(value) end
	return value and true or false
end

local function Same(a, b)
	if type(a) ~= "table" or type(b) ~= "table" then return a == b end
	if #a ~= #b then return false end
	for i = 1, #a do
		if a[i] ~= b[i] then return false end
	end
	return true
end

function Extension:Option(name, spec)
	spec = spec or {}
	local kind = KINDS[spec.kind] and spec.kind or "boolean"
	local o = { name = name, title = spec.title or name, kind = kind, hint = spec.hint, changed = spec.changed }
	if kind == "number" then
		o.min, o.max, o.unit = tonumber(spec.min), tonumber(spec.max), spec.unit
		if o.min and o.max and o.max < o.min then o.min, o.max = o.max, o.min end
		local step = tonumber(spec.step)
		o.step = ns.Finite(step) and step > 0 and step or 1
		o.default = o.min or 0
		o.default = Normalize(o, spec.default)
	elseif kind == "choice" then
		o.choices = {}
		for _, c in ipairs(type(spec.choices) == "table" and spec.choices or {}) do
			if type(c) == "table" then
				local value = c.value
				if value == nil then value = c[1] end
				if value ~= nil then o.choices[#o.choices + 1] = { value = value, label = c.label or c[2] or tostring(value) } end
			end
		end
		o.default = o.choices[1] and o.choices[1].value
		o.default = Normalize(o, spec.default)
	elseif kind == "list" then
		o.default = List(spec.default)
	else
		o.default = spec.default
	end
	if not self.options[name] then self.optionOrder[#self.optionOrder + 1] = name end
	self.options[name] = o
	ns.Changed("option", self)
end

function Extension:Get(name)
	local o = self.options[name]
	local saved
	if type(self.db) == "table" and type(self.db.options) == "table" then saved = self.db.options[name] end
	if saved == nil then saved = o and o.default end
	if o and (o.kind == "number" or o.kind == "choice" or o.kind == "list") then return Normalize(o, saved) end
	return saved
end

-- the player set an option in the window or an OptionsPanel (the only ways one changes): kept as its kind keeps it;
-- a change calls its changed and emits kit.option. true and the value kept, or false (no such option)
function ns.SetOption(ext, name, value)
	local o = ext.options[name]
	if not o then return false end
	ext.db = ext.db or Storage(ext)
	ext.db.options = type(ext.db.options) == "table" and ext.db.options or {}
	local before = ext:Get(name)
	if o.kind == "number" and not ns.Finite(tonumber(value)) then value = before end   -- not a number: as it was
	value = Normalize(o, value)
	ext.db.options[name] = value
	if not Same(before, value) then
		if o.changed then ns.Safe(o.changed, ext, Copy(value)) end
		Kit:Emit("kit.option", { extension = ext.id, name = name, value = Copy(value) })
	end
	return true, Copy(value)
end

-- an extension's options as kit.options answers: name -> { title (in the language in force), kind, value, default,
-- choices ({ value, label }), min, max, unit }
function ns.OptionList(ext)
	local out = {}
	for _, name in ipairs(ext.optionOrder) do
		local o = ext.options[name]
		local e = { title = ns.T(o.title), kind = o.kind, value = ext:Get(name), default = Copy(o.default) }
		if o.hint ~= nil then e.hint = ns.T(o.hint) end
		if o.kind == "number" then
			e.min, e.max = o.min, o.max
			if o.unit ~= nil then e.unit = ns.T(o.unit) end
		elseif o.kind == "choice" then
			e.choices = {}
			for i, c in ipairs(o.choices) do e.choices[i] = { value = c.value, label = ns.T(c.label) } end
		end
		out[name] = e
	end
	return out
end

local commands = {}                       -- word -> { ext, fn, help }

function Extension:Command(word, fn, help)
	if type(word) ~= "string" or not word:match("^%a+$") then error("ext:Command(word, fn, help): word is letters", 2) end
	commands[word:lower()] = { ext = self, fn = fn, help = help }
end

function ns.Commands() return commands end

------------------------------------------------------------------------------------------------------------------------
-- sources: what apps hear (Apps.lua). ext:Source(name, spec) registers the hear entries <name>:<what>. A name is the
-- whole kit's: another extension's of the same name is an error. The same extension's again (a hot reload) replaces it:
-- a new source object, the old one keeps its spec, so a token the old on gave goes to the old off (the apps subscribe
-- again when told). ext:Source(name, nil) takes it back (source.gone). spec:
--   title, doc         doc: what <name>:<what> hears and what an item is (kit.app.open's doc and the manifest show it)
--   values             the known values of what (a list, or a function that gives one), for the docs
--   check(what)        nil when <name>:<what> is an entry it takes, else why not (in the agent's words)
--   covers(a, b)       whether <name>:a hears all that <name>:b does (chat:* covers chat:guild): an app hears b once
--   on(self, what, fn) -> token   subscribes: fn(item) for each item heard, a new table each time (an app writes its
--                      fields on it); off(self, token) unsubscribes; self is the extension
-- (What the player is like now is not on items: an app sees the facet me, below.)
-- An extension that is off keeps its sources registered: an app that hears one cannot start (Apps.lua says why), and
-- one that runs hears nothing of it until it is on again.
-- addon, control and player are the apps' own sources (an item's source) and cannot be registered.
-- ns.sources: name -> { name, ext, spec }; ns.sourceOrder: the names as registered; ns.SourceList(ext) and
-- ns.SourceValues(source) for the manifest and the docs.
-- Told to the apps (ns.OnChange): "source", source when one is registered (ns.sources[source.name] == source),
-- registered again (a new object in its place) or taken back (source.gone, ns.sources[source.name] == nil); "facet",
-- facet the same for facets, below (registered again: the same object); "extension", ext when the extension that owns
-- them goes on or off (ext.active; its names are ext.sourceOrder and ext.facetOrder), then the bus's kit.extension.

local sources, sourceOrder = {}, {}
ns.sources, ns.sourceOrder = sources, sourceOrder
local RESERVED = { addon = true, control = true, player = true }
local SOURCE_MAX = 24

local function Drop(list, name)
	for i, n in ipairs(list) do
		if n == name then return table.remove(list, i) end
	end
end

function Extension:Source(name, spec)
	if type(name) ~= "string" or #name > SOURCE_MAX or not name:match("^[a-z][a-z0-9_]*$") then
		error(("%s: a source's name is lowercase letters, digits and _, at most %d bytes"):format(self.id, SOURCE_MAX), 2)
	end
	if RESERVED[name] then error(("%s: the source name %s is the apps' own"):format(self.id, name), 2) end
	local old = sources[name]
	if old and old.ext ~= self then
		error(("%s: the source %s is extension %s's"):format(self.id, name, old.ext.id), 2)
	end
	if spec == nil then                                 -- taken back: the apps that hear it unsubscribe when told
		if not old then return end
		old.gone, sources[name] = true, nil
		Drop(sourceOrder, name)
		Drop(self.sourceOrder, name)
		ns.Changed("source", old)
		return
	end
	if type(spec) ~= "table" or type(spec.on) ~= "function" or type(spec.off) ~= "function" then
		error(("%s: source %s's spec has on(self, what, fn) and off(self, token)"):format(self.id, name), 2)
	end
	for _, k in ipairs({ "check", "covers" }) do
		if spec[k] ~= nil and type(spec[k]) ~= "function" then
			error(("%s: source %s's %s is a function"):format(self.id, name, k), 2)
		end
	end
	local source = { name = name, ext = self, spec = spec }
	if not old then
		sourceOrder[#sourceOrder + 1] = name
		self.sourceOrder[#self.sourceOrder + 1] = name
	end
	sources[name] = source
	ns.Changed("source", source)
	return source
end

-- a source's known values of what: a list of strings, or nil
function ns.SourceValues(source)
	local v = source.spec.values
	if type(v) == "function" then
		local ok, got = pcall(v)
		v = ok and got or nil
	end
	if type(v) ~= "table" then return nil end
	local out = {}
	for _, x in ipairs(v) do out[#out + 1] = ns.Text(x) end
	return #out > 0 and out or nil
end

-- an extension's sources as the manifest lists them: [{ name, title, doc, values? }]
function ns.SourceList(ext)
	local out = {}
	for _, name in ipairs(ext.sourceOrder) do
		local s = sources[name]
		if s and s.ext == ext then
			out[#out + 1] = { name = name, title = ns.T(s.spec.title) or name, doc = ns.Text(ns.T(s.spec.doc) or ""),
				values = ns.SourceValues(s) }
		end
	end
	return out
end

------------------------------------------------------------------------------------------------------------------------
-- facets: what apps see (Apps.lua), as sources are what they hear. ext:Facet(name, spec) registers a state an app
-- declares in see = { name, ... }: each wake of the app carries state[name] = what read gives at that wake, and
-- kit.app.state reads them at once. A name is the whole kit's, as a source's (a source and a facet may share one: route):
-- another extension's of the same name is an error. The same extension's again (a hot reload) puts the new spec on the
-- same facet: those looking at it still do, each counted once; when it is looked at, the old spec's off is called (it
-- pairs the old on), then the new one's on. ext:Facet(name, nil) takes it back (its off when looked at, facet.gone).
-- spec:
--   title, doc         doc: what the state is (kit.app.open's doc and the manifest show it)
--   fields             optional: field -> type text ({ level = "number", zone = "string?" }), for the docs
--   read(self) -> table|nil   the state now, a small table (nil: none now); one that comes to more than FACET_MAX bytes
--                      as a wake carries it is cut (texts shorten, lists lose their last entries, nested tables go) and
--                      says cut = true
--   on(self), off(self)   optional: the first app that runs and sees it started (turn on what it takes to know it: a
--                      probe, a game event), the last one stopped; off too when its extension goes off, and on again when
--                      it comes back on while one still sees it
-- An extension that is off keeps its facets registered: an app that sees one of them cannot start, and one that runs stops
-- (Apps.lua); read is not called while it is off.
-- ns.facets: name -> { name, ext, spec, watchers = { [who] = true }, n, live (spec.on was called) }; ns.facetOrder: the names as
-- registered; ns.FacetList(ext) for the manifest; ns.FacetWatch(facet, who, on): who (an app) starts or stops looking;
-- ns.FacetRead(facet): the state as a wake carries it.

local facets, facetOrder = {}, {}
ns.facets, ns.facetOrder = facets, facetOrder
local FACET_MAX, FACET_TEXT, FACET_DEPTH = 600, 200, 4
ns.FACET_MAX = FACET_MAX

-- on or off as whether anyone looks and the extension is on (one taken back: off)
local function Live(facet)
	local want = facet.n > 0 and facet.ext.active == true and not facet.gone
	if want == (facet.live == true) then return end
	facet.live = want or nil
	local fn = facet.spec[want and "on" or "off"]
	if fn then ns.Safe(fn, facet.ext) end
end

function Extension:Facet(name, spec)
	if type(name) ~= "string" or #name > SOURCE_MAX or not name:match("^[a-z][a-z0-9_]*$") then
		error(("%s: a facet's name is lowercase letters, digits and _, at most %d bytes"):format(self.id, SOURCE_MAX), 2)
	end
	local facet = facets[name]
	if facet and facet.ext ~= self then
		error(("%s: the facet %s is extension %s's"):format(self.id, name, facet.ext.id), 2)
	end
	if spec == nil then                                 -- taken back
		if not facet then return end
		facet.gone, facets[name] = true, nil
		Live(facet)
		Drop(facetOrder, name)
		Drop(self.facetOrder, name)
		ns.Changed("facet", facet)
		return
	end
	if type(spec) ~= "table" or type(spec.read) ~= "function" then
		error(("%s: facet %s's spec has read(self)"):format(self.id, name), 2)
	end
	for _, k in ipairs({ "on", "off" }) do
		if spec[k] ~= nil and type(spec[k]) ~= "function" then
			error(("%s: facet %s's %s is a function"):format(self.id, name, k), 2)
		end
	end
	if spec.fields ~= nil and type(spec.fields) ~= "table" then
		error(("%s: facet %s's fields is a table (field -> type text)"):format(self.id, name), 2)
	end
	if facet then
		if facet.live then                              -- looked at: the old spec's off, then (Live) the new one's on
			facet.live = nil
			if facet.spec.off then ns.Safe(facet.spec.off, self) end
		end
		facet.spec = spec
	else
		facet = { name = name, ext = self, spec = spec, watchers = {}, n = 0 }
		facets[name] = facet
		facetOrder[#facetOrder + 1] = name
		self.facetOrder[#self.facetOrder + 1] = name
	end
	Live(facet)
	ns.Changed("facet", facet)
	return facet
end

function ns.FacetWatch(facet, who, on)
	if on and not facet.watchers[who] then
		facet.watchers[who], facet.n = true, facet.n + 1
	elseif not on and facet.watchers[who] then
		facet.watchers[who], facet.n = nil, facet.n - 1
	end
	Live(facet)
end

-- an extension went on or off: its facets that apps look at with it (Enable, Disable)
function ns.FacetsLive(ext)
	for _, name in ipairs(ext.facetOrder) do
		local facet = facets[name]
		if facet and facet.ext == ext then Live(facet) end
	end
end

-- a copy of v as a wake may carry it: texts at most `text` bytes, no deeper than FACET_DEPTH, no secret values
local function Plain(v, text, depth)
	v = Kit:Value(v)
	local t = type(v)
	if t == "string" then return ns.Cut(v, text) end
	if t == "number" then return ns.Finite(v) and v or nil end
	if t == "boolean" then return v end
	if t ~= "table" or depth > FACET_DEPTH then return nil end
	local out = {}
	for k, x in pairs(v) do
		if type(k) == "string" or (type(k) == "number" and ns.Finite(k)) then out[k] = Plain(x, text, depth + 1) end
	end
	return out
end

local function Size(v)
	local ok, text = pcall(ns.Comm.Serialize, v)
	return ok and #text or math.huge
end

-- the longest list in t, at any depth (nil when none has an entry), and its length
local function Longest(t, best, n)
	if #t > n then best, n = t, #t end
	for _, x in pairs(t) do
		if type(x) == "table" then best, n = Longest(x, best, n) end
	end
	return best, n
end

-- v cut to FACET_MAX: texts shorten to FACET_TEXT bytes, then lists lose their last entries, then texts shorten more,
-- then nested tables go; cut = true says so
local function Fit(v)
	local out = Plain(v, FACET_MAX, 1)
	if Size(out) <= FACET_MAX then return out end
	local room = FACET_MAX - 12                         -- (for cut = true)
	out = Plain(out, FACET_TEXT, 1)
	while Size(out) > room do
		local list, n = Longest(out, nil, 0)
		if not list then break end
		list[n] = nil
	end
	if Size(out) > room then out = Plain(out, 40, 1) end
	if Size(out) > room then                            -- its top level's plain values alone
		local flat = {}
		for k, x in pairs(out) do
			if type(x) ~= "table" then flat[k] = x end
		end
		out = flat
	end
	if Size(out) > room then out = {} end
	out.cut = true
	return out
end

function ns.FacetRead(facet)
	if not (facet and facet.ext.active) then return nil end
	local ok, v = pcall(facet.spec.read, facet.ext)
	if not ok then
		geterrorhandler()(v)
		return nil
	end
	if type(v) ~= "table" then return nil end
	return Fit(v)
end

-- an extension's facets as the manifest lists them: [{ name, title, doc, fields? }]
function ns.FacetList(ext)
	local out = {}
	for _, name in ipairs(ext.facetOrder) do
		local f = facets[name]
		if f and f.ext == ext then
			local fields
			if type(f.spec.fields) == "table" then
				fields = {}
				for k, v in pairs(f.spec.fields) do
					if type(k) == "string" then fields[k] = ns.Text(v) end
				end
			end
			out[#out + 1] = { name = name, title = ns.T(f.spec.title) or name, doc = ns.Text(ns.T(f.spec.doc) or ""),
				fields = fields }
		end
	end
	return out
end

------------------------------------------------------------------------------------------------------------------------
-- the extensions another addon brings: each addon whose .toc says ## X-WuxianKit-Extension: <id>, loaded or not

function ns.Installed()
	local out = {}
	for i = 1, C_AddOns.GetNumAddOns() do
		local name, title, notes, loadable, reason = C_AddOns.GetAddOnInfo(i)
		local id = name and C_AddOns.GetAddOnMetadata(name, "X-WuxianKit-Extension")
		if id and id ~= "" and name ~= addonName then
			local ok, state = pcall(C_AddOns.GetAddOnEnableState, name, UnitGUID and UnitGUID("player") or nil)  -- the GUID
			out[id] = { id = id, addon = name, title = title, notes = notes, loadable = loadable, reason = reason,
				version = C_AddOns.GetAddOnMetadata(name, "Version"), loaded = C_AddOns.IsAddOnLoaded(name) and true or false,
				enabled = not ok or (tonumber(state) or 0) > 0 }
		end
	end
	return out
end

-- every extension as the window and kit.extensions show it: the core first, then as they were defined, then the
-- installed ones not loaded; state on / off / disabled (in the game's addon list) / missing (cannot load: reason)
function ns.ExtensionList()
	local out, seen = {}, {}
	local installed = ns.Installed()
	for _, id in ipairs(order) do
		local ext = extensions[id]
		out[#out + 1] = { id = id, title = ns.T(ext.title), version = ext.version, addon = ext.addon or (installed[id] or {}).addon,
			builtin = ext.builtin or nil, core = id == "kit" or nil, state = ext.active and "on" or "off",
			capabilities = #ext.capOrder }
		seen[id] = true
	end
	local rest = {}
	for id, e in pairs(installed) do
		if not seen[id] then
			local state = not e.enabled and "disabled" or ((e.loadable or e.reason == "DEMAND_LOADED") and "off") or "missing"
			rest[#rest + 1] = { id = id, title = e.title, version = e.version, addon = e.addon, state = state,
				reason = state == "missing" and e.reason or nil, capabilities = 0 }
		end
	end
	table.sort(rest, function(a, b) return a.id < b.id end)
	for _, e in ipairs(rest) do out[#out + 1] = e end
	return out
end

-- turns extension `id` on or off and remembers it; another addon's that is not loaded is loaded (it goes on once its
-- files have run). true, or false + why not
function ns.Switch(id, on)
	if id == "kit" then return false, "WuxianKit's core stays on" end
	local db = ns.db
	if db then
		db.off = type(db.off) == "table" and db.off or {}
		db.off[id] = (not on) and true or nil
	end
	local ext = extensions[id]
	if not on then
		if ext and ext.active then
			ns.Disable(ext)
			ns.Say(L.EXT_OFF:format(ns.T(ext.title)))
		end
		return true
	end
	if ext then
		if not ext.active then
			ns.Enable(ext)
			ns.Say(L.EXT_ON:format(ns.T(ext.title)))
		end
		return true
	end
	local e = ns.Installed()[id]
	if not e then return false, "not installed" end
	local loaded, reason = C_AddOns.LoadAddOn(e.addon)
	if not loaded then
		ns.Say(L.EXT_LOAD_FAILED:format(e.title or id, ns.ReasonText(reason)))
		return false, reason
	end
	ext = extensions[id]                                -- its files have run by now: on at once
	if ext and not ext.active then ns.Enable(ext) end
	ns.Say(L.EXT_ON:format(e.title or id))
	return true
end

ns.When("load", function()
	started = true
	for _, id in ipairs(order) do
		if ns.IsOn(id) then ns.Enable(extensions[id]) end
	end
end)

ns.When("login", function()
	for id, e in pairs(ns.Installed()) do
		if not e.loaded and e.enabled and ns.IsOn(id) then C_AddOns.LoadAddOn(e.addon) end
	end
end)
