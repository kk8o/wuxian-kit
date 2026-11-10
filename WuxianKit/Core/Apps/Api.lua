-- Apps, what the agent and the window read and call (see Decl.lua for the apps, the contract, and for how the four
-- files share names): the start line, the status, the ns functions the window uses (ns.App, ns.AppList,
-- ns.AppManifest, ns.AppStatus, ns.AppStop, ns.AppOptionList, ns.SetAppOption, ns.AppControls), the core's
-- capabilities kit.app.open / declare / status / state / stop / recent and kit.apps, the event kit.app, and the count
-- of what the agent said today.
-- Here by choice: StartLine and DocsPath (only the lists and the status use them); ns.AppOptionList and
-- ns.SetAppOption (the window's, over Decl.lua's Bound); the said count (kit.proposal), beside the status that reads
-- it. ns.ForgetApp is in Decl.lua; the arguments OPEN_ARGS and DECLARE_ARGS too.
local addonName, ns = ...
local Kit = ns.Kit
local A = ns.apps
local W, OPEN_ARGS, DECLARE_ARGS, Copy, Me, Fail = A.W, A.OPEN_ARGS, A.DECLARE_ARGS, A.Copy, A.Me, A.Fail
local CheckId, LeaseOf, MinutesOf, Given, Declare = A.CheckId, A.LeaseOf, A.MinutesOf, A.Given, A.Declare
local apps, order, Record, Run, Title, Paced, Bound = A.apps, A.order, A.Record, A.Run, A.Title, A.Paced, A.Bound
local RING, State, Recent = A.RING, A.State, A.Recent
local Retune, Unsubscribe, Drop, Stop, Present, Blocked, Start, Resume = A.Retune, A.Unsubscribe, A.Drop, A.Stop,
	A.Present, A.Blocked, A.Start, A.Resume

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

------------------------------------------------------------------------------------------------------------------------
-- what the agent and the window read

local function Said(app)
	local c = A.Char(app)
	local said = c and c.said
	if type(said) ~= "table" or said.d ~= date("%Y-%m-%d", time()) then return 0 end
	return tonumber(said.n) or 0
end

local function Status(app)
	local d, s, now = app.decl, Run(app), time()
	local out = { app = app.id, title = Title(app), by = app.by, on = s ~= nil, hear = Copy(d.hear), see = Copy(d.see),
		said = Said(app),
		lease = (s and s.lease) or (not s and d.lease) or 0, controls = Copy(d.controls), say = d.say,
		next = Recent(app, math.huge, 1).next, start = StartLine(app), temp = app.temp == true }
	if out.next == math.huge then out.next = 0 end
	if s then
		out.ends, out.started, out.heard, out.wakes, out.lastWake, out.seen = s.ends, s.started, s.heard or 0,
			s.wakes or 0, s.lastWake, s.seen
		out.present = Present(s, now)
	else
		out.present = false
		out.blocked = Blocked(app)
		local c = A.Char(app)
		local last = c and c.last
		if type(last) == "table" then out.why = last.why end
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
-- ns, for the window

function ns.App(id) return apps[id] end

function ns.AppList()
	local out, now = {}, time()
	for _, id in ipairs(order) do
		local app = apps[id]
		local s = Run(app)
		out[#out + 1] = { id = id, title = Title(app), by = app.by, addon = app.addon, on = s ~= nil,
			ends = s and s.ends or nil, present = Present(s, now), prompt = app.decl.prompt, start = StartLine(app),
			extension = app.decl.extension, blocked = not s and Blocked(app) or nil, temp = app.temp == true,
			see = #app.decl.see > 0 and Copy(app.decl.see) or nil, hidden = app.decl.hidden,
			["local"] = Copy(app.decl["local"]) }
	end
	return out
end

