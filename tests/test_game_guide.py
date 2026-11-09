"""游戏动态 · Guide.lua (topic guide): RestedXP's guide.step / guide.arrive, ported from 无限陪玩's tests (a fake
LibStub, AceEvent and guide, shaped as measured on 11-07)."""
import unittest

from test_game import GameTest

# AceEvent-3.0's messages: RegisterMessage(obj, message, fn), fn(message, args...) when one is sent;
# UnregisterMessage(obj, message) when __unregister is on (a real AceEvent has it)
ACE = """
__msgs = {}
local AceEvent = {}
function AceEvent.RegisterMessage(obj, msg, fn)
	__msgs[msg] = __msgs[msg] or {}
	table.insert(__msgs[msg], fn)
end
function __unregisters()
	AceEvent.UnregisterMessage = function(obj, msg) __msgs[msg] = nil end
end
function __send(msg, ...)
	for _, fn in ipairs(__msgs[msg] or {}) do fn(msg, ...) end
end
function LibStub(name, silent)
	if name == "AceEvent-3.0" then return AceEvent end
	if not silent then error("no " .. name) end
end
"""

RXP_INSTALLED = """
__installed[#__installed + 1] = { name = "RXPGuides", title = "RestedXP Guides", meta = {}, loaded = true }
"""

# a guide: each step's elements in step.elements, each element knows its step; the current step is RXPCData.currentStep
GUIDE = """
local maps = { [1434] = "荆棘谷" }
C_Map.GetMapInfo = function(id) return { mapID = id, name = maps[id] or "?" } end
__guide = { name = "22-24 荆棘谷", steps = {} }
for i = 1, 50 do __guide.steps[i] = { index = i, elements = { { tag = nil, text = "第 " .. i .. " 步" } } } end
__guide.steps[41].elements = {
	{ tag = "goto", x = 37.512, y = 3.249, zone = 1434 },
	{ tag = "accept", text = "|cFFFFFF00接任务|r |T134400:0|t[猎杀迅猛龙]", questId = 194 },
	{ tag = "accept", text = "接任务 [丛林之王]", questId = 185 },
	{ tag = "target" },
	{ tag = "goto", x = 50, y = 50, zone = 1434 },
}
__guide.steps[42].elements = {
	{ tag = "goto", x = 41.04, y = 9.75, zone = 1434 },
	{ tag = "complete", text = "击杀 迅猛龙 ×10", questId = 194 },
}
__guide.steps[43].elements = {}
for i = 1, 8 do __guide.steps[43].elements[i] = { tag = "isOnQuest", text = "第 " .. i .. " 行" } end
for _, step in ipairs(__guide.steps) do
	for _, e in ipairs(step.elements) do e.step = step end
end
RXPCData = { currentStep = 41 }
function __activate(...)
	for _, i in ipairs({ ... }) do __send("RXP_STEP_ACTIVATED", __guide.steps[i], __guide) end
end
"""


