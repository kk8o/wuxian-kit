-- 公会聊天 (Guild chat): the kit's own app (ARCHITECTURE.md section 10). The player's agent takes part in guild chat
-- with the player's own character, at the pace the player set. The core does the rest: it hears the guild channel
-- (chat:guild, each line with its why) and the guild's moments (game:guild: guild.join, guild.leave,
-- guild.achievement, guild.level), gathers them into wakes (activity and quiet hours: the core's own options), runs
-- the lease, the status (said today included), the stop and the card. The agent speaks through chat.send (proposals
-- the player confirms or pre-approved); this file sends nothing. The session procedure is the skill
-- skills/guild-chat.md (the prompt guild-chat).
-- The id stays "guild" as WuxianGuild 0.3 declared it, so the player's options in WuxianKitDB.apps.guild carry over.
-- An addon that declares "guild" again after this file replaces this declaration (Apps.lua: the last one wins).
local Kit = WuxianKit

local L = Kit:Words {
	zhCN = {
		TITLE = "公会聊天",
		TOPICS = "想多聊的话题", TOPICS_HINT = "用逗号分开，如：副本, 专业, 拍卖行",
		AVOID = "不聊的话题", AVOID_HINT = "Agent 不会主动提起",
		NO_GUILD = "你还没有加入公会",
	},
	enUS = {
		TITLE = "Guild chat",
		TOPICS = "Topics to talk about", TOPICS_HINT = "Separated by commas, such as: dungeons, professions, auctions",
		AVOID = "Topics to avoid", AVOID_HINT = "The agent never brings them up",
		NO_GUILD = "Your character is not in a guild",
	},
}

Kit:App("guild", {
	title = L"TITLE", prompt = "guild-chat", addon = "WuxianKit", extension = "chat",
	hear = { "chat:guild", "game:guild" },
	pace = true,                                  -- the core's three paces and its options activity and quiet
	controls = { "mute", "unmute", "stop" },
	say = true,
	lease = 600, minutes = 120,
	options = {
		topics = { kind = "list", title = L"TOPICS", hint = L"TOPICS_HINT", default = {}, order = 1 },
		avoid = { kind = "list", title = L"AVOID", hint = L"AVOID_HINT", default = {}, order = 2 },
	},
	check = function()
		if not IsInGuild() then return L.NO_GUILD end
	end,
})
