-- 图鉴 (Codex): the player's characters for wuxianwow.com's 我的角色. Every character that logs in is kept in the
-- account's saved variables (its name, realm, class, race, level and professions, and what it wears and its talents, for the
-- site's 战斗模拟器: the items with their enchants, the talent nodes with points in them); /wk codex (or the button on its page)
-- opens a small window: tick the characters, copy the link (Ctrl+C) and open it in a browser, or paste it into the site's
-- 我的角色. The link's part after # never reaches the site's server, and the site keeps the characters in that browser only.
-- Nothing is sent from the game.
--
-- The code (the site's app/src/mychar.ts reads it):
--   <character>[,<character>...]!<check>
--   character = class.level.race[.profession-skill...][*g<gear>][*t<talents>][~name[@realm]]   ids: ChrClasses, ChrRaces,
--               SkillLine; name and realm percent-encoded UTF-8
--   gear      = slot-item[-enchant] joined by "_", by slot: the inventory slot in decimal, the item and its enchant
--               (SpellItemEnchantment) in base 36; the shirt and the tabard left out
--   talents   = the nodes of the class's talent tree with points in them, by node: the rank, then the node's distance from the
--               one before (the first: from 0) in base 36, joined by "_" ("3a": rank 3, 10 on)
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
		HINT = "勾选要导出的角色，按 Ctrl+C 复制下面的链接，在浏览器里打开；也可以粘到图鉴「我的角色」的「导入角色码」。带上的装备、附魔与天赋可在图鉴的战斗模拟器里「用这个角色」。",
		PRIVATE = "链接里 # 后面的内容不会发给网站服务器，角色只保存在你的浏览器里。",
		WITH_NAME = "带上角色名和服务器", NONE = "还没有记录到角色：登录一次角色就会记下。", NONE_PICKED = "至少勾选一个角色。",
		MORE = "另有 %d 个角色没有列出（只列最近登录的 %d 个）。", FORGET = "移除", CLOSE = "关闭",
		STATUS = "已记录 %d 个角色。登录过的角色会自动记下（名字、服务器、职业、种族、等级、专业、装备与附魔、天赋），只存在本机。",
		GEAR = "装备 %d 件", TALENTS = "天赋 %d 点",
		LEVEL = "%d 级" },
	enUS = { TITLE = "Codex", WINDOW = "Export to Wuxian Codex", OPEN = "Export characters",
		HELP = "export characters to Wuxian Codex (wuxianwow.com), its 我的角色",
		HINT = "Tick the characters, press Ctrl+C to copy the link below and open it in a browser; or paste it into the site's My characters, Import code. The gear, enchants and talents go along, for the site's combat simulator.",
		PRIVATE = "What follows # in the link never reaches the site's server; the characters stay in your browser only.",
		WITH_NAME = "Include name and realm", NONE = "No character kept yet: log one in once.", NONE_PICKED = "Tick one character at least.",
		MORE = "%d more not listed (only the %d logged in last).", FORGET = "Remove", CLOSE = "Close",
		STATUS = "%d characters kept. Characters that log in are kept (name, realm, class, race, level, professions, gear and enchants, talents), on this computer only.",
		GEAR = "%d items", TALENTS = "%d talent points",
		LEVEL = "level %d" },
}

local codex = Kit:Extension("codex", { title = L"TITLE", version = Kit.VERSION, defaults = { chars = {}, withName = true } })

local function V(v)
	if issecret(v) then return nil end
	return v
end

-- the character logged in now, or nil while the client does not tell (a loading screen)
-- what the character wears: { slot, item, enchant } by slot (the shirt and the tabard left out)
local function Gear()
	local out = {}
	for slot = 1, 18 do
		local link = slot ~= 4 and V(GetInventoryItemLink("player", slot))
		local id, ench
		if type(link) == "string" then id, ench = link:match("item:(%d+):(%-?%d*)") end
		if id and tonumber(id) > 0 then out[#out + 1] = { slot, tonumber(id), math.max(tonumber(ench) or 0, 0) } end
	end
	return out
end

-- the talent tree's nodes with points in them: { node, rank } by node; {} when the client has no talent tree to read
local function Talents()
	local out = {}
	local ok = pcall(function()
		local cfg = C_ClassTalents.GetActiveConfigID()
		local info = cfg and C_Traits.GetConfigInfo(cfg)
		local tree = info and info.treeIDs and info.treeIDs[1]
		if not tree then return end
		for _, node in ipairs(C_Traits.GetTreeNodes(tree) or {}) do
			local n = C_Traits.GetNodeInfo(cfg, node)
			local rank = n and V(n.ranksPurchased)
			if rank and rank > 0 then out[#out + 1] = { node, math.min(rank, 9) } end
		end
	end)
	if not ok then return {} end
	table.sort(out, function(a, b) return a[1] < b[1] end)
	return out
end

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
	return { name = name, realm = realm, cls = cls, race = race or 0, lv = lv, profs = profs, gear = Gear(), talents = Talents(), seen = time() }
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

local function B36(n)
	local DIGITS, out = "0123456789abcdefghijklmnopqrstuvwxyz", ""
	n = math.floor(n)
	repeat
		local d = n % 36
		out = DIGITS:sub(d + 1, d + 1) .. out
		n = math.floor(n / 36)
	until n == 0
	return out
end

-- the *g and *t parts of a character's code ("" when it has none)
local function GearCode(gear)
	local parts = {}
	for _, g in ipairs(gear or {}) do
		parts[#parts + 1] = g[1] .. "-" .. B36(g[2]) .. ((g[3] or 0) > 0 and ("-" .. B36(g[3])) or "")
	end
	return #parts > 0 and ("*g" .. table.concat(parts, "_")) or ""
end
local function TalentCode(talents)
	local parts, last = {}, 0
	for _, t in ipairs(talents or {}) do
		parts[#parts + 1] = t[2] .. B36(t[1] - last)
		last = t[1]
	end
	return #parts > 0 and ("*t" .. table.concat(parts, "_")) or ""
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
		local s = table.concat(p, ".") .. GearCode(c.gear) .. TalentCode(c.talents)
		if withName and c.name then s = s .. "~" .. Pct(c.name) .. (c.realm and ("@" .. Pct(c.realm)) or "") end
		parts[#parts + 1] = s
	end
	local payload = table.concat(parts, ",")
	return payload .. "!" .. Check(payload)
end

local function Who(c)
	local cls = GetClassInfo and GetClassInfo(c.cls)
	local race = C_CreatureInfo and C_CreatureInfo.GetRaceInfo and C_CreatureInfo.GetRaceInfo(c.race or 0)
	local s = ("%s · %s · %s %s%s"):format(c.name or "?", c.realm or "?", L.LEVEL:format(c.lv), race and race.raceName or "", cls or "")
	if c.gear and #c.gear > 0 then s = s .. " · " .. L.GEAR:format(#c.gear) end
	local pts = 0
	for _, t in ipairs(c.talents or {}) do pts = pts + t[2] end
	if pts > 0 then s = s .. " · " .. L.TALENTS:format(pts) end
	return s
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
-- gear and talents: after the change has settled (a set swaps several items, a talent change comes in steps)
local pending
local function Later()
	if pending then return end
	pending = true
	C_Timer.After(1, function()
		pending = nil
		Remember()
	end)
end
codex:On("PLAYER_EQUIPMENT_CHANGED", Later)
codex:On("TRAIT_CONFIG_UPDATED", Later)
codex:Status(function(self) return L.STATUS:format(#Kept()) end)
codex:Button(L"OPEN", function() Open() end)
codex:Command("codex", function() Open() end, L"HELP")
