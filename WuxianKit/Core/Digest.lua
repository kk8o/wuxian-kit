-- The digest (摘要): items gathered into wakes instead of sent one by one, for apps (Apps/Deliver.lua makes the
-- host). A host is { ext, spec = { digest = { urgent(self, options, item) } }, Wrap(host, s)?, Send(host, data) ->
-- whether it went } and a run s is { options = { digest }, buffer, first, last, urgentAt, wakes, lastWake, started,
-- sent, skipped, retry, reason, quiet }.
--   ns.Digest.Params(host, s)         the digest now: the run's options.digest, then the host spec's, then the defaults
--   ns.Digest.Hold(host, s, item)     an item into the run's buffer (the oldest go when it holds too many)
--   ns.Digest.Gather(host, s, item)   an item gathered (and a wake when its time has come)
--   ns.Digest.Due(host, s)            a wake when its time has come (the host's ticker asks every second)
--   ns.Digest.Wake(host, s, reason)   one wake of what is gathered, sent by host:Send(data); whether it went
--   ns.Digest.Small(v)                a copy of v as saved variables and wakes hold it: data only, texts and depth cut
--   ns.Digest.Fit(v)                  v (such a copy) within what one item may take of a wake
-- A wake is { seq, reason, items (oldest first), skipped, after, next } and what host:Wrap(s) adds. reason is "urgent",
-- "full", "batch", "idle" (or the host's own, "item"): gather s (5) after an urgent item, at once at most (30) of them
-- (not while s.quiet: quiet hours wake for urgent items only), every s (60; false: only urgent or full) after the
-- first one gathered, and after idle s (false: never) without an item or a wake (an idle wake carries what is
-- gathered: nothing, unless every is false). urgent may be a list instead: an item is urgent when its why or its kind
-- is in it (ns.UrgentList).
-- One cursor, the items' ids: a wake covers every item of the run with after < id <= next, of which the oldest
-- `skipped` are not in it (the buffer was full: at most HELD times `most` wait, in quiet hours `most`; the host's ring
-- still has them). after is the next of the wake sent before (s.sent; the host sets it for a run's first), seq counts
-- the wakes that went, from 1.
-- A wake that does not go (host:Send answers false) changes nothing: its items stay first in the buffer, s.wakes and
-- s.sent stay, and Due sends it again a second later (s.retry), with the same reason and whatever came meanwhile.
-- A wake keeps under WAKE_MAX bytes as WoWBridge writes it (ns.WireSize; WoWBridge cuts an event of more than 8000 to
-- {cut = true}): the items that do not fit stay in the buffer and go with the next wake, a second later. What Wrap adds
-- is at most WRAP_MAX (the host sees to it) and an item at most ITEM_MAX (Fit), so the oldest item always fits.
-- Also here: ns.Lease (a lease as kept), ns.RingRecent (what a ring answers for since and limit).
local _, ns = ...
local Kit = ns.Kit

local KEEP_MAX, ITEM_TEXT, ITEM_DEPTH = 200, 500, 6       -- 6: a route step goal's place and quest (item, data, goals, goal, place)
local ITEM_TEXT_SHORT = 120                             -- the texts of an item that is too large
local LEASE_MIN = 60
-- 8000 is WoWBridge's line; 200 is room for seq, reason, skipped, after, next and the items' brackets
local WAKE_MAX, WRAP_MAX, ITEM_MAX = 7200, 5300, 1700
local HELD = 4
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

-- a copy of v, data only: texts of at most `text` bytes, tables to ITEM_DEPTH levels; a value the client keeps secret
-- is left out (its length, even, would raise)
local function Small(v, depth, text)
	v = Kit:Value(v)
	local t = type(v)
	if t == "string" then return ns.Cut(v, text) end
	if t == "number" then return ns.Finite(v) and v or nil end
	if t == "boolean" then return v end
	if t ~= "table" or depth > ITEM_DEPTH then return nil end
	local out = {}
	for k, x in pairs(v) do
		if type(k) == "string" or type(k) == "number" then out[k] = Small(x, depth + 1, text) end
	end
	return out
end

local function ItemSize(v)                               -- (an item is two levels inside its wake)
	return ns.WireSize(v, 4)
end

-- v (a Small copy) as one item of a wake, at most ITEM_MAX bytes: one larger has its texts cut shorter, then loses the
-- tables in it, then everything; cut = true says so
local function Fit(v)
	if ItemSize(v) <= ITEM_MAX then return v end
	local room = ITEM_MAX - 12                           -- (for cut = true)
	local out = Small(v, 1, ITEM_TEXT_SHORT)
	if ItemSize(out) > room then
		local top = {}
		for k, x in pairs(out) do
			if type(x) ~= "table" then top[k] = x end
		end
		out = ItemSize(top) <= room and top or {}
	end
	out.cut = true
	return out
end

-- the oldest gathered items beyond `limit` go (the host's ring still has them): the next wake's skipped counts them
local function Shed(s, limit)
	local over = #s.buffer - limit
	if over <= 0 then return end
	local kept = {}
	for i = over + 1, #s.buffer do kept[#kept + 1] = s.buffer[i] end
	s.buffer, s.skipped = kept, (tonumber(s.skipped) or 0) + over
end

-- an item into the buffer; the digest's parameters
local function Hold(host, s, item)
	local d = Params(host, s)
	s.buffer = type(s.buffer) == "table" and s.buffer or {}
	s.buffer[#s.buffer + 1] = item
	Shed(s, s.quiet and d.most or d.most * HELD)
	return d
end

-- one wake of what is gathered (the oldest items that fit), sent by host:Send(data); whether it went
local function Wake(host, s, reason)
	if host.sending then return false end                 -- (asked by one who hears this very wake: with the next)
	if s.urgentAt then reason = "urgent" end
	local now = time()
	local data = host.Wrap and host:Wrap(s) or {}
	local after = ns.Finite(s.sent) and s.sent or 0
	data.seq, data.reason, data.skipped = (tonumber(s.wakes) or 0) + 1, reason, tonumber(s.skipped) or 0
	data.after, data.next, data.items = after, 2 ^ 53, {}   -- (next: as long as it gets, for the size)
	local total, n = ns.WireSize(data), 0
	for _, item in ipairs(type(s.buffer) == "table" and s.buffer or {}) do
		local size = ItemSize(item) + 1
		if total + size > WAKE_MAX and n > 0 then break end   -- (the oldest goes whatever its size: the buffer must empty)
		total, n = total + size, n + 1
		data.items[n] = item
	end
	local last = n > 0 and data.items[n].id
	data.next = ns.Finite(last) and last or after
	host.sending = true
	local ok, went = pcall(host.Send, host, data)
	host.sending = nil
	if not ok then geterrorhandler()(went) end
	if not (ok and went) then
		s.retry, s.reason = now + 1, reason
		return false
	end
	local gone, rest = {}, {}
	for i = 1, n do gone[data.items[i]] = true end
	for _, item in ipairs(type(s.buffer) == "table" and s.buffer or {}) do
		if not gone[item] then rest[#rest + 1] = item end
	end
	local skipped = (tonumber(s.skipped) or 0) - data.skipped
	s.buffer, s.skipped = rest, skipped > 0 and skipped or nil
	s.wakes, s.lastWake, s.sent, s.urgentAt = data.seq, now, data.next, nil
	if #rest > 0 then                                     -- what did not fit: the same wake goes on, a second later
		s.retry, s.reason = now + 1, reason
	else
		s.first, s.retry, s.reason = nil, nil, nil
	end
	return true
end

-- a wake when its time has come: first of all the one that did not go, or the rest of one that did not fit
local function Due(host, s)
	local now = time()
	if s.retry then
		if now >= (tonumber(s.retry) or 0) then Wake(host, s, s.reason or "batch") end
		return
	end
	local d = Params(host, s)
	s.buffer = type(s.buffer) == "table" and s.buffer or {}
	if s.quiet then Shed(s, d.most) end
	local n = #s.buffer
	if n >= d.most and not s.quiet then
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
	local d, now = Hold(host, s, item), time()
	s.first, s.last = s.first or now, now
	if d.urgent and not s.urgentAt then
		local ok, yes = pcall(d.urgent, host.ext, s.options, item)
		if not ok then geterrorhandler()(yes) elseif yes then s.urgentAt = now end
	end
	Due(host, s)
end

ns.Digest = { Params = Params, Hold = Hold, Gather = Gather, Due = Due, Wake = Wake, Fit = Fit, WRAP_MAX = WRAP_MAX,
	Small = function(v) return Small(v, 1, ITEM_TEXT) end }

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
