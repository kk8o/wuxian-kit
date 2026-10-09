-- The proposal window: the oldest proposal waiting for the player, its steps as their extensions preview them, who made
-- it, when it expires; Run, Decline, and Next when more wait. Run stays off before the proposal's `after` time and while a
-- step is not ready (chat lockdown...); in combat it says a Do waits for the end of it. When another proposal takes the
-- place of the one shown (it ran, was declined or expired), Run (and /wk yes) waits SETTLE seconds: a click meant for
-- the one before never runs one the player has not seen.
local _, ns = ...
local L, UI = ns.L, ns.UI
local S, C = UI.Skin, UI.Skin.C

local W, MAX_LINES, SETTLE = 400, 16, 1
local f                                 -- the frame, made the first time it shows
local shown                             -- the id it shows
local shownAt = 0                       -- GetTime() when another took the place of the one shown
local chosen                            -- the player picked it (Next): no wait

local function Line(text, color, indent)
	f.used = f.used + 1
	local fs = f.pool[f.used]
	if not fs then
		fs = S.Text(f)
		f.pool[f.used] = fs
	end
	fs:ClearAllPoints()
	fs:SetPoint("TOPLEFT", f, "TOPLEFT", 14 + (indent or 0), -f.y)
	fs:SetWidth(W - 28 - (indent or 0))
	S.Ink(fs, color or C.fg)
	fs:SetText(text)
	fs:Show()
	f.y = f.y + math.max(14, fs:GetStringHeight()) + 4
	return fs
end

local function Frame()
	if f then return f end
	f = S.Panel("WuxianKitProposal", W, 120, "proposal")
	f.pool, f.used = {}, 0
	f.run = S.Button(f, L.RUN, true, function() if shown and not UI.Settling() then ns.Act("run", shown) end end)
	f.decline = S.Button(f, L.DECLINE, false, function() if shown then ns.Act("decline", shown) end end)
	f.next = S.Button(f, L.NEXT, false, function()
		local list = ns.Waiting()
		for i, id in ipairs(list) do
			if id == shown then
				shown, chosen = list[i % #list + 1], true
				break
			end
		end
		UI.Refresh()
	end)
	f.run:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -14, 12)
	f.decline:SetPoint("RIGHT", f.run, "LEFT", -8, 0)
	f.next:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 14, 12)
	return f
end

local function Expiry(p)
	return ("%s · %s"):format(L.FROM:format(ns.SourceText(p.source)), L.EXPIRES:format(S.Clock(p.expires - time())))
end

-- the window drawn again for `shown` (hidden when nothing waits)
function UI.DrawProposal()
	local list = ns.Waiting()
	if #list == 0 then
		shown = nil
		if f then f:Hide() end
		return
	end
	local index, before = 1, shown
	for i, id in ipairs(list) do
		if id == shown then index = i end
	end
	shown = list[index]
	Frame()
	if f:IsShown() and before and before ~= shown and not chosen then shownAt = GetTime() end
	chosen = nil
	local p = ns.Get(shown)
	f.run.label:SetText(L.RUN)                    -- the words again: the language may have changed
	f.decline.label:SetText(L.DECLINE)
	f.next.label:SetText(L.NEXT)
	f.used, f.y = 0, 12
	Line(("%s · %s"):format(L.TITLE, L.PROPOSAL:format(p.id)) .. (#list > 1 and ("   " .. L.COUNT:format(index, #list)) or ""),
		C.gold)
	f.expiry = Line(Expiry(p), C.muted)
	if p.title then Line(p.title, C.fg) end
	local lines, total = 0, 0
	for _, s in ipairs(p.steps) do total = total + 1 + #s.preview end
	for _, s in ipairs(p.steps) do
		if lines >= MAX_LINES then break end
		Line(("[%s] %s"):format(L.KIND[s.cap.kind] or s.cap.kind, ns.T(s.cap.title)), C.gold)
		lines = lines + 1
		for _, text in ipairs(s.preview) do
			if lines >= MAX_LINES then break end
			Line(text, C.fg, 12)
			lines = lines + 1
		end
	end
	if total > lines then Line(L.STEP_MORE:format(total - lines), C.muted, 12) end
	local why, status = ns.Blocked(p), nil
	if why == "after" then
		status = L.WAIT_AFTER:format(p.after - time())
	elseif why then
		status = L.NOT_READY:format(ns.Text(why))
	elseif ns.NeedsPeace(p) and InCombatLockdown() then
		status = L.IN_COMBAT
	end
	f.status = status and Line(status, why and C.bad or C.sky) or nil
	for i = f.used + 1, #f.pool do f.pool[i]:Hide() end
	S.Enable(f.run, not why and GetTime() - shownAt >= SETTLE)   -- (UI.Settling, the frame shown)
	f.next:SetShown(#list > 1)
	f:SetHeight(f.y + 48)
	if not f:IsShown() then
		S.Place(f, "proposal", "TOP", 0, -140)
		f:Show()
	end
end

-- a new proposal waits: shown when nothing else is (the oldest stays in front)
function UI.Show(id)
	local p = shown and ns.Get(shown)
	if not p or p.state ~= "pending" then shown = id end
	UI.Refresh()
end

-- every second: the countdown, and Run as soon as the `after` time comes, a step gets ready (or stops being), or the
-- wait after a change of the one shown is over
function UI.TickProposal()
	if f and f:IsShown() then UI.DrawProposal() end
end

-- the proposal in front, for /wk yes, /wk no and the key bindings
function UI.Current()
	return shown
end

-- whether the wait after another proposal took the place of the one shown lasts (Run, /wk yes: not yet)
function UI.Settling()
	return f ~= nil and f:IsShown() and GetTime() - shownAt < SETTLE
end
