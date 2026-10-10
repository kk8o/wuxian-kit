"""The built-in extensions (WuxianKit/Extensions) and the core's addon messages under Lua 5.1 in the mock client: chat
heard through the Feed pattern (and kept through a reload), chat sent as a Say, settings looked up, WuxianKit.Comm."""
import unittest

from kitmock import Session, click, lupa, py, texts


@unittest.skipIf(lupa is None, "lupa (Lua 5.1 for Python) is not installed")
class Extensions(unittest.TestCase):
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

    def heard(self, s):
        return [e["data"] for e in py(s.g("__events")) or [] if e["topic"] == "chat.message"]

    def say(self, s, event, text, sender, guid):
        s.fire(event, text, sender, "", "", "", "", 0, 0, "", 1, 77, guid)

    def test_chat_heard_for_a_while(self):
        s = self.start()
        status = self.call(s, "chat.listen", "{ channels = { 'guild', 'whisper', 'guild' }, minutes = 10 }")
        self.assertEqual((status["on"], status["channels"]), (True, ["guild", "whisper"]))
        self.assertIn("Listen to channels: Guild, Whisper, until", s.chat())
        item = "|cffffffff|Hitem:7166::::::::1:::::::|h[Copper Dagger]|h|r"
        self.say(s, "CHAT_MSG_GUILD", f"how do I make {item}?", "Asker-Realm", "Player-1-00000002")
        self.say(s, "CHAT_MSG_PARTY", "not heard", "Other-Realm", "Player-1-00000003")
        self.say(s, "CHAT_MSG_GUILD", "<secret>x", "Asker-Realm", "Player-1-00000002")
        self.say(s, "CHAT_MSG_GUILD", "mine", "Wuxian-Realm", "Player-1-00000001")
        self.say(s, "CHAT_MSG_WHISPER", "psst", "Friend-Realm", "Player-1-00000004")
        msgs = self.heard(s)
        self.assertEqual(len(msgs), 3)
        self.assertEqual((msgs[0]["channel"], msgs[0]["sender"], msgs[0]["plain"], msgs[0].get("self")),
                         ("guild", "Asker", "how do I make [Copper Dagger]?", None))
        self.assertEqual(msgs[0]["links"], [{"kind": "item", "id": 7166, "name": "Copper Dagger"}])
        self.assertEqual((msgs[1]["self"], msgs[2]["target"]), (True, "Friend"))
        s2 = s.reload()                                                    # kept through a reload
        s2.login()
        s2.lua.execute(b"__events = {} WuxianKit:On('*', function(topic, data) "
                       b"__events[#__events + 1] = { topic = topic, data = data } end)")
        self.say(s2, "CHAT_MSG_GUILD", "still here?", "Asker-Realm", "Player-1-00000002")
        self.assertEqual([m["plain"] for m in self.heard(s2)], ["still here?"])
        s2.run(601)                                                        # its ten minutes are over
        self.say(s2, "CHAT_MSG_GUILD", "too late", "Asker-Realm", "Player-1-00000002")
        self.assertEqual(len(self.heard(s2)), 1)
        self.assertEqual(self.call(s2, "chat.listen.status"), {"on": False})
        self.assertIn("channels: shout is not one of guild", self.fails(s2, "WuxianKit:Call('chat.listen', { channels = { 'shout' } })"))
        self.call(s2, "chat.listen", "{ channels = { 'guild' } }")
        self.call(s2, "chat.listen.stop")
        self.assertIn("Listen to channels: stopped", "\n".join(s2.lines))
        self.addCleanup(lambda: self.assertEqual(s2.errors(), []))

    def test_chat_send(self):
        s = self.start()
        p = self.call(s, "chat.send", "{ channel = 'guild', text = 'take {item:7166:Copper Dagger} to the smith' }")
        self.assertEqual((p["steps"][0]["preview"], p["steps"][0]["scope"]),
                         (["Guild: take [Copper Dagger] to the smith"], "chat.guild"))
        click(s.g("WuxianKitProposal")[b"run"])
        self.assertEqual(py(s.g("__sent")), [{"text": "take |cffffffff|Hitem:7166::::::::1:::::::|h[Copper Dagger]|h|r to "
                                                       "the smith", "type": "GUILD"}])
        say = self.call(s, "chat.send", "{ channel = 'say', text = 'hi' }")
        self.assertEqual(say["steps"][0]["scope"], "chat.send")              # no scope to let say go without asking
        click(s.g("WuxianKitProposal")[b"decline"])
        for args, why in (("{ channel = 'guild', text = 'a|b' }", "has a | or a line break"),
                          ("{ channel = 'guild', text = string.rep('x', 300) }", "300 bytes, more than 255"),
                          ("{ channel = 'whisper', text = 'hi' }", "a whisper needs target"),
                          ("{ channel = 'guild', text = '' }", "text is empty")):
            self.assertIn(why, self.fails(s, f"WuxianKit:Call('chat.send', {args})"))
        s.lua.execute(b"__lockdown = true")                                 # a Say waits out chat lockdown by itself
        self.call(s, "chat.send", "{ channel = 'whisper', target = 'Friend', text = 'later' }")
        self.assertFalse(s.g("WuxianKitProposal")[b"run"][b"enabled"])
        self.assertIn("Not available: Chat is restricted", "\n".join(texts(s.g("WuxianKitProposal"))))
        s.lua.execute(b"__lockdown = false")
        s.run(1.1)
        click(s.g("WuxianKitProposal")[b"run"])
        self.assertEqual(py(s.g("__sent"))[-1], {"text": "later", "type": "WHISPER", "target": "Friend"})

    def test_chat_alone_targets_and_ones_own_whispers(self):
        """a message to a public channel is a proposal of its own; a target has no | or line break; a whisper the
        player sends is heard as theirs, to the other player"""
        s = self.start()
        self.assertIn("goes in a proposal of its own", self.fails(s, "WuxianKit:Propose({ { 'chat.send', { channel = 'say', "
                                                                   "text = 'hi' } }, { 'tune.cvar.set', { name = "
                                                                   "'nameplateShowAll', value = 1 } } })"))
        self.assertIn("target has a | or a line break",
                      self.fails(s, "WuxianKit:Call('chat.send', { channel = 'whisper', target = 'A|cffB', text = 'hi' })"))
        self.call(s, "chat.listen", "{ channels = { 'whisper' } }")
        self.say(s, "CHAT_MSG_WHISPER_INFORM", "on my way", "Friend-Realm", "Player-1-00000004")
        m = self.heard(s)[-1]
        self.assertEqual((m["sender"], m["target"], m["self"], m["guid"]),
                         ("Wuxian Forever", "Friend", True, "Player-1-00000001"))

    def test_settings_looked_up(self):
        s = self.start()
        found = [c["name"] for c in self.call(s, "tune.cvar.find", "{ text = 'nameplate' }")]
        self.assertEqual(found, ["nameplateCastBarDisplay", "nameplateClamped", "nameplateMaxDistance", "nameplateShowAll"])
        vol = self.call(s, "tune.cvar.find", "{ text = 'volume', limit = 1 }")
        self.assertEqual((len(vol), vol[0]["name"], vol[0]["category"]), (1, "Sound_MasterVolume", "sound"))
        self.assertEqual(self.call(s, "tune.cvar.get", "{ name = 'secureThing' }")["secure"], True)

    def test_addon_messages(self):
        s = self.start()
        s.lua.execute("""
            __got = {}
            WuxianKit.Comm.Listen("WXTEST", function(data, sender, channel)
                __got[#__got + 1] = { data = data, sender = sender, channel = channel }
            end)
            __big = { text = string.rep("两\\0\\1x", 600), list = { 1, 2.5, -3, true, false }, nested = { a = { b = "c" } } }
            __n = WuxianKit.Comm.Send("WXTEST", __big, "GUILD")
            WuxianKit.Comm.Send("WXTEST", "small", "WHISPER", "Friend")""".encode())
        self.assertGreater(s.g("__n"), 15)
        self.assertEqual(s.lua.eval(b"#__addon_sent"), 10)                 # BURST at once: the rest waits
        self.assertTrue(s.lua.eval(b"(function() for _, m in ipairs(__addon_sent) do if #m.text > 255 then return false "
                                   b"end end return true end)()"))
        s.run(3)
        self.assertIn(s.lua.eval(b"#__addon_sent"), (12, 13))             # then one a second
        s.lua.execute(b"__throttle = 1")                                    # the server says slow down: it waits a second
        s.run(40)
        self.assertEqual(s.lua.eval(b"#__addon_sent"), s.g("__n") + 1)
        s.lua.execute(b'for _, m in ipairs(__addon_sent) do __fire("CHAT_MSG_ADDON", m.prefix, m.text, m.channel, "Me-Realm") end')
        self.assertEqual(s.lua.eval(b"#__got"), 2)
        self.assertTrue(s.lua.eval(b"__got[1].data.text == __big.text and __got[1].data.nested.a.b == 'c' "
                                   b"and __got[1].data.list[2] == 2.5 and __got[1].data.list[5] == false"))
        self.assertEqual(s.lua.eval(b"__got[2].data .. ' ' .. __got[2].channel"), b"small WHISPER")
        deserialize = s.lua.eval(b"WuxianKit.Comm.Deserialize")
        for bad in (b"x", b"s5:ab", b"t s1:a", b"n1e;", b"Tz"):
            value, why = deserialize(bad)
            self.assertIsNone(value, bad)
            self.assertTrue(why, bad)


if __name__ == "__main__":
    unittest.main()
