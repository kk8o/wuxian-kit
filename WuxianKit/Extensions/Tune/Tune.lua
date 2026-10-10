-- 调校 (Tune): what the player sets up in the client, each a proposal with a preview and undo. Its files:
--   Tune.lua      the extension; the client's settings (CVars)
--   Options.lua   the game's Settings panel: its options found by what the player reads there, and those of them that
--                 are no single CVar (the action bars shown, modifier keys, several CVars at once ...)
--   Bindings.lua  key bindings          Macros.lua  macros          Layouts.lua  Edit Mode layouts
--   Talents.lua   talent loadouts       Gear.lua    equipment sets  Bags.lua     sorting the bags
--   AddOns.lua    addons on and off     Profiles.lua  profiles: named sets of steps, applied with one click, shared as text
-- Here: one Setting gives tune.cvar.get and tune.cvar.set (the preview "name: old → new" with the setting's help text);
-- tune.cvar.find looks settings up by name or help text. A setting's scope is its category (graphics, sound, game,
-- combat, net, other), so the player may let one kind go without asking. Secure, read-only and locked settings are
-- refused when the proposal is made (C_CVar.SetCVar wants a valid, public, writable, non-secure one). What the Settings
-- panel's Apply does besides setting a CVar is done too: a display setting updates the window, a few restart the
-- graphics device, and a graphics quality sets the detail settings under it to that quality's values (as the panel's
-- slider does: the quality alone changes nothing on the screen); undo puts the details back as they were.
local Kit = WuxianKit

