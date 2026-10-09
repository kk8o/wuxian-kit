-- A third-party extension for the tests: a Setting over its own storage, a Keep, a timer and a status line, declared
-- the way any addon would.
local addonName = ...
local Kit = WuxianKit

local demo = Kit:Extension("demo", { title = "Demo", version = "1.2.3", addon = addonName,
	defaults = { volume = 3, notes = {} } })
demo:Scope("volume", "Demo volume")

demo:Setting("volume", { title = "Demo volume", doc = "the demo's volume (0-10)", value = "number", scope = "volume",
	check = function(self, k) end,
	get = function(self) return self.db.volume end,
	set = function(self, _, v) self.db.volume = v end,
	label = function() return "Demo volume" end })

demo:Keep("note", { title = "Keep a note", args = { text = "string" },
	run = function(self, a)
		table.insert(self.db.notes, a.text)
		return #self.db.notes
	end })

demo:Every(10, function(self) self.db.ticks = (self.db.ticks or 0) + 1 end)
demo:Status(function(self) return ("ticks: %d"):format(self.db.ticks or 0) end)
