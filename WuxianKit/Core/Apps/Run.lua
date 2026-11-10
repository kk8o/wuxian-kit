-- Apps, runs (see Decl.lua for the apps and for how the four files share names): quiet hours and the pace (Retune),
-- what a run hears and sees (its sources subscribed, its facets watched), the one rule of the lease (Silence), and
-- Reconcile: the one place that decides whether an app runs, waits or stops. Whatever may change that (a declaration,
-- an extension switched, a source or a facet registered, login, kit.app.open, each second of the ticker) only calls
-- it. Start, Stop and Drop make and end runs; WuxianKit:AppControl and WuxianKit:AppSay are the player's commands and
-- words.
-- Here by choice: Present, beside the lease's rule (only Api.lua calls it); ns.QuietWindow and ns.InQuiet, with
-- Retune. The count of what was said today (kit.proposal) is in Api.lua, beside the status that reads it.
local addonName, ns = ...
local Kit = ns.Kit
local A = ns.apps
local W, LEASE, Fail, Set, Me, Split, Trim = A.W, A.LEASE, A.Fail, A.Set, A.Me, A.Split, A.Trim
local apps, order, Record, Owned, Run, Title, Paced, Digesting = A.apps, A.order, A.Record, A.Owned, A.Run, A.Title,
	A.Paced, A.Digesting
local Deliver = A.Deliver

local SAY_MAX = 255
local GRACE = 30                -- seconds a run waits for what it needs (after a login or a reload) before it stops

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
-- pace

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

------------------------------------------------------------------------------------------------------------------------
-- what a run hears and sees

-- the facets it sees counted as looked at (ns.FacetWatch: the first look turns one on); one registered again: that one
local function Watch(app)
	app.watching = app.watching or {}
	for _, name in ipairs(app.decl.see) do
		local facet = ns.facets[name]
		if facet and app.watching[name] ~= facet then
			if app.watching[name] then ns.FacetWatch(app.watching[name], app, false) end
			app.watching[name] = facet
			ns.FacetWatch(facet, app, true)
		end
	end
end

local function Unwatch(app)
	for _, facet in pairs(app.watching or {}) do ns.FacetWatch(facet, app, false) end
	app.watching = nil
end

