-- The core's own extension, "kit", written as any extension is: what the agent (or another addon) can ask of the core.
--   kit.extensions        (See)  the extensions: built in, another addon's (loaded or not), on or off
--   kit.capabilities      (See)  every live capability with its kind, doc and args
--   kit.proposals         (See)  the proposals still open and the last finished ones; kit.proposal one of them
--   kit.history           (See)  what ran on this character (the last `limit`, 20, of the 50 kept), to undo
--   kit.extension.get/set        a Setting: whether an extension is on; turning one on or off is a proposal, undoable
--   kit.options           (See)  an extension's or an app's options as the player set them (read only: only the player
--                                changes them)
--   kit.me                (See)  the player's name, what AI apps call them (the core's option nickname), their aliases
--   kit.undo              (Do)   undo a proposal that ran
--   kit.local.set         (Keep) 无限工坊's list of the extensions added to this computer that have a local part
--                                (本机端), for the window to show them beside the game's (ns.LocalList), with whether
--                                each runs and their local options; the player changes one on its page: the event
--                                kit.local.option (ns.SetLocalOption). ext:Local() reads a game extension's own part
--                                of it, and the event kit.local says when that changed
--   bus                   (Source) what addons emit on the bus, for apps to hear (bus:<topic or prefix.*>)
--   me                    (Facet)  the player now (WuxianKit:Me()), for apps to see (see = { "me" }: state.me)
-- (The apps' capabilities, kit.app.* and kit.apps, are in Core/Apps/Api.lua.)
local _, ns = ...
local Kit, L = ns.Kit, ns.L

-- words of the core's own extension that the core's Locale does not have
local W = Kit:Words {
	zhCN = { NICKNAME = "称呼", NICKNAME_HINT = "AI 应用怎么叫你；留空就叫角色名", ME = "关于我", BUS = "插件事件",
		PLAYER = "角色状态" },
	enUS = { NICKNAME = "What to call me", NICKNAME_HINT = "How AI apps address you; empty: your character name",
		ME = "About me", BUS = "Addon events", PLAYER = "The player now" },
}

local kit = Kit:Extension("kit", { title = L"CORE", version = Kit.VERSION })
kit:Scope("extensions", L"SCOPE_EXTENSIONS")
kit:Scope("undo", L"SCOPE_UNDO")
kit:Option("nickname", { title = W"NICKNAME", kind = "text", default = "", hint = W"NICKNAME_HINT" })

kit:See("extensions", { title = L"LIST_EXTENSIONS",
	doc = "the extensions in the game: id, title, version, addon, author, builtin (in WuxianKit itself), official "
		.. "(无限工坊's own: the built-in ones and those it gives in an addon of their own), state (on, off, disabled in "
		.. "the game's addon list, missing: cannot load), how many capabilities",
	run = function() return ns.ExtensionList() end })

------------------------------------------------------------------------------------------------------------------------
-- the local extensions: what 无限工坊 says is added to this computer (an extension with a local part, 本机端: a
-- program, documents, apps it declares). The game knows nothing of them by itself, so 无限工坊 gives the whole list, at
-- every kit.ready and when one is added, removed, turned on or off, starts or stops; kept in memory only (a reload:
-- given again; until then nothing is known: ns.LocalKnown). The window lists them with the game's extensions
-- (UI/Window.lua), a game extension reads its own (ext:Local()), and Apps/Report.lua asks which addons one brings

local LOCAL_MOST, LOCAL_IDS = 32, 16     -- extensions kept; ids kept in one's adds, folders in its addons
local OPTIONS_MOST, CHOICES_MOST = 16, 12 -- of one extension's local options; of one option's choices
local CONFIRM = 10                       -- seconds a value the player set waits for 无限工坊's list before it goes back
local roster, known = {}, false

local function Short(v, most)
	if type(v) ~= "string" then return nil end
	v = ns.Cut((v:gsub("%c+", " ")), most)
	return v ~= "" and v or nil
end

local function Ids(v)
	local out = {}
	for _, id in ipairs(type(v) == "table" and v or {}) do
		if #out < LOCAL_IDS and type(id) == "string" and #id <= 40 and id:match("^[a-z][a-z0-9_]*$") then
			out[#out + 1] = id
		end
	end
	return out
end

-- addon folders as given: names of at most 64 bytes, no path in them
local function Folders(v)
	local out = {}
	for _, name in ipairs(type(v) == "table" and v or {}) do
		if #out < LOCAL_IDS and type(name) == "string" and name ~= "" and #name <= 64 and not name:find("[%c/\\]") then
			out[#out + 1] = name
		end
	end
	return out
end

-- a local option as 无限工坊 gives it ({ name, kind, title, value, default?, hint?, choices?, min?, max?, step?,
-- unit? }), kept: kind boolean, number, choice or text, the value (and a default) of that kind; nil when it is not so
local LOCAL_KINDS = { boolean = "boolean", number = "number", choice = true, text = "string" }

local function Fits(kind, v)
	if kind == "choice" then return type(v) == "string" or ns.Finite(v) end
	if kind == "number" then return ns.Finite(v) end
	return type(v) == LOCAL_KINDS[kind]
end

local function LocalOption(v)
	if type(v) ~= "table" then return nil end
	local name, kind = v.name, v.kind
	if type(name) ~= "string" or #name > 40 or not name:match("^[a-z][a-z0-9_]*$") or not LOCAL_KINDS[kind]
		or not Fits(kind, v.value) or (v.default ~= nil and not Fits(kind, v.default)) then
		return nil
	end
	local o = { name = name, kind = kind, title = Short(v.title, 60) or name, hint = Short(v.hint, 120),
		value = kind == "text" and ns.Cut(v.value, 200) or v.value, default = v.default }
	if kind == "text" and o.default ~= nil then o.default = ns.Cut(o.default, 200) end
	if kind == "number" then
		for _, k in ipairs({ "min", "max", "step" }) do
			if v[k] ~= nil and not ns.Finite(v[k]) then return nil end
			o[k] = v[k]
		end
		if o.step and o.step <= 0 then return nil end
		o.unit = Short(v.unit, 24)
	elseif kind == "choice" then
		o.choices = {}
		for _, c in ipairs(type(v.choices) == "table" and v.choices or {}) do
			if type(c) == "table" and Fits("choice", c.value) and #o.choices < CHOICES_MOST then
				o.choices[#o.choices + 1] = { value = c.value, label = Short(c.label, 24) or tostring(c.value) }
			end
		end
		local found = false
		for _, c in ipairs(o.choices) do found = found or c.value == o.value end
		if not found then return nil end                   -- (its value among them, or nothing to draw it by)
	end
	return o
end

local function LocalOptions(v)
	if type(v) ~= "table" then return nil end
	local out, seen = {}, {}
	for _, x in ipairs(v) do
		local o = #out < OPTIONS_MOST and LocalOption(x)
		if o and not seen[o.name] then
			seen[o.name] = true
			out[#out + 1] = o
		end
	end
	return #out > 0 and out or nil
end

-- the list as it is kept: { id, title, version, author, notes, where ("local", or "both": it has addons in the game
-- too), on (enabled and approved), running (its program runs), addons (the folders of the addons it brings), adds (the
-- ids of the apps it adds to), options? (its local options in order, each { name, kind, title, value, default?, hint?,
-- choices? ({ value, label }), min?, max?, step?, unit?, pending? ({ value }: what the player set here, not confirmed
-- yet) }) }, texts as given (escape them to draw them)
function ns.LocalList() return roster end

-- whether 无限工坊 gave its list in this UI session (before it does, nothing is known of the local parts)
function ns.LocalKnown() return known end

-- the list's entry of local extension id, or nil
function ns.LocalEntry(id)
	for _, x in ipairs(roster) do
		if x.id == id then return x end
	end
end

-- whether local extension x brings the addon of that folder (folders compare without case, as the client's do)
local function Brings(x, addon)
	if type(addon) ~= "string" or addon == "" then return false end
	addon = addon:lower()
	for _, name in ipairs(x.addons) do
		if name:lower() == addon then return true end
	end
	return false
end

-- the local part of a game extension (id, and the addon that registers it): the list's entry of the same id, else
-- the one that brings its addon; nil when none (or no list yet). The one rule that makes the two halves one
-- extension: the window's rows, ext:Local() and ext:OnReport all ask here
function ns.LocalOf(id, addon)
	local x = ns.LocalEntry(id)
	if x then return x end
	for _, e in ipairs(roster) do
		if Brings(e, addon) then return e end
	end
end

-- ext:Local(): the extension's part on this computer as 无限工坊 lists it: { known (false: no list yet in this UI
-- session, the rest says nothing), listed (the list has it), on (enabled and approved), running (its program runs),
-- version, options = { name = value } (its local options, as 无限工坊 holds them) }. The bus event kit.local
-- { extension = <this extension's id> } says when the answer changed (for an extension that asked here, or is listed)
local asked = {}                         -- the game extensions that called ext:Local()

local function LocalState(ext)
	local x = known and ns.LocalOf(ext.id, ext.addon) or nil
	local options = {}
	for _, o in ipairs(x and x.options or {}) do options[o.name] = o.value end
	return { known = known, listed = x ~= nil, on = x ~= nil and x.on, running = x ~= nil and x.running,
		version = x and x.version or nil, options = options }
end

function ns.Extension:Local()
	asked[self.id] = true
	return LocalState(self)
end

-- a state as one text, to tell two apart
local function Mark(st)
	local parts = { tostring(st.known), tostring(st.listed), tostring(st.on), tostring(st.running), tostring(st.version) }
	local names = {}
	for name in pairs(st.options) do names[#names + 1] = name end
	table.sort(names)
	for _, name in ipairs(names) do parts[#parts + 1] = name .. "=" .. tostring(st.options[name]) end
	return table.concat(parts, "\1")
end

-- the option name of local extension id, or nil
local function OptionOf(id, name)
	local x = ns.LocalEntry(id)
	for _, o in ipairs(x and x.options or {}) do
		if o.name == name then return o end
	end
end

-- the player set local extension id's option name on its page (boolean, number or choice; a text is 无限工坊's App's):
-- the value as the option takes it shows at once, marked as not confirmed (o.pending), and goes to 无限工坊 as
-- kit.local.option { extension, name, value }, which applies it and gives the list again: that list confirms it, or
-- puts back what holds; none within CONFIRM seconds: back to what 无限工坊 gave. true and the value, or false (no such
-- option, a text, a number that is none, or 无限工坊 not linked: nobody would take it)
function ns.SetLocalOption(id, name, value)
	local o = OptionOf(id, name)
	if not o or o.kind == "text" or (o.kind == "number" and not ns.Finite(tonumber(value))) or not Kit:AgentOnline() then
		return false
	end
	value = ns.OptionValue({ kind = o.kind, min = o.min, max = o.max, step = o.step, choices = o.choices or {},
		default = o.value }, value)
	local shown = o.value
	if o.pending then shown = o.pending.value end
	if value ~= shown then
		local pending = { value = value }
		o.pending = pending
		ns.EmitCore("kit.local.option", { extension = id, name = name, value = value })
		C_Timer.After(CONFIRM, function()
			if o.pending == pending and OptionOf(id, name) == o then   -- no list came: 无限工坊 did not take it
				o.pending = nil
				ns.Changed("local")
			end
		end)
		ns.Changed("local")
	end
	return true, value
end

kit:Keep("local.set", { title = "kit.local.set", args = { extensions = "table" },
	doc = "无限工坊 calls this, not an agent: the extensions added to this computer that have a local part, the whole "
		.. "list each time (it takes the place of the one before; kept until the UI reloads). Each {id, title, version?, "
		.. "author?, notes?, where (local, or both: it has addons in the game too), on (enabled and approved), running "
		.. "(its program runs), addons? (the folders of the addons it brings: a game extension of one of them, or of its "
		.. "id, is the same extension), adds? (the ids of the apps it adds to), options? (its local options in order: "
		.. "[{name, kind boolean|number|choice|text, title, value, default?, hint?, choices? [{value, label}], min?, max?, "
		.. "step?, unit?}]; an option that is not so is skipped)}; one that is not so is left out. The window lists them "
		.. "with the game's extensions; the player changes a local option there (not a text): the event "
		.. "kit.local.option. Answers {count}",
	run = function(_, a)
		local out, seen = {}, {}
		for _, v in ipairs(a.extensions) do
			local id = type(v) == "table" and v.id
			if #out < LOCAL_MOST and type(id) == "string" and #id <= 40 and id:match("^[a-z][a-z0-9_]*$")
				and not seen[id] then
				seen[id] = true
				out[#out + 1] = { id = id, title = Short(v.title, 60) or id, version = Short(v.version, 24),
					author = Short(v.author, 40), notes = Short(v.notes, 200),
					where = v.where == "both" and "both" or "local", on = v.on ~= false, running = v.running == true,
					addons = Folders(v.addons), adds = Ids(v.adds), options = LocalOptions(v.options) }
			end
		end
		local before = {}                                   -- what each game extension's ext:Local() answered
		for _, id in ipairs(ns.order) do
			local st = LocalState(ns.extensions[id])
			before[id] = { mark = Mark(st), listed = st.listed }
		end
		roster, known = out, true
		for _, id in ipairs(ns.order) do
			local st = LocalState(ns.extensions[id])
			if Mark(st) ~= before[id].mark and (asked[id] or st.listed or before[id].listed) then
				ns.EmitCore("kit.local", { extension = id })
			end
		end
		ns.Changed("local")
		return { count = #out }
	end })

kit:See("capabilities", { title = L"LIST_CAPABILITIES",
	doc = "every capability of the extensions that are on: id, kind (see, keep and point run at once; say and do make a "
		.. "proposal the player confirms), title, doc, args (name -> \"string\", \"number?\", \"a|b\"...), undoable",
	run = function() return Kit:Capabilities() end })

kit:See("proposals", { title = L"LIST_PROPOSALS",
	doc = "the proposals still open and the last finished ones: id, state (pending: waits for the player; waiting: "
		.. "pre-approved or confirmed, for its time or until it can run; queued: after combat; running: a step waits for "
		.. "the game to show it; done, failed, declined, expired, undone), title, source, steps with their preview and "
		.. "result, error. Pending and waiting ones expire; queued and running ones do not; a UI reload drops the open ones",
	run = function() return Kit:Proposals() end })

kit:See("proposal", { title = L"ONE_PROPOSAL", args = { id = "number" },
	doc = "one proposal by its id: its state, steps, results, error",
	run = function(_, a)
		return Kit:Proposal(a.id) or error(("no proposal %d (only the open and the recent ones are kept)"):format(a.id), 0)
	end })

kit:See("history", { title = L"HISTORY", args = { limit = "number?" },
	doc = "what ran on this character, newest last: the last `limit` proposals (20, up to 50: all that are kept): id, "
		.. "title, source, ran (Unix time), steps {cap, args (a long text shortened), preview}, undoable, undone",
	run = function(_, a)                                 -- as the proposals read: no snapshots, no layout strings in full
		local all, out = ns.History(), {}
		local limit = math.max(1, math.min(math.floor(tonumber(a and a.limit) or 20), 50))
		for i = math.max(1, #all - limit + 1), #all do
			local e, steps = all[i], {}
			for j, s in ipairs(e.steps or {}) do steps[j] = { cap = s.cap, args = ns.Brief(s.args), preview = s.preview } end
			out[#out + 1] = { id = e.id, title = e.title, source = e.source, ran = e.ran, steps = steps,
				undoable = e.undoable, undone = e.undone }
		end
		return out
	end })

kit:See("options", { title = L"LIST_OPTIONS", args = { extension = "string?", app = "string?" },
	doc = "the options of an extension (extension = its id) or of an app (app = its id; give one of the two), as the "
		.. "player set them on its page: name -> {title, kind (boolean, text, number, choice, list), value, default, "
		.. "choices [{value, label}] (choice), min, max, unit (number)}. Read only: only the player changes them; "
		.. "kit.option says when one changed",
	run = function(_, a)
		if a.extension and a.app then error("give extension or app, not both", 0) end
		if not a.extension and not a.app then error("give extension (an extension's id) or app (an app's id)", 0) end
		if a.app then
			local list = ns.AppOptionList and ns.AppOptionList(a.app)
			if not list then error(("no app %s (kit.apps lists them)"):format(a.app), 0) end
			return list
		end
		local ext = ns.extensions[a.extension]
		if not ext then error(("no extension %s (kit.extensions lists them)"):format(a.extension), 0) end
		return ns.OptionList(ext)
	end })

kit:See("me", { title = W"ME",
	doc = "the player as AI apps address them: name (the whole character name), nickname (the core's option 称呼, What "
		.. "to call me: call the player this; \"\" = by name), aliases (the names chat counts as naming the player: the "
		.. "whole name, its parts, the chat option 别人怎么叫我; none while the chat extension is off)",
	run = function()
		local me = Kit:Me()
		local chat = ns.extensions.chat
		local aliases = chat and chat.active and Kit.Chat and Kit.Chat.Names and Kit.Chat.Names() or {}
		return { name = me.name, nickname = me.nickname, aliases = aliases }
	end })

-- the player now, as a facet apps see (see = { "me" }): each wake carries state.me
kit:Facet("me", { title = W"PLAYER",
	doc = "the player now: name (whole), nickname (what to call them; \"\" = by name), level, class, classToken, zone, "
		.. "subzone, combat, dead (dead or a ghost), resting, xp (this level's experience, a whole percent; none at the "
		.. "top level)",
	fields = { name = "string", nickname = "string", level = "number", class = "string", classToken = "string",
		zone = "string?", subzone = "string?", combat = "boolean", dead = "boolean", resting = "boolean", xp = "number?" },
	read = function() return Kit:Me() end })

kit:Setting("extension", { title = L"SWITCH", doc = "whether an extension is on",
	key = { extension = "string" }, value = "boolean", scope = "extensions",
	check = function(_, k)
		if k.extension == "kit" then return "WuxianKit's core stays on" end
		if not ns.extensions[k.extension] and not ns.Installed()[k.extension] then
			return ("no extension %s (kit.extensions lists them)"):format(k.extension)
		end
	end,
	get = function(_, k)
		local ext = ns.extensions[k.extension]
		return ext ~= nil and ext.active == true
	end,
	set = function(_, k, on)
		local ok, why = ns.Switch(k.extension, on)
		if not ok then error(("could not turn %s %s: %s"):format(k.extension, on and "on" or "off", ns.Text(why)), 0) end
	end,
	label = function(_, k)
		local ext = ns.extensions[k.extension] or ns.Installed()[k.extension]
		return ext and ns.T(ext.title) or k.extension
	end,
	format = function(_, v) return v and L.STATE.on or L.STATE.off end })

kit:See("manifest", { title = L"MANIFEST",
	doc = "what the agent may use (the Agent access spec): protocol, kit (version), language, revision, extensions [{id, "
		.. "title, version, addon, builtin, state, docs (the folder under Interface\\AddOns of its AGENT.md and skills/), "
		.. "capabilities, events, sources [{name, title, doc, values}] (what apps can hear of it), facets [{name, title, "
		.. "doc, fields}] (what apps can see of it)}], the capabilities and events of those that are on, apps [{id, title, "
		.. "by, addon, topic, hear, see, prompt, start, extension, docs (an addon's app: the folder of its skills/), "
		.. "temp, link?, driver?}]. For 无限工坊's app",
	run = function() return Kit:Manifest() end })
kit:See("revision", { title = L"REVISION", doc = "the manifest's revision: {revision}; it changes whenever the manifest does",
	run = function() return { revision = Kit:Manifest().revision } end })
kit:Event("proposal", { doc = "a proposal changed state: pending, waiting (for its time, or until it can run), queued "
	.. "(after combat), done, failed, declined, expired, undone",
	data = { id = "number", state = "string", title = "string?", source = "string", error = "string?" } })
kit:Event("extension", { doc = "an extension went on or off", data = { id = "string", on = "boolean" } })
kit:Event("dropped", { doc = "extension events that were not sent because they came faster than the link carries "
	.. "(the core's own always go, and an app's wakes wait and are sent again): how many, by topic",
	data = { count = "number", topics = "table" } })
kit:Event("changed", { doc = "the manifest changed: an extension on or off, a capability, the language",
	data = { revision = "string" } })
kit:Event("ready", { doc = "WuxianKit is up, after a login or a reload", data = { version = "string", extensions = "table",
	revision = "string" } })
-- one topic, two shapes: an extension's option is { extension, name, value } (ns.SetOption, Extension.lua), an app's is
-- { app, name, value } (ns.SetAppOption, Apps/Api.lua); never both keys
kit:Event("option", { doc = "the player changed an option: an extension's ({extension, name, value}) or an app's "
	.. "({app, name, value}): one of extension and app, never both (kit.options reads them all)",
	data = { extension = "string?", app = "string?", name = "string", value = "any" } })
kit:Event("local", { doc = "for addons, not an agent: what ext:Local() answers for a game extension changed (无限工坊 "
	.. "gave its list of local extensions: its local part listed or gone, on or off, its program started or stopped, "
	.. "its version, a local option): {extension (the game extension's id)}",
	data = { extension = "string" } })
-- the core sends it (ns.EmitCore; WuxianKit:Emit refuses kit.*): 无限工坊 takes it as the player's own change
kit:Event("local.option", { doc = "for 无限工坊, not an agent: the player changed a local extension's option on its "
	.. "page of the /wk window (boolean, number or choice): {extension, name, value}; 无限工坊 applies it and calls "
	.. "kit.local.set again (only WuxianKit sends this event)",
	data = { extension = "string", name = "string", value = "any" } })

-- the bus as a source apps hear (bus:<topic or prefix.*>): what addons tell each other with WuxianKit:Emit, not the
-- core's own (kit.*) nor apps' wakes (app.*)
kit:Source("bus", { title = W"BUS",
	doc = "bus:<topic> or bus:<prefix>.* (an event addons emit, such as bus:demo.ping or bus:demo.*; not kit.* or app.*): "
		.. "items {topic, data}",
	check = function(what)
		local base = what:gsub("%.%*$", "")
		if not base:match("^[a-z][a-z0-9_.]*$") or base:sub(-1) == "." then
			return "a bus source is a topic such as chat.message, or a prefix such as chat.*"
		end
		local head = base:match("^([^.]+)")
		if head == "kit" or head == "app" then return "an app cannot hear kit.* or app.* topics" end
	end,
	covers = function(a, b)                              -- demo.* hears demo.ping and demo.x.*
		return a:sub(-2) == ".*" and b:sub(1, #a - 1) == a:sub(1, -2)
	end,
	on = function(_, what, fn)
		return Kit:On(what, function(topic, data) fn({ topic = topic, data = data }) end)
	end,
	off = function(_, t) Kit:Off(t) end })

kit:Do("undo", { title = L"UNDO", args = { id = "number" }, scope = "undo", notes = false,
	doc = "proposes to undo a proposal that ran (its id from kit.history): what its steps changed is put back, last step "
		.. "first; only on the character it ran on; what cannot be undone (a sent message, a bag sort) stays",
	check = function(_, a)
		for _, h in ipairs(ns.History()) do
			if h.id == a.id then
				if h.undone then return ("proposal %d was undone already"):format(a.id) end
				if not h.undoable then return ("proposal %d cannot be undone (nothing of it was kept)"):format(a.id) end
				return nil
			end
		end
		return ("no proposal %d in the history"):format(a.id)
	end,
	preview = function(_, a)                             -- and what it takes back, last step first
		local lines = { L.UNDO_STEP:format(a.id) }
		for _, h in ipairs(ns.History()) do
			if h.id == a.id then
				for j = #h.steps, 1, -1 do
					local s = h.steps[j]
					if s.snap ~= nil then
						for _, line in ipairs(s.preview or {}) do
							if type(line) == "string" and not line:find("^|cff9c9ea6") then
								lines[#lines + 1] = L.UNDO_LINE:format(line)
							end
						end
					end
				end
			end
		end
		return lines
	end,
	apply = function(_, a)
		local ok, why = ns.UndoNow(a.id)
		if not ok then error(ns.Text(why), 0) end
		return true
	end })
