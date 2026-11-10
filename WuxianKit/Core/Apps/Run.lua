-- Apps, runs (see Decl.lua for the apps and for how the four files share names): quiet hours and the pace (Retune),
-- what a run hears and sees (its sources subscribed, its facets watched), the run itself (Blocked, Start, Stop, Resume,
-- Drop, the ticker: the end of its time and of its lease), the player's commands and words (WuxianKit:AppControl,
-- WuxianKit:AppSay), and what else stops an app or resumes it (an extension going off, a source or a facet registered,
-- login).
-- Here by choice: Present, beside the ticker's own lease check (only Api.lua calls it); ns.QuietWindow and ns.InQuiet,
-- with Retune. The count of what was said today (kit.proposal) is in Api.lua, beside the status that reads it.
local addonName, ns = ...
local Kit = ns.Kit
local A = ns.apps
local W, LEASE, Fail, Set, Me, Split, Trim = A.W, A.LEASE, A.Fail, A.Set, A.Me, A.Split, A.Trim
local apps, order, Record, Owned, Run, Title, Paced, Digesting = A.apps, A.order, A.Record, A.Owned, A.Run, A.Title,
	A.Paced, A.Digesting
local Deliver = A.Deliver

local SAY_MAX = 255

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

-- the facets it sees counted as looked at (ns.FacetWatch: the first look turns one on); one not registered yet: once it
-- is
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

-- each entry of a registered source subscribed (one of a source not registered yet: when it is), and the facets it sees
-- watched; what a source gives while its extension is off is not heard
local function Subscribe(app)
	if app.subs then return end
	app.subs = {}
	for _, entry in ipairs(Trim(app.decl.hear)) do
		local name, what = Split(entry)
		local src = name and ns.sources[name]
		if src then
			local ok, t = pcall(src.spec.on, src.ext, what, function(item)
				if src.ext.active then Deliver(app, name, item, false) end
			end)
			if ok then app.subs[#app.subs + 1] = { src = src, token = t } else geterrorhandler()(t) end
		end
	end
	Watch(app)
end

local function Unsubscribe(app)
	for _, sub in ipairs(app.subs or {}) do pcall(sub.src.spec.off, sub.src.ext, sub.token) end
	app.subs = nil
	Unwatch(app)
end

-- whether the app sees a facet of extension ext
local function SeesOf(app, ext)
	for _, name in ipairs(app.decl.see) do
		local facet = ns.facets[name]
		if facet and facet.ext.id == ext then return true end
	end
	return false
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
	local c = A.Char(app)
	local s = c and c.run
	if type(s) ~= "table" then return false end
	c.run = nil
	c.last = { why = why }
	Unsubscribe(app)
	if not quiet and not app.decl.hidden and STOP_WORDS[why] then
		ns.Say(W[STOP_WORDS[why]]:format(ns.Escape(Title(app))))
	end
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

-- why the app cannot start now (for the player: its extension, a source or a facet missing or its extension off, its
-- check), or nil
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
	for _, name in ipairs(d.see) do
		local facet = ns.facets[name]
		if not facet then return W.NEEDS_FACET:format(ns.Text(name)) end
		if not facet.ext.active then return W.NEEDS:format(ns.T(facet.ext.title)) end
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

-- starts the app's run; one running goes on with the new time and lease (kit.app on = true again, no stop), and with
-- what its declaration now says
local function Start(app, minutes, lease, agent)
	local why = Blocked(app)
	if why then Fail("app %s cannot start: %s", app.id, why) end
	local rec = Record(app)
	if not rec or not Me() then Fail("app %s cannot start before the player is in the world", app.id) end
	local now = time()
	local old = Owned(app)
	if old and (tonumber(old.ends) or 0) <= now then
		Stop(app, "expired")
	elseif old then
		old.ends, old.lease = now + math.floor(minutes * 60), lease or nil
		if agent then old.seen = now end
		Retune(app, old)
		Subscribe(app)
		Kit:Emit("kit.app", { app = app.id, on = true, ends = old.ends })
		Ticking()
		return old
	end
	local s = { started = now, ends = now + math.floor(minutes * 60), lease = lease or nil, heard = 0,
		wakes = 0, buffer = {}, options = { digest = {} }, seen = agent and now or nil }
	A.Char(app).run = s
	Retune(app, s)
	Subscribe(app)
	if not app.decl.hidden then ns.Say(W.STARTED:format(ns.Escape(Title(app)), date("%H:%M", s.ends))) end
	Kit:Emit("kit.app", { app = app.id, on = true, ends = s.ends })
	Ticking()
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
-- what else stops an app or starts it again

-- its extension going off stops it, and so does one whose sources it hears or whose facets it sees
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
		if app and (app.decl.extension == e.id or hears or SeesOf(app, e.id)) then Stop(app, "extension") end
	end
end)

-- a source registered (another addon's, once its files have run): kit.app.open's doc tells of it, and an app running
-- that hears it is heard again; a facet the same, and an app running that sees it watches it
ns.OnChange(function(what, source)
	if what == "facet" then                              -- a facet registered: kit.app.open's doc, and apps that see it
		A.DeclareOpen()
		for _, id in ipairs(Ids()) do
			local app = apps[id]
			if app.subs and Run(app) then Watch(app) end
		end
		return
	end
	if what ~= "source" then return end
	A.DeclareOpen()
	for _, id in ipairs(Ids()) do
		local app = apps[id]
		if type(source) == "table" and HearsFrom(app, source.name) and Run(app) then
			Unsubscribe(app)
			Subscribe(app)
		end
	end
end)

ns.When("login", function()
	A.loggedIn = true
	for _, id in ipairs(order) do Resume(apps[id]) end
end)

------------------------------------------------------------------------------------------------------------------------
-- shared with the other files

A.Retune, A.Unsubscribe = Retune, Unsubscribe
A.Drop, A.Stop, A.Present = Drop, Stop, Present
A.Blocked, A.Start, A.Resume = Blocked, Start, Resume
