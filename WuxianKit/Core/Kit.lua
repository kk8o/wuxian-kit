-- WuxianKit, the extension framework (扩展框架) of 无限工坊: the core and its extensions. An extension declares what it
-- can do; the core does the rest: checks the arguments, turns whatever changes the game into a proposal the player
-- confirms, keeps what ran so it can be undone, keeps the player's pre-approvals, the extension's storage, game events
-- and timers, its page in the window, and hands every capability and event to the AI agent. The core's files, in load
-- order:
--   Locale.lua     its words
--   Kit.lua        the public table WuxianKit: words, the bus, the load / login / logout hooks, small helpers
--   Schema.lua     argument specs
--   Extension.lua  the extension object and its life (defined, on, off), storage, game events, timers
--   Kinds.lua      the five kinds of capability and the two patterns built on them, Setting and Feed; Call / Propose
--   Proposals.lua  the proposal pipeline: preview, the player's Run, combat, undo, what goes without asking
--   Comm.lua       addon messages between players' clients (WuxianKit.Comm)
--   Bridge.lua     the AI agent, through 无限工坊's WoWBridge when it is there
--   UI/            the proposal window, the core's window (/wk) and OptionsPanel, the copy box (WuxianKit:Copy)
--   Builtins.lua   the core's own extension, "kit"
-- Extensions/<Name>/<Name>.lua are the built-in extensions (on unless the player turned one off). Another addon becomes
-- an extension with the same calls; its .toc says ## Dependencies: WuxianKit, ## X-WuxianKit-Extension: <id> and
-- ## LoadOnDemand: 1, and the core loads it at login unless it was turned off.
local addonName, ns = ...

local Kit = { VERSION = C_AddOns and C_AddOns.GetAddOnMetadata and C_AddOns.GetAddOnMetadata(addonName, "Version") or "?" }
WuxianKit = Kit
ns.Kit = Kit

-- "a.b.c" (or "a.b", "a"; anything after the numbers ignored) -> { a, b, c }, else nil
local function Semver(v)
	local a, b, c = tostring(v or ""):match("^%s*(%d+)%.?(%d*)%.?(%d*)")
	if not a then return nil end
	return { tonumber(a), tonumber(b) or 0, tonumber(c) or 0 }
end

-- WuxianKit:Requires(version): whether this WuxianKit is version ("0.5.0") or newer; false when it cannot tell. For
-- addons that use it when it is there and a newer call only when it has it
function Kit:Requires(version)
	local have, want = Semver(Kit.VERSION), Semver(version)
	if not (have and want) then return false end
	for i = 1, 3 do
		if have[i] ~= want[i] then return have[i] > want[i] end
	end
	return true
end

-- the language of the words: the player's choice (WuxianKitDB.lang: "zhCN" or "enUS"; none = the client's: Chinese on a
-- Chinese client, else English)
local LANGS = { zhCN = true, enUS = true }

function ns.Lang()
	if LANGS[ns.lang] then return ns.lang end
	local locale = GetLocale()
	return (locale == "zhCN" or locale == "zhTW") and "zhCN" or "enUS"
end

