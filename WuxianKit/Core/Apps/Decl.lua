-- Apps (应用, 0.6): the finished products. Extensions are the parts (capabilities, the sources apps hear: ext:Source, and
-- the facets they see: ext:Facet, Extension.lua); the core is the runtime; an app uses extensions, and no extension knows
-- which apps there are. Outside the game, hearing the game is only through an app. An app is a declaration an agent
-- drives: what it hears (hear entries <source>:<what>, such as chat:guild, game:quest, bus:demo.*: what happened), what
-- it sees (see: facets such as me, group: how things are now; each wake carries them as state), whether and how its
-- items are gathered into wakes (a digest, Digest.lua; with pace, the player's activity and quiet hours run it), which
-- commands the player can give it in the game, how long it may go unheard from before it counts as gone (lease),
-- options the player sets for it, and its prompt: the skill an AI client follows to drive it.
-- UI/AppPanel.lua draws it (its card on its extension's page of the window, /wk <app> ...). The contract is
-- ARCHITECTURE.md section 10; in short:
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
--   WuxianKit:AppPanel(id, parent, width)      (UI/AppPanel.lua) the app's card in another addon's window
--
-- Capabilities (the core's extension "kit"; Api.lua). Keep: kit.app.declare { app, ...the declaration's fields } (the
-- whole declaration of a kept app: a field not given is its default; not started, no heartbeat), kit.app.open { app,
-- minutes?, lease?, temp? } (starts it, or goes on; temp: a table, the whole declaration of a temporary app, there for
-- this run only), kit.app.stop { app }, kit.app.forget { app } (an agent's app withdrawn: stopped with why
-- "forgotten", its declaration gone, the player's options kept). See: kit.app.describe { app } ({ app, by, temp, decl }:
-- the declaration as normalized; declared again it changes nothing), kit.app.status { app } (also the heartbeat),
-- kit.app.state { app }, kit.app.recent { app, since, limit }, kit.apps. Events: app.<id> (the app's wakes), kit.app
-- ({ app, on, why?, ends?, waiting? } when one starts, stops, or waits for what it needs).
--
-- One table says what a declaration is: FIELDS, a row a field ({ name, type, doc, check, default, status, list, addon,
-- build }). kit.app.declare's arguments and doc, the check, the defaults, the declaration as data (what is compared,
-- kept and described) and what the status and the lists copy all come from it: a new field is one row.
-- hidden is a temporary app's only (plumbing: no card, no chat lines; listed while it runs); local = { id, title } is
-- a label (the local extension of 无限工坊 an app comes with): such apps do not count among the AGENT_MOST an agent
-- keeps, at most LOCAL_MOST of them. A temporary app is in memory only, at most TEMP_MOST at once, gone once it stops
-- or the UI reloads.
--
-- For the window:
--   ns.AppList()                  the apps as kit.apps answers (each row with on, temp, hidden, waiting, local; a
--                                 hidden app only while it runs)
--   ns.App(id)                    the app object, or nil
--   ns.AppStatus(id)              as kit.app.status answers (without marking it heard from)
--   ns.AppStop(id, why)           stops it ("player" from the window)
--   ns.AppOptionList(id)          its options as kit.options answers ({ [name] = { title, kind, value, ... } })
--   ns.SetAppOption(id, name, v)  the player set one: true and the value kept, or false
--   ns.AppControls(id)            { { cmd, label } } in its declared order (label: the core's word, or the app's own)
--   ns.ForgetApp(id, wipe)        an agent's app goes: wipe = true is the player's remove (its declaration, options and
--                                 every character's record), false is kit.app.forget (the options stay); true when gone
--   ns.CONTROL_WORDS              word (English and Chinese) -> cmd, for /wk <app> <word>
-- ns.Changed("app", id) tells it when an app is declared or removed.
--
-- Storage: WuxianKitDB.apps[id] = { decl (an agent's declaration, normalized: FIELDS' data), options (the player's),
-- chars = { [the character's GUID] = { run (this run: ends, started, seen, lease, heard, wakes, lastWake, pace, quiet,
-- and the digest's options, buffer, first, last, urgentAt), recent = { n, items } (the last RING items), last = { why }
-- (how the last run ended), said = { d, n } } } }: what is the account's is at the top, what is a character's under its
-- GUID (A.Char). An addon's declaration is kept in memory only (it may carry functions) and wins over an agent's of the
-- same id; a temporary app's whole record is in memory. A record without decl is an addon's app's, or what is left of
-- an app forgotten (its options, picked up when it is declared again).
--
-- An app has its declaration twice: app.decl, as the runtime reads it (sets, labels by cmd, functions), and app.data,
-- as data (FIELDS' checks give it, every default filled in: compared, kept, described).
--
-- The runtime is four files (Core/Apps/, in load order), split by what they do:
--   Decl.lua     (this one) the fields, declarations checked and normalized, the stored record, the app object and its
--                options, declaring (WuxianKit:App, an agent's Declare, ns.ForgetApp), the declarations back from
--                storage
--   Deliver.lua  items: which wake at once, the digest host, the ring, an item into an app, app:Push
--   Run.lua      runs: quiet hours and pace, what a run hears and sees, Reconcile (the one place that decides whether
--                an app runs, waits or stops), start / stop / the ticker, the player's commands and words
--   Api.lua      kit.app.* and kit.apps, the status, and the ns functions the window uses
-- What they share is the private table ns.apps (A in each file): a name another file uses is a field of A under the
-- same name, set at the end of the file that defines it and read into a local at the top of the files loaded after it.
-- A file loaded before calls it as A.Name(...) when it runs (here: A.Host, A.Stop, A.Drop, A.Reconcile). A.loggedIn is
-- the one field that changes: always read as A.loggedIn. What only one file uses stays local there.
local addonName, ns = ...
local Kit = ns.Kit
ns.apps = ns.apps or {}
local A = ns.apps

local W = Kit:Words {
	zhCN = {
		STARTED = "%s：已开始，至 %s", STOPPED = "%s：已停止", EXPIRED = "%s：已到时间，已停止",
		LEFT = "%s：Agent 已离开，已停止", STOPPED_WHY = "%s：已停止，%s",
		EXT_OFF = "所属扩展「%s」已停用", EXT_MISSING = "所属扩展「%s」未载入", NEEDS = "需要开启「%s」扩展",
		NEEDS_SOURCE = "需要来源「%s」", NEEDS_FACET = "需要状态面「%s」",
		DECL_DROPPED = "应用「%s」的声明已失效，已移除",
		ACTIVITY = "活跃度", A_QUIET = "安静", A_NORMAL = "适中", A_LIVELY = "活跃",
		ACTIVITY_HINT = "安静：只在点名时唤醒；适中：接话、提问时唤醒，冷场时也唤醒；活跃：话题正热时也唤醒，节奏更快",
		QUIET = "免打扰时段", QUIET_HINT = "如 01:00-08:00；这段时间只在点名时唤醒",
		CONTROL = { mute = "静音", unmute = "开声", less = "少说", more = "多说", test = "试音", pause = "暂停",
			resume = "继续", stop = "停止" },
		START = "开始无限工坊的应用「%s」：先调用无限工坊 MCP 的工具 wk_docs，参数 {\"skill\": \"%s\"}，照读到的步骤做。",
	},
	enUS = {
		STARTED = "%s: started, until %s", STOPPED = "%s: stopped", EXPIRED = "%s: time is up, stopped",
		LEFT = "%s: the agent left, stopped", STOPPED_WHY = "%s: stopped. %s",
		EXT_OFF = "Its extension %s is off", EXT_MISSING = "Its extension %s is not loaded",
		NEEDS = "Needs the %s extension on", NEEDS_SOURCE = "Needs the source %s", NEEDS_FACET = "Needs the state %s",
		DECL_DROPPED = "The app %s's declaration no longer holds: removed",
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
local OPTIONS_MOST, CHOICES_MOST, HEAR_MOST, SEE_MOST, LIST_MOST = 8, 8, 16, 8, 16
local MINUTES, MINUTES_MOST, LEASE, LEASE_MOST = 120, 720, 600, 43200
-- how many apps there may be, by sort: an agent's kept, those a local extension brings (local), the temporary ones
local MOST = { agent = 8, ["local"] = 16, temp = 4 }

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

-- /wk's own words (UI/Window.lua's, which loads before this: its slash handler takes them before an app's id): no app
-- is named so
local RESERVED = ns.SLASH_WORDS

local function Copy(v)
	if type(v) ~= "table" then return v end
	local t = {}
	for k, x in pairs(v) do t[k] = Copy(x) end
	return t
end

-- a copy as data: a text given as a function (an addon's L"KEY") reads as its text now
local function Plain(v)
	if type(v) == "function" then return ns.T(v) end
	if type(v) ~= "table" then return v end
	local t = {}
	for k, x in pairs(v) do t[k] = Plain(x) end
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

-- the hear entries the sources take, from the sources registered now (hear's doc)
local function HearDoc()
	local parts = {}
	for _, name in ipairs(ns.sourceOrder) do
		local src = ns.sources[name]
		local values = ns.SourceValues(src)
		parts[#parts + 1] = ns.Text(ns.T(src.spec.doc) or (name .. ":<what>"))
			.. (values and (" (" .. table.concat(values, "|") .. ")") or "")
	end
	return table.concat(parts, "; ")
end

------------------------------------------------------------------------------------------------------------------------
-- checks. A declaration is an agent's (data only, c.agent: refused on anything out of shape) or an addon's (Lua: it
-- may carry functions, and texts as L"KEY"). Each check answers the value as data, the same whoever gave it, and the
-- same again when it is given what it answered (kit.app.describe's decl declared again changes nothing).

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

local function Words(v, what)                          -- a list of words (whys, kinds): lowercase, digits, _ and .
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
	if preset then out.wake = Words(d.wake, what .. ".wake") end
	return out
end

-- pace as data: true (the core's three), or the three with every field (one not given is the core's)
local function Pace(p, c)
	if p == false then return nil end
	if p == true then return true end
	if type(p) ~= "table" then Fail("pace is true or a table {quiet, normal, lively}") end
	if c.agent then Only(p, { quiet = true, normal = true, lively = true }, "pace") end
	local out = {}
	for _, name in ipairs(ACTIVITIES) do
		local given = p[name] and Digest(p[name], "pace." .. name, c.agent, true) or {}
		local core = PRESETS[name]
		local e = {}
		for k in pairs(PRESET_FIELDS) do
			if given[k] ~= nil then e[k] = given[k] else e[k] = Copy(core[k]) end
		end
		out[name] = e
	end
	return out
end

-- a hear entry checked by its source; kept (a remembered declaration, an addon's): one of a source not registered (yet:
-- its addon has not loaded) stays, and the app waits for it (Run.lua's Reconcile)
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

local function Hear(list, c)
	if not IsList(list) or #list > HEAR_MOST then Fail("hear is a list of at most %d sources", HEAR_MOST) end
	for _, entry in ipairs(list) do Entry(entry, c.kept) end
	return Trim(list)
end

-- see: the facets an app's wakes carry as state (ns.facets, Extension.lua)

local function FacetNames()
	local names = {}
	for i, name in ipairs(ns.facetOrder) do names[i] = name end
	table.sort(names)
	return table.concat(names, ", ")
end

-- the facets apps see, from those registered now (see's doc)
local function SeeDoc()
	local parts = {}
	for _, name in ipairs(ns.facetOrder) do
		local f = ns.facets[name]
		parts[#parts + 1] = name .. ": " .. ns.Text(ns.T(f.spec.doc) or ns.T(f.spec.title) or name)
	end
	return #parts > 0 and table.concat(parts, "; ") or "none registered"
end

-- the names, each once; kept: a facet not registered (yet) stays, and the app waits for it
local function See(list, c)
	if not IsList(list) or #list > SEE_MOST then Fail("see is a list of at most %d states (%s)", SEE_MOST, FacetNames()) end
	local out, done = {}, {}
	for _, name in ipairs(list) do
		if type(name) ~= "string" or #name > ID_MAX or not name:match("^[a-z][a-z0-9_]*$") then
			Fail("see: %s is not a state's name (the states: %s)", ns.Text(name), FacetNames())
		end
		if not ns.facets[name] and not c.kept then Fail("see: no state %s (the states: %s)", name, FacetNames()) end
		if not done[name] then
			done[name] = true
			out[#out + 1] = name
		end
	end
	return out
end

-- the controls as data: the core's as its cmd, the app's own as { cmd, label }, each cmd once
local function Controls(list, c)
	if not IsList(list) or #list > CONTROLS_MOST then
		Fail("controls is a list of at most %d: %s, or {cmd, label} of the app's own", CONTROLS_MOST,
			table.concat(CONTROL_ORDER, ", "))
	end
	local out, seen, own = {}, {}, {}
	for i, x in ipairs(list) do
		local cmd, label = x, nil
		if type(x) == "table" then                         -- the app's own: a button with its label, told as {cmd}
			if c.agent then Only(x, { cmd = true, label = true }, ("controls[%d]"):format(i)) end
			cmd = x.cmd
			if type(cmd) ~= "string" or #cmd > ID_MAX or not cmd:match("^[a-z][a-z0-9_]*$") or CONTROLS[cmd]
				or ns.CONTROL_WORDS[cmd] then
				Fail("controls[%d].cmd: a word of the app's own (lowercase letters, digits, _, at most %d bytes), not "
					.. "one of %s", i, ID_MAX, table.concat(CONTROL_ORDER, ", "))
			end
			label = Text(x.label, ("controls[%d].label"):format(i), LABEL_MAX, c.agent)
			if label == nil or (type(label) == "string" and not label:match("^%S+$")) then
				Fail("controls[%d].label: the button's text, one word without spaces (/wk <app> <label> gives it), at "
					.. "most %d bytes", i, LABEL_MAX)
			end
		elseif not CONTROLS[x] then
			Fail("controls: %s is not one of %s (or {cmd, label} of the app's own)", ns.Text(x),
				table.concat(CONTROL_ORDER, ", "))
		end
		if not seen[cmd] then
			seen[cmd] = true
			out[#out + 1] = label ~= nil and { cmd = cmd, label = label } or cmd
			if label ~= nil then own[#own + 1] = { i = i, cmd = cmd, text = ns.T(label) } end
		end
	end
	-- /wk <app> <word> takes the core's words first, then a cmd or a label: a label that is one of those names
	-- another control, or none
	for _, a in ipairs(own) do
		if ns.CONTROL_WORDS[a.text] or ns.CONTROL_WORDS[a.text:lower()] then
			Fail("controls[%d].label: %s is one of the core's words (/wk <app> %s gives the core's command)", a.i,
				ns.Text(a.text), ns.Text(a.text))
		end
		for _, b in ipairs(own) do
			if b ~= a and (b.text == a.text or b.cmd == a.text:lower()) then
				Fail("controls[%d].label: %s is also controls[%d]'s %s", a.i, ns.Text(a.text), b.i,
					b.text == a.text and "label" or "cmd")
			end
		end
	end
	return out
end

local OPTION_FIELDS = { kind = true, title = true, default = true, hint = true, choices = true, min = true, max = true,
	step = true, unit = true, order = true }

local function Option(name, o, c)
	if type(name) ~= "string" or #name > ID_MAX or not name:match("^[a-z][a-z0-9_]*$") then
		Fail("options: %s is not a name (lowercase letters, digits and _, at most %d bytes)", ns.Text(name), ID_MAX)
	end
	if c.data.pace ~= nil and (name == "activity" or name == "quiet") then
		Fail("options: %s is the core's own option of an app with pace", name)
	end
	if type(o) ~= "table" then Fail("options.%s is a table {kind, title, default, ...}", name) end
	local what, agent = "options." .. name, c.agent
	if agent then Only(o, OPTION_FIELDS, what) end
	local kind = o.kind or "boolean"
	if not OPTION_KINDS[kind] then Fail("%s.kind is boolean, text, number, choice or list", what) end
	local spec = { kind = kind, title = Text(o.title, what .. ".title", TITLE_MAX, agent) or name,
		hint = Text(o.hint, what .. ".hint", HINT_MAX, agent), unit = Text(o.unit, what .. ".unit", LABEL_MAX, agent),
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
		local list = o.choices
		if not IsList(list) or #list == 0 or (agent and #list > CHOICES_MOST) then
			Fail("%s.choices is a list of 1 to %d {value, label}", what, CHOICES_MOST)
		end
		spec.choices = {}
		for i, x in ipairs(list) do
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

-- the options as data: name -> { kind, title, default, ... } (an addon's `changed` is not data: build takes it)
local function Options(t, c)
	if type(t) ~= "table" or IsList(t) and #t > 0 then Fail("options is a table {name = {kind, title, ...}}") end
	local out, n = {}, 0
	for name, o in pairs(t) do
		out[name] = Option(name, o, c)
		n = n + 1
	end
	if c.agent and n > OPTIONS_MOST then Fail("an app has at most %d options (it gave %d)", OPTIONS_MOST, n) end
	return out
end

local function CheckId(id)
	if type(id) ~= "string" or #id > ID_MAX or not id:match("^[a-z][a-z0-9_]*$") then
		Fail("an app's id is lowercase letters, digits and _, starting with a letter, at most %d bytes (not %s)", ID_MAX,
			ns.Text(id))
	end
	if RESERVED[id] then Fail("an app's id is not %s: /wk %s is the window's own command", id, id) end
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

-- an addon's docs: a folder in its addon's ("Apps/Officers"), as given with / and no slash at either end
local function Docs(v)
	if type(v) ~= "string" then Fail("docs is a folder in the addon's, such as \"Apps/Officers\"") end
	v = v:gsub("\\", "/"):gsub("^/+", ""):gsub("/+$", "")
	return v ~= "" and v or nil
end

local function Name(v)                                  -- an addon's or an extension's name, or none
	return type(v) == "string" and v ~= "" and v or nil
end

------------------------------------------------------------------------------------------------------------------------
-- the fields of a declaration, in the order they are checked (a check may read those before it in c.data). A row:
--   name
--   type     as kit.app.declare takes it (Schema.lua); none: not an argument
--   doc      for the agent: a text, or a function (hear and see say what is registered now)
--   check    (v, c) -> the value as data, for a value given; c = { id, agent, kept, temp, data (the fields so far) }
--   default  the data when none is given (or a function of c)
--   status   true: kit.app.status carries it      list   true: kit.apps and the manifest carry it
--   addon    true: only an addon's declaration has it
--   build    (n, v, c, d) puts it into the runtime's declaration n, from the data v and the declaration given d
--            (functions are there); without one n[name] = v

local FIELDS = {}

local function Field(f)
	FIELDS[#FIELDS + 1] = f
	FIELDS[f.name] = f
end

local function Fn(name)                                 -- an addon's function: not data
	return { name = name, addon = true, check = function() return nil end, build = function(n, _, _, d)
		n[name] = type(d[name]) == "function" and d[name] or nil
	end }
end

Field { name = "title", type = "string?", status = true,
	doc = ("at most %d bytes; default: the id"):format(TITLE_MAX),
	check = function(v, c) return Text(v, "title", TITLE_MAX, c.agent) end,
	default = function(c) return c.id end }

Field { name = "hear", type = "table?", status = true,
	doc = function() return ("at most %d entries <source>:<what>: %s"):format(HEAR_MOST, HearDoc()) end,
	check = Hear, default = {} }

Field { name = "see", type = "table?", status = true,
	doc = function()
		return ("at most %d states each wake carries as state {name = the state at that wake}; kit.app.state reads "
			.. "them at once: %s"):format(SEE_MOST, SeeDoc())
	end,
	check = See, default = {} }

Field { name = "pace", type = "table|boolean?",
	doc = "true: the player's activity quiet|normal|lively and quiet hours set the rhythm; or {quiet, normal, lively} "
		.. "of {gather, every, idle, most, wake = [whys]}",
	check = Pace,
	build = function(n, v)
		if v == nil then return end
		n.pace = Copy(v == true and PRESETS or v)
		for _, name in ipairs(ACTIVITIES) do n.pace[name].wakeSet = Set(n.pace[name].wake) end
	end }

Field { name = "digest", type = "table|boolean?",
	doc = "{gather, every, idle, most} or true: its items gathered into wakes; none: each item is a wake; pace has "
		.. "its own",
	check = function(v, c)
		if v == false or c.data.pace ~= nil then return nil end
		if v == true then return true end
		local out = Digest(v, "digest", c.agent)
		return next(out) ~= nil and out or true
	end,
	build = function(n, v)
		if v ~= nil then n.digest = v == true and {} or v end
	end }

Field { name = "urgent", type = "table?",
	doc = ("at most %d whys or kinds that wake within gather seconds, without pace"):format(LIST_MOST),
	check = function(v, c)
		if not c.agent and type(v) == "function" then return nil end   -- (an addon's own test: build takes it)
		return Words(v, "urgent")
	end,
	build = function(n, v, _, d)
		if type(d.urgent) == "function" then n.urgent = d.urgent elseif v then n.urgentSet = Set(v) end
	end }

Field { name = "controls", type = "table?", status = true,
	doc = ("the player's commands, buttons on its card and /wk <app> <word>: %s; or one of the app's own, {cmd, label} "
		.. "(label: one word, at most %d bytes, not a word of the core's nor another's label or cmd); at most %d, each "
		.. "told as a control item {cmd}"):format(table.concat(CONTROL_ORDER, ", "), LABEL_MAX, CONTROLS_MOST),
	check = Controls, default = {},
	build = function(n, v)
		n.controls, n.labels = {}, {}
		for _, x in ipairs(v) do
			local cmd = type(x) == "table" and x.cmd or x
			n.controls[#n.controls + 1] = cmd
			if type(x) == "table" then n.labels[cmd] = x.label end
		end
	end }

Field { name = "say", type = "boolean?", status = true,
	doc = "the player may talk to you: /wk <app> <words>",
	check = function(v) return Bool(v, "say") end, default = false }

Field { name = "lease", type = "number?",
	doc = ("seconds without a heartbeat of yours (kit.app.open, status, state or recent) before it stops, default %d, "
		.. "0 none, at least %d, at most %d")
		:format(LEASE, ns.Lease(1), LEASE_MOST),
	check = function(v) return LeaseOf(v, "lease") or 0 end, default = LEASE,
	build = function(n, v) n.lease = v > 0 and v or nil end }

Field { name = "minutes", type = "number?",
	doc = ("how long a run lasts, default %d, at most %d"):format(MINUTES, MINUTES_MOST),
	check = function(v) return MinutesOf(v, "minutes") end, default = MINUTES }

Field { name = "options", type = "table?",
	doc = ("at most %d the player sets: name -> {kind boolean|text|number|choice|list, title, default, hint, choices "
		.. "[{value, label}] (at most %d), min, max, step, unit, order}"):format(OPTIONS_MOST, CHOICES_MOST),
	check = Options, default = {},
	build = function(n, v, c, d)
		n.options, n.optionNames = {}, {}
		for name, spec in pairs(v) do
			local o = Copy(spec)
			local given = not c.agent and type(d.options) == "table" and d.options[name]
			if type(given) == "table" and type(given.changed) == "function" then o.changed = given.changed end
			n.options[name] = o
			n.optionNames[#n.optionNames + 1] = name
		end
		table.sort(n.optionNames, function(a, b)            -- by order (when given), then by name
			local ra, rb = n.options[a].order or math.huge, n.options[b].order or math.huge
			if ra ~= rb then return ra < rb end
			return a < b
		end)
	end }

Field { name = "prompt", type = "string?", list = true,
	doc = "the name of the skill an AI client follows to drive it",
	check = function(v)
		if type(v) ~= "string" or #v > TITLE_MAX or not v:match("^[a-z0-9][a-z0-9_%-]*$") then
			Fail("prompt is a skill's name (lowercase letters, digits, - and _)")
		end
		return v
	end }

Field { name = "hidden", type = "boolean?", status = true, list = true,
	doc = "true, in kit.app.open's temp only: plumbing of a program, such as 无限工坊's reactions: no card and no chat "
		.. "line when it starts or stops; while it runs the /wk window lists it as listening in the background",
	check = function(v, c)
		if Bool(v, "hidden") and not c.temp then
			Fail("hidden is a temporary app's only (kit.app.open's temp): an app that is kept has its card")
		end
		return v or nil
	end }

Field { name = "local", type = "table?", status = true, list = true,
	doc = ("{id, title}: the local extension of 无限工坊 the app comes with, a label on its card; such apps do not "
		.. "count among the %d an agent keeps, at most %d of them"):format(MOST.agent, MOST["local"]),
	check = function(v)
		if type(v) ~= "table" or type(v.id) ~= "string" or #v.id > ID_MAX or not v.id:match("^[a-z][a-z0-9_]*$") then
			Fail("local is {id, title}: the local extension of 无限工坊 the app comes with (id: lowercase letters, "
				.. "digits, _, at most %d bytes)", ID_MAX)
		end
		return { id = v.id, title = Text(v.title, "local.title", TITLE_MAX, true) or v.id }
	end }

Field { name = "addon", addon = true, check = Name }
Field { name = "extension", addon = true, list = true, check = Name }
Field { name = "docs", addon = true, check = Docs }
Field(Fn("check"))
Field(Fn("enrich"))

-- what an agent's declaration may name, and kit.app.declare's arguments
local AGENT_FIELDS, DECLARE_ARGS = {}, { app = "string" }
for _, f in ipairs(FIELDS) do
	if not f.addon then AGENT_FIELDS[f.name] = true end
	if f.type then DECLARE_ARGS[f.name] = f.type end
end

-- the fields as kit.app.declare's doc tells them, from what is registered now
local function FieldDocs()
	local parts = {}
	for _, f in ipairs(FIELDS) do
		if f.type then
			local doc = f.doc
			if type(doc) == "function" then doc = doc() end
			parts[#parts + 1] = ("%s (%s)"):format(f.name, doc)
		end
	end
	return table.concat(parts, ", ")
end

-- decl (an agent's table, or an addon's) -> the declaration as the runtime reads it, and as data. c: agent (an agent's:
-- data only), kept (a remembered or an addon's declaration: an entry of a source not registered yet stays), temp (a
-- temporary app's)
local function Normalize(id, d, c)
	CheckId(id)
	if type(d) ~= "table" then Fail("a declaration is a table") end
	if c.agent then Only(d, AGENT_FIELDS, "the declaration") end
	local n, data = {}, {}
	c.id, c.data = id, data
	for _, f in ipairs(FIELDS) do
		local v = d[f.name]
		if f.addon and c.agent then v = nil end
		if v ~= nil then v = f.check(v, c) end
		if v == nil then
			v = f.default
			if type(v) == "function" then v = v(c) else v = Copy(v) end
		end
		data[f.name] = v
		if f.build then f.build(n, v, c, d) else n[f.name] = v end
	end
	return n, data
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

-- the app of id made, or declared again: decl (as the runtime reads it), by (addon or agent), data (the declaration as
-- data), temp (a temporary app's record is in memory)
local function New(id, decl, by, data, temp)
	local app = apps[id]
	if not app then
		app = setmetatable({ id = id, mem = { options = {} } }, App)
		apps[id] = app
		order[#order + 1] = id
	end
	app.decl, app.by, app.data, app.temp = decl, by, data, temp or nil
	app.addon = decl.addon
	Duck(app)
	A.Host(app)
	return app
end

-- an agent's app's sort, as the limits count them: temp, local (a local extension's) or agent
local function Sort(temp, data)
	return temp and "temp" or data["local"] and "local" or "agent"
end

local function Count(sort)
	local n = 0
	for _, app in pairs(apps) do
		if app.by == "agent" and Sort(app.temp, app.data) == sort then n = n + 1 end
	end
	return n
end

local FULL = {
	temp = "at most %d temporary apps run at once: stop one (kit.app.stop) or reuse its id",
	agent = "at most %d apps an agent declared are kept: declare one again under its id (kit.apps lists them), "
		.. "withdraw one (kit.app.forget) or ask the player to remove one in the /wk window (each has a page under "
		.. "Agent 应用, with 移除)",
	["local"] = "at most %d apps of local extensions are kept: withdraw one (kit.app.forget)",
}

-- an agent's declaration, whole (d: its fields; one not given is its default): kit.app.declare's (kept), or
-- kit.app.open's temp (temp: a temporary app). The app, and whether its declaration changed (one equal to the one it
-- has changes nothing). A kept app declared temporary (or the other way) ends its run, why "replaced"; what the player
-- set for it stays in storage
local function Declare(id, d, temp)
	if not Store() then Fail("WuxianKit's saved variables are not loaded yet") end
	CheckId(id)
	local app = apps[id]
	if app and app.by == "addon" then
		Fail("app %s is an addon's (%s): its declaration is the addon's; kit.app.open {app} starts it", id,
			ns.Text(app.addon or "?"))
	end
	local n, data = Normalize(id, d, { agent = true, temp = temp })
	local same = app ~= nil and (app.temp == true) == temp
	if same and Equal(app.data, data) then return app, false end
	local sort = Sort(temp, data)
	if not (app and Sort(app.temp, app.data) == sort) and Count(sort) >= MOST[sort] then Fail(FULL[sort], MOST[sort]) end
	if app and not same then                              -- kept <-> temporary
		A.Stop(app, "replaced", true)
		if temp then
			Stored(id).decl = nil
			app.mem = { options = {} }
		end
	end
	app = New(id, n, "agent", data, temp)
	if not temp then Stored(id).decl = data end
	ns.Changed("app", id)
	A.Reconcile(app)                                     -- (one that runs goes on as the declaration now says)
	return app, true
end

function Kit:App(id, decl)
	if decl == nil then return apps[id] end
	local ok, n, data = pcall(Normalize, id, decl, { kept = true })
	if not ok then error(("WuxianKit:App(%s, decl): %s"):format(ns.Text(id), ns.Text(n)), 2) end
	local old = apps[id]
	if old and old.temp then A.Stop(old, "replaced", true) end   -- (its record was in memory)
	local app = New(id, n, "addon", data)
	local rec = Stored(id)
	if rec then rec.decl = nil end                       -- an agent's declaration of the same id gives way
	ns.Changed("app", id)
	A.Reconcile(app)
	return app
end

-- an agent's app goes. wipe: the player removes it (the window): its record goes whole. Without: kit.app.forget (无限工坊
-- withdraws a local extension's app when the extension goes): the declaration goes and no character's run stays, the
-- player's options and the rings wait for it to be declared again
function ns.ForgetApp(id, wipe)
	local app = apps[id]
	if not app or app.by ~= "agent" then return false end
	A.Stop(app, wipe and "player" or "forgotten")        -- (a temporary one goes with its run)
	local store = not app.temp and Store()
	local rec = store and store[id]
	if wipe and store then
		store[id] = nil
	elseif type(rec) == "table" then
		rec.decl = nil
		for _, c in pairs(type(rec.chars) == "table" and rec.chars or {}) do
			if type(c) == "table" and c.run ~= nil then c.run, c.last = nil, { why = "forgotten" } end
		end
	end
	A.Drop(app)
	return true
end

-- the agent's declarations come back from storage (an entry of a source not registered yet stays); ids never go back.
-- One that no longer holds goes with its record, and the player is told at login (the chat frame keeps no line before)
local dropped = {}

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
					local ok, n, data = pcall(Normalize, id, rec.decl, { agent = true, kept = true })
					if ok then
						rec.decl = data
						agents[#agents + 1] = { id, n, data }
					else
						store[id] = nil
						dropped[#dropped + 1] = id
					end
				end
			end
		end
	end
	table.sort(agents, function(a, b) return a[1] < b[1] end)
	for _, x in ipairs(agents) do New(x[1], x[2], "agent", x[3]) end
	for _, app in pairs(apps) do Bound(app) end
	ns.Changed("app")
end)

ns.When("login", function()
	table.sort(dropped)
	for _, id in ipairs(dropped) do ns.Say(W.DECL_DROPPED:format(ns.Escape(ns.Text(id)))) end
	dropped = {}
end)

------------------------------------------------------------------------------------------------------------------------
-- shared with the other files (A.loggedIn is set above)

A.W, A.LEASE, A.MOST, A.ID_MAX = W, LEASE, MOST, ID_MAX
A.FIELDS, A.DECLARE_ARGS, A.FieldDocs = FIELDS, DECLARE_ARGS, FieldDocs
A.Copy, A.Plain, A.Set, A.Me, A.Fail = Copy, Plain, Set, Me, Fail
A.Split, A.Trim = Split, Trim
A.CheckId, A.LeaseOf, A.MinutesOf = CheckId, LeaseOf, MinutesOf
A.apps, A.order, A.App = apps, order, App
A.Record, A.Char, A.Owned, A.Run, A.Title = Record, Char, Owned, Run, Title
A.Paced, A.Digesting, A.Bound = Paced, Digesting, Bound
A.Declare = Declare
