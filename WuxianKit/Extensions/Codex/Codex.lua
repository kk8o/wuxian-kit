-- 图鉴 (Codex): the player's characters for wuxianwow.com's 我的角色. Every character that logs in is kept in the
-- account's saved variables (its name, realm, class, race, level and professions); /wk codex (or the button on its page)
-- opens a small window: tick the characters, copy the link (Ctrl+C) and open it in a browser, or paste it into the site's
-- 我的角色. The link's part after # never reaches the site's server, and the site keeps the characters in that browser only.
-- Nothing is sent from the game.
--
-- The code (the site's app/src/mychar.ts reads it):
--   <character>[,<character>...]!<check>
--   character = class.level.race[.profession-skill...][~name[@realm]]   ids: ChrClasses, ChrRaces, SkillLine; name and
--               realm percent-encoded UTF-8
--   check     = two base-36 digits of h, h = (h * 31 + byte) % 1296 over the bytes before "!", from 0
local Kit = WuxianKit
local S = Kit.Skin
local C = S.C
local issecret = issecretvalue or function() return false end

local SITE = "https://wuxianwow.com/#me="
local SHOWN = 12                      -- characters listed in the window, the latest first

local L = Kit:Words {
	zhCN = { TITLE = "图鉴", WINDOW = "导出到无限图鉴", OPEN = "导出角色",
		HELP = "导出角色到无限图鉴（wuxianwow.com）的「我的角色」",
		HINT = "勾选要导出的角色，按 Ctrl+C 复制下面的链接，在浏览器里打开；也可以粘到图鉴「我的角色」的「导入角色码」。",
		PRIVATE = "链接里 # 后面的内容不会发给网站服务器，角色只保存在你的浏览器里。",
		WITH_NAME = "带上角色名和服务器", NONE = "还没有记录到角色：登录一次角色就会记下。", NONE_PICKED = "至少勾选一个角色。",
		MORE = "另有 %d 个角色没有列出（只列最近登录的 %d 个）。", FORGET = "移除", CLOSE = "关闭",
		STATUS = "已记录 %d 个角色。登录过的角色会自动记下（名字、服务器、职业、种族、等级、专业），只存在本机。",
		LEVEL = "%d 级" },
	enUS = { TITLE = "Codex", WINDOW = "Export to Wuxian Codex", OPEN = "Export characters",
		HELP = "export characters to Wuxian Codex (wuxianwow.com), its 我的角色",
		HINT = "Tick the characters, press Ctrl+C to copy the link below and open it in a browser; or paste it into the site's My characters, Import code.",
		PRIVATE = "What follows # in the link never reaches the site's server; the characters stay in your browser only.",
		WITH_NAME = "Include name and realm", NONE = "No character kept yet: log one in once.", NONE_PICKED = "Tick one character at least.",
		MORE = "%d more not listed (only the %d logged in last).", FORGET = "Remove", CLOSE = "Close",
		STATUS = "%d characters kept. Characters that log in are kept (name, realm, class, race, level, professions), on this computer only.",
		LEVEL = "level %d" },
}

local codex = Kit:Extension("codex", { title = L"TITLE", version = Kit.VERSION, defaults = { chars = {}, withName = true } })

local function V(v)
	if issecret(v) then return nil end
	return v
end

-- the character logged in now, or nil while the client does not tell (a loading screen)
local function Current()
	local name = GetUnitName and V(GetUnitName("player", true)) or V((UnitName("player")))
	local realm = V(GetRealmName())
	local _, _, cls = UnitClass("player")
	local _, _, race = UnitRace("player")
	local lv = V(UnitLevel("player"))
	cls, race = V(cls), V(race)
	if not (name and realm and cls and lv and lv > 0) then return nil end
	local profs, list = {}, { GetProfessions() }
	for n = 1, select("#", GetProfessions()) do
		local i = list[n]
		if i then
			local _, _, level, _, _, _, line = GetProfessionInfo(i)
			if V(line) and V(level) then profs[#profs + 1] = { line, level } end
		end
	end
	return { name = name, realm = realm, cls = cls, race = race or 0, lv = lv, profs = profs, seen = time() }
end

local function Remember()
	local c = Current()
	if c and type(codex.db.chars) == "table" then codex.db.chars[c.realm .. "|" .. c.name] = c end
end

-- the characters kept, the latest first: { key, char }
local function Kept()
	local out = {}
	for key, c in pairs(type(codex.db.chars) == "table" and codex.db.chars or {}) do
		if type(c) == "table" and c.cls and c.lv then out[#out + 1] = { key = key, char = c } end
	end
	table.sort(out, function(a, b) return (a.char.seen or 0) > (b.char.seen or 0) end)
	return out
end

local function Pct(s)
	return (tostring(s):gsub("[^%w%-_]", function(ch) return ("%%%02X"):format(ch:byte()) end))
end

local function Check(s)
	local h = 0
	for i = 1, #s do h = (h * 31 + s:byte(i)) % 1296 end
	local DIGITS = "0123456789abcdefghijklmnopqrstuvwxyz"
	local a, b = math.floor(h / 36) + 1, h % 36 + 1
	return DIGITS:sub(a, a) .. DIGITS:sub(b, b)
end

-- the code of the characters given, with their names or without
function codex.Code(chars, withName)
	local parts = {}
	for _, c in ipairs(chars) do
		local p = { c.cls, c.lv, c.race or 0 }
		for _, pr in ipairs(c.profs or {}) do p[#p + 1] = pr[1] .. "-" .. pr[2] end
		local s = table.concat(p, ".")
		if withName and c.name then s = s .. "~" .. Pct(c.name) .. (c.realm and ("@" .. Pct(c.realm)) or "") end
		parts[#parts + 1] = s
	end
	local payload = table.concat(parts, ",")
	return payload .. "!" .. Check(payload)
end

local function Who(c)
	local cls = GetClassInfo and GetClassInfo(c.cls)
	local race = C_CreatureInfo and C_CreatureInfo.GetRaceInfo and C_CreatureInfo.GetRaceInfo(c.race or 0)
	return ("%s · %s · %s %s%s"):format(c.name or "?", c.realm or "?", L.LEVEL:format(c.lv), race and race.raceName or "",
		cls or "")
end

------------------------------------------------------------------------------------------------------------------------
-- the window

local f
local W = 560
local off = {}                        -- the keys ticked off in this window (all ticked when it opens)

local function Link()
	local picked = {}
	for _, k in ipairs(Kept()) do
		if not off[k.key] and #picked < SHOWN then picked[#picked + 1] = k.char end
	end
	if #picked == 0 then return nil end
	return SITE .. codex.Code(picked, codex.db.withName)
end

local Draw

local function Frame()
	if f then return f end
	f = S.Panel("WuxianKitCodexWindow", W, 200, "codex")
	tinsert(UISpecialFrames, "WuxianKitCodexWindow")
	f.title = S.Text(f, C.gold)
	f.title:SetPoint("TOPLEFT", 14, -12)
	f.close = S.Button(f, "×", false, function() f:Hide() end)
	f.close:SetSize(24, 24)
	f.close:SetPoint("TOPRIGHT", -8, -8)
	f.hint = S.Text(f, C.fg)
	f.hint:SetWidth(W - 28)
	f.rows, f.forgets = {}, {}
	f.name = S.Check(f, function(_, on)
		codex.db.withName = on
		Draw()
	end)
	f.more = S.Text(f, C.muted, true)
	f.more:SetWidth(W - 28)
	f.edit = S.Edit(f, function() end)
	f.edit:SetWidth(W - 28)
	f.edit:SetMaxLetters(0)
	f.edit:SetScript("OnTextChanged", function(self, user)        -- read only: what was typed goes, the link stays
		if user then
			self:SetText(self.link or "")
			self:HighlightText()
		end
	end)
	f.edit:SetScript("OnEditFocusGained", function(self) self:HighlightText() end)
	f.edit:SetScript("OnEditFocusLost", function(self) self:HighlightText(0, 0) end)
	f.edit:SetScript("OnEscapePressed", function() f:Hide() end)
	f.edit:SetScript("OnEnterPressed", function(self) self:HighlightText() end)
	f.private = S.Text(f, C.muted, true)
	f.private:SetWidth(W - 28)
	f.done = S.Button(f, L.CLOSE, true, function() f:Hide() end)
	return f
end

function Draw()
	if not (f and f:IsShown()) then return end
	f.title:SetText(L.WINDOW)
	f.hint:ClearAllPoints()
	f.hint:SetPoint("TOPLEFT", 14, -40)
	f.hint:SetText(L.HINT)
	local y = 40 + f.hint:GetStringHeight() + 12
	local kept = Kept()
	for i = 1, math.max(#f.rows, math.min(#kept, SHOWN)) do
		local k = i <= SHOWN and kept[i]
		local row, x = f.rows[i], f.forgets[i]
		if k then
			if not row then
				row = S.Check(f, function(self, on)
					off[self.key] = not on or nil
					Draw()
				end)
				row.label:SetWidth(W - 110)
				row.label:SetWordWrap(false)
				f.rows[i] = row
				x = S.Button(f, L.FORGET, false, function(self)
					codex.db.chars[self.key] = nil
					off[self.key] = nil
					Draw()
				end)
				x:SetSize(52, 18)
				f.forgets[i] = x
			end
			row.key, x.key = k.key, k.key
			row:ClearAllPoints()
			row:SetPoint("TOPLEFT", 14, -y)
			row.label:SetText(Who(k.char))
			row.Set(not off[k.key])
			row:Show()
			x.label:SetText(L.FORGET)
			x:ClearAllPoints()
			x:SetPoint("TOPRIGHT", -14, -y + 1)
			x:Show()
			y = y + 22
		elseif row then
			row:Hide()
			x:Hide()
		end
	end
	f.more:ClearAllPoints()
	f.more:SetPoint("TOPLEFT", 14, -y)
	if #kept == 0 then
		f.more:SetText(L.NONE)
	elseif #kept > SHOWN then
		f.more:SetText(L.MORE:format(#kept - SHOWN, SHOWN))
	else
		f.more:SetText("")
	end
	if f.more:GetText() ~= "" then y = y + f.more:GetStringHeight() + 6 end
	y = y + 4
	f.name:ClearAllPoints()
	f.name:SetPoint("TOPLEFT", 14, -y)
	f.name.label:SetText(L.WITH_NAME)
	f.name.Set(codex.db.withName)
	y = y + 26
	local link = Link()
	f.edit.link = link or ""
	f.edit:ClearAllPoints()
	f.edit:SetPoint("TOPLEFT", 14, -y)
	f.edit:SetText(link or L.NONE_PICKED)
	f.edit.kept = f.edit:GetText()
	if link then
		f.edit:SetFocus()
		f.edit:HighlightText()
	else
		f.edit:ClearFocus()
	end
	y = y + 30
	f.private:ClearAllPoints()
	f.private:SetPoint("TOPLEFT", 14, -y)
	f.private:SetText(L.PRIVATE)
	y = y + f.private:GetStringHeight() + 12
	f.done.label:SetText(L.CLOSE)
	f.done:ClearAllPoints()
	f.done:SetPoint("TOPRIGHT", -14, -y)
	f:SetHeight(y + 36)
end

local function Open()
	Remember()
	Frame()
	for k in pairs(off) do off[k] = nil end
	S.Place(f, "codex", "CENTER", 0, 60)
	f:Show()
	f:Raise()
	Draw()
end
codex.Open = Open

codex:On("PLAYER_ENTERING_WORLD", function() Remember() end)
codex:On("PLAYER_LEVEL_UP", function() C_Timer.After(1, Remember) end)
codex:On("SKILL_LINES_CHANGED", function() Remember() end)
codex:Status(function(self) return L.STATUS:format(#Kept()) end)
codex:Button(L"OPEN", function() Open() end)
codex:Command("codex", function() Open() end, L"HELP")
