-- 调校 · 界面布局 (Tune: Edit Mode layouts). tune.layout.get / tune.layout.set: a Setting, the layout in use by its name
-- (the client's presets, or the player's own); tune.layout.list; tune.layout.export: a layout as the game's share string;
-- tune.layout.import (a Do): a share string as a new layout, put in use; undo deletes it and puts back the one in use
-- before. The client numbers the layouts presets first, then the account's, then the character's; it shows a change of
-- layout a moment later, so the steps wait for it. Measured on 1.60.1.70245: deleting the layout in use puts the
-- client's first preset in use, whatever SaveLayouts was given, so undo puts the old one in use itself.
local Kit = WuxianKit

local L = Kit:Words {
	zhCN = { LAYOUT = "编辑模式布局", LIST = "布局列表", EXPORT = "导出布局", IMPORT = "导入布局", SCOPE = "编辑模式布局",
		IN_USE = "当前布局", IMPORT_LINE = "导入并启用布局「%s」（%s）", ACCOUNT = "账号通用", CHARACTER = "仅限此角色" },
	enUS = { LAYOUT = "Edit Mode layout", LIST = "Layout list", EXPORT = "Export layout", IMPORT = "Import layout",
		SCOPE = "Edit Mode layouts", IN_USE = "Active layout", IMPORT_LINE = "Import and use layout \"%s\" (%s)",
		ACCOUNT = "account-wide", CHARACTER = "this character only" },
}

local tune = Kit:Extension("tune")
tune:Scope("layouts", L"SCOPE")

local MAX_PER_TYPE = Constants and Constants.EditModeConsts and Constants.EditModeConsts.EditModeMaxLayoutsPerType or 5

local function Presets()
	return EditModePresetLayoutManager and EditModePresetLayoutManager:GetCopyOfPresetLayouts() or {}
end

