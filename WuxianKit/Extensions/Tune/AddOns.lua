-- 调校 · 插件开关 (Tune: addons). tune.addon.get / tune.addon.set: a Setting, whether an addon is on for this character
-- (by its folder name); it takes effect after a reload, which the preview says and the player does. tune.addon.list.
-- WuxianKit keeps itself on. The client knows a character by its GUID here (measured on 1.60.1.70245: with its name
-- EnableAddOn / DisableAddOn do nothing and GetAddOnEnableState always answers 2).
local addonName = ...
local Kit = WuxianKit

local L = Kit:Words {
	zhCN = { ADDON = "插件启用状态", LIST = "插件列表", SCOPE = "插件启用状态", ON = "启用", OFF = "禁用" },
	enUS = { ADDON = "Addon state", LIST = "Addon list", SCOPE = "Addon state", ON = "Enabled", OFF = "Disabled" },
}

local tune = Kit:Extension("tune")
tune:Scope("addons", L"SCOPE")

local function Me() return UnitGUID("player") end

local function Exists(name)
	if C_AddOns.DoesAddOnExist then return C_AddOns.DoesAddOnExist(name) end
	return C_AddOns.GetAddOnInfo(name) ~= nil
end

local function On(name) return (tonumber(C_AddOns.GetAddOnEnableState(name, Me())) or 0) > 0 end

tune:Setting("addon", { title = L"ADDON", scope = "addons", reload = true,
	doc = "whether an addon is on for this character, by its folder name (tune.addon.list)",
	change = "it takes effect after a reload",
	key = { name = "string" }, value = "boolean",
	check = function(_, k, reading)
		if not Exists(k.name) then return ("no addon %s (tune.addon.list lists them)"):format(k.name) end
		if not reading and k.name == addonName then return "WuxianKit keeps itself on" end
	end,
	get = function(_, k) return On(k.name) end,
	set = function(_, k, v)
		if v then C_AddOns.EnableAddOn(k.name, Me()) else C_AddOns.DisableAddOn(k.name, Me()) end
		if C_AddOns.SaveAddOns then C_AddOns.SaveAddOns() end
	end,
	format = function(_, v) return v and L.ON or L.OFF end,
	info = function(_, k)
		local _, title = C_AddOns.GetAddOnInfo(k.name)
		return { name = k.name, title = title, loaded = C_AddOns.IsAddOnLoaded(k.name) and true or false }
	end })

tune:See("addon.list", { title = L"LIST", args = { text = "string?" },
	doc = "the installed addons (those whose name or title holds `text`, no case): name (its folder), title, version, on "
		.. "(for this character), loaded",
	run = function(_, a)
		local want, out = a.text and a.text:lower(), {}
		for i = 1, C_AddOns.GetNumAddOns() do
			local name, title = C_AddOns.GetAddOnInfo(i)
			if name and (not want or name:lower():find(want, 1, true) or (title or ""):lower():find(want, 1, true)) then
				out[#out + 1] = { name = name, title = title, version = C_AddOns.GetAddOnMetadata(name, "Version"),
					on = On(name), loaded = C_AddOns.IsAddOnLoaded(name) and true or false }
			end
		end
		return out
	end })
