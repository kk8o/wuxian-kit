"""A mock WoW client for WuxianKit under Lua 5.1 (lupa): BASE is the client itself (time and timers, frames and their
events, the chat frame, the error handler), KIT what the core and its extensions use of the WoW API (settings, chat,
addon messages, addon management over a list of installed addons, combat, items and spells, secret values; key
bindings, macros, Edit Mode, talents, gear, bags, C_EncodingUtil and what Sense reads, each as the client behaves: a
macro, a layout put in use, a talent loadout, gear show a moment later). Session is
one UI session: WuxianKit loaded from this repo, the fixtures in tests/fixtures/ installed beside it.

tests/test_agent.py runs KIT inside 无限工坊's own mock client (its tests.support.wowmock) instead, with the real WoWBridge."""
import shutil
import tempfile
from pathlib import Path

try:
    import lupa.lua51 as lupa
except ImportError:      # pragma: no cover
    lupa = None

REPO = Path(__file__).resolve().parents[1]
KIT_DIR = REPO / "WuxianKit"
FIXTURES = REPO / "tests" / "fixtures"

BASE = r"""
local py = ...
local clock = py.t0
local timers, frames = {}, {}
function GetTime() return clock end
function time(t) if t then return os.time(t) end return math.floor(clock) end
date = os.date
C_Timer = {}
function C_Timer.After(d, fn) timers[#timers + 1] = { t = clock + d, fn = fn } end
function C_Timer.NewTicker(d, fn)
	local tk = { t = clock + d, fn = fn, every = d }
	timers[#timers + 1] = tk
	return { Cancel = function() tk.dead = true end }
end
function __run(dt)
	local target = clock + dt
	while true do
		local best, bi
		for i, tm in ipairs(timers) do
			if not tm.dead and (best == nil or tm.t < best.t) then best, bi = tm, i end
		end
		if not best or best.t > target then break end
		clock = best.t
		if best.every then best.t = best.t + best.every else table.remove(timers, bi) end
		best.fn()
	end
	clock = target
end
function __load(src, name) local f, err = loadstring(src, name) return f, err end
function __dump(v)
	if type(v) == "table" then
		local parts = {}
		for k, x in pairs(v) do
			local key = type(k) == "string" and ("[%q]"):format(k) or ("[" .. tostring(k) .. "]")
			parts[#parts + 1] = key .. "=" .. __dump(x)
		end
		return "{" .. table.concat(parts, ",") .. "}"
	elseif type(v) == "string" then
		return ("%q"):format(v)
	end
	return tostring(v)
end

local Region = {}
Region.__index = Region
local REGIONS = { Texture = true, FontString = true }
local function new(kind, parent)
	local r = setmetatable({ kind = kind, parent = parent, shown = true, scripts = {}, events = {} }, Region)
	if parent then
		local list = REGIONS[kind] and "__regions" or "__kids"
		parent[list] = parent[list] or {}
		table.insert(parent[list], r)
	end
	return r
end
for _, m in ipairs({ "SetFrameStrata", "SetFrameLevel", "SetToplevel", "SetClampedToScreen", "EnableMouse", "SetMovable",
	"RegisterForDrag", "RegisterForClicks", "ClearAllPoints", "SetAllPoints", "SetJustifyH", "SetJustifyV", "SetWordWrap",
	"SetTexture", "SetTexCoord", "SetPushedTextOffset", "SetHighlightTexture", "SetIgnoreParentScale", "SetClipsChildren",
	"EnableMouseWheel", "SetAutoFocus", "SetFontObject", "SetTextInsets", "SetMaxLetters", "Raise" }) do
	Region[m] = function() end
end
function Region:SetSize(w, h) self.w, self.h = w, h end
function Region:SetWidth(w) self.w = w end
function Region:SetHeight(h) self.h = h end
function Region:GetWidth() return self.w or 0 end
function Region:GetHeight() return self.h or 0 end
function Region:GetLeft() return self.left or 100 end
function Region:GetTop() return self.top or 700 end
function Region:GetBottom() return self.bottom or 600 end
function Region:SetPoint(...) self.point = { ... } end
function Region:Show()
	local was = self.shown
	self.shown = true
	if not was and self.scripts.OnShow then self.scripts.OnShow(self) end
end
function Region:Hide()
	local was = self.shown
	self.shown = false
	if was and self.scripts.OnHide then self.scripts.OnHide(self) end
end
function Region:SetShown(v) if v then self:Show() else self:Hide() end end
function Region:IsShown() return self.shown end
function Region:RegisterEvent(e) self.events[e] = true end
function Region:UnregisterEvent(e) self.events[e] = nil end
function Region:UnregisterAllEvents() self.events = {} end
function Region:SetScript(k, fn) self.scripts[k] = fn end
function Region:GetScript(k) return self.scripts[k] end
function Region:CreateTexture() return new("Texture", self) end
function Region:SetColorTexture(r, g, b, a) self.rgb = { r, g, b, a } end
function Region:SetVertexColor() end
function Region:CreateFontString() return new("FontString", self) end
function Region:SetText(t) self.text = t end
function Region:GetText() return self.text end
function Region:SetTextColor(r, g, b, a) self.color = { r, g, b, a } end
function Region:GetStringHeight() return 14 end
function Region:SetFontString(fs) self.fontString = fs end
function Region:SetEnabled(v) self.enabled = v and true or false end
function Region:IsEnabled() return self.enabled ~= false end
function Region:SetChecked(v) self.checked = v and true or false end
function Region:GetChecked() return self.checked end
function Region:StartMoving() end
function Region:SetScrollChild(child) self.scrollChild = child end
function Region:HasFocus() return self.focus or false end
function Region:SetAlpha(a) self.alpha = a end
function Region:GetStringWidth() return #(self.text or "") * 7 end
function Region:IsVisible()
	local f = self
	while f do
		if not f.shown then return false end
		f = f.parent
	end
	return true
end
function Region:SetFocus() self.focus = true end
function Region:ClearFocus()
	local was = self.focus
	self.focus = false
	if was and self.scripts.OnEditFocusLost then self.scripts.OnEditFocusLost(self) end
end
function Region:SetVerticalScroll(v) self.scrollTop = v end
function Region:GetVerticalScroll() return self.scrollTop or 0 end
function Region:StopMovingOrSizing() end
function Region:GetObjectType() return self.kind end
function Region:GetName() return self.__name end
-- a click: nothing on a disabled button; a check button turns over first (as in the client)
function Region:Click(which)
	if self.enabled == false then return end
	if self.kind == "CheckButton" then self.checked = not self.checked end
	if self.scripts.OnClick then self.scripts.OnClick(self, which or "LeftButton") end
end

UIParent = new("Frame")
UISpecialFrames = {}
tinsert = table.insert
__locale = "enUS"
function GetLocale() return __locale end
function CreateFrame(kind, name, parent)
	local f = new(kind, parent)
	if name then _G[name], f.__name = f, name end
	frames[#frames + 1] = f
	return f
end
function __fire(event, ...)
	for _, f in ipairs(frames) do
		if f.events[event] and f.scripts.OnEvent then f.scripts.OnEvent(f, event, ...) end
	end
end
DEFAULT_CHAT_FRAME = { AddMessage = function(_, msg) py.chat(msg) end }
SlashCmdList = {}
__errors = {}
local errorHandler = function(msg) __errors[#__errors + 1] = tostring(msg) end
function geterrorhandler() return errorHandler end
function print(...) py.chat(table.concat({ ... }, " ")) end
C_AddOns = {}
"""

