-- The digest (摘要): items gathered into wakes instead of sent one by one, for apps (Apps.lua). A host is { ext, spec =
-- { digest = { urgent(self, options, item) } }, Wrap(host, s)?, Send(host, data) } and a run s is { options = { digest },
-- buffer, first, last, urgentAt, wakes, lastWake, started }.
--   ns.Digest.Params(host, s)         the digest now: the run's options.digest, then the host spec's, then the defaults
--   ns.Digest.Gather(host, s, item)   an item gathered (and a wake when its time has come)
--   ns.Digest.Due(host, s)            a wake when its time has come (the host's ticker asks every second)
--   ns.Digest.Wake(host, s, reason)   one wake of what is gathered, sent by host:Send(data)
--   ns.Digest.Small(v)                a copy of v cut to what saved variables should hold
-- A wake is { reason = "urgent" | "full" | "batch" | "idle" (or the host's own, "item"), items (oldest first), skipped }
-- and what host:Wrap(s) adds: gather s (5) after an urgent item, every s (60; false: only urgent or full) after the first
-- one gathered, at once at most (30) of them, and after idle s (false: never) without an item or a wake (an idle wake
-- carries what is gathered: nothing, unless every is false). A wake is kept under WAKE_MAX bytes: the oldest items go
-- (skipped counts them; the ring still has them). urgent may be a list instead: an item is urgent when its why or its kind
-- is in it (ns.UrgentList).
-- Also here: ns.Lease (a lease as kept), ns.RingRecent (what a ring answers for since and limit).
local _, ns = ...

local KEEP_MAX, ITEM_TEXT, ITEM_DEPTH = 200, 500, 4
local LEASE_MIN = 60
-- a wake's size as Comm.Serialize writes it: WoWBridge sends an event's data as JSON of at most 8000 bytes (more goes as
-- {cut = true}) and queues at most 6000 bytes of waiting events; JSON's keys and quotes take more than Serialize's
-- lengths, so a wake keeps well under both
local WAKE_MAX = 5500
local DIGEST = { gather = 5, every = 60, idle = false, most = 30 }

-- a list of whys and kinds ({ "mention", "question" }) as an urgent function: an item whose why or kind is in it
function ns.UrgentList(list)
	local set = {}
	for k, v in pairs(list) do
		if type(v) == "string" then set[v] = true elseif v == true and type(k) == "string" then set[k] = true end
	end
	return function(_, _, item)
		return type(item) == "table" and ((item.why ~= nil and set[item.why] == true) or
			(item.kind ~= nil and set[item.kind] == true)) or false
	end
end

-- a lease as kept: whole seconds, at least LEASE_MIN, or nil for none (0, false, nothing usable)
function ns.Lease(v)
	v = tonumber(v)
	if not ns.Finite(v) or v <= 0 then return nil end
	return math.max(LEASE_MIN, math.floor(v))
end

-- the digest's parameters now: the run's options.digest table, then the host spec's, then the defaults
local function Params(host, s)
	local mine = type(s.options) == "table" and type(s.options.digest) == "table" and s.options.digest or {}
	local spec = type(host.spec.digest) == "table" and host.spec.digest or {}
	local function Get(k)
		if mine[k] ~= nil then return mine[k] end
		if spec[k] ~= nil then return spec[k] end
		return DIGEST[k]
	end
	local function Seconds(k, min)                        -- a number of seconds, or false
		local v = Get(k)
		if not ns.Finite(v) then
			if v == false then return false end           -- (not "v == false and false or ...": that is never false)
			return DIGEST[k]
		end
		return math.max(min, v)
	end
	local most = Get("most")
	most = ns.Finite(most) and math.max(1, math.min(KEEP_MAX, math.floor(most))) or DIGEST.most
	local urgent = Get("urgent")
	if type(urgent) == "table" then urgent = ns.UrgentList(urgent) end
	return { gather = Seconds("gather", 0) or 0, every = Seconds("every", 1), idle = Seconds("idle", 1), most = most,
		urgent = type(urgent) == "function" and urgent or nil }
end

local function Small(v, depth)                          -- a copy for saved variables
	local t = type(v)
	if t == "string" then return ns.Cut(v, ITEM_TEXT) end
	if t == "number" then return ns.Finite(v) and v or nil end
	if t == "boolean" then return v end
	if t ~= "table" or depth > ITEM_DEPTH then return nil end
	local out = {}
	for k, x in pairs(v) do
		if type(k) == "string" or type(k) == "number" then out[k] = Small(x, depth + 1) end
	end
	return out
end

local function Size(v)
	local ok, text = pcall(ns.Comm.Serialize, v)
	return ok and #text or math.huge
end

-- one wake of what is gathered: { reason, items, skipped } and what host:Wrap(s) adds, sent by host:Send(data)
local function Wake(host, s, reason)
	local items = s.buffer or {}
	if s.urgentAt then reason = "urgent" end
	s.buffer, s.first, s.urgentAt = {}, nil, nil
	local now = time()
	s.wakes, s.lastWake = (s.wakes or 0) + 1, now
	local data = host.Wrap and host:Wrap(s) or {}
	data.reason, data.items, data.skipped = reason, {}, 1000
	local sizes, total = {}, Size(data)
	for i, item in ipairs(items) do
		sizes[i] = Size(item) + 24                        -- (its key, and room)
		total = total + sizes[i]
	end
	local skipped = 0
	while total > WAKE_MAX and skipped < #items do
		skipped = skipped + 1
		total = total - sizes[skipped]
	end
	local out = {}
	for i = skipped + 1, #items do out[#out + 1] = items[i] end
	data.items, data.skipped = out, skipped
	host:Send(data)
end

-- a wake when its time has come
local function Due(host, s)
	local d, now = Params(host, s), time()
	local n = #(s.buffer or {})
	if n >= d.most then
		Wake(host, s, "full")
	elseif s.urgentAt and now >= s.urgentAt + d.gather then
		Wake(host, s, "urgent")
	elseif n > 0 and d.every and now >= (s.first or now) + d.every then
		Wake(host, s, "batch")
	elseif d.idle and now >= math.max(s.started or 0, s.last or 0, s.lastWake or 0) + d.idle then
		Wake(host, s, "idle")
	end
end

local function Gather(host, s, item)
	local d, now = Params(host, s), time()
	s.buffer = type(s.buffer) == "table" and s.buffer or {}
	s.buffer[#s.buffer + 1] = item
	s.first, s.last = s.first or now, now
	if d.urgent and not s.urgentAt then
		local ok, yes = pcall(d.urgent, host.ext, s.options, item)
		if not ok then geterrorhandler()(yes) elseif yes then s.urgentAt = now end
	end
	Due(host, s)
end

ns.Digest = { Params = Params, Gather = Gather, Due = Due, Wake = Wake, Small = function(v) return Small(v, 1) end }

-- the items of a ring (oldest first) with id > since, the last `limit` (default 50, at most `most`), and the newest id
function ns.RingRecent(items, since, limit, most)
	since = ns.Finite(since) and since or 0
	limit = ns.Finite(limit) and math.max(1, math.min(most or KEEP_MAX, math.floor(limit))) or 50
	local out = {}
	for i = #items, 1, -1 do
		local item = items[i]
		if #out >= limit or not (tonumber(item.id) and item.id > since) then break end
		table.insert(out, 1, item)
	end
	local last = items[#items]
	return { items = out, next = last and last.id or since }
end
