-- The core's own extension, "kit", written as any extension is: what the agent (or another addon) can ask of the core.
--   kit.extensions        (See)  the extensions: built in, another addon's (loaded or not), on or off
--   kit.capabilities      (See)  every live capability with its kind, doc and args
--   kit.proposals         (See)  the proposals still open and the last finished ones; kit.proposal one of them
--   kit.history           (See)  what ran on this character (of the last 50), to undo
--   kit.extension.get/set        a Setting: whether an extension is on; turning one on or off is a proposal, undoable
--   kit.undo              (Do)   undo a proposal that ran
local _, ns = ...
local Kit, L = ns.Kit, ns.L

local kit = Kit:Extension("kit", { title = L"CORE", version = Kit.VERSION })
kit:Scope("extensions", L"SCOPE_EXTENSIONS")
kit:Scope("undo", L"SCOPE_UNDO")

kit:See("extensions", { title = L"LIST_EXTENSIONS",
	doc = "the extensions: id, title, version, addon, builtin, state (on, off, disabled in the game's addon list, missing: "
		.. "cannot load), how many capabilities",
	run = function() return ns.ExtensionList() end })

kit:See("capabilities", { title = L"LIST_CAPABILITIES",
	doc = "every capability of the extensions that are on: id, kind (see, keep and point run at once; say and do make a "
		.. "proposal the player confirms), title, doc, args (name -> \"string\", \"number?\", \"a|b\"...), undoable",
	run = function() return Kit:Capabilities() end })

kit:See("proposals", { title = L"LIST_PROPOSALS",
	doc = "the proposals still open and the last finished ones: id, state (pending: waits for the player; waiting: "
		.. "pre-approved or confirmed, for its time or until it can run; queued: after combat; running: a step waits for "
		.. "the game to show it; done, failed, declined, expired, undone), title, source, steps with their preview and "
		.. "result, error. Pending and waiting ones expire; queued and running ones do not",
	run = function() return Kit:Proposals() end })

kit:See("proposal", { title = L"ONE_PROPOSAL", args = { id = "number" },
	doc = "one proposal by its id: its state, steps, results, error",
	run = function(_, a)
		return Kit:Proposal(a.id) or error(("no proposal %d (only the open and the recent ones are kept)"):format(a.id), 0)
	end })

kit:See("history", { title = L"HISTORY",
	doc = "what ran on this character, newest last (of the last 50 proposals): id, title, source, ran (time()), steps "
		.. "{cap, args (a long text shortened), preview}, undoable, undone",
	run = function()                                     -- as the proposals read: no snapshots, no layout strings in full
		local out = {}
		for i, e in ipairs(ns.History()) do
			local steps = {}
			for j, s in ipairs(e.steps or {}) do steps[j] = { cap = s.cap, args = ns.Brief(s.args), preview = s.preview } end
			out[i] = { id = e.id, title = e.title, source = e.source, ran = e.ran, steps = steps, undoable = e.undoable,
				undone = e.undone }
		end
		return out
	end })

kit:Setting("extension", { title = L"SWITCH", doc = "whether an extension is on",
	key = { extension = "string" }, value = "boolean", scope = "extensions",
	check = function(_, k)
		if k.extension == "kit" then return "WuxianKit's core stays on" end
		if not ns.extensions[k.extension] and not ns.Installed()[k.extension] then
			return ("no extension %s (kit.extensions lists them)"):format(k.extension)
		end
	end,
	get = function(_, k)
		local ext = ns.extensions[k.extension]
		return ext ~= nil and ext.active == true
	end,
	set = function(_, k, on)
		local ok, why = ns.Switch(k.extension, on)
		if not ok then error(("could not turn %s %s: %s"):format(k.extension, on and "on" or "off", ns.Text(why)), 0) end
	end,
	label = function(_, k)
		local ext = ns.extensions[k.extension] or ns.Installed()[k.extension]
		return ext and ns.T(ext.title) or k.extension
	end,
	format = function(_, v) return v and L.STATE.on or L.STATE.off end })

kit:See("manifest", { title = L"MANIFEST",
	doc = "what the agent may use (the Agent access spec): protocol, kit (version), language, revision, extensions [{id, "
		.. "title, version, addon, builtin, state, docs (the folder under Interface\\AddOns of its AGENT.md and skills/), "
		.. "capabilities, events}], the capabilities and events of those that are on. For 无限工坊's app",
	run = function() return Kit:Manifest() end })
kit:See("revision", { title = L"REVISION", doc = "the manifest's revision: {revision}; it changes whenever the manifest does",
	run = function() return { revision = Kit:Manifest().revision } end })
kit:Event("proposal", { doc = "a proposal changed state: pending, waiting (for its time, or until it can run), queued "
	.. "(after combat), done, failed, declined, expired, undone",
	data = { id = "number", state = "string", title = "string?", source = "string", error = "string?" } })
kit:Event("extension", { doc = "an extension went on or off", data = { id = "string", on = "boolean" } })
kit:Event("dropped", { doc = "extension events that were not sent because they came faster than the link carries "
	.. "(the core's own always go): how many, by topic", data = { count = "number", topics = "table" } })
kit:Event("changed", { doc = "the manifest changed: an extension on or off, a capability, the language",
	data = { revision = "string" } })
kit:Event("ready", { doc = "WuxianKit is up, after a login or a reload", data = { version = "string", extensions = "table",
	revision = "string" } })
kit:Event("feed", { doc = "a feed started or stopped", data = { extension = "string", feed = "string", on = "boolean",
	ends = "number?", options = "table?" } })

kit:Do("undo", { title = L"UNDO", args = { id = "number" }, scope = "undo", notes = false,
	doc = "undo a proposal that ran (see kit.history): what its steps changed is put back, last step first",
	check = function(_, a)
		for _, h in ipairs(ns.History()) do
			if h.id == a.id then
				if h.undone then return ("proposal %d was undone already"):format(a.id) end
				if not h.undoable then return ("proposal %d cannot be undone (nothing of it was kept)"):format(a.id) end
				return nil
			end
		end
		return ("no proposal %d in the history"):format(a.id)
	end,
	preview = function(_, a)                             -- and what it takes back, last step first
		local lines = { L.UNDO_STEP:format(a.id) }
		for _, h in ipairs(ns.History()) do
			if h.id == a.id then
				for j = #h.steps, 1, -1 do
					local s = h.steps[j]
					if s.snap ~= nil and s.preview and s.preview[1] then lines[#lines + 1] = L.UNDO_LINE:format(s.preview[1]) end
				end
			end
		end
		return lines
	end,
	apply = function(_, a)
		local ok, why = ns.UndoNow(a.id)
		if not ok then error(ns.Text(why), 0) end
		return true
	end })
