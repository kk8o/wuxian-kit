-- Proposals: every Say and Do goes the same way. WuxianKit:Call / :Propose check the args and each step's check, make the
-- preview lines, and the proposal waits for the player (the proposal window) until it expires (ttl, 300 s by default).
-- The title and, for another player's proposal, every preview line are escaped (WuxianKit:Escape): text from outside
-- never draws colors, textures or lines of its own. The player's Run runs it: not before its `after` time, nor while a
-- step is not ready (its spec's ready, or its kind's: a Say waits out chat lockdown); a proposal with a Do step clicked
-- in combat waits for the end of combat, and is checked again then. Each Do step's snapshot is taken right before its
-- apply; a step the game does a moment later (its spec's settled) is waited for before the next one, and a step that
-- must not run in combat waits for the end of it when combat began meanwhile ("queued" again, the rest after combat);
-- a step that fails (one that changed the game before it failed included), or does not show in time, stops the proposal
-- and the steps that ran are put back (restore(snapshot), or apply of the snapshot when it has the args' shape). Only a
-- capability that is still live runs: an extension turned off takes its proposals with it. The preview says by itself
-- which steps cannot be undone and which take effect after a reload. What ran is kept (WuxianKitDB.history, the last
-- HISTORY_KEPT, each with the character it ran on) so that the player, or a proposal of the agent's, can undo it later
-- on that character. Until it runs the player can stop it: Decline while it waits for the click, Cancel (the core's
-- page, /wk no [id]) while it waits for its time or for the end of combat, asked or not; one stopped half way has what
-- ran put back. Queued and running proposals do not expire.
-- The player may let a scope go without asking (pre-approval, in the window); a proposal whose every step falls under
-- such a scope runs without the click, unless it came from another player (source "remote:...") or from a profile
-- someone shared ("import:..."), and the grants are asked again right before it runs: one the player took back meanwhile
-- turns it into one that asks. Only the window sets grants (ns.Act, private to the core's files; nothing in the public
-- WuxianKit table does), and the grants that count live in this file, written to the saved variables at logout over
-- whatever else wrote there. Code running in the game could still click the window's buttons (measured on
-- 1.60.1.70245: a click handler cannot tell a :Click() from code from the player's), as it could change the game
-- directly: the hard boundary is hot loading off, when the agent reaches the game only through the capabilities
-- addons expose. Every change of state is the bus event "kit.proposal" (and so an agent event).
local _, ns = ...
local Kit, L, KINDS = ns.Kit, ns.L, ns.KINDS

local TTL, TTL_MIN, TTL_MAX = 300, 10, 600
local TITLE_MAX = 120                     -- bytes of a proposal's title
local HISTORY_KEPT, FINISHED_KEPT = 50, 30
local SETTLE_TIME, SETTLE_EVERY = 5, 0.1    -- how long a step may take to show in the game, and how often it is asked
local FINAL = { done = true, failed = true, declined = true, expired = true, undone = true }
local OPEN = { pending = true, waiting = true, queued = true }   -- not run yet: the player can still stop them

local proposals = {}                      -- id -> proposal: the open ones and the last FINISHED_KEPT finished
local waiting = {}                        -- ids of the open ones, oldest first
local grants = {}                         -- scope -> true: the player's "without asking"; the only copy that counts
local undoQueue = {}                      -- history ids the player undid in combat

------------------------------------------------------------------------------------------------------------------------
-- a proposal's text

-- who made it, for the player (a kind without a name: the kind alone)
function ns.SourceText(s)
	local kind, who = s:match("^(%a+):?(.*)$")
	if (who or "") == "" and L.SOURCE_ANY[kind or ""] then return L.SOURCE_ANY[kind] end
	local f = L.SOURCE[kind or ""] or L.SOURCE.addon
	return f:find("%%s") and f:format(ns.Escape(who ~= "" and who or "?")) or f
end

-- a line of another player's proposal as the player may see it: as its extension made it when what came from the args
-- is escaped (only ||, the core's grey and |r are left of codes), else escaped whole
local function Safe(line)
	local rest = line:gsub("||", ""):gsub("|cff9c9ea6", ""):gsub("|r", "")
	if rest:find("|", 1, true) then return ns.Escape(line) end
	return line
end

-- the preview of a step: its lines (the spec's preview: a line or a list of them; its title without one; plain: each
-- line made safe, for another player's proposal), and what the core knows by itself (unless the spec says notes =
-- false): a Do it cannot undo, a change that waits for a reload
-- whether a step takes effect after a reload: reload = true, or reload(self, args) for one that depends on its args
function ns.Reloads(cap, args)
	local r = cap.spec.reload
	if type(r) == "function" then
		local ok, v = pcall(r, cap.ext, args)
		return ok and v and true or false
	end
	return r and true or false
end

local function Lines(cap, args, plain)
	local spec, out = cap.spec, { ns.T(cap.title) }
	if type(spec.preview) == "function" then
		local ok, v = pcall(spec.preview, cap.ext, args)
		if not ok then error(("%s: its preview failed: %s"):format(cap.id, ns.Text(v)), 0) end
		if type(v) == "string" then
			out = { v }
		elseif type(v) == "table" and #v > 0 then
			out = {}
			for i, line in ipairs(v) do out[i] = ns.Text(line) end
		end
	end
	if plain then
		for i, line in ipairs(out) do out[i] = Safe(line) end
	end
	if spec.notes == false then return out end
	if cap.kind == "do" and not cap.undoable then out[#out + 1] = "|cff9c9ea6" .. L.NO_UNDO .. "|r" end
	if ns.Reloads(cap, args) then out[#out + 1] = "|cff9c9ea6" .. L.RELOAD_NOTE .. "|r" end
	return out
end

-- a step's args as callers and the agent see them: a long text shortened (a layout's share string is thousands of
-- bytes, and every change of state sends the summary again)
local function Brief(args)
	local out = {}
	for k, v in pairs(args or {}) do
		if type(v) == "string" and #v > 200 then
			v = v:sub(1, 60):gsub("[\192-\255][\128-\191]*$", "") .. ("...(%d bytes)"):format(#v)
		end
		out[k] = v
	end
	return out
end

ns.Brief = Brief

-- a preview as the agent reads it (Bridge.lua): plain text, no color, texture or link codes, an escaped "||" back to "|".
-- Callers and the bus keep the lines as the window shows them, escaped, so that an addon may show them as they are.
local function Plain(lines)
	local out = {}
	for i, line in ipairs(type(lines) == "table" and lines or {}) do
		if type(line) == "string" then
			line = line:gsub("||", "\1"):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|T.-|t", "")
				:gsub("|H.-|h(.-)|h", "%1"):gsub("\1", "|")
		end
		out[i] = line
	end
	return out
end
ns.Plain = Plain

-- a proposal as callers and the agent see it
local function Summary(p)
	local steps = {}
	for i, s in ipairs(p.steps) do
		steps[i] = { cap = s.cap.id, args = Brief(s.args), preview = s.preview, scope = s.scope, result = s.result }
	end
	return { id = p.id, state = p.state, title = p.title, source = p.source, created = p.created, expires = p.expires,
		after = p.after, steps = steps, error = p.error, auto = p.auto or nil, undoable = p.undoable or nil }
end

local function Prune()
	local done = {}
	for id, p in pairs(proposals) do
		if FINAL[p.state] then done[#done + 1] = id end
	end
	table.sort(done)
	for i = 1, #done - FINISHED_KEPT do proposals[done[i]] = nil end
end

local function Unwait(p)
	for i, id in ipairs(waiting) do
		if id == p.id then
			table.remove(waiting, i)
			return
		end
	end
end

local function SetState(p, state)
	p.state = state
	if FINAL[state] then
		Unwait(p)
		Prune()
	end
	if ns.UI then ns.UI.Refresh() end
	Kit:Emit("kit.proposal", Summary(p))
end

------------------------------------------------------------------------------------------------------------------------
-- running

local function Restore(cap, snap)
	if type(cap.spec.restore) == "function" then return cap.spec.restore(cap.ext, snap) end
	return cap.spec.apply(cap.ext, snap)
end

-- what keeps a proposal from running now: "after" (its time has not come), a step's reason (its spec's ready, else its
-- kind's; a ready that breaks says not now), or nil
local function Blocked(p)
	if p.after and time() < p.after then return "after" end
	for _, s in ipairs(p.steps) do
		local ready = s.cap.spec.ready or KINDS[s.cap.kind].ready
		if type(ready) == "function" then
			local ok, why = pcall(ready, s.cap.ext, s.args)
			if not ok then return ns.Text(why) end
			if why then return why end
		end
	end
end
ns.Blocked = Blocked

-- what keeps it from running, for the player
local function WhyText(p, why)
	if why == "after" then return L.RUNS_IN:format(p.after - time()) end
	return ns.Text(why)
end

-- whether a step changes something a fight must not see changed: one whose kind waits for peace, unless its spec says
-- combat = true
local function StepNeedsPeace(s)
	return KINDS[s.cap.kind].peace and s.cap.spec.combat ~= true or false
end

local function NeedsPeace(p)
	for _, s in ipairs(p.steps) do
		if StepNeedsPeace(s) then return true end
	end
	return false
end
ns.NeedsPeace = NeedsPeace

-- the character the game runs (history entries are theirs: undo only where they ran)
local function Me()
	return UnitGUID and UnitGUID("player") or nil
end

local function Mine(e)
	return e.who == nil or e.who == Me()
end

-- what ran, kept for undo: the steps with their snapshots (a Say step is kept but cannot be taken back)
local function Remember(p)
	local steps, undoable = {}, false
	for i, s in ipairs(p.steps) do
		steps[i] = { cap = s.cap.id, args = s.args, snap = s.snap, preview = s.preview }
		if s.snap ~= nil then undoable = true end
	end
	p.undoable = undoable
	local db = ns.db
	if not db then return end
	db.history = type(db.history) == "table" and db.history or {}
	local h = db.history
	h[#h + 1] = { id = p.id, title = p.title, source = p.source, ran = time(), steps = steps, undoable = undoable or nil,
		who = Me() }
	while #h > HISTORY_KEPT do table.remove(h, 1) end
end

-- the steps that ran put back, last first; how many
local function RollBack(p)
	local back = 0
	for j = #(p.done or {}), 1, -1 do
		local d = p.done[j]
		if d.snap ~= nil and pcall(Restore, d.cap, d.snap) then back = back + 1 end
	end
	p.rolledBack, p.done, p.resume = back, {}, nil
	return back
end

-- step i failed (or did not show in time): the steps that ran are put back. The player reads which step in their
-- language; the agent gets the reason (error)
local function Fail(p, i, why)
	local back = RollBack(p)
	p.error = ("step %d (%s): %s"):format(i, p.steps[i].cap.id, ns.Text(why))
	ns.Say(L.FAILED:format(p.id, i, ns.T(p.steps[i].cap.title)) .. (back > 0 and L.ROLLED_BACK or ""))
	SetState(p, "failed")
end

-- a proposal stopped half way (the player cancelled it, its extension went off): what ran is put back now, or after
-- combat when a step of it must not change in a fight
local function Stop(p, said)
	for _, d in ipairs(p.done or {}) do
		if StepNeedsPeace(d) and InCombatLockdown() then
			p.stopping = said
			ns.Say(L.STOP_AFTER_COMBAT:format(p.id))
			return
		end
	end
	local back = RollBack(p)
	p.stopping = nil
	ns.Say(said .. (back > 0 and L.ROLLED_BACK or ""))
	SetState(p, "declined")
end

local function Finish(p)
	p.ran = time()
	Remember(p)
	ns.Say((p.auto and L.AUTO_DONE or L.DONE):format(p.id))
	for _, s in ipairs(p.steps) do
		if ns.Reloads(s.cap, s.args) then
			ns.Say(L.RELOAD_HINT)
			break
		end
	end
	SetState(p, "done")
end

local settling, settleTicker = {}, nil  -- { p, i, ends }: a proposal waiting for its step i to show in the game
local Continue

local function Settle()
	for n = #settling, 1, -1 do
		local w = settling[n]
		local s = w.p.steps[w.i]
		local ok, yes, why = pcall(s.cap.spec.settled, s.cap.ext, s.args, s.result)
		if ok and yes then
			table.remove(settling, n)
			Continue(w.p, w.i + 1)
		elseif GetTime() >= w.ends then
			table.remove(settling, n)
			Fail(w.p, w.i, (not ok and yes) or why or "the game did not show it in time")
		end
	end
	if #settling == 0 and settleTicker then
		settleTicker:Cancel()
		settleTicker = nil
	end
end

-- runs steps i.. of p, each Do's snapshot right before its apply; one the game does a moment later (settled) is waited
-- for, asked every SETTLE_EVERY seconds, before the next. A capability no longer live fails its step; a step that must
-- not run in a fight that began meanwhile waits for the end of it (the proposal queued again, from that step)
function Continue(p, i)
	for j = i, #p.steps do
		local s = p.steps[j]
		if ns.caps[s.cap.id] ~= s.cap then return Fail(p, j, "its extension is off") end
		if StepNeedsPeace(s) and InCombatLockdown() then
			p.resume = j
			ns.Say(L.PAUSED:format(p.id) .. L.CANCEL_HINT:format(p.id))
			return SetState(p, "queued")
		end
		local spec, ext, failed, applied = s.cap.spec, s.cap.ext, nil, false
		if s.cap.kind == "do" and type(spec.snapshot) == "function" then
			local ok, snap = pcall(spec.snapshot, ext, s.args)
			if ok then s.snap = snap else failed = snap end
		end
		if not failed then
			applied = true
			local ok, res = pcall(spec.apply, ext, s.args)
			if ok then s.result = res else failed = res end
		end
		if failed then
			if applied and s.snap ~= nil then p.done[#p.done + 1] = s end   -- it may have changed the game before it failed
			return Fail(p, j, failed)
		end
		if type(s.result) == "table" and s.result.unchanged then
			s.snap = nil                                    -- it changed nothing: nothing to put back, on undo or on a failure
		else
			p.done[#p.done + 1] = s
		end
		if type(spec.settled) == "function" then
			local ok, yes = pcall(spec.settled, ext, s.args, s.result)
			if not (ok and yes) then
				settling[#settling + 1] = { p = p, i = j, ends = GetTime() + (tonumber(spec.settleTime) or SETTLE_TIME) }
				if not settleTicker then settleTicker = C_Timer.NewTicker(SETTLE_EVERY, Settle) end
				return
			end
		end
	end
	Finish(p)
end

local function Run(p)
	p.state, p.done = "running", {}
	Continue(p, 1)
end

-- whether it runs without the click: every step under a scope the player pre-approved, and not another player's
-- proposal nor a shared profile's
local function Granted(p)
	if p.source:match("^remote") or p.source:match("^import") then return false end
	for _, s in ipairs(p.steps) do
		if not grants[s.scope] then return false end
	end
	return true
end

-- run it now, or queue it for the end of combat; false + reason when it cannot run yet. One that was to run without the
-- click asks for it when the player took back a scope it falls under meanwhile
local function Go(p)
	if p.auto and not Granted(p) then
		p.auto = nil
		ns.Say(L.ASKS_NOW:format(p.id))
		SetState(p, "pending")
		if ns.UI then ns.UI.Show(p.id) end
		return true
	end
	local why = Blocked(p)
	if why then return false, why end
	if NeedsPeace(p) and InCombatLockdown() then
		if p.state ~= "queued" then
			ns.Say((p.auto and L.AUTO_QUEUED or L.QUEUED):format(p.id) .. L.CANCEL_HINT:format(p.id))
			SetState(p, "queued")
		end
		return true
	end
	Run(p)
	return true
end

------------------------------------------------------------------------------------------------------------------------
-- making one

-- a step that goes in a proposal of its own (its spec's alone: true, or a function of its args): a message to a public
-- channel must go from the player's click itself, never from a later moment of a longer proposal
local function Alone(s)
	local a = s.cap.spec.alone
	if type(a) == "function" then
		local ok, v = pcall(a, s.cap.ext, s.args)
		return ok and v and true or false
	end
	return a == true
end

-- a proposal of checked steps ({ cap, args }); its summary
function ns.Propose(list, opts)
	opts = type(opts) == "table" and opts or {}
	local source = type(opts.source) == "string" and opts.source ~= "" and opts.source or "addon"
	local title = type(opts.title) == "string" and opts.title ~= "" and ns.Cut(ns.Escape(opts.title), TITLE_MAX) or nil
	local p = { steps = {}, title = title, created = time(), source = source }
	local ttl = tonumber(opts.ttl)
	p.expires = p.created + math.max(TTL_MIN, math.min(ns.Finite(ttl) and ttl or TTL, TTL_MAX))
	local after = tonumber(opts.after)
	if after and not ns.Finite(after) then error("after: a time() (a finite number)", 0) end
	if after and after > p.created then
		if after >= p.expires then error("after: later than the proposal's end (its ttl)", 0) end
		p.after = math.floor(after)
	end
	local plain = source:match("^remote:") ~= nil
	for i, s in ipairs(list) do
		local check = s.cap.spec.check
		if type(check) == "function" then
			local ok, why = pcall(check, s.cap.ext, s.args)
			if not ok or why then error(("%s: %s"):format(s.cap.id, ns.Text(why)), 0) end
		end
		if #list > 1 and Alone(s) then error(("%s: it goes in a proposal of its own"):format(s.cap.id), 0) end
		p.steps[i] = { cap = s.cap, args = s.args, preview = Lines(s.cap, s.args, plain), scope = ns.ScopeOf(s.cap, s.args) }
	end
	local db = ns.db
	p.id = db and tonumber(db.nextId) or 1
	if db then db.nextId = p.id + 1 end
	proposals[p.id] = p
	waiting[#waiting + 1] = p.id
	if Granted(p) then
		p.auto = true
		p.state = "waiting"
		Kit:Emit("kit.proposal", Summary(p))
		local ok, why = Go(p)                 -- now, or when combat ends; while blocked the ticker tries again
		if not ok then
			ns.Say(L.AUTO_LATER:format(p.id, WhyText(p, why)) .. L.CANCEL_HINT:format(p.id))
			if ns.UI then ns.UI.Refresh() end
		end
	else
		SetState(p, "pending")
		if ns.UI then ns.UI.Show(p.id) end
	end
	return Summary(p)
end

------------------------------------------------------------------------------------------------------------------------
-- what the player does

-- no to a proposal not run yet: declined while it waits for the click, cancelled while it waits for its time or for the
-- end of combat (its state is "declined" either way)
local function Decline(id)
	local p = proposals[id]
	if not p or not OPEN[p.state] or p.stopping then return false end
	if p.resume then                                  -- stopped half way: what ran goes back
		Stop(p, L.CANCELLED:format(p.id))
		return true
	end
	ns.Say((p.state == "pending" and L.DECLINED or L.CANCELLED):format(p.id))
	SetState(p, "declined")
	return true
end

local function Approve(id)
	local p = proposals[id]
	if not p or p.state ~= "pending" then return false end
	local ok, why = Go(p)
	if not ok then ns.Say(WhyText(p, why)) end
	return ok
end

local function Grant(scope, on)
	if type(scope) ~= "string" then return false end
	grants[scope] = on and true or nil
	if ns.UI then ns.UI.Refresh() end
	return true
end

-- puts back what history entry `id` changed (its steps in reverse); in combat it waits for the end of it
local function Undo(id)
	local h
	for _, e in ipairs(ns.db and ns.db.history or {}) do
		if e.id == id then h = e end
	end
	if not h or h.undone or not h.undoable then return false, "nothing to undo" end
	if not Mine(h) then return false, L.OTHER_CHARACTER end
	if InCombatLockdown() then
		undoQueue[#undoQueue + 1] = id
		ns.Say(L.UNDO_QUEUED:format(id))
		return true
	end
	local failed
	for j = #h.steps, 1, -1 do
		local s = h.steps[j]
		if s.snap ~= nil then
			local cap = ns.caps[s.cap]
			if not cap then
				failed = failed or L.CAP_OFF:format(s.cap)
			else
				local ok, err = pcall(Restore, cap, s.snap)
				if not ok then failed = failed or ns.Text(err) end
			end
		end
	end
	if failed then
		ns.Say(L.UNDO_FAILED:format(id, failed))
		return false, failed
	end
	h.undone = time()
	ns.Say(L.UNDONE:format(id))
	local p = proposals[id]
	if p then
		SetState(p, "undone")
	else
		Kit:Emit("kit.proposal", { id = id, state = "undone", title = h.title, source = h.source })
		if ns.UI then ns.UI.Refresh() end
	end
	return true
end
ns.UndoNow = Undo                        -- for the core's undo capability (Builtins.lua), which runs inside a proposal

local ACTIONS = { run = Approve, decline = Decline, grant = Grant, undo = Undo }

-- more of what the player does, from the core's other files
function ns.AddAction(name, fn)
	ACTIONS[name] = fn
end

-- what the player did on the core's windows, its slash command or key bindings
function ns.Act(action, ...)
	local fn = ACTIONS[action]
	if not fn then return false end
	return fn(...)
end

------------------------------------------------------------------------------------------------------------------------
-- reading them

-- the proposals still open (oldest first) and the last finished ones, as summaries
function Kit:Proposals()
	local out = {}
	for _, p in pairs(proposals) do out[#out + 1] = Summary(p) end
	table.sort(out, function(a, b) return a.id < b.id end)
	return out
end

function Kit:Proposal(id)
	local p = proposals[tonumber(id)]
	return p and Summary(p) or nil
end

-- whether the player lets scope go without asking
function Kit:Granted(scope)
	return grants[scope] == true
end

-- the ids waiting for the player's click, oldest first
function ns.Waiting()
	local out = {}
	for _, id in ipairs(waiting) do
		local p = proposals[id]
		if p and p.state == "pending" then out[#out + 1] = id end
	end
	return out
end

-- the ids not run yet, oldest first: waiting for the click, for their time or for the end of combat
function ns.Open()
	local out = {}
	for _, id in ipairs(waiting) do
		local p = proposals[id]
		if p and OPEN[p.state] then out[#out + 1] = id end
	end
	return out
end

function ns.Get(id) return proposals[id] end

-- what ran on this character, oldest first (another character's entries stay theirs)
function ns.History()
	local out = {}
	for _, e in ipairs(ns.db and type(ns.db.history) == "table" and ns.db.history or {}) do
		if Mine(e) then out[#out + 1] = e end
	end
	return out
end
function ns.Grants()
	local copy = {}
	for k in pairs(grants) do copy[k] = true end
	return copy
end

------------------------------------------------------------------------------------------------------------------------
-- the clock, combat, load and logout

local function Tick()
	local now = time()
	for _, id in ipairs({ unpack(waiting) }) do
		local p = proposals[id]
		if p and (p.state == "pending" or p.state == "waiting") and now >= p.expires then
			ns.Say(L.EXPIRED:format(p.id))
			SetState(p, "expired")
		elseif p and p.state == "waiting" then
			Go(p)                                              -- a granted one whose time has come, or that is ready now
		end
	end
	if ns.UI then ns.UI.Tick() end
end

-- combat over: a proposal stopped half way in it is put back; one paused half way goes on from its step; one queued
-- before it ran is checked again (the grants, its time, chat lockdown, its steps' ready) and runs, or waits until it
-- can (the clock asks every second)
local function PeaceAgain()
	for _, id in ipairs({ unpack(waiting) }) do
		local p = proposals[id]
		if p and p.stopping then
			Stop(p, p.stopping)
		elseif p and p.state == "queued" and p.resume then
			local j = p.resume
			p.resume, p.state = nil, "running"
			Continue(p, j)
		elseif p and p.state == "queued" then
			if not Go(p) then SetState(p, "waiting") end
		end
	end
	local undo = undoQueue
	undoQueue = {}
	for _, id in ipairs(undo) do Undo(id) end
end

-- an extension turned off: its proposals not run yet are declined, one stopped half way has what ran put back, one
-- waiting for a step to show in the game fails
function ns.ForgetExtension(ext)
	local function Has(p)
		for _, s in ipairs(p.steps) do
			if s.cap.ext == ext then return true end
		end
		return false
	end
	for n = #settling, 1, -1 do
		local w = settling[n]
		if Has(w.p) then
			table.remove(settling, n)
			Fail(w.p, w.i, "its extension was turned off")
		end
	end
	for _, id in ipairs({ unpack(waiting) }) do
		local p = proposals[id]
		if p and OPEN[p.state] and not p.stopping and Has(p) then
			local said = L.DROPPED:format(p.id, ns.T(ext.title))
			if p.resume then
				Stop(p, said)
			else
				ns.Say(said)
				SetState(p, "declined")
			end
		end
	end
end

ns.When("load", function(db)
	db.nextId = tonumber(db.nextId) or 1
	db.history = type(db.history) == "table" and db.history or {}
	for scope, on in pairs(type(db.grants) == "table" and db.grants or {}) do
		if on == true and type(scope) == "string" then grants[scope] = true end
	end
end)

-- at logout the grants that count go to the saved variables, over whatever else wrote there meanwhile; the saved table
-- is put back too, in case something replaced it
ns.When("logout", function(db)
	if not db then return end
	local copy = {}
	for k in pairs(grants) do copy[k] = true end
	db.grants = copy
	WuxianKitDB = db
end)

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_REGEN_ENABLED")
events:RegisterEvent("PLAYER_REGEN_DISABLED")
events:SetScript("OnEvent", function(_, event)
	if event == "PLAYER_REGEN_ENABLED" then PeaceAgain() end
	if ns.UI then ns.UI.Refresh() end
end)
C_Timer.NewTicker(1, Tick)
