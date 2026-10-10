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
--   UI/            the proposal window and the core's window (/wk)
--   Builtins.lua   the core's own extension, "kit"
-- Extensions/<Name>/<Name>.lua are the built-in extensions (on unless the player turned one off). Another addon becomes
-- an extension with the same calls; its .toc says ## Dependencies: WuxianKit, ## X-WuxianKit-Extension: <id> and
-- ## LoadOnDemand: 1, and the core loads it at login unless it was turned off.
local addonName, ns = ...

local Kit = { VERSION = C_AddOns and C_AddOns.GetAddOnMetadata and C_AddOns.GetAddOnMetadata(addonName, "Version") or "?" }
WuxianKit = Kit
ns.Kit = Kit

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
