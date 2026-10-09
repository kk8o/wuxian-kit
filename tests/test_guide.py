"""指引 (Guide) under Lua 5.1 in the mock client: a highlight round a frame (by name or path), a note, the map's pin, a
tour the player steps through, and all of it put away (by guide.clear, or when the extension goes off)."""
import unittest

from kitmock import Session, click, lupa, py, texts


@unittest.skipIf(lupa is None, "lupa (Lua 5.1 for Python) is not installed")
class Guide(unittest.TestCase):
    def start(self):
        s = Session(self)
        s.lua.execute(b"__events = {} WuxianKit:On('*', function(topic, data) "
                      b"__events[#__events + 1] = { topic = topic, data = data } end)")
        s.lua.execute(b"TestButton = CreateFrame('Button', 'TestButton', UIParent) "
                      b"TestButton.icon = TestButton:CreateTexture() HiddenThing = CreateFrame('Frame', 'HiddenThing', UIParent) "
                      b"HiddenThing:Hide()")
        s.login()
        s.run(1)
        self.addCleanup(lambda: self.assertEqual(s.errors(), []))
        return s

    def call(self, s, cap, args="{}"):
        s.lua.execute(f"__answer = WuxianKit:Call({cap!r}, {args})".encode())
        return py(s.g("__answer"))

    def fails(self, s, code):
        ok, err = s.lua.eval(f"pcall(function() {code} end)".encode())
        self.assertFalse(ok, code)
        return err.decode()

    def marks(self, s):
        """the highlight frames showing, each with its text"""
        out = []
        for f in (s.g("UIParent")[b"__kids"] or {}).values():
            if f[b"edges"] and f[b"shown"]:
                out.append(f[b"text"][b"text"].decode())
        return out

    def tour(self, s):
        return [e["data"] for e in py(s.g("__events")) or [] if e["topic"] == "guide.tour"]

    def test_pointing(self):
        s = self.start()
        self.assertEqual(self.call(s, "guide.highlight", "{ frame = 'TestButton', text = 'Click here' }"),
                         {"frame": "TestButton", "shown": True})
        self.assertEqual(self.call(s, "guide.highlight", "{ frame = 'TestButton.icon' }")["shown"], True)
        self.assertEqual(self.call(s, "guide.highlight", "{ frame = 'HiddenThing' }")["shown"], False)
        self.assertEqual(self.marks(s), ["Click here", "", ""])
        self.assertIn("no frame Nope.x", self.fails(s, "WuxianKit:Call('guide.highlight', { frame = 'Nope.x' })"))
        self.call(s, "guide.note", "{ text = 'Open your bags', title = 'Bags', frame = 'TestButton' }")
        note = s.g("WuxianKitGuideNote")
        self.assertEqual((note[b"shown"], texts(note)[:2]), (True, ["Bags", "Open your bags"]))
        click(note[b"ok"])
        self.assertFalse(note[b"shown"])
        self.assertEqual(self.call(s, "guide.waypoint", "{ x = 41.8, y = 62.3 }"), {"map": 2521, "x": 41.8, "y": 62.3})
        self.assertEqual((py(s.g("__waypoint"))["uiMapID"], s.g("__superTracked")), (2521, True))
        self.assertIn("map 947 takes no pin", self.fails(s, "WuxianKit:Call('guide.waypoint', { x = 1, y = 1, map = 947 })"))
        self.assertIn("x and y are 0 to 100", self.fails(s, "WuxianKit:Call('guide.waypoint', { x = 101, y = 1 })"))
        self.call(s, "guide.clear")
        self.assertEqual((self.marks(s), s.g("__waypoint")), ([], None))      # its pin goes too
        self.call(s, "guide.waypoint", "{ x = 10, y = 10 }")
        s.lua.execute(b"__waypoint = UiMapPoint.CreateFromCoordinates(2521, 0.5, 0.5)")   # the player's own
        self.call(s, "guide.clear")
        self.assertEqual(py(s.g("__waypoint"))["position"], {"x": 0.5, "y": 0.5})

    def test_a_tour(self):
        s = self.start()
        self.call(s, "guide.tour", "{ title = 'Your first macro', steps = { { text = 'Open the macro window' }, "
                                   "{ text = 'Drag it to your bar', frame = 'TestButton' } } }")
        note = s.g("WuxianKitGuideNote")
        self.assertEqual(texts(note)[:2], ["Your first macro · 1/2", "Open the macro window"])
        self.assertEqual((note[b"next"][b"label"][b"text"], self.marks(s)), (b"Next", []))
        click(note[b"next"])
        self.assertEqual((texts(note)[1], note[b"next"][b"label"][b"text"], len(self.marks(s))),
                         ("Drag it to your bar", b"Done", 1))
        click(note[b"next"])
        self.assertEqual([(t["step"], t["state"]) for t in self.tour(s)], [(1, "shown"), (2, "shown"), (2, "done")])
        self.assertFalse(note[b"shown"])
        self.call(s, "guide.tour", "{ steps = { { text = 'one' }, { text = 'two' } } }")
        self.call(s, "guide.clear")
        self.assertEqual(self.tour(s)[-1], {"step": 1, "of": 2, "state": "closed"})
        self.assertIn("step 1: no frame Gone", self.fails(s, "WuxianKit:Call('guide.tour', { steps = { { text = 'x', frame = 'Gone' } } })"))
        self.call(s, "guide.highlight", "{ frame = 'TestButton' }")
        s.lua.execute(b"WuxianKit:Call('kit.extension.set', { extension = 'guide', value = false })")
        click(s.g("WuxianKitProposal")[b"run"])                              # off: all of it put away
        self.assertEqual(self.marks(s), [])


    def test_a_tour_taken_over_and_the_agents_words(self):
        """a note in place of a tour going on ends the tour as closed; the agent's words show escaped, lines kept"""
        s = self.start()
        self.call(s, "guide.tour", "{ steps = { { text = 'one' }, { text = 'two' } } }")
        self.call(s, "guide.note", "{ text = 'A |cff000000hidden|r note' }")
        self.assertEqual(self.tour(s)[-1], {"step": 1, "of": 2, "state": "closed"})
        self.assertIn("A ||cff000000hidden||r note", texts(s.g("WuxianKitGuideNote")))

if __name__ == "__main__":
    unittest.main()
