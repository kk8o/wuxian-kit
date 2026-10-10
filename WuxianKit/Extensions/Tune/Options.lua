-- 调校 · 系统设置 (Tune: the game's Settings panel). tune.setting.find: the panel's options (the game's own categories,
-- not addons'), found by the words the player reads there, the category or the setting's name, each with its value and
-- how to change it: tune.cvar.set for one that is a CVar (or stands for one), tune.option.set for one this file sets.
-- tune.option.get / tune.option.set: a Setting, the options that are no single CVar, by the panel's own name for them
-- (PROXY_SHOW_ACTIONBAR_2, SELFCAST, PROXY_STATUS_TEXT ...) and with the values the panel offers. The panel is only read,
-- as tables: none of its functions runs here (run from this addon, one would carry its taint into the panel), and an
-- option is set the way the panel's own code sets it (Blizzard_SettingsDefinitions_*), through the same API: the action
-- bars shown, the modifier keys, several CVars at once (status text, self cast, motion sickness ...), guild invites, the
-- window's size, the character models. Undo puts back everything an option changed.
local Kit = WuxianKit

local L = Kit:Words {
	zhCN = { OPTION = "系统设置选项", FIND = "查找系统设置", SEP = " · ", BOTH = "%s、%s", ON = "开启", OFF = "关闭" },
	enUS = { OPTION = "Settings option", FIND = "Find settings", SEP = " · ", BOTH = "%s and %s", ON = "On", OFF = "Off" },
}

local tune = Kit:Extension("tune")

local function G(key) return type(key) == "string" and type(_G[key]) == "string" and _G[key] or nil end   -- the panel's words

local function CVar(name) return C_CVar.GetCVar(name) end

local function On(name)
	local v = C_CVar.GetCVar(name)
	return v ~= nil and v ~= "" and v ~= "0" and v:lower() ~= "false"
end

local function Set(name, v)
	if type(v) == "boolean" then v = v and "1" or "0" end
	C_CVar.SetCVar(name, tostring(v))
end

local function SaveKeys()
	if SaveBindings and GetCurrentBindingSet then SaveBindings(GetCurrentBindingSet()) end
end

------------------------------------------------------------------------------------------------------------------------
-- the options: type (boolean, number, string), title (the global string the panel shows it by; titleArg formats it),
-- choices ({ value, global string } of a dropdown: what each value means), min / max / step (a slider's), sizes() (the
-- window sizes this monitor offers), get(), set(v), cvars (the CVars it sets: undo puts each back as it was),
-- keep() / restore(kept) (what else undo needs), scope (a tune scope; settings.game by default), check() -> why it is
-- not on this client, reload (takes effect after a reload), window (the window updates after it), gx (the graphics
-- device restarts after it)

local O = {}

local function Add(name, o)
	o.name = name
	O[name] = o
end

-- the action bars 2 to 8 shown; the toggles are kept as last set for ten seconds: the server mirrors them back a moment
-- later, and several set before then would each send an old mask (as the panel keeps them)
local bars, barsAt = nil, 0
for i = 2, 8 do
	Add("PROXY_SHOW_ACTIONBAR_" .. i, { type = "boolean", title = "OPTION_SHOW_ACTION_BAR", titleArg = i,
		check = function()
			if not GetActionBarToggles or not SetActionBarToggles then return "no action bar toggles on this client" end
			if C_GameRules and C_GameRules.IsMultiActionBarVisibilityForced and C_GameRules.IsMultiActionBarVisibilityForced() then
				return "this client shows its action bars itself"
			end
		end,
		get = function() return select(i - 1, GetActionBarToggles()) and true or false end,
		set = function(v)
			if not bars or GetTime() - barsAt > 10 then bars = { GetActionBarToggles() } end
			barsAt = GetTime()
			bars[i - 1] = v and true or false
			SetActionBarToggles(unpack(bars, 1, 7))
		end })
end

-- the modifier keys (the panel's modified-click settings), saved with the key bindings
local KEYS = { { "ALT", "ALT_KEY" }, { "CTRL", "CTRL_KEY" }, { "SHIFT", "SHIFT_KEY" }, { "NONE", "NONE_KEY" } }
for _, m in ipairs({ { "AUTOLOOTTOGGLE", "AUTO_LOOT_KEY_TEXT" }, { "MOUSEOVERCAST", "MOUSEOVER_CAST_KEY" },
	{ "SELFCAST", "AUTO_SELF_CAST_KEY_TEXT" }, { "FOCUSCAST", "FOCUS_CAST_KEY_TEXT" }, { "PICKUPACTION", "PICKUP_ACTION_KEY_TEXT" } }) do
	local action = m[1]
	Add(action, { type = "string", title = m[2], choices = KEYS, scope = "bindings",
		check = function()
			if not GetModifiedClick or not SetModifiedClick or not GetModifiedClick(action) then return "no such key on this client" end
		end,
		get = function() return GetModifiedClick(action) end,
		set = function(v)
			SetModifiedClick(action, v)
			SaveKeys()
		end })
end

Add("PROXY_SELF_CAST", { type = "number", title = "SELF_CAST", scope = "settings.combat", cvars = { "autoSelfCast" },
	choices = { { 1, "NONE" }, { 2, "SELF_CAST_AUTO" }, { 3, "SELF_CAST_KEY_PRESS" }, { 4, "SELF_CAST_AUTO_AND_KEY_PRESS" } },
	get = function()
		local key, auto = GetModifiedClick("SELFCAST") ~= "NONE", On("autoSelfCast")
		if not key then return auto and 2 or 1 end
		return auto and 4 or 3
	end,
	set = function(v)                                       -- a key press without a key takes Alt, as the panel does
		local key = GetModifiedClick("SELFCAST")
		if v == 1 or v == 2 then key = "NONE" elseif key == "NONE" then key = "ALT" end
		Set("autoSelfCast", v == 2 or v == 4)
		SetModifiedClick("SELFCAST", key)
		SaveKeys()
	end,
	keep = function() return GetModifiedClick("SELFCAST") end,
	restore = function(key)
		SetModifiedClick("SELFCAST", key)
		SaveKeys()
	end })

local STATUS = { "NUMERIC", "PERCENT", "BOTH", "NONE" }
Add("PROXY_STATUS_TEXT", { type = "number", title = "STATUSTEXT_LABEL", cvars = { "statusTextDisplay", "statusText" },
	choices = { { 1, "STATUS_TEXT_VALUE" }, { 2, "STATUS_TEXT_PERCENT" }, { 3, "STATUS_TEXT_BOTH" }, { 4, "NONE" } },
	get = function()
		local shown = CVar("statusTextDisplay")
		for i, s in ipairs(STATUS) do
			if shown == s then return i end
		end
		return 4
	end,
	set = function(v)
		Set("statusTextDisplay", STATUS[v])
		Set("statusText", v ~= 4)
	end })

-- the interact key and action targeting: soft targeting with any input, or with the gamepad only
local function Flags() return Enum and Enum.SoftTargetEnableFlags or { Gamepad = 1, Any = 3 } end
local function SoftTarget(name, title, cvar, scope)
	Add(name, { type = "boolean", title = title, scope = scope, cvars = { cvar },
		get = function() return tonumber(CVar(cvar)) == Flags().Any end,
		set = function(v) Set(cvar, v and Flags().Any or Flags().Gamepad) end })
end
SoftTarget("PROXY_ENABLE_INTERACT", "ENABLE_INTERACT_TEXT", "softTargetInteract")
SoftTarget("PROXY_ACTION_TARGETING", "ACTION_TARGETING_OPTION", "softTargetEnemy", "settings.combat")

-- the mouse look and camera follow speeds: yaw, and pitch at a part of it
local function Speed(name, title, yaw, pitch, part)
	Add(name, { type = "number", title = title, min = 90, max = 270, step = 10, cvars = { yaw, pitch },
		get = function() return tonumber(CVar(yaw)) end,
		set = function(v)
			Set(yaw, v)
			Set(pitch, v / part)
		end })
end
Speed("PROXY_MOUSE_LOOK_SPEED", "MOUSE_LOOK_SPEED", "cameraYawMoveSpeed", "cameraPitchMoveSpeed", 2)
Speed("PROXY_CAMERA_SPEED", "AUTO_FOLLOW_SPEED", "cameraYawSmoothSpeed", "cameraPitchSmoothSpeed", 4)

Add("PROXY_SICKNESS", { type = "boolean", title = "MOTION_SICKNESS_CHECKBOX",
	cvars = { "CameraKeepCharacterCentered", "CameraReduceUnexpectedMovement" },
	get = function() return not On("CameraKeepCharacterCentered") and On("CameraReduceUnexpectedMovement") end,
	set = function(v)
		Set("CameraKeepCharacterCentered", not v)
		Set("CameraReduceUnexpectedMovement", v)
	end })

local function Near(v, x) return math.abs((tonumber(v) or -1) - x) < 0.001 end
Add("PROXY_SICKNESS_SHAKE", { type = "number", title = "ADJUST_MOTION_SICKNESS_SHAKE", cvars = { "ShakeStrengthCamera", "ShakeStrengthUI" },
	choices = { { 1, "SHAKE_INTENSITY_NONE" }, { 3, "SHAKE_INTENSITY_REDUCED" }, { 2, "SHAKE_INTENSITY_FULL" } },
	get = function()
		local camera, ui = CVar("ShakeStrengthCamera"), CVar("ShakeStrengthUI")
		if Near(camera, 0) and Near(ui, 0) then return 1 end
		if Near(camera, 1) and Near(ui, 1) then return 2 end
		return 3
	end,
	set = function(v)
		local strength = ({ 0, 1, 0.25 })[v]
		Set("ShakeStrengthCamera", strength)
		Set("ShakeStrengthUI", strength)
	end })

Add("PROXY_TARGET_TOOLTIP", { type = "boolean", title = "TARGET_TOOLTIP_OPTION",
	cvars = { "SoftTargetTooltipEnemy", "SoftTargetTooltipInteract" },
	get = function() return On("SoftTargetTooltipEnemy") and On("SoftTargetTooltipInteract") end,
	set = function(v)
		Set("SoftTargetTooltipEnemy", v)
		Set("SoftTargetTooltipInteract", v)
	end })

local ICONS = { "SoftTargetIconEnemy", "SoftTargetIconInteract", "SoftTargetIconGameObject", "SoftTargetLowPriorityIcons" }
Add("PROXY_INTERACT_ICONS", { type = "number", title = "INTERACT_ICONS_OPTION", cvars = ICONS,
	choices = { { 1, "INTERACT_ICONS_DEFAULT" }, { 2, "INTERACT_ICONS_SHOW_ALL" }, { 3, "INTERACT_ICONS_SHOW_NONE" } },
	get = function()
		local all, none = true, true
		for _, c in ipairs(ICONS) do
			if On(c) then none = false else all = false end
		end
		return all and 2 or none and 3 or 1
	end,
	set = function(v)
		local values = ({ { 0, 1, 0, 0 }, { 1, 1, 1, 1 }, { 0, 0, 0, 0 } })[v]
		for i, c in ipairs(ICONS) do Set(c, values[i]) end
	end })

local NPC = { "UnitNameFriendlySpecialNPCName", "UnitNameHostleNPC", "UnitNameInteractiveNPC", "UnitNameNPC", "ShowQuestUnitCircles" }
Add("PROXY_NPC_NAMES", { type = "number", title = "SHOW_NPC_NAMES", cvars = NPC,
	choices = { { 1, "NPC_NAMES_DROPDOWN_TRACKED" }, { 2, "NPC_NAMES_DROPDOWN_HOSTILE" }, { 3, "NPC_NAMES_DROPDOWN_INTERACTIVE" },
		{ 4, "NPC_NAMES_DROPDOWN_ALL" }, { 5, "NPC_NAMES_DROPDOWN_NONE" } },
	get = function()
		if On("UnitNameNPC") then return 4 end
		local special, hostile = On("UnitNameFriendlySpecialNPCName"), On("UnitNameHostleNPC")
		if special and hostile and On("UnitNameInteractiveNPC") then return 3 end
		if special and hostile then return 2 end
		return special and 1 or 5
	end,
	set = function(v)                                       -- special, hostile, interactive, all NPCs, quest circles
		local values = ({ { 1, 0, 0, 0, 0 }, { 1, 1, 0, 0, 1 }, { 1, 1, 1, 0, 1 }, { 0, 0, 0, 1, 1 }, { 0, 0, 0, 0, 1 } })[v]
		for i, c in ipairs(NPC) do Set(c, values[i]) end
	end })

Add("UNIT_NAMEPLATES_CLASS_COLOR", { type = "number", title = "UNIT_NAMEPLATES_CLASS_COLOR",
	cvars = { "nameplateShowFriendlyClassColor", "nameplateShowClassColor" },
	choices = { { 0, "UNIT_NAMEPLATES_CLASS_COLOR_NONE" }, { 1, "UNIT_NAMEPLATES_CLASS_COLOR_FRIENDLY" },
		{ 2, "UNIT_NAMEPLATES_CLASS_COLOR_ENEMY" }, { 3, { "UNIT_NAMEPLATES_CLASS_COLOR_FRIENDLY", "UNIT_NAMEPLATES_CLASS_COLOR_ENEMY" } } },
	get = function() return (On("nameplateShowFriendlyClassColor") and 1 or 0) + (On("nameplateShowClassColor") and 2 or 0) end,
	set = function(v)
		Set("nameplateShowFriendlyClassColor", v % 2 == 1)
		Set("nameplateShowClassColor", v >= 2)
	end })

Add("PROXY_SELF_HIGHLIGHT", { type = "number", title = "SELF_HIGHLIGHT_OPTION", scope = "settings.combat",
	cvars = { "findYourselfAnywhere", "findYourselfModeCircle", "findYourselfModeOutline", "findYourselfModeIcon" },
	choices = { { 1, "SELF_HIGHLIGHT_MODE_CIRCLE" }, { 2, "SELF_HIGHLIGHT_MODE_OUTLINE" }, { 4, "SELF_HIGHLIGHT_MODE_ICON" },
		{ 3, "SELF_HIGHLIGHT_MODE_CIRCLE_AND_OUTLINE" }, { 5, "SELF_HIGHLIGHT_MODE_CIRCLE_AND_ICON" },
		{ 6, "SELF_HIGHLIGHT_MODE_OUTLINE_AND_ICON" }, { 7, "SELF_HIGHLIGHT_MODE_CIRCLE_OUTLINE_AND_ICON" }, { 0, "OFF" } },
	get = function()
		return (On("findYourselfModeCircle") and 1 or 0) + (On("findYourselfModeOutline") and 2 or 0)
			+ (On("findYourselfModeIcon") and 4 or 0)
	end,
	set = function(v)
		Set("findYourselfAnywhere", v > 0)
		Set("findYourselfModeIcon", v >= 4)
		Set("findYourselfModeOutline", v % 4 >= 2)
		Set("findYourselfModeCircle", v % 2 == 1)
	end })

local function Sources() return Enum and Enum.ExcludedCensorSources or { Friends = 1, Guild = 2 } end
Add("PROXY_CENSOR_MESSAGES", { type = "number", title = "CENSOR_SOURCE_EXCLUDE", cvars = { "excludedCensorSources" },
	choices = { { 1, "CENSOR_SOURCE_EVERYONE" }, { 2, "CENSOR_SOURCE_EXCLUDE_FRIENDS" },
		{ 3, "CENSOR_SOURCE_EXCLUDE_FRIENDS_AND_GUILD" }, { 4, "CENSOR_SOURCE_NO_ONE" } },
	get = function()
		local v, s = tonumber(CVar("excludedCensorSources")), Sources()
		if v == 0 then return 1 end
		if v == s.Friends then return 2 end
		if v == s.Friends + s.Guild then return 3 end
		return 4
	end,
	set = function(v)
		local s = Sources()
		Set("excludedCensorSources", ({ 0, s.Friends, s.Friends + s.Guild, 255 })[v])
	end })

Add("PROXY_BLOCK_GUILD_INVITES", { type = "boolean", title = "BLOCK_GUILD_INVITES",
	check = function()
		if not GetAutoDeclineGuildInvites or not SetAutoDeclineGuildInvites then return "not on this client" end
	end,
	get = function() return GetAutoDeclineGuildInvites() and true or false end,
	set = function(v) SetAutoDeclineGuildInvites(v) end })

Add("PROXY_SOCIAL_LOCATION_VISIBILITY", { type = "boolean", title = "SOCIAL_LOCATION_VISIBILITY_SETTING",
	choices = { { false, "SOCIAL_LOCATION_VISIBILITY_FRIEND_GUILD" }, { true, "SOCIAL_LOCATION_VISIBILITY_FRIEND_GUILD_ALLIES" } },
	check = function()
		if not GetAllowRecentAlliesSeeLocation or not SetAllowRecentAlliesSeeLocation then return "not on this client" end
	end,
	get = function() return GetAllowRecentAlliesSeeLocation() and true or false end,
	set = function(v) SetAllowRecentAlliesSeeLocation(v) end })

-- low-level quests on the minimap: a tracking filter
local function Trivial()
	local filter = Enum and Enum.MinimapTrackingFilter and Enum.MinimapTrackingFilter.TrivialQuests
	if not filter or not (C_Minimap and C_Minimap.GetNumTrackingTypes and C_Minimap.GetTrackingFilter) then return nil end
	for i = 1, C_Minimap.GetNumTrackingTypes() do
		local t = C_Minimap.GetTrackingFilter(i)
		if t and t.filterID == filter then return i, filter end
	end
end
Add("PROXY_TRIVIAL_QUEST_FILTERING", { type = "boolean", title = "SETTINGS_TRIVIAL_QUEST_FILTER",
	check = function() if not Trivial() then return "the minimap tracks no low-level quests on this client" end end,
	get = function() return not C_Minimap.IsFilteredOut(select(2, Trivial())) end,
	set = function(v) C_Minimap.SetTracking((Trivial()), v) end })

Add("PROXY_TRIPLE_BUFFERING", { type = "boolean", title = "TRIPLE_BUFFER", scope = "settings.graphics", gx = true,
	cvars = { "gxMaxFrameLatency" },
	get = function() return tonumber(CVar("gxMaxFrameLatency")) == 3 end,
	set = function(v) Set("gxMaxFrameLatency", v and 3 or 2) end })

-- the window's size, among those the monitor in use offers in the display mode in use
local function Display() return tonumber(CVar("gxMonitor")) or 0, On("gxMaximize") end
local function SizeText(s) return type(s) == "table" and s.x and ("%dx%d"):format(s.x, s.y) or nil end
Add("PROXY_RESOLUTION", { type = "string", title = "WINDOW_SIZE", scope = "settings.graphics", window = true,
	check = function()
		local v = C_VideoOptions
		if not (v and v.GetCurrentGameWindowSize and v.GetGameWindowSizes and v.SetGameWindowSize) then return "not on this client" end
	end,
	sizes = function()
		local out, monitor, full = {}, Display()
		for _, s in ipairs(C_VideoOptions.GetGameWindowSizes(monitor, full) or {}) do out[#out + 1] = SizeText(s) end
		return out
	end,
	get = function() return SizeText(C_VideoOptions.GetCurrentGameWindowSize(Display())) end,
	set = function(v)
		local x, y = v:match("^(%d+)x(%d+)$")
		C_VideoOptions.SetGameWindowSize(tonumber(x), tonumber(y))
	end })

Add("PROXY_CHARACTER_MODELS_TOGGLE", { type = "boolean", title = "CHARACTER_MODELS", scope = "settings.graphics", reload = true,
	choices = { { true, "STANDARD_DEFINITION" }, { false, "HIGH_DEFINITION" } },
	check = function()
		local r = C_GameRules
		if not (r and r.IsSDHDToggleEnabled and r.AccountHasSDEnabled and r.SetSDHDToggleValue and r.IsSDHDToggleEnabled()) then
			return "this client offers no choice of character models"
		end
	end,
	get = function() return C_GameRules.AccountHasSDEnabled() and true or false end,
	set = function(v) C_GameRules.SetSDHDToggleValue(v) end })

------------------------------------------------------------------------------------------------------------------------
-- the panel's other proxies: those that stand for one CVar (tune.cvar.set changes it: a display one updates the window,
-- a graphics quality its details, as the panel's Apply does), and why the rest are the player's to change. An advanced
-- graphics setting names its CVar itself (setting.cvar).

local ALIAS = {
	PROXY_PRIMARY_MONITOR = "gxMonitor", PROXY_DISPLAY_MODE = "gxMaximize", PROXY_RESOLUTION_RENDER_SCALE = "RenderScale",
	PROXY_USE_UI_SCALE = "useUiScale", PROXY_UI_SCALE = "uiscale", PROXY_VERTICAL_SYNC = "vsync",
	PROXY_NOTCHED_DISPLAY_MODE = "NotchedDisplayMode", PROXY_FXAA = "ffxAntiAliasingMode", PROXY_MSAA_ALPHA = "msaaAlphaTest",
	PROXY_CAMERA_FOV = "cameraFov", PROXY_GRAPHICS_API = "gxapi", PROXY_PHYSICS_LEVEL = "physicsLevel",
	PROXY_GX_ADAPTER = "gxAdapter", PROXY_FOREGROUND_FPS_ENABLED = "useMaxFPS", PROXY_FOREGROUND_FPS = "maxFPS",
	PROXY_BACKGROUND_FPS_ENABLED = "useMaxFPSBk", PROXY_BACKGROUND_FPS = "maxFPSBk", PROXY_TARGET_FPS_ENABLED = "useTargetFPS",
	PROXY_TARGET_FPS = "targetFPS", PROXY_RESAMPLE_SHARPNESS = "ResampleSharpness",
	PROXY_OPT_GPU_FEATURES = "GxCompatOptionalGpuFeatures", PROXY_DEVICE_MT = "GxCompatAsyncShaderCompilation",
	PROXY_CMDLIST_MT = "GxCompatCommandListMultiThreading", PROXY_ADV_WORK_SUBMIT = "GxCompatWorkSubmitOptimizations",
	PROXY_MINIMUM_CHARACTER_NAME_SIZE = "WorldTextMinSize", PROXY_QUEST_TEXT_CONTRAST = "questTextContrast",
	PROXY_MOVIE_SUBTITLE_BACKGROUND = "movieSubtitleBackground",
	PROXY_MOVIE_SUBTITLE_BACKGROUND_ALPHA = "movieSubtitleBackgroundAlpha", PROXY_HIGH_RES_TEXTURES = "useHighResTextures",
	UNIT_NAMEPLATES_ENABLE_STACKING = "nameplateStackingTypes", UNIT_NAMEPLATES_INFO_DISPLAY = "nameplateInfoDisplay",
	UNIT_NAMEPLATES_CAST_BAR_DISPLAY = "nameplateCastBarDisplay", UNIT_NAMEPLATES_THREAT_DISPLAY = "nameplateThreatDisplay",
	UNIT_NAMEPLATES_ENEMY_NPC_AURA_DISPLAY = "nameplateEnemyNpcAuraDisplay",
	UNIT_NAMEPLATES_ENEMY_PLAYER_AURA_DISPLAY = "nameplateEnemyPlayerAuraDisplay",
	UNIT_NAMEPLATES_FRIENDLY_PLAYER_AURA_DISPLAY = "nameplateFriendlyPlayerAuraDisplay",
	UNIT_NAMEPLATES_SIMPLIFIED = "nameplateSimplifiedTypes",
}
local NOTE = { PROXY_RESAMPLE_SHARPNESS = "the panel shows it reversed: its slider's top is 0" }

local PANEL = "the player changes it in the Settings panel"
local WHY = {
	PROXY_CHARACTER_SPECIFIC_BINDINGS = "switching between the account's and the character's key bindings loads or "
		.. "deletes a whole set of them: " .. PANEL,
	PROXY_DISABLE_CHAT = "turning chat off asks the player to confirm: " .. PANEL,
	PROXY_PREFERRED_PLAY_LOCALE = "the account's preference, kept on the server: " .. PANEL,
	PROXY_PREFERRED_PLAY_DATACENTER_LOCALITY = "the account's preference, kept on the server: " .. PANEL,
	PROXY_ACCESSIBILITY_FONT_SIZE = "the panel's own text-size code applies it: " .. PANEL,
	PROXY_ANTIALIASING = "the panel works its CVars out from what the graphics card supports: " .. PANEL,
	PROXY_MSAA = "the panel works its CVars out from what the graphics card supports: " .. PANEL,
}

------------------------------------------------------------------------------------------------------------------------
-- the option Setting

local function Label(o)
	local title = G(o.title)
	if title and o.titleArg then
		local ok, text = pcall(string.format, title, o.titleArg)
		title = ok and text or title
	end
	return title or o.name
end

local function ChoiceText(c)
	if type(c[2]) == "table" then return L.BOTH:format(G(c[2][1]) or c[2][1], G(c[2][2]) or c[2][2]) end
	return G(c[2]) or tostring(c[2])
end

local function Choices(o)
	if not o.choices then return nil end
	local out = {}
	for i, c in ipairs(o.choices) do out[i] = { value = c[1], label = ChoiceText(c) } end
	return out
end

local function After(o)                                      -- what the panel's Apply does after it
	if o.window and UpdateWindow then UpdateWindow() end
	if o.gx and RestartGx then RestartGx() end
end

tune:Setting("option", { title = L"OPTION", settle = true,
	doc = "an option of the game's Settings panel that is no single CVar, by the panel's own name for it "
		.. "(PROXY_SHOW_ACTIONBAR_2, SELFCAST, PROXY_STATUS_TEXT ...: tune.setting.find finds it by the words the player "
		.. "reads, with the values it takes)",
	change = "value: what tune.setting.find gives for it: true or false, one of its choices, a number in its range, a "
		.. "window size such as \"1920x1080\"; it is set as the panel sets it, and undo puts back everything it changed",
	key = { name = "string" }, value = "string|number|boolean",
	scope = function(_, k)
		local o = O[k.name]
		return o and o.scope or "settings.game"
	end,
	check = function(_, k)
		local o = O[k.name]
		if not o then
			return ("no option %s (tune.setting.find gives the names; a CVar goes through tune.cvar.set)"):format(k.name)
		end
		return o.check and o.check() or nil
	end,
	normalize = function(_, v, k)
		local o = k and O[k.name]
		if not o then return v end
		if o.type == "boolean" and type(v) ~= "boolean" then
			local s = tostring(v):lower()
			if s == "1" or s == "true" then return true end
			if s == "0" or s == "false" then return false end
		elseif o.type == "number" then
			return tonumber(v) or v
		elseif type(v) == "string" then
			if o.sizes then return (v:lower():gsub("[%s]", ""):gsub("×", "x")) end
			return v:upper()
		end
		return v
	end,
	validate = function(_, k, v)
		local o = O[k.name]
		if o.type == "boolean" then
			if type(v) ~= "boolean" then return ("%s takes true or false"):format(k.name) end
			return nil
		end
		if o.type == "number" then
			if type(v) ~= "number" then return ("%s takes a number"):format(k.name) end
			if o.min and (v < o.min or v > o.max) then return ("%s takes %s to %s"):format(k.name, o.min, o.max) end
		end
		if o.choices then
			for _, c in ipairs(o.choices) do
				if c[1] == v then return nil end
			end
			local list = {}
			for _, c in ipairs(o.choices) do list[#list + 1] = tostring(c[1]) end
			return ("%s takes one of %s (tune.setting.find says what each is)"):format(k.name, table.concat(list, ", "))
		end
		if o.sizes then
			for _, s in ipairs(o.sizes()) do
				if s == v then return nil end
			end
			return ("%s takes a size the monitor offers, as \"1920x1080\" (tune.setting.find lists them)"):format(k.name)
		end
	end,
	get = function(_, k) return O[k.name].get() end,
	set = function(_, k, v)
		local o = O[k.name]
		o.set(v)
		After(o)
	end,
	keep = function(_, k)                                    -- the CVars it sets as they are, and what else it keeps
		local o, kept = O[k.name], { cvars = {} }
		for _, c in ipairs(o.cvars or {}) do kept.cvars[c] = CVar(c) end
		if o.keep then kept.extra = o.keep() end
		return kept
	end,
	restore = function(_, k, v, kept)
		local o = O[k.name]
		if kept and next(kept.cvars or {}) then
			for c, value in pairs(kept.cvars) do C_CVar.SetCVar(c, value) end
			if o.restore and kept.extra ~= nil then o.restore(kept.extra) end
		elseif v ~= nil then
			o.set(v)
		end
		After(o)
	end,
	reload = function(_, k)
		local o = O[k.name]
		return o and o.reload or false
	end,
	label = function(_, k)
		local o = O[k.name]
		return Kit:Escape(o and Label(o) or k.name)
	end,
	format = function(_, v, k)
		local o = k and O[k.name]
		for _, c in ipairs(o and o.choices or {}) do
			if c[1] == v then return Kit:Escape(ChoiceText(c)) end
		end
		if type(v) == "boolean" then return v and L.ON or L.OFF end
		return Kit:Escape(v)
	end,
	info = function(_, k)
		local o = O[k.name]
		if not o then return {} end
		return { label = Label(o), type = o.type, choices = Choices(o), min = o.min, max = o.max, step = o.step,
			sizes = o.sizes and o.sizes() or nil }
	end })

------------------------------------------------------------------------------------------------------------------------
-- reading the panel: its categories (the game's, not addons'), the initializers of each one's list, the settings they
-- show with the words they show them by. Fields only: no method of the panel's is called.

local function IsSetting(v) return type(v) == "table" and type(v.variable) == "string" and type(v.Init) == "function" end

local function Kind(s)
	if CVarSettingMixin and s.Init == CVarSettingMixin.Init then return "cvar" end
	if ProxySettingMixin and s.Init == ProxySettingMixin.Init then return "proxy" end
	if ModifiedClickSettingMixin and s.Init == ModifiedClickSettingMixin.Init then return "modifier" end
	return "other"
end

-- an initializer's settings (a control can show two: a check box with a slider or a dropdown), and the graphics
-- quality section's, by CVar, with the tab each is on (the base one, the raids')
local SHOWN = { { "setting", "name", "tooltip", "options" }, { "cbSetting", "cbLabel", "cbTooltip" },
	{ "sliderSetting", "sliderLabel", "sliderTooltip", "sliderOptions" }, { "dropdownSetting", "dropDownLabel", "dropDownTooltip" } }

local function Controls(init, add)
	local d = type(init) == "table" and rawget(init, "data")
	if type(d) ~= "table" then return end
	for _, f in ipairs(SHOWN) do
		local s = d[f[1]]
		if IsSetting(s) then add(s, d[f[2]], d[f[3]], f[4] and d[f[4]]) end
	end
	for _, t in ipairs({ { "settings", "BASE_GRAPHICS_QUALITY" }, { "raidSettings", "SETTINGS_RAID_GRAPHICS_QUALITY" } }) do
		local list = d[t[1]]
		if type(list) == "table" and not IsSetting(list) then
			local found = {}
			for cvar, s in pairs(list) do
				if IsSetting(s) then found[#found + 1] = { s = s, first = tostring(cvar):find("raphicsQuality$") ~= nil } end
			end
			table.sort(found, function(x, y)                   -- the quality first, then its details
				if x.first ~= y.first then return x.first end
				return x.s.variable < y.s.variable
			end)
			for _, f in ipairs(found) do add(f.s, f.s.name, nil, nil, G(t[2])) end
		end
	end
end

-- every setting the panel shows, in its order: { s, label, tooltip, slider (its options), category }
local function Panel()
	local panel = SettingsPanel
	local list = type(panel) == "table" and rawget(panel, "CategoryList")
	local groups = type(list) == "table" and rawget(list, "groups")
	local layouts = type(panel) == "table" and rawget(panel, "categoryLayouts")
	if type(groups) ~= "table" or type(layouts) ~= "table" then
		error("the game's Settings panel is not there yet (it loads with the world)", 0)
	end
	local addons = Settings and Settings.CategorySet and Settings.CategorySet.AddOns or 2
	local out, seen = {}, {}
	local function Category(c, words)
		local layout = layouts[c]
		for _, init in ipairs(type(layout) == "table" and type(layout.initializers) == "table" and layout.initializers or {}) do
			local tags = {}                                   -- the words the panel's own search finds it by
			local list = type(init) == "table" and rawget(init, "searchTags")
			for _, tag in ipairs(type(list) == "table" and list or {}) do
				if type(tag) == "string" then tags[#tags + 1] = tag end
			end
			Controls(init, function(s, label, tooltip, slider, tab)
				if seen[s.variable] then return end
				seen[s.variable] = true
				out[#out + 1] = { s = s, label = type(label) == "string" and label or type(s.name) == "string" and s.name or nil,
					tooltip = type(tooltip) == "string" and tooltip or nil, slider = type(slider) == "table" and slider or nil,
					category = words, tab = tab, tags = table.concat(tags, "\1") }
			end)
		end
		for _, sub in ipairs(type(c.subcategories) == "table" and c.subcategories or {}) do
			Category(sub, words .. L.SEP .. tostring(sub.name))
		end
	end
	for _, g in ipairs(groups) do
		for _, c in ipairs(type(g.categories) == "table" and g.categories or {}) do
			if c.categorySet ~= addons and g.categorySet ~= addons then
				Category(c, (type(g.groupText) == "string" and (g.groupText .. L.SEP) or "") .. tostring(c.name))
			end
		end
	end
	return out
end

-- one setting as the agent reads it: label, category, name and set (the capability and the name it takes), value, and
-- what else tells how: type, choices, min / max / step, inverted (a box ticked when the CVar is 0), note; or why it is
-- the player's to change
local function Entry(e)
	local s, kind = e.s, Kind(e.s)
	local out = { label = e.label or s.variable, category = e.category, tab = e.tab, type = s.variableType }
	local o = O[s.variable]
	local cvar = kind == "cvar" and s.variable or ALIAS[s.variable] or (kind == "proxy" and type(s.cvar) == "string" and s.cvar)
	if o then
		out.name, out.set = s.variable, "tune.option.set"
		local why = o.check and o.check()
		if why then
			out.set, out.why = nil, why
		else
			local ok, v = pcall(o.get)
			if ok then out.value = v end
			out.choices, out.min, out.max, out.step = Choices(o), o.min, o.max, o.step
			if o.sizes then out.sizes = o.sizes() end
		end
	elseif cvar then
		out.name, out.set = cvar, "tune.cvar.set"
		if cvar ~= s.variable then out.panel = s.variable end
		local value, why = tune.CVarState(cvar)
		if why or value == nil then
			out.set, out.why = nil, why or "no such setting on this client"
		else
			out.value = value
		end
		if s.valueTransformer and s.variableType == "boolean" then out.inverted = true end
		out.note = NOTE[s.variable]
	else
		out.name, out.why = s.variable, WHY[s.variable] or ("the panel sets it with its own code: " .. PANEL)
	end
	if e.slider and tonumber(e.slider.minValue) and tonumber(e.slider.maxValue) then
		out.min, out.max = out.min or e.slider.minValue, out.max or e.slider.maxValue
		local steps = tonumber(e.slider.steps)
		if not out.step and steps and steps > 0 then out.step = (e.slider.maxValue - e.slider.minValue) / steps end
	end
	return out
end

tune:See("setting.find", { title = L"FIND", args = { text = "string?", limit = "number?" },
	doc = "the game's Settings panel (its own categories, not addons'): the options whose words hold every word of `text` "
		.. "(no case; the words the player reads there, in the client's language, its category, its name, or the words the "
		.. "panel's own search goes by), those found by their own words first; all without "
		.. "text: {total, settings = [{label, category, tab (the graphics quality tab: base or raids), name, set, value, "
		.. "type, choices [{value, label}], min, max, step, sizes, inverted, panel, note, why}]} in the panel's order; at "
		.. "most `limit` (20, up to 100). set is how to "
		.. "change it: \"tune.cvar.set\" with name (a CVar; inverted: its box is ticked when the CVar is 0; panel: the "
		.. "panel's own name for it) or \"tune.option.set\" with name and a value from choices, min..max or sizes; no set: "
		.. "why says why it is the player's to change. Key bindings: tune.binding.find",
	run = function(_, a)
		local words = {}
		for w in (a.text or ""):lower():gmatch("%S+") do words[#words + 1] = w end
		local limit = math.max(1, math.min(tonumber(a.limit) or 20, 100))
		local function Has(hay)
			for _, w in ipairs(words) do
				if not hay:find(w, 1, true) then return false end
			end
			return true
		end
		local named, tagged = {}, {}                         -- found by its own words first, by tooltip or tags after
		for _, e in ipairs(Panel()) do
			local o = O[e.s.variable]
			local own = table.concat({ e.label or "", e.category or "", e.s.variable, ALIAS[e.s.variable] or "",
				type(e.s.cvar) == "string" and e.s.cvar or "", o and Label(o) or "" }, "\1"):lower()
			if Has(own) then
				named[#named + 1] = e
			elseif Has(own .. "\1" .. table.concat({ e.tooltip or "", e.tab or "", e.tags }, "\1"):lower()) then
				tagged[#tagged + 1] = e
			end
		end
		local found = {}
		for _, list in ipairs({ named, tagged }) do
			for _, e in ipairs(list) do
				if #found < limit then found[#found + 1] = Entry(e) end
			end
		end
		return { total = #named + #tagged, settings = found }
	end })
