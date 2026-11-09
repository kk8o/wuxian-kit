"""任务指引适配 (WuxianKit_Guides): the custom extension guides and its adapter rxp for RestedXP, read through the quest
guide's source route. RestedXP is faked as measured on 11-07 (v4.11.29): LibStub's AceEvent-3.0 and AceAddon-3.0
(kitmock.RXP), a guide whose steps hold their elements, each element knowing its step, the current step
RXPCData.currentStep."""
import unittest

from kitmock import RXP, RXP_INSTALLED, py
from test_route import RouteTest

# a guide with elements as RestedXP's parser makes them (tag, and the fields of functions.lua for each)
GUIDE = r"""
local maps = { [1434] = "荆棘谷" }
C_Map.GetMapInfo = function(id) return { mapID = id, name = maps[id] or "?" } end
__guide = { name = "22-24 Stranglethorn", displayname = "22-24 荆棘谷", steps = {} }
for i = 1, 50 do __guide.steps[i] = { index = i, elements = { { text = "第 " .. i .. " 步", textOnly = true } } } end
__guide.steps[41].elements = {
	{ tag = "goto", x = 37.512, y = 3.249, zone = 1434, textOnly = true },
	{ text = "与|cRXP_FRIENDLY_猎手阿吉萨|r交谈", textOnly = true },
	{ tag = "accept", text = "|cFFFFFF00接任务|r |T134400:0|t[猎杀迅猛龙]", questId = 194, title = "猎杀迅猛龙" },
	{ tag = "accept", text = "接任务 [丛林之王]", questId = 185, title = "" },
	{ tag = "target", targets = { "猎手阿吉萨", "1234" }, textOnly = true },
	{ tag = "goto", x = 50, y = 50, zone = 1434, textOnly = true },
}
__guide.steps[42].elements = {
	{ tag = "goto", x = 41.04, y = 9.75, zone = 1434, textOnly = true, completed = true },
	{ tag = "goto", x = 42, y = 11, zone = 1434, textOnly = true },
	{ tag = "complete", text = "迅猛龙 已杀死：3/10", questId = 194, obj = 1, title = "猎杀迅猛龙" },
	{ tag = "collect", text = "铜质短剑", id = 7166, qty = 3, questId = 194 },
	{ tag = "mob", mobs = { "迅猛龙", "迅猛龙" }, textOnly = true },
	{ tag = "isOnQuest", text = "如果你在做任务" },
}
__guide.steps[43].elements = {}
for i = 1, 8 do __guide.steps[43].elements[i] = { tag = "isOnQuest", text = "第 " .. i .. " 行" } end
__guide.steps[44].elements = {
	{ tag = "goto", x = 1, y = 2, zone = 1434, textOnly = true, completed = true },
	{ tag = "home", text = "将你的炉石设置为暴风城" },
	{ tag = "bindlocation" },
	{ tag = "target", targets = { "旅店老板奥里森" }, textOnly = true },
	{ tag = "turnin", text = "交任务", questId = -3001 },
	{ text = "清理营地" },
	{ tag = "hs", text = "使用炉石" },
	{ tag = "fly", text = "飞往西部荒野" },
}
__guide.steps[45].elements = {
	{ tag = "mob", mobs = { "|cffff0000野猪|r" }, text = "杀野猪" },
	{ tag = "target", targets = { "某人" }, textOnly = true },
}
__guide.steps[46].elements = { { tag = "target", targets = { "某人" }, textOnly = true } }
for _, step in ipairs(__guide.steps) do
	for _, e in ipairs(step.elements) do e.step = step end
end
table.insert(__quests, { title = "猎杀迅猛龙", questID = 194, level = 22,
	objectives = { { text = "迅猛龙 已杀死：4/10", type = "monster", finished = false, numFulfilled = 4, numRequired = 10 } } })
RXPCData = { currentStep = 41 }
function __activate(...)
	for _, i in ipairs({ ... }) do __send("RXP_STEP_ACTIVATED", __guide.steps[i], __guide) end
end
function __at(i)
	RXPCData.currentStep = i
	__activate(i)
end
"""


