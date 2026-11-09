-- 游戏动态 · Travel: the topic travel (zone, taxi, rest). Ported from 无限陪玩 (the companion's Progress.lua). The zones
-- this character has been to (for zone's `first`) are kept in the extension's storage for the character (ext:Char()),
-- also while nobody listens: been there is been there. That costs two rare events (ZONE_CHANGED_NEW_AREA,
-- PLAYER_ENTERING_WORLD); the rest runs only while the topic does.
local addonName, ns = ...
local Kit = WuxianKit
local G = ns.game
local Read = G.Read
local game = G.ext

local function Zone()
	return Kit:Clean(Read(GetZoneText))
end

-- marks zone visited; answers whether it was the first time
local function Visit(zone)
	local char = game:Char()
	char.zones = type(char.zones) == "table" and char.zones or {}
	local first = not char.zones[zone]
	char.zones[zone] = true
	return first
end

local zoneLast

game:On("ZONE_CHANGED_NEW_AREA", function()
	local zone = Zone()
	if not zone or zone == zoneLast then return end
	zoneLast = zone
	local first = Visit(zone)
	G.Moment("zone", { zone = zone, first = first }, { key = zone, every = 30 })
end)

game:On("PLAYER_ENTERING_WORLD", function()
	local zone = Zone()
	if not zone then return end
	zoneLast = zone
	Visit(zone)
end)

------------------------------------------------------------------------------------------------------------------------
-- taxi: the node taken (TakeTaxiNode, hooked once the topic first runs), then a loss of control while on a taxi

local taxiTo, taxiAt, hooked = nil, -100, false

local function Hook()
	if hooked or not (hooksecurefunc and TakeTaxiNode) then return end
	hooked = pcall(hooksecurefunc, "TakeTaxiNode", function(i)
		if G.active.travel then taxiTo, taxiAt = Kit:Clean(Read(TaxiNodeName, i)), GetTime() end
	end)
end

local resting = false

G.Topic("travel", {
	events = {
		PLAYER_CONTROL_LOST = function()
			C_Timer.After(0.3, function()
				if not (G.active.travel and Read(UnitOnTaxi, "player")) then return end
				local to = GetTime() - taxiAt < 10 and taxiTo or nil
				taxiTo = nil
				G.Moment("taxi", { to = to }, { every = 10 })
			end)
		end,
		PLAYER_UPDATE_RESTING = function()
			local now = Read(IsResting) and true or false
			if now and not resting then G.Moment("rest", {}, { every = 30 }) end
			resting = now
		end,
	},
	on = function()
		Hook()
		resting = Read(IsResting) and true or false
		zoneLast = Zone() or zoneLast
	end,
})