KIT = r"""
local py = ...
-- combat: __combat(true / false) fires the events as the client does
local combat = false
function InCombatLockdown() return combat end
function __combat(on)
	combat = on
	__fire(on and "PLAYER_REGEN_DISABLED" or "PLAYER_REGEN_ENABLED")
end

-- secret values: a string starting with "<secret>" counts as one
function issecretvalue(v) return type(v) == "string" and v:sub(1, 8) == "<secret>" end

-- settings
__cvars = {
	nameplateShowAll = { value = "0", default = "0", category = 4, help = "If true, nameplates are shown all the time." },
	nameplateMaxDistance = { value = "41", default = "41", category = 4, help = "The max distance to show nameplates." },
	Sound_MasterVolume = { value = "1.0", default = "1.0", category = 7, help = "Master volume (0.0 to 1.0)" },
	graphicsQuality = { value = "3", default = "3", category = 1, help = "Graphics quality" },
	secureThing = { value = "1", default = "1", category = 4, help = "a secure one", secure = true },
	readOnlyThing = { value = "1", default = "1", category = 2, help = "a read-only one", readOnly = true },
	stubborn = { value = "a", default = "a", category = 4, help = "the client keeps its value", keep = true },
	nameplateClamped = { value = "41", default = "41", category = 4, help = "the client clamps it at 60", max = 60 },
}
local function cv(name)
	for k, c in pairs(__cvars) do
		if k:lower() == tostring(name):lower() then return c end
	end
end
C_CVar = {
	GetCVarInfo = function(name)
		local c = cv(name)
		if not c then return nil end
		return c.value, c.default, false, false, c.locked or false, c.secure or false, c.readOnly or false
	end,
	GetCVar = function(name) local c = cv(name) return c and c.value end,
	SetCVar = function(name, value)
		local c = cv(name)
		if not c or c.secure or c.readOnly then return false end
		if c.max and tonumber(value) and tonumber(value) > c.max then
			c.value = tostring(c.max)
		elseif not c.keep then
			c.value = tostring(value)
		end
		return true
	end,
}
Enum = Enum or {}
Enum.ConsoleCategory = { Debug = 0, Graphics = 1, Console = 2, Combat = 3, Game = 4, Default = 5, Net = 6, Sound = 7 }
Enum.ConsoleCommandType = { Cvar = 0, Command = 1 }
function ConsoleGetAllCommands()
	local out = { { command = "reloadui", help = "reload", category = 2, commandType = 1 } }
	for k, c in pairs(__cvars) do
		out[#out + 1] = { command = k, help = c.help, category = c.category, commandType = 0 }
	end
	return out
end

-- chat
__sent, __addon_sent, __lockdown, __throttle = {}, {}, false, 0
C_ChatInfo = {
	SendChatMessage = function(text, chatType, lang, target)
		__sent[#__sent + 1] = { text = text, type = chatType, target = target }
	end,
	InChatMessagingLockdown = function() return __lockdown end,
	SendAddonMessage = function(prefix, text, channel, target)
		if __throttle > 0 then
			__throttle = __throttle - 1
			return 3
		end
		__addon_sent[#__addon_sent + 1] = { prefix = prefix, text = text, channel = channel, target = target }
		return 0
	end,
	RegisterAddonMessagePrefix = function() return true end,
}
__guid = "Player-1-00000001"      -- the character playing (a test logs in as another by setting it)
function UnitGUID(unit) return unit == "player" and __guid or nil end
__group = nil                     -- the party beside the player: { { name, class, level, role } }
local function Member(unit)
	local n = type(unit) == "string" and unit:match("^party(%d)$")
	return n and __group and __group[tonumber(n)] or nil
end
-- a character's name has two parts on this client: UnitName gives them as name and second value, GetUnitName whole
__surname = "Forever"
function UnitName(unit)
	if unit == "player" then return "Wuxian", __surname end
	local m = Member(unit)
	return m and m.name or nil
end
function GetUnitName(unit, whole)
	local name, second = UnitName(unit)
	if name and whole and second and second ~= "" then return name .. " " .. second end
	return name
end
function Ambiguate(name) return (name:gsub("%-.*$", "")) end

-- items and spells: an item is known once asked for
__items = { [7166] = { name = "Copper Dagger" } }
C_Item = {
	GetItemInfo = function(id)
		local i = __items[id]
		if i and i.known then return i.name, ("|cffffffff|Hitem:%d::::::::1:::::::|h[%s]|h|r"):format(id, i.name) end
	end,
	RequestLoadItemDataByID = function(id) if __items[id] then __items[id].known = true end end,
}
C_Spell = { GetSpellLink = function(id) return ("|cff71d5ff|Hspell:%d:0|h[Spell %d]|h|r"):format(id, id) end }

-- the installed addons: { name, title, meta = { [field] = value }, loaded, disabled }; LoadAddOn runs an addon's files
__installed = __installed or {}
local function addon(which)
	if type(which) == "number" then return __installed[which] end
	for _, a in ipairs(__installed) do
		if a.name == which then return a end
	end
end
C_AddOns.GetNumAddOns = function() return #__installed end
C_AddOns.GetAddOnInfo = function(which)
	local a = addon(which)
	if not a then return nil end
	return a.name, a.title or a.name, a.notes or "", not a.disabled, a.disabled and "DISABLED" or "DEMAND_LOADED", "INSECURE"
end
C_AddOns.GetAddOnMetadata = function(which, field)
	local a = addon(which)
	return a and a.meta[field] or nil
end
C_AddOns.IsAddOnLoaded = function(which)
	local a = addon(which)
	return a and a.loaded or false, a and a.loaded or false
end
-- a character is its GUID, as the client has it: another string matches none (asked, every addon is on)
local function ThisCharacter(character) return character == nil or character == UnitGUID("player") end
C_AddOns.GetAddOnEnableState = function(which, character)
	local a = addon(which)
	if not ThisCharacter(character) then return a and 2 or 0 end
	return (a and not a.disabled) and 2 or 0
end
C_AddOns.LoadAddOn = function(name)
	local a = addon(name)
	if not a then return false, "MISSING" end
	if a.loaded then return true end
	if a.disabled then return false, "DISABLED" end
	py.load_addon(name)
	a.loaded = true
	__fire("ADDON_LOADED", name)
	return true
end
C_AddOns.DoesAddOnExist = function(which) return addon(which) ~= nil end
C_AddOns.EnableAddOn = function(which, character)
	local a = addon(which)
	if a and ThisCharacter(character) then a.disabled = false end
end
C_AddOns.DisableAddOn = function(which, character)
	local a = addon(which)
	if a and ThisCharacter(character) then a.disabled = true end
end
C_AddOns.SaveAddOns = function() __addonsSaved = (__addonsSaved or 0) + 1 end

local function Deep(v)
	if type(v) ~= "table" then return v end
	local t = {}
	for k, x in pairs(v) do t[k] = Deep(x) end
	return t
end

local function ItemLink(id, name) return ("|cffffffff|Hitem:%d::::::::1:::::::|h[%s]|h|r"):format(id, name) end

-- key bindings: __bindings[key] = command; the client's list of commands (GetBinding) in its order
__bindings = { ["1"] = "ACTIONBUTTON1", ["2"] = "ACTIONBUTTON2", M = "TOGGLEWORLDMAP", W = "MOVEFORWARD" }
__bindingList = { { "HEADER_MOVEMENT", "BINDING_HEADER_MOVEMENT" }, { "MOVEFORWARD", "BINDING_HEADER_MOVEMENT" },
	{ "HEADER_ACTIONBAR", "BINDING_HEADER_ACTIONBAR" }, { "ACTIONBUTTON1", "BINDING_HEADER_ACTIONBAR" },
	{ "ACTIONBUTTON2", "BINDING_HEADER_ACTIONBAR" }, { "TOGGLEWORLDMAP", "BINDING_HEADER_INTERFACE" } }
BINDING_HEADER_MOVEMENT, BINDING_HEADER_ACTIONBAR, BINDING_HEADER_INTERFACE = "Movement Keys", "Action Bar", "Interface Panel"
BINDING_NAME_MOVEFORWARD, BINDING_NAME_ACTIONBUTTON1 = "Move Forward", "Action Button 1"
BINDING_NAME_ACTIONBUTTON2, BINDING_NAME_TOGGLEWORLDMAP = "Action Button 2", "Open World Map"
__bindingSaves = 0
function GetBindingAction(key) return __bindings[key] or "" end
function SetBinding(key, command)
	if type(key) ~= "string" or key == "" then return false end
	__bindings[key] = command
	return true
end
function SaveBindings() __bindingSaves = __bindingSaves + 1 end
function GetCurrentBindingSet() return 1 end
function GetNumBindings() return #__bindingList end
function GetBindingKey(command)
	local keys = {}
	for k, c in pairs(__bindings) do
		if c == command then keys[#keys + 1] = k end
	end
	table.sort(keys)
	return unpack(keys)
end
function GetBinding(i)
	local b = __bindingList[i]
	if b then return b[1], b[2], GetBindingKey(b[1]) end
end

-- macros: the account's numbered 1.., the character's 121..; the client makes and changes one a moment later (a
-- placeholder first), firing UPDATE_MACROS
__macros = { account = { { name = "reload", icon = 134400, body = "/reload\n" } }, character = {} }
local function SortMacros(list) table.sort(list, function(x, y) return x.name:lower() < y.name:lower() end) end
local function MacroAt(i)
	i = tonumber(i) or 0
	if i >= 121 then return __macros.character[i - 120], __macros.character, i - 120 end
	return __macros.account[i], __macros.account, i
end
local function Soon(fn) C_Timer.After(0.03, function() fn() __fire("UPDATE_MACROS") end) end
function GetNumMacros() return #__macros.account, #__macros.character end
function GetMacroIndexByName(name)
	for i, m in ipairs(__macros.account) do if m.name == name then return i end end
	for i, m in ipairs(__macros.character) do if m.name == name then return 120 + i end end
	return 0
end
-- a question-mark macro shows the icon of the spell it casts (here 135907 for any /cast); the icon it keeps is what
-- C_Macro.GetSelectedMacroIcon gives
function GetMacroInfo(i)
	local m = MacroAt(i)
	if m then return m.name, m.icon == 134400 and m.body:find("/cast") and 135907 or m.icon, m.body end
end
C_Macro = { GetSelectedMacroIcon = function(i) local m = MacroAt(i) return m and m.icon end }
-- the action bars: slot -> { kind, id }
__actions = {}
function GetActionInfo(slot) local a = __actions[slot] if a then return a[1], a[2] end end
function GetMacroBody(i)
	local m = MacroAt(i)
	return m and m.body
end
function CreateMacro(name, icon, body, perCharacter)
	local list = perCharacter and __macros.character or __macros.account
	local m = { name = "placeholder", icon = 134400, body = "" }
	list[#list + 1] = m
	SortMacros(list)
	Soon(function()
		m.name, m.icon, m.body = name, icon, body
		SortMacros(list)
	end)
	for i, x in ipairs(list) do
		if x == m then return (perCharacter and 120 or 0) + i end
	end
end
function EditMacro(i, name, icon, body)
	local m, list = MacroAt(i)
	if not m then return nil end
	Soon(function()
		m.name, m.icon, m.body = name or m.name, icon or m.icon, body or m.body
		SortMacros(list)
	end)
	return i
end
function DeleteMacro(i)
	local m, list, j = MacroAt(i)
	if m then
		table.remove(list, j)
		__fire("UPDATE_MACROS")
	end
end

-- Edit Mode: the client's presets, then the player's layouts; the layout put in use shows a moment later
Enum.EditModeLayoutType = { Preset = 0, Account = 1, Character = 2, Override = 3 }
__presets = { { layoutName = "Modern", layoutType = 0, systems = {} }, { layoutName = "Classic", layoutType = 0, systems = {} } }
__editMode = { activeLayout = 3, layouts = { { layoutName = "Mine", layoutType = 1, systems = { { system = 3, systemIndex = 5,
	anchorInfo = { point = "TOPLEFT", relativeTo = "UIParent", relativePoint = "TOPLEFT", offsetX = 20, offsetY = -200 },
	settings = {}, isInDefaultPosition = true } } } } }
EditModePresetLayoutManager = { GetCopyOfPresetLayouts = function() return Deep(__presets) end }
C_EditMode = {
	GetLayouts = function() return Deep(__editMode) end,
	SaveLayouts = function(info) __editMode = Deep(info) end,
	SetActiveLayout = function(i) C_Timer.After(0.05, function() __editMode.activeLayout = i end) end,
	OnLayoutAdded = function() end,
	OnLayoutDeleted = function() __editMode.activeLayout = 1 end,     -- the client's first preset, as measured
	IsValidLayoutName = function(name) return type(name) == "string" and name ~= "" and #name <= 32 end,
	ConvertLayoutInfoToString = function(info)
		local copy = Deep(info)
		copy.layoutName, copy.layoutType = nil, nil
		return "EM1:" .. __dump(copy)
	end,
	ConvertStringToLayoutInfo = function(text)
		if type(text) ~= "string" or text:sub(1, 4) ~= "EM1:" then return nil end
		local f = loadstring("return " .. text:sub(5))
		local ok, t = pcall(f or error)
		return ok and type(t) == "table" and t or nil
	end,
}

-- talent loadouts of the current specialization; loading one takes a moment
Enum.LoadConfigResult = { Error = 0, NoChangesNecessary = 1, LoadInProgress = 2, Ready = 3 }
__talents = { spec = 1484, loadouts = { [101] = "Leveling", [102] = "Dungeons" }, selected = 101 }
PlayerUtil = { GetCurrentSpecID = function() return __talents.spec end }
C_ClassTalents = {
	GetConfigIDsBySpecID = function()
		local ids = {}
		for id in pairs(__talents.loadouts) do ids[#ids + 1] = id end
		table.sort(ids)
		return ids
	end,
	GetLastSelectedSavedConfigID = function() return __talents.selected end,
	CanEditTalents = function() return true, "" end,
	LoadConfig = function(id)
		if not __talents.loadouts[id] then return Enum.LoadConfigResult.Error, "no such loadout" end
		if id == __talents.selected then return Enum.LoadConfigResult.NoChangesNecessary end
		return Enum.LoadConfigResult.LoadInProgress   -- which loadout is in use is the talent window's to say (below)
	end,
	UpdateLastSelectedSavedConfigID = function(spec, id) C_Timer.After(0.5, function() __talents.selected = id end) end,
}
C_Traits = {
	GetConfigInfo = function(id)
		local name = __talents.loadouts[id]
		return name and { ID = id, name = name } or nil
	end,
	GenerateImportString = function(id) return "TALENTS" .. id end,
}

-- what is worn (slot -> item link) and the equipment sets; putting one on, or an item, takes a moment
__worn = { [1] = ItemLink(100, "Cap"), [5] = ItemLink(101, "Shirt") }
__gearSets = { [0] = { name = "Healing", icon = 134400, items = { [1] = ItemLink(200, "Hood"), [5] = ItemLink(201, "Robe") } } }
function GetInventoryItemLink(unit, slot) if unit == "player" then return __worn[slot] end end
C_Item.EquipItemByName = function(link, slot) C_Timer.After(0.1, function() __worn[slot] = link end) end
C_EquipmentSet = {
	CanUseEquipmentSets = function() return true end,
	GetEquipmentSetIDs = function()
		local ids = {}
		for id in pairs(__gearSets) do ids[#ids + 1] = id end
		table.sort(ids)
		return ids
	end,
	GetEquipmentSetID = function(name)
		for id, set in pairs(__gearSets) do
			if set.name == name then return id end
		end
		return nil
	end,
	GetEquipmentSetInfo = function(id)
		local set = __gearSets[id]
		if not set then return nil end
		local n, on = 0, 0
		for slot, link in pairs(set.items) do
			n = n + 1
			if __worn[slot] == link then on = on + 1 end
		end
		return set.name, set.icon, id, n == on, n, on, n - on, 0, 0
	end,
	UseEquipmentSet = function(id)
		local set = __gearSets[id]
		if not set then return false end
		C_Timer.After(0.2, function()
			for slot, link in pairs(set.items) do __worn[slot] = link end
		end)
		return true
	end,
	CreateEquipmentSet = function(name, icon)                        -- a moment later, as the client does
		local items = {}
		for slot, link in pairs(__worn) do items[slot] = link end
		C_Timer.After(0.1, function()
			local id = 0
			while __gearSets[id] do id = id + 1 end
			__gearSets[id] = { name = name, icon = icon or 134400, items = items }
			if __gearTakenBack then C_Timer.After(0.3, function() __gearSets[id] = nil end) end   -- as seen once
		end)
	end,
	DeleteEquipmentSet = function(id) __gearSets[id] = nil end,
}

-- the bags: bag -> { size, items = { [slot] = info } }
NUM_BAG_SLOTS, NUM_TOTAL_EQUIPPED_BAG_SLOTS = 4, 5
__bags = { [0] = { size = 16, items = {
		[1] = { itemID = 7166, stackCount = 1, hyperlink = ItemLink(7166, "Copper Dagger"), quality = 1 },
		[2] = { itemID = 2589, stackCount = 12, hyperlink = ItemLink(2589, "Linen Cloth"), quality = 1 },
		[3] = { itemID = 2589, stackCount = 8, hyperlink = ItemLink(2589, "Linen Cloth"), quality = 1 } } },
	[1] = { size = 6, items = {} } }
__sorts = 0
C_Container = {
	GetContainerNumSlots = function(bag)
		local b = __bags[bag]
		return b and b.size or 0
	end,
	GetContainerNumFreeSlots = function(bag)
		local b = __bags[bag]
		if not b then return 0, 0 end
		local used = 0
		for _ in pairs(b.items) do used = used + 1 end
		return b.size - used, 0
	end,
	GetContainerItemInfo = function(bag, slot)
		local b = __bags[bag]
		local i = b and b.items[slot]
		if i then return { itemID = i.itemID, stackCount = i.stackCount, hyperlink = i.hyperlink, quality = i.quality } end
	end,
	SortBags = function() __sorts = __sorts + 1 end,
}

-- C_EncodingUtil: a round trip of the same shape (Lua literals for CBOR, a mark for compression, hex for base64)
C_EncodingUtil = {
	SerializeCBOR = function(v) return __dump(v) end,
	DeserializeCBOR = function(text)
		local f = loadstring("return " .. text)
		if not f then error("not CBOR") end
		return f()
	end,
	CompressString = function(text) return "Z" .. text end,
	DecompressString = function(text)
		if text:sub(1, 1) ~= "Z" then error("not compressed") end
		return text:sub(2)
	end,
	EncodeBase64 = function(text) return (text:gsub(".", function(c) return ("%02x"):format(c:byte()) end)) end,
	DecodeBase64 = function(text)
		if #text % 2 == 1 or text:find("[^%x]") then error("not base64") end
		return (text:gsub("%x%x", function(h) return string.char(tonumber(h, 16)) end))
	end,
}

-- the character and what Sense reads of it: where it is, its quests, professions, reputations, currencies, group
__player = { level = 8, class = { "Priest", "PRIEST" }, race = "Night Elf", faction = "Alliance", xp = 190, xpMax = 5400,
	money = 480, itemLevel = 9.46 }
function UnitLevel(unit)
	if unit == "player" then return __player.level end
	local m = Member(unit)
	return m and m.level
end
function UnitClass(unit)
	if unit == "player" then return unpack(__player.class) end
	local m = Member(unit)
	if m then return m.class, m.class end
end
function UnitRace(unit) if unit == "player" then return __player.race, "NightElf" end end
function UnitFactionGroup(unit) if unit == "player" then return __player.faction, __player.faction end end
function UnitXP() return __player.xp end
function UnitXPMax() return __player.xpMax end
function GetXPExhaustion() return nil end
function GetMoney() return __player.money end
function GetAverageItemLevel() return __player.itemLevel, __player.itemLevel end
function GetRealmName() return "Forever" end
function GetGuildInfo(unit) if unit == "player" then return "Wuxian Guild", "Member", 3 end end
function IsResting() return false end
function UnitHealth() return "<secret>" end
function UnitGroupRolesAssigned(unit)
	local m = Member(unit)
	return m and m.role or "NONE"
end
function UnitIsConnected() return true end
function UnitIsGroupLeader(unit) return unit == "player" end
function IsInGroup() return __group ~= nil end
function IsInRaid() return false end
function GetNumGroupMembers() return __group and #__group + 1 or 0 end
C_SpecializationInfo = {
	GetSpecialization = function() return 1 end,
	GetSpecializationInfo = function() return 1484, "Holy" end,
}
C_Map = {
	GetBestMapForUnit = function() return 2521 end,
	GetMapInfo = function(id) return { mapID = id, name = "Zephyr Isle" } end,
	GetPlayerMapPosition = function() return { GetXY = function() return 0.41847, 0.62278 end } end,
}
function GetZoneText() return "Zephyr Isle" end
function GetSubZoneText() return "" end
function IsInInstance() return false, "none" end
function GetInstanceInfo() return "Zephyr Isle", "none", 0, "", 5, 0, false, 2521 end
__quests = {
	{ title = "Zephyr Isle", isHeader = true },
	{ title = "Healing Herbs", questID = 3001, level = 7,
		objectives = { { text = "Peacebloom: 3/5", finished = false, numFulfilled = 3, numRequired = 5 } } },
	{ title = "A Letter", questID = 3002, level = 8, complete = true, objectives = {} },
}
C_QuestLog = {
	GetNumQuestLogEntries = function() return #__quests, 2 end,
	GetInfo = function(i)
		local q = __quests[i]
		if q then return { title = q.title, questID = q.questID, level = q.level, isHeader = q.isHeader or false } end
	end,
	IsComplete = function(id)
		for _, q in ipairs(__quests) do
			if q.questID == id then return q.complete or false end
		end
		return false
	end,
	GetQuestObjectives = function(id)
		for _, q in ipairs(__quests) do
			if q.questID == id then return q.objectives end
		end
		return {}
	end,
}
__professions = { [1] = { "Leatherworking", 136247, 37, 75, 0, 0, 165 }, [2] = { "Skinning", 134366, 73, 75, 0, 0, 393 },
	[4] = { "Fishing", 136245, 1, 75, 0, 0, 356 } }
function GetProfessions() return 1, 2, nil, 4, nil end
function GetProfessionInfo(i)
	local p = __professions[i]
	if p then return unpack(p) end
end
FACTION_STANDING_LABEL4, FACTION_STANDING_LABEL5 = "Neutral", "Friendly"
__factions = { { name = "Alliance", factionID = 469, isHeader = true },
	{ name = "Darnassus", factionID = 69, reaction = 5, currentStanding = 4200, currentReactionThreshold = 3000,
		nextReactionThreshold = 9000, isWatched = true },
	{ name = "Stormwind", factionID = 72, reaction = 4, currentStanding = 100, currentReactionThreshold = 0,
		nextReactionThreshold = 3000 } }
C_Reputation = {
	GetNumFactions = function() return #__factions end,
	GetFactionDataByIndex = function(i) return __factions[i] end,
}
C_CurrencyInfo = {
	GetCurrencyListSize = function() return 2 end,
	GetCurrencyListInfo = function(i)
		if i == 1 then return { name = "Misc", isHeader = true } end
		if i == 2 then return { name = "Honor", quantity = 10, maxQuantity = 0, isHeader = false } end
	end,
}

-- the guild: in one unless __guild = false; __guildMembers[name] = true for those MemberExistsByName knows
__guild, __guildMembers = true, {}

-- the map's pin
UiMapPoint = { CreateFromCoordinates = function(map, x, y) return { uiMapID = map, position = { x = x, y = y } } end }
C_Map.CanSetUserWaypointOnMap = function(map) return map ~= 947 end      -- 947: a map that takes no pin
C_Map.SetUserWaypoint = function(point) __waypoint = point return true end
C_Map.GetUserWaypoint = function() return __waypoint end
C_Map.ClearUserWaypoint = function() __waypoint = nil end
C_SuperTrack = { SetSuperTrackedUserWaypoint = function(on) __superTracked = on end }
function IsInGuild() return __guild end
C_GuildInfo = { MemberExistsByName = function(name) return __guildMembers[name] == true end }
"""


