-- An extension: one object per id, made by WuxianKit:Extension(id, info) when its file runs (its other files get it with
-- WuxianKit:Extension(id), no info). What it declares
-- (capabilities and scopes, game events, timers, feeds; Kinds.lua) is kept on it and goes live when the core turns it
-- on: the built-in ones when the core's saved variables come, another addon's once its files have run, each unless the
-- player turned it off (WuxianKitDB.off[id]). Turned off from the window, it stops at once: its game events are no
-- longer handed to it, its timers and feeds stop, its capabilities refuse calls, its proposals not run yet go; what its
-- proposals changed stays (the history undoes it), what it made of the UI stays until a reload. Its storage is
-- WuxianKitDB.ext[id], info.defaults filled in.
--   info: { title, version, notes, addon, docs, defaults = {...}, setup(self) when it goes on, teardown(self) when it
--           goes off }; docs: the folder (in its addon's) of its AGENT.md and skills/ for the agent (Agent access spec)
--   ext:On(event, fn(self, event, ...))   a game event, handed over while it is on
--   ext:Every(seconds, fn(self))           a timer, running while it is on
--   ext:Emit(topic, data)                  the bus event "<id>.<topic>" (and so an agent event)
--   ext:Event(topic, { doc, data })        declares one it emits, for the agent's manifest (data: field -> spec text)
--   ext:Tell(text)                         a chat line for the player, under its title
--   ext:Status(fn(self)), ext:Button(label, fn(self))   a line and buttons on its page in the window
--   ext:Option(name, { title, kind = "boolean" | "text", default, hint, changed(self, value) })   a choice the player
--                                          makes on its page, and only there: no capability reads or changes it;
--                                          ext:Get(name) is its value (a who-may-send list, an opt-in)
--   ext:Command(word, fn(self, rest), help)  "/wk <word> ..." runs fn while it is on; /wk help lists it
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
	ns.Changed("extension", ext)
	Kit:Emit("kit.extension", { id = ext.id, on = true })
end

function ns.Disable(ext)
	if not ext.active or ext.id == "kit" then return end
	for _, name in ipairs(ext.feedOrder) do ns.FeedStop(ext.feeds[name], true, true) end
	ext.active = false
	for _, name in ipairs(ext.capOrder) do caps[ext.caps[name].id] = nil end
	if ns.ForgetExtension then ns.ForgetExtension(ext) end
	for _, t in ipairs(ext.timers) do
		if t.ticker then t.ticker:Cancel() end
		t.ticker = nil
	end
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
		ext = setmetatable({ id = id, caps = {}, capOrder = {}, scopes = {}, scopeOrder = {}, timers = {}, feeds = {},
			feedOrder = {}, options = {}, optionOrder = {}, emits = {}, emitOrder = {}, builtin = not started }, Extension)
		extensions[id] = ext
		order[#order + 1] = id
	end
	ext.title, ext.version, ext.notes = info.title or id, info.version, info.notes
	ext.addon = info.addon or (ext.builtin and addonName) or nil
	ext.defaults, ext.setup, ext.teardown, ext.docs = info.defaults, info.setup, info.teardown, info.docs
	ns.Changed("extension", ext)
	if started and not ext.active then                  -- another addon's: on once its files have run
		C_Timer.After(0, function()
			if not ext.active and ns.IsOn(id) then ns.Enable(ext) end
		end)
	end
	return ext
end

function Extension:Scope(name, label)
	local id = self.id .. "." .. name
	if not self.scopes[id] then self.scopeOrder[#self.scopeOrder + 1] = id end
	self.scopes[id] = label or name
	ns.Changed("scope", id)
	return id
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

function Extension:Option(name, spec)
	spec = spec or {}
	if not self.options[name] then self.optionOrder[#self.optionOrder + 1] = name end
	self.options[name] = { name = name, title = spec.title or name, kind = spec.kind == "text" and "text" or "boolean",
		default = spec.default, hint = spec.hint, changed = spec.changed }
	ns.Changed("option", self)
end

function Extension:Get(name)
	local saved = type(self.db) == "table" and self.db.options
	if type(saved) == "table" and saved[name] ~= nil then return saved[name] end
	local o = self.options[name]
	return o and o.default
end

-- the player set an option in the window (the only way one changes)
function ns.SetOption(ext, name, value)
	local o = ext.options[name]
	if not o then return false end
	ext.db = ext.db or Storage(ext)
	ext.db.options = type(ext.db.options) == "table" and ext.db.options or {}
	if o.kind == "text" then value = tostring(value or "") else value = value and true or false end
	ext.db.options[name] = value
	if o.changed then ns.Safe(o.changed, ext, value) end
	return true
end

local commands = {}                       -- word -> { ext, fn, help }

function Extension:Command(word, fn, help)
	if type(word) ~= "string" or not word:match("^%a+$") then error("ext:Command(word, fn, help): word is letters", 2) end
	commands[word:lower()] = { ext = self, fn = fn, help = help }
end

function ns.Commands() return commands end

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
