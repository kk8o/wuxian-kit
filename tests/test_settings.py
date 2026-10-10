"""调校 and the game's Settings panel, under Lua 5.1 in the mock client: tune.setting.find reads the panel (its own
categories, not addons') and says how each option changes; tune.option sets the options that are no single CVar as the
panel does (the action bars shown, a modifier key, several CVars at once, the window's size, the character models) and
undo puts back all they changed; tune.cvar.set does what the panel's Apply does besides (a graphics quality's details,
the window, the graphics device, a restart)."""
import unittest

from kitmock import Session, click, lupa, py


@unittest.skipIf(lupa is None, "lupa (Lua 5.1 for Python) is not installed")
class Settings(unittest.TestCase):
    def start(self, **kw):
        s = Session(self, **kw)
        s.login()
        s.run(1)
        self.addCleanup(lambda: self.assertEqual(s.errors(), []))
        return s

    def call(self, s, cap, args="{}"):
        s.lua.execute(f"__answer = WuxianKit:Call({cap!r}, {args})".encode())
        return py(s.g("__answer"))

    def fails(self, s, cap, args):
        ok, err = s.lua.eval(f"pcall(function() WuxianKit:Call({cap!r}, {args}) end)".encode())
        self.assertFalse(ok, args)
        return err.decode()

    def run_it(self, s, seconds=0.5):
        click(s.g("WuxianKitProposal")[b"run"])
        s.run(seconds)

    def state(self, s, pid):
        return self.call(s, "kit.proposal", f"{{ id = {pid} }}")["state"]

    def undo(self, s, pid, seconds=0.5):
        self.call(s, "kit.undo", f"{{ id = {pid} }}")
        self.run_it(s, seconds)

    def cvar(self, s, name):
        return s.lua.eval(f"__cvars.{name}.value".encode()).decode()

    def test_find(self):
        """by the words the player reads (any of them, every word), the category or the name; each with its value and
        how to change it; the game's categories only, a mirrored one once, key bindings left out"""
        s = self.start()
        everything = self.call(s, "tune.setting.find", "{ limit = 100 }")
        self.assertEqual(everything["total"], 13)
        names = [e["name"] for e in everything["settings"]]
        self.assertEqual(names.count("autoLootDefault"), 1)                 # mirrored in Action Bars: once
        self.assertNotIn("nameplateShowAll", names)                        # an addon's category
        loot = self.call(s, "tune.setting.find", "{ text = 'auto loot' }")["settings"]
        self.assertEqual(loot, [{"label": "Auto Loot", "category": "Gameplay · Controls", "name": "autoLootDefault",
                                 "set": "tune.cvar.set", "value": "0", "type": "boolean"}])
        by_tip = self.call(s, "tune.setting.find", "{ text = 'health power' }")["settings"]
        self.assertEqual((by_tip[0]["name"], by_tip[0]["set"], by_tip[0]["value"]), ("PROXY_STATUS_TEXT", "tune.option.set", 4))
        self.assertEqual(by_tip[0]["choices"][1], {"value": 2, "label": "Percentage"})
        mouse = self.call(s, "tune.setting.find", "{ text = 'mouse' }")["settings"]
        self.assertEqual({e["name"]: e.get("inverted") for e in mouse}, {"lootUnderMouse": True, "PROXY_MOUSE_LOOK_SPEED": None})
        speed = next(e for e in mouse if e["name"] == "PROXY_MOUSE_LOOK_SPEED")
        self.assertEqual((speed["min"], speed["max"], speed["step"], speed["value"]), (90, 270, 10, 180))
        display = self.call(s, "tune.setting.find", "{ text = 'display mode' }")["settings"][0]
        self.assertEqual((display["name"], display["set"], display["panel"]), ("gxMaximize", "tune.cvar.set", "PROXY_DISPLAY_MODE"))
        quality = self.call(s, "tune.setting.find", "{ text = 'quality' }")["settings"]
        self.assertEqual([(e["name"], e["set"]) for e in quality],
                         [("graphicsQuality", "tune.cvar.set"), ("graphicsShadowQuality", "tune.cvar.set")])
        tagged = self.call(s, "tune.setting.find", "{ text = 'picture' }")              # by the panel's search words
        self.assertEqual([e["name"] for e in tagged["settings"]], ["graphicsQuality", "graphicsShadowQuality"])
        shadow = self.call(s, "tune.setting.find", "{ text = 'shadow' }")                # its own words first
        self.assertEqual([e["name"] for e in shadow["settings"]], ["graphicsShadowQuality", "graphicsQuality"])
        chat = self.call(s, "tune.setting.find", "{ text = 'disable chat' }")["settings"][0]
        self.assertEqual((chat["name"], chat.get("set")), ("PROXY_DISABLE_CHAT", None))
        self.assertIn("asks the player to confirm", chat["why"])
        size = self.call(s, "tune.setting.find", "{ text = 'window size' }")["settings"][0]
        self.assertEqual((size["value"], size["sizes"]), ("1295x971", ["1280x720", "1295x971", "1920x1080"]))
        none = self.call(s, "tune.setting.find", "{ text = 'nothing like it' }")
        self.assertEqual((none["total"], len(none["settings"])), (0, 0))
        self.assertEqual(self.call(s, "tune.setting.find", "{ text = 'gameplay', limit = 2 }")["total"], 9)

    def test_an_option_and_undo(self):
        """an option is set as the panel sets it (here several CVars and a modifier key), previewed with the panel's
        words, read back once the game shows it; undo puts back each CVar and the key as they were, not as the old
        value would set them"""
        s = self.start()
        s.lua.execute(b"__modifiers.SELFCAST = 'CTRL'")
        got = self.call(s, "tune.option.get", "{ name = 'PROXY_SELF_CAST' }")
        self.assertEqual((got["value"], got["label"], got["type"]), (4, "Self Cast", "number"))
        p = self.call(s, "tune.option.set", "{ name = 'PROXY_SELF_CAST', value = 1 }")
        self.assertEqual((p["steps"][0]["preview"], p["steps"][0]["scope"]),
                         (["Self Cast: Auto and Key Press → None"], "tune.settings.combat"))
        self.run_it(s)
        self.assertEqual((self.state(s, p["id"]), self.cvar(s, "autoSelfCast"), s.lua.eval(b"__modifiers.SELFCAST")),
                         ("done", "0", b"NONE"))
        self.undo(s, p["id"])
        self.assertEqual((self.cvar(s, "autoSelfCast"), s.lua.eval(b"__modifiers.SELFCAST")), ("1", b"CTRL"))   # not Alt
        status = self.call(s, "tune.option.set", "{ name = 'PROXY_STATUS_TEXT', value = '2' }")       # a number as text
        self.assertEqual(status["steps"][0]["preview"], ["Status Text: None → Percentage"])
        self.run_it(s)
        self.assertEqual((self.cvar(s, "statusTextDisplay"), self.cvar(s, "statusText")), ("PERCENT", "1"))
        self.undo(s, status["id"])
        self.assertEqual((self.cvar(s, "statusTextDisplay"), self.cvar(s, "statusText")), ("NONE", "0"))
        key = self.call(s, "tune.option.set", "{ name = 'FOCUSCAST', value = 'shift' }")
        self.assertEqual((key["steps"][0]["preview"], key["steps"][0]["scope"]), (["Focus Cast Key: None → SHIFT key"]
                         if s.lua.eval(b"FOCUS_CAST_KEY_TEXT") else ["FOCUSCAST: None → SHIFT key"], "tune.bindings"))
        saves = s.lua.eval(b"__bindingSaves")
        self.run_it(s)
        self.assertEqual((s.lua.eval(b"__modifiers.FOCUSCAST"), s.lua.eval(b"__bindingSaves")), (b"SHIFT", saves + 1))
        for args, why in (("{ name = 'PROXY_NOTHING', value = 1 }", "no option PROXY_NOTHING (tune.setting.find gives"),
                          ("{ name = 'PROXY_STATUS_TEXT', value = 7 }", "PROXY_STATUS_TEXT takes one of 1, 2, 3, 4"),
                          ("{ name = 'PROXY_MOUSE_LOOK_SPEED', value = 400 }", "PROXY_MOUSE_LOOK_SPEED takes 90 to 270"),
                          ("{ name = 'PROXY_SHOW_ACTIONBAR_2', value = 'yes' }", "takes true or false"),
                          ("{ name = 'PROXY_RESOLUTION', value = '1x1' }", "takes a size the monitor offers")):
            self.assertIn(why, self.fails(s, "tune.option.set", args))

    def test_the_bars_the_server_mirrors(self):
        """two bars shown in one proposal: the second does not send the mask the server has not mirrored yet; each step
        waits until the game shows it; undo hides them again"""
        s = self.start()
        s.lua.execute(b"__answer = WuxianKit:Propose({ { 'tune.option.set', { name = 'PROXY_SHOW_ACTIONBAR_2', value = true } }, "
                      b"{ 'tune.option.set', { name = 'PROXY_SHOW_ACTIONBAR_3', value = true } } })")
        p = py(s.g("__answer"))
        self.assertEqual(p["steps"][0]["preview"], ["Action Bar 2: Off → On"])
        self.run_it(s, 1)
        self.assertEqual(self.state(s, p["id"]), "done")
        self.assertEqual(py(s.g("__barToggles"))[:3], [True, True, False])
        self.undo(s, p["id"], 1)
        self.assertEqual(py(s.g("__barToggles"))[:3], [False, False, False])

    def test_the_window_and_the_models(self):
        """the window's size: one the monitor offers, the window updated, read back once it shows; the character models
        take effect after a reload (that option only)"""
        s = self.start()
        p = self.call(s, "tune.option.set", "{ name = 'PROXY_RESOLUTION', value = '1920 X 1080' }")
        self.assertEqual(p["steps"][0]["preview"], ["Window Size: 1295x971 → 1920x1080"])
        self.run_it(s)
        self.assertEqual((self.state(s, p["id"]), py(s.g("__window")), s.lua.eval(b"__windowUpdates")),
                         ("done", {"x": 1920, "y": 1080}, 1))
        self.undo(s, p["id"])
        self.assertEqual(py(s.g("__window")), {"x": 1295, "y": 971})
        m = self.call(s, "tune.option.set", "{ name = 'PROXY_CHARACTER_MODELS_TOGGLE', value = true }")
        self.assertEqual(m["steps"][0]["preview"], ["Character Models: Modern → Classic",
                                                    "|cff9c9ea6(takes effect after a reload)|r"])
        self.assertNotIn("reload", " ".join(self.call(s, "tune.option.set",
                                                      "{ name = 'PROXY_BLOCK_GUILD_INVITES', value = true }")["steps"][0]["preview"]))

    def test_what_the_panels_apply_does(self):
        """a graphics quality sets its details to that quality's values (as the panel's slider does) and undo puts back
        the details as they were, custom ones too; a display setting updates the window, triple buffering restarts the
        graphics device, the graphics API waits for a restart"""
        s = self.start()
        s.lua.execute(b"__cvars.graphicsShadowQuality.value = '5'")             # the player's own, above the quality's
        p = self.call(s, "tune.cvar.set", "{ name = 'graphicsQuality', value = 2 }")
        self.assertIn("Also sets shadows, view distance and the rest (4 settings) to this quality", p["steps"][0]["preview"][-1])
        self.run_it(s)
        self.assertEqual([self.cvar(s, c) for c in ("graphicsQuality", "graphicsShadowQuality", "graphicsViewDistance",
                                                     "graphicsParticleDensity", "graphicsSSAO")], ["2", "1", "1", "1", "1"])
        self.undo(s, p["id"])
        self.assertEqual([self.cvar(s, c) for c in ("graphicsQuality", "graphicsShadowQuality", "graphicsViewDistance",
                                                     "graphicsParticleDensity", "graphicsSSAO")], ["3", "5", "6", "4", "2"])
        raid = self.call(s, "tune.cvar.set", "{ name = 'raidGraphicsQuality', value = 1 }")
        self.run_it(s)
        self.assertEqual(self.cvar(s, "raidGraphicsShadowQuality"), "0")
        self.undo(s, raid["id"])
        w = self.call(s, "tune.cvar.set", "{ name = 'gxMaximize', value = true }")
        self.run_it(s)
        self.assertEqual((self.cvar(s, "gxMaximize"), s.lua.eval(b"__windowUpdates")), ("1", 1))
        self.undo(s, w["id"])
        self.assertEqual((self.cvar(s, "gxMaximize"), s.lua.eval(b"__windowUpdates")), ("0", 2))
        t = self.call(s, "tune.option.set", "{ name = 'PROXY_TRIPLE_BUFFERING', value = false }")
        self.run_it(s)
        self.assertEqual((self.cvar(s, "gxMaxFrameLatency"), s.lua.eval(b"__gxRestarts")), ("2", 1))
        api = self.call(s, "tune.cvar.set", "{ name = 'gxapi', value = 'D3D12' }")
        self.assertIn("Takes effect after the game restarts", api["steps"][0]["preview"][-1])

    def test_undo_lists_what_it_takes_back(self):
        """an undo's preview lists every line its steps changed (their notes left out); a step that leaves a setting
        without a value says none"""
        s = self.start()
        p = self.call(s, "tune.cvar.set", "{ name = 'graphicsQuality', value = 2 }")
        self.run_it(s)
        u = self.call(s, "kit.undo", f"{{ id = {p['id']} }}")
        self.assertEqual(u["steps"][0]["preview"], [f"Undo proposal #{p['id']}", "Undo: graphicsQuality: 3 → 2"])
        self.run_it(s)
        gone = self.call(s, "tune.binding.set", "{ key = 'M' }")
        self.run_it(s)
        self.assertEqual(self.call(s, "kit.proposal", f"{{ id = {gone['id']} }}")["steps"][0]["result"], {"none": True})


if __name__ == "__main__":
    unittest.main()
