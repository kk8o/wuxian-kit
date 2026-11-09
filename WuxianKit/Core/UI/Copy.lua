-- The copy box: WuxianKit:Copy(text, { title, hint, how, done }) shows text in a read-only box, selected, the keyboard
-- in it, for the player to copy with Ctrl+C (this client does not let addons write the clipboard: CopyToClipboard is
-- restricted). Ctrl+C says so and the box goes a moment later (the client copies first), then done(); Esc, Enter and
-- the close button close it.
-- One box: a new text takes the place of the one shown (whose done is not called).
local _, ns = ...
local Kit, L, UI = ns.Kit, ns.L, ns.UI
local S, C = UI.Skin, UI.Skin.C

local W = 440
local GONE = 0.3                          -- seconds between Ctrl+C and the box going
local f                                   -- the frame, made the first time
local shown                               -- { text, done, copied }: what the box shows now

local function Copied()
	local now = shown
	if not now or now.copied then return end
	now.copied = true
	f.status:SetText(L.COPIED)
	S.Ink(f.status, C.ok)
	C_Timer.After(GONE, function()
		if shown ~= now then return end                       -- another text took its place meanwhile
		f:Hide()
		if now.done then ns.Safe(now.done) end
	end)
end

local function Frame()
	if f then return f end
	f = S.Panel("WuxianKitCopyWindow", W, 120, "copy")
	tinsert(UISpecialFrames, "WuxianKitCopyWindow")         -- Esc closes it
	f.title = S.Text(f, C.gold)
	f.title:SetPoint("TOPLEFT", 14, -12)
	f.title:SetWidth(W - 60)
	f.title:SetWordWrap(false)
	f.close = S.Button(f, "×", false, function() f:Hide() end)
	f.close:SetSize(24, 24)
	f.close:SetPoint("TOPRIGHT", -8, -8)
	f.edit = S.Edit(f, function() end)
	f.edit:SetPoint("TOPLEFT", 14, -42)
	f.edit:SetWidth(W - 28)
	f.edit:SetMaxLetters(0)
	f.edit:SetScript("OnTextChanged", function(self, user)  -- read only: what was typed goes, the text stays selected
		if user then
			self:SetText(shown and shown.text or "")
			self:HighlightText()
		end
	end)
	f.edit:SetScript("OnEditFocusGained", function(self) self:HighlightText() end)
	f.edit:SetScript("OnMouseUp", function(self) self:HighlightText() end)
	f.edit:SetScript("OnEnterPressed", function() f:Hide() end)
	f.edit:SetScript("OnEscapePressed", function() f:Hide() end)
	f.edit:SetScript("OnKeyDown", function(_, key)
		if key == "C" and IsControlKeyDown and IsControlKeyDown() then Copied() end
	end)
	f.hint = S.Text(f, C.fg, true)
	f.hint:SetWidth(W - 28)
	f.status = S.Text(f, C.muted, true)
	f.status:SetWidth(W - 28)
	f:SetScript("OnHide", function()
		if f.edit:HasFocus() then f.edit:ClearFocus() end
	end)
	return f
end

-- WuxianKit:Copy(text, opts): the box with text selected; opts.title above it, opts.hint under it, opts.how the last
-- line until it is copied (default "Ctrl+C 复制"), opts.done() after the player copied it. true
function Kit:Copy(text, opts)
	opts = type(opts) == "table" and opts or {}
	Frame()
	shown = { text = ns.Text(text == nil and "" or text), done = type(opts.done) == "function" and opts.done or nil }
	f.title:SetText(opts.title ~= nil and ns.T(opts.title) or "")
	f.edit.kept = shown.text
	f.edit:SetText(shown.text)
	local y = 42 + 22 + 8
	f.hint:ClearAllPoints()
	f.hint:SetPoint("TOPLEFT", 14, -y)
	if opts.hint ~= nil then
		f.hint:SetText(ns.T(opts.hint))
		f.hint:Show()
		y = y + math.max(12, f.hint:GetStringHeight()) + 6
	else
		f.hint:SetText("")
		f.hint:Hide()
	end
	f.status:ClearAllPoints()
	f.status:SetPoint("TOPLEFT", 14, -y)
	f.status:SetText(opts.how ~= nil and ns.T(opts.how) or L.COPY_HINT)
	S.Ink(f.status, C.muted)
	f:SetHeight(y + math.max(12, f.status:GetStringHeight()) + 14)
	if not f:IsShown() then
		S.Place(f, "copy", "CENTER", 0, 120)
		f:Show()
	end
	f:Raise()
	f.edit:SetFocus()
	f.edit:HighlightText()
	return true
end
