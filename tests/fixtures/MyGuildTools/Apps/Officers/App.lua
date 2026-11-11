local IsMine = select(2, ...).IsMine
WuxianKit:App("officers", {
	title = "官员频道", prompt = "officer-chat", docs = "Apps/Officers",
	addon = "MyGuildTools", extension = "myguild",
	hear = { "chat:officer", "game:guild" }, see = { "me" },
	pace = true, urgent = { "mention", "followup", "question", "burst" },
	controls = { "stop" }, lease = 600, minutes = 120,
	options = { topics = { kind = "list", title = "想多聊的话题" }, avoid = { kind = "list", title = "不聊的话题" } },
	check = function() if not IsInGuild() then return "你还没有加入公会" end end,
	enrich = function(item) if item.kind == "guild.join" then item.recruited = IsMine(item.data.name) or nil end end,
})
