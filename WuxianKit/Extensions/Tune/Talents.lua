-- 调校 · 天赋配置 (Tune: talent loadouts). tune.talent.list: the current specialization's saved loadouts and the one in
-- use; tune.talent.get / tune.talent.set: a Setting, the loadout in use by its name (the client loads it a moment later,
-- out of combat, and the step waits for it; as the talent window does, the loadout loaded is then made the one in use);
-- a name two loadouts share is refused. Undo loads the one before by its id, and fails when it is gone.
-- tune.talent.export: a loadout's share string.
local Kit = WuxianKit

local L = Kit:Words {
	zhCN = { TALENT = "天赋配置", LIST = "天赋配置列表", EXPORT = "导出天赋配置", SCOPE = "天赋配置", IN_USE = "当前天赋配置" },
	enUS = { TALENT = "Talent loadout", LIST = "Loadout list", EXPORT = "Export loadout", SCOPE = "Talent loadouts",
		IN_USE = "Active loadout" },
}

local tune = Kit:Extension("tune")
tune:Scope("talents", L"SCOPE")

local function Spec()
	return PlayerUtil and PlayerUtil.GetCurrentSpecID and PlayerUtil.GetCurrentSpecID() or nil
end

-- the current specialization's saved loadouts: { id, name }
local function Loadouts()
	local out, spec = {}, Spec()
	if not spec or not C_ClassTalents then return out end
	for _, id in ipairs(C_ClassTalents.GetConfigIDsBySpecID(spec) or {}) do
		local info = C_Traits.GetConfigInfo(id)
		if info then out[#out + 1] = { id = id, name = info.name } end
	end
	return out
end

-- the loadout of that name; nil + why when none has it, or more than one
local function Named(name)
	local found, n = nil, 0
	for _, l in ipairs(Loadouts()) do
		if l.name == name then found, n = found or l, n + 1 end
	end
	if n > 1 then return nil, ("%d loadouts are named %s: rename one in the talent window"):format(n, tostring(name)) end
	if not found then return nil, ("no loadout %s (tune.talent.list lists them)"):format(tostring(name)) end
	return found
end

local function InUseID()
	local spec = Spec()
	local get = C_ClassTalents and C_ClassTalents.GetLastSelectedSavedConfigID
	return spec and get and get(spec) or nil
end

local function InUse()
	local id = InUseID()
	local info = id and C_Traits.GetConfigInfo(id)
	return info and info.name or nil
end

-- loads loadout `id` and makes it the one in use, as the talent window does after LoadConfig
local function LoadID(id)
	local result, why = C_ClassTalents.LoadConfig(id, true)
	if result == Enum.LoadConfigResult.Error then error(why or "the game would not load it", 0) end
	if C_ClassTalents.UpdateLastSelectedSavedConfigID then C_ClassTalents.UpdateLastSelectedSavedConfigID(Spec(), id) end
end

local function Load(name)
	local l, why = Named(name)
	if not l then error(why, 0) end
	LoadID(l.id)
end

tune:Setting("talent", { title = L"TALENT", scope = "talents", settle = true, settleTime = 10,
	doc = "the talent loadout in use, by its name (tune.talent.list: the current specialization's saved loadouts)",
	change = "the client loads it a moment later, out of combat; the loadout in use loads again too (its unsaved edits go)",
	key = {}, value = "string", always = true,
	check = function()
		if not Spec() then return "no specialization yet" end
	end,
	validate = function(_, _, v)
		local l, why = Named(v)
		if not l then return why end
		local can, cannot = C_ClassTalents.CanEditTalents()
		if can == false then return ("talents cannot change now: %s"):format(tostring(cannot)) end
	end,
	get = function() return InUse() end,
	set = function(_, _, v) Load(v) end,
	keep = function() return { id = InUseID() } end,             -- the one in use by its id (names can be shared)
	restore = function(_, _, v, kept)
		local id = kept and kept.id
		if id and C_Traits.GetConfigInfo(id) then return LoadID(id) end
		if v then error(("the loadout %s is gone"):format(v), 0) end
	end,
	label = function() return L.IN_USE end })

tune:See("talent.list", { title = L"LIST",
	doc = "the current specialization's saved talent loadouts: name, id, inUse",
	run = function()
		local now, out = InUseID(), {}
		for _, l in ipairs(Loadouts()) do out[#out + 1] = { name = l.name, id = l.id, inUse = l.id == now or nil } end
		return out
	end })

tune:See("talent.export", { title = L"EXPORT", args = { name = "string?" },
	doc = "a loadout's share string, as the talent window's Share gives it (the one in use without a name)",
	run = function(_, a)
		local l, why = Named(a.name or InUse() or "")
		if not l then error(why, 0) end
		return { name = l.name, text = C_Traits.GenerateImportString(l.id) }
	end })
