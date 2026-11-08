-- The core's window (/wk, the addon compartment): the extensions on the left, the selected one's page on the right, made
-- from what it declared (no extension writes window code): its state and the switch to turn it on or off, its running
-- feeds with a stop button and when the agent last answered, its own status line and buttons ("connect an agent" when
-- it names a prompt: the copy box, Copy.lua), its options (the player's choices, made only here or in an OptionsPanel),
-- its scopes to tick "without asking", each ticked one with its budget (a button that goes through the usual ones), and
-- what it can do, a line of titles for each kind. The core's own page lists, instead of what it can do (that is the
-- agent's), what has not run yet, to stop, and what ran, to undo. A page longer than the window scrolls with the mouse
-- wheel. One window: nothing else is spread over the screen.
-- WuxianKit:OptionsPanel(id, parent, width) draws an extension's options in another addon's window with the same
-- controls; both change the same values (the "option" action) and both redraw when one changes.
local _, ns = ...
local Kit, L, UI = ns.Kit, ns.L, ns.UI
local S, C = UI.Skin, UI.Skin.C

local W, H, LEFT = 640, 470, 176
local BODY, ROW = H - 66, 19              -- the page's height; a line's (Put: 14 and 5 between)
local HISTORY_SHOWN = 8
local KIND_ORDER = { "see", "say", "do", "keep", "point" }
local NUMBER_W = 80                       -- a number option's box
local f                                   -- the frame, made the first time it opens
local selected = "kit"
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

local function PutEdit(x, text, onCommit, width)
	cv.nEdit = cv.nEdit + 1
	local e = cv.edits[cv.nEdit]
	if not e then
		e = S.Edit(cv.body, function(self, value) if self.onCommit then self.onCommit(value) end end)
		cv.edits[cv.nEdit] = e
	end
	e:ClearAllPoints()
	e:SetPoint("TOPLEFT", cv.body, "TOPLEFT", x, -cv.y)
	e:SetWidth(width or (cv.width - 32 - x))
	e.onCommit = onCommit
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

-- drawing a canvas: Begin, its pieces, Finish (what it did not use of its pools hidden)
local function Begin(c)
	cv = c
	c.nText, c.nCheck, c.nButton, c.nEdit, c.y = 0, 0, 0, 0, 0
end

local function Finish(c)
	for i = c.nText + 1, #c.texts do c.texts[i]:Hide() end
	for i = c.nCheck + 1, #c.checks do c.checks[i]:Hide() end
	for i = c.nButton + 1, #c.buttons do c.buttons[i]:Hide() end
	for i = c.nEdit + 1, #c.edits do c.edits[i]:Hide() end
end

------------------------------------------------------------------------------------------------------------------------
-- options, on the window's page and in an OptionsPanel

local function ValueText(o, v)
	if o.kind == "list" then return table.concat(type(v) == "table" and v or {}, L.SEP) end
	return v == nil and "" or tostring(v)
end

-- each option of ext with its control: a check box, a text box, a number box and its unit, a row of buttons (the
-- chosen one gold), a text box of items; a change is the "option" action, as the window's always were
local function Options(ext)
	local id = ext.id
	for _, name in ipairs(ext.optionOrder) do
		local o = ext.options[name]
		local value = ext:Get(name)
		local function Set(v) ns.Act("option", id, name, v) end
		if o.kind == "boolean" then
			PutCheck(0, ns.T(o.title), value, Set)
		else
			Put(0, C.fg, ns.T(o.title))
			if o.kind == "number" then
				local y = cv.y
				PutEdit(0, ValueText(o, value), Set, NUMBER_W)
				if o.unit ~= nil then
					local after = cv.y
					cv.y = y + 4
					Put(NUMBER_W + 8, C.muted, ns.T(o.unit), cv.width - 20 - NUMBER_W, true)
					cv.y = after
				end
			elseif o.kind == "choice" then
				local y, x = cv.y, 0
				for _, c in ipairs(o.choices) do
					local b = PutButton(x, y, ns.T(c.label), c.value == value, function() Set(c.value) end)
					local w = Fit(b, 48)
					if x > 0 and x + w > cv.width - 12 then          -- no room left on this row: the next
						x, y = 0, y + 28
						b:ClearAllPoints()
						b:SetPoint("TOPLEFT", cv.body, "TOPLEFT", x, -y)
					end
					b:SetWidth(w)
					x = x + w + 6
				end
				cv.y = y + 28
			else                                                   -- text, list
				PutEdit(0, ValueText(o, value), Set)
				if o.kind == "list" then Put(0, C.muted, L.OPTION_LIST_HINT) end
			end
		end
		if o.hint then Put(0, C.muted, ns.T(o.hint)) end
	end
end

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

-- under a running feed: when the agent last called the extension, how often the feed woke it (ns.FeedInfo, else what
-- the feed's state keeps)
local function FeedLine(feed, s)
	local info
	if ns.FeedInfo then
		local ok, got = pcall(ns.FeedInfo, feed)
		info = ok and type(got) == "table" and got or nil
	end
	info = info or s
	local seen, wakes = tonumber(info.seen), tonumber(info.wakes)
	local text = seen and L.FEED_SEEN:format(S.Duration(time() - seen)) or L.FEED_UNSEEN
	if wakes and wakes > 0 then text = text .. " · " .. L.FEED_WAKES:format(wakes) end
	return text
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

-- the copy box with the command that starts the extension's prompt in Claude Code
local function Connect(ext)
	Kit:Copy(("/mcp__wuxian__%s"):format(ext.prompt), { title = L.CONNECT, hint = L.CONNECT_HINT:format(ns.Escape(ext.prompt)) })
end

local function Page(e)
	local ext = ns.extensions[e.id]
	local title = Put(0, C.fg, e.title or e.id, W - LEFT - 160, true)  -- the title, its kind as a capsule after it
	f.pill.Set(e.builtin and L.GROUP.sys or L.GROUP.custom, e.builtin and "sys" or "custom")
	f.pill:ClearAllPoints()
	f.pill:SetPoint("LEFT", title, "LEFT", math.min(math.ceil(title:GetStringWidth()), W - LEFT - 160) + 8, 0)
	f.pill:Show()
	Put(0, C.muted, ("%s · %s%s"):format(L.VERSION:format(e.version or "?"), StateText(e),
		not e.builtin and e.addon and (" · " .. e.addon) or ""))
	if not e.core and e.state ~= "disabled" and e.state ~= "missing" then
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
	end
	if ext and ext.active then
		for _, name in ipairs(ext.feedOrder) do                -- a running feed: what it hears, until when, and a stop
			local feed = ext.feeds[name]
			local s = ns.FeedState(feed)
			if s then
				local y = cv.y
				Put(0, C.sky, L.FEED_ON:format(ns.T(feed.spec.title) or name, ns.FeedText(feed, s), date("%H:%M", s.ends)),
					W - LEFT - 150)
				PutButton(W - LEFT - 128, y - 2, L.STOP, false, function() ns.Act("feed.stop", e.id, name) end, 70)
				Put(0, C.muted, FeedLine(feed, s), W - LEFT - 150)
			end
		end
		if ext.status then
			local ok, line = pcall(ext.status, ext)
			if ok and line then Put(0, C.sky, ns.Text(line)) end
		end
		if ext.buttons or ext.prompt then                     -- its buttons, then "connect an agent"
			local y, x = cv.y, 0
			for i, b in ipairs(ext.buttons or {}) do
				PutButton(x, y, ns.T(b.label), false, function() ns.Act("button", e.id, i) end)
				x = x + 96
			end
			if ext.prompt then
				local b = PutButton(x, y, L.CONNECT, false, function() Connect(ext) end)
				b:SetWidth(Fit(b, 86))
			end
			cv.y = y + 30
		end
	end
	if ext and #ext.optionOrder > 0 then                    -- the player's choices for it, made here and only here
		Heading(L.OPTIONS)
		Options(ext)
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
	if not e.core then return Capabilities(ext) end
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
	f.list = CreateFrame("Frame", nil, f)
	f.list:SetPoint("TOPLEFT", 10, -56)
	f.list:SetSize(LEFT - 10, H - 66)
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
	f.pill = S.Pill(f.body)
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
		b.label = S.Text(b, C.fg)
		b.label:SetPoint("LEFT", 8, 0)
		b.label:SetWidth(LEFT - 30)
		b.label:SetWordWrap(false)                          -- a long title: one line, cut with "..."
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
	local list = ns.ExtensionList()
	local groups = { { kind = "sys", list = {} }, { kind = "custom", list = {} } }   -- WuxianKit's own, then other addons'
	for _, e in ipairs(list) do table.insert(groups[e.builtin and 1 or 2].list, e) end
	local current, n, nHead, y = nil, 0, 0, 0
	for _, g in ipairs(groups) do
		if #g.list > 0 then
			nHead = nHead + 1
			local h = f.heads[nHead] or S.Text(f.list, C.muted, true)
			f.heads[nHead] = h
			h:ClearAllPoints()
			h:SetPoint("TOPLEFT", f.list, "TOPLEFT", 8, -y - 3)
			h:SetText(L.GROUP[g.kind])
			h:Show()
			y = y + 20
			for _, e in ipairs(g.list) do
				n = n + 1
				local b = Item(n)
				b:ClearAllPoints()
				b:SetPoint("TOPLEFT", 0, -y)
				b.id = e.id
				b.label:SetText(e.title or e.id)
				S.Fill(b.bg, e.id == selected and C.goldSoft or C.panel2)
				S.Ink(b.label, e.state == "on" and C.fg or C.muted)
				b:Show()
				if e.id == selected then current = e end
				y = y + 24
			end
			y = y + 8
		end
	end
	for i = n + 1, #f.items do f.items[i]:Hide() end
	for i = nHead + 1, #f.heads do f.heads[i]:Hide() end
	if not current then selected, current = "kit", list[1] end
	Begin(f)
	Page(current)
	f.range = math.max(0, f.y + 8 - BODY)                  -- how far the page scrolls
	f.body:SetHeight(BODY + f.range)
	if f.scroll:GetVerticalScroll() > f.range then f.scroll:SetVerticalScroll(f.range) end
	f.more:SetShown(f.range > 0)
	Finish(f)
end

------------------------------------------------------------------------------------------------------------------------
-- WuxianKit:OptionsPanel(id, parent, width): extension id's options in another addon's window

local panels = setmetatable({}, { __mode = "k" })       -- every panel made, to redraw when an option changes

local function DrawPanel(p)
	if not ns.extensions[p.ext.id] then return end
	Begin(p)
	Options(p.ext)
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

-- WuxianKit:Window(page): the window, open and in front, on an extension's page ("tune", "chat" ...; "kit" the core's);
-- without one, or with one not there, on the page it showed last. For other addons' buttons (WoWBridge's panel, its
-- minimap button)
function Kit:Window(page)
	Frame()
	if type(page) == "string" and ns.extensions[page] and page ~= selected then
		selected = page
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
		if p:IsVisible() then DrawPanel(p) end
	end
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
ns.AddAction("feed.stop", function(id, name)
	local ext = ns.extensions[id]
	local feed = ext and ext.feeds[name]
	if feed then ns.FeedStop(feed) end
	UI.Refresh()
	return feed ~= nil
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

SLASH_WUXIANKIT1 = "/wk"
SlashCmdList.WUXIANKIT = function(msg)
	local cmd, rest = (msg or ""):match("^%s*(%S*)%s*(.-)%s*$")
	cmd = cmd:lower()
	local command = ns.Commands()[cmd]
	if cmd == "yes" or cmd == "no" then                     -- the one numbered, the one shown, or the oldest
		local yes = cmd == "yes"
		local id = tonumber(rest:match("^(%d+)"))
		if yes and not id and UI.Settling() then return end -- another just took the place of the one shown: not yet
		id = id or UI.Current() or (yes and ns.Waiting() or ns.Open())[1]
		if not id then return ns.Say(yes and L.NONE_PENDING or L.NONE_OPEN) end
		local p = ns.Get(id)
		if not (p and (p.state == "pending" or not yes and (p.state == "waiting" or p.state == "queued"))) then
			return ns.Say(L.NOT_OPEN:format(id))
		end
		ns.Act(yes and "run" or "decline", id)
	elseif cmd == "lang" then
		local want = ({ auto = "auto", zh = "zhCN", zhcn = "zhCN", en = "enUS", enus = "enUS" })[rest:lower()]
		if not want then return ns.Say(L.LANG_USAGE) end
		ns.Act("language", want)
	elseif cmd == "help" then
		ns.Say(L.HELP)
		local words = {}
		for word, c in pairs(ns.Commands()) do
			if c.ext.active and c.help then words[#words + 1] = word end
		end
		table.sort(words)
		for _, word in ipairs(words) do ns.Say(L.HELP_COMMAND:format(word, ns.T(ns.Commands()[word].help))) end
	elseif command and command.ext.active then             -- an extension's own: /wk <word> ...
		ns.Safe(command.fn, command.ext, rest)
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