class Guides(RouteTest):
    def rxp(self, installed=True, guide=True):
        before = RXP + (RXP_INSTALLED if installed else "") + (GUIDE if guide else "")
        return self.app(fixtures=("WuxianKit_Guides",), before=before)

    def steps(self, a):
        return [d for d in a.data("route.step") if d["provider"] == "rxp"]

    def test_the_extension_provides_rxp_while_restedxp_is_loaded_and_on(self):
        a = self.rxp()
        exts = {e["id"]: e for e in a.call("kit.extensions")}
        self.assertEqual((exts["guides"]["state"], exts["guides"].get("builtin")), ("on", None))
        self.assertEqual(a.eval("WuxianKit.Route:Providers()")[1], {"id": "rxp", "title": "RestedXP", "addon": "RXPGuides",
                                                                    "active": False})   # no guide going yet
        a.s.ns[b"Switch"](b"guides", False)
        self.assertEqual([p["id"] for p in a.eval("WuxianKit.Route:Providers()")], ["game"])
        a.s.ns[b"Switch"](b"guides", True)
        self.assertEqual([p["id"] for p in a.eval("WuxianKit.Route:Providers()")], ["game", "rxp"])

    def test_no_restedxp_no_adapter_until_it_loads(self):
        a = self.rxp(installed=False)
        self.assertEqual([p["id"] for p in a.eval("WuxianKit.Route:Providers()")], ["game"])
        a.lua_(RXP_INSTALLED)
        a.fire("ADDON_LOADED", "RXPGuides")
        self.assertEqual([p["id"] for p in a.eval("WuxianKit.Route:Providers()")], ["game", "rxp"])

    def test_the_step_once_the_activations_settle_with_its_goals(self):
        a = self.rxp()
        a.lua_("__rxp.currentGuide = __guide")
        a.listen()
        a.lua_("__activate(41, 42, 43, 44)")          # several steps at once: the current one, once
        a.run(0.2)
        a.lua_("__activate(45)")
        a.run(1)
        [step] = self.steps(a)
        self.assertEqual(step, {"provider": "rxp", "guide": "22-24 荆棘谷", "index": 41, "key": "22-24 Stranglethorn|41",
                                "text": ["与猎手阿吉萨交谈", "接任务 [猎杀迅猛龙]", "接任务 [丛林之王]"],
                                "goals": [
                                    {"op": "go", "place": {"map": 1434, "zone": "荆棘谷", "x": 37.5, "y": 3.2},
                                     "done": False},
                                    {"op": "accept", "quest": {"id": 194, "name": "猎杀迅猛龙"}, "target": "猎手阿吉萨",
                                     "done": True, "text": "接任务 [猎杀迅猛龙]"},          # in the log: done
                                    {"op": "accept", "quest": {"id": 185}, "target": "猎手阿吉萨", "done": False,
                                     "text": "接任务 [丛林之王]"}]})
        a.lua_("__activate(41)")                      # the same step: nothing
        a.run(2)
        self.assertEqual(len(self.steps(a)), 1)

    def test_kill_and_collect_with_the_clients_progress(self):
        a = self.rxp()
        a.lua_("__rxp.currentGuide = __guide RXPCData.currentStep = 42 __bags[7166] = 2 __items[7166].known = true")
        a.listen()
        [step] = self.steps(a)
        self.assertEqual(step["goals"], [
            {"op": "go", "place": {"map": 1434, "zone": "荆棘谷", "x": 42, "y": 11}, "done": False},   # the first not reached
            {"op": "kill", "target": "迅猛龙", "quest": {"id": 194, "name": "猎杀迅猛龙"}, "objective": 1, "need": 10,
             "have": 4, "done": False, "text": "迅猛龙 已杀死：3/10"},
            {"op": "collect", "target": "Copper Dagger", "need": 3, "have": 2, "quest": {"id": 194, "name": "猎杀迅猛龙"},
             "done": False, "text": "铜质短剑"}])
        self.assertEqual(step["text"], ["迅猛龙 已杀死：3/10", "铜质短剑", "如果你在做任务"])
        a.lua_("__objective(194, 1, 5)")              # the quest log moves: progress
        a.run(0.5)
        self.assertEqual(a.data("route.progress"), [{"key": "22-24 Stranglethorn|42", "goal": 2, "have": 5, "need": 10,
                                                     "done": False}])

    def test_talk_use_other_and_the_names_of_the_step(self):
        a = self.rxp()
        a.lua_("__rxp.currentGuide = __guide RXPCData.currentStep = 44")
        a.listen()
        [step] = self.steps(a)
        self.assertEqual(step["goals"], [
            {"op": "go", "place": {"map": 1434, "zone": "荆棘谷", "x": 1, "y": 2}, "done": True},    # all reached
            {"op": "talk", "target": "旅店老板奥里森", "done": False, "text": "将你的炉石设置为暴风城"},
            {"op": "turnin", "quest": {"id": 3001, "name": "Healing Herbs"}, "target": "旅店老板奥里森", "done": False,
             "text": "交任务"},
            {"op": "other", "done": False, "text": "清理营地"},
            {"op": "use", "done": False, "text": "使用炉石"},
            {"op": "other", "done": False, "text": "飞往西部荒野"}])
        a.lua_("__at(45)")
        a.run(1)
        self.assertEqual(self.steps(a)[-1]["goals"], [{"op": "kill", "target": "野猪", "text": "杀野猪"}])
        a.lua_("__at(46)")
        a.run(1)
        self.assertEqual(self.steps(a)[-1]["goals"], [{"op": "talk", "target": "某人"}])
        self.assertEqual(a.data("route.done"), [{"key": "22-24 Stranglethorn|44", "why": "replaced"},
                                                {"key": "22-24 Stranglethorn|45", "why": "replaced"}])

    def test_arrive_at_the_current_steps_waypoint_and_an_element_done(self):
        a = self.rxp()
        a.lua_("__rxp.currentGuide = __guide RXPCData.currentStep = 42")
        a.listen()
        a.lua_("__send('RXP_OBJECTIVE_COMPLETE', __guide.steps[41].elements[1], __guide)")   # not the current step
        a.lua_("__guide.steps[42].elements[2].completed = true "
               "__send('RXP_OBJECTIVE_COMPLETE', __guide.steps[42].elements[2], __guide)")
        self.assertEqual(a.data("route.arrive"), [{"key": "22-24 Stranglethorn|42",
                                                   "place": {"map": 1434, "zone": "荆棘谷", "x": 42, "y": 11}}])
        a.run(0.5)
        self.assertEqual(a.data("route.progress"), [{"key": "22-24 Stranglethorn|42", "goal": 1, "done": True}])
        a.lua_("__guide.steps[42].elements[4].completed = true "
               "__send('RXP_OBJECTIVE_COMPLETE', __guide.steps[42].elements[4], __guide)")   # not a goto: progress
        a.run(0.5)
        self.assertEqual(a.data("route.progress")[-1], {"key": "22-24 Stranglethorn|42", "goal": 3, "have": 0, "need": 3,
                                                        "done": True})
        self.assertEqual(len(a.data("route.arrive")), 1)

    def test_the_turnin_done_then_the_next_step(self):
        a = self.rxp()
        a.lua_("__rxp.currentGuide = __guide __guide.steps[47].elements = { { tag = 'turnin', questId = 3001, "
               "text = '交任务', step = __guide.steps[47] } } RXPCData.currentStep = 47")
        a.listen()
        a.lua_("__turnin(3001) __at(48)")
        a.run(1)
        self.assertEqual(a.data("route.done"), [{"key": "22-24 Stranglethorn|47", "why": "turnin"}])
        self.assertEqual(self.steps(a)[-1]["index"], 48)

    def test_auto_switches_to_restedxp_once_a_guide_is_going(self):
        a = self.rxp()
        a.lua_("__track(3001)")
        a.listen()
        self.assertEqual([s["provider"] for s in a.data("route.step")], ["game"])
        self.assertIsNone(a.eval("__msgs.RXP_STEP_ACTIVATED"))         # not read: not hooked
        a.lua_("__rxp.currentGuide = __guide")
        a.run(5)
        self.assertEqual([s["provider"] for s in a.data("route.step")], ["game", "rxp"])
        self.assertEqual(len(a.eval("__msgs.RXP_STEP_ACTIVATED")), 1)

    def test_hooked_only_while_read(self):
        a = self.rxp()
        a.lua_("__unregisters() __rxp.currentGuide = __guide")
        self.assertIsNone(a.eval("__msgs.RXP_STEP_ACTIVATED"))         # nobody uses it: no hook
        a.listen()
        self.assertEqual(len(a.eval("__msgs.RXP_STEP_ACTIVATED")), 1)
        a.stop()
        self.assertIsNone(a.eval("__msgs.RXP_STEP_ACTIVATED"))
        a.listen()
        self.assertEqual(len(a.eval("__msgs.RXP_STEP_ACTIVATED")), 1)
        self.assertEqual(len(self.steps(a)), 2)                        # each start: the current step

    def test_a_guide_heard_without_restedxps_own(self):
        a = self.rxp()
        a.lua_("__track(3001)")
        a.s.ns[b"SetOption"](a.s.ns[b"extensions"][b"route"], b"provider", b"rxp")
        a.listen()
        self.assertEqual(a.data("route.step"), [])                     # rxp picked, no guide known yet
        a.lua_("__at(43)")
        a.run(1)
        [step] = self.steps(a)
        self.assertEqual((step["goals"] or [], step["text"]), ([], [f"第 {i} 行" for i in range(1, 7)]))
        a.lua_("__send('RXP_TARGET_LIST_UPDATE', {}, { '迅猛龙' }, { '旅店老板' })")
        a.run(1)
        self.assertEqual(py(a.lua.eval(b"WuxianKit.Route:Current()"))["goals"], [{"op": "kill", "target": "迅猛龙"}])


if __name__ == "__main__":
    unittest.main()
