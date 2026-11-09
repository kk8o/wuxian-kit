"""An app's options in the order its declaration gives (order, then name; the core's activity and quiet first) and with
their hints, as kit.options { app } and the card show them."""
import unittest

from kitmock import Session, lupa, py


@unittest.skipIf(lupa is None, "lupa (Lua 5.1 for Python) is not installed")
class AppOptions(unittest.TestCase):
    def test_order_and_hints(self):
        s = Session(self)
        s.login()
        s.run(1)
        self.addCleanup(lambda: self.assertEqual(s.errors(), []))
        s.lua.execute("""
WuxianKit:App("demo", { title = "Demo", hear = { "bus:demo.*" }, pace = true,
  options = { avoid = { kind = "list", title = "不聊", hint = "这些不聊", order = 2 },
              topics = { kind = "list", title = "多聊", hint = "这些多聊", order = 1 },
              alpha = { kind = "boolean", title = "A" } } })
""".encode())
        s.run(1)
        self.assertEqual(py(s.ns.App(b"demo").optionOrder), ["activity", "quiet", "topics", "avoid", "alpha"])
        opts = py(s.ns.AppOptionList(b"demo"))
        self.assertEqual(opts["topics"]["hint"], "这些多聊")
        self.assertTrue(opts["quiet"]["hint"])                                  # the core's own hint
        self.assertNotIn("hint", opts["alpha"])

    def test_agent_order_is_checked(self):
        s = Session(self)
        s.login()
        s.run(1)
        ok, err = s.lua.eval(b"""pcall(WuxianKit.App, WuxianKit, "x", { hear = { "bus:x.*" },
            options = { a = { kind = "boolean", order = "first" } } })""")
        self.assertTrue(ok)                                                    # an addon's odd order is just ignored
        self.assertIsNone(s.ns.App(b"x").decl.options[b"a"]["order"])


if __name__ == "__main__":
    unittest.main()