-- the layouts as the client numbers them ({ name, preset, character, info }), and the number of the one in use
local function All()
	local saved = C_EditMode.GetLayouts()
	local list = {}
	for _, l in ipairs(Presets()) do list[#list + 1] = { name = l.layoutName, preset = true, info = l } end
	for _, l in ipairs(saved.layouts or {}) do
		list[#list + 1] = { name = l.layoutName, info = l, character = l.layoutType == Enum.EditModeLayoutType.Character or nil }
	end
	return list, saved.activeLayout
end

local function Index(name)
	for i, l in ipairs((All())) do
		if l.name == name then return i, l end
	end
end

local function InUse()
	local list, active = All()
	return list[active] and list[active].name or nil
end

local function Use(name)
	local i = Index(name)
	if i then C_EditMode.SetActiveLayout(i) end
end

tune:Setting("layout", { title = L"LAYOUT", scope = "layouts", settle = true,
	doc = "the Edit Mode layout in use, by its name: the client's presets or the player's own (tune.layout.list); the "
		.. "client shows the change a moment later",
	key = {}, value = "string",
	validate = function(_, _, v)
		if not Index(v) then return ("no layout %s (tune.layout.list lists them)"):format(v) end
	end,
	get = function() return InUse() end,
	set = function(_, _, v) Use(v) end,
	restore = function(_, _, v)
		if not v then return end
		if not Index(v) then error(("the layout %s is gone"):format(v), 0) end   -- undo says it could not
		Use(v)
	end,
	label = function() return L.IN_USE end })

tune:See("layout.list", { title = L"LIST",
	doc = "the Edit Mode layouts in the client's order: name, preset = true for the client's own, character = true for "
		.. "this character's (the rest are the account's), inUse",
	run = function()
		local list, active = All()
		local out = {}
		for i, l in ipairs(list) do
			out[i] = { name = l.name, preset = l.preset, character = l.character, inUse = i == active or nil }
		end
		return out
	end })

tune:See("layout.export", { title = L"EXPORT", args = { name = "string?" },
	doc = "a layout as the game's share string (the one in use without a name); tune.layout.import takes it, here or on "
		.. "another computer",
	run = function(_, a)
		local name = a.name or InUse()
		local _, l = Index(name or "")
		if not l then error(("no layout %s (tune.layout.list lists them)"):format(tostring(name)), 0) end
		return { name = l.name, text = C_EditMode.ConvertLayoutInfoToString(l.info) }
	end })

-- where a new layout of that type goes in the client's numbering: after the last one of its type (the account's come
-- before the character's)
local function Slot(saved, layoutType)
	local character = Enum.EditModeLayoutType.Character
	if layoutType == character then return #saved.layouts + 1 end
	local at = 0
	for i, l in ipairs(saved.layouts) do
		if l.layoutType ~= character then at = i end
	end
	return at + 1
end

tune:Do("layout.import", { title = L"IMPORT", scope = "layouts", args = { name = "string", text = "string", character = "boolean?" },
	doc = "a layout's share string (tune.layout.export, or one shared by others) as a new layout of that name, the "
		.. "account's (character = true: this character's), put in use; undo deletes it and puts back the one in use before",
	check = function(_, a)
		if Index(a.name) then return ("there is a layout %s already"):format(a.name) end
		if C_EditMode.IsValidLayoutName and not C_EditMode.IsValidLayoutName(a.name) then
			return ("%s is not a name a layout may have"):format(a.name)
		end
		local ok, info = pcall(C_EditMode.ConvertStringToLayoutInfo, a.text)
		if not ok or type(info) ~= "table" then return "text is not a layout's share string (tune.layout.export makes one)" end
		local want, count = a.character and Enum.EditModeLayoutType.Character or Enum.EditModeLayoutType.Account, 0
		for _, l in ipairs(C_EditMode.GetLayouts().layouts or {}) do
			if l.layoutType == want then count = count + 1 end
		end
		if count >= MAX_PER_TYPE then return ("no room: there are %d layouts of that kind already"):format(count) end
	end,
	preview = function(_, a) return L.IMPORT_LINE:format(Kit:Escape(a.name), a.character and L.CHARACTER or L.ACCOUNT) end,
	snapshot = function(_, a) return { name = a.name, active = InUse() } end,
	apply = function(_, a)
		local info = C_EditMode.ConvertStringToLayoutInfo(a.text)
		info.layoutName = a.name
		info.layoutType = a.character and Enum.EditModeLayoutType.Character or Enum.EditModeLayoutType.Account
		local saved = C_EditMode.GetLayouts()
		local at = Slot(saved, info.layoutType)
		table.insert(saved.layouts, at, info)
		local index = #Presets() + at
		saved.activeLayout = index
		C_EditMode.SaveLayouts(saved)
		if C_EditMode.OnLayoutAdded then C_EditMode.OnLayoutAdded(index, true, true) end
		C_EditMode.SetActiveLayout(index)
		return { name = a.name }
	end,
	settled = function(_, a)
		local now = InUse()
		if now == a.name then return true end
		return false, ("the layout in use is %s"):format(tostring(now))
	end,
	restore = function(_, snap)                              -- as the client's own Delete does it: save, then tell it
		local saved, gone = C_EditMode.GetLayouts(), nil
		for i = #saved.layouts, 1, -1 do
			if saved.layouts[i].layoutName == snap.name then
				table.remove(saved.layouts, i)
				gone = i
			end
		end
		local presets, active = Presets(), nil
		for i, l in ipairs(presets) do
			if l.layoutName == snap.active then active = i end
		end
		for i, l in ipairs(saved.layouts) do
			if l.layoutName == snap.active then active = #presets + i end
		end
		saved.activeLayout = active or 1
		C_EditMode.SaveLayouts(saved)
		if gone and C_EditMode.OnLayoutDeleted then C_EditMode.OnLayoutDeleted(#presets + gone) end
		if snap.active then Use(snap.active) end            -- deleting the one in use puts the client's first preset in use
	end })
