-- Apps (应用, 0.6): the finished products. Extensions are the parts (capabilities, and the sources apps hear: ext:Source,
-- Extension.lua); the core is the runtime; an app uses extensions, and no extension knows which apps there are. Outside
-- the game, hearing the game is only through an app. An app is a declaration and its driver: what it hears (hear
-- entries <source>:<what>, such as chat:guild, game:quest, bus:demo.*), whether and how its items are gathered into wakes
-- (a digest, Digest.lua; with pace, the player's activity and quiet hours run it), which commands the player can give it
-- in the game, how long it may go unheard from before it counts as gone (lease), and options the player sets for it; its
-- driver is a prompt (an AI client follows the skill it names) or a program (one on this computer, which 无限工坊 loads).
-- K2 draws it (UI/AppPanel.lua, the window's 应用 page, /wk <app> ...). The contract is ARCHITECTURE.md section 10; in
-- short:
--
--   WuxianKit:App(id, decl) -> app       an addon declares an app (functions allowed: check, urgent, enrich; docs: the
--                                        folder of its AGENT.md and skills/ in its addon's); with no decl, the app
--                                        declared before (or nil)
--   app:Get(name)                        one of its options (as ext:Get)
--   app:Running()                        its run while it runs ({ ends, started, ... }), else nil
--   app:Push(data) -> boolean            an item of its own ({ source = "addon", data }) while it runs
--   WuxianKit:AppControl(id, cmd) -> boolean   the player's command (one of the app's controls; "stop" stops it too)
--   WuxianKit:AppSay(id, text) -> boolean      the player's words to the app (decl.say)
--   WuxianKit:AppPanel(id, parent, width)      (UI/AppPanel.lua, K2) the app's card in another addon's window
--
-- Capabilities (the core's extension "kit"): kit.app.open { app, ...decl, temp, minutes, lease }, kit.app.declare
-- { app, ...decl, launch } (kept, not started, no heartbeat), kit.app.status { app } (also the heartbeat), kit.app.stop
-- { app }, kit.app.recent { app, since, limit }, kit.apps. Events: app.<id> (the app's wakes: { app, reason, items,
-- skipped, pace?, quiet? }; an extension's event as far as the link's rate goes), kit.app ({ app, on, why?, ends? } when
-- one starts or stops), kit.app.launch ({ app }: the player wants a program's app started).
-- A declaration's driver is "prompt" or "program" (none given with a prompt: "prompt"; "prompt" needs one). temp = true
-- (kit.app.open's): a temporary app, in memory only, at most TEMP_MOST at once and not one of the AGENT_MOST kept, gone
-- once it stops or the UI reloads. launch = true (kit.app.declare's, in memory: 无限工坊 declares again after each
-- kit.ready): 无限工坊 loads its program, so the player can start it (kit.app.launch). Neither counts when two
-- declarations are compared.
--
-- For the window (K2):
--   ns.AppList()                  the apps as kit.apps answers (start: the start line, for an app with a prompt;
--                                 launching: kit.app.launch went in the last LAUNCH_WAIT s and the app has not started)
--   ns.App(id)                    the app object, or nil
--   ns.AppStatus(id)              as kit.app.status answers (without marking it heard from)
--   ns.AppStop(id, why)           stops it ("player" from the window)
--   ns.AppOptionList(id)          its options as kit.options answers ({ [name] = { title, kind, value, ... } })
--   ns.SetAppOption(id, name, v)  the player set one: true and the value kept, or false
--   ns.AppControls(id)            { { cmd, label } } in its declared order
--   ns.ForgetApp(id)              the player removes an app an agent declared
--   ns.AppLaunch(id)              the player starts a program's app: kit.app.launch; true, or false and why not (their words)
--   ns.WorkshopOnline()           whether 无限工坊 is linked now (Kit:AgentOnline)
--   ns.CONTROL_WORDS              word (English and Chinese) -> cmd, for /wk <app> <word>
-- ns.Changed("app", id) tells it when an app is declared, removed, or starts or stops launching.
--
-- Storage: WuxianKitDB.apps[id] = { decl (an agent's declaration, as it was given and checked), run (this run: who =
-- the character's GUID, ends, started, seen, lease, heard, wakes, lastWake, pace, quiet, and the digest's options,
-- buffer, first, last, urgentAt), recent = { who, n, items } (the last RING items of the character's), options (the
-- player's), said = { d, n } }. An addon's declaration is kept in memory only (it may carry functions) and wins over an
-- agent's of the same id; a temporary app's whole record is in memory.
local addonName, ns = ...
local Kit = ns.Kit

local W = Kit:Words {
	zhCN = {
		STARTED = "%s：已开始，至 %s", STOPPED = "%s：已停止", EXPIRED = "%s：已到时间，已停止",
		LEFT = "%s：Agent 已离开，已停止", EXT_STOPPED = "%s：所属扩展已停用，已停止",
		EXT_OFF = "所属扩展「%s」已停用", NEEDS = "需要开启「%s」扩展", NEEDS_SOURCE = "需要来源「%s」",
		ACTIVITY = "活跃度", A_QUIET = "安静", A_NORMAL = "适中", A_LIVELY = "活跃",
		ACTIVITY_HINT = "安静：只在点名时唤醒；适中：接话、提问时唤醒，冷场时也唤醒；活跃：话题正热时也唤醒，节奏更快",
		QUIET = "免打扰时段", QUIET_HINT = "如 01:00-08:00；这段时间只在点名时唤醒",
		CONTROL = { mute = "静音", unmute = "开声", less = "少说", more = "多说", test = "试音", pause = "暂停",
			resume = "继续", stop = "停止" },
		START = "开始无限工坊的应用「%s」：先调用无限工坊 MCP 的工具 wk_docs，参数 {\"skill\": \"%s\"}，照读到的步骤做。",
		NO_APP = "没有应用 %s", PROGRAM = "由本机程序驱动", OFFLINE = "需要无限工坊在运行", RUNNING = "已在运行",
		LAUNCHING = "启动中…",
	},
	enUS = {
		STARTED = "%s: started, until %s", STOPPED = "%s: stopped", EXPIRED = "%s: time is up, stopped",
		LEFT = "%s: the agent left, stopped", EXT_STOPPED = "%s: its extension was turned off, stopped",
		EXT_OFF = "Its extension %s is off", NEEDS = "Needs the %s extension on", NEEDS_SOURCE = "Needs the source %s",
		ACTIVITY = "Activity", A_QUIET = "Quiet", A_NORMAL = "Normal", A_LIVELY = "Lively",
		ACTIVITY_HINT = "Quiet: wakes only when you are named; Normal: also for follow-ups, questions and lulls; "
			.. "Lively: also when the talk is hot, faster",
		QUIET = "Quiet hours", QUIET_HINT = "Such as 01:00-08:00; only wakes when you are named then",
		CONTROL = { mute = "Mute", unmute = "Unmute", less = "Less", more = "More", test = "Test", pause = "Pause",
			resume = "Resume", stop = "Stop" },
		START = "Start the 无限工坊 app \"%s\": first call the 无限工坊 MCP tool wk_docs with {\"skill\": \"%s\"} and follow the steps "
			.. "it gives.",
		NO_APP = "No app %s", PROGRAM = "Driven by a program on this computer", OFFLINE = "Needs 无限工坊 running",
		RUNNING = "Already running", LAUNCHING = "Starting…",
	},
}

local ID_MAX, TITLE_MAX, HINT_MAX, LABEL_MAX, WORD_MAX = 24, 48, 120, 24, 32
local AGENT_MOST, TEMP_MOST, OPTIONS_MOST, CHOICES_MOST, HEAR_MOST, LIST_MOST = 8, 4, 8, 8, 16, 16
local RING, MINUTES, MINUTES_MOST, LEASE, LEASE_MOST, SAY_MAX = 100, 120, 720, 600, 43200, 255
local LAUNCH_WAIT = 30

local CONTROL_ORDER = { "mute", "unmute", "less", "more", "test", "pause", "resume", "stop" }
local CONTROLS = {}
for _, c in ipairs(CONTROL_ORDER) do CONTROLS[c] = true end
local OPTION_KINDS = { boolean = true, text = true, number = true, choice = true, list = true }
local ACTIVITIES = { "quiet", "normal", "lively" }
local DRIVERS = { prompt = true, program = true }

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
-- quiet hours: "01:00-08:00" (also a full-width colon, ～ ~ – —, 至, 到, hours alone "1-8"; across midnight too)

-- the window as minutes of the day (from, to), or nil when the text gives none
function ns.QuietWindow(text)
	if type(text) ~= "string" then return nil end
	text = text:gsub("：", ":"):gsub("–", "-"):gsub("—", "-"):gsub("～", "-"):gsub("~", "-"):gsub("至", "-"):gsub("到", "-")
	local h1, m1, h2, m2 = text:match("^%s*(%d%d?):(%d%d)%s*%-+%s*(%d%d?):(%d%d)%s*$")
	if not h1 then
		h1, h2 = text:match("^%s*(%d%d?)%s*%-+%s*(%d%d?)%s*$")
		m1, m2 = "0", "0"
	end
	h1, m1, h2, m2 = tonumber(h1), tonumber(m1), tonumber(h2), tonumber(m2)
	if not (h1 and m1 and h2 and m2) or h1 > 24 or h2 > 24 or m1 > 59 or m2 > 59 then return nil end
	local from, to = (h1 * 60 + m1) % 1440, (h2 * 60 + m2) % 1440
	if from == to then return nil end
	return from, to
end

-- whether the clock is in the quiet hours a text gives (false for none)
function ns.InQuiet(text)
	local from, to = ns.QuietWindow(text)
	if not from then return false end
	local t = date("*t", time())
	local now = t.hour * 60 + t.min
	if from < to then return now >= from and now < to end
	return now >= from or now < to
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

local DECL_FIELDS = { title = true, hear = true, digest = true, pace = true, urgent = true, controls = true, say = true,
	me = true, lease = true, minutes = true, options = true, prompt = true, driver = true }

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
	n.controls = {}
	if d.controls ~= nil then
		if not IsList(d.controls) then Fail("controls is a list (of %s)", table.concat(CONTROL_ORDER, ", ")) end
		local seen = {}
		for _, c in ipairs(d.controls) do
			if not CONTROLS[c] then Fail("controls: %s is not one of %s", ns.Text(c), table.concat(CONTROL_ORDER, ", ")) end
			if not seen[c] then
				seen[c] = true
				n.controls[#n.controls + 1] = c
			end
		end
	end
	n.say = Bool(d.say, "say") or false
	n.me = Bool(d.me, "me") or false
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
	if d.driver ~= nil then
		if not DRIVERS[d.driver] then Fail("driver is \"prompt\" or \"program\"") end
		n.driver = d.driver
	elseif n.prompt then
		n.driver = "prompt"
	end
	if n.driver == "prompt" and not n.prompt then Fail("driver \"prompt\" goes with prompt (a skill's name)") end
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
-- temp, not launch)
local function Raw(a)
	local raw = {}
	for k in pairs(DECL_FIELDS) do raw[k] = Copy(a[k]) end
	return raw
end

------------------------------------------------------------------------------------------------------------------------
-- storage and the apps

local apps, order = {}, {}                              -- id -> app; ids, the addons' as declared, then the agent's
local loggedIn = false

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

-- its run of this character's, ended or not
local function Owned(app)
	local rec = Record(app)
	local s = rec and rec.run
	if type(s) == "table" and s.who ~= nil and s.who == Me() then return s end
end

-- its run while it runs
local function Run(app)
	local s = Owned(app)
	if s and (tonumber(s.ends) or 0) > time() then return s end
end

local function Title(app)
	return ns.T(app.decl.title) or app.id
end

-- the start line (启动语): one sentence for any AI client with 无限工坊's MCP tools, in the language in force, that
-- points it at the app's skill; nil for an app without a prompt
local function StartLine(app)
	local prompt = app.decl.prompt
	if type(prompt) ~= "string" or prompt == "" then return nil end
	return W.START:format(ns.Text(Title(app)), prompt)
end

-- an addon's app's docs as the manifest gives a folder: under Interface\AddOns ("WuxianKit/Apps/Guild"), or nil
local function DocsPath(app)
	local docs, addon = app.decl.docs, app.decl.addon
	if docs and addon then return addon .. "/" .. docs end
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
-- pace and the digest

local function Urgent(app, item)
	if item.source == "control" or item.source == "player" then return true end
	local d = app.decl
	if d.pace then
		local s = Owned(app)
		if s and s.quiet then return item.why == "mention" end
		local p = d.pace[s and s.pace or "normal"] or d.pace.normal
		return (item.why ~= nil and p.wakeSet[item.why] == true) or (item.kind ~= nil and p.wakeSet[item.kind] == true)
	end
	if d.urgent then
		local ok, yes = pcall(d.urgent, item)
		if not ok then geterrorhandler()(yes) return false end
		return yes and true or false
	end
	if d.urgentSet then
		return (item.why ~= nil and d.urgentSet[item.why] == true) or (item.kind ~= nil and d.urgentSet[item.kind] == true)
	end
	return false
end

-- the run's digest as the declaration, the player's activity and the quiet hours make it now (in place)
local function Retune(app, s)
	local d = app.decl
	s.options = type(s.options) == "table" and s.options or {}
	local dg = {}
	if d.pace then
		local activity = app:Get("activity")
		local p = d.pace[activity] or d.pace.normal
		local quiet = ns.InQuiet(app:Get("quiet"))
		dg.gather, dg.every, dg.idle, dg.most = p.gather, p.every, p.idle, p.most
		if quiet then dg.every, dg.idle = false, false end
		s.pace, s.quiet = d.pace[activity] and activity or "normal", quiet
	else
		for k, v in pairs(d.digest or {}) do dg[k] = v end
		s.pace, s.quiet = nil, nil
	end
	s.options.digest = dg
end

local function Host(app)
	app.host = {
		ext = ns.extensions.kit,
		spec = { digest = { urgent = function(_, _, item) return Urgent(app, item) end } },
		Wrap = function(_, s)
			local w = { app = app.id }
			if app.decl.pace then w.pace, w.quiet = s.pace or "normal", s.quiet and true or false end
			return w
		end,
		Send = function(_, data) Kit:Emit("app." .. app.id, data) end,
	}
end

------------------------------------------------------------------------------------------------------------------------
-- the ring

local function Ring(app)
	local rec = Record(app)
	if not rec then return nil end
	local r, me = rec.recent, Me()
	if type(r) ~= "table" or r.who ~= me or type(r.items) ~= "table" then
		r = { who = me, n = 0, items = {} }
		rec.recent = r
	end
	return r
end

local function Keep(app, item)
	local r = Ring(app)
	if not r then return end
	r.n = math.max(tonumber(r.n) or 0, item.id)
	r.items[#r.items + 1] = ns.Digest.Small(item)
	while #r.items > RING do table.remove(r.items, 1) end
end

local function Recent(app, since, limit)
	return ns.RingRecent((Ring(app) or { items = {} }).items, since, limit, RING)
end

------------------------------------------------------------------------------------------------------------------------
-- items

-- an item heard while the app runs, from source (a registered source's name, or the app's own: addon, control,
-- player): stamped, enriched, kept, gathered or sent; me: the source gives the player to an app that declared me;
-- immediate: the wake goes at once (control and player items)
local function Deliver(app, source, item, immediate, me)
	local s = Run(app)
	if not s or type(item) ~= "table" then return false end
	item.source = source
	if me and app.decl.me then item.me = Kit:Me() end
	if ns.Finite(item.id) then ns.BumpId(item.id) else item.id = Kit:NewId() end
	if item.time == nil then item.time = time() end
	if app.decl.enrich then
		local ok, err = pcall(app.decl.enrich, item)
		if not ok then geterrorhandler()(err) end
	end
	s.heard = (s.heard or 0) + 1
	Keep(app, item)
	if Digesting(app) then
		ns.Digest.Gather(app.host, s, item)
		if immediate and #(s.buffer or {}) > 0 then ns.Digest.Wake(app.host, s, "urgent") end
	else
		s.buffer, s.first, s.urgentAt = { item }, nil, nil
		ns.Digest.Wake(app.host, s, "item")
	end
	return true
end

-- each entry of a registered source subscribed (one of a source not registered yet: when it is); what a source gives
-- while its extension is off is not heard
local function Subscribe(app)
	if app.subs then return end
	app.subs = {}
	for _, entry in ipairs(Trim(app.decl.hear)) do
		local name, what = Split(entry)
		local src = name and ns.sources[name]
		if src then
			local me = src.spec.me == true
			local ok, t = pcall(src.spec.on, src.ext, what, function(item)
				if src.ext.active then Deliver(app, name, item, false, me) end
			end)
			if ok then app.subs[#app.subs + 1] = { src = src, token = t } else geterrorhandler()(t) end
		end
	end
end

local function Unsubscribe(app)
	for _, sub in ipairs(app.subs or {}) do pcall(sub.src.spec.off, sub.src.ext, sub.token) end
	app.subs = nil
end

-- whether the app hears an entry of source name
local function HearsFrom(app, name)
	for _, entry in ipairs(app.decl.hear) do
		if Split(entry) == name then return true end
	end
	return false
end

------------------------------------------------------------------------------------------------------------------------
-- runs: start, stop, the ticker

local ticker

-- the app goes (a temporary one once it stops, one the player removed)
local function Drop(app)
	Unsubscribe(app)
	if apps[app.id] ~= app then return end
	apps[app.id] = nil
	for i, x in ipairs(order) do
		if x == app.id then
			table.remove(order, i)
			break
		end
	end
	ns.Changed("app", app.id)
end

local STOP_WORDS = { stopped = "STOPPED", player = "STOPPED", expired = "EXPIRED", left = "LEFT", extension = "EXT_STOPPED" }

-- stops this character's run (why: stopped, player, expired, left, extension, replaced); quiet: no chat line. A
-- temporary app goes with its run (unless it is replaced: a new run of it follows)
local function Stop(app, why, quiet)
	local rec = Record(app)
	local s = rec and rec.run
	if type(s) ~= "table" or s.who ~= Me() then return false end
	rec.run = nil
	rec.last = { who = s.who, why = why }
	Unsubscribe(app)
	if not quiet and STOP_WORDS[why] then ns.Say(W[STOP_WORDS[why]]:format(ns.Escape(Title(app)))) end
	Kit:Emit("kit.app", { app = app.id, on = false, why = why })
	if app.temp and why ~= "replaced" then Drop(app) end
	return true
end

local function Present(s, now)
	if not s then return false end
	if s.lease then return now - math.max(tonumber(s.seen) or 0, tonumber(s.started) or 0) <= s.lease end
	return s.seen ~= nil and now - s.seen <= LEASE
end

-- the ids now (a stop may take a temporary app out of order)
local function Ids()
	local ids = {}
	for i, id in ipairs(order) do ids[i] = id end
	return ids
end

local function Tick()
	local now, any = time(), false
	for _, id in ipairs(Ids()) do
		local app = apps[id]
		local s = app and Owned(app)
		if s then
			if (tonumber(s.ends) or 0) <= now then
				Stop(app, "expired")
			elseif s.lease and now - math.max(tonumber(s.seen) or 0, tonumber(s.started) or 0) > s.lease then
				Stop(app, "left")
			else
				any = true
				if not app.subs then Subscribe(app) end
				if Paced(app) and ns.InQuiet(app:Get("quiet")) ~= (s.quiet == true) then Retune(app, s) end
				if Digesting(app) then ns.Safe(ns.Digest.Due, app.host, s) end
			end
		end
	end
	if not any and ticker then
		ticker:Cancel()
		ticker = nil
	end
end

local function Ticking()
	if not ticker then ticker = C_Timer.NewTicker(1, Tick) end
end

-- why the app cannot start now (for the player: its extension, a source missing or its extension off, its check), or nil
local function Blocked(app)
	local d = app.decl
	if d.extension then
		local ext = ns.extensions[d.extension]
		if not (ext and ext.active) then return W.EXT_OFF:format(ext and ns.T(ext.title) or d.extension) end
	end
	for _, entry in ipairs(d.hear) do
		local name = Split(entry)
		local src = name and ns.sources[name]
		if not src then return W.NEEDS_SOURCE:format(ns.Text(name or entry)) end
		if not src.ext.active then return W.NEEDS:format(ns.T(src.ext.title)) end
	end
	if d.check then
		local ok, why = pcall(d.check, app)
		if not ok then
			geterrorhandler()(why)
		elseif why ~= nil and why ~= false then
			return ns.Text(why)
		end
	end
end

-- the app started: a launch it waited for is over
local function Launched(app)
	if app.launching then
		app.launching = nil
		ns.Changed("app", app.id)
	end
end

-- starts the app's run; one running goes on with the new time and lease (kit.app on = true again, no stop), unless
-- replace (a new declaration): then it ends (why "replaced") and a new run starts
local function Start(app, minutes, lease, agent, replace)
	local why = Blocked(app)
	if why then Fail("app %s cannot start: %s", app.id, why) end
	local rec = Record(app)
	if not rec or not Me() then Fail("app %s cannot start before the player is in the world", app.id) end
	local now = time()
	local old = Owned(app)
	if old and (tonumber(old.ends) or 0) <= now then
		Stop(app, "expired")
	elseif old and not replace then
		old.ends, old.lease = now + math.floor(minutes * 60), lease or nil
		if agent then old.seen = now end
		Retune(app, old)
		Subscribe(app)
		Kit:Emit("kit.app", { app = app.id, on = true, ends = old.ends })
		Ticking()
		Launched(app)
		return old
	elseif old then
		Stop(app, "replaced", true)
	end
	local s = { who = Me(), started = now, ends = now + math.floor(minutes * 60), lease = lease or nil, heard = 0,
		wakes = 0, buffer = {}, options = { digest = {} }, seen = agent and now or nil }
	rec.run = s
	Retune(app, s)
	Subscribe(app)
	ns.Say(W.STARTED:format(ns.Escape(Title(app)), date("%H:%M", s.ends)))
	Kit:Emit("kit.app", { app = app.id, on = true, ends = s.ends })
	Ticking()
	Launched(app)
	return s
end

-- a run kept from before a reload (or a login) goes on: heard again, retuned, ticked
local function Resume(app)
	local s = Owned(app)
	if not s then return end
	if (tonumber(s.ends) or 0) > time() then
		Subscribe(app)
		Retune(app, s)
	end
	Ticking()
end

------------------------------------------------------------------------------------------------------------------------
-- what the agent and the window read

local function Said(app)
	local rec = Record(app)
	local said = rec and rec.said
	if type(said) ~= "table" or said.d ~= date("%Y-%m-%d", time()) then return 0 end
	return tonumber(said.n) or 0
end

local function Status(app)
	local d, s, now = app.decl, Run(app), time()
	local out = { app = app.id, title = Title(app), by = app.by, on = s ~= nil, hear = Copy(d.hear), said = Said(app),
		lease = (s and s.lease) or (not s and d.lease) or 0, controls = Copy(d.controls), say = d.say,
		next = Recent(app, math.huge, 1).next, start = StartLine(app), driver = d.driver, launch = app.launch == true,
		temp = app.temp == true }
	if out.next == math.huge then out.next = 0 end
	if s then
		out.ends, out.started, out.heard, out.wakes, out.lastWake, out.seen = s.ends, s.started, s.heard or 0,
			s.wakes or 0, s.lastWake, s.seen
		out.present = Present(s, now)
	else
		out.present = false
		out.blocked = Blocked(app)
		local rec = Record(app)
		local last = rec and rec.last
		if type(last) == "table" and last.who == Me() then out.why = last.why end
	end
	if d.extension then
		local ext = ns.extensions[d.extension]
		out.extension = (ext ~= nil and ext.active == true)
	end
	if d.pace then
		out.pace = s and s.pace or app:Get("activity")
		if s then out.quiet = s.quiet and true or false else out.quiet = ns.InQuiet(app:Get("quiet")) end
	end
	return out
end

local function Touch(app, opts)
	if type(opts) == "table" and opts.source == "agent" then
		local s = Run(app)
		if s then s.seen = time() end
	end
end

local function Need(id)
	CheckId(id)
	local app = apps[id]
	if not app then Fail("no app %s (kit.apps lists them)", id) end
	return app
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
	Host(app)
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
		Stop(app, "replaced", true)
		Unsubscribe(app)
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
		if old.temp then Stop(old, "replaced", true) end     -- (its record was in memory)
		Unsubscribe(old)                                     -- (heard again as this declaration says, below)
	end
	local app = New(id, n, "addon")
	local rec = Stored(id)
	if rec then rec.decl = nil end                       -- an agent's declaration of the same id gives way
	ns.Changed("app", id)
	if loggedIn then Resume(app) end
	return app
end

function App:Push(data)
	if data == nil then return false end
	return Deliver(self, "addon", { data = data })
end

function Kit:AppControl(id, cmd)
	local app = apps[id]
	cmd = ns.CONTROL_WORDS[cmd] or cmd
	if not app or not Set(app.decl.controls)[cmd] or not Run(app) then return false end
	Deliver(app, "control", { cmd = cmd }, true)
	if cmd == "stop" then Stop(app, "player") end
	return true
end

function Kit:AppSay(id, text)
	local app = apps[id]
	if not app or not app.decl.say or type(text) ~= "string" then return false end
	text = text:match("^%s*(.-)%s*$")
	if text == "" or not Run(app) then return false end
	return Deliver(app, "player", { text = ns.Cut(text, SAY_MAX) }, true)
end

------------------------------------------------------------------------------------------------------------------------
-- programs: 无限工坊 loads them (kit.app.declare launch = true); the player starts one from its card

local launches = 0                                      -- a number for each launch: its LAUNCH_WAIT s are its own

function ns.WorkshopOnline()
	return Kit:AgentOnline()
end

function ns.AppLaunch(id)
	local app = apps[id]
	if not app then return false, W.NO_APP:format(ns.Escape(id)) end
	if not app.launch then return false, W.PROGRAM end
	if Run(app) then return false, W.RUNNING end
	if app.launching then return false, W.LAUNCHING end
	if not ns.WorkshopOnline() then return false, W.OFFLINE end
	local why = Blocked(app)
	if why then return false, why end
	Kit:Emit("kit.app.launch", { app = id })
	launches = launches + 1
	local mine = launches
	app.launching = mine
	ns.Changed("app", id)
	C_Timer.After(LAUNCH_WAIT, function()
		if app.launching == mine then
			app.launching = nil
			ns.Changed("app", id)
		end
	end)
	return true
end

------------------------------------------------------------------------------------------------------------------------
-- ns, for the window

function ns.App(id) return apps[id] end

function ns.AppList()
	local out, now = {}, time()
	for _, id in ipairs(order) do
		local app = apps[id]
		local s = Run(app)
		out[#out + 1] = { id = id, title = Title(app), by = app.by, addon = app.addon, on = s ~= nil,
			ends = s and s.ends or nil, present = Present(s, now), prompt = app.decl.prompt, start = StartLine(app),
			extension = app.decl.extension, blocked = not s and Blocked(app) or nil, driver = app.decl.driver,
			launch = app.launch == true, temp = app.temp == true, launching = app.launching ~= nil }
	end
	return out
end

function ns.AppManifest()
	local out = {}
	for _, id in ipairs(order) do
		local app = apps[id]
		out[#out + 1] = { id = id, title = Title(app), by = app.by, addon = app.addon, topic = "app." .. id,
			hear = Copy(app.decl.hear), prompt = app.decl.prompt, start = StartLine(app), extension = app.decl.extension,
			driver = app.decl.driver, docs = DocsPath(app), launch = app.launch == true, temp = app.temp == true }
	end
	return out
end

function ns.AppStatus(id)
	local app = apps[id]
	if not app then return { app = id, on = false } end
	return Status(app)
end

function ns.AppStop(id, why)
	local app = apps[id]
	return app ~= nil and Stop(app, why or "player")
end

function ns.AppOptionList(id)
	local app = apps[id]
	if not app then return nil end
	return ns.OptionList(Bound(app))
end

local function Same(a, b)
	if type(a) ~= "table" or type(b) ~= "table" then return a == b end
	if #a ~= #b then return false end
	for i = 1, #a do
		if a[i] ~= b[i] then return false end
	end
	return true
end

function ns.SetAppOption(id, name, value)
	local app = apps[id]
	local duck = app and Bound(app)
	local o = duck and duck.options[name]
	if not o then return false end
	local rec = duck.db
	rec.options = type(rec.options) == "table" and rec.options or {}
	local before = duck:Get(name)
	if o.kind == "number" and not ns.Finite(tonumber(value)) then value = before end   -- not a number: as it was
	if o.kind == "text" then
		value = tostring(value == nil and "" or value)
	elseif o.kind == "boolean" then
		value = value and true or false
	end
	rec.options[name] = value
	if o.kind == "number" or o.kind == "choice" or o.kind == "list" then value = duck:Get(name) end   -- as its kind keeps it
	rec.options[name] = value
	if not Same(before, value) then
		if o.changed then ns.Safe(o.changed, app, Copy(value)) end
		local s = Run(app)
		if s and Paced(app) and (name == "activity" or name == "quiet") then Retune(app, s) end
		Kit:Emit("kit.option", { app = id, name = name, value = Copy(value) })
	end
	return true, Copy(value)
end

function ns.AppControls(id)
	local app = apps[id]
	local out = {}
	for _, cmd in ipairs(app and app.decl.controls or {}) do out[#out + 1] = { cmd = cmd, label = W.CONTROL[cmd] } end
	return out
end

function ns.ForgetApp(id)
	local app = apps[id]
	if not app or app.by ~= "agent" then return false end
	Stop(app, "player")                                  -- (a temporary one goes with its run)
	if not app.temp then
		local store = Store()
		if store then store[id] = nil end
	end
	Drop(app)
	return true
end

------------------------------------------------------------------------------------------------------------------------
-- the core's capabilities and events

local kit = Kit:Extension("kit")

local OPEN_ARGS = { app = "string", minutes = "number?", lease = "number?", title = "string?", hear = "table?",
	digest = "table|boolean?", pace = "table|boolean?", urgent = "table?", controls = "table?", say = "boolean?",
	me = "boolean?", options = "table?", prompt = "string?", driver = "string?", temp = "boolean?" }
local DECLARE_ARGS = { app = "string", minutes = "number?", lease = "number?", title = "string?", hear = "table?",
	digest = "table|boolean?", pace = "table|boolean?", urgent = "table?", controls = "table?", say = "boolean?",
	me = "boolean?", options = "table?", prompt = "string?", driver = "string?", launch = "boolean?" }

-- the hear entries the sources take, from the sources registered now
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

local function Open(_, a, opts)
	local agent = type(opts) == "table" and opts.source == "agent"
	CheckId(a.app)
	local app, ignored, replace = apps[a.app], nil, false
	local given = Given(a)
	if app and app.by == "addon" then
		if a.temp ~= nil then
			given[#given + 1] = "temp"
			table.sort(given)
		end
		ignored = #given > 0 and given or nil
	elseif #given > 0 then
		app, replace = Declare(a, a.temp == true)
	elseif not app then
		Fail("no app %s: the first kit.app.open of an app gives its declaration (title, hear, ...); kit.apps lists "
			.. "the apps there are", a.app)
	elseif a.temp ~= nil and a.temp ~= (app.temp == true) then
		ignored = { "temp" }                          -- (kept or temporary changes only with a declaration)
	end
	local minutes = MinutesOf(a.minutes, "minutes") or app.decl.minutes
	local lease = LeaseOf(a.lease, "lease")
	if lease == nil then lease = app.decl.lease end
	local why = Blocked(app)
	if why then                       -- not an error: an answer (an error shows the player a red notice each try)
		local out = Status(app)
		out.blocked, out.ignored = why, ignored
		if app.temp and not Run(app) then Drop(app) end     -- a temporary app is there only while it runs
		return out
	end
	local ok, err = pcall(Start, app, minutes, lease or nil, agent, replace)
	if not ok then
		if app.temp and not Run(app) then Drop(app) end
		error(err, 0)
	end
	local out = Status(app)
	out.ignored = ignored
	return out
end

-- kit.app.open, its doc made from the sources registered: declared again whenever a source is
local function DeclareOpen()
	kit:See("app.open", { title = "kit.app.open", args = OPEN_ARGS, run = Open,
		doc = "starts an app; one already running goes on with the new minutes and lease (a changed declaration ends "
			.. "that run instead, kit.app why \"replaced\", and starts a new one); answers its status as kit.app.status; "
			.. "when it cannot start now (its check, an extension off, a source missing) it does not start and the status "
			.. "says why: blocked (on false). The first time, give its declaration (it is remembered: later just {app}; at "
			.. "most 8 kept): app (id: lowercase letters, digits, _, at most 24 bytes), title (at most 48 bytes), hear (at "
			.. "most 16 entries <source>:<what>: " .. HearDoc() .. "), pace (true: the player's activity "
			.. "quiet|normal|lively and quiet hours set the rhythm; or {quiet, normal, lively} of {gather, every, idle, "
			.. "most, wake = [whys]}), digest ({gather, every, idle, most}: gathered into wakes; none: each item is a "
			.. "wake), urgent ([whys or kinds] that wake within gather seconds, without pace), controls (the player's "
			.. "commands: mute, unmute, less, more, test, pause, resume, stop), say (the player may talk to you: /wk <app> "
			.. "<words>), me (the items of a source that offers it, game, carry the player: name, nickname, level, class, "
			.. "zone ...), lease (seconds without a kit.app.* call before it stops, default 600, 0 none, at least 60), "
			.. "minutes (default 120, at most 720), options (at most 8 the player sets: name -> {kind "
			.. "boolean|text|number|choice|list, title, default, hint, choices [{value, label}], min, max, step, unit}), "
			.. "prompt (a skill's name), driver (prompt: an AI client runs it from that skill, the default with a "
			.. "prompt; program: a program on this computer drives it, see kit.app.declare). temp = true with a "
			.. "declaration: a temporary app, to listen for a while (as when debugging): not remembered, not one of the "
			.. "8, at most 4 at once, gone once it stops or the UI reloads. An app an addon declared takes only app, "
			.. "minutes and lease (the rest is listed in `ignored`). Its wakes are the event app.<app>: {app, reason "
			.. "(item, urgent, full, batch, idle), items (oldest first; each {id, time, source (the source's name, or "
			.. "addon, control, player), ...}), skipped, pace?, quiet?}; kit.app {app, on, why?} says when it stops" })
end
DeclareOpen()

kit:See("app.declare", { title = "kit.app.declare", args = DECLARE_ARGS,
	doc = "remembers an app's declaration without starting it (as kit.app.open's first call gives it: title, hear, "
		.. "pace, digest, urgent, controls, say, me, lease, minutes, options, prompt, driver; not temp), for a program "
		.. "that drives it: the program starts it with kit.app.open {app} when it runs. launch = true: 无限工坊 on this "
		.. "computer loads the program, so the player can start it from the app's card (the event kit.app.launch); "
		.. "launch is kept until the UI reloads: declare again after kit.ready. An app an addon declared keeps its "
		.. "declaration (the fields given are listed in `ignored`); launch still counts. A changed declaration of an "
		.. "app that runs goes on with what it now hears. Not a heartbeat. Answers its status as kit.app.status",
	run = function(_, a)
		CheckId(a.app)
		local app, ignored = apps[a.app], nil
		local given = Given(a, true)
		if app and app.by == "addon" then
			ignored = #given > 0 and given or nil
		elseif #given > 0 then
			local changed
			app, changed = Declare(a, false)
			if changed and Run(app) then                     -- heard as the new declaration says
				Unsubscribe(app)
				Resume(app)
			end
		elseif not app then
			Fail("no app %s: kit.app.declare gives its declaration (title, hear, ...)", a.app)
		end
		if a.launch ~= nil and (app.launch == true) ~= a.launch then
			app.launch = a.launch or nil
			if not app.launch then app.launching = nil end
			ns.Changed("app", a.app)
		end
		local out = Status(app)
		out.ignored = ignored
		return out
	end })

kit:See("app.status", { title = "kit.app.status", args = { app = "string" },
	doc = "an app's status, and your heartbeat (every kit.app.* call of yours but kit.app.declare marks the app heard "
		.. "from): {app, title, by (addon|agent), on, ends, started, heard (items this run), wakes, lastWake, seen (your "
		.. "last call), present (you called within its lease), lease (seconds, 0 none), why (while off: how its last run "
		.. "ended), pace? (the player's activity), quiet? (in quiet hours), said (today's chat.send of yours that ran into "
		.. "channels it hears), hear, controls, say, next (the newest item id: kit.app.recent's since), blocked? (why it "
		.. "cannot start, while off), start? (with a prompt: the start line the player hands an AI client, which reads the "
		.. "skill with wk_docs), driver? (prompt or program), launch (无限工坊 loads its program), temp (a temporary "
		.. "app)}. Call it at least every lease / 3 seconds while you listen",
	run = function(_, a, opts)
		local app = Need(a.app)
		Touch(app, opts)
		return Status(app)
	end })

kit:See("app.stop", { title = "kit.app.stop", args = { app = "string" },
	doc = "stops an app (kit.app {app, on = false, why = \"stopped\"}; a temporary app goes with it); answers its status",
	run = function(_, a)
		local app = Need(a.app)
		Stop(app, "stopped")
		return Status(app)
	end })

kit:See("app.recent", { title = "kit.app.recent", args = { app = "string", since = "number?", limit = "number?" },
	doc = ("an app's last items (it keeps %d, through stops and reloads, per character; a temporary app's go with it): "
		.. "{items (each id > since, the last `limit`, default 50, at most %d, oldest first), next (the newest id: pass it "
		.. "as since next time)}"):format(RING, RING),
	run = function(_, a, opts)
		local app = Need(a.app)
		Touch(app, opts)
		return Recent(app, a.since, a.limit)
	end })

kit:See("apps", { title = "kit.apps",
	doc = "the apps: [{id, title, by (addon: an addon declared it, kit.app.open takes only app, minutes, lease; agent: "
		.. "declared by kit.app.open or kit.app.declare), addon?, on, ends, present, prompt? (its skill), start? (the "
		.. "start line: one sentence that tells an AI client to read the skill with wk_docs), extension? (the extension "
		.. "it belongs to), blocked? (why it cannot start, while off), driver? (prompt or program), launch (无限工坊 "
		.. "loads its program), temp (a temporary app), launching (the player asked to start its program a moment "
		.. "ago)}]. Not a heartbeat: it does not keep an app alive",
	run = function() return ns.AppList() end })

kit:Event("app", { doc = "an app started or stopped: {app, on, ends (a start), why (a stop: stopped by kit.app.stop, "
	.. "player, expired, left (its lease), extension, replaced)}", data = { app = "string", on = "boolean",
	ends = "number?", why = "string?" } })
kit:Event("app.launch", { doc = "the player wants a program's app started (its card's Start, /wk <app> start): {app}. "
	.. "Only for an app declared with kit.app.declare launch = true, while it does not run and 无限工坊 is linked: "
	.. "无限工坊 starts the program it loads for that app", data = { app = "string" } })

------------------------------------------------------------------------------------------------------------------------
-- what else stops an app, counts for it, or starts it again

-- its extension going off stops it
Kit:On("kit.extension", function(_, e)
	if type(e) ~= "table" or e.on ~= false then return end
	for _, id in ipairs(Ids()) do
		local app = apps[id]
		local hears = false                              -- one of its sources is that extension's: it would hear nothing
		for _, entry in ipairs(app and app.decl.hear or {}) do
			local name = Split(entry)
			local src = name and ns.sources[name]
			if src and src.ext.id == e.id then hears = true end
		end
		if app and (app.decl.extension == e.id or hears) then Stop(app, "extension") end
	end
end)

-- a source registered (another addon's, once its files have run): kit.app.open's doc tells of it, and an app running
-- that hears it is heard again
ns.OnChange(function(what, source)
	if what ~= "source" then return end
	DeclareOpen()
	for _, id in ipairs(Ids()) do
		local app = apps[id]
		if type(source) == "table" and HearsFrom(app, source.name) and Run(app) then
			Unsubscribe(app)
			Subscribe(app)
		end
	end
end)

-- said: today's chat.send steps of the agent's that ran, into channels an app hears
local counted = {}
Kit:On("kit.proposal", function(_, p)
	if type(p) ~= "table" or p.state ~= "done" or p.source ~= "agent" or counted[p.id] then return end
	counted[p.id] = true
	local day = date("%Y-%m-%d", time())
	for _, id in ipairs(order) do
		local app = apps[id]
		local channels = {}
		for _, entry in ipairs(app.decl.hear) do
			local c = entry:match("^chat:(.+)$")
			if c then channels[c] = true end
		end
		local n = 0
		for _, step in ipairs(next(channels) and type(p.steps) == "table" and p.steps or {}) do
			local channel = type(step) == "table" and step.cap == "chat.send" and type(step.args) == "table" and
				step.args.channel
			if channel and (channels[channel] or channels["*"]) then n = n + 1 end
		end
		local rec = n > 0 and Record(app)
		if rec then
			if type(rec.said) ~= "table" or rec.said.d ~= day then rec.said = { d = day, n = 0 } end
			rec.said.n = (tonumber(rec.said.n) or 0) + n
		end
	end
end)

-- the agent's declarations come back from storage (an entry of a source not registered yet stays); ids never go back
ns.When("load", function()
	local store = Store()
	local agents = {}
	for id, rec in pairs(store) do
		if type(rec) ~= "table" then
			store[id] = nil
		else
			if type(rec.recent) == "table" then ns.BumpId(rec.recent.n) end
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

ns.When("login", function()
	loggedIn = true
	for _, id in ipairs(order) do Resume(apps[id]) end
end)
