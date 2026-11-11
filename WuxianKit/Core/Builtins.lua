-- The core's own extension, "kit", written as any extension is: what the agent (or another addon) can ask of the core.
--   kit.extensions        (See)  the extensions: built in, another addon's (loaded or not), on or off
--   kit.capabilities      (See)  every live capability with its kind, doc and args
--   kit.proposals         (See)  the proposals still open and the last finished ones; kit.proposal one of them
--   kit.history           (See)  what ran on this character (the last `limit`, 20, of the 50 kept), to undo
--   kit.extension.get/set        a Setting: whether an extension is on; turning one on or off is a proposal, undoable
--   kit.options           (See)  an extension's or an app's options as the player set them (read only: only the player
--                                changes them)
--   kit.me                (See)  the player's name, what AI apps call them (the core's option nickname), their aliases
--   kit.undo              (Do)   undo a proposal that ran
--   kit.local.set         (Keep) 无限工坊's list of the extensions added to this computer that have a local part, for
--                                the window to show them beside the game's (ns.LocalList)
--   bus                   (Source) what addons emit on the bus, for apps to hear (bus:<topic or prefix.*>)
--   me                    (Facet)  the player now (WuxianKit:Me()), for apps to see (see = { "me" }: state.me)
-- (The apps' capabilities, kit.app.* and kit.apps, are in Core/Apps/Api.lua.)
local _, ns = ...
local Kit, L = ns.Kit, ns.L

-- words of the core's own extension that the core's Locale does not have
local W = Kit:Words {
	zhCN = { NICKNAME = "称呼", NICKNAME_HINT = "AI 应用怎么叫你；留空就叫角色名", ME = "关于我", BUS = "插件事件",
		PLAYER = "角色状态" },
	enUS = { NICKNAME = "What to call me", NICKNAME_HINT = "How AI apps address you; empty: your character name",
		ME = "About me", BUS = "Addon events", PLAYER = "The player now" },
}

local kit = Kit:Extension("kit", { title = L"CORE", version = Kit.VERSION })
kit:Scope("extensions", L"SCOPE_EXTENSIONS")
kit:Scope("undo", L"SCOPE_UNDO")
kit:Option("nickname", { title = W"NICKNAME", kind = "text", default = "", hint = W"NICKNAME_HINT" })

kit:See("extensions", { title = L"LIST_EXTENSIONS",
	doc = "the extensions in the game: id, title, version, addon, author, builtin (in WuxianKit itself), official "
		.. "(无限工坊's own: the built-in ones and those it gives in an addon of their own), state (on, off, disabled in "
		.. "the game's addon list, missing: cannot load), how many capabilities",
	run = function() return ns.ExtensionList() end })

------------------------------------------------------------------------------------------------------------------------
-- the local extensions: what 无限工坊 says is added to this computer (an extension with a local part: a program,
-- documents, apps it declares). The game knows nothing of them by itself, so 无限工坊 gives the whole list, at every
-- kit.ready and when one is added, removed, turned on or off; kept in memory only (a reload: given again). The window
-- lists them with the game's extensions (UI/Window.lua); nothing else reads them

local LOCAL_MOST, LOCAL_IDS = 32, 16     -- extensions kept; ids kept in one's game and adds
local roster = {}

local function Short(v, most)
	if type(v) ~= "string" then return nil end
	v = ns.Cut((v:gsub("%c+", " ")), most)
	return v ~= "" and v or nil
end

local function Ids(v)
	local out = {}
	for _, id in ipairs(type(v) == "table" and v or {}) do
		if #out < LOCAL_IDS and type(id) == "string" and #id <= 40 and id:match("^[a-z][a-z0-9_]*$") then
			out[#out + 1] = id
		end
	end
	return out
end

-- the list as it is kept: { id, title, version, author, notes, where ("local", or "both": also in the game), on,
-- game (the ids of its extensions in the game), adds (the ids of the apps it adds to) }, texts as given (escape
-- them to draw them)
function ns.LocalList() return roster end

kit:Keep("local.set", { title = "kit.local.set", args = { extensions = "table" },
	doc = "无限工坊 calls this, not an agent: the extensions added to this computer that have a local part, the whole "
		.. "list each time (it takes the place of the one before; kept until the UI reloads). Each {id, title, version?, "
		.. "author?, notes?, where (local, or both: in the game too), on (enabled), game? (the ids of its extensions in "
		.. "the game), adds? (the ids of the apps it adds to)}; one that is not so is left out. The window lists them with "
		.. "the game's extensions. Answers {count}",
	run = function(_, a)
		local out, seen = {}, {}
		for _, v in ipairs(a.extensions) do
			local id = type(v) == "table" and v.id
			if #out < LOCAL_MOST and type(id) == "string" and #id <= 40 and id:match("^[a-z][a-z0-9_]*$")
				and not seen[id] then
				seen[id] = true
				out[#out + 1] = { id = id, title = Short(v.title, 60) or id, version = Short(v.version, 24),
					author = Short(v.author, 40), notes = Short(v.notes, 200),
					where = v.where == "both" and "both" or "local", on = v.on ~= false,
					game = Ids(v.game), adds = Ids(v.adds) }
			end
		end
		roster = out
		ns.Changed("local")
		return { count = #out }
	end })

kit:See("capabilities", { title = L"LIST_CAPABILITIES",
	doc = "every capability of the extensions that are on: id, kind (see, keep and point run at once; say and do make a "
		.. "proposal the player confirms), title, doc, args (name -> \"string\", \"number?\", \"a|b\"...), undoable",
	run = function() return Kit:Capabilities() end })

kit:See("proposals", { title = L"LIST_PROPOSALS",
	doc = "the proposals still open and the last finished ones: id, state (pending: waits for the player; waiting: "
		.. "pre-approved or confirmed, for its time or until it can run; queued: after combat; running: a step waits for "
		.. "the game to show it; done, failed, declined, expired, undone), title, source, steps with their preview and "
		.. "result, error. Pending and waiting ones expire; queued and running ones do not; a UI reload drops the open ones",
	run = function() return Kit:Proposals() end })

kit:See("proposal", { title = L"ONE_PROPOSAL", args = { id = "number" },
	doc = "one proposal by its id: its state, steps, results, error",
	run = function(_, a)
		return Kit:Proposal(a.id) or error(("no proposal %d (only the open and the recent ones are kept)"):format(a.id), 0)
	end })

kit:See("history", { title = L"HISTORY", args = { limit = "number?" },
	doc = "what ran on this character, newest last: the last `limit` proposals (20, up to 50: all that are kept): id, "
		.. "title, source, ran (Unix time), steps {cap, args (a long text shortened), preview}, undoable, undone",
	run = function(_, a)                                 -- as the proposals read: no snapshots, no layout strings in full
		local all, out = ns.History(), {}
		local limit = math.max(1, math.min(math.floor(tonumber(a and a.limit) or 20), 50))
		for i = math.max(1, #all - limit + 1), #all do
			local e, steps = all[i], {}
			for j, s in ipairs(e.steps or {}) do steps[j] = { cap = s.cap, args = ns.Brief(s.args), preview = s.preview } end
			out[#out + 1] = { id = e.id, title = e.title, source = e.source, ran = e.ran, steps = steps,
				undoable = e.undoable, undone = e.undone }
		end
		return out
	end })

kit:See("options", { title = L"LIST_OPTIONS", args = { extension = "string?", app = "string?" },
	doc = "the options of an extension (extension = its id) or of an app (app = its id; give one of the two), as the "
		.. "player set them on its page: name -> {title, kind (boolean, text, number, choice, list), value, default, "
		.. "choices [{value, label}] (choice), min, max, unit (number)}. Read only: only the player changes them; "
		.. "kit.option says when one changed",
	run = function(_, a)
		if a.extension and a.app then error("give extension or app, not both", 0) end
		if not a.extension and not a.app then error("give extension (an extension's id) or app (an app's id)", 0) end
		if a.app then
			local list = ns.AppOptionList and ns.AppOptionList(a.app)
			if not list then error(("no app %s (kit.apps lists them)"):format(a.app), 0) end
			return list
		end
		local ext = ns.extensions[a.extension]
		if not ext then error(("no extension %s (kit.extensions lists them)"):format(a.extension), 0) end
		return ns.OptionList(ext)
	end })

kit:See("me", { title = W"ME",
	doc = "the player as AI apps address them: name (the whole character name), nickname (the core's option 称呼, What "
		.. "to call me: call the player this; \"\" = by name), aliases (the names chat counts as naming the player: the "
		.. "whole name, its parts, the chat option 别人怎么叫我; none while the chat extension is off)",
	run = function()
		local me = Kit:Me()
		local chat = ns.extensions.chat
		local aliases = chat and chat.active and Kit.Chat and Kit.Chat.Names and Kit.Chat.Names() or {}
		return { name = me.name, nickname = me.nickname, aliases = aliases }
	end })

-- the player now, as a facet apps see (see = { "me" }): each wake carries state.me
kit:Facet("me", { title = W"PLAYER",
	doc = "the player now: name (whole), nickname (what to call them; \"\" = by name), level, class, classToken, zone, "
		.. "subzone, combat, dead (dead or a ghost), resting, xp (this level's experience, a whole percent; none at the "
		.. "top level)",
	fields = { name = "string", nickname = "string", level = "number", class = "string", classToken = "string",
		zone = "string?", subzone = "string?", combat = "boolean", dead = "boolean", resting = "boolean", xp = "number?" },
	read = function() return Kit:Me() end })

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
		.. "capabilities, events, sources [{name, title, doc, values}] (what apps can hear of it), facets [{name, title, "
		.. "doc, fields}] (what apps can see of it)}], the capabilities and events of those that are on, apps [{id, title, "
		.. "by, addon, topic, hear, see, prompt, start, extension, docs (an addon's app: the folder of its skills/), "
		.. "temp}]. For 无限工坊's app",
	run = function() return Kit:Manifest() end })
kit:See("revision", { title = L"REVISION", doc = "the manifest's revision: {revision}; it changes whenever the manifest does",
	run = function() return { revision = Kit:Manifest().revision } end })
kit:Event("proposal", { doc = "a proposal changed state: pending, waiting (for its time, or until it can run), queued "
	.. "(after combat), done, failed, declined, expired, undone",
	data = { id = "number", state = "string", title = "string?", source = "string", error = "string?" } })
kit:Event("extension", { doc = "an extension went on or off", data = { id = "string", on = "boolean" } })
kit:Event("dropped", { doc = "extension events that were not sent because they came faster than the link carries "
	.. "(the core's own always go, and an app's wakes wait and are sent again): how many, by topic",
	data = { count = "number", topics = "table" } })
kit:Event("changed", { doc = "the manifest changed: an extension on or off, a capability, the language",
	data = { revision = "string" } })
kit:Event("ready", { doc = "WuxianKit is up, after a login or a reload", data = { version = "string", extensions = "table",
	revision = "string" } })
-- one topic, two shapes: an extension's option is { extension, name, value } (ns.SetOption, Extension.lua), an app's is
-- { app, name, value } (ns.SetAppOption, Apps/Api.lua); never both keys
kit:Event("option", { doc = "the player changed an option: an extension's ({extension, name, value}) or an app's "
	.. "({app, name, value}): one of extension and app, never both (kit.options reads them all)",
	data = { extension = "string?", app = "string?", name = "string", value = "any" } })

-- the bus as a source apps hear (bus:<topic or prefix.*>): what addons tell each other with WuxianKit:Emit, not the
-- core's own (kit.*) nor apps' wakes (app.*)
kit:Source("bus", { title = W"BUS",
	doc = "bus:<topic> or bus:<prefix>.* (an event addons emit, such as bus:demo.ping or bus:demo.*; not kit.* or app.*): "
		.. "items {topic, data}",
	check = function(what)
		local base = what:gsub("%.%*$", "")
		if not base:match("^[a-z][a-z0-9_.]*$") or base:sub(-1) == "." then
			return "a bus source is a topic such as chat.message, or a prefix such as chat.*"
		end
		local head = base:match("^([^.]+)")
		if head == "kit" or head == "app" then return "an app cannot hear kit.* or app.* topics" end
	end,
	covers = function(a, b)                              -- demo.* hears demo.ping and demo.x.*
		return a:sub(-2) == ".*" and b:sub(1, #a - 1) == a:sub(1, -2)
	end,
	on = function(_, what, fn)
		return Kit:On(what, function(topic, data) fn({ topic = topic, data = data }) end)
	end,
	off = function(_, t) Kit:Off(t) end })

kit:Do("undo", { title = L"UNDO", args = { id = "number" }, scope = "undo", notes = false,
	doc = "proposes to undo a proposal that ran (its id from kit.history): what its steps changed is put back, last step "
		.. "first; only on the character it ran on; what cannot be undone (a sent message, a bag sort) stays",
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
					if s.snap ~= nil then
						for _, line in ipairs(s.preview or {}) do
							if type(line) == "string" and not line:find("^|cff9c9ea6") then
								lines[#lines + 1] = L.UNDO_LINE:format(line)
							end
						end
					end
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