local L = Kit:Words {
	zhCN = { TITLE = "调校", CVAR = "客户端设置", FIND = "查找客户端设置",
		SCOPE = { graphics = "画面设置", sound = "声音设置", game = "游戏设置", combat = "战斗设置", net = "网络设置",
			other = "其他设置" },
		PRESET = "同时按这一档画质调整阴影、视距等 %d 项", RESTART = "重启游戏后生效" },
	enUS = { TITLE = "Tune", CVAR = "Client settings", FIND = "Find client settings",
		SCOPE = { graphics = "Graphics settings", sound = "Sound settings", game = "Game settings",
			combat = "Combat settings", net = "Network settings", other = "Other settings" },
		PRESET = "Also sets shadows, view distance and the rest (%d settings) to this quality",
		RESTART = "Takes effect after the game restarts" },
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

-- writes v ("bits:..." a bit at a time, never as text, whatever the setting holds now)
local function Write(name, v)
	local wanted = Wanted(v)
	if wanted == false then return C_CVar.SetCVar(name, v) end
	local raw = Info(name)
	if not wanted or not IsBits(raw) then error(("%s is no bit-field setting now"):format(name), 0) end
	local on, count = BitsOf(raw)
	for i in pairs(wanted) do count = math.max(count, i) end
	for i = 1, count do
		if (on[i] or false) ~= (wanted[i] or false) then C_CVar.SetCVarBitfield(name, i, wanted[i] or false) end
	end
end

-- What the Settings panel's Apply does besides setting these (Blizzard_SettingsDefinitions, their commit flags): the
-- window takes a display change at once, the graphics device restarts, or the game must restart. By lowercase name.
local WINDOW = { gxmaximize = true, gxmonitor = true, vsync = true, notcheddisplaymode = true }
local GX = { gxmaxframelatency = true, gxadapter = true, gxcompatoptionalgpufeatures = true,
	gxcompatasyncshadercompilation = true, gxcompatcommandlistmultithreading = true, gxcompatworksubmitoptimizations = true }
local RESTART = { gxapi = true, physicslevel = true }

local function Applied(name)
	local n = name:lower()
	if WINDOW[n] and UpdateWindow then UpdateWindow() end
	if GX[n] and RestartGx then RestartGx() end
end

-- A graphics quality (graphicsQuality, raidGraphicsQuality) and the detail settings under it, as the panel lists them on
-- this client (some only when the client supports them); a quality sets each to GetGraphicsCVarValueForQualityLevel's
-- value for it, particle density at least 1 (the panel's floor)
local QUALITY = { graphicsquality = "graphics", raidgraphicsquality = "raidGraphics" }
local DETAILS = { "ShadowQuality", "LiquidDetail", "PBRLiquidDetail", "ParticleDensity", "SSAO", "DepthEffects",
	"ComputeEffects", "OutlineMode", "TextureResolution", "SpellDensity", "ProjectedTextures", "LightMode", "ViewDistance",
	"EnvironmentDetail", "GroundClutter", "BloomUserMult" }
local SUPPORTED = { PBRLiquidDetail = "IsPBRWaterSupported", OutlineMode = "IsOutlineModeSupported",
	SpellDensity = "IsSpellVisualDensitySystemSupported", LightMode = "IsSecondaryLightingSupported",
	BloomUserMult = "IsLinearEnabledOnStart" }
local FLOOR = { graphicsParticleDensity = 1 }

local function Details(name)
	local prefix, out = QUALITY[name:lower()], {}
	if not prefix then return out end
	for _, d in ipairs(DETAILS) do
		local test = SUPPORTED[d] and C_VideoOptions and C_VideoOptions[SUPPORTED[d]]
		local ok, yes = true, true
		if SUPPORTED[d] then
			if type(test) == "function" then ok, yes = pcall(test) else yes = false end
		end
		if ok and yes and C_CVar.GetCVar(prefix .. d) ~= nil then out[#out + 1] = prefix .. d end
	end
	return out
end

local function Preset(name, level)
	if not GetGraphicsCVarValueForQualityLevel or not tonumber(level) then return end
	local raid = QUALITY[name:lower()] == "raidGraphics"
	for _, cvar in ipairs(Details(name)) do
		local ok, v = pcall(GetGraphicsCVarValueForQualityLevel, cvar, tonumber(level), raid)
		if ok and tonumber(v) then C_CVar.SetCVar(cvar, math.max(tonumber(v), FLOOR[cvar] or -1)) end
	end
end

-- a setting as tune.setting.find reports it: its value as tune.cvar.get reads it, and why tune.cvar.set would refuse
-- it (nil when it would not); nil, why when the client has no setting of that name
function tune.CVarState(name)
	local value, _, f = Info(name)
	if value == nil then return nil, "no such setting on this client" end
	local why = f.secure and "secure: addons cannot change it" or f.readOnly and "read-only" or f.locked and "locked" or nil
	return Readable(value), why
end

tune:Setting("cvar", { title = L"CVAR",
	doc = "a client setting (CVar) by its name; a bit-field setting (bits = true) reads as the bits that are on, e.g. "
		.. "\"bits:1,4\"",
	change = "value: a string, number or boolean (true and false are written as 1 and 0); for a bit-field setting, all "
		.. "the bits that should be on (\"bits:1,4\"; \"bits:\" turns all off). Its pre-approval category is the setting's "
		.. "(graphics, sound, game, combat, net or other). Secure, read-only and locked settings are refused. Done as the "
		.. "Settings panel does it: a display setting (gxMaximize, vsync ...) updates the window at once, graphicsQuality "
		.. "and raidGraphicsQuality also set the detail settings under them to that quality's values; gxapi and "
		.. "physicsLevel take effect after the game restarts",
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
		Write(k.name, v)
		if QUALITY[k.name:lower()] then Preset(k.name, v) end
		Applied(k.name)
	end,
	keep = function(_, k)                                    -- a quality: the details under it, as they are
		if not QUALITY[k.name:lower()] then return nil end
		local details = {}
		for _, cvar in ipairs(Details(k.name)) do details[cvar] = C_CVar.GetCVar(cvar) end
		return { details = details }
	end,
	restore = function(_, k, v, kept)
		Write(k.name, v)
		for cvar, value in pairs(kept and kept.details or {}) do C_CVar.SetCVar(cvar, value) end
		Applied(k.name)
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
		local lines, help = {}, Entry(k.name).help
		if help then lines[#lines + 1] = #help > 90 and (help:sub(1, 87) .. "...") or help end
		if QUALITY[k.name:lower()] then lines[#lines + 1] = L.PRESET:format(#Details(k.name)) end
		if RESTART[k.name:lower()] then lines[#lines + 1] = L.RESTART end
		return #lines > 0 and table.concat(lines, "\n") or nil
	end,
	info = function(_, k)
		local value, default, f = Info(k.name)
		local e = Entry(k.name)
		return { name = e.name or k.name, default = default and Readable(default), category = e.category, help = e.help,
			secure = f and f.secure or nil, readOnly = f and f.readOnly or nil, locked = f and f.locked or nil,
			stored = f and (f.account and "account" or f.character and "character") or nil, bits = IsBits(value) or nil }
	end })

tune:See("cvar.find", { title = L"FIND", args = { text = "string", limit = "number?" },
	doc = "settings (CVars) whose name or help text holds `text` (no case; the help texts are English): name, value, "
		.. "category, help; at most `limit` (20, up to 100), names that start with the text first. For an option of the "
		.. "game's Settings panel, by the words the player reads there, use tune.setting.find",
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
