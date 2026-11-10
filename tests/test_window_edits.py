"""The text boxes of the window's pages and of the cards (Core/UI/Window.lua's PutEdit) under Lua 5.1 in the mock client:
the boxes are used again by their place, so one being typed in when the page is drawn again keeps its text only while it
still edits the same option; put to another option, or no longer drawn, its edit ends first and what was typed goes to
the option it was typed for, never to the one that took its place."""
import unittest

from kitmock import click, lupa, texts
from test_app_panel import log, shown, start


def typing(box, text):
    """the player types text into an edit box and stays in it"""
    box.SetFocus(box)
    box.SetText(box, text.encode())


@unittest.skipIf(lupa is None, "lupa (Lua 5.1 for Python) is not installed")
class WindowEdits(unittest.TestCase):
    def window(self, s, page="kit"):
        s.lua.execute(f"WuxianKit:Window({page!r})".encode())
        return s.g("WuxianKitWindow")

    def item(self, w, title):
        return next(b for b in shown(w[b"items"]) if b[b"label"][b"text"].decode() == title)

    def extensions(self, s):
        s.lua.execute(b"local a = WuxianKit:Extension('alpha', { title = 'Alpha' }) "
                      b"a:Option('name', { title = 'Name', kind = 'text', default = 'a0' }) "
                      b"local b = WuxianKit:Extension('beta', { title = 'Beta' }) "
                      b"b:Option('motto', { title = 'Motto', kind = 'text', default = 'b0' })")
        s.run(0.1)

    def get(self, s, ext, name):
        return s.lua.eval(f"WuxianKit:Extension({ext!r}):Get({name!r})".encode())

    def test_another_page_ends_the_edit(self):
        """typed on one page and not yet entered, then another page chosen: the text goes to the option it was typed
        for; the box, now the other page's, shows that page's value, and Enter there commits nothing of the first"""
        s = start(self)
        self.extensions(s)
        w = self.window(s, "alpha")
        box = shown(w[b"edits"])[0]
        self.assertEqual(box[b"text"], b"a0")
        typing(box, "typed for alpha")
        click(self.item(w, "Beta"))
        self.assertEqual(texts(w[b"body"])[0], "Beta")
        self.assertEqual((self.get(s, "alpha", "name"), self.get(s, "beta", "motto")), (b"typed for alpha", b"b0"))
        self.assertTrue(s.lua.eval(b"rawequal")(shown(w[b"edits"])[0], box))    # the same box, used again
        self.assertEqual((box[b"text"], box[b"focus"]), (b"b0", False))
        box.ClearFocus(box)                                                     # Enter: nothing changed here
        self.assertEqual(self.get(s, "beta", "motto"), b"b0")
        click(self.item(w, "Alpha"))
        self.assertEqual(box[b"text"], b"typed for alpha")

    def test_the_same_option_keeps_its_text(self):
        """drawn again while typed in (an app's page every few seconds), a box that still edits the same option keeps
        the keyboard and its text, uncommitted; Escape puts back what it had"""
        s = start(self)
        s.lua.execute(b"__add('one', { decl = { title = 'One' }, options = { "
                      b"greet = { title = 'Greeting', kind = 'text', value = 'hi' } } }) "
                      b"__add('two', { decl = { title = 'Two' }, options = { "
                      b"bye = { title = 'Farewell', kind = 'text', value = 'bye' } } })")
        w = self.window(s, "one")
        box = shown(w[b"edits"])[0]
        typing(box, "hel")
        s.run(12)                                                               # two redraws
        self.assertEqual((box[b"text"], box[b"focus"], log(s)), (b"hel", True, []))
        box.SetText(box, b"hello")
        click(self.item(w, "Two"))                                              # another app's option in its place
        self.assertEqual(log(s), ["option one greet hello"])
        self.assertEqual((box[b"text"], box[b"focus"]), (b"bye", False))
        typing(box, "see you")
        box[b"scripts"][b"OnEscapePressed"](box)
        self.assertEqual((box[b"text"], log(s)), (b"bye", ["option one greet hello"]))

    def test_a_box_no_longer_drawn_ends_its_edit(self):
        """a page with no box in that place: the box is hidden, its edit ended, the text given to its option; an
        option gone meanwhile moves the next one into its box, which is not given what was typed for the gone one"""
        s = start(self)
        s.lua.execute(b"__add('one', { decl = { title = 'One' }, options = { "
                      b"a = { title = 'A', kind = 'text', value = 'a0', order = 1 }, "
                      b"b = { title = 'B', kind = 'text', value = 'b0', order = 2 } } }) "
                      b"__add('bare', { decl = { title = 'Bare' } })")
        w = self.window(s, "one")
        first, second = shown(w[b"edits"])
        typing(second, "for b")
        click(self.item(w, "Bare"))
        self.assertEqual(log(s), ["option one b for b"])
        self.assertEqual((shown(w[b"edits"]), second[b"focus"]), ([], False))
        click(self.item(w, "One"))
        self.assertEqual((first[b"text"], second[b"text"]), (b"a0", b"for b"))
        typing(first, "for a")                                                  # an option gone meanwhile: b moves up
        s.g("__apps")[b"one"][b"options"][b"a"] = None
        s.lua.execute(b"__ns.UI.Refresh()")
        self.assertEqual(log(s)[1:], [])                                        # (a is gone: its text has nowhere to go)
        self.assertEqual((first[b"text"], first[b"focus"], len(shown(w[b"edits"]))), (b"for b", False, 1))

    def test_a_cards_box(self):
        """a card in another addon's window draws on its own canvas: its box keeps what is typed while the window is
        drawn, and the window's keeps its own"""
        s = start(self)
        self.extensions(s)
        s.lua.execute(b"__add('one', { decl = { title = 'One' }, options = { "
                      b"greet = { title = 'Greeting', kind = 'text', value = 'hi' } } }) "
                      b"__host = CreateFrame('Frame', nil, UIParent) __p = WuxianKit:AppPanel('one', __host, 320)")
        card = shown(s.g("__p")[b"edits"])[0]
        w = self.window(s, "alpha")
        box = shown(w[b"edits"])[0]
        typing(card, "on the card")
        click(self.item(w, "Beta"))
        self.assertEqual((card[b"text"], card[b"focus"], log(s)), (b"on the card", True, []))
        card.ClearFocus(card)
        self.assertEqual(log(s), ["option one greet on the card"])
        self.assertEqual((box[b"text"], self.get(s, "beta", "motto")), (b"b0", b"b0"))


if __name__ == "__main__":
    unittest.main()
