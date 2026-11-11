-- Apps, what the agent and the window read and call (see Decl.lua for the apps, the contract, and for how the four
-- files share names): the start line, the status, the ns functions the window uses (ns.App, ns.AppList,
-- ns.AppManifest, ns.AppStatus, ns.AppStop, ns.AppOptionList, ns.SetAppOption, ns.AppControls), the core's
-- capabilities (Keep: kit.app.declare / open / stop / forget; See: kit.app.describe / status / state / recent and
-- kit.apps), the event kit.app, and the count of what the agent said today.
-- Here by choice: StartLine and DocsPath (only the lists and the status use them); ns.AppOptionList and
-- ns.SetAppOption (the window's, over Decl.lua's Bound); the said count (kit.proposal), beside the status that reads
-- it. ns.ForgetApp is in Decl.lua, with the fields (FIELDS) the arguments, the docs, the status and the lists here are
-- made from.
local addonName, ns = ...
local Kit = ns.Kit
local A = ns.apps
local W, MOST, ID_MAX, FIELDS, DECLARE_ARGS, FieldDocs = A.W, A.MOST, A.ID_MAX, A.FIELDS, A.DECLARE_ARGS, A.FieldDocs
local Copy, Plain, Fail = A.Copy, A.Plain, A.Fail
local CheckId, LeaseOf, MinutesOf, Declare = A.CheckId, A.LeaseOf, A.MinutesOf, A.Declare
local apps, order, Run, Title, Paced, Bound = A.apps, A.order, A.Run, A.Title, A.Paced, A.Bound
local RING, State, Recent = A.RING, A.State, A.Recent
local Retune, Drop, Stop, Present, Blocked, Start, Reconcile = A.Retune, A.Drop, A.Stop, A.Present, A.Blocked,
	A.Start, A.Reconcile

-- the start line (启动语): one sentence for any AI client with 无限工坊's MCP tools, in the language in force, that
-- points it at the app's skill; nil for an app without a prompt
local function StartLine(app)
	local prompt = app.decl.prompt
	if type(prompt) ~= "string" or prompt == "" then return nil end
	return W.START:format(ns.Text(Title(app)), prompt)
end

-- an addon's app's docs as the manifest gives a folder: under Interface\AddOns ("MyGuildTools/Apps/Officers"), or nil
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

-- the fields of FIELDS marked `mark` (status, list), copied from the app's declaration into row
local function Marked(row, app, mark)
	for _, f in ipairs(FIELDS) do
		if f[mark] and row[f.name] == nil then row[f.name] = Plain(app.decl[f.name]) end
	end
	return row
end

local function Status(app)
	local d, s, now = app.decl, Run(app), time()
	local out = Marked({ app = app.id, title = Title(app), by = app.by, on = s ~= nil, said = Said(app),
		lease = (s and s.lease) or (not s and d.lease) or 0, next = Recent(app, math.huge, 1).next,
		start = StartLine(app), temp = app.temp == true }, app, "status")
	if out.next == math.huge then out.next = 0 end
	if s then
		out.ends, out.started, out.heard, out.wakes, out.lastWake, out.seen = s.ends, s.started, s.heard or 0,
			s.wakes or 0, s.lastWake, s.seen
		out.present = Present(s, now)
		out.waiting = app.waiting                           -- (on, and not heard yet: what it waits for)
		-- the wakes' cursor: the next of the last one that went (next runs ahead of it while items are gathered)
		out.sent = ns.Finite(s.sent) and s.sent or out.next
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

