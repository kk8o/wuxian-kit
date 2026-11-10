-- 任务指引适配 (Guide adapters): the custom extension "guides". Each file after this one is the adapter of one guide
-- addon (RestedXP.lua: RXPGuides) and hands it over with ns.Adapter(id, addon, adapter, trouble); once the extension is
-- on, each whose addon is loaded is provided to WuxianKit's quest guide (WuxianKit.Route:Provide, the extension route)
-- as this extension's (adapter.extension), one loaded later as soon as it is. The quest guide keeps them away while the
-- extension is off, so nothing is taken back here. Nothing with a WuxianKit before 0.6 (it has no quest guide).
--
-- The status line says of each adapter what is true now: its addon is not loaded, or it reads the addon (connected), or
-- what keeps it from reading (trouble() -> a line | nil: an adapter reads its addon's private fields, and one renamed
-- must not read as "connected").
local addonName, ns = ...
local Kit = WuxianKit
if not (Kit and Kit.Requires and Kit:Requires("0.6.0")) then return end

local L = Kit:Words {
	zhCN = { TITLE = "任务指引适配", ON = "%s：已接上", OFF = "%s：未加载", NOT = "%s：%s", SEP = "；" },
	enUS = { TITLE = "Guide adapters", ON = "%s: connected", OFF = "%s: not loaded", NOT = "%s: %s", SEP = "; " },
}

local adapters = {}                               -- { id, addon, adapter, trouble, offered }, as handed over
ns.adapters = adapters

-- an adapter for addon (the folder name), provided as id once the addon is loaded; trouble() -> what keeps it from
-- reading the addon now (a line for the status), or nil
function ns.Adapter(id, addon, adapter, trouble)
	adapter.extension = "guides"
	adapters[#adapters + 1] = { id = id, addon = addon, adapter = adapter, trouble = trouble }
end

function ns.Safe(fn, ...)
	local ok, err = pcall(fn, ...)
	if not ok then geterrorhandler()(err) end
	return ok
end

-- whether the addon (its folder name) is loaded
function ns.Loaded(name)
	local f = C_AddOns and C_AddOns.IsAddOnLoaded or IsAddOnLoaded
	if type(f) ~= "function" then return false end
	local ok, loaded = pcall(f, name)
	return ok and loaded and true or false
end

local function Offer()
	for _, a in ipairs(adapters) do
		if not a.offered and ns.Loaded(a.addon) then
			a.offered = true
			Kit.Route:Provide(a.id, a.adapter)
		end
	end
end

local version = C_AddOns and C_AddOns.GetAddOnMetadata and C_AddOns.GetAddOnMetadata(addonName, "Version") or nil

local guides = Kit:Extension("guides", { title = L"TITLE", version = version, addon = addonName,
	notes = "Connects guide addons (RestedXP) to the quest guide (the extension route)",
	setup = Offer })

guides:On("ADDON_LOADED", function(self)
	if self.active then Offer() end
end)

guides:Status(function()
	local parts = {}
	for _, a in ipairs(adapters) do
		local title = tostring(a.adapter.title or a.id)
		if not a.offered then
			parts[#parts + 1] = L.OFF:format(title)
		else
			local ok, why = pcall(a.trouble or function() end)
			if not ok then geterrorhandler()(why) end
			if ok and why == nil then
				parts[#parts + 1] = L.ON:format(title)
			else
				parts[#parts + 1] = L.NOT:format(title, ok and tostring(why) or "?")
			end
		end
	end
	return table.concat(parts, L.SEP)
end)
