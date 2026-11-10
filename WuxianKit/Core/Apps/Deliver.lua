-- Apps, items (see Decl.lua for the apps and for how the four files share names): which items wake at once (Urgent),
-- what a wake carries (State, the digest host's Wrap and Send for Digest.lua), the ring of an app's last items, an
-- item of a source into an app (Deliver: stamped, enriched, kept, gathered or sent), and app:Push.
-- Here by choice: Urgent and State, beside the host that uses them (State is kit.app.state's too). The player's
-- commands and words (WuxianKit:AppControl, WuxianKit:AppSay) deliver items but are in Run.lua.
local addonName, ns = ...
local Kit = ns.Kit
local A = ns.apps
local Char, App, Owned, Run, Digesting = A.Char, A.App, A.Owned, A.Run, A.Digesting

local RING = 100                                        -- the items an app keeps

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

local function Host(app)
	app.host = {
		ext = ns.extensions.kit,
		spec = { digest = { urgent = function(_, _, item) return Urgent(app, item) end } },
		Wrap = function(_, s)
			local w = { app = app.id }
			if app.decl.pace then w.pace, w.quiet = s.pace or "normal", s.quiet and true or false end
			if #app.decl.see > 0 then w.state = State(app) end   -- (read at the wake; its size counts: items go first)
			return w
		end,
		Send = function(_, data) Kit:Emit("app." .. app.id, data) end,
	}
end

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
	r.items[#r.items + 1] = ns.Digest.Small(item)
	while #r.items > RING do table.remove(r.items, 1) end
end

local function Recent(app, since, limit)
	return ns.RingRecent((Ring(app) or { items = {} }).items, since, limit, RING)
end

------------------------------------------------------------------------------------------------------------------------
-- items

-- an item heard while the app runs, from source (a registered source's name, or the app's own: addon, control,
-- player): stamped, enriched, kept, gathered or sent; immediate: the wake goes at once (control and player items)
local function Deliver(app, source, item, immediate)
	local s = Run(app)
	if not s or type(item) ~= "table" then return false end
	item.source = source
	if ns.Finite(item.id) then ns.BumpId(item.id) else item.id = Kit:NewId() end
	if item.time == nil then item.time = time() end
	if app.decl.enrich then
		local ok, err = pcall(app.decl.enrich, item)
		if not ok then geterrorhandler()(err) end
	end
	s.heard = (s.heard or 0) + 1
	Keep(app, item)
	if Digesting(app) then
		ns.Digest.Gather(app.host, s, item)
		if immediate and #(s.buffer or {}) > 0 then ns.Digest.Wake(app.host, s, "urgent") end
	else
		s.buffer, s.first, s.urgentAt = { item }, nil, nil
		ns.Digest.Wake(app.host, s, "item")
	end
	return true
end

function App:Push(data)
	if data == nil then return false end
	return Deliver(self, "addon", { data = data })
end

------------------------------------------------------------------------------------------------------------------------
-- shared with the other files

A.RING = RING
A.State, A.Host = State, Host
A.Recent, A.Deliver = Recent, Deliver
