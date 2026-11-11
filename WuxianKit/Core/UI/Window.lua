-- The core's window (/wk, the addon compartment): the extensions on the left, the selected one's page on the right, made
-- from what it declared (no extension writes window code): its state and the switch to turn it on or off, its own
-- status line and buttons, its options (the player's choices, made only here or in an OptionsPanel),
-- its scopes to tick "without asking", each ticked one with its budget (a button that goes through the usual ones), and
-- what it can do, a line of titles for each kind. The core's own page lists, instead of what it can do (that is the
-- agent's), what has not run yet, to stop, and what ran, to undo. A page longer than the window scrolls with the mouse
-- wheel, and so does the list at the left. One window: nothing else is spread over the screen.
-- WuxianKit:OptionsPanel(id, parent, width) draws an extension's options in another addon's window with the same
-- controls; both change the same values (the "option" action) and both redraw when one changes.
-- The list, as 无限工坊's App has its extensions: the core's row (扩展框架), then 内置 (无限工坊's own extensions), then
-- 已添加 (the others: another addon's in the game, and the ones added to this computer, which 无限工坊 names:
-- ns.LocalList), each of those with where it runs (游戏, 本机, 游戏 · 本机). There is no list of apps: an app is on
-- the page of the extension it came with, under its own heading, as its card (UI.AppCard, AppPanel.lua: 交给 AI for
-- an app with a prompt), and a row whose app runs has a dot (green; gold while it waits). An app's row is found by
-- the extension its declaration names, else the local extension that brought it, else its addon's extension (an addon
-- with apps and no extension is a row itself). Only an app an agent declared by itself, with no extension at all, is
-- a row of its own, in a last group (Agent 应用) that is there only then, its page the card with a remove button.
-- The window first opens on the first row with an app that runs (none: the core's). The core's page ends with the
-- hidden apps that run (后台监听: a program's plumbing is not listed, but the player sees what listens and can stop
-- it). /wk <app> opens the page its card is on; /wk <app> <word or words> gives it the player's command or words; the
-- words /wk keeps for itself (ns.SLASH_WORDS) come first and are no app's id.
-- UI.Canvas: the drawing pieces, for AppPanel.lua's card (one canvas drawn at a time).
local _, ns = ...
local Kit, L, UI = ns.Kit, ns.L, ns.UI
local S, C = UI.Skin, UI.Skin.C

-- the words of the apps' parts (the window's pages, the card, the slash command)
local A = Kit:Words {
	zhCN = {
		PILL = "应用", TEMP = "临时", BY_AGENT = "Agent 声明", REMOVE = "移除",
		APP = "应用 · %s", TEMP_APP = "临时应用 · %s", APP_OPTIONS = "应用选项",
		ADDS = "补充：%s", ADDS_TO = "补充到应用：%s", MANAGED = "在无限工坊 App 中管理",
		WAITING = "等待中", WAIT_HINT = "就绪后自动开始",
		LISTENERS = "后台监听", LISTEN_MORE = "%s 等 %d 项", LISTEN_UNTIL = "至 %s",
		NO_LINK = "无限工坊未连接", NO_LINK_HINT = "打开无限工坊 App，游戏保持在前台或窗口模式",
		EXT_OFF = "扩展「%s」未启用", EXT_OFF_HINT = "启用后才能接入", OPEN_EXT = "打开扩展页",
		UNTIL = "Agent 在场至 %s", PRESENT = "Agent 在场", LEFT = "Agent 已离开",
		SEEN = "最近应答 %d 分钟前", SEEN_NOW = "最近应答 刚刚", UNSEEN = "Agent 尚未应答", SAID = "今天发言 %d 条",
		READY = "可以接入 Agent",
		HAND = "交给 AI", HAND_HOW = "按 Ctrl+C 复制，粘贴到 AI 对话里",
		CONTROL = { mute = "静音", unmute = "开声", less = "少说", more = "多说", test = "试音", pause = "暂停",
			resume = "继续", stop = "停止" },
		NAME = "「%s」",
		SENT = "已告知%s：%s", SAID_TO = "已转告%s", NOT_RUNNING = "%s未运行", USAGE = "%s的指令：%s",
		NO_WORDS = "%s不接受指令", HELP = "应用：",
	},
	enUS = {
		PILL = "App", TEMP = "Temporary", BY_AGENT = "Declared by an agent", REMOVE = "Remove",
		APP = "App · %s", TEMP_APP = "Temporary app · %s", APP_OPTIONS = "App options",
		ADDS = "Additions: %s", ADDS_TO = "Adds to the apps: %s", MANAGED = "Managed in the Wuxian Workshop app",
		WAITING = "Waiting", WAIT_HINT = "Starts by itself once ready",
		LISTENERS = "Background listeners", LISTEN_MORE = "%s, %d in all", LISTEN_UNTIL = "until %s",
		NO_LINK = "Wuxian Workshop not connected", NO_LINK_HINT = "Open the Wuxian Workshop app; keep the game in front or windowed",
		EXT_OFF = "Extension %s is off", EXT_OFF_HINT = "Turn it on to connect", OPEN_EXT = "Open its page",
		UNTIL = "Agent here until %s", PRESENT = "Agent here", LEFT = "Agent has left",
		SEEN = "Last answer %d min ago", SEEN_NOW = "Last answer just now", UNSEEN = "Agent has not answered yet",
		SAID = "Said today: %d",
		READY = "Ready to connect an agent",
		HAND = "Hand to AI", HAND_HOW = "Press Ctrl+C to copy, then paste it into your AI chat",
		CONTROL = { mute = "Mute", unmute = "Unmute", less = "Less", more = "More", test = "Test", pause = "Pause",
			resume = "Resume", stop = "Stop" },
		NAME = "%s",
		SENT = "Told %s: %s", SAID_TO = "Passed on to %s", NOT_RUNNING = "%s is not running", USAGE = "%s takes: %s",
		NO_WORDS = "%s takes no commands", HELP = "Apps:",
	},
}
UI.AppWords = A

local W, H, LEFT = 670, 470, 206
local TITLE_W = W - LEFT - 210            -- a page's title: room after it for its two capsules
local BODY, ROW = H - 66, 19              -- the page's height; a line's (Put: 14 and 5 between)
local HISTORY_SHOWN = 8
local KIND_ORDER = { "see", "say", "do", "keep", "point" }
local NUMBER_W = 80                       -- a number option's box
local f                                   -- the frame, made the first time it opens
local selected                            -- the page shown: its row's id (Rows); nil at first
local cv                                  -- the canvas being drawn: the window (f) or an OptionsPanel

------------------------------------------------------------------------------------------------------------------------
-- a canvas's pieces, from its pools: cv.body holds them, cv.width is its width, cv.y where the next line goes

-- a line of text (single: cut to one line, "..." at the end)
local function Put(x, color, text, width, single)
	cv.nText = cv.nText + 1
	local fs = cv.texts[cv.nText]
	if not fs then
		fs = S.Text(cv.body)
		cv.texts[cv.nText] = fs
	end
	fs:ClearAllPoints()
	fs:SetPoint("TOPLEFT", cv.body, "TOPLEFT", x, -cv.y)
	fs:SetWidth(width or (cv.width - 12 - x))
	fs:SetWordWrap(not single)
	S.Ink(fs, color)
	fs:SetText(text)
	fs:Show()
	cv.y = cv.y + math.max(14, fs:GetStringHeight()) + 5
	return fs
end

local function PutCheck(x, label, on, onClick, labelWidth)
	cv.nCheck = cv.nCheck + 1
	local c = cv.checks[cv.nCheck]
	if not c then
		c = S.Check(cv.body, function(self, checked) if self.onClick then self.onClick(checked) end end)
		cv.checks[cv.nCheck] = c
	end
	c:ClearAllPoints()
	c:SetPoint("TOPLEFT", cv.body, "TOPLEFT", x, -cv.y)
	c.label:SetWidth(labelWidth or (cv.width - 42 - x))   -- one line, cut with "..." at the page's edge
	c.label:SetWordWrap(false)
	c.label:SetText(label)
	c.Set(on)
	c.onClick = onClick
	c:Show()
	cv.y = cv.y + 22
	return c
end

-- ends the edit a box of canvas c holds: the keyboard let go, and what was typed (when it changed) given to what it was
-- typed for (the box's own onCommit, as when it loses the keyboard by itself), once the draw is over (Finish: a commit
-- draws again, and must not in the middle of this draw)
local function EndEdit(c, e)
	local typed, commit = e:GetText() or "", e.onCommit
	local changed = typed ~= e.kept
	e.kept = typed                                          -- (so losing the keyboard, below, commits nothing itself)
	e:ClearFocus()
	if changed and commit then
		c.late = c.late or {}
		c.late[#c.late + 1] = function() commit(typed) end
	end
end

-- key: what the box edits (a page's option). The boxes are used again by their place, so one that holds the keyboard
-- is still being typed in: for the same key it keeps its text (a redraw does not take it away); for another (another
-- page, the options moved) its edit ends first, so nothing typed for one option is ever committed to another
local function PutEdit(x, text, onCommit, width, key)
	cv.nEdit = cv.nEdit + 1
	local e = cv.edits[cv.nEdit]
	if not e then
		e = S.Edit(cv.body, function(self, value) if self.onCommit then self.onCommit(value) end end)
		cv.edits[cv.nEdit] = e
	end
	e:ClearAllPoints()
	e:SetPoint("TOPLEFT", cv.body, "TOPLEFT", x, -cv.y)
	e:SetWidth(width or (cv.width - 32 - x))
	if e:HasFocus() and (key == nil or e.key ~= key) then EndEdit(cv, e) end
	e.key, e.onCommit = key, onCommit
	if not e:HasFocus() then
		e.kept = text
		e:SetText(text)
	end
	e:Show()
	cv.y = cv.y + 28
	return e
end

local function PutButton(x, y, label, primary, onClick, w)
	cv.nButton = cv.nButton + 1
	local b = cv.buttons[cv.nButton]
	if not b then
		b = S.Button(cv.body, label, primary, function(self) if self.onClick then self.onClick() end end)
		cv.buttons[cv.nButton] = b
	end
	b.label:SetText(label)
	b.primary, b.onClick = primary, onClick
	b:SetSize(w or 86, 22)
	b:ClearAllPoints()
	b:SetPoint("TOPLEFT", cv.body, "TOPLEFT", x, -y)
	S.Enable(b, true)
	b:Show()
	return b
end

-- a button's width for its label, at least least
local function Fit(b, least)
	return math.max(least or 0, math.ceil(b.label:GetStringWidth()) + 20)
end

local function Heading(text)
	cv.y = cv.y + 6
	Put(0, C.gold, text)
end

-- drawing a canvas: Begin, its pieces, Finish (what it did not use of its pools hidden: a box no longer drawn ends its
-- edit as one put to another use does; then, last, what the ended edits commit, each of which may draw again)
local function Begin(c)
	cv = c
	c.nText, c.nCheck, c.nButton, c.nEdit, c.y = 0, 0, 0, 0, 0
end

local function Finish(c)
	for i = c.nText + 1, #c.texts do c.texts[i]:Hide() end
	for i = c.nCheck + 1, #c.checks do c.checks[i]:Hide() end
	for i = c.nButton + 1, #c.buttons do c.buttons[i]:Hide() end
	for i = c.nEdit + 1, #c.edits do
		local e = c.edits[i]
		if e:HasFocus() then EndEdit(c, e) end
		e.key = nil
		e:Hide()
	end
	local late = c.late
	c.late = nil
	for _, commit in ipairs(late or {}) do commit() end
end

------------------------------------------------------------------------------------------------------------------------
-- options, on the window's page and in an OptionsPanel

local function ValueText(o, v)
	if o.kind == "list" then return table.concat(type(v) == "table" and v or {}, L.SEP) end
	return v == nil and "" or tostring(v)
end

-- a row of buttons ({ label, primary, fn, least, off }) from x0 (0), each as wide as its label (at least least), wrapped
-- at the edge; off: drawn but not to be clicked
local function ButtonRow(list, x0)
	x0 = x0 or 0
	local y, x = cv.y, x0
	for _, it in ipairs(list) do
		local b = PutButton(x, y, it[1], it[2], it[3])
		if it[5] then S.Enable(b, false) end
		local w = Fit(b, it[4] or 48)
		if x > x0 and x + w > cv.width - 12 then             -- no room left on this row: the next
			x, y = x0, y + 28
			b:ClearAllPoints()
			b:SetPoint("TOPLEFT", cv.body, "TOPLEFT", x, -y)
		end
		b:SetWidth(w)
		x = x + w + 6
	end
	cv.y = y + 28
end

-- options from a source: the names in order; entry(name) -> the option ({ title, kind, choices, unit, hint }) and its
-- value; set(name, value) when the player changes it. Each with its control: a check box, a text box, a number box and
-- its unit, a row of buttons (the chosen one gold), a text box of items. indent: each title on the left, its control
-- from there on the same row (the core's page: as its language row), its hint under the control. scope: whose options
-- they are ("ext:tune", "app:guild"), for the boxes' keys (PutEdit)
local function Options(order, entry, set, indent, scope)
	local x = indent or 0
	for _, name in ipairs(order) do
		local o, value = entry(name)
		local key = scope and (scope .. ":" .. name) or nil
		local function Set(v) set(name, v) end
		if type(o) ~= "table" then                             -- (gone meanwhile)
		elseif o.kind == "boolean" or o.kind == nil then
			PutCheck(0, ns.T(o.title), value, Set)
		else
			if indent then                                     -- the title beside the control
				local y = cv.y + 4
				cv.y = y
				Put(0, C.fg, ns.T(o.title), indent - 6, true)
				cv.y = o.kind == "choice" and y - 3 or y - 4
			else
				Put(0, C.fg, ns.T(o.title))
			end
			if o.kind == "number" then
				local y = cv.y
				PutEdit(x, ValueText(o, value), Set, NUMBER_W, key)
				if o.unit ~= nil then
					local after = cv.y
					cv.y = y + 4
					Put(x + NUMBER_W + 8, C.muted, ns.T(o.unit), cv.width - 20 - NUMBER_W - x, true)
					cv.y = after
				end
			elseif o.kind == "choice" then
				local row = {}
				for _, c in ipairs(type(o.choices) == "table" and o.choices or {}) do
					local v = c.value
					if v == nil then v = c[1] end
					row[#row + 1] = { ns.T(c.label or c[2] or v), v == value, function() Set(v) end }
				end
				ButtonRow(row, x)
			else                                                   -- text, list
				PutEdit(x, ValueText(o, value), Set, nil, key)
				if o.kind == "list" and not o.hint then Put(x, C.muted, L.OPTION_LIST_HINT) end   -- its own hint says it
			end
		end
		if type(o) == "table" and o.hint then Put(o.kind == "boolean" and 0 or x, C.muted, ns.T(o.hint)) end
	end
end

-- an extension's options; a change is the "option" action, as the window's always were
local function ExtOptions(ext, indent)
	local id = ext.id
	Options(ext.optionOrder, function(name) return ext.options[name], ext:Get(name) end,
		function(name, v) ns.Act("option", id, name, v) end, indent, "ext:" .. id)
end

UI.Canvas = { Begin = Begin, Finish = Finish, Put = Put, PutButton = PutButton, ButtonRow = ButtonRow, Fit = Fit,
	Heading = Heading, Options = Options, Current = function() return cv end }

------------------------------------------------------------------------------------------------------------------------
-- an extension's page

local function StateText(e)
	if e.state == "missing" then return L.STATE.missing:format(ns.ReasonText(e.reason)) end
	return L.STATE[e.state] or e.state
end

-- what an extension can do: a line of titles for each kind (a title said once)
local function Capabilities(ext)
	Heading(L.CAPABILITIES)
	if not ext or #ext.capOrder == 0 or not ext.active then return Put(0, C.muted, L.NO_CAPABILITIES) end
	local byKind, seen = {}, {}
	for _, name in ipairs(ext.capOrder) do
		local c = ext.caps[name]
		local title = ns.T(c.title)
		if not seen[c.kind .. title] then
			seen[c.kind .. title] = true
			byKind[c.kind] = byKind[c.kind] or {}
			table.insert(byKind[c.kind], title)
		end
	end
	for _, kind in ipairs(KIND_ORDER) do
		if byKind[kind] then Put(0, C.fg, L.KIND_LINE:format(L.KIND[kind] or kind, table.concat(byKind[kind], L.SEP))) end
	end
end

-- budgets for a ticked scope: { per, most } (and used, how many ran without asking in the last per seconds), or none
-- (true, or a table without them: no limit)
local PRESETS = { { per = 600, most = 1 }, { per = 600, most = 3 }, { per = 600, most = 6 }, { per = 3600, most = 10 } }

local function BudgetKey(b)
	if type(b) == "table" and tonumber(b.per) and tonumber(b.most) then return b.per .. "/" .. b.most end
	return "any"
end

-- the budgets the button goes through: the scope's suggested one, the usual ones, no limit (false); none twice
local function Budgets(scope)
	local out, seen = {}, {}
	local function Add(b)
		local key = BudgetKey(b)
		if seen[key] then return end
		seen[key] = true
		out[#out + 1] = b and { per = b.per, most = b.most } or false
	end
	local suggested = ns.ScopeBudget(scope)
	if suggested then Add(suggested) end
	for _, b in ipairs(PRESETS) do Add(b) end
	Add(false)
	return out
end

local function NextBudget(scope, g)
	local list, key = Budgets(scope), BudgetKey(g)
	for i = 1, #list do
		if BudgetKey(list[i]) == key then return list[i % #list + 1] end
	end
	return list[1]
end

local function BudgetText(g)
	if BudgetKey(g) == "any" then return L.BUDGET_ANY end
	local text = L.BUDGET:format(S.Duration(g.per), g.most)
	if tonumber(g.used) then text = text .. " · " .. L.COUNT:format(g.used, g.most) end
	return text
end

-- the hidden apps that run (UI.Listeners, AppPanel.lua), under their heading: a line each (its name, what it hears,
-- until when) with a stop. None: nothing drawn
local function Listeners()
	local list = UI.Listeners()
	if #list == 0 then return end
	Heading(A.LISTENERS)
	for _, a in ipairs(list) do
		local parts = {}
		if a.hears then parts[#parts + 1] = a.hears end
		if a.ends then parts[#parts + 1] = A.LISTEN_UNTIL:format(date("%H:%M", a.ends)) end
		local y = cv.y
		Put(0, C.fg, #parts > 0 and ("%s  |cff9c9ea6%s|r"):format(a.name, table.concat(parts, " · ")) or a.name,
			W - LEFT - 150, true)
		PutButton(W - LEFT - 128, y - 2, L.STOP, false, function() ns.Act("app.stop", a.id) end, 70)
	end
end

------------------------------------------------------------------------------------------------------------------------
-- the rows of the list

-- what an addon's .toc says of it (## Version, ## Author ...), or nil
local function Meta(addon, field)
	local ok, v = pcall(C_AddOns.GetAddOnMetadata, addon, field)
	if ok and type(v) == "string" and v ~= "" then return v end
end

-- Rows(): the list's groups in order ({ kind (core, sys, custom, agent), list }) and every row. A row: { id (what
-- `selected` holds), title, version, addon, author, notes, where (game, local, both), state (on, off, disabled,
-- missing), apps (its rows of UI.Apps), running, waiting (one of its apps is), and one of: ext (a row of
-- ns.ExtensionList, with its fields), managed (a local extension: 无限工坊's App turns it on and off), loose (an
-- agent's app with no extension: app, temp), or none (an addon with apps and no extension) }. Texts are ready to draw
local function Rows()
	local groups = { { kind = "core", list = {} }, { kind = "sys", list = {} }, { kind = "custom", list = {} },
		{ kind = "agent", list = {} } }
	local all, byId, byAddon, byLocal = {}, {}, {}, {}
	local function Add(g, e)
		e.apps = {}
		table.insert(groups[g].list, e)
		all[#all + 1] = e
		return e
	end
	for _, e in ipairs(ns.ExtensionList()) do
		e.ext, e.where = true, "game"
		byId[e.id] = e
		if e.addon and not e.builtin then byAddon[e.addon] = byAddon[e.addon] or e end
		Add(e.core and 1 or e.official and 2 or 3, e)
	end
	for _, x in ipairs(ns.LocalList()) do                    -- the ones on this computer, as 无限工坊 names them
		local row
		for _, id in ipairs(x.game) do row = row or byId[id] end
		if row and x.where == "both" then                   -- in the game too: its row there, marked
			row.where, row.adds = "both", x.adds
			row.author = row.author or (x.author and ns.Escape(x.author))
		else
			row = Add(3, { id = "local:" .. x.id, title = ns.Escape(x.title), version = x.version and ns.Escape(x.version),
				author = x.author and ns.Escape(x.author), notes = x.notes and ns.Escape(x.notes), where = x.where,
				state = x.on and "on" or "off", managed = true, adds = x.adds })
		end
		byLocal[x.id] = row
	end
	for _, a in ipairs(UI.Apps()) do
		local agent = a.by == "agent"
		local row = a.extension and byId[a.extension] or a.localId and byLocal[a.localId]
			or not agent and a.addon and byAddon[a.addon] or nil
		if row then                                           -- (found)
		elseif a.localId then                                 -- 无限工坊 gave no list (an older one): the app's own label
			row = Add(3, { id = "local:" .. a.localId, title = a.from, where = "local", state = "on", managed = true })
			byLocal[a.localId] = row
		elseif not agent and a.addon then                     -- an addon with apps and no extension: the addon
			local ok, _, title = pcall(C_AddOns.GetAddOnInfo, a.addon)
			row = Add(3, { id = "addon:" .. a.addon, title = ok and type(title) == "string" and title ~= "" and title
				or ns.Escape(a.addon), addon = a.addon, version = Meta(a.addon, "Version"), author = Meta(a.addon, "Author"),
				where = "game", state = "on" })
			byAddon[a.addon] = row
		else                                                  -- an agent's, by itself
			row = Add(4, { id = "app:" .. a.id, app = a.id, title = a.title, temp = a.temp, loose = true, state = "on" })
		end
		table.insert(row.apps, a)
		row.running = row.running or a.on
		row.waiting = row.waiting or a.waiting ~= nil
	end
	return groups, all
end

-- the row a page names: a row's own id (an extension's id, "local:<id>" ...), else the row app `page` ("app:<id>" too)
-- is on. nil: none
local function Find(page)
	local _, all = Rows()
	for _, e in ipairs(all) do
		if e.id == page then return e.id end
	end
	local app = page:match("^app:(.+)$") or page
	for _, e in ipairs(all) do
		for _, a in ipairs(e.apps) do
			if a.id == app then return e.id end
		end
	end
end

-- whether the window is drawing the page of row id now (the card: no button to a page that is this one)
function UI.OnPage(id) return cv == f and f ~= nil and selected == id end

------------------------------------------------------------------------------------------------------------------------
-- the pages

-- a page's title, then its capsules: its kind, and where it runs (none: no second capsule)
local function Title(text, kind, tone, where)
	local title = Put(0, C.fg, text, TITLE_W, true)
	f.pill.Set(kind, tone)
	f.pill:ClearAllPoints()
	f.pill:SetPoint("LEFT", title, "LEFT", math.min(math.ceil(title:GetStringWidth()), TITLE_W) + 8, 0)
	f.pill:Show()
	f.where:SetShown(where ~= nil)
	if where then
		f.where.Set(L.WHERE[where] or where, "sys")
		f.where:ClearAllPoints()
		f.where:SetPoint("LEFT", f.pill, "RIGHT", 6, 0)
	end
end

-- the local extensions that are on and add to app id (无限工坊's list), their titles in a line; nil: none
local function Adders(id)
	local names = {}
	for _, x in ipairs(ns.LocalList()) do
		for _, app in ipairs(x.on and x.adds or {}) do
			if app == id then names[#names + 1] = ns.Escape(x.title) end
		end
	end
	return #names > 0 and table.concat(names, L.SEP) or nil
end

-- a row's apps, each under its heading: its card (its own options under 应用选项: the page has the extension's 选项
-- too), then the local extensions that add to it
local function Apps(e)
	for _, a in ipairs(e.apps) do
		Heading((a.temp and A.TEMP_APP or A.APP):format(a.title))
		UI.AppCard(a.id, nil, A.APP_OPTIONS)
		local adds = Adders(a.id)
		if adds then Put(0, C.muted, A.ADDS:format(adds)) end
	end
end

local function Page(e)
	local ext = e.ext and ns.extensions[e.id] or nil
	Title(e.title or e.id, e.official and L.GROUP.sys or L.GROUP.custom, e.official and "sys" or "custom", e.where)
	local facts = {}
	if e.ext or e.version then facts[#facts + 1] = L.VERSION:format(e.version or "?") end
	if e.ext or e.managed then facts[#facts + 1] = StateText(e) end
	if not e.builtin and e.addon and e.addon ~= e.title then facts[#facts + 1] = e.addon end
	if e.author then facts[#facts + 1] = L.AUTHOR:format(e.author) end
	if #facts > 0 then Put(0, C.muted, table.concat(facts, " · ")) end
	if e.notes then Put(0, C.muted, e.notes) end
	if e.managed then Put(0, C.muted, A.MANAGED) end        -- on, off, removed: in 无限工坊's App, not here
	if e.adds and #e.adds > 0 then                          -- the apps it adds to (their documents, their wakes)
		local names = {}
		for _, id in ipairs(e.adds) do names[#names + 1] = UI.AppTitle(id) end
		Put(0, C.muted, A.ADDS_TO:format(table.concat(names, L.SEP)))
	end
	if e.ext and not e.core and e.state ~= "disabled" and e.state ~= "missing" then
		PutCheck(0, L.ENABLED, e.state == "on", function(on) ns.Act("switch", e.id, on) end)
	end
	if e.core then                                          -- the core: the language, the chosen one marked
		local y = cv.y + 4
		cv.y = y
		Put(0, C.fg, L.LANGUAGE, 70)
		local choice = ns.LanguageChoice()
		for i, lang in ipairs(ns.LANGUAGES) do
			PutButton(76 + (i - 1) * 84, y - 3, lang[2] or L.LANG_AUTO, lang[1] == choice,
				function() ns.Act("language", lang[1]) end, 78)
		end
		cv.y = y + 26
		if ext and #ext.optionOrder > 0 then ExtOptions(ext, 76) end   -- its options (称呼) as rows like the language's
	end
	if ext and ext.active then
		if ext.status then
			local ok, line = pcall(ext.status, ext)
			if ok and line then Put(0, C.sky, ns.Text(line)) end
		end
		if ext.buttons then                                   -- its buttons
			local y, x = cv.y, 0
			for i, b in ipairs(ext.buttons) do
				PutButton(x, y, ns.T(b.label), false, function() ns.Act("button", e.id, i) end)
				x = x + 96
			end
			cv.y = y + 30
		end
	end
	Apps(e)                                                 -- the apps it came with
	if ext and not e.core and #ext.optionOrder > 0 then     -- the player's choices for it, made here and only here
		Heading(L.OPTIONS)
		ExtOptions(ext)
	end
	if e.core then                                          -- the core: what has not run yet, a stop for each
		local open = ns.Open()
		if #open > 0 then
			Heading(L.OPEN)
			for _, id in ipairs(open) do
				local p = ns.Get(id)
				local y = cv.y
				Put(0, C.fg, ("#%d  |cff7fb3e0%s|r  %s"):format(p.id, L.OPEN_STATE[p.state] or p.state,
					p.title or p.steps[1].preview[1] or ""), W - LEFT - 150, true)
				PutButton(W - LEFT - 128, y - 2, p.state == "pending" and L.DECLINE or L.CANCEL, false,
					function() ns.Act("decline", id) end, 70)
			end
		end
	end
	if ext and #ext.scopeOrder > 0 then                     -- each ticked one with its budget, a click the next one
		Heading(L.PERMISSIONS)
		Put(0, C.muted, L.PERMISSIONS_HINT)
		local grants = ns.Grants()
		for _, scope in ipairs(ext.scopeOrder) do
			local g = grants[scope]
			local y = cv.y
			if g then
				local b = PutButton(0, y - 3, BudgetText(g), false,
					function() ns.Act("grant", scope, true, NextBudget(scope, g)) end)
				local w = Fit(b, 90)
				b:SetWidth(w)
				b:ClearAllPoints()
				b:SetPoint("TOPLEFT", cv.body, "TOPLEFT", cv.width - 12 - w, -(y - 3))
				PutCheck(0, ns.T(ext.scopes[scope]), true, function(on) ns.Act("grant", scope, on) end, cv.width - 62 - w)
			else
				PutCheck(0, ns.T(ext.scopes[scope]), false, function(on) ns.Act("grant", scope, on) end)
			end
		end
	end
	if not e.core then
		if e.ext then Capabilities(ext) end                 -- (a local extension's are 无限工坊's tools, not the game's)
		return
	end
	Heading(L.HISTORY)                                      -- the core: what ran, newest first
	do
		local h = ns.History()
		if #h == 0 then Put(0, C.muted, L.NO_HISTORY) end
		for i = #h, 1, -1 do
			if #h - i == HISTORY_SHOWN then
				Put(0, C.muted, L.HISTORY_MORE:format(i))
				break
			end
			local x = h[i]
			local first = x.steps[1] and x.steps[1].preview and x.steps[1].preview[1] or ""
			local y = cv.y
			Put(0, x.undone and C.muted or C.fg, ("#%d  %s  %s%s"):format(x.id, date("%H:%M", x.ran),
				x.undone and ("(" .. L.UNDONE_MARK .. ")  ") or "", x.title or first), W - LEFT - 150, true)
			if x.undoable and not x.undone then
				PutButton(W - LEFT - 128, y - 2, L.UNDO, false, function() ns.Act("undo", x.id) end, 70)
			end
		end
	end
	Listeners()                                             -- what listens in the background, whoever started it
end

-- the page of an app an agent declared by itself: its title (a temporary one's capsule says so), who declared it, its
-- card with a remove button
local function AppPage(e)
	Title(e.title, e.temp and A.TEMP or A.PILL, "custom")
	Put(0, C.muted, A.BY_AGENT)
	UI.AppCard(e.app, { { A.REMOVE, false, function() ns.Act("app.forget", e.app) end } })
end

------------------------------------------------------------------------------------------------------------------------
-- the window

local function Frame()
	if f then return f end
	f = S.Panel("WuxianKitWindow", W, H, "window")
	tinsert(UISpecialFrames, "WuxianKitWindow")             -- Esc closes it
	f.title = S.Text(f, C.gold)
	f.title:SetPoint("TOPLEFT", 14, -12)
	f.title:SetText(L.TITLE)
	f.agent = S.Text(f, C.muted)
	f.agent:SetPoint("TOPLEFT", 14, -32)
	f.close = S.Button(f, "×", false, function() f:Hide() end)
	f.close:SetSize(24, 24)
	f.close:SetPoint("TOPRIGHT", -8, -8)
	f.side = CreateFrame("ScrollFrame", nil, f)              -- the list, cut at the window's edge, scrolled by the wheel
	f.side:SetPoint("TOPLEFT", 10, -56)
	f.side:SetSize(LEFT - 10, BODY)
	f.side:EnableMouseWheel(true)
	f.side:SetScript("OnMouseWheel", function(self, delta)
		self:SetVerticalScroll(math.max(0, math.min(self:GetVerticalScroll() - delta * 2 * 24, f.sideRange or 0)))
	end)
	f.list = CreateFrame("Frame", nil, f.side)
	f.list:SetSize(LEFT - 10, BODY)
	f.side:SetScrollChild(f.list)
	f.items = {}
	f.scroll = CreateFrame("ScrollFrame", nil, f)            -- the page, cut at the window's edge, scrolled by the wheel
	f.scroll:SetPoint("TOPLEFT", LEFT + 14, -56)
	f.scroll:SetSize(W - LEFT - 28, BODY)
	f.scroll:EnableMouseWheel(true)
	f.scroll:SetScript("OnMouseWheel", function(self, delta)
		self:SetVerticalScroll(math.max(0, math.min(self:GetVerticalScroll() - delta * 3 * ROW, f.range or 0)))
	end)
	f.body = CreateFrame("Frame", nil, f.scroll)
	f.body:SetSize(W - LEFT - 28, BODY)
	f.width = W - LEFT - 28
	f.scroll:SetScrollChild(f.body)
	f.more = S.Text(f, C.muted, true)
	f.more:SetPoint("TOPRIGHT", -40, -34)
	f.more:SetText(L.SCROLL)
	f.texts, f.checks, f.buttons, f.edits, f.heads = {}, {}, {}, {}, {}
	f.pill, f.where = S.Pill(f.body), S.Pill(f.body)
	local sep = f:CreateTexture(nil, "BORDER")
	sep:SetPoint("TOPLEFT", LEFT + 2, -56)
	sep:SetSize(1, H - 66)
	S.Fill(sep, C.line)
	return f
end

local function Item(i)
	local b = f.items[i]
	if not b then
		b = CreateFrame("Button", nil, f.list)
		b:SetSize(LEFT - 14, 22)
		b.bg = b:CreateTexture(nil, "BACKGROUND")
		b.bg:SetAllPoints()
		b.dot = b:CreateTexture(nil, "ARTWORK")             -- one of its apps runs: a dot before the title
		b.dot:SetSize(6, 6)
		b.dot:SetPoint("LEFT", 3, 0)
		if b.CreateMaskTexture and b.dot.AddMaskTexture then
			local m = b:CreateMaskTexture()
			m:SetTexture("Interface\\Masks\\CircleMaskScalable", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
			m:SetAllPoints(b.dot)
			b.dot:AddMaskTexture(m)
		end
		b.label = S.Text(b, C.fg)
		b.label:SetPoint("LEFT", 12, 0)
		b.label:SetWordWrap(false)                          -- a long title: one line, cut with "..."
		b.state = S.Text(b, C.muted, true)                  -- where it runs, dim, at the right
		b.state:SetPoint("RIGHT", -8, 0)
		b.state:SetJustifyH("RIGHT")
		b:SetScript("OnClick", function(self)
			selected = self.id
			f.scroll:SetVerticalScroll(0)
			UI.Refresh()
		end)
		f.items[i] = b
	end
	return b
end

function UI.DrawWindow()
	if not (f and f:IsShown()) then return end
	f.title:SetText(L.TITLE)
	f.more:SetText(L.SCROLL)
	f.agent:SetText(not ns.bound and "" or Kit:AgentOnline() and L.AGENT_ON or L.AGENT_OFF)   -- none without 无限工坊
	local groups, all = Rows()
	local current
	for _, e in ipairs(all) do
		if e.id == selected then current = e end
	end
	if not current then                                    -- none chosen yet, or gone: the first whose app runs, else the core
		for _, e in ipairs(all) do
			if e.running then current = current or e end
		end
		current = current or all[1]
		selected = current.id
	end
	f.ticks = #current.apps > 0                            -- (UI.TickApps)
	local n, nHead, y = 0, 0, 0
	for _, g in ipairs(groups) do
		if #g.list > 0 then
			if g.kind ~= "core" then                          -- (the core's row: by itself, above the groups)
				nHead = nHead + 1
				local h = f.heads[nHead] or S.Text(f.list, C.muted, true)
				f.heads[nHead] = h
				h:ClearAllPoints()
				h:SetPoint("TOPLEFT", f.list, "TOPLEFT", 8, -y - 3)
				h:SetText(L.GROUP[g.kind])
				h:Show()
				y = y + 20
			end
			for _, e in ipairs(g.list) do
				n = n + 1
				local b = Item(n)
				b:ClearAllPoints()
				b:SetPoint("TOPLEFT", 0, -y)
				b.id = e.id
				local tag = g.kind == "custom" and L.WHERE[e.where] or e.temp and A.TEMP or ""
				b.state:SetText(tag)
				b.state:SetShown(tag ~= "")
				b.label:SetText(e.title or e.id)
				b.label:SetWidth(LEFT - 34 - (tag ~= "" and math.ceil(b.state:GetStringWidth()) + 6 or 0))
				b.dot:SetShown(e.running and true or false)
				S.Fill(b.dot, e.waiting and C.gold or C.ok)
				S.Fill(b.bg, e.id == selected and C.goldSoft or C.panel2)
				S.Ink(b.label, e.state == "on" and C.fg or C.muted)
				b:Show()
				y = y + 24
			end
			y = y + 8
		end
	end
	for i = n + 1, #f.items do f.items[i]:Hide() end
	for i = nHead + 1, #f.heads do f.heads[i]:Hide() end
	f.sideRange = math.max(0, y - 8 - BODY)                -- how far the list scrolls
	f.list:SetHeight(BODY + f.sideRange)
	if f.side:GetVerticalScroll() > f.sideRange then f.side:SetVerticalScroll(f.sideRange) end
	Begin(f)
	if current.loose then AppPage(current) else Page(current) end
	f.range = math.max(0, f.y + 8 - BODY)                  -- how far the page scrolls
	f.body:SetHeight(BODY + f.range)
	if f.scroll:GetVerticalScroll() > f.range then f.scroll:SetVerticalScroll(f.range) end
	f.more:SetShown(f.range > 0)
	Finish(f)
end

------------------------------------------------------------------------------------------------------------------------
-- WuxianKit:OptionsPanel(id, parent, width): extension id's options in another addon's window

local panels = setmetatable({}, { __mode = "k" })       -- every panel made (and the apps' cards), to redraw

-- another panel to redraw with the window: p:Refresh() while it is visible (AppPanel.lua's cards)
function UI.AddPanel(p) panels[p] = true end

local function DrawPanel(p)
	if not ns.extensions[p.ext.id] then return end
	Begin(p)
	ExtOptions(p.ext)
	Finish(p)
	p:SetHeight(math.max(1, p.y))
end

-- a frame in parent, width wide (parent's width, else 300), its height as its options take; p:Refresh() draws it
-- again (it does by itself when it shows and when an option changes). nil when there is no such extension or it has
-- no options
function Kit:OptionsPanel(id, parent, width)
	local ext = type(id) == "string" and ns.extensions[id]
	if not ext or #ext.optionOrder == 0 then return nil end
	parent = parent or UIParent
	width = tonumber(width) or (parent.GetWidth and parent:GetWidth()) or 0
	if not (ns.Finite(width) and width > 0) then width = 300 end
	local p = CreateFrame("Frame", nil, parent)
	p:SetWidth(width)
	p.ext, p.body, p.width = ext, p, width
	p.texts, p.checks, p.buttons, p.edits = {}, {}, {}, {}
	p.Refresh = DrawPanel
	p:SetScript("OnShow", DrawPanel)
	panels[p] = true
	DrawPanel(p)
	return p
end

function UI.Toggle()
	Frame()
	if f:IsShown() then
		f:Hide()
	else
		S.Place(f, "window", "CENTER", 60, -20)          -- clear of the frame code WoWBridge shows top left
		f:Show()
		UI.DrawWindow()
	end
end

-- WuxianKit:Window(page): the window, open and in front, on an extension's page ("tune", "chat" ...; "kit" the core's),
-- or on the page an app's card is on (the app's id, or "app:<id>": an extension of that name comes first); without one,
-- or with one not there, on the page it showed last (at first the first whose app runs, else the core's). For other
-- addons' buttons (WoWBridge's panel, its minimap button)
function Kit:Window(page)
	Frame()
	local want = type(page) == "string" and Find(page) or nil
	if want and want ~= selected then
		selected = want
		f.scroll:SetVerticalScroll(0)
	end
	if not f:IsShown() then
		S.Place(f, "window", "CENTER", 60, -20)
		f:Show()
	end
	f:Raise()
	UI.DrawWindow()
	return true
end

function UI.Refresh()
	UI.DrawProposal()
	UI.DrawWindow()
	for p in pairs(panels) do
		if p:IsVisible() then p:Refresh() end
	end
end

-- every few seconds (AppPanel.lua): a page with an app's card drawn again ("last answer n min ago")
function UI.TickApps()
	if f and f:IsShown() and f.ticks then UI.DrawWindow() end
end

function UI.Tick()
	UI.TickProposal()
	if f and f:IsShown() then f.agent:SetText(not ns.bound and "" or Kit:AgentOnline() and L.AGENT_ON or L.AGENT_OFF) end
end

------------------------------------------------------------------------------------------------------------------------
-- what the window's own buttons do, the slash command, the key bindings, the addon compartment

ns.AddAction("switch", function(id, on)
	local ok, why = ns.Switch(id, on)
	UI.Refresh()
	return ok, why
end)
ns.AddAction("option", function(id, name, value)
	local ext = ns.extensions[id]
	local ok = ext ~= nil and ns.SetOption(ext, name, value)
	UI.Refresh()
	return ok
end)
ns.AddAction("language", function(choice)
	ns.SetLanguage(choice)
	return true
end)
ns.AddAction("button", function(id, i)
	local ext = ns.extensions[id]
	local b = ext and ext.buttons and ext.buttons[i]
	if not b then return false end
	local ok = ns.Safe(b.fn, ext)
	UI.Refresh()
	return ok
end)

-- /wk <app> <rest>: the page its card is on when nothing follows; a word that names one of its controls (UI.AppControl: a word of
-- ns.CONTROL_WORDS, or the cmd or the label of one of its own) the command, given by its cmd; else the player's words,
-- when it takes them; else what it takes
local function AppCommand(id, rest)
	if rest == "" then return Kit:Window("app:" .. id) end
	local name = A.NAME:format(UI.AppTitle(id))
	local c = UI.AppControl(id, rest:match("^(%S+)"))
	if c then
		if Kit:AppControl(id, c.cmd) then return ns.Say(A.SENT:format(name, c.label)) end
		return ns.Say(A.NOT_RUNNING:format(name))
	end
	if Kit:AppSay(id, rest) then return ns.Say(A.SAID_TO:format(name)) end
	local words = UI.AppWordList(id)
	if words == "" then return ns.Say(A.NO_WORDS:format(name)) end
	ns.Say(A.USAGE:format(name, words))
end

-- /wk's own words (lowercase), each with what it does with the rest of the line. They come before an extension's
-- command and an app's id, so neither can take one. ns.SLASH_WORDS: the set of them, for whoever checks a name
-- (Decl.lua's CheckId: an app's id is none of these)
local SLASH = {}

-- /wk yes | no [n]: the one numbered, the one shown, or the oldest
local function Answer(yes, rest)
	local id = tonumber(rest:match("^(%d+)"))
	if yes and not id and UI.Settling() then return end     -- another just took the place of the one shown: not yet
	id = id or UI.Current() or (yes and ns.Waiting() or ns.Open())[1]
	if not id then return ns.Say(yes and L.NONE_PENDING or L.NONE_OPEN) end
	local p = ns.Get(id)
	if not (p and (p.state == "pending" or not yes and (p.state == "waiting" or p.state == "queued"))) then
		return ns.Say(L.NOT_OPEN:format(id))
	end
	ns.Act(yes and "run" or "decline", id)
end

function SLASH.yes(rest) Answer(true, rest) end
function SLASH.no(rest) Answer(false, rest) end

function SLASH.lang(rest)
	local want = ({ auto = "auto", zh = "zhCN", zhcn = "zhCN", en = "enUS", enus = "enUS" })[rest:lower()]
	if not want then return ns.Say(L.LANG_USAGE) end
	ns.Act("language", want)
end

function SLASH.help()
	ns.Say(L.HELP)
	local words = {}
	for word, c in pairs(ns.Commands()) do
		if c.ext.active and c.help and not SLASH[word] then words[#words + 1] = word end
	end
	table.sort(words)
	for _, word in ipairs(words) do ns.Say(L.HELP_COMMAND:format(word, ns.T(ns.Commands()[word].help))) end
	local apps = UI.Apps()
	if #apps > 0 then ns.Say(A.HELP) end
	for _, a in ipairs(apps) do
		local takes = UI.AppWordList(a.id)
		ns.Say(L.HELP_COMMAND:format(a.id, a.title .. (takes ~= "" and (" · " .. takes) or "")))
	end
end

ns.SLASH_WORDS = {}
for word in pairs(SLASH) do ns.SLASH_WORDS[word] = true end

SLASH_WUXIANKIT1 = "/wk"
SlashCmdList.WUXIANKIT = function(msg)
	local cmd, rest = (msg or ""):match("^%s*(%S*)%s*(.-)%s*$")
	cmd = cmd:lower()
	local command = ns.Commands()[cmd]
	if SLASH[cmd] then                                      -- /wk's own, before any other's
		SLASH[cmd](rest)
	elseif command and command.ext.active then             -- an extension's own: /wk <word> ...
		ns.Safe(command.fn, command.ext, rest)
	elseif cmd ~= "" and ns.App(cmd) then                  -- an app's: /wk <app> [word or words]
		AppCommand(cmd, rest)
	else
		UI.Toggle()
	end
end

-- the key bindings' names (the client's key binding settings read them), in the language in force
local function Bindings()
	BINDING_HEADER_WUXIANKIT = L.BINDING_HEADER
	BINDING_NAME_WUXIANKIT_YES = L.BINDING_YES
	BINDING_NAME_WUXIANKIT_NO = L.BINDING_NO
end
Bindings()
ns.When("load", Bindings)                               -- the player's language is known from here
ns.OnChange(function(what)
	if what ~= "language" then return end
	Bindings()
	local choice = ns.LanguageChoice()
	for _, lang in ipairs(ns.LANGUAGES) do
		if lang[1] == choice then ns.Say(L.LANG_SET:format(lang[2] or L.LANG_AUTO_LONG)) end
	end
	UI.Refresh()
end)

function WuxianKit_Yes() SlashCmdList.WUXIANKIT("yes") end
function WuxianKit_No() SlashCmdList.WUXIANKIT("no") end
function WuxianKit_OnCompartment() UI.Toggle() end
