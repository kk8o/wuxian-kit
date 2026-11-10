-- Apps (应用, 0.6): the finished products. Extensions are the parts (capabilities, the sources apps hear: ext:Source, and
-- the facets they see: ext:Facet, Extension.lua); the core is the runtime; an app uses extensions, and no extension knows
-- which apps there are. Outside the game, hearing the game is only through an app. An app is a declaration an agent
-- drives: what it hears (hear entries <source>:<what>, such as chat:guild, game:quest, bus:demo.*: what happened), what
-- it sees (see: facets such as me, group: how things are now; each wake carries them as state), whether and how its
-- items are gathered into wakes (a digest, Digest.lua; with pace, the player's activity and quiet hours run it), which
-- commands the player can give it in the game, how long it may go unheard from before it counts as gone (lease),
-- options the player sets for it, and its prompt: the skill an AI client follows to drive it.
-- K2 draws it (UI/AppPanel.lua, the window's 应用 page, /wk <app> ...). The contract is ARCHITECTURE.md section 10; in
-- short:
--
--   WuxianKit:App(id, decl) -> app       an addon declares an app (functions allowed: check, urgent, enrich; docs: the
--                                        folder of its AGENT.md and skills/ in its addon's); with no decl, the app
--                                        declared before (or nil)
--   app:Get(name)                        one of its options (as ext:Get)
--   app:Running()                        its run while it runs ({ ends, started, ... }), else nil
--   app:Push(data) -> boolean            an item of its own ({ source = "addon", data }) while it runs
--   WuxianKit:AppControl(id, cmd) -> boolean   the player's command (one of the app's controls, by its cmd, a word of
--                                        ns.CONTROL_WORDS or its own label; "stop" stops it too)
--   WuxianKit:AppSay(id, text) -> boolean      the player's words to the app (decl.say)
--   WuxianKit:AppPanel(id, parent, width)      (UI/AppPanel.lua, K2) the app's card in another addon's window
--
-- Capabilities (the core's extension "kit"): kit.app.open { app, ...decl, temp, minutes, lease }, kit.app.declare
-- { app, ...decl } (kept, not started, no heartbeat: 无限工坊 declares a local extension's apps so), kit.app.status
-- { app } (also the heartbeat), kit.app.state { app } (what it sees now: { app, at, state }; a heartbeat too),
-- kit.app.stop { app }, kit.app.recent { app, since, limit }, kit.apps. Events: app.<id> (the app's wakes: { app,
-- reason, items, skipped, state? (with see: { [facet] = its read at the wake }), pace?, quiet? }; an extension's event
-- as far as the link's rate goes), kit.app ({ app, on, why?, ends? } when one starts or stops).
-- see: at most SEE_MOST facet names; a facet is on (its spec's on) while an app that runs sees it, and its extension
-- going off stops the apps that see it, as for a source. temp = true (kit.app.open's): a temporary app, in memory only,
-- at most TEMP_MOST at once and not one of the AGENT_MOST kept, gone once it stops or the UI reloads; it does not count
-- when two declarations are compared.
--
-- For the window (K2):
--   ns.AppList()                  the apps as kit.apps answers (start: the start line, for an app with a prompt)
--   ns.App(id)                    the app object, or nil
--   ns.AppStatus(id)              as kit.app.status answers (without marking it heard from)
--   ns.AppStop(id, why)           stops it ("player" from the window)
--   ns.AppOptionList(id)          its options as kit.options answers ({ [name] = { title, kind, value, ... } })
--   ns.SetAppOption(id, name, v)  the player set one: true and the value kept, or false
--   ns.AppControls(id)            { { cmd, label } } in its declared order (label: the core's word, or the app's own)
--   ns.ForgetApp(id)              the player removes an app an agent declared (not one a local extension brings)
--   ns.CONTROL_WORDS              word (English and Chinese) -> cmd, for /wk <app> <word>
-- ns.Changed("app", id) tells it when an app is declared or removed.
--
-- Storage: WuxianKitDB.apps[id] = { decl (an agent's declaration, as it was given and checked), options (the player's),
-- chars = { [the character's GUID] = { run (this run: ends, started, seen, lease, heard, wakes, lastWake, pace, quiet,
-- and the digest's options, buffer, first, last, urgentAt), recent = { n, items } (the last RING items), last = { why }
-- (how the last run ended), said = { d, n } } } }: what is the account's is at the top, what is a character's under its
-- GUID (A.Char). An addon's declaration is kept in memory only (it may carry functions) and wins over an agent's of the
-- same id; a temporary app's whole record is in memory.
--
-- The runtime is four files (Core/Apps/, in load order), split by what they do:
--   Decl.lua     (this one) declarations checked and normalized, the stored record, the app object and its options,
--                declaring (WuxianKit:App, an agent's Declare, ns.ForgetApp), the declarations back from storage
--   Deliver.lua  items: which wake at once, the digest host, the ring, an item into an app, app:Push
--   Run.lua      runs: quiet hours and pace, what a run hears and sees, start / stop / the ticker / leases, the
--                player's commands and words, what else stops an app or resumes it
--   Api.lua      kit.app.* and kit.apps, the status, and the ns functions the window uses
-- What they share is the private table ns.apps (A in each file): a name another file uses is a field of A under the
-- same name, set at the end of the file that defines it and read into a local at the top of the files loaded after it.
-- A file loaded before calls it as A.Name(...) when it runs (here: A.Host, A.Stop, A.Unsubscribe, A.Resume, A.Drop;
-- Run.lua: A.DeclareOpen). A.loggedIn is the one field that changes: always read as A.loggedIn. What only one file
-- uses stays local there.
-- Here by choice: OPEN_ARGS, DECLARE_ARGS and Given (the declaration's fields, beside DECL_FIELDS; only Api.lua uses
-- them), Paced and Digesting (what a declaration says), ns.ForgetApp and the load hook (a declaration going, and
-- those kept coming back).
local addonName, ns = ...
local Kit = ns.Kit
ns.apps = ns.apps or {}
local A = ns.apps

local W = Kit:Words {
	zhCN = {
		STARTED = "%s：已开始，至 %s", STOPPED = "%s：已停止", EXPIRED = "%s：已到时间，已停止",
		LEFT = "%s：Agent 已离开，已停止", EXT_STOPPED = "%s：所属扩展已停用，已停止",
		EXT_OFF = "所属扩展「%s」已停用", NEEDS = "需要开启「%s」扩展", NEEDS_SOURCE = "需要来源「%s」",
		NEEDS_FACET = "需要状态面「%s」",
		ACTIVITY = "活跃度", A_QUIET = "安静", A_NORMAL = "适中", A_LIVELY = "活跃",
		ACTIVITY_HINT = "安静：只在点名时唤醒；适中：接话、提问时唤醒，冷场时也唤醒；活跃：话题正热时也唤醒，节奏更快",
		QUIET = "免打扰时段", QUIET_HINT = "如 01:00-08:00；这段时间只在点名时唤醒",
		CONTROL = { mute = "静音", unmute = "开声", less = "少说", more = "多说", test = "试音", pause = "暂停",
			resume = "继续", stop = "停止" },
		START = "开始无限工坊的应用「%s」：先调用无限工坊 MCP 的工具 wk_docs，参数 {\"skill\": \"%s\"}，照读到的步骤做。",
	},
	enUS = {
		STARTED = "%s: started, until %s", STOPPED = "%s: stopped", EXPIRED = "%s: time is up, stopped",
		LEFT = "%s: the agent left, stopped", EXT_STOPPED = "%s: its extension was turned off, stopped",
		EXT_OFF = "Its extension %s is off", NEEDS = "Needs the %s extension on", NEEDS_SOURCE = "Needs the source %s",
		NEEDS_FACET = "Needs the state %s",
		ACTIVITY = "Activity", A_QUIET = "Quiet", A_NORMAL = "Normal", A_LIVELY = "Lively",
		ACTIVITY_HINT = "Quiet: wakes only when you are named; Normal: also for follow-ups, questions and lulls; "
			.. "Lively: also when the talk is hot, faster",
		QUIET = "Quiet hours", QUIET_HINT = "Such as 01:00-08:00; only wakes when you are named then",
		CONTROL = { mute = "Mute", unmute = "Unmute", less = "Less", more = "More", test = "Test", pause = "Pause",
			resume = "Resume", stop = "Stop" },
		START = "Start the 无限工坊 app \"%s\": first call the 无限工坊 MCP tool wk_docs with {\"skill\": \"%s\"} and follow the steps "
			.. "it gives.",
	},
}

local ID_MAX, TITLE_MAX, HINT_MAX, LABEL_MAX, WORD_MAX = 24, 48, 120, 24, 32
local AGENT_MOST, TEMP_MOST, OPTIONS_MOST, CHOICES_MOST, HEAR_MOST, SEE_MOST, LIST_MOST = 8, 4, 8, 8, 16, 8, 16
local MINUTES, MINUTES_MOST, LEASE, LEASE_MOST = 120, 720, 600, 43200

local CONTROL_ORDER = { "mute", "unmute", "less", "more", "test", "pause", "resume", "stop" }
local CONTROLS_MOST = 12                                -- the core's and an app's own ({cmd, label}) together
local CONTROLS = {}
for _, c in ipairs(CONTROL_ORDER) do CONTROLS[c] = true end
local OPTION_KINDS = { boolean = true, text = true, number = true, choice = true, list = true }
local ACTIVITIES = { "quiet", "normal", "lively" }

-- the core's three paces (pace = true): the digest of each and the whys that wake at once
local PRESETS = {
	quiet = { gather = 6, every = false, idle = false, most = 30, wake = { "mention" } },
	normal = { gather = 5, every = 60, idle = 1200, most = 30, wake = { "mention", "followup", "question" } },
	lively = { gather = 3, every = 20, idle = 480, most = 30, wake = { "mention", "followup", "question", "burst" } },
}
ns.APP_PRESETS = PRESETS

ns.CONTROL_WORDS = {
	mute = "mute", unmute = "unmute", less = "less", more = "more", test = "test", pause = "pause", resume = "resume",
	stop = "stop",
	["静音"] = "mute", ["开声"] = "unmute", ["少说"] = "less", ["多说"] = "more", ["试音"] = "test", ["暂停"] = "pause",
	["继续"] = "resume", ["离开"] = "stop", ["停止"] = "stop",
}

local function Copy(v)
	if type(v) ~= "table" then return v end
	local t = {}
	for k, x in pairs(v) do t[k] = Copy(x) end
	return t
end

local function Set(list)
	local set = {}
	for _, v in ipairs(list or {}) do set[v] = true end
	return set
end

local function Me()
	return UnitGUID and UnitGUID("player") or nil
end

------------------------------------------------------------------------------------------------------------------------
-- hear entries: <source>:<what>, of the sources registered (ns.sources, Extension.lua)

-- an entry's source name and what, or nil
local function Split(entry)
	if type(entry) ~= "string" then return nil end
	return entry:match("^([a-z][a-z0-9_]*):(.+)$")
end

local function SourceNames()
	local names = {}
	for i, name in ipairs(ns.sourceOrder) do names[i] = name end
	table.sort(names)
	return table.concat(names, ", ")
end

-- whether entry a hears all that entry b does (its source's covers), b another entry of the same source
local function Covers(a, b)
	local na, wa = Split(a)
	local nb, wb = Split(b)
	if not na or na ~= nb or a == b then return false end
	local src = ns.sources[na]
	if not (src and src.spec.covers) then return false end
	local ok, yes = pcall(src.spec.covers, wa, wb)
	return ok and yes == true
end

-- the entries, each once and none another covers (each subscription hears its own copy of an item: chat:* and
-- chat:guild would hear a guild line twice); of two that cover each other the first stays
local function Trim(list)
	local out, done = {}, {}
	for i, e in ipairs(list) do
		if not done[e] then
			done[e] = true
			local covered = false
			for j, o in ipairs(list) do
				if o ~= e and Covers(o, e) and (j < i or not Covers(e, o)) then
					covered = true
					break
				end
			end
			if not covered then out[#out + 1] = e end
		end
	end
	return out
end

------------------------------------------------------------------------------------------------------------------------
-- declarations, checked. An agent's (data only, agent = true) is refused on anything out of shape, its texts escaped;
-- an addon's (Lua) may carry functions and texts as L"KEY". Both come out as the same normalized declaration.

local function Fail(fmt, ...) error(fmt:format(...), 0) end

local function IsList(t)
	if type(t) ~= "table" then return false end
	local n = 0
	for k in pairs(t) do
		if type(k) ~= "number" then return false end
		n = n + 1
	end
	return n == #t
end

local function Text(v, what, most, agent)
	if v == nil then return nil end
	if not agent and type(v) == "function" then return v end
	if type(v) ~= "string" then Fail("%s is a string", what) end
	if agent and #v > most then Fail("%s is at most %d bytes (it has %d)", what, most, #v) end
	return v                                            -- (kept as given: whoever draws it escapes it)
end

local function Words(v, what, agent)                  -- a list of words (whys, kinds): lowercase, digits, _ and .
	if v == nil then return nil end
	if not IsList(v) or #v > LIST_MOST then Fail("%s is a list of at most %d words", what, LIST_MOST) end
	local out = {}
	for _, w in ipairs(v) do
		if type(w) ~= "string" or #w > WORD_MAX or not w:match("^[a-z][a-z0-9_.]*$") then
			Fail("%s: %s is not a word such as \"mention\" (lowercase letters, digits, _ and .)", what, ns.Text(w))
		end
		out[#out + 1] = w
	end
	return out
end

local function Bool(v, what)
	if v == nil then return nil end
	if type(v) ~= "boolean" then Fail("%s is true or false", what) end
	return v
end

local function Number(v, what, min, allowFalse)
	if v == nil then return nil end
	if allowFalse and v == false then return false end
	if not ns.Finite(v) or v < min then
		Fail("%s is a number of at least %s%s", what, tostring(min), allowFalse and " or false" or "")
	end
	return v
end

local function Only(t, allowed, what)                   -- an agent's table names no field it may not
	for k in pairs(t) do
		if not allowed[k] then
			local names = {}
			for n in pairs(allowed) do names[#names + 1] = n end
			table.sort(names)
			Fail("%s: no field %s (it takes %s)", what, ns.Text(k), table.concat(names, ", "))
		end
	end
end

local DIGEST_FIELDS = { gather = true, every = true, idle = true, most = true }
local PRESET_FIELDS = { gather = true, every = true, idle = true, most = true, wake = true }

local function Digest(d, what, agent, preset)
	if type(d) ~= "table" then Fail("%s is a table {gather, every, idle, most}", what) end
	if agent then Only(d, preset and PRESET_FIELDS or DIGEST_FIELDS, what) end
	local out = { gather = Number(d.gather, what .. ".gather", 0), every = Number(d.every, what .. ".every", 1, true),
		idle = Number(d.idle, what .. ".idle", 1, true), most = Number(d.most, what .. ".most", 1) }
	if out.most then out.most = math.floor(out.most) end
	if preset then out.wake = Words(d.wake, what .. ".wake", agent) or {} end
	return out
end

local function Pace(p, agent)
	if p == true then return PRESETS end
	if type(p) ~= "table" then Fail("pace is true or a table {quiet, normal, lively}") end
	if agent then Only(p, { quiet = true, normal = true, lively = true }, "pace") end
	local out = {}
	for _, name in ipairs(ACTIVITIES) do
		local given = p[name] and Digest(p[name], "pace." .. name, agent, true) or {}
		local core = PRESETS[name]
		local e = {}
		for k in pairs(PRESET_FIELDS) do
			if given[k] ~= nil then e[k] = given[k] else e[k] = core[k] end
		end
		out[name] = e
	end
	return out
end

-- a hear entry checked by its source; kept (a remembered declaration, an addon's): one of a source not registered (yet:
-- its addon has not loaded) stays, and the app cannot start while it is missing
local function Entry(entry, kept)
	if type(entry) ~= "string" then Fail("a hear entry is a string such as \"chat:guild\"") end
	local name, what = Split(entry)
	if not name or #what > ns.NAME_MAX then
		Fail("%s: a hear entry is <source>:<what> (what at most %d bytes); the sources: %s", entry, ns.NAME_MAX,
			SourceNames())
	end
	local src = ns.sources[name]
	if not src then
		if kept then return end
		Fail("%s: no source %s (the sources: %s)", entry, name, SourceNames())
	end
	if src.spec.check then
		local ok, why = pcall(src.spec.check, what)
		if not ok or (why ~= nil and why ~= false) then Fail("%s: %s", entry, ns.Text(why)) end
	end
end

local function Hear(list, kept)
	if list == nil then return {} end
	if not IsList(list) or #list > HEAR_MOST then Fail("hear is a list of at most %d sources", HEAR_MOST) end
	for _, entry in ipairs(list) do Entry(entry, kept) end
	return Trim(list)
end

------------------------------------------------------------------------------------------------------------------------
-- see: the facets an app's wakes carry as state (ns.facets, Extension.lua)

local function FacetNames()
	local names = {}
	for i, name in ipairs(ns.facetOrder) do names[i] = name end
	table.sort(names)
	return table.concat(names, ", ")
end

-- the names, each once; kept (a remembered declaration, an addon's): a facet not registered (yet) stays, and the app
-- cannot start while it is missing
local function See(list, kept)
	if list == nil then return {} end
	if not IsList(list) or #list > SEE_MOST then Fail("see is a list of at most %d states (%s)", SEE_MOST, FacetNames()) end
	local out, done = {}, {}
	for _, name in ipairs(list) do
		if type(name) ~= "string" or #name > ID_MAX or not name:match("^[a-z][a-z0-9_]*$") then
			Fail("see: %s is not a state's name (the states: %s)", ns.Text(name), FacetNames())
		end
		if not ns.facets[name] and not kept then Fail("see: no state %s (the states: %s)", name, FacetNames()) end
		if not done[name] then
			done[name] = true
			out[#out + 1] = name
		end
	end
	return out
end

local function Option(name, o, agent, paced)
	if type(name) ~= "string" or #name > ID_MAX or not name:match("^[a-z][a-z0-9_]*$") then
		Fail("options: %s is not a name (lowercase letters, digits and _, at most %d bytes)", ns.Text(name), ID_MAX)
	end
	if paced and (name == "activity" or name == "quiet") then
		Fail("options: %s is the core's own option of an app with pace", name)
	end
	if type(o) ~= "table" then Fail("options.%s is a table {kind, title, default, ...}", name) end
	local what = "options." .. name
	if agent then
		Only(o, { kind = true, title = true, default = true, hint = true, choices = true, min = true, max = true,
			step = true, unit = true, order = true }, what)
	end
	local kind = o.kind or "boolean"
	if not OPTION_KINDS[kind] then Fail("%s.kind is boolean, text, number, choice or list", what) end
	local spec = { kind = kind, title = Text(o.title, what .. ".title", TITLE_MAX, agent) or name,
		hint = Text(o.hint, what .. ".hint", HINT_MAX, agent), unit = Text(o.unit, what .. ".unit", LABEL_MAX, agent),
		changed = not agent and type(o.changed) == "function" and o.changed or nil,
		order = ns.Finite(o.order) and o.order or nil }
	local d = o.default
	if agent and d ~= nil then
		local t = type(d)
		local fits = (kind == "boolean" and t == "boolean") or (kind == "text" and t == "string" and #d <= HINT_MAX)
			or (kind == "number" and ns.Finite(d)) or (kind == "choice" and (t == "string" or ns.Finite(d)))
			or (kind == "list" and (t == "string" or IsList(d)))
		if not fits then Fail("%s.default does not fit a %s option", what, kind) end
	end
	spec.default = Copy(d)
	if kind == "number" then
		spec.min, spec.max = Number(o.min, what .. ".min", -math.huge), Number(o.max, what .. ".max", -math.huge)
		spec.step = Number(o.step, what .. ".step", 0)
	elseif kind == "choice" then
		local c = o.choices
		if not IsList(c) or #c == 0 or (agent and #c > CHOICES_MOST) then
			Fail("%s.choices is a list of 1 to %d {value, label}", what, CHOICES_MOST)
		end
		spec.choices = {}
		for i, x in ipairs(c) do
			local value, label
			if type(x) == "table" then value, label = x.value, x.label else value = x end
			if value == nil and type(x) == "table" then value, label = x[1], x[2] end
			if not ((type(value) == "string" and #value <= WORD_MAX) or ns.Finite(value)) then
				Fail("%s.choices[%d]: a value is a string of at most %d bytes or a number", what, i, WORD_MAX)
			end
			label = Text(label, ("%s.choices[%d].label"):format(what, i), LABEL_MAX, agent)
			spec.choices[i] = { value = value, label = label or tostring(value) }
		end
	end
	return spec
end

local function Options(t, agent, paced)
	if t == nil then return {}, {} end
	if type(t) ~= "table" or IsList(t) and #t > 0 then Fail("options is a table {name = {kind, title, ...}}") end
	local out, names = {}, {}
	for name, o in pairs(t) do
		out[name] = Option(name, o, agent, paced)
		names[#names + 1] = name
	end
	if agent and #names > OPTIONS_MOST then Fail("an app has at most %d options (it gave %d)", OPTIONS_MOST, #names) end
	table.sort(names, function(a, b)                     -- by order (when given), then by name
		local ra, rb = out[a].order or math.huge, out[b].order or math.huge
		if ra ~= rb then return ra < rb end
		return a < b
	end)
	return out, names
end

local DECL_FIELDS = { title = true, hear = true, see = true, digest = true, pace = true, urgent = true, controls = true,
	hidden = true, ["local"] = true,
	say = true, lease = true, minutes = true, options = true, prompt = true }

local function CheckId(id)
	if type(id) ~= "string" or #id > ID_MAX or not id:match("^[a-z][a-z0-9_]*$") then
		Fail("an app's id is lowercase letters, digits and _, starting with a letter, at most %d bytes (not %s)", ID_MAX,
			ns.Text(id))
	end
end

-- a lease as an app keeps it: seconds (at least 60, at most LEASE_MOST), or false for none
local function LeaseOf(v, what)
	if v == nil then return nil end
	if v == false or v == 0 then return false end
	if not ns.Finite(v) or v < 0 then Fail("%s is a number of seconds (0: none)", what) end
	return math.min(LEASE_MOST, ns.Lease(v))
end

local function MinutesOf(v, what)
	if v == nil then return nil end
	if not ns.Finite(v) or v <= 0 then Fail("%s is a number of minutes", what) end
	return math.max(1, math.min(MINUTES_MOST, v))
end

-- an addon's docs: a folder in its addon's ("Apps/Guild"), as given with / and no slash at either end
local function Docs(v)
	if v == nil then return nil end
	if type(v) ~= "string" then Fail("docs is a folder in the addon's, such as \"Apps/Guild\"") end
	v = v:gsub("\\", "/"):gsub("^/+", ""):gsub("/+$", "")
	return v ~= "" and v or nil
end

-- decl (an agent's table, or an addon's) -> the normalized declaration; kept: a remembered or an addon's declaration
-- (an entry of a source not registered yet stays)
local function Normalize(id, d, agent, kept)
	CheckId(id)
	if type(d) ~= "table" then Fail("a declaration is a table") end
	if agent then Only(d, DECL_FIELDS, "the declaration") end
	local n = { title = Text(d.title, "title", TITLE_MAX, agent) or id }
	n.hear = Hear(d.hear, kept)
	n.see = See(d.see, kept)
	if d.pace ~= nil and d.pace ~= false then
		n.pace = Pace(d.pace, agent)
		for _, name in ipairs(ACTIVITIES) do n.pace[name].wakeSet = Set(n.pace[name].wake) end
	elseif d.digest ~= nil and d.digest ~= false then
		n.digest = d.digest == true and {} or Digest(d.digest, "digest", agent)
	end
	if not agent and type(d.urgent) == "function" then
		n.urgent = d.urgent
	elseif d.urgent ~= nil then
		n.urgentSet = Set(Words(d.urgent, "urgent", agent))
	end
	n.controls, n.labels = {}, {}
	if d.controls ~= nil then
		if not IsList(d.controls) or #d.controls > CONTROLS_MOST then
			Fail("controls is a list of at most %d: %s, or {cmd, label} of the app's own", CONTROLS_MOST,
				table.concat(CONTROL_ORDER, ", "))
		end
		local seen = {}
		for i, c in ipairs(d.controls) do
			local cmd, label = c, nil
			if type(c) == "table" then                       -- the app's own: a button with its label, told as {cmd}
				cmd = c.cmd
				if type(cmd) ~= "string" or #cmd > ID_MAX or not cmd:match("^[a-z][a-z0-9_]*$") or CONTROLS[cmd]
					or ns.CONTROL_WORDS[cmd] then
					Fail("controls[%d].cmd: a word of the app's own (lowercase letters, digits, _, at most %d bytes), not "
						.. "one of %s", i, ID_MAX, table.concat(CONTROL_ORDER, ", "))
				end
				label = Text(c.label, ("controls[%d].label"):format(i), LABEL_MAX, agent)
				if label == nil or (type(label) == "string" and not label:match("^%S+$")) then
					Fail("controls[%d].label: the button's text, one word without spaces (/wk <app> <label> gives it), at "
						.. "most %d bytes", i, LABEL_MAX)
				end
			elseif not CONTROLS[c] then
				Fail("controls: %s is not one of %s (or {cmd, label} of the app's own)", ns.Text(c),
					table.concat(CONTROL_ORDER, ", "))
			end
			if not seen[cmd] then
				seen[cmd] = true
				n.controls[#n.controls + 1] = cmd
				n.labels[cmd] = label
			end
		end
	end
	n.say = Bool(d.say, "say") or false
	n.hidden = Bool(d.hidden, "hidden") or nil              -- plumbing: not in the window's list, no chat lines
	local from = d["local"]                               -- the local extension it comes with: no remove button
	if from ~= nil then
		if type(from) ~= "table" or type(from.id) ~= "string" or #from.id > ID_MAX
			or not from.id:match("^[a-z][a-z0-9_]*$") then
			Fail("local is {id, title}: the local extension of 无限工坊 the app comes with (id: lowercase letters, "
				.. "digits, _, at most %d bytes)", ID_MAX)
		end
		n["local"] = { id = from.id, title = Text(from.title, "local.title", TITLE_MAX, true) or from.id }
	end
	local lease = LeaseOf(d.lease, "lease")
	if lease == nil then lease = LEASE end
	n.lease = lease or nil
	n.minutes = MinutesOf(d.minutes, "minutes") or MINUTES
	n.options, n.optionNames = Options(d.options, agent, n.pace ~= nil)
	if d.prompt ~= nil then
		if type(d.prompt) ~= "string" or #d.prompt > TITLE_MAX or not d.prompt:match("^[a-z0-9][a-z0-9_%-]*$") then
			Fail("prompt is a skill's name (lowercase letters, digits, - and _)")
		end
		n.prompt = d.prompt
	end
	if not agent then
		n.addon = type(d.addon) == "string" and d.addon ~= "" and d.addon or nil
		n.extension = type(d.extension) == "string" and d.extension ~= "" and d.extension or nil
		n.docs = Docs(d.docs)
		n.check = type(d.check) == "function" and d.check or nil
		n.enrich = type(d.enrich) == "function" and d.enrich or nil
	end
	return n
end

local function Equal(a, b)                              -- two declarations as data
	if type(a) ~= "table" or type(b) ~= "table" then return a == b end
	for k, v in pairs(a) do
		if not Equal(v, b[k]) then return false end
	end
	for k in pairs(b) do
		if a[k] == nil then return false end
	end
	return true
end

-- an agent's declaration as it is kept (the fields it gave, as given: escaping is done each time it is normalized; not
-- temp)
local function Raw(a)
	local raw = {}
	for k in pairs(DECL_FIELDS) do raw[k] = Copy(a[k]) end
	return raw
end

-- the arguments kit.app.open and kit.app.declare take (Api.lua)
local OPEN_ARGS = { app = "string", minutes = "number?", lease = "number?", title = "string?", hear = "table?",
	digest = "table|boolean?", pace = "table|boolean?", urgent = "table?", controls = "table?", say = "boolean?",
	see = "table?", options = "table?", prompt = "string?", temp = "boolean?", hidden = "boolean?",
	["local"] = "table?" }
local DECLARE_ARGS = { app = "string", minutes = "number?", lease = "number?", title = "string?", hear = "table?",
	digest = "table|boolean?", pace = "table|boolean?", urgent = "table?", controls = "table?", say = "boolean?",
	see = "table?", options = "table?", prompt = "string?", hidden = "boolean?", ["local"] = "table?" }

------------------------------------------------------------------------------------------------------------------------
-- storage and the apps

local apps, order = {}, {}                              -- id -> app; ids, the addons' as declared, then the agent's
A.loggedIn = false                                      -- true from login on (Run.lua)

local function Store()
	local db = ns.db
	if not db then return nil end
	db.apps = type(db.apps) == "table" and db.apps or {}
	return db.apps
end

-- the record of an id in storage (made when asked), or nil before the saved variables are there
local function Stored(id)
	local store = Store()
	if not store then return nil end
	local r = store[id]
	if type(r) ~= "table" then
		r = {}
		store[id] = r
	end
	return r
end

-- the app's record: a temporary app's in memory, else its id's in storage
local function Record(app)
	if app.temp then return app.mem end
	return Stored(app.id)
end

local App = {}
App.__index = App

-- this character's part of the app's record ({ run, recent, last, said }; made when asked), or nil before there is a
-- character or the saved variables
local function Char(app)
	local rec, me = Record(app), Me()
	if not rec or me == nil then return nil end
	if type(rec.chars) ~= "table" then rec.chars = {} end
	local c = rec.chars[me]
	if type(c) ~= "table" then
		c = {}
		rec.chars[me] = c
	end
	return c
end

-- a record as a kit before 0.6's release kept it (run, recent, last with who at the top): each goes under its character
local function Migrate(rec)
	for _, k in ipairs({ "run", "recent", "last" }) do
		local v = rec[k]
		if type(v) == "table" and type(v.who) == "string" then
			if type(rec.chars) ~= "table" then rec.chars = {} end
			local c = rec.chars[v.who]
			if type(c) ~= "table" then
				c = {}
				rec.chars[v.who] = c
			end
			if c[k] == nil then
				v.who = nil
				c[k] = v
			end
		end
		rec[k] = nil
	end
	rec.said = nil
	if type(rec.chars) ~= "table" then rec.chars = nil end
end

-- its run of this character's, ended or not
local function Owned(app)
	local c = Char(app)
	local s = c and c.run
	if type(s) == "table" then return s end
end

-- its run while it runs
local function Run(app)
	local s = Owned(app)
	if s and (tonumber(s.ends) or 0) > time() then return s end
end

local function Title(app)
	return ns.T(app.decl.title) or app.id
end

local function Paced(app) return app.decl.pace ~= nil end
local function Digesting(app) return app.decl.pace ~= nil or app.decl.digest ~= nil end

-- the options' object: an extension-like table, so that Extension's Option, Get and ns.OptionList serve apps too
local function Duck(app)
	local duck = setmetatable({ id = app.id, title = app.decl.title, options = {}, optionOrder = {},
		db = Record(app) or app.mem }, ns.Extension)
	if Paced(app) then
		duck:Option("activity", { title = W"ACTIVITY", kind = "choice", default = "normal", hint = W"ACTIVITY_HINT",
			choices = { { value = "quiet", label = W"A_QUIET" }, { value = "normal", label = W"A_NORMAL" },
				{ value = "lively", label = W"A_LIVELY" } } })
		duck:Option("quiet", { title = W"QUIET", kind = "text", default = "", hint = W"QUIET_HINT" })
	end
	for _, name in ipairs(app.decl.optionNames) do duck:Option(name, app.decl.options[name]) end
	app.duck, app.optionOrder = duck, duck.optionOrder
end

local function Bound(app)                               -- its options read from its record once there is one
	local rec = Record(app)
	if rec then app.duck.db = rec end
	return app.duck
end

function App:Get(name)
	return Bound(self):Get(name)
end

function App:Running()
	return Run(self)
end

------------------------------------------------------------------------------------------------------------------------
-- declaring

-- the app of id made, or declared again: decl (normalized), by (addon or agent), raw (an agent's as given: compared with
-- the next one), temp (a temporary app's record is in memory)
local function New(id, decl, by, raw, temp)
	local app = apps[id]
	if not app then
		app = setmetatable({ id = id, mem = { options = {} } }, App)
		apps[id] = app
		order[#order + 1] = id
	end
	app.decl, app.by, app.raw, app.temp = decl, by, raw, temp or nil
	app.addon = decl.addon
	Duck(app)
	A.Host(app)
	return app
end

local function AgentCount()                             -- the agent's apps kept (not the temporary ones)
	local n = 0
	for _, app in pairs(apps) do
		if app.by == "agent" and not app.temp then n = n + 1 end
	end
	return n
end

local function TempCount()
	local n = 0
	for _, app in pairs(apps) do
		if app.temp then n = n + 1 end
	end
	return n
end

-- an agent's declaration (kit.app.open's or kit.app.declare's), not an addon's app: the app, and whether its declaration
-- changed (one equal to the one it has changes nothing). temp: a temporary app (kit.app.open's temp); a kept app
-- declared temporary (or the other way) ends its run, and what was kept of it goes
local function Declare(a, temp)
	if not Store() then Fail("WuxianKit's saved variables are not loaded yet") end
	local id = a.app
	local app = apps[id]
	local raw = Raw(a)
	local decl = Normalize(id, raw, true)
	local same = app ~= nil and app.by == "agent" and (app.temp == true) == temp
	if same and Equal(app.raw, raw) then return app, false end
	if not same then
		if temp and TempCount() >= TEMP_MOST then
			Fail("at most %d temporary apps run at once: stop one (kit.app.stop) or reuse its id", TEMP_MOST)
		end
		if not temp and AgentCount() >= AGENT_MOST then
			Fail("at most %d apps an agent declared are kept: reuse one (kit.apps lists them; kit.app.open with its "
				.. "id and a new declaration replaces it) or ask the player to remove one on the /wk window's Apps page",
				AGENT_MOST)
		end
	end
	if app and app.by == "agent" and not same then         -- kept <-> temporary
		A.Stop(app, "replaced", true)
		A.Unsubscribe(app)
		if temp then
			Store()[id] = nil
			app.mem = { options = {} }
		end
	end
	app = New(id, decl, "agent", raw, temp)
	if not temp then Stored(id).decl = raw end
	ns.Changed("app", id)
	return app, true
end

-- the declaration's fields a call gives, sorted (open: not minutes and lease, which are its run's too)
local function Given(a, all)
	local given = {}
	for k in pairs(DECL_FIELDS) do
		if a[k] ~= nil and (all or (k ~= "minutes" and k ~= "lease")) then given[#given + 1] = k end
	end
	table.sort(given)
	return given
end

function Kit:App(id, decl)
	if decl == nil then return apps[id] end
	local ok, n = pcall(Normalize, id, decl, false, true)
	if not ok then error(("WuxianKit:App(%s, decl): %s"):format(ns.Text(id), ns.Text(n)), 2) end
	local old = apps[id]
	if old then
		if old.temp then A.Stop(old, "replaced", true) end   -- (its record was in memory)
		A.Unsubscribe(old)                                   -- (heard again as this declaration says, below)
	end
	local app = New(id, n, "addon")
	local rec = Stored(id)
	if rec then rec.decl = nil end                       -- an agent's declaration of the same id gives way
	ns.Changed("app", id)
	if A.loggedIn then A.Resume(app) end
	return app
end

-- the player removes an app an agent declared (the window)
function ns.ForgetApp(id)
	local app = apps[id]
	if not app or app.by ~= "agent" or app.decl["local"] then return false end   -- (a local extension's: 无限工坊's)
	A.Stop(app, "player")                                -- (a temporary one goes with its run)
	if not app.temp then
		local store = Store()
		if store then store[id] = nil end
	end
	A.Drop(app)
	return true
end

-- the agent's declarations come back from storage (an entry of a source not registered yet stays); ids never go back
ns.When("load", function()
	local store = Store()
	local agents = {}
	for id, rec in pairs(store) do
		if type(rec) ~= "table" then
			store[id] = nil
		else
			Migrate(rec)
			for _, c in pairs(rec.chars or {}) do
				if type(c) == "table" and type(c.recent) == "table" then ns.BumpId(c.recent.n) end
			end
			if rec.decl ~= nil then
				if apps[id] and apps[id].by == "addon" then
					rec.decl = nil
				else
					local ok, n = pcall(Normalize, id, rec.decl, true, true)
					if ok then agents[#agents + 1] = { id, n, rec.decl } else rec.decl = nil end
				end
			end
		end
	end
	table.sort(agents, function(a, b) return a[1] < b[1] end)
	for _, x in ipairs(agents) do New(x[1], x[2], "agent", x[3]) end
	for _, app in pairs(apps) do Bound(app) end
	ns.Changed("app")
end)

------------------------------------------------------------------------------------------------------------------------
-- shared with the other files (A.loggedIn is set above)

A.W, A.LEASE, A.OPEN_ARGS, A.DECLARE_ARGS = W, LEASE, OPEN_ARGS, DECLARE_ARGS
A.Copy, A.Set, A.Me, A.Fail = Copy, Set, Me, Fail
A.Split, A.Trim = Split, Trim
A.CheckId, A.LeaseOf, A.MinutesOf, A.Given = CheckId, LeaseOf, MinutesOf, Given
A.apps, A.order, A.App = apps, order, App
A.Record, A.Char, A.Owned, A.Run, A.Title = Record, Char, Owned, Run, Title
A.Paced, A.Digesting, A.Bound = Paced, Digesting, Bound
A.Declare = Declare
