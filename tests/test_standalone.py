"""WuxianKit on its own, and beside WoWBridges it does not take or that misbehave: with no WoWBridge it runs as for any
addon (the rest of the suite runs so too) and says nothing of 无限工坊; an older WoWBridge (0.9.6: an agent's calls would
come as code) is left alone; one whose calls raise breaks nothing (the bus, calls and proposals go on, no Lua error);
names WoWBridge could not carry are refused when declared, with or without it; the link state comes from a WoWBridge's
own Online()."""
import unittest

from kitmock import Session, lupa


def bridge(version, online=None, expose="__exposed[#__exposed + 1] = name __fns[name] = fn", emit="return true"):
    """a WoWBridge stub (a Lua literal): its VERSION, Online() answering the global __online (None: no Online), and what
    its handle's Expose and Emit do; Bind counts in __binds"""
    on = "Online = function() return __online end," if online else ""
    return (f"(function() __binds, __exposed, __emitted, __fns = 0, {{}}, {{}}, {{}} return {{ VERSION = {version!r}, {on} "
            f"Bind = function(addon) __binds = __binds + 1 return {{ "
            f"Expose = function(self, name, fn, doc) {expose} end, "
            f"Emit = function(self, topic, data) __emitted[#__emitted + 1] = topic {emit} end }} end }} end)()").encode()


@unittest.skipIf(lupa is None, "lupa (Lua 5.1 for Python) is not installed")
class Standalone(unittest.TestCase):
    def start(self, **kw):
        s = Session(self, **kw)
        s.lua.execute(b"__heard = {} WuxianKit:On('kit.*', function(topic) __heard[#__heard + 1] = topic end)")
        s.login()
        s.run(1)
        self.addCleanup(lambda: self.assertEqual(s.errors(), []))
        return s

    def window_line(self, s):
        s.lua.execute(b"SlashCmdList.WUXIANKIT('')")
        return s.lua.eval(b"WuxianKitWindow.agent:GetText()").decode()

    def works(self, s):
        """a call and a proposal of the core run as for any addon"""
        self.assertEqual(s.lua.eval(b"WuxianKit:Call('tune.cvar.get', { name = 'nameplateShowAll' }).value"), b"0")
        self.assertEqual(s.lua.eval(b"WuxianKit:Call('tune.cvar.set', { name = 'nameplateShowAll', value = 1 }).state"),
                         b"pending")

    def test_without_wowbridge(self):
        s = self.start()
        self.assertIs(s.lua.eval(b"WuxianKit:AgentOnline()"), False)
        self.assertEqual(self.window_line(s), "")                   # nothing about 无限工坊 without it
        self.works(s)
        self.assertIn(b"kit.ready", list(s.g("__heard").values()))

    def test_an_older_wowbridge_is_left_alone(self):
        s = self.start(saved={"WoWBridge": bridge("0.9.6")})
        self.assertEqual(s.g("__binds"), 0)
        self.assertIs(s.lua.eval(b"WuxianKit:AgentOnline()"), False)
        self.assertEqual(self.window_line(s), "")
        self.works(s)

    def test_a_wowbridge_that_raises(self):
        s = self.start(saved={"WoWBridge": bridge("0.9.7", expose="error('refused')", emit="error('boom')")})
        self.assertEqual(s.g("__binds"), 1)
        self.works(s)
        s.run(1)
        self.assertIn(b"kit.proposal", list(s.g("__heard").values()))   # the bus goes on
        self.assertIs(s.lua.eval(b"WuxianKit:AgentOnline()"), False)     # no Online(), no insides to read
        self.assertEqual(self.window_line(s), "Not linked to Wuxian Workshop")

    def test_online_from_wowbridge(self):
        s = self.start(saved={"WoWBridge": bridge("0.9.8", online=True)})
        exposed = list(s.g("__exposed").values())
        self.assertIn(b"tune.cvar.get", exposed)
        self.assertIn(b"kit.propose", exposed)
        self.assertEqual(self.window_line(s), "Not linked to Wuxian Workshop")
        s.lua.execute(b"__online = true")
        s.run(1.2)                                                   # the window's tick
        self.assertEqual(s.lua.eval(b"WuxianKitWindow.agent:GetText()").decode(), "Linked to Wuxian Workshop")
        self.assertIn(b"kit.ready", list(s.g("__emitted").values()))
        ok, err = s.lua.eval(b"pcall(__fns['kit.propose'], { steps = { { cap = 'tune.cvar.get', args = { name = 'x' } } } })")
        self.assertFalse(ok)                                           # the core's refusal alone, no place in Bridge.lua
        self.assertEqual(err, b"step 1: tune.cvar.get is a see capability; a proposal holds Say and Do ones")

    def test_names_too_long(self):
        s = self.start()
        for code, why in ((b"WuxianKit:Extension('longnames', {}):See(string.rep('a', 60), { run = function() end })",
                           b"at most 64 bytes"),
                          (b"WuxianKit:Extension('longnames', {}):Event(string.rep('b', 60))", b"longer than 64 bytes"),
                          (b"WuxianKit:Emit(string.rep('c', 65), {})", b"at most 64 bytes")):
            ok, err = s.lua.eval(b"pcall(function() " + code + b" end)")
            self.assertFalse(ok, code)
            self.assertIn(why, err, code)


if __name__ == "__main__":
    unittest.main()
