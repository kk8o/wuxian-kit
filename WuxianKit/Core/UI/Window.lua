-- The core's window (/wk, the addon compartment): the extensions on the left, the selected one's page on the right, made
-- from what it declared (no extension writes window code): its state and the switch to turn it on or off, its running
-- feeds with a stop button, its own status line and buttons, its options (the player's choices, made only here), its
-- scopes to tick "without asking", and what it can do,
-- a line of titles for each kind. The core's own page lists, instead of what it can do (that is the agent's), what has
-- not run yet, to stop, and what ran, to undo. A page longer than the window scrolls with the mouse wheel. One window:
-- nothing else is spread over the screen.
local _, ns = ...
local Kit, L, UI = ns.Kit, ns.L, ns.UI
local S, C = UI.Skin, UI.Skin.C

local W, H, LEFT = 640, 470, 176
local BODY, ROW = H - 66, 19              -- the page's height; a line's (Put: 14 and 5 between)
local HISTORY_SHOWN = 8
local KIND_ORDER = { "see", "say", "do", "keep", "point" }
local f                                   -- the frame, made the first time it opens
local selected = "kit"

------------------------------------------------------------------------------------------------------------------------
-- the page's pieces, from pools

-- a line of text (single: cut to one line, "..." at the end)
local function Put(x, color, text, width, single)
	f.nText = f.nText + 1
	local fs = f.texts[f.nText]
	if not fs then
		fs = S.Text(f.body)
		f.texts[f.nText] = fs
	end
	fs:ClearAllPoints()
	fs:SetPoint("TOPLEFT", f.body, "TOPLEFT", x, -f.y)
	fs:SetWidth(width or (W - LEFT - 40 - x))
	fs:SetWordWrap(not single)
	S.Ink(fs, color)
	fs:SetText(text)
	fs:Show()
	f.y = f.y + math.max(14, fs:GetStringHeight()) + 5
	return fs
end

local function PutCheck(x, label, on, onClick)
	f.nCheck = f.nCheck + 1
	local c = f.checks[f.nCheck]
	if not c then
		c = S.Check(f.body, function(self, checked) if self.onClick then self.onClick(checked) end end)
		f.checks[f.nCheck] = c
	end
	c:ClearAllPoints()
	c:SetPoint("TOPLEFT", f.body, "TOPLEFT", x, -f.y)
	c.label:SetWidth(W - LEFT - 70 - x)                   -- one line, cut with "..." at the page's edge
	c.label:SetWordWrap(false)
	c.label:SetText(label)
	c.Set(on)
	c.onClick = onClick
	c:Show()
	f.y = f.y + 22
	return c
end

local function PutEdit(x, text, onCommit)
	f.nEdit = f.nEdit + 1
	local e = f.edits[f.nEdit]
	if not e then
		e = S.Edit(f.body, function(self, value) if self.onCommit then self.onCommit(value) end end)
		f.edits[f.nEdit] = e
	end
	e:ClearAllPoints()
	e:SetPoint("TOPLEFT", f.body, "TOPLEFT", x, -f.y)
	e:SetWidth(W - LEFT - 60 - x)
	e.onCommit = onCommit
	if not e:HasFocus() then
		e.kept = text
		e:SetText(text)
	end
	e:Show()
	f.y = f.y + 28
	return e
end

local function PutButton(x, y, label, primary, onClick, w)
	f.nButton = f.nButton + 1
	local b = f.buttons[f.nButton]
	if not b then
		b = S.Button(f.body, label, primary, function(self) if self.onClick then self.onClick() end end)
		f.buttons[f.nButton] = b
	end
	b.label:SetText(label)
	b.primary, b.onClick = primary, onClick
	b:SetSize(w or 86, 22)
	b:ClearAllPoints()
	b:SetPoint("TOPLEFT", f.body, "TOPLEFT", x, -y)
	S.Enable(b, true)
	b:Show()
	return b
end

local function Heading(text)
	f.y = f.y + 6
	Put(0, C.gold, text)
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