-- a hidden app (a temporary one's plumbing) is listed only while it runs
function ns.AppList()
	local out, now = {}, time()
	for _, id in ipairs(order) do
		local app = apps[id]
		local s = Run(app)
		if s or not app.decl.hidden then
			out[#out + 1] = Marked({ id = id, title = Title(app), by = app.by, addon = app.addon, on = s ~= nil,
				ends = s and s.ends or nil, present = Present(s, now), start = StartLine(app),
				blocked = not s and Blocked(app) or nil, waiting = s and app.waiting or nil, temp = app.temp == true,
				see = #app.decl.see > 0 and Copy(app.decl.see) or nil }, app, "list")
		end
	end
	return out
end

function ns.AppManifest()
	local out = {}
	for _, id in ipairs(order) do
		local app = apps[id]
		out[#out + 1] = Marked({ id = id, title = Title(app), by = app.by, addon = app.addon, topic = "app." .. id,
			hear = Copy(app.decl.hear), see = Copy(app.decl.see), start = StartLine(app), docs = DocsPath(app),
			temp = app.temp == true }, app, "list")
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
	if o.kind == "number" or o.kind == "choice" or o.kind == "list" then
		value = duck:Get(name)                               -- read back as its kind keeps it, and kept so
		rec.options[name] = value
	end
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

local ID_DOC = ("lowercase letters, digits, _, at most %d bytes, not a word of /wk's own"):format(ID_MAX)

-- kit.app.open: an app that is declared starts, or goes on; temp declares a temporary one for this run. One that
-- cannot start now is an answer (on false, blocked), not an error: an error shows the player a red notice each try
local function Open(_, a, opts)
	local agent = type(opts) == "table" and opts.source == "agent"
	CheckId(a.app)
	local minutes, lease = MinutesOf(a.minutes, "minutes"), LeaseOf(a.lease, "lease")
	local app = apps[a.app]
	if app then
		Reconcile(app)            -- (a run whose time is over ends here: a temporary app goes with it, and is new below)
		app = apps[a.app]
	end
	if a.temp ~= nil then
		app = Declare(a.app, a.temp, true)
	elseif not app then
		Fail("no app %s: kit.app.declare declares one that is kept, kit.app.open's temp (its whole declaration) a "
			.. "temporary one; kit.apps lists the apps there are", a.app)
	end
	minutes = minutes or app.decl.minutes
	if lease == nil then lease = app.decl.lease end
	if not Run(app) then
		if Blocked(app) then
			local out = Status(app)
			if app.temp then Drop(app) end                   -- a temporary app is there only while it runs
			return out
		end
	end
	local ok, err = pcall(Start, app, minutes, lease or nil, agent)
	if not ok then
		if app.temp and not Run(app) then Drop(app) end
		error(err, 0)
	end
	return Status(app)
end

kit:Keep("app.open", { title = "kit.app.open", args = { app = "string", minutes = "number?", lease = "number?",
	temp = "table?" }, run = Open,
	doc = ("starts an app that is declared (kit.app.declare, or an addon's: kit.apps lists them); one already running "
		.. "goes on with the new minutes and lease (default: its declaration's). temp: a table, the whole declaration "
		.. "of a temporary app (kit.app.declare's fields, and hidden; given again it replaces the one before): to "
		.. "listen for a while, as when debugging, or a program's plumbing; not remembered, not one of the %d kept, at "
		.. "most %d at once, gone once it stops or the UI reloads (temp for a kept app of yours makes it temporary: "
		.. "kit.app why \"replaced\"). Answers its status as kit.app.status; when it cannot start now (its check, an "
		.. "extension off, a source missing) it does not start and the status says why: blocked (on false). Its wakes "
		.. "are the event app.<app>: {app, seq (from 1 each run), reason (item, urgent, full, batch, idle), items "
		.. "(oldest first; each {id, time, source (the source's name, or addon, control, player), ref? (the id the "
		.. "source gave), ...}), after, next (item ids, the one cursor: the wake covers the run's items with after < id "
		.. "<= next; after is the next of the wake before, or where the run began), skipped (how many of those, the "
		.. "oldest, are not in items: too many were waiting; kit.app.recent has them), state? (with see), pace?, "
		.. "quiet?}; a wake that does not get through is sent again. kit.app {app, on, why?} says when it "
		.. "stops"):format(MOST.agent, MOST.temp) })

-- kit.app.declare, its doc made from the fields and from the sources and facets registered: declared again whenever
-- one is (Run.lua)
local function Redeclare()
	kit:Keep("app.declare", { title = "kit.app.declare", args = DECLARE_ARGS,
		doc = ("declares an app that is kept, or declares it again: the whole declaration (a field not given is its "
			.. "default, not what it was), remembered through reloads, at most %d (kit.app.forget withdraws one). Not "
			.. "started (kit.app.open {app} starts it: its card shows before anyone does, 交给 AI with a prompt) and not "
			.. "a heartbeat; one that runs goes on as the declaration now says (or stops, why \"extension\", when it "
			.. "cannot). An app an addon declared is the addon's: an error. Answers its status as kit.app.status, and "
			.. "changed (false: the declaration is the one it had; kit.app.describe's decl given back is). The fields: "
			.. "app (id: %s), %s"):format(MOST.agent, ID_DOC, FieldDocs()),
		run = function(_, a)
			local d = {}
			for k, v in pairs(a) do
				if k ~= "app" then d[k] = v end
			end
			local app, changed = Declare(a.app, d, false)
			local out = Status(app)
			out.changed = changed
			return out
		end })
end
A.Redeclare = Redeclare
Redeclare()

kit:Keep("app.stop", { title = "kit.app.stop", args = { app = "string" },
	doc = "stops an app (kit.app {app, on = false, why = \"stopped\"}; a temporary app goes with it); answers its status",
	run = function(_, a)
		local app = Need(a.app)
		Stop(app, "stopped")
		return Status(app)
	end })

kit:Keep("app.forget", { title = "kit.app.forget", args = { app = "string" },
	doc = "withdraws an app an agent declared (无限工坊 does when the local extension it came with goes): stopped if it "
		.. "runs (kit.app why \"forgotten\"), its declaration and its card gone; what the player set for it stays, and "
		.. "is there again when it is declared again. An addon's app is the addon's: an error. Answers {app, forgotten}",
	run = function(_, a)
		local app = Need(a.app)
		if app.by ~= "agent" then
			Fail("app %s is an addon's (%s): only an app an agent declared is forgotten", app.id, ns.Text(app.addon or "?"))
		end
		ns.ForgetApp(app.id, false)
		return { app = app.id, forgotten = true }
	end })

kit:See("app.describe", { title = "kit.app.describe", args = { app = "string" },
	doc = "an app's declaration as it is kept: {app, by (addon|agent), temp, decl (every field of kit.app.declare with "
		.. "its value, defaults filled in, lease 0 for none; texts an addon gives read in the language in force)}. "
		.. "decl given back to kit.app.declare changes nothing (changed false): compare before you declare. Not a "
		.. "heartbeat",
	run = function(_, a)
		local app = Need(a.app)
		return { app = app.id, by = app.by, temp = app.temp == true, decl = Plain(app.data) }
	end })

kit:See("app.status", { title = "kit.app.status", args = { app = "string" },
	doc = "an app's status, and your heartbeat (kit.app.open, status, state and recent of yours mark the app heard "
		.. "from): {app, title, by (addon|agent), on, ends, started, heard (items this run), wakes, lastWake, seen (your "
		.. "last call), present (you called within its lease), lease (seconds, 0 none), waiting? (while on: what it "
		.. "needs that is not registered yet, such as another addon's source after a reload; nothing is heard until it "
		.. "is, and it stops, why \"extension\", if that takes more than half a minute), why (while off: how its last "
		.. "run ended), pace? (the player's activity), quiet? (in quiet hours), said (today's chat.send of yours that ran "
		.. "into channels it hears), hear, see, controls, say, hidden?, local?, next (the newest item id: "
		.. "kit.app.recent's since), sent? (while on: the next of the last wake sent, or where the run began; items "
		.. "newer than it are gathered and come with a wake, so one who joins a run starts from sent and reads "
		.. "kit.app.recent only up to it), blocked? (why it cannot start, while off), start? (with a prompt: the "
		.. "start line the player hands an AI client, which reads the skill with wk_docs), temp (a temporary app)}. "
		.. "Call it at least every lease / 3 seconds while you listen",
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
	doc = "the apps: [{id, title, by (addon: an addon declared it; agent: declared by kit.app.declare or kit.app.open's "
		.. "temp), addon?, on, ends, present, prompt? (its skill), start? (the start line: one sentence that tells an AI "
		.. "client to read the skill with wk_docs), extension? (the extension it belongs to), blocked? (why it cannot "
		.. "start, while off), waiting? (while on: what it needs that is not registered yet), see? (the states it sees), "
		.. "temp (a temporary app), hidden? (a temporary app's plumbing: listed while it runs), local? ({id, title}: the "
		.. "local extension of 无限工坊 it comes with)}]. Not a heartbeat: it does not keep an app alive",
	run = function() return ns.AppList() end })

kit:Event("app", { doc = "an app started, stopped, or what it waits for changed: {app, on, ends (while on), waiting "
	.. "(on, and something it needs is not registered yet: nothing is heard until it is; without: it hears), why (a "
	.. "stop: stopped by kit.app.stop, player, expired, left (its lease), extension (one it needs is off or missing, or "
	.. "its check says no), forgotten (kit.app.forget), replaced)}", data = { app = "string", on = "boolean",
	ends = "number?", why = "string?", waiting = "string?" } })

------------------------------------------------------------------------------------------------------------------------
-- what counts for an app

-- said: today's chat.send steps of the agent's that ran, into channels an app hears. A proposal counts once: those
-- counted are remembered for the day they ran
local counted, countedDay = {}, nil
Kit:On("kit.proposal", function(_, p)
	if type(p) ~= "table" or p.state ~= "done" or p.source ~= "agent" then return end
	local day = date("%Y-%m-%d", time())
	if day ~= countedDay then counted, countedDay = {}, day end
	if counted[p.id] then return end
	counted[p.id] = true
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
