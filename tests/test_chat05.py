"""聊天 (Chat) 0.5 under Lua 5.1 in the mock client: message ids that go on through a reload, mentions (the whole name, a
part of it, an alias, a whisper; never the player's own), WuxianKit.Chat for other addons, chat.send's reply and its
<channel>.reply scope, and the option yield: a message waits while the player types or has just spoken."""
import unittest

from kitmock import Session, click, lupa, py, texts

FRIEND, ASKER = "Player-1-00000004", "Player-1-00000002"


@unittest.skipIf(lupa is None, "lupa (Lua 5.1 for Python) is not installed")
class Chat05(unittest.TestCase):
    line = 100

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
        """the items of the app ear's wakes (kit.app.open { app = 'ear', hear = ... }: no digest, one each)"""
        return [i for e in py(s.g("__events")) or [] if e["topic"] == "app.ear" for i in e["data"]["items"]]

    def say(self, s, event, text, sender, guid):
        """the client's chat event, each with its own line id; answers what WuxianKit.Chat.Read makes of it"""
        Chat05.line += 1
        args = (text, sender, "", "", "", "", 0, 0, "", 1, Chat05.line, guid)
        s.fire(event, *args)
        enc = [a.encode() if isinstance(a, str) else a for a in args]
        return py(s.lua.eval(b"function(...) return WuxianKit.Chat.Read(...) end")(event.encode(), *enc))

    def aliases(self, s, text):
        """the player's aliases as saved (a list option: a table; a text saved by 0.5 reads as a list)"""
        s.lua.execute(f"WuxianKitDB.ext.chat.options = WuxianKitDB.ext.chat.options or {{}} "
                      f"WuxianKitDB.ext.chat.options.aliases = {text}".encode())

    def test_ids_go_on_through_a_reload(self):
        s = self.start()
        self.call(s, "kit.app.open", "{ app = 'ear', hear = { 'chat:guild' }, lease = 0 }")
        a = self.say(s, "CHAT_MSG_GUILD", "one", "Asker-Realm", ASKER)
        b = self.say(s, "CHAT_MSG_GUILD", "two", "Asker-Realm", ASKER)
        c = self.say(s, "CHAT_MSG_PARTY", "three", "Asker-Realm", ASKER)     # not listened to: still read, still an id
        self.assertEqual([b["id"] - a["id"], c["id"] - b["id"]], [1, 1])
        self.assertEqual([m["id"] for m in self.heard(s)], [a["id"], b["id"]])    # the app's item: a copy, its id
        self.assertEqual(py(s.lua.eval(f"WuxianKit.Chat.Message({b['id']})".encode()))["plain"], "two")
        s2 = s.reload()
        s2.login()
        self.addCleanup(lambda: self.assertEqual(s2.errors(), []))
        d = self.say(s2, "CHAT_MSG_GUILD", "after", "Asker-Realm", ASKER)
        self.assertEqual(d["id"], c["id"] + 1)
        self.assertIsNone(s2.lua.eval(f"WuxianKit.Chat.Message({b['id']})".encode()))   # kept in memory only

    def test_the_ring_holds_200(self):
        s = self.start()
        first = self.say(s, "CHAT_MSG_GUILD", "m0", "Asker-Realm", ASKER)["id"]
        for i in range(1, 201):
            last = self.say(s, "CHAT_MSG_GUILD", f"m{i}", "Asker-Realm", ASKER)["id"]
        self.assertIsNone(s.lua.eval(f"WuxianKit.Chat.Message({first})".encode()))
        self.assertEqual(py(s.lua.eval(f"WuxianKit.Chat.Message({first + 1})".encode()))["plain"], "m1")
        self.assertEqual(py(s.lua.eval(f"WuxianKit.Chat.Message({last})".encode()))["plain"], "m200")

    def test_mentions(self):
        s = self.start()
        self.assertEqual(py(s.lua.eval(b"WuxianKit.Chat.Names()")), ["Wuxian Forever", "Wuxian", "Forever"])
        m = lambda text, event="CHAT_MSG_GUILD", guid=ASKER: self.say(s, event, text, "Asker-Realm", guid)["mention"]
        self.assertTrue(m("hey wuxian forever, you there?"))               # whole name, any case
        self.assertTrue(m("FOREVER can you help"))                         # a part
        for text in ("thanks Wuxian!", "wuxian's turn", "@forever", "(Forever)", "找wuxian帮忙", "Wuxian，在吗", "forever"):
            self.assertTrue(m(text), text)                                 # a whole word, whatever is around it
        for text in ("forevermore", "that takes forever2", "unforeverish", "wuxianwow.com is up", "xwuxian",
                     "4ever and foreverx"):
            self.assertFalse(m(text), text)                                # inside another Latin word: not the name
        self.assertTrue(m("foreverx, forever?"))                           # a later one that is a word
        self.assertFalse(m("nobody in particular"))
        self.assertFalse(m("Wuxian here", guid="Player-1-00000001"))       # the player's own
        self.assertTrue(m("psst", event="CHAT_MSG_WHISPER", guid=FRIEND))  # a whisper to the player
        self.assertFalse(m("on my way", event="CHAT_MSG_WHISPER_INFORM", guid=FRIEND))
        self.aliases(s, "'老王，Boss、 ,小王'")                               # a text, as 0.5 saved it
        self.assertEqual(py(s.lua.eval(b"WuxianKit.Chat.Names()")), ["Wuxian Forever", "Wuxian", "Forever", "老王", "Boss",
                                                                     "小王"])
        self.assertTrue(m("老王在吗"))
        self.assertTrue(m("ask the boss"))
        self.assertFalse(m("so bossy"))                                    # an alias with Latin letters: a whole word too
        self.assertTrue(m("叫老王来"))                                       # Chinese: anywhere
        self.aliases(s, "{ 'Bo', 'T1' }")                                   # the player's own: of any length
        self.assertTrue(m("bo, t1?"))
        self.assertFalse(m("bob and t10"))
        self.aliases(s, "'老王，Boss、 ,小王'")
        self.aliases(s, "{ '大佬' }")                                        # a list option's table
        self.assertEqual(py(s.lua.eval(b"WuxianKit.Chat.Names()"))[3:], ["大佬"])
        self.assertFalse(m("老王在吗"))
        self.assertTrue(s.lua.eval("WuxianKit.Chat.Mentions('|cffffffff|Hitem:1::|h[x]|h|r 大佬 帮忙')".encode()))
        self.assertTrue(s.lua.eval(b"WuxianKit.Chat:Mentions('wuxian?')"))      # with : too

    def test_a_two_part_name(self):
        s = self.start()
        s.lua.execute("GetUnitName = function(unit, whole) if unit == 'player' then return '看淡生死死后 依然从容施法' end end"
                      .encode())
        s.fire("PLAYER_LOGIN")
        self.assertEqual(py(s.lua.eval(b"WuxianKit.Chat.Names()")),
                         ["看淡生死死后 依然从容施法", "看淡生死死后", "依然从容施法"])
        m = lambda text: self.say(s, "CHAT_MSG_GUILD", text, "Asker-Realm", ASKER)["mention"]
        self.assertTrue(m("依然从容施法在不在"))
        self.assertFalse(m("依然从容"))
        s.lua.execute("GetUnitName = function(unit, whole) if unit == 'player' then return '王 依然' end end".encode())
        self.assertEqual(py(s.lua.eval(b"WuxianKit.Chat.Names()")), ["王 依然"])    # a part of one or two characters: no name
        self.assertFalse(m("他依然没来"))                                    # (a word of its own)
        self.assertFalse(m("王者归来"))
        self.assertTrue(m("王 依然在不在"))                                   # the whole name still is
        s.lua.execute("GetUnitName = function(unit, whole) if unit == 'player' then return 'Li 依然在' end end".encode())
        self.assertEqual(py(s.lua.eval(b"WuxianKit.Chat.Names()")), ["Li 依然在", "依然在"])
        self.assertFalse(m("lich king"))
        self.assertTrue(m("依然在吗"))
        s.lua.execute(b"GetUnitName = function() return '<secret>x' end")    # a secret name: none of it
        self.assertFalse(py(s.lua.eval(b"WuxianKit.Chat.Names()")))

    def test_read_api(self):
        s = self.start()
        item = "|cffffffff|Hitem:7166::::::::1:::::::|h[Copper Dagger]|h|r"
        msg = self.say(s, "CHAT_MSG_RAID_LEADER", f"Wuxian take {item}", "Lead-Realm", ASKER)
        self.assertEqual({k: msg.get(k) for k in ("channel", "plain", "sender", "guid", "mention", "self")},
                         {"channel": "raid", "plain": "Wuxian take [Copper Dagger]", "sender": "Lead", "guid": ASKER,
                          "mention": True, "self": None})
        self.assertIsNone(s.lua.eval(b"WuxianKit.Chat.Read('CHAT_MSG_SYSTEM', 'hi', 'x')"))
        self.assertIsNone(s.lua.eval(b"WuxianKit.Chat.Read('CHAT_MSG_GUILD', '<secret>hi', 'x')"))
        again = py(s.lua.eval(b"WuxianKit.Chat.Read('CHAT_MSG_GUILD', 'once', 'A-R', '', '', '', '', 0, 0, '', 1, 5, 'G')"))
        same = py(s.lua.eval(b"WuxianKit.Chat:Read('CHAT_MSG_GUILD', 'once', 'A-R', '', '', '', '', 0, 0, '', 1, 5, 'G')"))
        self.assertEqual(again["id"], same["id"])                          # the same line read twice: one message
        self.assertIsNone(s.lua.eval(b"WuxianKit.Chat.Message(999999)"))

    def test_reply_checked_and_its_scope(self):
        s = self.start()
        named = self.say(s, "CHAT_MSG_GUILD", "Wuxian, where is the bank?", "Asker-Realm", ASKER)["id"]
        plain = self.say(s, "CHAT_MSG_GUILD", "anyone around?", "Asker-Realm", ASKER)["id"]
        mine = self.say(s, "CHAT_MSG_GUILD", "Wuxian Forever here", "Wuxian-Realm", "Player-1-00000001")["id"]
        party = self.say(s, "CHAT_MSG_PARTY", "Wuxian pull?", "Tank-Realm", ASKER)["id"]
        whisper = self.say(s, "CHAT_MSG_WHISPER", "got a sec?", "Friend-Realm", FRIEND)["id"]
        self.assertIn("reply: no such message heard",
                      self.fails(s, "WuxianKit:Call('chat.send', { channel = 'guild', text = 'hi', reply = 424242 })"))
        self.assertEqual(s.lua.eval(b"WuxianKit:Check('chat.send', { channel = 'guild', text = 'hi', reply = 424242 })"),
                         b"reply: no such message heard (use the id of a chat.message)")

        def scope(args):
            p = self.call(s, "chat.send", args)
            click(s.g("WuxianKitProposal")[b"decline"])
            return p["steps"][0]["scope"], p["steps"][0]["preview"]

        sc, preview = scope(f"{{ channel = 'guild', text = 'by the inn', reply = {named} }}")
        self.assertEqual(sc, "chat.guild.reply")
        self.assertEqual(preview, ["Guild: by the inn", "|cff9c9ea6Reply to Asker|r"])
        self.assertEqual(scope("{ channel = 'guild', text = 'hello' }"), ("chat.guild", ["Guild: hello"]))
        self.assertEqual(scope(f"{{ channel = 'guild', text = 'hi', reply = {plain} }}")[0], "chat.guild")   # not a mention
        self.assertEqual(scope(f"{{ channel = 'guild', text = 'hi', reply = {mine} }}")[0], "chat.guild")    # the player's
        self.assertEqual(scope(f"{{ channel = 'guild', text = 'hi', reply = {party} }}")[0], "chat.guild")   # another channel
        self.assertEqual(scope(f"{{ channel = 'party', text = 'go', reply = {party} }}")[0], "chat.party.reply")
        self.assertEqual(scope(f"{{ channel = 'whisper', target = 'Friend', text = 'sure', reply = {whisper} }}")[0],
                         "chat.whisper.reply")
        self.assertEqual(scope(f"{{ channel = 'whisper', target = 'Friend-Realm', text = 'sure', reply = {whisper} }}")[0],
                         "chat.whisper.reply")
        self.assertEqual(scope(f"{{ channel = 'whisper', target = 'Someone', text = 'sure', reply = {whisper} }}")[0],
                         "chat.whisper")                                   # not back to its sender
        say = self.call(s, "chat.send", f"{{ channel = 'say', text = 'hi', reply = {named} }}")
        self.assertEqual(say["steps"][0]["scope"], "chat.send")            # say has no scope, reply or not
        click(s.g("WuxianKitProposal")[b"decline"])
        s.run(181)                                                         # too old to be a reply
        self.assertEqual(scope(f"{{ channel = 'guild', text = 'late', reply = {named} }}")[0], "chat.guild")

    def test_a_stale_reply_is_refused_with_the_latest(self):
        s = self.start()
        q = self.say(s, "CHAT_MSG_GUILD", "Wuxian, where is the bank?", "Asker-Realm", ASKER)["id"]
        self.say(s, "CHAT_MSG_GUILD", "Wuxian Forever here", "Wuxian-Realm", "Player-1-00000001")   # the player's: not counted
        self.say(s, "CHAT_MSG_PARTY", "pull now", "Tank-Realm", FRIEND)                            # another channel
        self.say(s, "CHAT_MSG_WHISPER", "hey", "Friend-Realm", FRIEND)
        self.say(s, "CHAT_MSG_GUILD", "|TInterface/TargetingFrame/UI-RaidTargetingIcon_1:0|t found it|A:raidicon:0:0|a", "Asker-Realm", ASKER)
        p = self.call(s, "chat.send", f"{{ channel = 'guild', text = 'by the inn', reply = {q}, stale = 2 }}")
        self.assertEqual(p["steps"][0]["scope"], "chat.guild.reply")      # one line after it: still fresh
        click(s.g("WuxianKitProposal")[b"decline"])
        last = self.say(s, "CHAT_MSG_GUILD", "anyone for a dungeon?", "Other-Realm", FRIEND)["id"]
        why = s.lua.eval(f"WuxianKit:Check('chat.send', {{ channel = 'guild', text = 'x', reply = {q}, stale = 2 }})".encode())
        self.assertEqual(why.decode(), f"stale: 2 messages came after #{q}; the latest: #{last - 1} Asker: found it / "
                                       f"#{last} Other: anyone for a dungeon?")
        self.assertIn("stale: 2 messages", self.fails(
            s, f"WuxianKit:Call('chat.send', {{ channel = 'guild', text = 'x', reply = {q}, stale = 2 }})"))
        self.assertEqual(self.call(s, "chat.send", f"{{ channel = 'guild', text = 'x', reply = {q}, stale = 3 }}")
                         ["steps"][0]["scope"], "chat.guild.reply")       # a higher bar: still goes
        click(s.g("WuxianKitProposal")[b"decline"])
        self.assertEqual(self.call(s, "chat.send", f"{{ channel = 'guild', text = 'x', reply = {q} }}")
                         ["steps"][0]["scope"], "chat.guild.reply")       # no stale: no bar
        click(s.g("WuxianKitProposal")[b"decline"])
        self.assertEqual(s.lua.eval(b"WuxianKit:Check('chat.send', { channel = 'guild', text = 'x', stale = 2 })"),
                         b"stale goes with reply")
        self.assertEqual(s.lua.eval(f"WuxianKit:Check('chat.send', {{ channel = 'guild', text = 'x', reply = {q}, stale = 0.5 }})"
                                    .encode()), b"stale is a whole number, 1 or more")

    def test_waits_while_the_player_types_or_just_spoke(self):
        s = self.start(saved={"WuxianKitDB": b"{ grants = { ['chat.guild'] = true } }"})
        s.lua.execute(b"__box = CreateFrame('EditBox') __box.focus = true "
                      b"ChatEdit_GetActiveWindow = function() return __box end")
        p = self.call(s, "chat.send", "{ channel = 'guild', text = 'auto' }")
        self.assertEqual(p["state"], "waiting")                            # pre-approved, but the player types
        self.assertEqual(py(s.g("__sent")), {})
        s.lua.execute(b"__box.focus = false")
        s.run(1.5)
        self.assertEqual(py(s.g("__sent"))[-1]["text"], "auto")
        self.say(s, "CHAT_MSG_GUILD", "I'll do it", "Wuxian-Realm", "Player-1-00000001")   # the player's own words
        p = self.call(s, "chat.send", "{ channel = 'guild', text = 'second' }")
        self.assertEqual(p["state"], "waiting")
        s.run(5)
        self.assertEqual(len(py(s.g("__sent"))), 1)
        s.run(4)                                                           # eight seconds after the player spoke
        self.assertEqual(py(s.g("__sent"))[-1]["text"], "second")
        self.say(s, "CHAT_MSG_PARTY", "brb", "Wuxian-Realm", "Player-1-00000001")    # another channel: guild goes
        p = self.call(s, "chat.send", "{ channel = 'guild', text = 'third' }")
        self.assertEqual(p["state"], "done")

    def test_the_window_says_why_and_yield_off(self):
        s = self.start()
        s.lua.execute(b"__box = CreateFrame('EditBox') __box.focus = true "
                      b"ChatEdit_GetActiveWindow = function() return __box end")
        self.call(s, "chat.send", "{ channel = 'whisper', target = 'Friend', text = 'later' }")
        w = s.g("WuxianKitProposal")
        self.assertFalse(w[b"run"][b"enabled"])
        self.assertIn("Not available: Waiting for you to finish", "\n".join(texts(w)))
        s.lua.execute(b"__box:Hide()")                                     # a focused box that is hidden: not typing
        s.run(1.1)
        self.assertTrue(w[b"run"][b"enabled"])
        click(w[b"run"])
        self.assertEqual(py(s.g("__sent"))[-1]["text"], "later")
        s.lua.execute(b"WuxianKitDB.ext.chat.options = { yield = false } __box:Show() "
                      b"ChatEdit_GetActiveWindow = function() error('broken') end")
        self.call(s, "chat.send", "{ channel = 'guild', text = 'now' }")
        s.run(1.1)
        self.assertTrue(w[b"run"][b"enabled"])
        s.lua.execute(b"WuxianKitDB.ext.chat.options = { yield = true }")  # a box that breaks is no typing either
        s.run(1.1)
        self.assertTrue(w[b"run"][b"enabled"])
        s.lua.execute(b"__lockdown = true")                                # chat lockdown is waited out as before
        s.run(1.1)
        self.assertFalse(w[b"run"][b"enabled"])
        self.assertIn("Not available: Chat is restricted", "\n".join(texts(w)))


if __name__ == "__main__":
    unittest.main()
