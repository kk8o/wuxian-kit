"""调校 (Tune) under Lua 5.1 in the mock client: key bindings, macros (made a moment later: the step waits for them, and
one that never shows fails and is put back), Edit Mode layouts, talent loadouts, gear, sorting the bags, addons on and
off, profiles (kept, captured, applied as one proposal, shared as text), and gate 2 in the mock: one proposal of a
setting, a layout and a key, and one undo that brings them all back."""
import unittest

from kitmock import Session, click, lupa, py, texts


@unittest.skipIf(lupa is None, "lupa (Lua 5.1 for Python) is not installed")
class Tune(unittest.TestCase):
    def start(self, **kw):
        s = Session(self, **kw)
        s.lua.execute(b"__events = {} WuxianKit:On('*', function(topic, data) "
                      b"__events[#__events + 1] = { topic = topic, data = data } end)")
        s.login()
        s.run(1)
        self.addCleanup(lambda: self.assertEqual(s.errors(), []))
        return s

    def call(self, s, cap, args="{}", opts="nil"):
        s.lua.execute(f"__answer = WuxianKit:Call({cap!r}, {args}, {opts})".encode())
        return py(s.g("__answer"))

    def fails(self, s, code):
        ok, err = s.lua.eval(f"pcall(function() {code} end)".encode())
        self.assertFalse(ok, code)
        return err.decode()

    def proposals(self, s, state=None):
        return [e["data"] for e in py(s.g("__events")) or []
                if e["topic"] == "kit.proposal" and (state is None or e["data"]["state"] == state)]

    def run_it(self, s):
        click(s.g("WuxianKitProposal")[b"run"])

    def undo(self, s, pid):
        self.call(s, "kit.undo", f"{{ id = {pid} }}")
        self.run_it(s)

    def done(self, s, pid):
        return any(p["id"] == pid for p in self.proposals(s, "done"))

    def test_key_bindings(self):
        s = self.start()
        got = self.call(s, "tune.binding.get", "{ key = '1' }")
        self.assertEqual((got["value"], got["title"], got["category"]), ("ACTIONBUTTON1", "Action Button 1", "Action Bar"))
        p = self.call(s, "tune.binding.set", "{ key = 'shift-ctrl-f12', value = 'toggleworldmap' }")
        self.assertEqual((p["steps"][0]["preview"], p["steps"][0]["scope"]),
                         (["CTRL-SHIFT-F12: (none) → Open World Map (TOGGLEWORLDMAP)"], "tune.bindings"))
        self.run_it(s)
        self.assertEqual((py(s.g("__bindings"))["CTRL-SHIFT-F12"], s.g("__bindingSaves")), ("TOGGLEWORLDMAP", 1))
        self.undo(s, p["id"])
        self.assertNotIn("CTRL-SHIFT-F12", py(s.g("__bindings")))
        unbind = self.call(s, "tune.binding.set", "{ key = 'M' }")            # no command: the key is unbound
        self.assertEqual(unbind["steps"][0]["preview"], ["M: Open World Map (TOGGLEWORLDMAP) → (none)"])
        self.run_it(s)
        self.assertNotIn("M", py(s.g("__bindings")))
        for args, why in (("{ key = 'HYPER-F', value = 'MOVEFORWARD' }", "HYPER is not a modifier"),
                          ("{ key = 'F', value = 'FLY' }", "no binding command FLY"),
                          ("{ key = 'F', value = 'MACRO Nope' }", "no macro Nope")):
            self.assertIn(why, self.fails(s, f"WuxianKit:Call('tune.binding.set', {args})"))
        spell = self.call(s, "tune.binding.set", "{ key = 'F', value = 'spell Flash Heal' }")
        self.assertEqual(spell["steps"][0]["preview"], ["F: (none) → SPELL Flash Heal"])
        found = self.call(s, "tune.binding.find", "{ text = 'map' }")
        self.assertEqual([(b["command"], b["keys"] or []) for b in found], [("TOGGLEWORLDMAP", [])])
        self.assertEqual([b["command"] for b in self.call(s, "tune.binding.find")], ["MOVEFORWARD", "ACTIONBUTTON1", "ACTIONBUTTON2"])

    def test_macros_wait_for_the_client(self):
        s = self.start()
        p = self.call(s, "tune.macro.set", "{ name = 'Heal', value = '#showtooltip\\n/cast Flash Heal' }")
        self.assertEqual((p["steps"][0]["preview"], p["steps"][0]["scope"]),
                         (["Heal: (none) → #showtooltip ... (2 lines)", "|cff9c9ea6#showtooltip|r", "|cff9c9ea6/cast Flash Heal|r"],
                          "tune.macros"))
        self.run_it(s)
        self.assertFalse(self.done(s, p["id"]))                             # a placeholder first: the step waits
        s.run(0.3)
        self.assertTrue(self.done(s, p["id"]))
        self.assertEqual([(m["name"], m["body"]) for m in py(s.g("__macros"))["account"]],
                         [("Heal", "#showtooltip\n/cast Flash Heal"), ("reload", "/reload\n")])
        self.undo(s, p["id"])
        self.assertEqual([m["name"] for m in py(s.g("__macros"))["account"]], ["reload"])
        edit = self.call(s, "tune.macro.set", "{ name = 'reload', value = '/reload ui' }")
        self.run_it(s)
        s.run(0.3)
        self.assertEqual(py(s.g("__macros"))["account"][0]["body"], "/reload ui")
        self.undo(s, edit["id"])
        s.run(0.3)
        self.assertEqual(py(s.g("__macros"))["account"][0]["body"], "/reload\n")
        s.lua.execute(b"__macros.account[1].icon = 999")
        gone = self.call(s, "tune.macro.set", "{ name = 'reload' }")        # no text: deleted
        self.run_it(s)
        self.assertEqual(py(s.g("__macros"))["account"], {})
        self.undo(s, gone["id"])                                            # back, with its icon
        s.run(0.3)
        self.assertEqual([(m["name"], m["icon"]) for m in py(s.g("__macros"))["account"]], [("reload", 999)])
        long = self.call(s, "tune.macro.set", "{ name = 'Long', value = '/s ' .. string.rep('x', 227) }")
        self.assertEqual(long["steps"][0]["args"]["value"], "/s " + "x" * 57 + "...(230 bytes)")   # a long text, shortened
        click(s.g("WuxianKitProposal")[b"decline"])
        for args, why in (("{ name = 'x', value = string.rep('a', 300) }", "300 bytes, more than 255"),
                          ("{ name = 'x', value = '  ' }", "the text is empty"),
                          ("{ name = string.rep('n', 20), value = '/say hi' }", "a macro's name is 1 to 16 bytes")):
            self.assertIn(why, self.fails(s, f"WuxianKit:Call('tune.macro.set', {args})"))
        s.lua.execute(b"CreateMacro = function() end")                      # the client never shows it
        ghost = self.call(s, "tune.macro.set", "{ name = 'Ghost', value = '/say boo' }")
        self.run_it(s)
        s.run(6)
        failed = self.proposals(s, "failed")[-1]
        self.assertEqual((failed["id"], failed["error"]), (ghost["id"], "step 1 (tune.macro.set): the game shows Ghost at (none)"))
        self.assertEqual([m["name"] for m in self.call(s, "tune.macro.list")], ["reload"])

    def test_layouts(self):
        s = self.start()
        self.assertEqual(self.call(s, "tune.layout.list"), [{"name": "Modern", "preset": True}, {"name": "Classic", "preset": True},
                                                            {"name": "Mine", "inUse": True}])
        p = self.call(s, "tune.layout.set", "{ value = 'Modern' }")
        self.assertEqual(p["steps"][0]["preview"], ["Active layout: Mine → Modern"])
        self.run_it(s)
        self.assertFalse(self.done(s, p["id"]))                             # the client shows it a moment later
        s.run(0.3)
        self.assertTrue(self.done(s, p["id"]))
        self.assertEqual(self.call(s, "tune.layout.get")["value"], "Modern")
        self.undo(s, p["id"])
        s.run(0.3)
        self.assertEqual(self.call(s, "tune.layout.get")["value"], "Mine")
        s.lua.execute(b"__text = WuxianKit:Call('tune.layout.export', { name = 'Mine' }).text")
        self.assertTrue(s.g("__text").startswith(b"EM1:"))
        imp = self.call(s, "tune.layout.import", "{ name = 'Healer', text = __text }")
        self.assertEqual(imp["steps"][0]["preview"], ['Import and use layout "Healer" (account-wide)'])
        self.run_it(s)
        s.run(0.3)
        self.assertTrue(self.done(s, imp["id"]))
        self.assertEqual([(x["name"], x.get("inUse")) for x in self.call(s, "tune.layout.list")][2:],
                         [("Mine", None), ("Healer", True)])
        solo = self.call(s, "tune.layout.import", "{ name = 'Solo', text = __text, character = true }")
        self.run_it(s)
        s.run(0.3)
        self.undo(s, solo["id"])
        self.undo(s, imp["id"])
        s.run(0.3)
        self.assertEqual(self.call(s, "tune.layout.list")[2:], [{"name": "Mine", "inUse": True}])
        for args, why in (("{ name = 'Mine', text = __text }", "there is a layout Mine already"),
                          ("{ name = 'New', text = 'garbage' }", "not a layout's share string")):
            self.assertIn(why, self.fails(s, f"WuxianKit:Call('tune.layout.import', {args})"))
        self.assertIn("no layout Nope", self.fails(s, "WuxianKit:Call('tune.layout.set', { value = 'Nope' })"))

    def test_talent_loadouts(self):
        s = self.start()
        self.assertEqual(self.call(s, "tune.talent.list"), [{"name": "Leveling", "id": 101, "inUse": True},
                                                            {"name": "Dungeons", "id": 102}])
        p = self.call(s, "tune.talent.set", "{ value = 'Dungeons' }")
        self.assertEqual(p["steps"][0]["preview"], ["Active loadout: Leveling → Dungeons"])
        self.run_it(s)
        s.run(0.3)
        self.assertFalse(self.done(s, p["id"]))                             # still loading
        s.run(0.5)
        self.assertTrue(self.done(s, p["id"]))
        self.undo(s, p["id"])
        s.run(1)
        self.assertEqual(s.lua.eval(b"__talents.selected"), 101)
        self.assertEqual(self.call(s, "tune.talent.export")["text"], "TALENTS101")
        self.assertIn("no loadout Raid", self.fails(s, "WuxianKit:Call('tune.talent.set', { value = 'Raid' })"))

    def test_a_macros_icon_and_its_place_on_the_bars(self):
        """a change of text leaves the icon the macro keeps (a question-mark one keeps following its spell), and undo
        puts back the text; deleting a macro on the action bars says undo cannot put it back there"""
        s = self.start()
        s.lua.execute(b"CreateMacro('Heal', 134400, '/cast Heal', false)")
        s.run(0.2)
        i = s.lua.eval(b"GetMacroIndexByName('Heal')")
        kept = lambda: (s.lua.eval(f"C_Macro.GetSelectedMacroIcon({i})".encode()), s.lua.eval(f"GetMacroBody({i})".encode()))
        p = self.call(s, "tune.macro.set", "{ name = 'Heal', value = '/cast Flash Heal' }")
        self.run_it(s)
        s.run(0.5)
        self.assertEqual(kept(), (134400, b"/cast Flash Heal"))
        self.undo(s, p["id"])
        s.run(0.5)
        self.assertEqual(kept(), (134400, b"/cast Heal"))
        s.lua.execute(f"__actions[1] = {{ 'macro', {i} }}".encode())
        d = self.call(s, "tune.macro.set", "{ name = 'Heal' }")
        self.assertIn("|cff9c9ea6This macro is on the action bars: deleting it clears those buttons, and undo cannot put "
                      "them back|r", d["steps"][0]["preview"])

    def test_loadouts_by_id_and_a_layout_gone(self):
        """two loadouts of one name are refused; undo loads the one before by its id, and fails when it is gone; a layout
        gone fails its undo too"""
        s = self.start()
        s.lua.execute(b"__talents.loadouts[103] = 'Raid' __talents.loadouts[104] = 'Raid'")
        self.assertIn("2 loadouts are named Raid", self.fails(s, "WuxianKit:Call('tune.talent.set', { value = 'Raid' })"))
        p = self.call(s, "tune.talent.set", "{ value = 'Dungeons' }")
        self.run_it(s)
        s.run(1)
        self.assertTrue(self.done(s, p["id"]))
        s.lua.execute(b"__talents.loadouts[101] = nil")
        self.undo(s, p["id"])
        s.run(1)
        self.assertIn("the loadout Leveling is gone", self.proposals(s, "failed")[-1]["error"])
        q = self.call(s, "tune.layout.set", "{ value = 'Modern' }")
        self.run_it(s)
        s.run(0.5)
        self.assertTrue(self.done(s, q["id"]))
        s.lua.execute(b"__editMode.layouts = {}")
        self.undo(s, q["id"])
        s.run(0.5)
        self.assertIn("the layout Mine is gone", self.proposals(s, "failed")[-1]["error"])

    def test_an_imported_profile_always_asks(self):
        """a profile someone shared waits for the click even when every step is pre-approved; one the player keeps does not"""
        s = self.start()
        s.g("SlashCmdList")[b"WUXIANKIT"](b"")
        w = s.g("WuxianKitWindow")
        items = w[b"items"]
        click(next(items[n] for n in range(1, len(items) + 1) if items[n][b"id"] == b"tune"))
        c = w[b"checks"]
        click(next(c[n] for n in range(1, len(c) + 1) if c[n][b"shown"] and c[n][b"label"][b"text"] == b"Game settings"))
        self.call(s, "tune.profile.save", "{ name = 'mine', steps = { { cap = 'tune.cvar.set', "
                                          "args = { name = 'nameplateShowAll', value = 1 } } } }")
        s.lua.execute(b"__text = WuxianKit:Call('tune.profile.export', { name = 'mine' }).text")
        self.call(s, "tune.profile.import", "{ text = __text, name = 'shared' }")
        shared = self.call(s, "tune.profile.apply", "{ name = 'shared' }")
        self.assertEqual((shared["state"], shared["source"], shared.get("auto")), ("pending", "import:shared", None))
        self.assertIn("From shared profile shared", "\n".join(texts(s.g("WuxianKitProposal"))))
        mine = self.call(s, "tune.profile.apply", "{ name = 'mine' }", "{ source = 'agent' }")
        self.assertEqual((mine["state"], mine["auto"]), ("done", True))

    def test_gear(self):
        s = self.start()
        self.assertEqual(self.call(s, "tune.gear.list"), [{"name": "Healing", "items": 2, "missing": 0}])
        worn = py(s.g("__worn"))
        p = self.call(s, "tune.gear.use", "{ name = 'Healing' }")
        self.assertEqual(p["steps"][0]["preview"], ['Equip "Healing"'])
        self.run_it(s)
        self.assertFalse(self.done(s, p["id"]))
        s.run(0.5)
        self.assertTrue(self.done(s, p["id"]))
        self.assertTrue(self.call(s, "tune.gear.list")[0]["worn"])
        self.undo(s, p["id"])
        s.run(0.5)
        self.assertEqual(py(s.g("__worn")), worn)
        save = self.call(s, "tune.gear.save", "{ name = 'Now' }")
        self.run_it(s)
        s.run(0.5)
        self.assertFalse(self.done(s, save["id"]))                          # made a moment later, counted once it stays
        s.run(1)
        self.assertTrue(self.done(s, save["id"]))
        self.assertEqual([g["name"] for g in self.call(s, "tune.gear.list")], ["Healing", "Now"])
        self.undo(s, save["id"])
        self.assertEqual([g["name"] for g in self.call(s, "tune.gear.list")], ["Healing"])
        self.assertIn("no equipment set PvP", self.fails(s, "WuxianKit:Call('tune.gear.use', { name = 'PvP' })"))
        s.lua.execute(b"__gearTakenBack = true")                          # the client adds it and takes it back
        self.call(s, "tune.gear.save", "{ name = 'Gone' }")
        self.run_it(s)
        s.run(6)
        self.assertEqual(self.proposals(s, "failed")[-1]["error"], "step 1 (tune.gear.save): the game did not keep the set")
        self.assertEqual([g["name"] for g in self.call(s, "tune.gear.list")], ["Healing"])

    def test_bags_and_addons(self):
        s = self.start(fixtures=("WxDemo",))
        p = self.call(s, "tune.bags.sort")
        self.assertEqual(p["steps"][0]["preview"], ["Sort bags", "|cff9c9ea6(cannot be undone)|r"])
        self.run_it(s)
        self.assertEqual(s.g("__sorts"), 1)
        self.assertNotIn("undoable", self.proposals(s, "done")[-1])
        a = self.call(s, "tune.addon.set", "{ name = 'WxDemo', value = false }")
        self.assertEqual(a["steps"][0]["preview"], ["WxDemo: Enabled → Disabled", "|cff9c9ea6(takes effect after a reload)|r"])
        self.run_it(s)
        self.assertIn("Some changes take effect after a reload: /reload", s.chat())
        self.assertFalse(self.call(s, "tune.addon.get", "{ name = 'WxDemo' }")["value"])
        self.undo(s, a["id"])
        self.assertTrue(self.call(s, "tune.addon.get", "{ name = 'WxDemo' }")["value"])
        self.assertIn("WuxianKit keeps itself on",
                      self.fails(s, "WuxianKit:Call('tune.addon.set', { name = 'WuxianKit', value = false })"))
        self.assertIn("no addon Nope", self.fails(s, "WuxianKit:Call('tune.addon.get', { name = 'Nope' })"))
        self.assertEqual([(x["name"], x["on"]) for x in self.call(s, "tune.addon.list")], [("WuxianKit", True), ("WxDemo", True)])

    def test_profiles(self):
        s = self.start()
        kept = self.call(s, "tune.profile.capture",
                         "{ name = 'base', cvars = { 'nameplateShowAll' }, keys = { '1', 'CTRL-F' }, layout = true }")
        self.assertEqual(kept, {"name": "base", "steps": 4})
        self.assertEqual(self.call(s, "tune.profile.get", "{ name = 'base' }")["steps"], [
            {"cap": "tune.cvar.set", "args": {"name": "nameplateShowAll", "value": "0"}},
            {"cap": "tune.binding.set", "args": {"key": "1", "value": "ACTIONBUTTON1"}},
            {"cap": "tune.binding.set", "args": {"key": "CTRL-F"}},
            {"cap": "tune.layout.set", "args": {"value": "Mine"}}])
        s.lua.execute(b"__cvars.nameplateShowAll.value = '1' __bindings['1'] = 'MOVEFORWARD' "
                      b"__bindings['CTRL-F'] = 'TOGGLEWORLDMAP' __editMode.activeLayout = 1")
        p = self.call(s, "tune.profile.apply", "{ name = 'base' }", "{ source = 'agent' }")
        self.assertEqual((p["title"], p["source"], len(p["steps"])), ('Apply profile "base"', "agent", 4))
        self.run_it(s)
        s.run(0.3)
        self.assertTrue(self.done(s, p["id"]))
        self.assertEqual((self.call(s, "tune.cvar.get", "{ name = 'nameplateShowAll' }")["value"],
                          py(s.g("__bindings")).get("1"), py(s.g("__bindings")).get("CTRL-F"),
                          self.call(s, "tune.layout.get")["value"]), ("0", "ACTIONBUTTON1", None, "Mine"))
        s.lua.execute(b"__text = WuxianKit:Call('tune.profile.export', { name = 'base' }).text")
        self.assertTrue(s.g("__text").startswith(b"WK1:"))
        self.assertEqual(self.call(s, "tune.profile.import", "{ text = __text, name = 'copy' }"),
                         {"name": "copy", "steps": 4, "imported": True})
        self.assertIn("there is a profile copy already",
                      self.fails(s, "WuxianKit:Call('tune.profile.import', { text = __text, name = 'copy' })"))
        self.assertEqual([x["name"] for x in self.call(s, "tune.profile.list")], ["base", "copy"])
        for steps, why in (("{ { cap = 'chat.send', args = { channel = 'guild', text = 'x' } } }", "a profile holds Do ones"),
                           ("{ { cap = 'tune.nope', args = {} } }", "no capability tune.nope"),
                           ("{ { cap = 'tune.cvar.set', args = { name = 'x' } } }", "value is missing"),
                           ("{ { cap = 'tune.cvar.set', args = { name = 'x', value = 1, extra = 2 } } }", "takes no argument extra")):
            self.assertIn(why, self.fails(s, f"WuxianKit:Call('tune.profile.save', {{ name = 'bad', steps = {steps} }})"))
        self.assertIn("damaged", self.fails(s, "WuxianKit:Call('tune.profile.import', { text = 'WK1:zz' })"))
        self.call(s, "tune.profile.delete", "{ name = 'copy' }")
        self.assertEqual([x["name"] for x in self.call(s, "tune.profile.list")], ["base"])

    def test_gate_two(self):
        """one proposal turns the UI into a healer's (a setting, a layout, a key): one click runs them in order, the
        layout waited for before the key; one undo brings back what was"""
        s = self.start()
        s.lua.execute(b"__p = WuxianKit:Propose({ { 'tune.cvar.set', { name = 'nameplateShowAll', value = 1 } }, "
                      b"{ 'tune.layout.set', { value = 'Modern' } }, "
                      b"{ 'tune.binding.set', { key = 'CTRL-F', value = 'TOGGLEWORLDMAP' } } }, "
                      b"{ source = 'agent', title = 'healer' })")
        p = py(s.g("__p"))
        self.assertEqual([st["preview"][0] for st in p["steps"]], [
            "nameplateShowAll: 0 → 1", "Active layout: Mine → Modern", "CTRL-F: (none) → Open World Map (TOGGLEWORLDMAP)"])
        self.run_it(s)
        self.assertNotIn("CTRL-F", py(s.g("__bindings")))                   # the key waits for the layout
        s.run(0.3)
        self.assertTrue(self.done(s, p["id"]))
        self.assertEqual((s.lua.eval(b"__cvars.nameplateShowAll.value"), s.lua.eval(b"__editMode.activeLayout"),
                          py(s.g("__bindings")).get("CTRL-F")), (b"1", 1, "TOGGLEWORLDMAP"))
        self.undo(s, p["id"])
        s.run(0.3)
        self.assertEqual((s.lua.eval(b"__cvars.nameplateShowAll.value"), s.lua.eval(b"__editMode.activeLayout"),
                          py(s.g("__bindings")).get("CTRL-F")), (b"0", 3, None))


if __name__ == "__main__":
    unittest.main()
