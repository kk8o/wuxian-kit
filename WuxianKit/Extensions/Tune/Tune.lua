-- 调校 (Tune): what the player sets up in the client, each a proposal with a preview and undo. Its files:
--   Tune.lua      the extension; the client's settings (CVars)
--   Bindings.lua  key bindings          Macros.lua  macros          Layouts.lua  Edit Mode layouts
--   Talents.lua   talent loadouts       Gear.lua    equipment sets  Bags.lua     sorting the bags
--   AddOns.lua    addons on and off     Profiles.lua  profiles: named sets of steps, applied with one click, shared as text
-- Here: one Setting gives tune.cvar.get and tune.cvar.set (the preview "name: old → new" with the setting's help text);
-- tune.cvar.find looks settings up by name or help text. A setting's scope is its category (graphics, sound, game,
-- combat, net, other), so the player may let one kind go without asking. Secure, read-only and locked settings are
-- refused when the proposal is made (C_CVar.SetCVar wants a valid, public, writable, non-secure one).
local Kit = WuxianKit

local L = Kit:Words {
	zhCN = { TITLE = "调校", CVAR = "客户端设置", FIND = "查找客户端设置",
		SCOPE = { graphics = "画面设置", sound = "声音设置", game = "游戏设置", combat = "战斗设置", net = "网络设置",
			other = "其他设置" } },
	enUS = { TITLE = "Tune", CVAR = "Client settings", FIND = "Find client settings",
		SCOPE = { graphics = "Graphics settings", sound = "Sound settings", game = "Game settings",
			combat = "Combat settings", net = "Network settings", other = "Other settings" } },
}

local tune = Kit:Extension("tune", { title = L"TITLE", version = Kit.VERSION, docs = "Extensions/Tune", defaults = { profiles = {} } })
local KINDS = { "graphics", "sound", "game", "combat", "net", "other" }
local SCOPED = { graphics = true, sound = true, game = true, combat = true, net = true }
for _, kind in ipairs(KINDS) do tune:Scope("settings." .. kind, function() return L.SCOPE[kind] end) end

-- the client's settings by lowercase name: { name, help, category }, read once
local index
local function Index()
	if index then return index end
	index = {}
	local names = {}
	for k, v in pairs(Enum and Enum.ConsoleCategory or {}) do names[v] = k:lower() end
	local cvar = Enum and Enum.ConsoleCommandType and Enum.ConsoleCommandType.Cvar or 0
	local ok, all = pcall(ConsoleGetAllCommands)
	for _, c in ipairs(ok and type(all) == "table" and all or {}) do
		if c.commandType == cvar and type(c.command) == "string" then
			index[c.command:lower()] = { name = c.command, help = c.help ~= "" and c.help or nil,
				category = names[c.category] or "other" }
		end
	end
	return index
end

local function Entry(name) return Index()[name:lower()] or {} end

-- (value, default, flags) of a setting, or nil when the client has none of that name
local function Info(name)
	local ok, value, default, account, character, locked, secure, readOnly = pcall(C_CVar.GetCVarInfo, name)
	if not ok or value == nil then return nil end
	return value, default, { account = account, character = character, locked = locked, secure = secure, readOnly = readOnly }
end

tune:Setting("cvar", { title = L"CVAR",
	doc = "a setting (CVar) of the client; a value is a string, number or boolean (true / false as 1 / 0); scope "
		.. "settings.<category> (graphics, sound, game, combat, net, other); secure, read-only and locked ones are refused",
	key = { name = "string" }, value = "string|number|boolean",
	scope = function(_, k)
		local c = Entry(k.name).category
		return "settings." .. (SCOPED[c] and c or "other")
	end,
	check = function(_, k, reading)
		local value, _, f = Info(k.name)
		if value == nil then return ("no setting %s (tune.cvar.find looks them up)"):format(k.name) end
		if reading then return nil end
		if f.secure then return ("%s is secure: addons cannot change it"):format(k.name) end
		if f.readOnly then return ("%s is read-only"):format(k.name) end
		if f.locked then return ("%s is locked"):format(k.name) end
	end,
	get = function(_, k) return (Info(k.name)) end,
	set = function(_, k, v) C_CVar.SetCVar(k.name, v) end,
	normalize = function(_, v)
		if type(v) == "boolean" then return v and "1" or "0" end
		return tostring(v)
	end,
	label = function(_, k) return Entry(k.name).name or k.name end,
	explain = function(_, k)
		local help = Entry(k.name).help
		return help and (#help > 90 and (help:sub(1, 87) .. "...") or help)
	end,
	info = function(_, k)
		local _, default, f = Info(k.name)
		local e = Entry(k.name)
		return { name = e.name or k.name, default = default, category = e.category, help = e.help,
			secure = f and f.secure or nil, readOnly = f and f.readOnly or nil, locked = f and f.locked or nil,
			stored = f and (f.account and "account" or f.character and "character") or nil }
	end })

tune:See("cvar.find", { title = L"FIND", args = { text = "string", limit = "number?" },
	doc = "settings (CVars) whose name or help text holds `text` (no case): name, value, category, help; at most `limit` "
		.. "(20, up to 100), names that start with the text first",
	run = function(_, a)
		local want, limit = a.text:lower(), math.max(1, math.min(tonumber(a.limit) or 20, 100))
		local first, rest = {}, {}
		for key, e in pairs(Index()) do
			if key:find(want, 1, true) or (e.help and e.help:lower():find(want, 1, true)) then
				local list = key:sub(1, #want) == want and first or rest
				list[#list + 1] = e
			end
		end
		local function byName(x, y) return x.name:lower() < y.name:lower() end
		table.sort(first, byName)
		table.sort(rest, byName)
		local out = {}
		for _, list in ipairs({ first, rest }) do
			for _, e in ipairs(list) do
				if #out >= limit then return out end
				out[#out + 1] = { name = e.name, value = (Info(e.name)), category = e.category, help = e.help }
			end
		end
		return out
	end })