def toc(folder):
    """(the ## fields of an addon's .toc, the Lua files it loads in order as paths)"""
    meta, files = {}, []
    for line in (folder / f"{folder.name}.toc").read_text(encoding="utf-8-sig").splitlines():
        line = line.strip()
        if line.startswith("## ") and ":" in line:
            key, _, value = line[3:].partition(":")
            meta[key.strip()] = value.strip()
        elif line and not line.startswith("#") and line.endswith(".lua"):
            files.append(folder.joinpath(*line.split("\\")))
    return meta, files


def install(lua, folders, loaded=(), disabled=()):
    """the installed list the KIT mock reads: one entry per addon folder"""
    installed = lua.globals()[b"__installed"]
    for i, folder in enumerate(folders, 1):
        meta, _ = toc(folder)
        installed[i] = lua.table_from({
            b"name": folder.name.encode(), b"title": meta.get("Title", folder.name).encode(),
            b"meta": lua.table_from({k.encode(): v.encode() for k, v in meta.items()}),
            b"loaded": folder.name in loaded, b"disabled": folder.name in disabled})


def run_files(test, lua, folder, ns=None):
    """an addon's files run as the client runs them, with (its name, its private table) as \"...\""""
    load = lua.globals()[b"__load"]
    ns = ns if ns is not None else lua.table()
    for path in toc(folder)[1]:
        fn, err = load(path.read_bytes(), f"@{folder.name}/{path.relative_to(folder).as_posix()}".encode())
        test.assertIsNone(err, f"{folder.name}: {err}")
        fn(folder.name.encode(), ns)
    return ns


