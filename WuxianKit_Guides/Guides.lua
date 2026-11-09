-- 任务指引适配 (Guide adapters): the custom extension "guides". Each file after this one is the adapter of one guide
-- addon (RestedXP.lua: RXPGuides) and hands it over with ns.Adapter(id, addon, adapter); while the extension is on, each
-- whose addon is loaded is provided to WuxianKit's quest guide (WuxianKit.Route:Provide, the extension route), one loaded
-- later as soon as it is, and turned off they are taken back (Provide(id, nil)). Nothing without a WuxianKit that has
-- the quest guide.
local addonName, ns = ...
local Kit = WuxianKit
if not (Kit and Kit.Route and Kit.Route.Provide) then return end

local L = Kit:Words {
	zhCN = { TITLE = "任务指引适配", ON = "%s：已接上", OFF = "%s：未加载", SEP = "；" },
	enUS = { TITLE = "Guide adapters", ON = "%s: connected", OFF = "%s: not loaded", SEP = "; " },
}

local adapters = {}                               -- { id, addon, adapter, offered }, as handed over
ns.adapters = adapters

-- an adapter for addon (the folder name), provided as id while the addon is loaded
function ns.Adapter(id, addon, adapter)
	adapters[#adapters + 1] = { id = id, addon = addon, adapter = adapter }
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

local function Withdraw()
	for _, a in ipairs(adapters) do
		if a.offered then
			a.offered = nil
			Kit.Route:Provide(a.id, nil)
		end
	end
end

local version = C_AddOns and C_AddOns.GetAddOnMetadata and C_AddOns.GetAddOnMetadata(addonName, "Version") or nil

local guides = Kit:Extension("guides", { title = L"TITLE", version = version, addon = addonName,
	notes = "Connects guide addons (RestedXP) to the quest guide (the extension route)",
	setup = Offer, teardown = Withdraw })

guides:On("ADDON_LOADED", function(self)
	if self.active then Offer() end
end)

guides:Status(function()
	local parts = {}
	for _, a in ipairs(adapters) do
		parts[#parts + 1] = (a.offered and L.ON or L.OFF):format(tostring(a.adapter.title or a.id))
	end
	return table.concat(parts, L.SEP)
end)
