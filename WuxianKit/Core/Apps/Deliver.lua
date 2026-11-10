-- Apps, items (see Decl.lua for the apps and for how the four files share names): which items wake at once (Urgent),
-- what a wake carries (State, the digest host's Wrap and Send for Digest.lua), the ring of an app's last items, an
-- item of a source into an app (Deliver: copied, stamped, enriched, kept, gathered or sent), and app:Push.
-- An item is the core's from Deliver on: a copy of what the source gave (data only, ns.Digest.Small), never the
-- source's own table, with an id the core gives (WuxianKit:NewId; an id the source gave goes as ref), the same copy in
-- the ring and in the wake. The ids are the one cursor of an app's items: a wake's after and next, kit.app.recent's
-- since (Digest.lua has the rest: a wake that does not go is sent again).
-- Here by choice: Urgent and State, beside the host that uses them (State is kit.app.state's too). The player's
-- commands and words (WuxianKit:AppControl, WuxianKit:AppSay) deliver items but are in Run.lua.
local addonName, ns = ...
local Kit = ns.Kit
local A = ns.apps
local Char, App, Owned, Run, Digesting = A.Char, A.App, A.Owned, A.Run, A.Digesting

local RING = 100                                        -- the items an app keeps
local STATE_MAX = ns.Digest.WRAP_MAX - 150              -- a wake's state on the wire (150: app, pace, quiet beside it)

------------------------------------------------------------------------------------------------------------------------
-- the ring

local function Ring(app)
	local c = Char(app)
	if not c then return nil end
	local r = c.recent
	if type(r) ~= "table" or type(r.items) ~= "table" then
		r = { n = 0, items = {} }
		c.recent = r
	end
	return r
end

local function Keep(app, item)
	local r = Ring(app)
	if not r then return end
	r.n = math.max(tonumber(r.n) or 0, item.id)
	r.items[#r.items + 1] = item
	while #r.items > RING do table.remove(r.items, 1) end
end

-- what this character's ring answers; reading makes no ring and changes none
local function Recent(app, since, limit)
	local c = Char(app)
	local r = c and c.recent
	return ns.RingRecent(type(r) == "table" and type(r.items) == "table" and r.items or {}, since, limit, RING)
end

-- a run's cursor before its first wake: the newest item the ring had when the run began (0: none)
local function Began(app, s)
	if not ns.Finite(s.sent) then s.sent = Recent(app, nil, 1).next end
end

------------------------------------------------------------------------------------------------------------------------
-- the digest host: which items wake at once, what a wake carries

local function Urgent(app, item)
	if item.source == "control" or item.source == "player" then return true end
	local d = app.decl
	if d.pace then
		local s = Owned(app)
		if s and s.quiet then return item.why == "mention" end
		local p = d.pace[s and s.pace or "normal"] or d.pace.normal
		return (item.why ~= nil and p.wakeSet[item.why] == true) or (item.kind ~= nil and p.wakeSet[item.kind] == true)
	end
	if d.urgent then
		local ok, yes = pcall(d.urgent, item)
		if not ok then geterrorhandler()(yes) return false end
		return yes and true or false
	end
	if d.urgentSet then
		return (item.why ~= nil and d.urgentSet[item.why] == true) or (item.kind ~= nil and d.urgentSet[item.kind] == true)
	end
	return false
end

-- what the app sees now: { [name] = the facet's read } (a facet missing, or its extension off: none)
local function State(app)
	local state = {}
	for _, name in ipairs(app.decl.see) do state[name] = ns.FacetRead(ns.facets[name]) end
	return state
end

-- the state a wake carries: State, within STATE_MAX bytes as WoWBridge writes it, so that the items have their room
-- beside it. Of a larger one the largest facets go as { cut = true } (kit.app.state reads them whole)
local function Carried(app)
	local state, sizes, total = State(app), {}, 2
	for name, v in pairs(state) do
		sizes[name] = ns.WireSize(v, 4) + #name + 4      -- (a facet is two levels inside its wake)
		total = total + sizes[name]
	end
	while total > STATE_MAX do
		local big
		for name, size in pairs(sizes) do
			if not big or size > sizes[big] then big = name end
		end
		if not big then break end
		total = total - sizes[big] + #big + 16
		state[big], sizes[big] = { cut = true }, nil
	end
	return state
end

local function Host(app)
	app.host = {
		ext = ns.extensions.kit,
		spec = { digest = { urgent = function(_, _, item) return Urgent(app, item) end } },
		Wrap = function(_, s)
			Began(app, s)                                 -- (a wake before any item: an idle one)
			local w = { app = app.id }
			if app.decl.pace then w.pace, w.quiet = s.pace or "normal", s.quiet and true or false end
			if #app.decl.see > 0 then w.state = Carried(app) end   -- (read at the wake)
			return w
		end,
		Send = function(_, data) return ns.SendWake("app." .. app.id, data) end,
	}
end

------------------------------------------------------------------------------------------------------------------------
-- items

-- what a source gave as the app's item: a copy (data only; the source's table is neither kept nor changed) with the
-- core's id (never the source's: that goes as ref, unless it gave a ref), its source and its time, enriched, within
-- the size of an item; nil for one that cannot be read
local function Stamped(app, source, item)
	local it = ns.Digest.Small(item)
	if type(it) ~= "table" then return nil end
	if it.ref == nil then it.ref = it.id end
	local id, at = Kit:NewId(), ns.Finite(it.time) and it.time or time()
	it.id, it.source, it.time = id, source, at
	if app.decl.enrich then
		local ok, err = pcall(app.decl.enrich, it)
		if not ok then geterrorhandler()(err) end
		it = ns.Digest.Small(it)                          -- (what it added is data only too)
	end
	it = ns.Digest.Fit(it)
	it.id, it.source, it.time = id, source, at
	return it
end

-- an app without a digest has no ticker asking for it (Run.lua's asks ns.Digest.Due for those with one): its wake that
-- did not go, or the rest of one, is asked for here a second later
local function Again(app)
	if app.again then return end
	app.again = true
	C_Timer.After(1, function()
		app.again = nil
		local s = Run(app)
		if not s or not s.retry or Digesting(app) then return end
		ns.Safe(ns.Digest.Due, app.host, s)
		if s.retry then Again(app) end
	end)
end

-- an item heard while the app runs, from source (a registered source's name, or the app's own: addon, control,
-- player): copied and stamped, kept, gathered or sent; immediate: the wake goes at once (control and player items)
local function Deliver(app, source, item, immediate)
	local s = Run(app)
	if not s or type(item) ~= "table" then return false end
	local it = Stamped(app, source, item)
	if not it then return false end
	Began(app, s)
	s.heard = (s.heard or 0) + 1
	Keep(app, it)
	if Digesting(app) then
		ns.Digest.Gather(app.host, s, it)
		if immediate and #(s.buffer or {}) > 0 then ns.Digest.Wake(app.host, s, "urgent") end
	else
		ns.Digest.Hold(app.host, s, it)
		if immediate or not s.retry then ns.Digest.Wake(app.host, s, "item") end   -- (one waits: this one behind it)
		if s.retry then Again(app) end
	end
	return true
end

function App:Push(data)
	if data == nil then return false end
	return Deliver(self, "addon", { data = data })
end

-- a wake kept through a reload goes on (the ticker asks for the apps with a digest)
ns.When("login", function()
	for _, id in ipairs(A.order) do
		local app = A.apps[id]
		local s = app and Owned(app)
		if s and s.retry and not Digesting(app) then Again(app) end
	end
end)

------------------------------------------------------------------------------------------------------------------------
-- shared with the other files

A.RING = RING
A.State, A.Host = State, Host
A.Recent, A.Deliver = Recent, Deliver