class RXP(GameTest):
    def rxp_game(self, setup=ACE + RXP_INSTALLED):
        g = self.game()
        g.lua.execute(setup.encode())
        g.lua.execute(GUIDE.encode())
        return g

    def test_step_after_the_activations_settle(self):
        g = self.rxp_game()
        g.listen()
        g.lua.execute("__send('RXP_TARGET_LIST_UPDATE', { '猎手阿吉萨' }, { '猎手阿吉萨', '迅猛龙' }, {})".encode())
        g.lua.execute(b"__activate(41, 42, 43, 44)")      # several steps at once: one moment, the current one
        g.run(0.2)
        g.lua.execute(b"__activate(45)")
        g.run(0.5)
        [m] = g.moments("guide.step")
        self.assertEqual(m["data"], {"guide": "22-24 荆棘谷", "index": 41,
                                     "lines": ["接任务 [猎杀迅猛龙]", "接任务 [丛林之王]"],
                                     "goto": {"map": 1434, "zone": "荆棘谷", "x": 37.5, "y": 3.2},
                                     "targets": ["猎手阿吉萨", "迅猛龙"]})
        g.lua.execute(b"__activate(41)")                  # same step: nothing
        g.run(2)
        self.assertEqual(len(g.moments("guide.step")), 1)
        g.lua.execute(b"__send('RXP_TARGET_LIST_UPDATE', {}, {}, {}) RXPCData.currentStep = 43 __activate(43)")
        g.run(0.5)
        step = g.moments("guide.step")[-1]["data"]
        self.assertEqual((step["index"], step["lines"]), (43, [f"第 {i} 行" for i in range(1, 7)]))
        self.assertNotIn("goto", step)
        self.assertNotIn("targets", step)

    def test_targets_are_the_union_without_repeats_at_most_five(self):
        g = self.rxp_game()
        g.listen()
        g.lua.execute("__send('RXP_TARGET_LIST_UPDATE', { 'A', 'B' }, { 'B', 'C', '|cffff0000D|r' }, "
                      "{ 'A', 'E', 'F', 'G' })".encode())
        g.lua.execute(b"__activate(41)")
        g.run(0.5)
        self.assertEqual(g.moments("guide.step")[0]["data"]["targets"], ["A", "B", "C", "D", "E"])

    def test_arrive_at_the_current_steps_waypoint(self):
        g = self.rxp_game()
        g.listen()
        g.lua.execute(b"RXPCData.currentStep = 42 __activate(42)")
        g.run(0.5)
        g.lua.execute(b"__send('RXP_OBJECTIVE_COMPLETE', __guide.steps[41].elements[1], __guide)")   # not current
        g.lua.execute(b"__send('RXP_OBJECTIVE_COMPLETE', __guide.steps[42].elements[2], __guide)")   # not a goto
        g.lua.execute(b"__send('RXP_OBJECTIVE_COMPLETE', __guide.steps[42].elements[1], __guide)")
        self.assertEqual([m["data"] for m in g.moments("guide.arrive")], [{"guide": "22-24 荆棘谷", "index": 42}])

    def test_nothing_while_nobody_listens(self):
        g = self.rxp_game()
        g.lua.execute(b"__activate(41)")
        g.run(0.5)
        g.lua.execute(b"__send('RXP_OBJECTIVE_COMPLETE', __guide.steps[41].elements[1], __guide)")
        self.assertEqual(g.moments(), [])
        g.listen()
        g.lua.execute(b"__activate(41)")                  # listening now: the step is told
        g.run(0.5)
        self.assertEqual([m["data"]["index"] for m in g.moments("guide.step")], [41])

    def test_rxp_loaded_later(self):
        g = self.game()
        g.lua.execute((ACE + GUIDE).encode())
        g.listen()
        self.assertIsNone(g.lua.eval(b"__msgs.RXP_STEP_ACTIVATED"))
        g.lua.execute(RXP_INSTALLED.encode())
        g.fire("ADDON_LOADED", "RXPGuides")
        g.lua.execute(b"__activate(41)")
        g.run(0.5)
        self.assertEqual([m["data"]["index"] for m in g.moments("guide.step")], [41])
        g.fire("PLAYER_ENTERING_WORLD")                   # hooked once only
        self.assertEqual(len(g.lua.eval(b"__msgs.RXP_STEP_ACTIVATED")), 1)

    def test_hooked_only_while_heard(self):
        g = self.rxp_game()
        g.lua.execute(b"__unregisters()")
        self.assertIsNone(g.lua.eval(b"__msgs.RXP_STEP_ACTIVATED"))      # nobody hears: no hook
        g.listen(topics=["guide"])
        self.assertEqual(len(g.lua.eval(b"__msgs.RXP_STEP_ACTIVATED")), 1)
        g.stop()
        self.assertIsNone(g.lua.eval(b"__msgs.RXP_STEP_ACTIVATED"))
        g.lua.execute(b"__send('RXP_OBJECTIVE_COMPLETE', __guide.steps[41].elements[1], __guide)")
        g.listen(topics=["guide"])
        self.assertEqual(len(g.lua.eval(b"__msgs.RXP_STEP_ACTIVATED")), 1)
        g.lua.execute(b"__activate(41)")
        g.run(0.5)
        self.assertEqual(g.kinds(), ["guide.step"])

    def test_no_rxpguides_no_hook(self):
        g = self.rxp_game(setup=ACE)                      # AceEvent from some other addon, RXPGuides not there
        g.listen()
        g.fire("PLAYER_ENTERING_WORLD")
        self.assertIsNone(g.lua.eval(b"__msgs.RXP_STEP_ACTIVATED"))

    def test_no_libstub_no_hook(self):
        g = self.game()
        g.lua.execute(RXP_INSTALLED.encode())
        g.listen()
        g.fire("ADDON_LOADED", "RXPGuides")
        g.fire("PLAYER_ENTERING_WORLD")
        self.assertIsNone(g.lua.eval(b"LibStub"))
        self.assertEqual(g.moments(), [])


if __name__ == "__main__":
    unittest.main()
