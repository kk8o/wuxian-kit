-- 调校 · 宏 (Tune: macros). tune.macro.get / tune.macro.set: a Setting, a macro's text by its name (no text deletes it;
-- a new one is the account's, with the question-mark icon, which shows the icon of the first spell or item it uses);
-- tune.macro.list. The client makes and changes a macro a moment after it is asked (a placeholder first), so the step
-- waits until the game shows it. A change of text leaves the name and the icon as they are (a question-mark macro keeps
-- following its spell); undo puts back the text, the icon the macro keeps (not the one it shows) and whose it was. A
-- macro deleted from the action bars cannot be put back there (placing actions is protected): the preview says so.
local Kit = WuxianKit

local L = Kit:Words {
	zhCN = { MACRO = "宏", LIST = "宏列表", SCOPE = "宏", MORE = "%s ……（共 %d 行）",
		ON_BARS = "这个宏在动作条上：删除会清掉这些按钮，撤销也放不回动作条" },
	enUS = { MACRO = "Macros", LIST = "Macro list", SCOPE = "Macros", MORE = "%s ... (%d lines)",
		ON_BARS = "This macro is on the action bars: deleting it clears those buttons, and undo cannot put them back" },
}

local tune = Kit:Extension("tune")
tune:Scope("macros", L"SCOPE")

local ICON = 134400                  -- the question mark: the icon of the first spell or item the macro uses
local FIRST_CHARACTER = 121          -- where the character's macros are numbered from (MAX_ACCOUNT_MACROS + 1)
local MAX_ACCOUNT, MAX_BODY, MAX_NAME = 120, 255, 16

local function Find(name)
	local i = GetMacroIndexByName(name)
	return i and i > 0 and i or nil
end

local function Trim(s) return s and (s:gsub("%s+$", "")) end

local function Lines(body)
	local out = {}
	for line in (Trim(body) .. "\n"):gmatch("(.-)\n") do out[#out + 1] = line end
	return out
end

local function Make(name, icon, body, character)
	CreateMacro(name, icon or ICON, body, character or false)
end

local function Remove(name)
	local i = Find(name)
	if i then DeleteMacro(i) end
end

-- the icon a macro keeps (the question mark stays the question mark), not the one it shows now
local function KeptIcon(i)
	if C_Macro and C_Macro.GetSelectedMacroIcon then
		local ok, icon = pcall(C_Macro.GetSelectedMacroIcon, i)
		if ok and icon then return icon end
	end
	local _, icon = GetMacroInfo(i)
	return icon
end

-- whether macro i is on an action bar
local function Placed(i)
	if not GetActionInfo then return false end
	for slot = 1, 180 do
		local ok, kind, id = pcall(GetActionInfo, slot)
		if ok and kind == "macro" and id == i then return true end
	end
	return false
end

tune:Setting("macro", { title = L"MACRO", scope = "macros", settle = true,
	doc = "a macro's text by its name (the account's or the character's; a new one is the account's, with the "
		.. "question-mark icon); no text deletes it; at most 255 bytes; the client makes it a moment later",
	key = { name = "string" }, value = "string?",
	check = function(_, k)
		if k.name == "" or #k.name > MAX_NAME then return ("a macro's name is 1 to %d bytes"):format(MAX_NAME) end
	end,
	validate = function(_, k, v)
		if v == nil then return nil end
		if Trim(v) == "" then return "the text is empty (no value deletes the macro)" end
		if #v > MAX_BODY then return ("the text is %d bytes, more than %d"):format(#v, MAX_BODY) end
		if not Find(k.name) and GetNumMacros() >= (MAX_ACCOUNT_MACROS or MAX_ACCOUNT) then
			return "no room for another account macro"
		end
	end,
	get = function(_, k)
		local i = Find(k.name)
		return i and GetMacroBody(i) or nil
	end,
	same = function(a, b) return Trim(a) == Trim(b) end,
	set = function(_, k, v)
		local i = Find(k.name)
		if v == nil then
			Remove(k.name)
		elseif i then
			EditMacro(i, nil, nil, v)                            -- the text only: name and icon stay
		else
			Make(k.name, ICON, v)
		end
	end,
	keep = function(_, k)                                    -- what undo needs besides the text
		local i = Find(k.name)
		if not i then return nil end
		return { icon = KeptIcon(i), character = i >= FIRST_CHARACTER or nil }
	end,
	restore = function(_, k, v, kept)
		local i = Find(k.name)
		if v == nil then
			Remove(k.name)
		elseif i then
			EditMacro(i, nil, kept and kept.icon or nil, v)
		else
			Make(k.name, kept and kept.icon, v, kept and kept.character)
		end
	end,
	format = function(_, v)                                  -- (the core escapes explain's lines; this one escapes itself)
		local lines = Lines(v)
		if #lines <= 1 then return Kit:Escape(lines[1] or "") end
		return L.MORE:format(Kit:Escape(lines[1]), #lines)
	end,
	explain = function(_, k, v)
		if v == nil then
			local i = Find(k.name)
			return i and Placed(i) and L.ON_BARS or nil
		end
		if #Lines(v) <= 1 then return nil end
		return table.concat(Lines(v), "\n")
	end })

tune:See("macro.list", { title = L"LIST",
	doc = "the macros: name, text, icon, and character = true for the character's own (the rest are the account's)",
	run = function()
		local out = {}
		local account, character = GetNumMacros()
		for i = 1, account do
			local name, icon, body = GetMacroInfo(i)
			if name then out[#out + 1] = { name = name, text = body, icon = icon } end
		end
		for i = FIRST_CHARACTER, FIRST_CHARACTER + character - 1 do
			local name, icon, body = GetMacroInfo(i)
			if name then out[#out + 1] = { name = name, text = body, icon = icon, character = true } end
		end
		return out
	end })