function ns.AppManifest()
	local out = {}
	for _, id in ipairs(order) do
		local app = apps[id]
		out[#out + 1] = { id = id, title = Title(app), by = app.by, addon = app.addon, topic = "app." .. id,
			hear = Copy(app.decl.hear), see = Copy(app.decl.see), prompt = app.decl.prompt, start = StartLine(app),
			extension = app.decl.extension, docs = DocsPath(app), temp = app.temp == true }
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
	for _, cmd in ipairs(app and app.decl.controls or {}) do
		out[#out + 1] = { cmd = cmd, label = W.CONTROL[cmd] or app.decl.labels and app.decl.labels[cmd] }
	end
	return out
end

------------------------------------------------------------------------------------------------------------------------
-- the core's capabilities and events

local kit = Kit:Extension("kit")

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

-- the facets apps see, from those registered now
local function SeeDoc()
	local parts = {}
	for _, name in ipairs(ns.facetOrder) do
		local f = ns.facets[name]
		parts[#parts + 1] = name .. ": " .. ns.Text(ns.T(f.spec.doc) or ns.T(f.spec.title) or name)
	end
	return #parts > 0 and table.concat(parts, "; ") or "none registered"
end

local function Open(_, a, opts)
	local agent = type(opts) == "table" and opts.source == "agent"
	CheckId(a.app)
	local app, ignored = apps[a.app], nil
	local given = Given(a)
	if app and app.by == "addon" then
		if a.temp ~= nil then
			given[#given + 1] = "temp"
			table.sort(given)
		end
		ignored = #given > 0 and given or nil
	elseif #given > 0 then
		local changed
		app, changed = Declare(a, a.temp == true)
		if changed and Run(app) then                        -- it goes on, heard as the new declaration says
			Unsubscribe(app)
		end
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
	local ok, err = pcall(Start, app, minutes, lease or nil, agent)
	if not ok then
		if app.temp and not Run(app) then Drop(app) end
		error(err, 0)
	end
	local out = Status(app)
	out.ignored = ignored
	return out
end

-- kit.app.open, its doc made from the sources and facets registered: declared again whenever one is
local function DeclareOpen()
	kit:See("app.open", { title = "kit.app.open", args = OPEN_ARGS, run = Open,
		doc = "starts an app; one already running goes on with the new minutes and lease, and with what a changed "
			.. "declaration says (a kept app declared temporary, or the other way, starts a new run: kit.app why "
			.. "\"replaced\"); answers its status as kit.app.status; "
			.. "when it cannot start now (its check, an extension off, a source missing) it does not start and the status "
			.. "says why: blocked (on false). The first time, give its declaration (it is remembered: later just {app}; at "
			.. "most 8 kept): app (id: lowercase letters, digits, _, at most 24 bytes), title (at most 48 bytes), hear (at "
			.. "most 16 entries <source>:<what>: " .. HearDoc() .. "), pace (true: the player's activity "
			.. "quiet|normal|lively and quiet hours set the rhythm; or {quiet, normal, lively} of {gather, every, idle, "
			.. "most, wake = [whys]}), digest ({gather, every, idle, most}: gathered into wakes; none: each item is a "
			.. "wake), urgent ([whys or kinds] that wake within gather seconds, without pace), controls (the player's "
			.. "commands, buttons on its card and /wk <app> <word>: mute, unmute, less, more, test, pause, resume, stop; "
			.. "or one of the app's own, {cmd, label} (label one word, at most 24 bytes): at most 12, each told as a "
			.. "control item {cmd}), say (the player may talk to you: /wk <app> "
			.. "<words>), see (at most 8 states each wake carries as state {name = the state at that wake}; kit.app.state "
			.. "reads them at once: " .. SeeDoc() .. "), lease (seconds without a kit.app.* call before it stops, "
			.. "default 600, 0 none, at least 60), "
			.. "minutes (default 120, at most 720), hidden (true: plumbing of a program, such as 无限工坊's reactions: "
			.. "not in the /wk window's list and no chat line when it starts or stops; kit.apps still lists it), local "
			.. "({id, title}: the local extension of 无限工坊 the app comes with; its card has no remove button: it goes "
			.. "with the extension), options (at most 8 the player sets: name -> {kind "
			.. "boolean|text|number|choice|list, title, default, hint, choices [{value, label}], min, max, step, unit}), "
			.. "prompt (the name of the skill an AI client follows to drive it). temp = true with a "
			.. "declaration: a temporary app, to listen for a while (as when debugging): not remembered, not one of the "
			.. "8, at most 4 at once, gone once it stops or the UI reloads. An app an addon declared takes only app, "
			.. "minutes and lease (the rest is listed in `ignored`). Its wakes are the event app.<app>: {app, reason "
			.. "(item, urgent, full, batch, idle), items (oldest first; each {id, time, source (the source's name, or "
			.. "addon, control, player), ...}), skipped (the oldest items left out to keep a wake small; the state stays), "
			.. "state? (with see), pace?, quiet?}; kit.app {app, on, why?} says when it stops" })
end
A.DeclareOpen = DeclareOpen                             -- (Run.lua: again when a source or a facet is registered)
DeclareOpen()

kit:See("app.declare", { title = "kit.app.declare", args = DECLARE_ARGS,
	doc = "remembers an app's declaration without starting it (as kit.app.open's first call gives it: title, hear, "
		.. "pace, digest, urgent, controls, say, see, lease, minutes, options, prompt; not temp), so that its card "
		.. "shows (交给 AI with a prompt) before anyone opens it: 无限工坊 declares a local extension's apps so. An "
		.. "agent opens it later with kit.app.open {app}. An app an addon declared keeps its declaration (the fields "
		.. "given are listed in `ignored`). A changed declaration of an app that runs goes on with what it now hears. "
		.. "Not a heartbeat. Answers its status as kit.app.status",
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
		local out = Status(app)
		out.ignored = ignored
		return out
	end })

kit:See("app.status", { title = "kit.app.status", args = { app = "string" },
	doc = "an app's status, and your heartbeat (every kit.app.* call of yours but kit.app.declare marks the app heard "
		.. "from): {app, title, by (addon|agent), on, ends, started, heard (items this run), wakes, lastWake, seen (your "
		.. "last call), present (you called within its lease), lease (seconds, 0 none), why (while off: how its last run "
		.. "ended), pace? (the player's activity), quiet? (in quiet hours), said (today's chat.send of yours that ran into "
		.. "channels it hears), hear, see, controls, say, next (the newest item id: kit.app.recent's since), blocked? (why it "
		.. "cannot start, while off), start? (with a prompt: the start line the player hands an AI client, which reads the "
		.. "skill with wk_docs), temp (a temporary app)}. Call it at least every lease / 3 seconds while you listen",
	run = function(_, a, opts)
		local app = Need(a.app)
		Touch(app, opts)
		return Status(app)
	end })

kit:See("app.state", { title = "kit.app.state", args = { app = "string" },
	doc = "what an app sees now, read at once (as each of its wakes carries it): {app, at (the time read), state {name = "
		.. "the state} of the facets its see names (one missing or off: none)}. Also a heartbeat, as kit.app.status",
	run = function(_, a, opts)
		local app = Need(a.app)
		Touch(app, opts)
		return { app = app.id, at = time(), state = State(app) }
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
		.. "it belongs to), blocked? (why it cannot start, while off), see? (the states it sees), temp (a temporary "
		.. "app)}]. Not a heartbeat: it does not keep an app alive",
	run = function() return ns.AppList() end })

kit:Event("app", { doc = "an app started or stopped: {app, on, ends (a start), why (a stop: stopped by kit.app.stop, "
	.. "player, expired, left (its lease), extension, replaced)}", data = { app = "string", on = "boolean",
	ends = "number?", why = "string?" } })

------------------------------------------------------------------------------------------------------------------------
-- what counts for an app

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
		local c = n > 0 and A.Char(app)
		if c then
			if type(c.said) ~= "table" or c.said.d ~= day then c.said = { d = day, n = 0 } end
			c.said.n = (tonumber(c.said.n) or 0) + n
		end
	end
end)