local function Page(e)
	local ext = ns.extensions[e.id]
	Put(0, C.fg, ("%s  |cff9c9ea6%s · %s%s|r"):format(e.title or e.id, L.VERSION:format(e.version or "?"), StateText(e),
		e.builtin and not e.core and (" · " .. L.BUILTIN) or ""))
	if not e.core and e.state ~= "disabled" and e.state ~= "missing" then
		PutCheck(0, L.ENABLED, e.state == "on", function(on) ns.Act("switch", e.id, on) end)
	end
	if e.core then                                          -- the core: the language, the chosen one marked
		local y = f.y + 4
		f.y = y
		Put(0, C.fg, L.LANGUAGE, 70)
		local choice = ns.LanguageChoice()
		for i, lang in ipairs(ns.LANGUAGES) do
			PutButton(76 + (i - 1) * 84, y - 3, lang[2] or L.LANG_AUTO, lang[1] == choice,
				function() ns.Act("language", lang[1]) end, 78)
		end
		f.y = y + 26
	end
	if ext and ext.active then
		for _, name in ipairs(ext.feedOrder) do                -- a running feed: what it hears, until when, and a stop
			local feed = ext.feeds[name]
			local s = ns.FeedState(feed)
			if s then
				local y = f.y
				Put(0, C.sky, L.FEED_ON:format(ns.T(feed.spec.title) or name, ns.FeedText(feed, s), date("%H:%M", s.ends)),
					W - LEFT - 150)
				PutButton(W - LEFT - 128, y - 2, L.STOP, false, function() ns.Act("feed.stop", e.id, name) end, 70)
			end
		end
		if ext.status then
			local ok, line = pcall(ext.status, ext)
			if ok and line then Put(0, C.sky, ns.Text(line)) end
		end
		if ext.buttons then
			local y = f.y
			for i, b in ipairs(ext.buttons) do
				PutButton((i - 1) * 96, y, ns.T(b.label), false, function() ns.Act("button", e.id, i) end)
			end
			f.y = y + 30
		end
	end
	if ext and #ext.optionOrder > 0 then                    -- the player's choices for it, made here and only here
		Heading(L.OPTIONS)
		for _, name in ipairs(ext.optionOrder) do
			local o = ext.options[name]
			if o.kind == "text" then
				Put(0, C.fg, ns.T(o.title))
				PutEdit(0, ext:Get(name) or "", function(value) ns.Act("option", e.id, name, value) end)
				if o.hint then Put(0, C.muted, ns.T(o.hint)) end
			else
				PutCheck(0, ns.T(o.title), ext:Get(name), function(on) ns.Act("option", e.id, name, on) end)
			end
		end
	end
	if e.core then                                          -- the core: what has not run yet, a stop for each
		local open = ns.Open()
		if #open > 0 then
			Heading(L.OPEN)
			for _, id in ipairs(open) do
				local p = ns.Get(id)
				local y = f.y
				Put(0, C.fg, ("#%d  |cff7fb3e0%s|r  %s"):format(p.id, L.OPEN_STATE[p.state] or p.state,
					p.title or p.steps[1].preview[1] or ""), W - LEFT - 150, true)
				PutButton(W - LEFT - 128, y - 2, p.state == "pending" and L.DECLINE or L.CANCEL, false,
					function() ns.Act("decline", id) end, 70)
			end
		end
	end
	if ext and #ext.scopeOrder > 0 then
		Heading(L.PERMISSIONS)
		Put(0, C.muted, L.PERMISSIONS_HINT)
		local grants = ns.Grants()
		for _, scope in ipairs(ext.scopeOrder) do
			PutCheck(0, ns.T(ext.scopes[scope]), grants[scope], function(on) ns.Act("grant", scope, on) end)
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
			local y = f.y
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
	f.scroll:SetScrollChild(f.body)
	f.more = S.Text(f, C.muted, true)
	f.more:SetPoint("TOPRIGHT", -40, -34)
	f.more:SetText(L.SCROLL)
	f.texts, f.checks, f.buttons, f.edits = {}, {}, {}, {}
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
		b:SetPoint("TOPLEFT", 0, -(i - 1) * 24)
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
	f.agent:SetText(Kit:AgentOnline() and L.AGENT_ON or L.AGENT_OFF)
	local list = ns.ExtensionList()
	local current
	for i, e in ipairs(list) do
		local b = Item(i)
		b.id = e.id
		b.label:SetText(e.title or e.id)
		S.Fill(b.bg, e.id == selected and C.goldSoft or C.panel2)
		S.Ink(b.label, e.state == "on" and C.fg or C.muted)
		b:Show()
		if e.id == selected then current = e end
	end
	for i = #list + 1, #f.items do f.items[i]:Hide() end
	if not current then selected, current = "kit", list[1] end
	f.nText, f.nCheck, f.nButton, f.nEdit, f.y = 0, 0, 0, 0, 0
	Page(current)
	f.range = math.max(0, f.y + 8 - BODY)                  -- how far the page scrolls
	f.body:SetHeight(BODY + f.range)
	if f.scroll:GetVerticalScroll() > f.range then f.scroll:SetVerticalScroll(f.range) end
	f.more:SetShown(f.range > 0)
	for i = f.nText + 1, #f.texts do f.texts[i]:Hide() end
	for i = f.nCheck + 1, #f.checks do f.checks[i]:Hide() end
	for i = f.nButton + 1, #f.buttons do f.buttons[i]:Hide() end
	for i = f.nEdit + 1, #f.edits do f.edits[i]:Hide() end
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
end

function UI.Tick()
	UI.TickProposal()
	if f and f:IsShown() then f.agent:SetText(Kit:AgentOnline() and L.AGENT_ON or L.AGENT_OFF) end
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
