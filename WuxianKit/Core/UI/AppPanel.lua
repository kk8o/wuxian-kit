-- The app card (0.6): WuxianKit:AppPanel(id, parent, width) draws app `id` in another addon's window, the same card the
-- window shows on its extension's page (UI.AppCard, on the canvas being drawn): its state, one line of the first that holds (no
-- 无限工坊 link, its extension off, its check()'s reason, running but waiting for what it hears to be there, running:
-- the agent here until, last heard from, said today; else ready), its main button, stop, its controls (each drawn and
-- told apart by its cmd: UI.AppControlList), and its options (the core's 活跃度 / 免打扰时段 when it has pace)
-- with the window's controls. Returns a frame (its height set by its content) with :Refresh(), or nil when there is no
-- such app. Cards and the window redraw on kit.app, kit.option, kit.changed and app.<id> (the window also when
-- 无限工坊 gives its list of local extensions), and every few seconds while they show. The zhCN font has no arrows, squares or check marks: the state is told by the text's colour.
-- See ARCHITECTURE.md section 10.
-- The main button, while it does not run: an app with a prompt has 交给 AI (the copy box with its start line: any AI
-- client with 无限工坊's MCP tools starts from it, Claude Code too); one without has none. A temporary app (an agent's,
-- kept in memory only) has no 交给 AI; the window's page marks it.
-- The ns functions it reads are Core/Apps/Api.lua's: ns.AppList (rows with on, temp, hidden, waiting, local), ns.App,
-- ns.AppStatus (with waiting, hear), ns.AppStop, ns.AppOptionList, ns.SetAppOption, ns.AppControls, ns.ForgetApp(id,
-- wipe), ns.CONTROL_WORDS; and Kit:AppControl. One that is not there, or a field a row lacks, counts as none.
local _, ns = ...
local Kit, L, UI = ns.Kit, ns.L, ns.UI
local C = UI.Skin.C
local A, CV = UI.AppWords, UI.Canvas

local TICK = 5                            -- seconds between redraws while a card shows ("last answer n min ago")
local HEARS = 2                           -- of what a listener hears, how many are named on its line
local CORE_OPTIONS = { activity = 1, quiet = 2 }   -- the core's options for an app with pace: first

-- one of the apps' ns functions (Apps/Api.lua's), never breaking a draw (an error goes to the error handler)
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

-- ns.AppList() as drawn: { id, title (shown as is: an agent's escaped), by, addon, extension (the one its declaration
-- names), on, ends, present, prompt, start, temp, localId and from (the local extension that brought it: its id, its
-- title), waiting (why it runs but hears nothing yet, as the runtime says it) }
function UI.Apps()
	local out = {}
	local list = Call(ns.AppList)
	for _, a in ipairs(type(list) == "table" and list or {}) do
		if type(a) == "table" and type(a.id) == "string" and not a.hidden then   -- (plumbing: not drawn)
			local title = a.title
			if a.by == "agent" then title = title ~= nil and ns.Escape(title) or nil else title = ns.T(title) end
			local waiting = a.on and a.waiting or nil
			if waiting == "" then waiting = nil end
			local from = type(a["local"]) == "table" and type(a["local"].id) == "string" and a["local"] or nil
			out[#out + 1] = { id = a.id, title = title ~= nil and title ~= "" and ns.Text(title) or a.id, by = a.by,
				addon = a.addon, extension = type(a.extension) == "string" and a.extension or nil,
				on = a.on and true or false, ends = a.ends, present = a.present, prompt = a.prompt,
				start = type(a.start) == "string" and a.start ~= "" and a.start or nil, temp = a.temp == true,
				localId = from and from.id or nil, from = from and ns.Escape(ns.Text(from.title or from.id)) or nil,
				waiting = waiting }
		end
	end
	return out
end

