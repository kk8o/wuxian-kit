"""聊天 (Chat) 0.6 under Lua 5.1 in the mock client (ARCHITECTURE section 12): a chat.message's why (mention, followup,
question, burst; per conversation: whisper partner, numbered channel; none for the player's own; counted once for a
line read twice), WuxianKit.Chat:On / Off without an app (an app that hears chat gets a copy of the same message), and
ids from the core's one counter, going on from 0.5's chat.db.lastId (and 0.5's chat.listen state gone)."""
import unittest

from kitmock import Session, lupa, py

ME, ASKER, OTHER, FRIEND = "Player-1-00000001", "Player-1-00000002", "Player-1-00000003", "Player-1-00000004"


@unittest.skipIf(lupa is None, "lupa (Lua 5.1 for Python) is not installed")
class Chat06(unittest.TestCase):
    line = 5000

    def start(self, **kw):
        s = Session(self, **kw)
        s.lua.execute(b"__events = {} WuxianKit:On('*', function(topic, data) "
                      b"__events[#__events + 1] = { topic = topic, data = data } end)")
        s.login()
        s.run(1)
        self.addCleanup(lambda: self.assertEqual(s.errors(), []))
        return s

    def args(self, text, sender, guid, base="", line=None):
        if line is None:
            Chat06.line += 1
            line = Chat06.line
        name = f"1. {base}" if base else ""
        return (text, sender, "", name, "", "", 0, 1 if base else 0, base, 1, line, guid)

    def read(self, s, event, *args):
        enc = [a.encode() if isinstance(a, str) else a for a in args]
        return py(s.lua.eval(b"function(...) return WuxianKit.Chat.Read(...) end")(event.encode(), *enc))

    def say(self, s, event, text, sender, guid, base=""):
        """the client's chat event (its own line id), then what WuxianKit.Chat.Read makes of it"""
        args = self.args(text, sender, guid, base)
        s.fire(event, *args)
        return self.read(s, event, *args)

    def why(self, s, text, sender="Asker-Realm", guid=ASKER, event="CHAT_MSG_GUILD", base=""):
        return self.say(s, event, text, sender, guid, base).get("why")

    def mine(self, s, text, event="CHAT_MSG_GUILD", base=""):
        return self.say(s, event, text, "Wuxian-Realm", ME, base)

    # -- why ----------------------------------------------------------------------------------------------------------

    def test_mention_and_the_players_own(self):
        s = self.start()
        self.assertEqual(self.why(s, "wuxian, you there?"), "mention")       # before question
        self.assertEqual(self.why(s, "psst", "Friend-Realm", FRIEND, "CHAT_MSG_WHISPER"), "mention")
        own = self.mine(s, "Wuxian Forever: anyone know how?")
        self.assertIsNone(own.get("why"))                                    # a name and a question: still none
        self.assertIsNone(self.say(s, "CHAT_MSG_WHISPER_INFORM", "on my way?", "Friend-Realm", FRIEND).get("why"))

    def test_followup_within_90_seconds_of_the_players_line(self):
        s = self.start()
        self.assertIsNone(self.why(s, "hello all"))
        self.mine(s, "anyone up for a run")
        self.assertEqual(self.why(s, "sure"), "followup")
        s.run(60)
        self.mine(s, "great")                                                # each own line starts it again
        s.run(60)
        self.assertEqual(self.why(s, "me too", "Other-Realm", OTHER), "followup")
        self.assertIsNone(self.why(s, "pull now", event="CHAT_MSG_PARTY"))  # another conversation
        s.run(31)                                                            # 91 s after the player's line
        self.assertIsNone(self.why(s, "late"))

    def test_whispers_are_per_partner(self):
        s = self.start()
        self.assertIsNone(self.say(s, "CHAT_MSG_WHISPER_INFORM", "you there", "Friend-Realm", FRIEND).get("why"))
        self.assertEqual(self.why(s, "yes", "Friend-Realm", FRIEND, "CHAT_MSG_WHISPER"), "mention")
        self.assertIsNone(self.why(s, "ok", "Friend-Realm", FRIEND))         # guild: not the whisper's conversation
        self.assertEqual(self.why(s, "hi", "Stranger-Realm", OTHER, "CHAT_MSG_WHISPER"), "mention")
        # the conversations themselves: the whisper partner is the target, own and theirs alike
        inform = self.say(s, "CHAT_MSG_WHISPER_INFORM", "again", "Friend-Realm", FRIEND)
        back = self.say(s, "CHAT_MSG_WHISPER", "back", "Friend-Realm", FRIEND)
        other = self.say(s, "CHAT_MSG_WHISPER", "and me", "Stranger-Realm", OTHER)
        self.assertEqual([inform["target"], back["target"], other["target"]], ["Friend", "Friend", "Stranger"])

    def test_numbered_channels_are_per_channel(self):
        s = self.start()
        self.mine(s, "lf healer", event="CHAT_MSG_CHANNEL", base="General")
        self.assertEqual(self.why(s, "me", event="CHAT_MSG_CHANNEL", base="General"), "followup")
        self.assertIsNone(self.why(s, "me", event="CHAT_MSG_CHANNEL", base="Trade"))
        self.assertIsNone(self.why(s, "me", event="CHAT_MSG_COMMUNITIES_CHANNEL", base="General"))   # a community
        self.assertIsNone(self.why(s, "me"))                                 # guild

    def test_question(self):
        s = self.start()
        q = lambda text: self.why(s, text, "Asker-Realm", ASKER, "CHAT_MSG_PARTY")
        for text in ("怎么去暴风城", "好了吗", "谁有铜矿", "where is the bank", "How do I get there", "anyone know a tank",
                     "what's up", "bank open?", "银行在哪？"):
            self.assertEqual(q(text), "question", text)
        for text in ("a?", "吗", "求组 怎么打", "缺坦克，有没有", "WTS ore, who?", "lfg anyone?", "selling ore?",
                     "show me the way", "somewhat's odd", "收铜矿 有吗"):
            self.assertIsNone(q(text), text)

    def test_burst_at_most_once_in_45_seconds(self):
        s = self.start()
        w = lambda text, who: self.why(s, text, f"{who}-Realm", ASKER if who == "A" else OTHER)
        self.assertEqual([w("hi all", "A"), w("yo", "B")], [None, None])
        self.assertEqual(w("sup", "A"), "burst")
        s.run(5)
        self.assertIsNone(w("nm", "B"))                                     # 45 s have not passed
        self.assertEqual(self.why(s, "a", "A-Realm", ASKER, "CHAT_MSG_RAID"), None)
        self.assertEqual(self.why(s, "b", "B-Realm", OTHER, "CHAT_MSG_RAID"), None)
        self.assertEqual(self.why(s, "c", "A-Realm", ASKER, "CHAT_MSG_RAID"), "burst")   # its own conversation
        s.run(45)
        self.assertEqual([w("ok", "A"), w("fine", "B")], [None, None])      # the older lines are past 20 s
        self.assertEqual(w("cool", "A"), "burst")
        s.run(50)
        self.assertEqual([w("x", "A"), w("y", "A"), w("z", "A")], [None, None, None])   # one person is no burst

    def test_a_line_read_twice_counts_once(self):
        s = self.start()
        args = self.args("hey", "A-Realm", ASKER)
        s.fire("CHAT_MSG_GUILD", *args)
        first = self.read(s, "CHAT_MSG_GUILD", *args)
        again = self.read(s, "CHAT_MSG_GUILD", *args)
        self.assertEqual((first["id"], first.get("why")), (again["id"], again.get("why")))
        self.assertTrue(s.lua.eval(("rawequal(WuxianKit.Chat.Message(%d), WuxianKit.Chat.Message(%d))"
                                    % (first["id"], again["id"])).encode()))
        self.assertIsNone(self.why(s, "yo", "B-Realm", OTHER))               # two lines, not three
        self.assertEqual(self.why(s, "sup", "A-Realm", ASKER), "burst")
        mine = self.args("brb", "Wuxian-Realm", ME)
        self.read(s, "CHAT_MSG_GUILD", *mine)
        s.run(80)
        self.read(s, "CHAT_MSG_GUILD", *mine)                                # read again: no new 90 s
        s.run(11)
        self.assertIsNone(self.why(s, "back", "B-Realm", OTHER))           # 91 s after the line itself

    # -- Chat:On / Off --------------------------------------------------------------------------------------------------

    def subscribe(self, s, channel, name):
        s.lua.execute(f"{name} = {{}} __tok_{name} = WuxianKit.Chat:On({channel!r}, function(msg) "
                      f"{name}[#{name} + 1] = msg end)".encode())

    def test_on_and_off_without_listen(self):
        s = self.start()
        self.subscribe(s, "guild", "__g")
        self.subscribe(s, "*", "__all")
        s.lua.execute(b"__dot = {} __tok_dot = WuxianKit.Chat.On('party', function(msg) __dot[#__dot + 1] = msg end)")
        s.fire("CHAT_MSG_GUILD", *self.args("Wuxian, help?", "A-Realm", ASKER))
        s.fire("CHAT_MSG_PARTY", *self.args("pull", "B-Realm", OTHER))
        g, every, dot = py(s.g("__g")), py(s.g("__all")), py(s.g("__dot"))
        self.assertEqual([(m["channel"], m["plain"], m.get("why")) for m in g], [("guild", "Wuxian, help?", "mention")])
        self.assertEqual([m["channel"] for m in every], ["guild", "party"])
        self.assertEqual([m["plain"] for m in dot], ["pull"])
        self.assertEqual(every[1]["id"], every[0]["id"] + 1)
        self.assertTrue(s.lua.eval(b"rawequal(__g[1], __all[1]) and rawequal(__g[1], WuxianKit.Chat.Message(__g[1].id))"))
        self.assertEqual(self.heard(s), [])                                  # no app heard it
        s.lua.execute(b"WuxianKit.Chat:Off(__tok___g) WuxianKit.Chat.Off(__tok_dot) WuxianKit.Chat:Off(nil)")
        s.fire("CHAT_MSG_GUILD", *self.args("again", "A-Realm", ASKER))
        s.fire("CHAT_MSG_PARTY", *self.args("again", "B-Realm", OTHER))
        self.assertEqual((len(py(s.g("__g"))), len(py(s.g("__dot"))), len(py(s.g("__all")))), (1, 1, 4))

    def test_once_and_a_copy_for_an_app(self):
        s = self.start()
        s.lua.execute(b"__answer = WuxianKit:Call('kit.app.open', { app = 'ear', hear = { 'chat:guild' }, lease = 0 })")
        self.subscribe(s, "guild", "__g")
        args = self.args("one", "A-Realm", ASKER)
        s.fire("CHAT_MSG_GUILD", *args)
        msg = self.read(s, "CHAT_MSG_GUILD", *args)                         # another addon reads it too
        g = py(s.g("__g"))
        self.assertEqual([m["id"] for m in g], [msg["id"]])                 # told once
        [item] = self.heard(s)
        self.assertEqual((item["id"], item["source"], item["plain"]), (msg["id"], "chat", "one"))
        self.assertIsNone(s.lua.eval(b"__g[1].source"))                     # the shared message is left alone
        self.assertTrue(s.lua.eval(b"(function() for _, e in ipairs(__events) do if e.topic == 'app.ear' then "
                                   b"return not rawequal(e.data.items[1], __g[1]) end end end)()"))

    def test_off_while_the_extension_is_off_and_errors(self):
        s = self.start()
        self.subscribe(s, "*", "__all")
        s.lua.execute(b"WuxianKit.Chat:On('guild', function() error('boom') end)")
        self.subscribe(s, "guild", "__after")
        s.fire("CHAT_MSG_GUILD", *self.args("hi", "A-Realm", ASKER))
        self.assertEqual(len(py(s.g("__after"))), 1)                        # an error stops no one else
        self.assertEqual(len(s.errors()), 1)
        self.assertIn("boom", s.errors()[0])
        s.lua.execute(b"__errors = {}")
        s.ns[b"Disable"](s.ns[b"extensions"][b"chat"])
        args = self.args("off now", "A-Realm", ASKER)
        s.fire("CHAT_MSG_GUILD", *args)
        self.assertIsNotNone(self.read(s, "CHAT_MSG_GUILD", *args))          # Read still works
        self.assertEqual(len(py(s.g("__all"))), 1)                          # but nobody is told
        for bad in ("WuxianKit.Chat:On('nope', print)", "WuxianKit.Chat:On('guild')", "WuxianKit.Chat.On(1, print)"):
            ok, err = s.lua.eval(f"pcall(function() {bad} end)".encode())
            self.assertFalse(ok, bad)
            self.assertIn(b"channel is", err)

    def heard(self, s):
        """the items of the app ear's wakes (kit.app.open { app = 'ear', hear = ... }: no digest, one each)"""
        return [i for e in py(s.g("__events")) or [] if e["topic"] == "app.ear" for i in e["data"]["items"]]

    # -- ids --------------------------------------------------------------------------------------------------------------

    def test_ids_from_the_core_counter(self):
        s = self.start()
        a = s.lua.eval(b"WuxianKit:NewId()")
        m = self.say(s, "CHAT_MSG_GUILD", "one", "A-Realm", ASKER)
        b = s.lua.eval(b"WuxianKit:NewId()")
        self.assertEqual((m["id"], b), (a + 1, a + 2))
        self.assertEqual(s.lua.eval(b"WuxianKitDB.lastId"), b)
        self.assertIsNone(s.lua.eval(b"WuxianKit.Chat.NewId"))              # gone in 0.6
        self.assertIsNone(s.lua.eval(b"WuxianKitDB.ext.chat.lastId"))

    def test_the_counter_goes_on_from_an_old_chat_counter(self):
        s = self.start(saved={"WuxianKitDB": b"{ ext = { chat = { lastId = 777, feeds = { listen = { ends = 1 } }, "
                                             b"recent = { listen = { n = 700, items = {} } } } } }"})
        self.assertEqual(self.say(s, "CHAT_MSG_GUILD", "one", "A-Realm", ASKER)["id"], 778)
        self.assertIsNone(s.lua.eval(b"WuxianKitDB.ext.chat.lastId"))       # once: then it is gone
        self.assertIsNone(s.lua.eval(b"WuxianKitDB.ext.chat.feeds or WuxianKitDB.ext.chat.recent"))   # 0.5's listen
        s2 = s.reload()
        s2.login()
        self.addCleanup(lambda: self.assertEqual(s2.errors(), []))
        self.assertEqual(s2.lua.eval(b"WuxianKit:NewId()"), 779)
        s3 = self.start(saved={"WuxianKitDB": b"{ lastId = 900, ext = { chat = { lastId = 777 } } }"})
        self.assertEqual(self.say(s3, "CHAT_MSG_GUILD", "one", "A-Realm", ASKER)["id"], 901)   # the higher one
        s4 = self.start(saved={"WuxianKitDB": b"{ off = { chat = true }, ext = { chat = { lastId = 50 } } }"})
        self.assertEqual(s4.lua.eval(b"WuxianKit:NewId()"), 51)              # the extension off: still counted


if __name__ == "__main__":
    unittest.main()