-- { zhCN = {...}, enUS = {...} } -> the words, each looked up when used: in the language in force, English where it has
-- none. L"KEY" is a text for a declaration (an extension's title, a capability's, an option's ...): looked up whenever
-- it is shown, so it follows a change of language too
function Kit:Words(set)
	local en, zh = set.enUS or {}, set.zhCN or {}
	return setmetatable({}, {
		__index = function(_, k)
			local v = ns.Lang() == "zhCN" and zh[k] or nil
			if v == nil then v = en[k] end
			return v
		end,
		__call = function(self, k) return function() return self[k] end end,
	})
end

ns.L = Kit:Words(ns.WORDS)
local L = ns.L

-- a declared text as shown: a string, or a function that gives one (L"KEY")
function ns.T(x)
	if type(x) ~= "function" then return x end
	local ok, s = pcall(x)
	return ok and s ~= nil and tostring(s) or "?"
end

-- tostring that never raises (a secret value, a __tostring that errors)
function ns.Text(v)
	if issecretvalue and issecretvalue(v) then return "<secret>" end
	local ok, s = pcall(tostring, v)
	return ok and type(s) == "string" and s or ("<" .. type(v) .. ">")
end

-- text from outside (an argument, the agent's words, another player's) as it is drawn: | doubled, so no color, texture,
-- link or line code in it takes effect, and line breaks as spaces. WuxianKit:Escape(text) is the same for extensions'
-- previews: everything a preview shows of its args goes through it
function ns.Escape(v)
	return (ns.Text(v):gsub("|", "||"):gsub("[\r\n]+", " "))
end

function Kit:Escape(v)
	return ns.Escape(v)
end

-- whether v is a number neither NaN nor infinite. On this client NaN compares equal to every number, so no comparison
-- tells it: its text does ("nan", "inf", "1.#INF", "-1.#IND")
function ns.Finite(v)
	return type(v) == "number" and not tostring(v):find("[nN#]")
end

-- s cut to at most n bytes on a character boundary (UTF-8), "…" where it was cut
function ns.Cut(s, n)
	if #s <= n then return s end
	return (s:sub(1, n):gsub("[\192-\255][\128-\191]*$", "")) .. "…"
end

------------------------------------------------------------------------------------------------------------------------
-- small helpers for extensions (0.6): reading the game without tripping over secret values, game text as plain text

-- WuxianKit:Value(v): v as an addon may use it, or nil when the client keeps it secret (or will not let it be read)
function Kit:Value(v)
	if v == nil then return nil end
	if issecretvalue and issecretvalue(v) then return nil end
	if canaccessvalue and not canaccessvalue(v) then return nil end
	return v
end

-- WuxianKit:Clean(text): game text as one plain line: no colours, textures, atlases; a link as its text ("[name]");
-- line breaks and runs of spaces as one space, trimmed. nil for nil, secret, not a string or nothing left
function Kit:Clean(text)
	text = Kit:Value(text)
	if type(text) ~= "string" then return nil end
	text = text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|cn[^:]*:", ""):gsub("|r", "")
		:gsub("|T.-|t", ""):gsub("|A.-|a", ""):gsub("|H.-|h(.-)|h", "%1"):gsub("|n", " ")
		:gsub("[\r\n]+", " "):gsub("%s%s+", " "):gsub("^%s+", ""):gsub("%s+$", "")
	return text ~= "" and text or nil
end

-- game links, both ways: WuxianKit:Links reads the links in game text as { kind, id, name }; an agent writes the same
-- as a token {kind:id:name} in a text it hands in (chat.send, guide.note, guide.tour, guide.highlight), and
-- WuxianKit:Linkify puts the client's own link in its place. Only links the client gives: never a |H code built here,
-- so nothing in a token can draw more than the client's link for that id. The kinds and the client's call for each:
--   item         C_Item.GetItemInfo(id): once the item's data is loaded (asked for when it is not: nil now)
--   spell        C_Spell.GetSpellLink(id): any spell (mounts and professions are spells too)
--   recipe       C_TradeSkillUI.GetRecipeLink(recipe spell id): learned or not; its link is |Henchant:
--   achievement  GetAchievementLink(id): it carries the player's own progress
--   currency     C_CurrencyInfo.GetCurrencyLink(id)
--   quest        GetQuestLink(quest id): only a quest in the player's log
-- A token the client gives no link for (an unknown kind, an id it does not know, a quest not in the log, an item not
-- loaded yet) shows as [name] ([id] without a name), and is no error.

-- a token: {kind:id:name}, the name optional ({item:2589})
local TOKEN = "{(%a+):(%d+):?([^}]*)}"

-- a link's type in game text -> its kind, where they differ; a token may say either
local LINK_KIND = { enchant = "recipe" }

local function ItemLink(id)
	local _, link = C_Item.GetItemInfo(id)
	if not link and C_Item.RequestLoadItemDataByID then C_Item.RequestLoadItemDataByID(id) end
	return link
end

-- kind -> fn(id): the client's link (globals looked up when called)
local LINKERS = {
	item = ItemLink,
	spell = function(id) return C_Spell.GetSpellLink(id) end,
	recipe = function(id) return C_TradeSkillUI.GetRecipeLink(id) end,
	achievement = function(id) return GetAchievementLink(id) end,
	currency = function(id) return C_CurrencyInfo.GetCurrencyLink(id) end,
	quest = function(id) return GetQuestLink(id) end,
}

local function Kind(kind)
	if type(kind) ~= "string" then return nil end
	kind = kind:lower()
	return LINK_KIND[kind] or kind
end

-- WuxianKit:Links(text): the links in game text, in order: { { kind (item, spell, recipe, achievement, currency, quest,
-- or the link's own type for others: trade, talent ...), id (the first number of the link's data, or nil), name (its
-- text without brackets) } }; a kind and id from here make a token for WuxianKit:Linkify
function Kit:Links(text)
	local out = {}
	text = Kit:Value(text)
	if type(text) ~= "string" then return out end
	for kind, data, name in text:gmatch("|H(%a+):([^|]*)|h%[(.-)%]|h") do
		out[#out + 1] = { kind = LINK_KIND[kind] or kind, id = tonumber(data:match("^(%-?%d+)")), name = name }
	end
	return out
end

-- WuxianKit:Link(kind, id): the client's link for it, or nil (a kind it has no link for, an id it does not know, an
-- item whose data is not loaded yet: asked for, so it is there a moment later)
function Kit:Link(kind, id)
	local get = LINKERS[Kind(kind) or ""]
	id = tonumber(id)
	if not get or not ns.Finite(id) or id <= 0 or id ~= math.floor(id) then return nil end
	local ok, link = pcall(get, id)
	link = ok and Kit:Value(link) or nil
	if type(link) ~= "string" or not link:find("|H", 1, true) then return nil end
	return link
end

local function Bracketed(id, name)
	return "[" .. (name ~= "" and name or id) .. "]"
end

-- WuxianKit:Linkify(text): text with each {kind:id:name} the client's link, or [name] where it gives none; and how many
-- links it put in. Nothing else in text changes: text from outside is escaped first (WuxianKit:Escape), then linkified,
-- so that only the client's links take effect
function Kit:Linkify(text)
	if type(text) ~= "string" or Kit:Value(text) == nil then return text, 0 end
	local n = 0
	text = text:gsub(TOKEN, function(kind, id, name)
		local link = Kit:Link(kind, id)
		if not link then return Bracketed(id, name) end
		n = n + 1
		return link
	end)
	return text, n
end

-- WuxianKit:Unlink(text): text with each {kind:id:name} as [name] ([id] without a name), as the player reads it in
-- plain text: for counting, a plain preview, the agent's copy
function Kit:Unlink(text)
	if type(text) ~= "string" or Kit:Value(text) == nil then return text end
	return (text:gsub(TOKEN, function(_, id, name) return Bracketed(id, name) end))
end

-- WuxianKit:Preload(text): asks the client for the items of text's tokens it has not loaded, so that their links are
-- there by the time they are shown or sent; how many it is still loading
function Kit:Preload(text)
	if type(text) ~= "string" or Kit:Value(text) == nil then return 0 end
	local n = 0
	for kind, id in text:gmatch(TOKEN) do
		if Kind(kind) == "item" and not Kit:Link("item", id) then n = n + 1 end
	end
	return n
end

local CLASSIFICATIONS = { normal = true, elite = true, rare = true, rareelite = true, worldboss = true, trivial = true,
	minus = true }

-- WuxianKit:Unit(unit): what an addon may read of a unit, or nil when there is none: { name, fullName (as other players
-- address a player: both parts of a two-part name), level (-1: ??), classification, creature, player, hostile,
-- class (classFile, players) }; a field the client keeps secret is left out
function Kit:Unit(unit)
	local V = function(v) return Kit:Value(v) end
	local ok, out = pcall(function()
		if not (UnitExists and V(UnitExists(unit))) then return nil end
		local o = {}
		local name = V((UnitName(unit)))
		if type(name) == "string" and name ~= "" then o.name = name end
		local full = GetUnitName and V(GetUnitName(unit, true))
		if type(full) == "string" and full ~= "" then o.fullName = full end
		local level = V(UnitLevel(unit))
		if type(level) == "number" then o.level = level end
		local cls = UnitClassification and V(UnitClassification(unit))
		if CLASSIFICATIONS[cls] then o.classification = cls end
		local creature = UnitCreatureType and V(UnitCreatureType(unit))
		if type(creature) == "string" and creature ~= "" then o.creature = creature end
		if V(UnitIsPlayer(unit)) then
			o.player = true
			local _, file = UnitClass(unit)
			o.class = V(file)
		end
		if UnitCanAttack and V(UnitCanAttack("player", unit)) then o.hostile = true end
		return o
	end)
	return ok and out or nil
end

-- WuxianKit:Pattern(fmt): a GlobalStrings format ("%s has joined the guild.") as a pattern that matches its messages:
-- anchored, %s captures text, %d a number, the rest literal; nil for nothing usable
function Kit:Pattern(fmt)
	if type(fmt) ~= "string" or fmt == "" then return nil end
	local parts, i = { "^" }, 1
	while i <= #fmt do
		local spec = fmt:match("^%%%d*%$?[sd]", i)
		if spec then
			parts[#parts + 1] = spec:sub(-1) == "d" and "(%d+)" or "(.+)"
			i = i + #spec
		elseif fmt:sub(i, i + 1) == "%%" then
			parts[#parts + 1] = "%%"
			i = i + 2
		else
			local c = fmt:sub(i, i)
			if c:find("[%^%$%(%)%%%.%[%]%*%+%-%?]") then c = "%" .. c end
			parts[#parts + 1] = c
			i = i + 1
		end
	end
	parts[#parts + 1] = "$"
	return table.concat(parts)
end

-- WuxianKit:NewId(): the next number of the core's one counter (WuxianKitDB.lastId), for chat messages, feed items and
-- app items alike, so that no two ever share an id, through reloads too. ns.BumpId(n): the counter goes on from at
-- least n (what an older counter reached)
local lastId = 0
function ns.BumpId(n)
	n = tonumber(n)
	if not ns.Finite(n) then return end
	if n > lastId then lastId = math.floor(n) end
	if ns.db and (tonumber(ns.db.lastId) or 0) < lastId then ns.db.lastId = lastId end
end

function Kit:NewId()
	local id = math.max(lastId, ns.db and tonumber(ns.db.lastId) or 0) + 1
	lastId = id
	if ns.db then ns.db.lastId = id end
	return id
end

-- WuxianKit:Me(): a small picture of the player for an AI app: { name (whole), nickname (the core's option 称呼: what
-- an AI calls the player; "" = by name), level, class, classToken, zone, subzone, combat }
function Kit:Me()
	local V = function(v) return Kit:Value(v) end
	local core = ns.extensions and ns.extensions.kit
	local nick = core and core.options and core.options.nickname and core:Get("nickname") or ""
	nick = type(nick) == "string" and nick:match("^%s*(.-)%s*$") or ""
	local className, classToken = UnitClass("player")
	local name = GetUnitName and V(GetUnitName("player", true)) or V((UnitName("player")))
	return { name = name, nickname = nick, level = V(UnitLevel("player")), class = V(className),
		classToken = V(classToken), zone = Kit:Clean(GetZoneText and GetZoneText()),
		subzone = Kit:Clean(GetSubZoneText and GetSubZoneText()),
		combat = ((InCombatLockdown and InCombatLockdown()) or
			(UnitAffectingCombat and V(UnitAffectingCombat("player")))) and true or false }
end

-- a chat line the player reads (not print: WoWBridge forwards print output to the daemon)
function ns.Say(text)
	if DEFAULT_CHAT_FRAME then DEFAULT_CHAT_FRAME:AddMessage(L.TAG .. text) end
end

local function Safe(fn, ...)
	local ok, err = pcall(fn, ...)
	if not ok then geterrorhandler()(err) end
	return ok
end
ns.Safe = Safe

------------------------------------------------------------------------------------------------------------------------
-- hooks: the core's parts hear of its moments (its saved variables are there, login, logout) and of what changed (an
-- extension, a capability, a scope) without knowing of each other

local moments = { load = {}, login = {}, logout = {} }
local changes = {}

function ns.When(moment, fn) table.insert(moments[moment], fn) end
function ns.OnChange(fn) changes[#changes + 1] = fn end
function ns.Changed(what, x)
	for _, fn in ipairs(changes) do Safe(fn, what, x) end
end

local frame = CreateFrame("Frame")
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_LOGIN")
frame:RegisterEvent("PLAYER_LOGOUT")
frame:SetScript("OnEvent", function(_, event, arg)
	local moment = event == "ADDON_LOADED" and "load" or event == "PLAYER_LOGIN" and "login" or "logout"
	if moment == "load" then
		if arg ~= addonName then return end
		WuxianKitDB = type(WuxianKitDB) == "table" and WuxianKitDB or {}
		ns.db = WuxianKitDB
		ns.lang = LANGS[ns.db.lang] and ns.db.lang or nil
	end
	for _, fn in ipairs(moments[moment]) do Safe(fn, ns.db) end
end)

-- the player's choice of language: "zhCN", "enUS" or "auto" (the client's); every part shows it at once
function ns.SetLanguage(choice)
	ns.lang = LANGS[choice] and choice or nil
	if ns.db then ns.db.lang = ns.lang end
	ns.Changed("language")
end

-- "auto", "zhCN" or "enUS": what the player chose
function ns.LanguageChoice()
	return ns.lang or "auto"
end

------------------------------------------------------------------------------------------------------------------------
-- the bus: WuxianKit:On(topic, fn(topic, data)) hears a topic ("chat.message"), a module's ("chat.*") or all ("*");
-- WuxianKit:Emit(topic, data) tells them, and the agent (Bridge.lua)

local listeners, token = {}, 0

function Kit:On(topic, fn)
	if type(topic) ~= "string" or type(fn) ~= "function" then error("WuxianKit:On(topic, fn)", 2) end
	token = token + 1
	listeners[token] = { topic = topic, fn = fn }
	return token
end

function Kit:Off(t)
	listeners[t] = nil
end

local function Hears(want, topic)
	if want == topic or want == "*" then return true end
	return want:sub(-2) == ".*" and topic:sub(1, #want - 1) == want:sub(1, -2)
end

-- an event's topic and a capability's id are at most NAME_MAX bytes: what WoWBridge carries, and the same without it
ns.NAME_MAX = 64

function Kit:Emit(topic, data)
	if type(topic) ~= "string" or topic == "" or #topic > ns.NAME_MAX then
		error(("WuxianKit:Emit(topic, data): topic is a string of at most %d bytes"):format(ns.NAME_MAX), 2)
	end
	for _, l in pairs(listeners) do
		if Hears(l.topic, topic) then Safe(l.fn, topic, data) end
	end
	if ns.Forward then pcall(ns.Forward, topic, data) end   -- the agent's copy (Bridge.lua) never breaks the bus
end

-- whether 无限工坊 is linked now: WuxianKit took a WoWBridge handle (ns.bound, Bridge.lua) and the link is online. A
-- WoWBridge with Online() says so itself; an older one is read with care (its insides may change)
function Kit:AgentOnline()
	if not ns.bound then return false end
	local ok, online = pcall(function()
		if type(WoWBridge) == "table" and type(WoWBridge.Online) == "function" then return WoWBridge.Online() end
		local wb = type(WoWBridgeNS) == "table" and WoWBridgeNS.WoWBridge
		local link = type(wb) == "table" and wb.Link
		return type(link) == "table" and type(link.State) == "function" and link.State() == "online"
	end)
	return ok and online == true
end
