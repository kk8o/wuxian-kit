"""Sources (ext:Source, the layered kit): what apps hear is what the extensions register. The registry (a name is the
whole kit's: another extension's of the same name is an error; the same extension's again replaces it), the core's bus
and the chat and game extensions' own sources heard through apps, a new declaration of a source nobody registered
refused while a remembered one stays (blocked, and a run of it waiting, until the source is there, then heard),
kit.app.declare's doc and the manifest made from the registry."""
import unittest

from kitmock import Session, lupa, py
from test_standalone import bridge

# radio: a source of another addon's (an extension of its own); __radio(what, item) hands items to its subscribers
RADIO = b"""
local x = WuxianKit:Extension('rx', { title = 'Radio' })
__rx, __radio_subs, __radio_n = x, {}, 0
x:Source('radio', { title = 'Radio', doc = 'radio:<station>: what a station plays',
	values = function() return { 'jazz', 'news' } end,
	check = function(what) if what ~= 'jazz' and what ~= 'news' then return 'a station is jazz or news' end end,
	on = function(self, what, fn) __radio_n = __radio_n + 1 __radio_subs[__radio_n] = { what = what, fn = fn } return __radio_n end,
	off = function(self, t) __radio_subs[t] = nil end })
function __radio(what, item)
	for _, s in pairs(__radio_subs) do if s.what == what then s.fn(item) end end
end
"""


