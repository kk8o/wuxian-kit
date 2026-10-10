-- 指引 (Guide): points at something for the player to do, and changes nothing in the game (Point): guide.highlight (a
-- glowing frame round a part of the UI, a note under it), guide.note (a note by a frame or mid-screen), guide.waypoint
-- (the map's pin, with its arrow; it takes the place of a pin the player had), guide.tour (notes one after another, the
-- player clicks Next; the event guide.tour says where it is), guide.clear (and the pin it put, while it is still that
-- one). A frame is named by its global name
-- (CharacterMicroButton) or a path from one (PlayerFrame.healthbar); a forbidden one is refused. What is protected
-- (casting, using an item, placing an action) an addon cannot do: the agent points at it here, and the player does it.
-- Highlights and notes go after `seconds` (30, at most 600), a tour when it ends or is closed.
local Kit = WuxianKit
local S, C = Kit.Skin, Kit.Skin.C

local L = Kit:Words {
	zhCN = { TITLE = "指引", HIGHLIGHT = "高亮界面元素", NOTE = "显示说明", WAYPOINT = "设置地图路标",
		TOUR = "分步指引", CLEAR = "清除指引", OK = "关闭", NEXT = "下一步", DONE = "完成", STEP = "%d/%d",
		TOURING = "指引中：%s（%d/%d）" },
	enUS = { TITLE = "Guide", HIGHLIGHT = "Highlight UI element", NOTE = "Show note", WAYPOINT = "Set map waypoint",
		TOUR = "Step-by-step guide", CLEAR = "Clear guide", OK = "Close", NEXT = "Next", DONE = "Done", STEP = "%d/%d",
		TOURING = "Guide: %s (%d/%d)" },
}

local Clear                                -- below: everything the guide shows, put away

local guide = Kit:Extension("guide", { title = L"TITLE", version = Kit.VERSION, docs = "Extensions/Guide", teardown = function() Clear() end })

local SECONDS, MOST, PAD = 30, 600, 3
local marks, note, tour = {}, nil, nil     -- the highlight frames (a pool), the note frame, the tour going on
local pinned                              -- the map pin the guide put: { map, x, y } (0-1)

local function Seconds(s) return math.max(1, math.min(tonumber(s) or SECONDS, MOST)) end

-- the agent's words as the guide shows them: | doubled (no color, texture or link of theirs takes effect), lines kept
local function Clean(s) return s and (tostring(s):gsub("|", "||")) or nil end

-- a frame by its global name or a path from one, or nil and why
local function Target(path)
	local obj
	for part in path:gmatch("[^%.]+") do
		if obj == nil then obj = _G[part] elseif type(obj) == "table" then obj = obj[part] else obj = nil end
		if obj == nil then break end
	end
	if type(obj) ~= "table" or type(obj.GetObjectType) ~= "function" then
		return nil, ("no frame %s (a global name, or a path from one)"):format(path)
	end
	if obj.IsForbidden and obj:IsForbidden() then return nil, ("%s is forbidden to addons"):format(path) end
	return obj
end

-- whether a frame sits near the bottom of the screen (its note goes above it then); a position that is secret (a frame
-- anchored to a secret one) cannot be compared: below it, then
local function Low(target)
	local ok, bottom = pcall(target.GetBottom, target)
	if not ok or bottom == nil or (issecretvalue and issecretvalue(bottom)) then return false end
	return bottom < 160
end

------------------------------------------------------------------------------------------------------------------------
-- highlights

local function Pulse(self)
	local a = 0.8 + 0.2 * math.sin(GetTime() * 5)
	for _, t in ipairs(self.edges) do t:SetAlpha(a) end
	if self.ends and GetTime() > self.ends then self:Hide() end
end

