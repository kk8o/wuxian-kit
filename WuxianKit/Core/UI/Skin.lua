-- The core's look, 无限工坊's (a dark panel with a gold hairline; plain textures, none of the client's templates), and the
-- pieces both windows are made of: text, a movable panel that keeps its place, flat buttons, check boxes.
local _, ns = ...

local UI = {}
ns.UI = UI

local HEX = { panel = "23242a", panel2 = "2b2f37", line = "35363d", fg = "e8e4d8", muted = "9c9ea6", gold = "d8a85a",
	goldD = "8a6424", goldSoft = "3a3120", sky = "7fb3e0", skySoft = "323b47", ok = "6fcf97", bad = "f28b82",
	ink = "1b1c21" }
local C = {}
for k, hex in pairs(HEX) do
	C[k] = { tonumber(hex:sub(1, 2), 16) / 255, tonumber(hex:sub(3, 4), 16) / 255, tonumber(hex:sub(5, 6), 16) / 255, 1 }
end

local S = { C = C }
UI.Skin = S
ns.Kit.Skin = S                           -- the core's look for extensions that draw (Guide)

function S.Fill(t, c, a) t:SetColorTexture(c[1], c[2], c[3], a or c[4]) end
function S.Ink(fs, c) fs:SetTextColor(c[1], c[2], c[3], c[4]) end

-- a capsule: a short label on a fill with round ends (the client's own circle mask rounds them: no file of ours), in a
-- tone: "sys" grey, "custom" sky (as 无限工坊's App tags an extension). p.Set(text, tone) sizes it to its text
local PILL = { sys = { fill = "panel2", ink = "muted" }, custom = { fill = "skySoft", ink = "sky" } }
local MASK = "Interface\\Masks\\CircleMaskScalable"

function S.Pill(parent)
	local p = CreateFrame("Frame", nil, parent)
	p:SetHeight(16)
	p.parts = {}
	for i, side in ipairs({ "LEFT", "RIGHT" }) do               -- the round ends: a circle each, under the middle's edge
		local t = p:CreateTexture(nil, "BACKGROUND")
		t:SetSize(16, 16)
		t:SetPoint(side)
		if p.CreateMaskTexture and t.AddMaskTexture then
			local m = p:CreateMaskTexture()
			m:SetTexture(MASK, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
			m:SetAllPoints(t)
			t:AddMaskTexture(m)
		end
		p.parts[i] = t
	end
	p.parts[3] = p:CreateTexture(nil, "BACKGROUND")
	p.parts[3]:SetPoint("TOPLEFT", 8, 0)
	p.parts[3]:SetPoint("BOTTOMRIGHT", -8, 0)
	p.text = p:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	p.text:SetPoint("CENTER", 0, 0)
	function p.Set(text, tone)
		local look = PILL[tone] or PILL.sys
		p.text:SetText(text)
		S.Ink(p.text, C[look.ink])
		for _, t in ipairs(p.parts) do S.Fill(t, C[look.fill]) end
		p:SetWidth(math.ceil(p.text:GetStringWidth()) + 18)
	end
	return p
end

function S.Text(parent, color, small)
	local fs = parent:CreateFontString(nil, "OVERLAY", small and "GameFontHighlightSmall" or "GameFontNormal")
	fs:SetJustifyH("LEFT")
	fs:SetWordWrap(true)
	S.Ink(fs, color or C.fg)
	return fs
end

-- a dark panel with a hairline round it, movable by dragging; its place kept in WuxianKitDB.pos[key]
function S.Panel(name, w, h, key)
	local f = CreateFrame("Frame", name, UIParent)
	f:SetSize(w, h)
	f:SetFrameStrata("DIALOG")
	f:SetToplevel(true)
	f:SetClampedToScreen(true)
	f:EnableMouse(true)
	f:SetMovable(true)
	f:RegisterForDrag("LeftButton")
	f:SetScript("OnDragStart", f.StartMoving)
	f:SetScript("OnDragStop", function(self)
		self:StopMovingOrSizing()
		if ns.db then
			ns.db.pos = type(ns.db.pos) == "table" and ns.db.pos or {}
			ns.db.pos[key] = { self:GetLeft(), self:GetTop() }
		end
	end)
	local bg = f:CreateTexture(nil, "BACKGROUND")
	bg:SetAllPoints()
	S.Fill(bg, C.panel, 0.96)
	for _, e in ipairs({ { "TOPLEFT", "TOPRIGHT", nil, 1 }, { "BOTTOMLEFT", "BOTTOMRIGHT", nil, 1 },
		{ "TOPLEFT", "BOTTOMLEFT", 1 }, { "TOPRIGHT", "BOTTOMRIGHT", 1 } }) do
		local t = f:CreateTexture(nil, "BORDER")
		t:SetPoint(e[1])
		t:SetPoint(e[2])
		if e[3] then t:SetWidth(e[3]) else t:SetHeight(e[4]) end
		S.Fill(t, C.goldD)
	end
	f:Hide()
	return f
end

-- puts a panel where the player left it, else at (point, x, y) of the screen
function S.Place(f, key, point, x, y)
	local pos = ns.db and type(ns.db.pos) == "table" and ns.db.pos[key]
	f:ClearAllPoints()
	if pos and pos[1] and pos[2] then
		f:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", pos[1], pos[2])
	else
		f:SetPoint(point, UIParent, point, x, y)
	end
end

-- a flat button: gold when it is the one to press, quiet otherwise, tinted under the mouse; onClick(self)
function S.Button(parent, label, primary, onClick)
	local b = CreateFrame("Button", nil, parent)
	b:SetSize(86, 24)
	b.bg = b:CreateTexture(nil, "BACKGROUND")
	b.bg:SetAllPoints()
	b.label = S.Text(b, primary and C.ink or C.fg)
	b.label:SetPoint("CENTER")
	b.label:SetJustifyH("CENTER")
	b.label:SetText(label)
	b:SetFontString(b.label)
	b.primary = primary
	function b.Look(hover)
		if not b:IsEnabled() then
			S.Fill(b.bg, C.line)
			S.Ink(b.label, C.muted)
		elseif b.primary then
			S.Fill(b.bg, hover and C.goldD or C.gold)
			S.Ink(b.label, hover and C.fg or C.ink)
		else
			S.Fill(b.bg, hover and C.goldSoft or C.panel2)
			S.Ink(b.label, C.fg)
		end
	end
	b:SetScript("OnEnter", function() b.Look(true) end)
	b:SetScript("OnLeave", function() b.Look(false) end)
	b:SetScript("OnClick", onClick)
	b.Look(false)
	return b
end

function S.Enable(b, on)
	b:SetEnabled(on and true or false)
	b.Look(false)
end

-- a check box with its label; onClick(self, checked)
function S.Check(parent, onClick)
	local c = CreateFrame("CheckButton", nil, parent)
	c:SetSize(16, 16)
	c.bg = c:CreateTexture(nil, "BACKGROUND")
	c.bg:SetAllPoints()
	S.Fill(c.bg, C.panel2)
	c.mark = c:CreateTexture(nil, "ARTWORK")
	c.mark:SetPoint("CENTER")
	c.mark:SetSize(8, 8)
	S.Fill(c.mark, C.gold)
	c.label = S.Text(c, C.fg)
	c.label:SetPoint("LEFT", c, "RIGHT", 6, 0)
	function c.Set(on)
		c:SetChecked(on and true or false)
		c.mark:SetShown(on and true or false)
	end
	c:SetScript("OnClick", function(self)
		local on = self:GetChecked() and true or false
		self.mark:SetShown(on)
		onClick(self, on)
	end)
	return c
end

-- a one-line text box; commit(self, text) on Enter, or when it loses focus with its text changed; Escape puts back
-- what it had
function S.Edit(parent, commit)
	local e = CreateFrame("EditBox", nil, parent)
	e:SetSize(200, 22)
	e:SetAutoFocus(false)
	e:SetFontObject("ChatFontNormal")
	e:SetTextInsets(6, 6, 0, 0)
	e.bg = e:CreateTexture(nil, "BACKGROUND")
	e.bg:SetAllPoints()
	S.Fill(e.bg, C.panel2)
	e:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
	e:SetScript("OnEscapePressed", function(self)
		self:SetText(self.kept or "")
		self:ClearFocus()
	end)
	e:SetScript("OnEditFocusLost", function(self)
		local text = self:GetText() or ""
		if text ~= self.kept then
			self.kept = text
			commit(self, text)
		end
	end)
	return e
end

function S.Clock(seconds)
	seconds = math.max(0, math.floor(seconds))
	return ("%d:%02d"):format(math.floor(seconds / 60), seconds % 60)
end
