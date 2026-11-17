-- Apps, reports (0.7; see Decl.lua for the apps and for how the files share names): what the program that drives an
-- app (driver local: its local extension's own, on this computer) tells the game of its work, one channel for all of
-- them. 无限工坊 hands each report on with kit.app.report; the core keeps the last report of each of the app's last
-- KEPT keys, for this character; the app's card shows the newest one's text; and the game half of that extension hears
-- them with ext:OnReport.
--
--   kit.app.report { app, key, state, step?, text?, done?, total?, retry?, data?, at?, late? } -> { kept = true }
--     app     an app with driver local (any other: an error)
--     key     what the report is of (at most KEY_MAX bytes, such as "1794938824:Horde"): a new report of a key takes
--             the place of the one before
--     state   run, done, failed or retry
--     step    the app's own name for where it is (lowercase letters, digits, _; at most STEP_MAX bytes)
--     text    one line for the player (at most TEXT_MAX bytes; plain: drawn escaped)
--     done, total   how far (numbers);  retry   the Unix time it will try again (state retry)
--     data    a small table of the app's own (at most DATA_MAX bytes as it is carried)
--     at      the Unix time 无限工坊 got it (not given: now);  late   true: it could not be handed on when it came
--   A report is kept as { key, state, step, text, done, total, retry, data, at, late }, in
--   WuxianKitDB.apps[app].chars[GUID].reports, oldest first by at.
--
--   ext:OnReport(app, fn)   fn(report, replay) for each report of app: once when it comes (replay false), and those
--                           kept, oldest first, once this extension is on and it is known to be the app's (replay
--                           true): at once for one registered late, else when the extension goes on, at the login, or
--                           when 无限工坊's list comes. report is a copy. fn nil: no longer. Only the game half of
--                           the local extension the app comes with hears them: the extension of the same id, or one
--                           whose addon 无限工坊's list says that local extension brings (ns.LocalOf); another's is an
--                           error where that is known, and hears nothing where it is not known yet
--   ns.AppReport(id)        the newest report kept of app id (a copy), or nil: the card's line
local _, ns = ...
local Kit = ns.Kit
local A = ns.apps
local apps, Driven, Fail, CheckId, Copy = A.apps, A.Driven, A.Fail, A.CheckId, A.Copy

local KEPT = 8
local KEY_MAX, STEP_MAX, TEXT_MAX, DATA_MAX = 64, 24, 200, 4096
local STATES = { run = true, done = true, failed = true, retry = true }

------------------------------------------------------------------------------------------------------------------------
-- a report checked and kept

local function Count(v, what)
	if v == nil then return nil end
	if not ns.Finite(v) or v < 0 then Fail("%s is a number, not negative", what) end
	return v
end