-- each entry subscribed at its source and the facets it sees watched (Reconcile: only once all of them are there);
-- what a source gives while its extension is off is not heard
local function Subscribe(app)
	if app.subs then return end
	app.subs = { decl = app.decl }
	for _, entry in ipairs(Trim(app.decl.hear)) do            -- (again: a source's covers is there only once it is)
		local name, what = Split(entry)
		local src = name and ns.sources[name]
		if src then
			local ok, t = pcall(src.spec.on, src.ext, what, function(item)
				if src.ext.active then Deliver(app, name, item, false) end
			end)
			if ok then app.subs[#app.subs + 1] = { name = name, src = src, token = t } else geterrorhandler()(t) end
		end
	end
	Watch(app)
end

local function Unsubscribe(app)
	for _, sub in ipairs(app.subs or {}) do pcall(sub.src.spec.off, sub.src.ext, sub.token) end
	app.subs = nil
	Unwatch(app)
end

-- whether what it is subscribed to is no longer what it should hear: its declaration changed, or a source it hears was
-- registered again
local function Stale(app)
	if app.subs.decl ~= app.decl then return true end
	for _, sub in ipairs(app.subs) do
		if ns.sources[sub.name] ~= sub.src then return true end
	end
	return false
end

------------------------------------------------------------------------------------------------------------------------
-- the lease, one rule: how long the agent has not been heard from (its last kit.app.* call, or the start), against the
-- run's lease. A run with a lease stops once that is over (Lapsed); the agent is present while it has called and is
-- within the lease (a run with none: within the default)

local function Silence(s, now)
	return now - math.max(tonumber(s.seen) or 0, tonumber(s.started) or 0)
end

local function Lapsed(s, now)
	return s.lease ~= nil and Silence(s, now) > s.lease
end

local function Present(s, now)
	return s ~= nil and s.seen ~= nil and Silence(s, now) <= (s.lease or LEASE)
end

------------------------------------------------------------------------------------------------------------------------
-- runs: stop, what a run needs, Reconcile, the ticker, start

local ticker
local Tick

local function Ticking()
	if not ticker then ticker = C_Timer.NewTicker(1, Tick) end
end

-- the app goes (a temporary one once it stops, one forgotten or removed)
local function Drop(app)
	Unsubscribe(app)
	app.waiting, app.waitFrom = nil, nil
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

local STOP_WORDS = { stopped = "STOPPED", player = "STOPPED", forgotten = "STOPPED", extension = "STOPPED",
	expired = "EXPIRED", left = "LEFT" }

-- stops this character's run (why: stopped, player, expired, left, extension, forgotten, replaced); quiet: no chat
-- line; detail: what it needed, for the player (why extension). A temporary app goes with its run (unless it is
-- replaced: a new run of it follows)
local function Stop(app, why, quiet, detail)
	local c = A.Char(app)
	local s = c and c.run
	if type(s) ~= "table" then return false end
	c.run = nil
	c.last = { why = why }
	Unsubscribe(app)
	app.waiting, app.waitFrom = nil, nil
	if not quiet and not app.decl.hidden and STOP_WORDS[why] then
		local title = ns.Escape(Title(app))
		if detail then
			ns.Say(W.STOPPED_WHY:format(title, ns.Escape(detail)))
		else
			ns.Say(W[STOP_WORDS[why]]:format(title))
		end
	end
	Kit:Emit("kit.app", { app = app.id, on = false, why = why })
	if app.temp and why ~= "replaced" then Drop(app) end
	return true
end

-- the extensions that were on this session: one registered and not on that never was is on its way (another addon's is
-- turned on a frame after it registers), one that was, or that the player keeps off, is off
local wasOn = {}

-- an extension an app needs: nil when it is on, "wait" when it is not there yet, "stop" when it is off
local function Lacks(ext)
	if not ext then return "wait" end
	if ext.active then return nil end
	if wasOn[ext.id] or not ns.IsOn(ext.id) then return "stop" end
	return "wait"
end

-- what keeps the app from running now: "wait" (something it needs is not registered yet) or "stop" (an extension it
-- needs is off, or its check says no), why (for the player), and whether its check said so; nil when nothing does.
-- A source or a facet whose extension is on its way reads as the one still missing: one reason while it waits.
-- light: without asking its check
local function Verdict(app, light)
	local d = app.decl
	if d.extension then
		local ext = ns.extensions[d.extension]
		local lacks = Lacks(ext)
		if lacks then
			if lacks == "wait" then return lacks, W.EXT_MISSING:format(d.extension) end
			return lacks, W.EXT_OFF:format(ns.T(ext.title))
		end
	end
	for _, entry in ipairs(d.hear) do
		local name = Split(entry)
		local src = name and ns.sources[name]
		local lacks = not src and "wait" or Lacks(src.ext)
		if lacks == "wait" then return lacks, W.NEEDS_SOURCE:format(ns.Text(name or entry)) end
		if lacks then return lacks, W.NEEDS:format(ns.T(src.ext.title)) end
	end
	for _, name in ipairs(d.see) do
		local facet = ns.facets[name]
		local lacks = not facet and "wait" or Lacks(facet.ext)
		if lacks == "wait" then return lacks, W.NEEDS_FACET:format(ns.Text(name)) end
		if lacks then return lacks, W.NEEDS:format(ns.T(facet.ext.title)) end
	end
	if d.check and not light then
		local ok, why = pcall(d.check, app)
		if not ok then
			geterrorhandler()(why)
		elseif why ~= nil and why ~= false then
			return "stop", ns.Text(why), true
		end
	end
end

-- why the app cannot start now (for the player), or nil
local function Blocked(app)
	local _, why = Verdict(app)
	return why
end

local loginAt = 0

-- the one entry: what the app's run of this character's should be now, and made so.
--   run   everything it needs is there: subscribed as its declaration says now, its facets watched
--   wait  something it needs is not registered yet (after a login or a reload: another addon's has not loaded): the run
--         is kept, nothing subscribed, app.waiting says why (kit.app.status's waiting; on stays true); it runs once that
--         is registered, and stops, why "extension", when it still is not GRACE seconds on
--   stop  its time is over ("expired"), its agent left ("left"), or an extension it needs is off or its check says no
--         ("extension")
-- light (the ticker, and Start right after kit.app.open asked): the addon's check is not asked again, but for a run
-- that waits. A check that says no within GRACE seconds of the login waits (what it reads may not be loaded yet).
-- Nothing before the login: a run is this character's
local function Reconcile(app, light)
	if not A.loggedIn or apps[app.id] ~= app then return end
	local s, now = Owned(app), time()
	if not s then
		Unsubscribe(app)
		app.waiting, app.waitFrom = nil, nil
		return
	end
	if (tonumber(s.ends) or 0) <= now then
		Stop(app, "expired")
		return
	end
	if Lapsed(s, now) then
		Stop(app, "left")
		return
	end
	local verdict, why, check = Verdict(app, light and not app.waiting)
	if verdict == "stop" and check and now - loginAt < GRACE then verdict = "wait" end
	if verdict == "wait" then
		app.waitFrom = app.waitFrom or now
		if now - app.waitFrom >= GRACE then verdict = "stop" end
	end
	if verdict == "stop" then
		Stop(app, "extension", nil, why)
		return
	end
	if verdict == "wait" then
		Unsubscribe(app)
		if app.waiting ~= why then
			app.waiting = why
			Kit:Emit("kit.app", { app = app.id, on = true, ends = s.ends, waiting = why })
		end
		Ticking()
		return
	end
	local waited = app.waiting ~= nil
	app.waiting, app.waitFrom = nil, nil
	if app.subs and Stale(app) then Unsubscribe(app) end
	if not app.subs then
		Subscribe(app)
		Retune(app, s)
	end
	Watch(app)
	if waited then Kit:Emit("kit.app", { app = app.id, on = true, ends = s.ends }) end
	Ticking()
end

-- the ids now (a stop may take a temporary app out of order)
local function Ids()
	local ids = {}
	for i, id in ipairs(order) do ids[i] = id end
	return ids
end

local function All()
	for _, id in ipairs(Ids()) do
		local app = apps[id]
		if app then Reconcile(app) end
	end
end

function Tick()
	local any = false
	for _, id in ipairs(Ids()) do
		local app = apps[id]
		if app and Owned(app) then
			Reconcile(app, true)
			local s = apps[id] == app and Owned(app)
			if s then
				any = true
				if not app.waiting then
					if Paced(app) and ns.InQuiet(app:Get("quiet")) ~= (s.quiet == true) then Retune(app, s) end
					if Digesting(app) then ns.Safe(ns.Digest.Due, app.host, s) end
				end
			end
		end
	end
	if not any and ticker then
		ticker:Cancel()
		ticker = nil
	end
end

-- starts the app's run; one running goes on with the new time and lease (kit.app on = true again, no stop). The
-- caller (kit.app.open) reconciled it and asked Blocked first
local function Start(app, minutes, lease, agent)
	local rec = Record(app)
	if not rec or not Me() then Fail("app %s cannot start before the player is in the world", app.id) end
	local now = time()
	local s = Owned(app)
	if s and (tonumber(s.ends) or 0) <= now then
		Stop(app, "expired")
		s = nil
	end
	if apps[app.id] ~= app then Fail("app %s is gone", app.id) end   -- (a temporary app went with its run)
	if s then
		s.ends, s.lease = now + math.floor(minutes * 60), lease or nil
		if agent then s.seen = now end
		Retune(app, s)
	else
		-- sent: the run's cursor, the next of its last wake that went; before the first, the newest item there was
		s = { started = now, ends = now + math.floor(minutes * 60), lease = lease or nil, heard = 0, wakes = 0,
			buffer = {}, options = { digest = {} }, seen = agent and now or nil, sent = A.Recent(app, nil, 1).next }
		A.Char(app).run = s
		Retune(app, s)
		if not app.decl.hidden then ns.Say(W.STARTED:format(ns.Escape(Title(app)), date("%H:%M", s.ends))) end
	end
	local waiting = app.waiting
	Reconcile(app, true)
	if Owned(app) == s and app.waiting == waiting then   -- (a change of waiting: Reconcile said so)
		Kit:Emit("kit.app", { app = app.id, on = true, ends = s.ends, waiting = waiting })
	end
	return s
end

------------------------------------------------------------------------------------------------------------------------
-- the player's commands and words

-- cmd: one of the app's controls by its cmd, a word of ns.CONTROL_WORDS, or the label of one of its own
local function ControlOf(app, word)
	if type(word) ~= "string" then return word end
	local cmd = ns.CONTROL_WORDS[word] or ns.CONTROL_WORDS[word:lower()]
	if cmd then return cmd end
	for c, label in pairs(app.decl.labels or {}) do
		if c == word:lower() or ns.T(label) == word then return c end
	end
	return word
end

function Kit:AppControl(id, cmd)
	local app = apps[id]
	cmd = app and ControlOf(app, cmd) or cmd
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
-- what else may change what an app's run should be: each only reconciles (a declaration does in Decl.lua, kit.app.open
-- in Api.lua)

-- an extension registered, turned on or off; a source or a facet registered (another addon's, once its files have
-- run: kit.app.declare's doc tells of it too)
ns.OnChange(function(what, x)
	if what == "extension" then
		if type(x) == "table" and x.active then wasOn[x.id] = true end
	elseif what == "source" or what == "facet" then
		if A.Redeclare then A.Redeclare() end
	else
		return
	end
	All()
end)

-- the runs kept from before a reload (or the last time this character was here) go on, wait or end
ns.When("login", function()
	A.loggedIn, loginAt = true, time()
	All()
end)

------------------------------------------------------------------------------------------------------------------------
-- shared with the other files

A.Retune, A.Present = Retune, Present
A.Drop, A.Stop, A.Blocked, A.Start, A.Reconcile = Drop, Stop, Blocked, Start, Reconcile
