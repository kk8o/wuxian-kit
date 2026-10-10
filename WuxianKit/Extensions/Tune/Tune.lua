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

-- A bit-field setting keeps bytes, not text: the byte 2, then six bits a byte (from "@", 64). It reads as "bits:" and the
-- bits that are on, counted from 1 as C_CVar.GetCVarBitfield counts them ("bits:1,2,4,5"), and changes a bit at a time.
local function IsBits(raw)
	if type(raw) ~= "string" or raw:byte(1) ~= 2 then return false end
	for i = 2, #raw do
		local b = raw:byte(i)
		if b < 64 or b > 127 then return false end
	end
	return true
end

local function BitsOf(raw)                               -- the bits that are on (a set), and how many the value holds
	local on = {}
	for i = 2, #raw do
		local b = raw:byte(i) - 64
		for k = 1, 6 do
			if b % 2 == 1 then on[(i - 2) * 6 + k] = true end
			b = math.floor(b / 2)
		end
	end
	return on, (#raw - 1) * 6
end

local function BitsText(on)
	local list = {}
	for i in pairs(on) do list[#list + 1] = i end
	table.sort(list)
	return "bits:" .. table.concat(list, ",")
end

local function Wanted(v)                                -- the bits a "bits:1,4" value has on; false when it is not one
	local list = type(v) == "string" and v:match("^%s*bits:(.*)$")
	if not list then return false end
	local on = {}
	for n in list:gmatch("[^,%s]+") do
		local i = tonumber(n)
		if not i or i < 1 or i > 4096 or i % 1 ~= 0 then return nil end
		on[i] = true
	end
	return on
end

local function Readable(raw)                             -- a value as the agent and the preview read it
	if IsBits(raw) then return BitsText((BitsOf(raw))) end
	return raw
end

tune:Setting("cvar", { title = L"CVAR",
	doc = "a client setting (CVar) by its name; a bit-field setting (bits = true) reads as the bits that are on, e.g. "
		.. "\"bits:1,4\"",
	change = "value: a string, number or boolean (true and false are written as 1 and 0); for a bit-field setting, all "
		.. "the bits that should be on (\"bits:1,4\"; \"bits:\" turns all off). Its pre-approval category is the setting's "
		.. "(graphics, sound, game, combat, net or other). Secure, read-only and locked settings are refused",
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
	validate = function(_, k, v)
		local bits, wanted = IsBits((Info(k.name))), Wanted(v)
		if bits and not wanted then
			return ("%s is a bit-field setting: give the bits to have on, as bits:1,4 (numbers from 1)"):format(k.name)
		end
		if not bits and wanted ~= false then return ("%s is no bit-field setting"):format(k.name) end
	end,
	get = function(_, k) return Readable((Info(k.name))) end,
	set = function(_, k, v)
		local wanted = Wanted(v)
		if wanted == false then return C_CVar.SetCVar(k.name, v) end
		local raw = Info(k.name)                          -- bits: never written as text, whatever the setting holds now
		if not wanted or not IsBits(raw) then error(("%s is no bit-field setting now"):format(k.name), 0) end
		local on, count = BitsOf(raw)
		for i in pairs(wanted) do count = math.max(count, i) end
		for i = 1, count do
			if (on[i] or false) ~= (wanted[i] or false) then C_CVar.SetCVarBitfield(k.name, i, wanted[i] or false) end
		end
	end,
	normalize = function(_, v)
		if type(v) == "boolean" then return v and "1" or "0" end
		if IsBits(v) then return Readable(v) end           -- a raw bit-field value (a profile kept by 0.4.0)
		local wanted = Wanted(v)
		if wanted then return BitsText(wanted) end
		return tostring(v)
	end,
	label = function(_, k) return Entry(k.name).name or k.name end,
	explain = function(_, k)
		local help = Entry(k.name).help
		return help and (#help > 90 and (help:sub(1, 87) .. "...") or help)
	end,
	info = function(_, k)
		local value, default, f = Info(k.name)
		local e = Entry(k.name)
		return { name = e.name or k.name, default = default and Readable(default), category = e.category, help = e.help,
			secure = f and f.secure or nil, readOnly = f and f.readOnly or nil, locked = f and f.locked or nil,
			stored = f and (f.account and "account" or f.character and "character") or nil, bits = IsBits(value) or nil }
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
				out[#out + 1] = { name = e.name, value = Readable((Info(e.name))), category = e.category, help = e.help }
			end
		end
		return out
	end })