-- kit.app.report's arguments as a report (无限工坊 checked it before: what is not so is its caller's error)
local function Checked(a)
	local key = a.key
	if key == "" or #key > KEY_MAX or key:find("%c") then Fail("key is a text of 1 to %d bytes, one line", KEY_MAX) end
	if not STATES[a.state] then Fail("state is run, done, failed or retry") end
	local step, text = a.step, a.text
	if step ~= nil and (#step > STEP_MAX or not step:match("^[a-z0-9_]+$")) then
		Fail("step is lowercase letters, digits and _, at most %d bytes", STEP_MAX)
	end
	if text ~= nil then
		text = text:gsub("%c+", " ")
		if #text > TEXT_MAX then Fail("text is one line of at most %d bytes (it has %d)", TEXT_MAX, #text) end
		if text == "" then text = nil end
	end
	local data = a.data
	if data ~= nil then
		data = ns.Digest.Small(data)
		if ns.WireSize(data) > DATA_MAX then
			Fail("data is a small table (at most %d bytes as it is carried)", DATA_MAX)
		end
	end
	local at = a.at
	if at ~= nil and not ns.Finite(at) then Fail("at is a Unix time") end
	if a.retry ~= nil and not ns.Finite(a.retry) then Fail("retry is a Unix time") end
	return { key = key, state = a.state, step = step, text = text, done = Count(a.done, "done"),
		total = Count(a.total, "total"), retry = a.retry, data = data, at = at or time(), late = a.late and true or nil }
end

-- this character's reports of an app (made when asked for), or nil before there is a character
local function Reports(app, make)
	local c = A.Char(app)
	if not c then return nil end
	if type(c.reports) ~= "table" then
		if not make then return nil end
		c.reports = {}
	end
	return c.reports
end

-- kept: in the place of the one of its key, oldest first by at (one of the same time after those there), the last KEPT
local function Keep(app, r)
	local list = Reports(app, true)
	if not list then Fail("app %s takes no report before the player is in the world", app.id) end
	for i = #list, 1, -1 do
		if type(list[i]) ~= "table" or list[i].key == r.key then table.remove(list, i) end
	end
	local at = #list + 1
	while at > 1 and (tonumber(list[at - 1].at) or 0) > r.at do at = at - 1 end
	table.insert(list, at, r)
	while #list > KEPT do table.remove(list, 1) end
end

function ns.AppReport(id)
	local app = apps[id]
	local list = app and Driven(app) and Reports(app) or nil
	local r = list and list[#list]
	return type(r) == "table" and Copy(r) or nil
end

------------------------------------------------------------------------------------------------------------------------
-- ext:OnReport

local listeners = {}                      -- app id -> { { ext, fn, replayed } }

-- whether a game extension is the game half of the local extension an app comes with: of the same id, or
-- 无限工坊's list says that local extension is this one's (ns.LocalOf: the one rule). Second: whether that is known to
-- be the answer (false: no list yet, it may still turn out so)
local function Mine(ext, app)
	if not Driven(app) then return false, true end
	local id = app.decl["local"].id
	if id == ext.id then return true, true end
	local x = ns.LocalOf(ext.id, ext.addon)
	return x ~= nil and x.id == id, ns.LocalKnown()
end

-- the reports kept, oldest first, to one who has not had them: once its extension is on, the player is in the world
-- and the app is its extension's
local function Replay(id, l)
	local app = apps[id]
	if l.replayed or not (A.loggedIn and l.ext.active and app and Mine(l.ext, app)) then return end
	l.replayed = true
	for _, r in ipairs(Reports(app) or {}) do
		if type(r) == "table" then ns.Safe(l.fn, Copy(r), true) end
	end
end

local function ReplayAll()
	for id, list in pairs(listeners) do
		for _, l in ipairs(list) do Replay(id, l) end
	end
end

function ns.Extension:OnReport(id, fn)
	if type(id) ~= "string" or (fn ~= nil and type(fn) ~= "function") then
		error("ext:OnReport(app, fn): app is an app's id, fn a function (nil: no longer)", 2)
	end
	local list = listeners[id] or {}
	listeners[id] = list
	for i, l in ipairs(list) do
		if l.ext == self then
			table.remove(list, i)
			break
		end
	end
	if fn == nil then return end
	local app = apps[id]
	if app then                                           -- (not declared yet: it is seen when its reports come)
		local mine, known = Mine(self, app)
		if not mine and known then
			error(("ext:OnReport(%s, fn): %s"):format(id, Driven(app)
				and ("the app comes with the local extension %s, which is not extension %s's"):format(
					app.decl["local"].id, self.id)
				or "no local extension's program drives the app (driver local), so nothing reports for it"), 2)
		end
	end
	local l = { ext = self, fn = fn }
	list[#list + 1] = l
	Replay(id, l)
end

-- a report that came, to those who hear the app's
local function Tell(app, r)
	for _, l in ipairs(listeners[app.id] or {}) do
		if l.ext.active and Mine(l.ext, app) then
			if l.replayed then
				ns.Safe(l.fn, Copy(r), false)
			else                                                 -- (it has not had the others yet: all, this one among them)
				Replay(app.id, l)
			end
		end
	end
end

-- an extension off hears nothing, and has them again when it is back on; a list from 无限工坊, an app declared, the
-- login: one who waited to know has them
ns.OnChange(function(what, x)
	if what == "extension" and type(x) == "table" then
		for _, list in pairs(listeners) do
			for _, l in ipairs(list) do
				if l.ext == x and not x.active then l.replayed = nil end
			end
		end
	end
	if what == "extension" or what == "local" or what == "app" then ReplayAll() end
end)
ns.When("login", ReplayAll)

------------------------------------------------------------------------------------------------------------------------
-- kit.app.report

local kit = Kit:Extension("kit")

kit:Keep("app.report", { title = "kit.app.report",
	args = { app = "string", key = "string", state = "string", step = "string?", text = "string?", done = "number?",
		total = "number?", retry = "number?", data = "table?", at = "number?", late = "boolean?" },
	doc = ("无限工坊 calls this, not an agent: a report of the program that drives an app (driver local; any other app: "
		.. "an error) to the game: {app, key (what it is of, at most %d bytes: a new report of a key takes the place of the "
		.. "one before), state (run|done|failed|retry), step? (the app's own word, lowercase, at most %d bytes), text? (one "
		.. "line for the player, at most %d bytes), done?, total?, retry? (the Unix time it tries again), data? (a small "
		.. "table), at? (the Unix time it was given; default now), late? (true: it could not be handed on when it came)}. "
		.. "Kept for this character (the last of each of the app's last %d keys), shown on the app's card, and heard by "
		.. "the extension's addon in the game. Answers {kept = true}"):format(KEY_MAX, STEP_MAX, TEXT_MAX, KEPT),
	run = function(_, a)
		CheckId(a.app)
		local app = apps[a.app]
		if not app then Fail("no app %s (kit.apps lists them)", a.app) end
		if not Driven(app) then
			Fail("app %s is not driven by a local extension's program (driver local): nothing reports for it", a.app)
		end
		local r = Checked(a)
		Keep(app, r)
		Tell(app, r)
		ns.Changed("report", app.id)
		return { kept = true }
	end })
