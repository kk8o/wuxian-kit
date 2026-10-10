-- 调校 · 装备方案 (Tune: equipment sets). tune.gear.list: the sets and which one is worn; tune.gear.use (a Do): put a set
-- on (the client swaps the items a moment later, and the step waits until the set shows as worn; undo puts back each
-- slot's item, a slot that was empty stays as the set left it); tune.gear.save (a Do): what is worn now as a new set of
-- that name (undo deletes it). Measured on 1.60.1.70245: the client makes a new set a moment later, and after a set was
-- deleted in the same session it added one and took it back within half a second, without an event; so the step
-- waits until the set has stayed a second.
local Kit = WuxianKit

local L = Kit:Words {
	zhCN = { USE = "切换装备方案", SAVE = "保存装备方案", LIST = "装备方案列表", SCOPE = "装备方案",
		USE_LINE = "装备「%s」", SAVE_LINE = "将当前装备保存为「%s」" },
	enUS = { USE = "Equip set", SAVE = "Save equipment set", LIST = "Equipment set list", SCOPE = "Equipment sets",
		USE_LINE = "Equip \"%s\"", SAVE_LINE = "Save current gear as \"%s\"" },
}

local tune = Kit:Extension("tune")
tune:Scope("gear", L"SCOPE")

local SLOTS = 19                     -- the equipment slots, INVSLOT_FIRST_EQUIPPED .. INVSLOT_LAST_EQUIPPED
local STAYS = 1                      -- seconds a new set has to stay before it counts
local seen = setmetatable({}, { __mode = "k" })    -- a save's result -> when its set showed
local MAX_NAME = 16

local function SetID(name)
	local id = C_EquipmentSet.GetEquipmentSetID(name)
	return id and id >= 0 and id or nil
end

local function Worn()
	local t = {}
	for slot = 1, SLOTS do t[slot] = GetInventoryItemLink("player", slot) or false end
	return t
end

local function Usable()
	if not C_EquipmentSet.CanUseEquipmentSets() then return "this character cannot use equipment sets" end
end

tune:Do("gear.use", { title = L"USE", scope = "gear", args = { name = "string" },
	doc = "put on an equipment set (tune.gear.list); the client swaps the items a moment later; undo puts back each "
		.. "slot's item",
	check = function(_, a)
		local why = Usable()
		if why then return why end
		if not SetID(a.name) then return ("no equipment set %s (tune.gear.list lists them)"):format(a.name) end
	end,
	preview = function(_, a) return L.USE_LINE:format(Kit:Escape(a.name)) end,
	snapshot = function() return { worn = Worn() } end,
	apply = function(_, a)
		if not C_EquipmentSet.UseEquipmentSet(SetID(a.name)) then error(("the game would not put on %s"):format(a.name), 0) end
		return { name = a.name }
	end,
	settled = function(_, a)
		local id = SetID(a.name)
		local _, _, _, worn = C_EquipmentSet.GetEquipmentSetInfo(id)
		if worn then return true end
		return false, ("%s is not all on (an item missing or locked?)"):format(a.name)
	end,
	restore = function(_, snap)
		local now = Worn()
		for slot, link in pairs(snap.worn or {}) do
			if link and link ~= now[slot] then C_Item.EquipItemByName(link, slot) end
		end
	end })

tune:Do("gear.save", { title = L"SAVE", scope = "gear", args = { name = "string" },
	doc = "proposes to save what the character wears now as a new equipment set named `name` (1-16 bytes); undo deletes it",
	check = function(_, a)
		local why = Usable()
		if why then return why end
		if a.name == "" or #a.name > MAX_NAME then return ("a set's name is 1 to %d bytes"):format(MAX_NAME) end
		if SetID(a.name) then return ("there is a set %s already"):format(a.name) end
	end,
	preview = function(_, a) return L.SAVE_LINE:format(Kit:Escape(a.name)) end,
	snapshot = function(_, a) return { name = a.name } end,
	apply = function(_, a)
		C_EquipmentSet.CreateEquipmentSet(a.name)
		return { name = a.name }
	end,
	settled = function(_, a, result)
		if not SetID(a.name) then
			seen[result] = nil
			return false, "the game did not keep the set"
		end
		seen[result] = seen[result] or GetTime()
		return GetTime() - seen[result] >= STAYS, "the set has not stayed yet"
	end,
	restore = function(_, snap)
		local id = SetID(snap.name)
		if id then C_EquipmentSet.DeleteEquipmentSet(id) end
	end })

tune:See("gear.list", { title = L"LIST",
	doc = "the equipment sets: name, items, worn (all of it on), missing (items not in the bags or on)",
	run = function()
		local out = {}
		for _, id in ipairs(C_EquipmentSet.GetEquipmentSetIDs() or {}) do
			local name, _, _, worn, items, _, _, missing = C_EquipmentSet.GetEquipmentSetInfo(id)
			if name then out[#out + 1] = { name = name, items = items, worn = worn or nil, missing = missing } end
		end
		return out
	end })