-- the hidden apps that run (a program's plumbing: not in the list), as the window lists them under an app's page:
-- { id, name (its local extension's title, else its id), hears (what it hears: the first few, and how many), ends }
function UI.Listeners()
	local out = {}
	local list = Call(ns.AppList)
	for _, a in ipairs(type(list) == "table" and list or {}) do
		if type(a) == "table" and type(a.id) == "string" and a.hidden and a.on then
			local st = Call(ns.AppStatus, a.id)
			st = type(st) == "table" and st or {}
			local from = type(a["local"]) == "table" and a["local"].title or nil
			local heard = {}
			for _, h in ipairs(type(a.hear) == "table" and a.hear or type(st.hear) == "table" and st.hear or {}) do
				if type(h) == "string" then heard[#heard + 1] = ns.Escape(h) end
			end
			local hears = #heard > 0 and table.concat(heard, L.SEP, 1, math.min(#heard, HEARS)) or nil
			if #heard > HEARS then hears = A.LISTEN_MORE:format(hears, #heard) end
			local ends = tonumber(a.ends) or tonumber(st.ends)
			out[#out + 1] = { id = a.id, name = ns.Escape(from ~= nil and from ~= "" and from or a.id), hears = hears,
				ends = ends and ends > 0 and ends or nil }
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

-- its controls in order, { cmd, label, own } (a core control's label ours, in the language in force). One of its own
-- (own) has the label it declared, unless that could be taken for another control: a word of the core's
-- (ns.CONTROL_WORDS: 离开 is the core's stop), another control's cmd, or the label of another of its own. Such a one is
-- drawn, and typed, by its cmd, so no label ever names two controls and none of its own passes for stop
function UI.AppControlList(id)
	local out, cmds, times = {}, {}, {}
	local list = Call(ns.AppControls, id)
	for _, c in ipairs(type(list) == "table" and list or {}) do
		local cmd = type(c) == "table" and (c.cmd or c[1]) or c
		if type(cmd) == "string" then
			local label = type(c) == "table" and (c.label or c[2]) or nil
			if label ~= nil then label = ns.Text(ns.T(label)) end
			local own = not A.CONTROL[cmd]
			out[#out + 1] = { cmd = cmd, label = label, own = own or nil }
			cmds[cmd:lower()] = true
			if own and label then times[label:lower()] = (times[label:lower()] or 0) + 1 end
		end
	end
	local core = type(ns.CONTROL_WORDS) == "table" and ns.CONTROL_WORDS or {}
	for _, c in ipairs(out) do
		local label = c.label
		local low = label and label:lower()
		if not c.own then
			c.label = A.CONTROL[c.cmd]
		elseif not label or label == "" or core[low] or core[label] or times[low] > 1
			or (cmds[low] and low ~= c.cmd:lower()) then
			c.label = ns.Escape(c.cmd)
		else
			c.label = ns.Escape(label)
		end
	end
	return out
end

-- the control of app id a word names, as the player types it after /wk <app>: a word of the core's (ns.CONTROL_WORDS)
-- when the app has that control; else the cmd of one, or the label of one of its own as it is drawn. nil: no control
function UI.AppControl(id, word)
	if type(word) ~= "string" or word == "" then return nil end
	local list, low = UI.AppControlList(id), word:lower()
	local core = type(ns.CONTROL_WORDS) == "table" and ns.CONTROL_WORDS or {}
	local cmd = core[low] or core[word]
	for _, c in ipairs(list) do
		if cmd and c.cmd == cmd then return c end
	end
	for _, c in ipairs(list) do
		if c.cmd == word or c.cmd == low then return c end
	end
	for _, c in ipairs(list) do
		if c.own and c.label == ns.Escape(word) then return c end
	end
end

-- the words /wk <app> takes, as the player types them: Chinese ones in Chinese, else the commands
function UI.AppWordList(id)
	local words = {}
	for _, c in ipairs(UI.AppControlList(id)) do words[#words + 1] = ns.Lang() == "zhCN" and c.label or c.cmd end
	return table.concat(words, L.SEP)
end

------------------------------------------------------------------------------------------------------------------------
-- the card

-- what is known of app id: the object, its row of ns.AppList (UI.Apps), its status, and who declared it
local function Facts(id)
	local app = Call(ns.App, id)
	if not app then return nil end
	local entry = Entry(id) or {}
	local st = Call(ns.AppStatus, id)
	st = type(st) == "table" and st or {}
	return app, entry, st, st.by or entry.by
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

-- why an app that runs waits, as the player reads it ("等待中 · 需要来源「quest」"), or nil when it does not. why is
-- the runtime's (kit.app.status's waiting): a sentence for the player, in their language, shown as it is; anything
-- else that is not false goes with no reason
local function Waiting(why)
	if why == nil or why == false or why == "" then return nil end
	if type(why) ~= "string" then return A.WAITING end
	return A.WAITING .. " · " .. ns.Escape(ns.Cut(why, 60))
end

-- the line of the state: text, colour, a hint under it, a button ({ label, primary, fn }); and whether it is ready.
-- waiting: the row's, for a status that does not say
local function State(app, st, by, waiting)
	if not Kit:AgentOnline() then return A.NO_LINK, C.gold, A.NO_LINK_HINT end
	local why, ext, extId = Blocked(app, st, by)
	if extId then
		return why, C.gold, A.EXT_OFF_HINT,                       -- (its page: the switch is right there)
			ext and not UI.OnPage(extId) and { A.OPEN_EXT, false, function() Kit:Window(extId) end } or nil
	end
	if why then return why, C.muted end
	if st.on then
		if st.waiting ~= nil then waiting = st.waiting end
		local waits = Waiting(waiting)                          -- on, but it hears nothing yet: not said to be listening
		if waits then return waits, C.gold, A.WAIT_HINT end
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
	return A.READY, C.sky, nil, nil, true
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
-- ({ label, primary, fn }); heading: what its options are under (选项)
function UI.AppCard(id, extra, heading)
	local app, entry, st, by = Facts(id)
	if not app then return end
	local text, color, hint, button, ready = State(app, st, by, entry.waiting)
	CV.Put(0, color, text)
	if hint then CV.Put(0, C.muted, hint) end
	local row = {}
	local start = st.start or entry.start
	if type(start) ~= "string" or start == "" then start = nil end
	if button then row[#row + 1] = button end
	if not st.on and start and not (entry.temp or st.temp == true) then
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
		CV.Heading(heading or L.OPTIONS)
		CV.Options(OptionOrder(app, list), function(name)
			local e = list[name]
			if type(e) ~= "table" then return nil end
			return agent and Escaped(e) or e, e.value
		end, function(name, v) ns.Act("app.option", id, name, v) end, nil, "app:" .. id)
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
ns.AddAction("app.forget", function(id)                 -- the player's 移除: the declaration, its options, its records
	Call(ns.ForgetApp, id, true)
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
	if what == "app" or what == "apps" or what == "local" then Soon() end
end)

C_Timer.NewTicker(TICK, function()
	UI.TickApps()
	for p in pairs(cards) do
		if p:IsVisible() then DrawCard(p) end
	end
end)
