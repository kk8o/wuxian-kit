-- The app card (0.6): WuxianKit:AppPanel(id, parent, width) draws app `id` in another addon's window, the same card the
-- window's 应用 page shows (UI.AppCard, on the canvas being drawn): its state, one line of the first that holds (no
-- 无限工坊 link, its extension off, its check()'s reason, running: the agent here until, last heard from, said today;
-- else ready), its main button as its driver says, stop, its controls, and its options (the
-- core's 活跃度 / 免打扰时段 when it has pace) with the window's controls. Returns a frame (its height set by its
-- content) with :Refresh(), or nil when there is no such app. Cards and the window's app page redraw on kit.app,
-- kit.option, kit.changed and app.<id>, and every few seconds while they show. The zhCN font has no arrows, squares or
-- check marks: the state is told by the text's colour. See ARCHITECTURE.md section 10.
-- The main button, while it does not run: a prompt's app 交给 AI (the copy box with its start line: any AI client with
-- 无限工坊's MCP tools starts from it, Claude Code too); a program's 开始 (ns.AppLaunch: 无限工坊 starts the program)
-- when 无限工坊 declared it can (launch) and runs, 启动中… (not to be clicked) once asked, 开始 not to be clicked and
-- "needs 无限工坊 running" when it does not run, none and "driven by a local program" without launch. A temporary app
-- (an agent's, kept in memory only) has no 交给 AI; the window's page marks it.
-- The ns functions it reads are Apps.lua's (package K2): ns.AppList (with driver, launch, temp, launching),
-- ns.App, ns.AppStatus, ns.AppStop, ns.AppOptionList, ns.SetAppOption, ns.AppControls, ns.ForgetApp, ns.AppLaunch,
-- ns.WorkshopOnline, ns.CONTROL_WORDS; and Kit:AppControl. One that is not there counts as none (no launch; 无限工坊
-- running as the link says).
local _, ns = ...
local Kit, L, UI = ns.Kit, ns.L, ns.UI
local C = UI.Skin.C
local A, CV = UI.AppWords, UI.Canvas

local TICK = 5                            -- seconds between redraws while a card shows ("last answer n min ago")
local CORE_OPTIONS = { activity = 1, quiet = 2 }   -- the core's options for an app with pace: first

-- one of Apps.lua's functions, never breaking a draw (an error goes to the error handler)
local function Call(fn, ...)
	if type(fn) ~= "function" then return nil end
	local ok, v = pcall(fn, ...)
	if ok then return v end
	geterrorhandler()(v)
	return nil
end

-- the app's declaration: the object's decl when it keeps one apart, else the object
local function Decl(app)
	if type(app) ~= "table" then return {} end
	return type(app.decl) == "table" and app.decl or app
end

------------------------------------------------------------------------------------------------------------------------
-- what the window and the slash command read of the apps

-- ns.AppList() as drawn: { id, title (shown as is: an agent's escaped), by, addon, on, ends, present, prompt, start,
-- driver ("prompt", "program" or nil), launch, temp, launching }
function UI.Apps()
	local out = {}
	local list = Call(ns.AppList)
	for _, a in ipairs(type(list) == "table" and list or {}) do
		if type(a) == "table" and type(a.id) == "string" then
			local title = a.title
			if a.by == "agent" then title = title ~= nil and ns.Escape(title) or nil else title = ns.T(title) end
			out[#out + 1] = { id = a.id, title = title ~= nil and title ~= "" and ns.Text(title) or a.id, by = a.by,
				addon = a.addon, on = a.on and true or false, ends = a.ends, present = a.present, prompt = a.prompt,
				start = type(a.start) == "string" and a.start ~= "" and a.start or nil,
				driver = type(a.driver) == "string" and a.driver or nil, launch = a.launch == true,
				temp = a.temp == true, launching = a.launching == true }
		end
	end
	return out
end

local function Entry(id)
	for _, a in ipairs(UI.Apps()) do
		if a.id == id then return a end
	end
end

function UI.AppTitle(id)
	local e = Entry(id)
	return e and e.title or ns.Escape(id)
end

-- its controls in order, { cmd, label } (the label ours, in the language in force)
function UI.AppControlList(id)
	local out = {}
	local list = Call(ns.AppControls, id)
	for _, c in ipairs(type(list) == "table" and list or {}) do
		local cmd = type(c) == "table" and (c.cmd or c[1]) or c
		if type(cmd) == "string" then
			local label = type(c) == "table" and (c.label or c[2]) or nil
			out[#out + 1] = { cmd = cmd, label = A.CONTROL[cmd] or ns.Escape(label ~= nil and ns.T(label) or cmd) }
		end
	end
	return out
end

-- the words /wk <app> takes, as the player types them: Chinese ones in Chinese, else the commands (a program's app: 开始
-- or start first)
function UI.AppWordList(id)
	local words, e = {}, Entry(id)
	if e and e.driver == "program" then words[1] = A.LAUNCH_WORD end
	for _, c in ipairs(UI.AppControlList(id)) do words[#words + 1] = ns.Lang() == "zhCN" and c.label or c.cmd end
	return table.concat(words, L.SEP)
end

------------------------------------------------------------------------------------------------------------------------
-- the card

-- whether 无限工坊 runs: ns.WorkshopOnline, else the link (Kit:AgentOnline)
local function WorkshopOnline()
	if type(ns.WorkshopOnline) == "function" then
		local ok, on = pcall(ns.WorkshopOnline)
		if not ok then geterrorhandler()(on) end
		return ok and on and true or false
	end
	return Kit:AgentOnline() and true or false
end

-- what is known of app id: the object, its row of ns.AppList (UI.Apps), its status, who declared it, and for a
-- program's app how it starts from the game: "on" (it runs), "none" (no launch: 无限工坊 has not said it can start it),
-- "offline" (无限工坊 does not run), "launching" (asked, not started yet), "ready"; nil for the others
local function Facts(id)
	local app = Call(ns.App, id)
	if not app then return nil end
	local entry = Entry(id) or {}
	local st = Call(ns.AppStatus, id)
	st = type(st) == "table" and st or {}
	local launch
	if (entry.driver or st.driver) == "program" then
		if st.on then
			launch = "on"
		elseif not (entry.launch or st.launch == true) then
			launch = "none"
		elseif not WorkshopOnline() then
			launch = "offline"
		else
			launch = entry.launching and "launching" or "ready"
		end
	end
	return app, entry, st, st.by or entry.by, launch
end

-- why the app cannot start now, as the player reads it, or nil; and when that is its extension being off, the
-- extension (nil when it is not there) and its id
local function Blocked(app, st, by)
	local decl = Decl(app)
	local extId = decl.extension
	local ext = type(extId) == "string" and ns.extensions[extId] or nil
	if st.extension == false or (type(extId) == "string" and not (ext and ext.active)) then
		return A.EXT_OFF:format(ext and ns.T(ext.title) or ns.Escape(extId or "?")), ext, extId or "?"
	end
	local why = st.blocked or st.check
	if why == nil and type(decl.check) == "function" then   -- not in the status: its check asked here
		local ok, got = pcall(decl.check, app)
		if ok then why = got end
	end
	if why ~= nil and why ~= false and why ~= "" then
		why = ns.T(why)
		return by == "agent" and ns.Escape(why) or ns.Text(why)
	end
end

-- the line of the state: text, colour, a hint under it, a button ({ label, primary, fn }); and whether it is ready.
-- launch: how a program's app starts (Facts), nil for the others
local function State(app, st, by, launch)
	if not Kit:AgentOnline() or launch == "offline" then return A.NO_LINK, C.gold, A.NO_LINK_HINT end
	local why, ext, extId = Blocked(app, st, by)
	if extId then
		return why, C.gold, A.EXT_OFF_HINT, ext and { A.OPEN_EXT, false, function() Kit:Window(extId) end } or nil
	end
	if why then return why, C.muted end
	if st.on then
		local now, parts = time(), {}
		if st.present == false then
			parts[1] = A.LEFT
		elseif tonumber(st.ends) then
			parts[1] = A.UNTIL:format(date("%H:%M", tonumber(st.ends)))
		else
			parts[1] = A.PRESENT
		end
		local seen = tonumber(st.seen)
		if not seen then
			parts[2] = A.UNSEEN
		elseif now - seen < 60 then
			parts[2] = A.SEEN_NOW
		else
			parts[2] = A.SEEN:format(math.floor((now - seen) / 60))
		end
		parts[3] = A.SAID:format(tonumber(st.said) or 0)
		return table.concat(parts, " · "), st.present == false and C.gold or C.ok
	end
	if launch == "none" then return A.IDLE, C.muted end
	if launch == "launching" then return A.ASKED, C.sky end
	return launch and A.READY_PROGRAM or A.READY, C.sky, nil, nil, true
end

-- the options' names in order: the object's optionOrder when it keeps one, else the core's first, then by order, name
local function OptionOrder(app, list)
	local names, seen = {}, {}
	if type(app) == "table" and type(app.optionOrder) == "table" then
		for _, name in ipairs(app.optionOrder) do
			if list[name] ~= nil and not seen[name] then names[#names + 1], seen[name] = name, true end
		end
	end
	local rest = {}
	for name in pairs(list) do
		if type(name) == "string" and not seen[name] then rest[#rest + 1] = name end
	end
	local function Rank(name)
		local e = list[name]
		return type(e) == "table" and tonumber(e.order) or CORE_OPTIONS[name] or 1000
	end
	table.sort(rest, function(a, b)
		local ra, rb = Rank(a), Rank(b)
		if ra ~= rb then return ra < rb end
		return a < b
	end)
	for _, name in ipairs(rest) do names[#names + 1] = name end
	return names
end

-- an option an agent declared, its texts escaped (they are drawn as they are)
local function Escaped(e)
	local o = {}
	for k, v in pairs(e) do o[k] = v end
	for _, k in ipairs({ "title", "hint", "unit" }) do
		if o[k] ~= nil then o[k] = ns.Escape(ns.T(o[k])) end
	end
	if type(e.choices) == "table" then
		o.choices = {}
		for i, c in ipairs(e.choices) do
			if type(c) == "table" then
				local v = c.value
				if v == nil then v = c[1] end
				local label = c.label or c[2]
				o.choices[i] = { value = v, label = ns.Escape(ns.T(label ~= nil and label or v)) }
			end
		end
	end
	return o
end

-- the copy box with the start line, the app's title above it
local function Hand(title, start)
	Kit:Copy(start, { title = title, how = A.HAND_HOW })
end

-- app id's card on the canvas being drawn (the window's page, or a panel); extra: more buttons for the row
-- ({ label, primary, fn })
function UI.AppCard(id, extra)
	local app, entry, st, by, launch = Facts(id)
	if not app then return end
	local text, color, hint, button, ready = State(app, st, by, launch)
	if launch == "none" then                                -- a program's: why there is no 开始, when there is none
		hint = A.BY_PROGRAM_HINT
	elseif launch == "offline" then
		hint = A.NEED_WORKSHOP
	end
	CV.Put(0, color, text)
	if hint then CV.Put(0, C.muted, hint) end
	local row = {}
	local start = st.start or entry.start
	if type(start) ~= "string" or start == "" then start = nil end
	if button then row[#row + 1] = button end
	if launch == "launching" then
		row[#row + 1] = { A.LAUNCHING, false, nil, 70, true }
	elseif launch == "ready" or launch == "offline" then  -- 开始, to be clicked only when it is ready
		row[#row + 1] = { A.LAUNCH, ready == true, function() ns.Act("app.launch", id) end, 70, ready ~= true }
	elseif not launch and not st.on and start and not (entry.temp or st.temp == true) then
		local title = entry.title or ns.Escape(id)
		row[#row + 1] = { A.HAND, ready, function() Hand(title, start) end, 70 }
	end
	if st.on then
		row[#row + 1] = { L.STOP, false, function() ns.Act("app.stop", id) end, 70 }
		for _, c in ipairs(UI.AppControlList(id)) do
			if c.cmd ~= "stop" then
				local cmd = c.cmd
				row[#row + 1] = { c.label, false, function() ns.Act("app.control", id, cmd) end, 60 }
			end
		end
	end
	for _, b in ipairs(extra or {}) do row[#row + 1] = b end
	if #row > 0 then
		CV.Current().y = CV.Current().y + 2
		CV.ButtonRow(row)
	end
	local list = Call(ns.AppOptionList, id)
	if type(list) == "table" and next(list) ~= nil then
		local agent = by == "agent"
		CV.Heading(L.OPTIONS)
		CV.Options(OptionOrder(app, list), function(name)
			local e = list[name]
			if type(e) ~= "table" then return nil end
			return agent and Escaped(e) or e, e.value
		end, function(name, v) ns.Act("app.option", id, name, v) end)
	end
end

------------------------------------------------------------------------------------------------------------------------
-- WuxianKit:AppPanel(id, parent, width)

local cards = setmetatable({}, { __mode = "k" })        -- every card made, to redraw every few seconds

local function DrawCard(p)
	CV.Begin(p)
	UI.AppCard(p.app)
	CV.Finish(p)
	p:SetHeight(math.max(1, p.y))
end

-- a frame in parent, width wide (parent's width, else 300), its height as the card takes; p:Refresh() draws it again
-- (it does by itself when it shows, when the app changes and every few seconds). nil when there is no such app
function Kit:AppPanel(id, parent, width)
	if type(id) ~= "string" or not Call(ns.App, id) then return nil end
	parent = parent or UIParent
	width = tonumber(width) or (parent.GetWidth and parent:GetWidth()) or 0
	if not (ns.Finite(width) and width > 0) then width = 300 end
	local p = CreateFrame("Frame", nil, parent)
	p:SetWidth(width)
	p.app, p.body, p.width = id, p, width
	p.texts, p.checks, p.buttons, p.edits = {}, {}, {}, {}
	p.Refresh = DrawCard
	p:SetScript("OnShow", DrawCard)
	cards[p] = true
	UI.AddPanel(p)
	DrawCard(p)
	return p
end

------------------------------------------------------------------------------------------------------------------------
-- what the card's buttons do; redrawing

-- a program's app started from the game (the card's 开始, /wk <app> 开始): ns.AppLaunch asks 无限工坊 to start its
-- program. nil for an app that is not a program's; else true or false, and the line for the player
function UI.AppLaunch(id)
	local app, entry, st, by, launch = Facts(id)
	if not launch then return nil end
	local name = A.NAME:format(entry.title or ns.Escape(id))
	if launch == "on" then return false, A.RUNNING:format(name) end
	if launch == "none" or type(ns.AppLaunch) ~= "function" then return false, A.NO_LAUNCH:format(name) end
	if launch == "offline" then return false, A.CANNOT:format(name, A.NEED_WORKSHOP) end
	if launch == "launching" then return false, A.STARTING:format(name) end
	local why = Blocked(app, st, by)
	if why then return false, A.CANNOT:format(name, why) end
	local ok, done, reason = pcall(ns.AppLaunch, id)
	if not ok then
		geterrorhandler()(done)
		return false, A.CANNOT_PLAIN:format(name)
	end
	if done then return true, A.LAUNCH_SENT:format(name) end
	if reason == nil or reason == "" then return false, A.CANNOT_PLAIN:format(name) end
	return false, A.CANNOT:format(name, ns.Escape(ns.T(reason)))
end

ns.AddAction("app.launch", function(id)
	local ok, line = UI.AppLaunch(id)
	if ok == false then ns.Say(line) end                  -- started: the card says so (启动中…)
	UI.Refresh()
	return ok and true or false
end)
ns.AddAction("app.stop", function(id)
	if not Kit:AppControl(id, "stop") then Call(ns.AppStop, id, "player") end   -- with stop among its controls, the app hears it
	UI.Refresh()
	return true
end)
ns.AddAction("app.control", function(id, cmd)
	local ok = Kit:AppControl(id, cmd)
	UI.Refresh()
	return ok and true or false
end)
ns.AddAction("app.option", function(id, name, value)
	local ok = Call(ns.SetAppOption, id, name, value)
	UI.Refresh()
	return ok and true or false
end)
ns.AddAction("app.forget", function(id)
	Call(ns.ForgetApp, id)
	UI.Refresh()
	return true
end)

local pending                             -- a redraw asked for: one, after the event's handlers ran
local function Soon()
	if pending then return end
	pending = true
	C_Timer.After(0, function()
		pending = false
		UI.Refresh()
	end)
end

for _, topic in ipairs({ "kit.app", "kit.option", "kit.changed", "app.*" }) do Kit:On(topic, Soon) end
ns.OnChange(function(what)
	if what == "app" or what == "apps" then Soon() end
end)

C_Timer.NewTicker(TICK, function()
	UI.TickApps()
	for p in pairs(cards) do
		if p:IsVisible() then DrawCard(p) end
	end
end)