local function Mark()
	for _, m in ipairs(marks) do
		if not m:IsShown() then return m end
	end
	local m = CreateFrame("Frame", nil, UIParent)
	m:SetFrameStrata("TOOLTIP")
	m.edges = {}
	for _, e in ipairs({ { "TOPLEFT", "TOPRIGHT", true }, { "BOTTOMLEFT", "BOTTOMRIGHT", true },
		{ "TOPLEFT", "BOTTOMLEFT", false }, { "TOPRIGHT", "BOTTOMRIGHT", false } }) do
		local t = m:CreateTexture(nil, "OVERLAY")
		t:SetPoint(e[1])
		t:SetPoint(e[2])
		if e[3] then t:SetHeight(3) else t:SetWidth(3) end
		S.Fill(t, C.gold)
		m.edges[#m.edges + 1] = t
	end
	m.box = CreateFrame("Frame", nil, m)
	m.box.bg = m.box:CreateTexture(nil, "BACKGROUND")
	m.box.bg:SetAllPoints()
	S.Fill(m.box.bg, C.panel, 0.92)
	m.text = S.Text(m.box, C.fg)
	m.text:SetPoint("CENTER")
	m:SetScript("OnUpdate", Pulse)
	marks[#marks + 1] = m
	return m
end

local function Highlight(target, text, seconds)
	local m = Mark()
	m:ClearAllPoints()
	m:SetPoint("TOPLEFT", target, "TOPLEFT", -PAD, PAD)
	m:SetPoint("BOTTOMRIGHT", target, "BOTTOMRIGHT", PAD, -PAD)
	m.text:SetWidth(0)                                    -- its own width first, then at most 304 and wrapped
	m.text:SetText(text or "")
	local w = math.min(304, m.text:GetStringWidth())
	m.text:SetWidth(math.max(1, w))
	m.box:ClearAllPoints()
	if Low(target) then m.box:SetPoint("BOTTOM", m, "TOP", 0, 6) else m.box:SetPoint("TOP", m, "BOTTOM", 0, -6) end
	m.box:SetSize(w + 16, m.text:GetStringHeight() + 10)
	m.box:SetShown(text ~= nil and text ~= "")
	m.ends = seconds and GetTime() + seconds or nil
	m:Show()
	return m
end

------------------------------------------------------------------------------------------------------------------------
-- the note, and tours on it

local Close, Next

local function Note()
	if note then return note end
	note = CreateFrame("Frame", "WuxianKitGuideNote", UIParent)
	note:SetFrameStrata("TOOLTIP")
	note:SetClampedToScreen(true)
	note:SetSize(320, 90)
	local bg = note:CreateTexture(nil, "BACKGROUND")
	bg:SetAllPoints()
	S.Fill(bg, C.panel, 0.96)
	note.title = S.Text(note, C.gold)
	note.title:SetPoint("TOPLEFT", 12, -10)
	note.title:SetWidth(296)                             -- one line, cut with "..."
	note.title:SetWordWrap(false)
	note.text = S.Text(note, C.fg)
	note.text:SetPoint("TOPLEFT", 12, -32)
	note.text:SetWidth(296)
	note.ok = S.Button(note, L.OK, false, function() Close() end)
	note.ok:SetPoint("BOTTOMRIGHT", -10, 10)
	note.next = S.Button(note, L.NEXT, true, function() Next() end)
	note.next:SetPoint("RIGHT", note.ok, "LEFT", -8, 0)
	note:SetScript("OnUpdate", function(self)
		if self.ends and GetTime() > self.ends then Close() end
	end)
	note:Hide()
	return note
end

local function Show(text, target, title, seconds, stepping)
	local n = Note()
	n.title:SetText(title or L.TITLE)
	n.text:SetText(text)
	n:SetHeight(math.max(90, n.text:GetStringHeight() + 72))
	n:ClearAllPoints()
	if not target then
		n:SetPoint("CENTER", UIParent, "CENTER", 0, 140)
	elseif Low(target) then
		n:SetPoint("BOTTOM", target, "TOP", 0, 32)
	else
		n:SetPoint("TOP", target, "BOTTOM", 0, -32)
	end
	n.ok.label:SetText(L.OK)                         -- in the language in force (it may have changed)
	n.next.label:SetText(L.NEXT)
	n.next:SetShown(stepping and true or false)
	n.ok:SetShown(true)
	n.ends = seconds and GetTime() + seconds or nil
	n:Show()
end

local function Step()
	local s = tour.steps[tour.at]
	for _, m in ipairs(marks) do m:Hide() end
	local target = s.frame and Target(s.frame) or nil
	if target then Highlight(target, nil, nil) end
	local last = tour.at == #tour.steps
	Show(s.text, target, ("%s · %s"):format(tour.title or L.TITLE, L.STEP:format(tour.at, #tour.steps)), nil, true)
	note.next.label:SetText(last and L.DONE or L.NEXT)
	guide:Emit("tour", { step = tour.at, of = #tour.steps, state = "shown" })
end

function Next()
	if not tour then return Close() end
	if tour.at < #tour.steps then
		tour.at = tour.at + 1
		return Step()
	end
	guide:Emit("tour", { step = tour.at, of = #tour.steps, state = "done" })
	tour = nil
	Clear()
end

function Close()
	if tour then guide:Emit("tour", { step = tour.at, of = #tour.steps, state = "closed" }) end
	tour = nil
	if note then note:Hide() end
	for _, m in ipairs(marks) do m:Hide() end
end

-- a tour going on ends as closed: another note or tour takes its place, or the guide goes off
local function Drop()
	if tour then guide:Emit("tour", { step = tour.at, of = #tour.steps, state = "closed" }) end
	tour = nil
end

function Clear()
	Drop()
	if note then note:Hide() end
	for _, m in ipairs(marks) do m:Hide() end
end

------------------------------------------------------------------------------------------------------------------------
-- what it can do

-- the pin goes with the guide only while it is the one the guide put
local function Unpin()
	local p = pinned and C_Map.GetUserWaypoint and C_Map.GetUserWaypoint()
	if p and p.uiMapID == pinned.map and p.position and math.abs(p.position.x - pinned.x) < 1e-4
		and math.abs(p.position.y - pinned.y) < 1e-4 then
		C_Map.ClearUserWaypoint()
	end
	pinned = nil
end

guide:Event("tour", { doc = "a tour's progress: a step shown, the tour done or closed",
	data = { step = "number", of = "number", state = "string" } })

guide:Point("highlight", { title = L"HIGHLIGHT", args = { frame = "string", text = "string?", seconds = "number?" },
	doc = "a glowing frame round a part of the UI (frame: its global name or a path from one, e.g. CharacterMicroButton, "
		.. "PlayerFrame.healthbar), text under it, for seconds (30, at most 600); answers {frame, shown}: shown = false, the "
		.. "frame is hidden (ask the player to open its window first)",
	run = function(_, a)
		local target, why = Target(a.frame)
		if not target then error(why, 0) end
		Highlight(target, Clean(a.text), Seconds(a.seconds))
		return { frame = a.frame, shown = target:IsVisible() and true or false }
	end })

guide:Point("note", { title = L"NOTE", args = { text = "string", frame = "string?", title = "string?", seconds = "number?" },
	doc = "a note for the player, under a frame (as for guide.highlight) or mid-screen, with a title; for seconds (30, at "
		.. "most 600) or until they click it away",
	run = function(_, a)
		local target
		if a.frame then
			local why
			target, why = Target(a.frame)
			if not target then error(why, 0) end
		end
		Drop()
		Show(Clean(a.text), target, Clean(a.title), Seconds(a.seconds), false)
		return true
	end })

guide:Point("waypoint", { title = L"WAYPOINT", args = { x = "number", y = "number", map = "number?" },
	doc = "sets the player's map pin, with its arrow, at x, y (0-100, as sense.position gives them) on map `map` (a map "
		.. "id; default the player's); it replaces a pin the player had set",
	run = function(_, a)
		local map = a.map or C_Map.GetBestMapForUnit("player")
		if not map then error("no map here", 0) end
		if a.x < 0 or a.x > 100 or a.y < 0 or a.y > 100 then error("x and y are 0 to 100", 0) end
		if C_Map.CanSetUserWaypointOnMap and not C_Map.CanSetUserWaypointOnMap(map) then
			error(("map %d takes no pin"):format(map), 0)
		end
		C_Map.SetUserWaypoint(UiMapPoint.CreateFromCoordinates(map, a.x / 100, a.y / 100))
		pinned = { map = map, x = a.x / 100, y = a.y / 100 }
		if C_SuperTrack and C_SuperTrack.SetSuperTrackedUserWaypoint then C_SuperTrack.SetSuperTrackedUserWaypoint(true) end
		return { map = map, x = a.x, y = a.y }
	end })

guide:Point("tour", { title = L"TOUR", args = { steps = "table", title = "string?" },
	doc = "notes one after another, steps [{text, frame?}] (a frame is highlighted for its step), up to 20; the player "
		.. "clicks Next; the event guide.tour {step, of, state: shown, done, closed} says where it is",
	run = function(_, a)
		if #a.steps == 0 or #a.steps > 20 then error("steps: 1 to 20 of {text, frame?}", 0) end
		local steps = {}
		for i, s in ipairs(a.steps) do
			if type(s) ~= "table" or type(s.text) ~= "string" then error(("step %d is {text, frame?}"):format(i), 0) end
			if s.frame ~= nil then
				local _, why = Target(tostring(s.frame))
				if why then error(("step %d: %s"):format(i, why), 0) end
			end
			steps[i] = { text = Clean(s.text), frame = s.frame and tostring(s.frame) or nil }
		end
		Clear()
		tour = { steps = steps, at = 1, title = Clean(a.title) }
		Step()
		return { steps = #steps }
	end })

guide:Point("clear", { title = L"CLEAR",
	doc = "put away what the guide shows (a tour ends as closed), and its map pin while that is still the one it put",
	run = function()
		Close()
		Unpin()
		return true
	end })

guide:Status(function()
	if tour then return L.TOURING:format(tour.title or L.TITLE, tour.at, #tour.steps) end
end)
