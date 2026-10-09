-- The example of ARCHITECTURE.md (sections 3, 5 and 8), as written there: the tests load it, so the document stays true.
local Kit = WuxianKit
local L = Kit:Words {
	zhCN = { TITLE = "示例", VOLUME = "音量", SCOPE = "示例设置" },
	enUS = { TITLE = "Demo", VOLUME = "Volume", SCOPE = "Demo settings" },
}
local demo = Kit:Extension("demo", { title = L"TITLE", version = "1.0.0", defaults = { volume = 3 } })
demo:Scope("settings", L"SCOPE")

demo:Setting("volume", {
	title = L"VOLUME", doc = "the demo's volume, 0-10", value = "number", scope = "settings",
	validate = function(self, key, v) if v < 0 or v > 10 then return "0-10" end end,
	get = function(self, key) return self.db.volume end,
	set = function(self, key, v) self.db.volume = v end,
})

demo:Event("changed", { doc = "the volume changed", data = { volume = "number" } })