class Session:
    """one UI session: WuxianKit and the given fixtures installed (fixtures not loaded until LoadAddOn), the saved
    variables as Lua table literals {global: literal}"""

    def __init__(self, test, fixtures=(), disabled=(), saved=None, locale="enUS", t0=1000.0):
        self.test, self.fixtures, self.disabled = test, tuple(fixtures), tuple(disabled)
        self.lines, self.loaded = [], []
        self.lua = lupa.LuaRuntime(encoding=None, unpack_returned_tuples=True)
        lua = self.lua
        py = lua.table_from({b"t0": t0, b"chat": lambda m: self.lines.append(m.decode("utf-8", "replace")),
                             b"load_addon": self.load_addon})
        lua.execute(BASE.encode(), py)
        lua.execute(KIT.encode(), py)
        lua.globals()[b"__locale"] = locale.encode()
        for name, literal in (saved or {}).items():
            lua.execute(name.encode() + b" = " + literal)
        self.saved = saved or {}
        folders = [KIT_DIR] + [FIXTURES / f for f in self.fixtures]
        install(lua, folders, loaded=("WuxianKit",), disabled=self.disabled)
        run_files(test, lua, KIT_DIR)
        self.loaded.append("WuxianKit")

    def load_addon(self, name):
        name = name.decode() if isinstance(name, bytes) else name
        run_files(self.test, self.lua, FIXTURES / name)
        self.loaded.append(name)

    def g(self, name):
        return self.lua.globals()[name.encode()]

    def fire(self, event, *args):
        self.g("__fire")(event.encode(), *[a.encode() if isinstance(a, str) else a for a in args])

    def login(self):
        self.fire("ADDON_LOADED", "WuxianKit")
        self.fire("PLAYER_LOGIN")
        self.fire("PLAYER_ENTERING_WORLD")

    def run(self, seconds, dt=0.05):
        step = self.g("__run")
        for _ in range(int(round(seconds / dt))):
            step(dt)

    def now(self):
        return float(self.lua.eval(b"GetTime()"))

    def reload(self, **kw):
        """/reload: logout, then a new session with the saved variables WuxianKit wrote"""
        self.fire("PLAYER_LOGOUT")
        dump = self.g("__dump")
        saved = dict(self.saved)
        if self.g("WuxianKitDB") is not None:
            saved["WuxianKitDB"] = dump(self.g("WuxianKitDB"))
        kw.setdefault("fixtures", self.fixtures)
        kw.setdefault("disabled", self.disabled)
        return Session(self.test, saved=saved, t0=self.now() + 5, **kw)

    def chat(self):
        return "\n".join(self.lines)

    def errors(self):
        return [e.decode("utf-8", "replace") for e in (self.g("__errors") or {}).values()]


def texts(frame):
    """the texts of a frame's font strings that show, in the order made"""
    out = []
    for r in list((frame[b"__regions"] or {}).values()):
        if r[b"kind"] == b"FontString" and r[b"shown"] and r[b"text"]:
            out.append(r[b"text"].decode())
    return out


def type_into(box, text):
    """the player types text into an edit box and leaves it"""
    box.SetFocus(box)
    box.SetText(box, text.encode())
    box.ClearFocus(box)


def click(frame):
    """a click on a frame (its OnClick with the frame as self)"""
    frame.Click(frame)


def py(v):
    """a Lua value as Python: a table with keys 1..n a list, other tables dicts, strings text"""
    if lupa.lua_type(v) == "table":
        items = {(k.decode() if isinstance(k, bytes) else k): py(x) for k, x in v.items()}
        if items and sorted(items, key=str) == sorted(range(1, len(items) + 1), key=str):
            return [items[i] for i in range(1, len(items) + 1)]
        return items
    return v.decode() if isinstance(v, bytes) else v


__all__ = ["BASE", "KIT", "Session", "toc", "install", "run_files", "texts", "click", "type_into", "py", "lupa", "KIT_DIR",
           "FIXTURES",
           "shutil", "tempfile"]