@unittest.skipIf(lupa is None, "lupa (Lua 5.1 for Python) is not installed")
class Sources(unittest.TestCase):
    def start(self, s=None, before=None, **kw):
        if s is None:
            kw.setdefault("saved", {"WoWBridge": bridge("0.9.7")})
            s = Session(self, **kw)
        s.lua.execute(b"__events = {} WuxianKit:On('*', function(topic, data) "
                      b"__events[#__events + 1] = { topic = topic, data = data } end)")
        if before:
            s.lua.execute(before)
        s.login()
        s.run(1)
        self.addCleanup(lambda: self.assertEqual(s.errors(), []))
        return s

    def agent(self, s, cap, args="{}"):
        s.lua.execute(f"__r = __fns[{cap!r}]({args})".encode())
        return py(s.g("__r"))

    def fails(self, s, code):
        ok, err = s.lua.eval(f"pcall(function() {code} end)".encode())
        self.assertFalse(ok, code)
        return err.decode()

    def items(self, s, app):
        return [i for e in py(s.g("__events")) or [] if e["topic"] == "app." + app for i in e["data"]["items"]]

    def test_the_registry(self):
        s = self.start(before=RADIO)
        self.assertEqual(py(s.ns.sourceOrder), ["bus", "chat", "game", "route", "radio"])
        self.assertIn("other: the source radio is extension rx's",
                      self.fails(s, "WuxianKit:Extension('other'):Source('radio', { on = print, off = print })"))
        for code, why in (("WuxianKit:Extension('other'):Source('Bad', { on = print, off = print })", "lowercase"),
                          ("WuxianKit:Extension('other'):Source('player', { on = print, off = print })", "player"),
                          ("WuxianKit:Extension('other'):Source('fm', { on = print })", "off"),
                          ("WuxianKit:Extension('other'):Source('fm', { on = print, off = print, check = 1 })", "check")):
            self.assertIn(why, self.fails(s, code), code)
        # the same extension's again replaces it (an addon's file run again)
        s.lua.execute(b"__rx:Source('radio', { title = 'Radio 2', on = function() return 0 end, off = function() end })")
        self.assertEqual(s.lua.eval(b"WuxianKit:Extension('rx').sourceOrder[1]"), b"radio")
        m = py(s.lua.eval(b"WuxianKit:Manifest()"))
        rx = next(e for e in m["extensions"] if e["id"] == "rx")
        self.assertEqual([x["title"] for x in rx["sources"]], ["Radio 2"])

    def test_heard_through_an_app(self):
        s = self.start(before=RADIO)
        self.agent(s, "kit.app.declare", "{ app = 'mix', hear = { 'radio:jazz', 'chat:guild', 'game:quest', "
                                         "'bus:demo.*' }, lease = 0 }")
        st = self.agent(s, "kit.app.open", "{ app = 'mix' }")
        self.assertEqual(st["hear"], ["radio:jazz", "chat:guild", "game:quest", "bus:demo.*"])
        s.lua.execute(b"__radio('jazz', { tune = 'So What' }) __radio('news', { story = 'x' })")
        s.fire("CHAT_MSG_GUILD", "hello", "Asker-Realm", "", "", "", "", 0, 0, "", 1, 4242, "Player-1-00000002")
        s.fire("QUEST_TURNED_IN", 3001, 0, 0)
        s.lua.execute(b"WuxianKit:Emit('demo.ping', { n = 1 })")
        got = [(i["source"], i.get("tune") or i.get("plain") or i.get("kind") or i.get("topic")) for i in self.items(s, "mix")]
        self.assertEqual(got, [("radio", "So What"), ("chat", "hello"), ("game", "quest.turnin"), ("bus", "demo.ping")])
        self.assertIn("radio:rock: a station is jazz or news",
                      self.fails(s, "__fns['kit.app.declare']({ app = 'r', hear = { 'radio:rock' } })"))
        self.assertIn("pop:x: no source pop (the sources: bus, chat, game, radio, route)",
                      self.fails(s, "__fns['kit.app.declare']({ app = 'r', hear = { 'pop:x' } })"))
        s.ns.Switch(b"rx", False)                                        # its extension off: the app stops
        st = self.agent(s, "kit.app.status", "{ app = 'mix' }")
        self.assertEqual((st["on"], st["why"]), (False, "extension"))
        s.lua.execute(b"__radio('jazz', { tune = 'Blue' })")
        self.assertEqual(len(self.items(s, "mix")), 4)
        st = self.agent(s, "kit.app.open", "{ app = 'mix' }")             # and a new run cannot start
        self.assertEqual((st["on"], st["blocked"]), (False, "Needs the Radio extension on"))

    def test_a_remembered_declaration_waits_for_its_source(self):
        s = self.start(before=RADIO)
        self.agent(s, "kit.app.declare", "{ app = 'fan', title = 'Fan', hear = { 'radio:news' }, lease = 0 }")
        self.agent(s, "kit.app.declare", "{ app = 'mix', hear = { 'radio:jazz', 'bus:demo.*' }, lease = 0 }")
        self.agent(s, "kit.app.open", "{ app = 'mix' }")
        s2 = self.start(s.reload())                                      # the radio's addon is not loaded (yet)
        st = self.agent(s2, "kit.app.status", "{ app = 'fan' }")
        self.assertEqual((st["on"], st["hear"], st["blocked"]), (False, ["radio:news"], "Needs the source radio"))
        st = self.agent(s2, "kit.app.open", "{ app = 'fan' }")
        self.assertEqual((st["on"], st["blocked"]), (False, "Needs the source radio"))
        self.assertIn("radio:news: no source radio",
                      self.fails(s2, "__fns['kit.app.declare']({ app = 'new', hear = { 'radio:news' } })"))
        st = self.agent(s2, "kit.app.status", "{ app = 'mix' }")         # a run waits for it: on, nothing heard yet
        self.assertEqual((st["on"], st["waiting"]), (True, "Needs the source radio"))
        s2.lua.execute(b"WuxianKit:Emit('demo.a', 1)")
        s2.lua.execute(RADIO)                                            # the radio's addon loads after all
        s2.run(0.5)
        self.assertNotIn("blocked", self.agent(s2, "kit.app.status", "{ app = 'fan' }"))
        self.assertNotIn("waiting", self.agent(s2, "kit.app.status", "{ app = 'mix' }"))
        self.assertTrue(self.agent(s2, "kit.app.open", "{ app = 'fan' }")["on"])
        s2.lua.execute(b"__radio('news', { story = 'up' }) __radio('jazz', { tune = 'late' })")
        self.assertEqual([i["story"] for i in self.items(s2, "fan")], ["up"])
        self.assertEqual([i["source"] for i in self.items(s2, "mix")], ["radio"])   # heard once all of it is there

    def test_the_doc_and_the_manifest(self):
        s = self.start()
        doc = py(s.lua.eval(b"WuxianKit:Capability('kit.app.declare')"))["doc"]
        for want in ("chat:<channel>", "game:<topic>", "bus:<topic>", "(*|guild|officer|", "(combat|aura|growth|"):
            self.assertIn(want, doc)
        self.assertNotIn("radio:", doc)
        rev = py(s.lua.eval(b"WuxianKit:Manifest()"))["revision"]
        s.lua.execute(RADIO)
        s.run(1)
        doc = py(s.lua.eval(b"WuxianKit:Capability('kit.app.declare')"))["doc"]
        self.assertIn("radio:<station>: what a station plays (jazz|news)", doc)   # the doc follows the registry
        m = py(s.lua.eval(b"WuxianKit:Manifest()"))
        rx = next(e for e in m["extensions"] if e["id"] == "rx")
        self.assertEqual(rx["sources"], [{"name": "radio", "title": "Radio", "doc": "radio:<station>: what a station plays",
                                          "values": ["jazz", "news"]}])
        self.assertNotEqual(m["revision"], rev)
        self.assertEqual(py(s.lua.eval(b"(function() for _, e in ipairs(__events) do if e.topic == 'kit.changed' "
                                       b"then __last = e.data.revision end end return __last end)()")), m["revision"])
        s.ns.Switch(b"rx", False)                                        # an extension off: no sources listed
        rx = next(e for e in py(s.lua.eval(b"WuxianKit:Manifest()"))["extensions"] if e["id"] == "rx")
        self.assertNotIn("sources", rx)


if __name__ == "__main__":
    unittest.main()
