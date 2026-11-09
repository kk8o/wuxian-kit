-- 游戏动态 (Game events, 0.6): what happens in the game, told as it happens. The built-in extension "game" (package K1
-- fills it in; this is the contract the other packages build on). The detectors live in the other files of this folder,
-- one per topic: Combat.lua (combat, aura), Growth.lua (growth), Quest.lua (quest), Travel.lua (travel), Guild.lua
-- (guild), Guide.lua (guide: RestedXP's steps; nothing without RXPGuides). A topic's detectors run only while someone
-- hears it (game.listen, an app that hears "game:<topic>", or a Lua subscriber); its busy game events (UNIT_COMBAT,
-- UNIT_AURA, UNIT_HEALTH ...) are registered only then.
--
-- WuxianKit.Game, for the core (apps) and other addons:
--   Game:On(what, fn(item)) -> token   what: a kind ("quest.turnin"), a topic ("quest") or "*"; item = { kind, topic,
--                                     time, data }, no id (whoever passes it on gives it one: WuxianKit:NewId())
--   Game:Off(token)
--   Game.TOPICS                        the topics, in order
--   Game.KINDS                         kind -> topic
-- The capability game.listen { topics = table?, me = boolean?, minutes } (a Feed, keep 50) hears the topics (all when
-- none are given) and emits game.moment { id, time, kind, topic, me? (WuxianKit:Me()), data }.
local Kit = WuxianKit

local TOPICS = { "combat", "aura", "growth", "quest", "travel", "guild", "guide" }

-- kind -> topic; the data of each is in ARCHITECTURE.md (section 11)
local KINDS = {
	["combat.start"] = "combat", ["combat.end"] = "combat", danger = "combat", ["cast.at_me"] = "combat", kill = "combat",
	death = "combat", alive = "combat", ["spell.big"] = "combat", target = "combat",
	["aura.gift"] = "aura", ["aura.bad"] = "aura",
	xp = "growth", level = "growth", talent = "growth", ["spell.new"] = "growth",
	["quest.accept"] = "quest", ["quest.progress"] = "quest", ["quest.ready"] = "quest", ["quest.turnin"] = "quest",
	zone = "travel", taxi = "travel", rest = "travel",
	["guild.join"] = "guild", ["guild.leave"] = "guild", ["guild.achievement"] = "guild", ["guild.level"] = "guild",
	["guide.step"] = "guide", ["guide.arrive"] = "guide",
}

local Game = Kit.Game or {}
Kit.Game = Game
Game.TOPICS, Game.KINDS = TOPICS, KINDS

-- (contract stubs: K1 replaces them)
local subs, token = {}, 0
Game.subs = subs
function Game:On(what, fn)
	if type(what) ~= "string" or type(fn) ~= "function" then error("WuxianKit.Game:On(what, fn)", 2) end
	token = token + 1
	subs[token] = { what = what, fn = fn }
	return token
end
function Game:Off(t) subs[t] = nil end
