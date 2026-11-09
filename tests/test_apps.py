"""Apps (ARCHITECTURE section 10): an agent's declaration (kit.app.open, checked, remembered, at most 8) and an addon's
(WuxianKit:App, with check, urgent, enrich: it wins); status, the heartbeat and the lease, stop, recent, kit.apps; runs
through reloads and per character; the sources (chat, game, bus, addon, control, player) with fakes of Chat:On and
Game:On; digest, urgent lists, controls and the player's words; said; the extension an app belongs to; options; the
manifest's apps. Pace and quiet hours are in test_apps_pace.py."""
import unittest

from kitmock import Session, lupa, py
from test_standalone import bridge

# the start line (启动语) of an app with a prompt, as the contract gives it
START = {"en": 'Start the 无限工坊 app "{}": first call the 无限工坊 MCP tool wk_docs with {{"skill": "{}"}} and follow the steps it '
               'gives.',
         "zh": '开始无限工坊的应用「{}」：先调用无限工坊 MCP 的工具 wk_docs，参数 {{"skill": "{}"}}，照读到的步骤做。'}

# Chat:On and Game:On as K4 and K1 give them, faked: __say(channel, msg) and __moment(kind, topic, data) hand a message
# or a moment to whoever subscribed (a fresh copy of the moment to each, the same message table to all)
FAKES = b"""
__chatsubs, __gamesubs = {}, {}
local n = 0
WuxianKit.Chat.On = function(self, ch, fn) n = n + 1 __chatsubs[n] = { ch = ch, fn = fn } return n end
WuxianKit.Chat.Off = function(self, t) __chatsubs[t] = nil end
WuxianKit.Game.On = function(self, what, fn) n = n + 1 __gamesubs[n] = { what = what, fn = fn } return n end
WuxianKit.Game.Off = function(self, t) __gamesubs[t] = nil end
function __say(ch, msg)
	msg.channel = msg.channel or ch
	msg.id = msg.id or WuxianKit:NewId()
	msg.time = msg.time or time()
	for _, s in pairs(__chatsubs) do if s.ch == ch or s.ch == '*' then s.fn(msg) end end
	return msg
end
function __moment(kind, topic, data)
	for _, s in pairs(__gamesubs) do
		if s.what == kind or s.what == topic or s.what == '*' then
			s.fn({ kind = kind, topic = topic, time = time(), data = data })
		end
	end
end
function __count(t) local c = 0 for _ in pairs(t) do c = c + 1 end return c end
__events = {}
WuxianKit:On('*', function(topic, data) __events[#__events + 1] = { topic = topic, data = data } end)
"""


@unittest.skipIf(lupa is None, "lupa (Lua 5.1 for Python) is not installed")
class AppCase(unittest.TestCase):
    def start(self, s=None, guid=None, **kw):
        if s is None:
            kw.setdefault("saved", {"WoWBridge": bridge("0.9.7")})
            s = Session(self, **kw)
        if guid:
            s.lua.execute(f"__guid = {guid!r}".encode())
        s.lua.execute(FAKES)
        s.login()
        s.run(1)
        self.addCleanup(lambda: self.assertEqual(s.errors(), []))
        return s

    def agent(self, s, cap, args="{}"):
        """an agent's call through WoWBridge (source agent)"""
        s.lua.execute(f"__r = __fns[{cap!r}]({args})".encode())
        return py(s.g("__r"))

    def fails(self, s, cap, args="{}"):
        ok, err = s.lua.eval(f"pcall(__fns[{cap!r}], {args})".encode())
        self.assertFalse(ok, args)
        return err.decode()

    def call(self, s, cap, args="{}"):
        """an addon's call (no source)"""
        s.lua.execute(f"__r = WuxianKit:Call({cap!r}, {args})".encode())
        return py(s.g("__r"))

    def events(self, s, topic):
        return [e["data"] for e in py(s.g("__events")) or [] if e["topic"] == topic]

    def wakes(self, s, app):
        return self.events(s, "app." + app)

    def lua(self, s, code):
        return py(s.lua.eval(code.encode() if isinstance(code, str) else code))


class Basics(AppCase):
    def test_open_status_recent_stop(self):
        s = self.start()
        now = s.lua.eval(b"time()")
        st = self.agent(s, "kit.app.open", "{ app = 'notes', title = 'Notes', hear = { 'bus:demo.*' } }")
        self.assertEqual((st["app"], st["title"], st["by"], st["on"], st["lease"], st["hear"], st["seen"], st["present"]),
                         ("notes", "Notes", "agent", True, 600, ["bus:demo.*"], now, True))
        self.assertEqual(st["ends"], now + 7200)
        self.assertEqual((st["heard"], st["wakes"], st["said"], st["next"]), (0, 0, 0, 0))
        self.assertNotIn("pace", st)
        self.assertEqual(self.events(s, "kit.app"), [{"app": "notes", "on": True, "ends": now + 7200}])
        self.assertIn("Notes: started, until", s.chat())

        s.lua.execute(b"WuxianKit:Emit('demo.x', { n = 1 }) WuxianKit:Emit('other.y', { n = 2 })")
        w = self.wakes(s, "notes")
        self.assertEqual(len(w), 1)
        item = w[0]["items"][0]
        self.assertEqual((w[0]["app"], w[0]["reason"], w[0]["skipped"]), ("notes", "item", 0))
        self.assertEqual((item["source"], item["topic"], item["data"], item["time"]), ("bus", "demo.x", {"n": 1}, now))
        first = item["id"]
        s.lua.execute(b"WuxianKit:Emit('demo.y', 'two')")
        self.assertEqual(self.wakes(s, "notes")[1]["items"][0]["id"], first + 1)

        recent = self.agent(s, "kit.app.recent", "{ app = 'notes' }")
        self.assertEqual([i["topic"] for i in recent["items"]], ["demo.x", "demo.y"])
        self.assertEqual(recent["next"], first + 1)
        self.assertEqual(self.agent(s, "kit.app.recent", f"{{ app = 'notes', since = {first} }}")["items"][0]["data"],
                         "two")
        self.assertEqual(self.agent(s, "kit.app.recent", f"{{ app = 'notes', since = {first + 1} }}")["items"], {})
        st = self.agent(s, "kit.app.status", "{ app = 'notes' }")
        self.assertEqual((st["heard"], st["wakes"], st["next"]), (2, 2, first + 1))
        apps = self.agent(s, "kit.apps")
        self.assertEqual([a["id"] for a in apps], ["guild", "notes"])     # the kit's own guild chat first
        self.assertEqual(apps[1], {"id": "notes", "title": "Notes", "by": "agent", "on": True, "ends": now + 7200,
                                   "present": True})

        st = self.agent(s, "kit.app.stop", "{ app = 'notes' }")
        self.assertEqual((st["on"], st["present"], st["why"]), (False, False, "stopped"))
        self.assertEqual(self.events(s, "kit.app")[-1], {"app": "notes", "on": False, "why": "stopped"})
        self.assertIn("Notes: stopped", s.chat())
        s.lua.execute(b"WuxianKit:Emit('demo.z', 3)")
        self.assertEqual(len(self.wakes(s, "notes")), 2)                 # unsubscribed
        self.assertEqual(len(self.agent(s, "kit.app.recent", "{ app = 'notes' }")["items"]), 2)   # the ring stays

        st = self.agent(s, "kit.app.open", "{ app = 'notes', minutes = 5 }")   # remembered: just the id
        self.assertEqual((st["on"], st["ends"], st["title"]), (True, now + 300, "Notes"))
        self.assertNotIn("why", st)

    def test_reopen_goes_on_and_a_new_declaration_replaces(self):
        s = self.start()
        decl = "{ app = 'r', hear = { 'bus:demo.*' }, digest = { every = false } }"
        self.agent(s, "kit.app.open", decl)
        s.lua.execute(b"WuxianKit:Emit('demo.a', 1)")
        s.run(10)
        st = self.agent(s, "kit.app.open", "{ app = 'r', minutes = 30 }")  # goes on: on again, no stop
        self.assertEqual((st["heard"], st["ends"]), (1, s.lua.eval(b"time()") + 1800))
        st = self.agent(s, "kit.app.open", decl)                         # the same declaration: goes on too
        self.assertEqual(st["heard"], 1)
        self.assertEqual([e["on"] for e in self.events(s, "kit.app")], [True, True, True])
        st = self.agent(s, "kit.app.open", "{ app = 'r', hear = { 'bus:other.*' } }")   # changed: replaced
        self.assertEqual(st["heard"], 0)
        self.assertEqual(self.events(s, "kit.app")[-2:], [{"app": "r", "on": False, "why": "replaced"},
                                                          {"app": "r", "on": True, "ends": st["ends"]}])
        s.lua.execute(b"WuxianKit:Emit('demo.b', 2) WuxianKit:Emit('other.c', 3)")
        self.assertEqual(self.agent(s, "kit.app.status", "{ app = 'r' }")["heard"], 1)

    def test_validation(self):
        s = self.start()
        long_title = "x" * 49
        for args, why in (
                ("{ app = 'Bad', title = 'x' }", "lowercase letters"),
                ("{ app = string.rep('a', 25), title = 'x' }", "at most 24 bytes"),
                (f"{{ app = 'a', title = '{long_title}' }}", "title is at most 48 bytes"),
                ("{ app = 'a', hear = { 'chat:nope' } }", "chat:nope: a chat channel is"),
                ("{ app = 'a', hear = { 'bus:kit.proposal' } }", "cannot hear kit.* or app.*"),
                ("{ app = 'a', hear = { 'bus:app.other' } }", "cannot hear kit.* or app.*"),
                ("{ app = 'a', hear = { 'bus:*' } }", "a bus source is a topic"),
                ("{ app = 'a', hear = { 'game:nope' } }", "game:nope: a game source is a topic"),
                ("{ app = 'a', hear = { 'radio:x' } }", "a hear entry is chat:<channel>"),
                ("{ app = 'a', hear = 'chat:guild' }", "is a table"),
                ("{ app = 'a', controls = { 'dance' } }", "controls: dance is not one of"),
                ("{ app = 'a', urgent = { 'Big Deal' } }", "is not a word"),
                ("{ app = 'a', pace = { fast = {} } }", "pace: no field fast"),
                ("{ app = 'a', pace = { normal = { every = 0 } } }", "pace.normal.every is a number of at least 1"),
                ("{ app = 'a', digest = { soon = 1 } }", "digest: no field soon"),
                ("{ app = 'a', pace = true, options = { quiet = { kind = 'text' } } }", "the core's own option"),
                ("{ app = 'a', options = { x = { kind = 'weird' } } }", "options.x.kind is boolean"),
                ("{ app = 'a', options = { x = { kind = 'choice' } } }", "options.x.choices is a list"),
                ("{ app = 'a', options = { x = { kind = 'number', default = 'two' } } }", "does not fit"),
                ("{ app = 'a', options = { a = {}, b = {}, c = {}, d = {}, e = {}, f = {}, g = {}, h = {}, i = {} } }",
                 "at most 8 options"),
                ("{ app = 'a', color = 'red' }", "no argument color"),
                ("{ app = 'a', minutes = -1, title = 'x' }", "minutes is a number of minutes"),
                ("{ app = 'ghost' }", "no app ghost: the first kit.app.open"),
        ):
            self.assertIn(why, self.fails(s, "kit.app.open", args), args)
        self.assertIn("no app ghost (kit.apps lists them)", self.fails(s, "kit.app.status", "{ app = 'ghost' }"))
        self.assertEqual([a["id"] for a in self.agent(s, "kit.apps")], ["guild"])   # nothing kept of a refused one
        self.assertIsNone(s.lua.eval(b"WuxianKitDB.apps.a"))

        st = self.agent(s, "kit.app.open", "{ app = 'a', hear = { 'game:quest', 'game:quest.turnin', 'chat:*', "
                                           "'chat:guild', 'game:combat', 'bus:x.y', 'bus:x.y' }, lease = 10, minutes = 9999 }")
        self.assertEqual(st["hear"], ["game:quest", "chat:*", "game:combat", "bus:x.y"])   # covered ones go
        self.assertEqual(st["lease"], 60)                                  # at least 60
        self.assertEqual(st["ends"] - s.lua.eval(b"time()"), 720 * 60)      # at most 720 minutes
        self.assertEqual(self.agent(s, "kit.app.open", "{ app = 'b', hear = { 'game:*' }, lease = 0 }")["lease"], 0)
        for i in range(6):
            self.agent(s, "kit.app.open", f"{{ app = 'n{i}', title = 'N{i}' }}")
        self.assertIn("at most 8 apps an agent declared", self.fails(s, "kit.app.open", "{ app = 'ninth', title = '9' }"))
        self.agent(s, "kit.app.open", "{ app = 'n0', title = 'again' }")     # a known one may be declared again

        ok, err = s.lua.eval(b"pcall(WuxianKit.App, WuxianKit, 'Nope', {})")
        self.assertFalse(ok)
        self.assertIn(b"WuxianKit:App(Nope, decl)", err)
        ok, err = s.lua.eval(b"pcall(WuxianKit.App, WuxianKit, 'fine', { hear = { 'bus:kit.ready' } })")
        self.assertIn(b"cannot hear kit.*", err)

    def test_agent_texts_kept_raw(self):
        s = self.start()
        st = self.agent(s, "kit.app.open", "{ app = 't', title = '|cffff0000Red|r', options = { o = { kind = 'choice', "
                                           "title = 'Pick|n', choices = { { value = 'a', label = '|TAny|t' }, { value = 'b' } } } } }")
        self.assertEqual(st["title"], "|cffff0000Red|r")                   # whoever draws it escapes it
        options = py(s.ns.AppOptionList(b"t"))
        self.assertEqual(options["o"]["title"], "Pick|n")
        self.assertEqual(options["o"]["choices"], [{"value": "a", "label": "|TAny|t"}, {"value": "b", "label": "b"}])
        self.assertIn("||cffff0000Red||r: started", s.chat())             # the chat line escapes it


class Declarations(AppCase):
    ADDON = b"""
__inguild = true
__app = WuxianKit:App('club', { title = 'Club chat', addon = 'WxClub', prompt = 'club-chat',
	hear = { 'chat:guild', 'game:guild' }, digest = { gather = 2, every = false }, controls = { 'stop' },
	check = function() if not __inguild then return 'not in a guild' end end,
	urgent = function(item) return item.kind == 'guild.join' or item.why == 'mention' end,
	enrich = function(item) if item.kind == 'guild.join' then item.recruited = true end end })
"""

    def test_an_addons_declaration_wins(self):
        s = self.start()
        self.agent(s, "kit.app.open", "{ app = 'club', title = 'Mine', hear = { 'bus:x.*' } }")
        self.assertIsNotNone(s.lua.eval(b"WuxianKitDB.apps.club.decl"))
        s.lua.execute(self.ADDON)
        self.assertIsNone(s.lua.eval(b"WuxianKitDB.apps.club.decl"))      # the agent's gives way
        self.assertEqual(self.events(s, "kit.app")[-1]["on"], True)        # its run goes on, the addon's now
        st = self.agent(s, "kit.app.open", "{ app = 'club', title = 'Other', hear = { 'bus:y' }, lease = 120 }")
        self.assertEqual((st["title"], st["by"], st["hear"], st["lease"], st["ignored"]),
                         ("Club chat", "addon", ["chat:guild", "game:guild"], 120, ["hear", "title"]))
        self.assertEqual(self.agent(s, "kit.apps")[1], {"id": "club", "title": "Club chat", "by": "addon",
                                                        "addon": "WxClub", "on": True, "ends": st["ends"],
                                                        "present": True, "prompt": "club-chat",
                                                        "start": START["en"].format("Club chat", "club-chat")})
        self.assertIs(s.lua.eval(b"WuxianKit:App('club') == __app"), True)
        self.assertIsNone(s.lua.eval(b"WuxianKit:App('none')"))

        s.lua.execute(b"__moment('guild.join', 'guild', { name = 'Newbie' })")   # urgent (its function), enriched
        s.lua.execute(b"__say('guild', { plain = 'hello', sender = 'A' })")
        s.run(3.5)
        w = self.wakes(s, "club")
        self.assertEqual([x["reason"] for x in w], ["urgent"])
        join, line = w[0]["items"]
        self.assertEqual((join["source"], join["kind"], join["topic"], join["data"], join["recruited"]),
                         ("game", "guild.join", "guild", {"name": "Newbie"}, True))
        self.assertNotIn("me", join)
        self.assertEqual((line["source"], line["plain"], line["channel"]), ("chat", "hello", "guild"))

        self.agent(s, "kit.app.stop", "{ app = 'club' }")
        s.lua.execute(b"__inguild = false")
        st = self.agent(s, "kit.app.open", "{ app = 'club' }")                 # an answer, not an error (no red notice)
        self.assertEqual((st["on"], st["blocked"]), (False, "not in a guild"))
        st = py(s.ns.AppStatus(b"club"))
        self.assertEqual((st["on"], st["blocked"]), (False, "not in a guild"))
        self.assertEqual(self.lua(s, "__app.decl.prompt"), "club-chat")

    def test_sources_copy_and_dedupe(self):
        s = self.start()
        self.agent(s, "kit.app.open", "{ app = 'c', hear = { 'chat:*', 'game:*', 'game:quest' }, me = true }")
        self.assertEqual(self.lua(s, "__count(__chatsubs)"), 1)
        self.assertEqual(self.lua(s, "__count(__gamesubs)"), 1)
        s.lua.execute(b"__msg = __say('party', { plain = 'hi', why = 'question' })")
        self.assertIsNone(s.lua.eval(b"__msg.source"))                    # the shared message is left alone
        item = self.wakes(s, "c")[0]["items"][0]
        self.assertEqual((item["source"], item["why"], item["id"]), ("chat", "question", s.lua.eval(b"__msg.id")))
        s.lua.execute(b"__moment('quest.turnin', 'quest', { id = 5 })")
        g = self.wakes(s, "c")[1]["items"][0]
        self.assertEqual((g["kind"], g["data"], g["me"]["name"]), ("quest.turnin", {"id": 5}, s.lua.eval(b"WuxianKit:Me().name").decode()))
        self.assertGreater(g["id"], item["id"])
        self.agent(s, "kit.app.stop", "{ app = 'c' }")
        self.assertEqual((self.lua(s, "__count(__chatsubs)"), self.lua(s, "__count(__gamesubs)")), (0, 0))

    def test_the_app_object(self):
        s = self.start()
        s.lua.execute(b"__a = WuxianKit:App('pushy', { title = 'Pushy', options = { loud = { kind = 'boolean', "
                      b"default = true } } })")
        self.assertIsNone(s.lua.eval(b"__a:Running()"))
        self.assertIs(s.lua.eval(b"__a:Push({ x = 1 })"), False)
        self.assertIs(s.lua.eval(b"__a:Get('loud')"), True)
        self.call(s, "kit.app.open", "{ app = 'pushy' }")
        self.assertNotIn("seen", self.call(s, "kit.app.status", "{ app = 'pushy' }"))   # an addon opened it
        self.assertEqual(self.lua(s, "__a:Running().heard"), 0)
        self.assertIs(s.lua.eval(b"__a:Push({ x = 1 })"), True)
        self.assertIs(s.lua.eval(b"__a:Push(nil)"), False)
        item = self.wakes(s, "pushy")[0]["items"][0]
        self.assertEqual((item["source"], item["data"]), ("addon", {"x": 1}))
        self.assertEqual(self.call(s, "kit.app.status", "{ app = 'pushy' }")["heard"], 1)


class Runs(AppCase):
    def test_through_a_reload_and_per_character(self):
        s = self.start()
        self.agent(s, "kit.app.open", "{ app = 'keep', title = 'Keep', hear = { 'bus:demo.*' }, lease = 0 }")
        s.lua.execute(b"WuxianKit:Emit('demo.a', 1)")
        before = self.wakes(s, "keep")[0]["items"][0]["id"]
        ends = self.agent(s, "kit.app.status", "{ app = 'keep' }")["ends"]

        s2 = self.start(s.reload())                                       # the run goes on, heard again
        st = self.agent(s2, "kit.app.status", "{ app = 'keep' }")
        self.assertEqual((st["on"], st["ends"], st["heard"], st["title"], st["by"]), (True, ends, 1, "Keep", "agent"))
        s2.lua.execute(b"WuxianKit:Emit('demo.b', 2)")
        after = self.wakes(s2, "keep")[0]["items"][0]["id"]
        self.assertGreater(after, before)                                 # ids never go back
        self.assertEqual([i["data"] for i in self.agent(s2, "kit.app.recent", "{ app = 'keep' }")["items"]], [1, 2])

        s3 = self.start(s2.reload(), guid="Player-1-00000002")            # another character: not its run
        st = self.agent(s3, "kit.app.status", "{ app = 'keep' }")
        self.assertEqual((st["on"], st["title"]), (False, "Keep"))
        s3.lua.execute(b"WuxianKit:Emit('demo.c', 3)")
        self.assertEqual(self.wakes(s3, "keep"), [])
        self.assertEqual(self.agent(s3, "kit.app.recent", "{ app = 'keep' }")["items"], {})   # its own ring

        s4 = self.start(s3.reload(), guid="Player-1-00000001")            # back: it runs on
        self.assertTrue(self.agent(s4, "kit.app.status", "{ app = 'keep' }")["on"])

    def test_an_addons_app_through_a_reload(self):
        s = self.start()
        decl = b"WuxianKit:App('mine', { hear = { 'bus:demo.*' } })"
        s.lua.execute(decl)
        self.call(s, "kit.app.open", "{ app = 'mine' }")
        s2 = s.reload()
        s2.lua.execute(FAKES)
        s2.login()
        s2.lua.execute(decl)                                              # declared again after the login
        self.addCleanup(lambda: self.assertEqual(s2.errors(), []))
        s2.lua.execute(b"WuxianKit:Emit('demo.a', 1)")
        self.assertEqual(len(self.wakes(s2, "mine")), 1)

    def test_lease_and_time(self):
        s = self.start()
        self.agent(s, "kit.app.open", "{ app = 'l', title = 'L', lease = 60 }")
        s.run(50)
        self.assertTrue(self.agent(s, "kit.app.status", "{ app = 'l' }")["present"])   # a heartbeat
        s.run(50)
        self.call(s, "kit.app.status", "{ app = 'l' }")                    # an addon's call is none
        st = self.agent(s, "kit.app.recent", "{ app = 'l' }")              # any kit.app.* call of the agent's is
        s.run(55)
        self.assertTrue(self.call(s, "kit.app.status", "{ app = 'l' }")["on"])
        s.run(10)
        st = self.call(s, "kit.app.status", "{ app = 'l' }")
        self.assertEqual((st["on"], st["why"]), (False, "left"))
        self.assertEqual(self.events(s, "kit.app")[-1], {"app": "l", "on": False, "why": "left"})
        self.assertIn("L: the agent left, stopped", s.chat())

        self.agent(s, "kit.app.open", "{ app = 'l', lease = 0, minutes = 1 }")   # no lease; a minute
        s.run(55)
        self.assertTrue(self.call(s, "kit.app.status", "{ app = 'l' }")["on"])
        s.run(6)
        self.assertEqual(self.events(s, "kit.app")[-1], {"app": "l", "on": False, "why": "expired"})
        self.assertIn("L: time is up, stopped", s.chat())

    def test_the_extension_it_belongs_to(self):
        s = self.start()
        s.lua.execute(b"WuxianKit:Extension('xg', { title = 'XG' })")
        s.run(1)
        s.lua.execute(b"WuxianKit:App('xa', { title = 'XA', extension = 'xg', hear = { 'bus:xg.*' } })")
        self.call(s, "kit.app.open", "{ app = 'xa' }")
        self.assertIs(py(s.ns.AppStatus(b"xa"))["extension"], True)
        s.ns.Switch(b"xg", False)
        self.assertEqual(self.events(s, "kit.app")[-1], {"app": "xa", "on": False, "why": "extension"})
        self.assertIn("XA: its extension was turned off, stopped", s.chat())
        self.assertEqual(self.agent(s, "kit.app.open", "{ app = 'xa' }")["blocked"], "Its extension XG is off")
        st = py(s.ns.AppStatus(b"xa"))
        self.assertEqual((st["extension"], st["blocked"], st["why"]), (False, "Its extension XG is off", "extension"))
        listed = next(a for a in self.agent(s, "kit.apps") if a["id"] == "xa")      # the list says so too (no heartbeat)
        self.assertEqual((listed["extension"], listed["blocked"], listed["on"]), ("xg", "Its extension XG is off", False))
        self.assertEqual(next(a for a in py(s.ns.AppManifest()) if a["id"] == "xa")["extension"], "xg")
        s.ns.Switch(b"xg", True)
        self.assertTrue(self.agent(s, "kit.app.open", "{ app = 'xa' }")["on"])
        s.ns.Switch(b"chat", False)                                       # a source's extension off: cannot start
        self.agent(s, "kit.app.stop", "{ app = 'xa' }")
        st = self.agent(s, "kit.app.open", "{ app = 'cc', hear = { 'chat:guild' } }")
        self.assertEqual(st["on"], False)
        self.assertIn("Needs the Chat extension on", st["blocked"])


class Wakes(AppCase):
    def test_urgent_lists_and_the_digest(self):
        s = self.start()
        self.agent(s, "kit.app.open", "{ app = 'u', hear = { 'chat:guild', 'game:guild' }, lease = 0, "
                                      "digest = { gather = 2, every = false, most = 3 }, urgent = { 'question', 'guild.join' } }")
        s.lua.execute(b"__say('guild', { plain = 'just talk' })")
        s.run(30)
        self.assertEqual(self.wakes(s, "u"), [])                          # every false: only urgent or full
        s.lua.execute(b"__say('guild', { plain = 'where?', why = 'question' })")
        s.run(0.5)
        self.assertEqual(self.wakes(s, "u"), [])                          # gather 2 s (seen by a ticker a second)
        s.run(2.5)
        w = self.wakes(s, "u")
        self.assertEqual([(x["reason"], len(x["items"])) for x in w], [("urgent", 2)])
        s.lua.execute(b"__moment('guild.join', 'guild', { name = 'N' })")  # by its kind
        s.run(3.5)
        self.assertEqual(self.wakes(s, "u")[-1]["reason"], "urgent")
        for i in range(3):
            s.lua.execute(f"__say('guild', {{ plain = 'x{i}' }})".encode())
        self.assertEqual(self.wakes(s, "u")[-1]["reason"], "full")
        self.assertEqual(self.agent(s, "kit.app.status", "{ app = 'u' }")["wakes"], 3)

    def test_a_wake_kept_under_its_size(self):
        s = self.start()
        self.agent(s, "kit.app.open", "{ app = 'big', hear = { 'bus:demo.*' }, digest = { every = 5, most = 10 } }")
        for i in range(8):
            s.lua.execute(f"WuxianKit:Emit('demo.x', '{i}' .. string.rep('y', 1000))".encode())
        s.run(6)
        w = self.wakes(s, "big")[0]
        self.assertEqual((w["reason"], w["app"]), ("batch", "big"))
        self.assertGreater(w["skipped"], 0)
        self.assertEqual(len(w["items"]) + w["skipped"], 8)
        self.assertLessEqual(s.lua.eval(b"#WuxianKit.Comm.Serialize(__events[#__events].data)"), 5500)

    def test_controls_and_the_players_words(self):
        s = self.start()
        self.agent(s, "kit.app.open", "{ app = 'v', title = 'Voice', controls = { 'mute', 'stop' }, say = true, "
                                      "hear = { 'bus:demo.*' }, digest = { every = false } }")
        s.lua.execute(b"WuxianKit:Emit('demo.a', 1)")
        self.assertIs(s.lua.eval(b"WuxianKit:AppControl('v', 'mute')"), True)
        w = self.wakes(s, "v")
        self.assertEqual(len(w), 1)                                       # at once, with what was gathered
        self.assertEqual((w[0]["reason"], [i["source"] for i in w[0]["items"]], w[0]["items"][1]["cmd"]),
                         ("urgent", ["bus", "control"], "mute"))
        self.assertIs(s.lua.eval(b"WuxianKit:AppControl('v', 'test')"), False)   # not one of its controls
        self.assertIs(s.lua.eval("WuxianKit:AppControl('v', '静音')".encode()), True)   # its word
        self.assertIs(s.lua.eval(b"WuxianKit:AppSay('v', '  where now?  ')"), True)
        self.assertEqual(self.wakes(s, "v")[-1]["items"], [{"source": "player", "text": "where now?",
                                                            "id": self.wakes(s, "v")[-1]["items"][0]["id"],
                                                            "time": s.lua.eval(b"time()")}])
        self.assertIs(s.lua.eval(b"WuxianKit:AppSay('v', '   ')"), False)
        self.assertEqual([c["cmd"] for c in py(s.ns.AppControls(b"v"))], ["mute", "stop"])
        self.assertEqual(py(s.ns.AppControls(b"v"))[0]["label"], "Mute")
        self.assertIs(s.lua.eval(b"WuxianKit:AppControl('v', 'stop')"), True)
        self.assertEqual(self.wakes(s, "v")[-1]["items"][0]["cmd"], "stop")    # told, then stopped
        self.assertEqual(self.events(s, "kit.app")[-1], {"app": "v", "on": False, "why": "player"})
        self.assertIs(s.lua.eval(b"WuxianKit:AppControl('v', 'mute')"), False)  # not running
        self.agent(s, "kit.app.open", "{ app = 'w', controls = { 'test' } }")
        self.assertIs(s.lua.eval(b"WuxianKit:AppSay('w', 'hi')"), False)        # no say
        s.lua.execute(b"WuxianKit:AppControl('w', 'test')")
        self.assertEqual(self.wakes(s, "w")[-1]["reason"], "item")              # no digest: an item
        self.assertEqual(py(s.ns.AppControls(b"nothing")), {})

    def test_control_labels_in_chinese(self):
        s = self.start(locale="zhCN")
        self.agent(s, "kit.app.open", "{ app = 'v', controls = { 'less', 'stop' } }")
        self.assertEqual([c["label"] for c in py(s.ns.AppControls(b"v"))], ["少说", "停止"])
        self.assertEqual(s.ns.CONTROL_WORDS["离开".encode()], b"stop")

    def test_said(self):
        s = self.start()
        self.agent(s, "kit.app.open", "{ app = 'g', hear = { 'chat:guild', 'chat:whisper' } }")
        self.agent(s, "kit.app.open", "{ app = 'p', hear = { 'chat:*' } }")
        self.agent(s, "kit.app.open", "{ app = 'b', hear = { 'bus:x' } }")
        emit = ("WuxianKit:Emit('kit.proposal', {{ id = {id}, state = {state!r}, source = {source!r}, steps = {{ "
                "{{ cap = 'chat.send', args = {{ channel = 'guild', text = 'a' }} }}, "
                "{{ cap = 'chat.send', args = {{ channel = 'party', text = 'b' }} }}, "
                "{{ cap = 'tune.cvar.set', args = {{ name = 'x', value = 1 }} }} }} }})")
        s.lua.execute(emit.format(id=101, state="pending", source="agent").encode())
        s.lua.execute(emit.format(id=101, state="done", source="agent").encode())
        s.lua.execute(emit.format(id=101, state="done", source="agent").encode())   # counted once
        s.lua.execute(emit.format(id=102, state="done", source="addon:X").encode())  # not the agent's
        said = lambda app: self.agent(s, "kit.app.status", f"{{ app = {app!r} }}")["said"]
        self.assertEqual((said("g"), said("p"), said("b")), (1, 2, 0))
        p = self.call(s, "chat.send", "{ channel = 'whisper', target = 'Friend', text = 'hey' }")
        s.lua.execute(f"WuxianKit:Call('chat.send', {{ channel = 'whisper', target = 'Friend', text = 'hey' }}, "
                      f"{{ source = 'agent' }})".encode())
        s.lua.execute(b"SlashCmdList.WUXIANKIT('yes')")                    # the player runs the first open one
        s.run(2)
        s.lua.execute(b"SlashCmdList.WUXIANKIT('yes')")
        s.run(2)
        self.assertEqual(self.lua(s, f"WuxianKit:Proposal({p['id']}).state"), "done")
        self.assertEqual(said("g"), 2)                                     # the agent's ran; the addon's does not count


class Manifest(AppCase):
    def test_apps_in_the_manifest(self):
        s = self.start()
        m = self.lua(s, "WuxianKit:Manifest()")
        guild = {"id": "guild", "title": "Guild chat", "by": "addon", "addon": "WuxianKit", "topic": "app.guild",
                 "hear": ["chat:guild", "game:guild"], "prompt": "guild-chat",
                 "start": START["en"].format("Guild chat", "guild-chat"), "extension": "chat"}
        self.assertEqual(m["apps"], [guild])                               # the kit's own
        events = next(e for e in m["extensions"] if e["id"] == "kit")["events"]
        self.assertEqual(next(e for e in events if e["topic"] == "kit.app")["data"],
                         {"app": "string", "on": "boolean", "ends": "number?", "why": "string?"})
        self.assertEqual(next(e for e in events if e["topic"] == "kit.feed")["data"]["why"], "string?")
        caps = [c["id"] for c in next(e for e in m["extensions"] if e["id"] == "kit")["capabilities"]]
        for cap in ("kit.app.open", "kit.app.status", "kit.app.stop", "kit.app.recent", "kit.apps"):
            self.assertIn(cap, caps)
        rev = m["revision"]
        self.agent(s, "kit.app.open", "{ app = 'mm', title = 'MM', hear = { 'bus:demo.*' }, prompt = 'mm-skill' }")
        s.lua.execute(b"WuxianKit:App('ad', { title = 'AD', addon = 'WxAd', hear = { 'game:quest' } })")
        m = self.lua(s, "WuxianKit:Manifest()")
        self.assertEqual(m["apps"], [guild, {"id": "mm", "title": "MM", "by": "agent", "topic": "app.mm", "hear": ["bus:demo.*"],
                                      "prompt": "mm-skill", "start": START["en"].format("MM", "mm-skill")},
                                     {"id": "ad", "title": "AD", "by": "addon", "addon": "WxAd", "topic": "app.ad",
                                      "hear": ["game:quest"]}])
        self.assertNotEqual(m["revision"], rev)
        s.run(1)
        self.assertEqual(self.events(s, "kit.changed")[-1]["revision"], m["revision"])
        self.assertIs(s.ns.ForgetApp(b"ad"), False)                       # an addon's stays
        self.assertIs(s.ns.ForgetApp(b"mm"), True)
        self.assertEqual([a["id"] for a in self.lua(s, "WuxianKit:Manifest()")["apps"]], ["guild", "ad"])
        self.assertIsNone(s.lua.eval(b"WuxianKitDB.apps.mm"))
        self.assertEqual(self.events(s, "kit.app")[-1], {"app": "mm", "on": False, "why": "player"})

    def test_the_start_line(self):
        """an app with a prompt has a start line (kit.apps, kit.app.status, kit.app.open's answer, the manifest) in
        the language in force, its title as it is (an agent's raw: it is data); none without a prompt; a change of
        language changes it and the revision"""
        s = self.start()
        self.agent(s, "kit.app.open", "{ app = 'tt', title = 'Tea \"time\" |cff00ff00ok|r', hear = { 'bus:t.*' }, "
                                      "prompt = 'tea-time' }")
        self.agent(s, "kit.app.open", "{ app = 'np', title = 'No prompt', hear = { 'bus:n.*' } }")
        want = START["en"].format('Tea "time" |cff00ff00ok|r', "tea-time")
        apps = {a["id"]: a for a in self.agent(s, "kit.apps")}
        self.assertEqual(apps["tt"]["start"], want)
        self.assertNotIn("start", apps["np"])
        self.assertEqual(self.agent(s, "kit.app.status", "{ app = 'tt' }")["start"], want)
        self.assertEqual(self.agent(s, "kit.app.open", "{ app = 'tt' }")["start"], want)
        self.assertNotIn("start", self.agent(s, "kit.app.status", "{ app = 'np' }"))
        m =self.lua(s, "WuxianKit:Manifest()")
        man = {a["id"]: a for a in m["apps"]}
        self.assertEqual(man["tt"]["start"], want)
        self.assertNotIn("start", man["np"])
        self.agent(s, "kit.app.stop", "{ app = 'tt' }")
        s.ns.SetLanguage(b"zhCN")
        zh = {a["id"]: a for a in self.agent(s, "kit.apps")}
        self.assertEqual(zh["tt"]["start"], START["zh"].format('Tea "time" |cff00ff00ok|r', "tea-time"))
        self.assertEqual(zh["guild"]["start"], START["zh"].format("公会聊天", "guild-chat"))
        m2 = self.lua(s, "WuxianKit:Manifest()")
        self.assertEqual({a["id"]: a for a in m2["apps"]}["guild"]["start"], START["zh"].format("公会聊天", "guild-chat"))
        self.assertNotEqual(m2["revision"], m["revision"])


class Options(AppCase):
    def test_options(self):
        s = self.start()
        self.agent(s, "kit.app.open", "{ app = 'o', options = { topics = { kind = 'list', title = 'Topics' }, "
                                      "volume = { kind = 'number', min = 0, max = 10, default = 3, unit = 'pt' }, "
                                      "mode = { kind = 'choice', choices = { { value = 'a', label = 'A' }, { value = 'b' } } }, "
                                      "name = { kind = 'text', default = 'Bob' }, loud = {} } }")
        o = py(s.ns.AppOptionList(b"o"))
        self.assertEqual(sorted(o), ["loud", "mode", "name", "topics", "volume"])
        self.assertEqual((o["volume"]["value"], o["volume"]["min"], o["volume"]["unit"], o["mode"]["value"],
                          o["name"]["value"], o["topics"]["value"], o["loud"]["kind"]),
                         (3, 0, "pt", "a", "Bob", {}, "boolean"))
        self.assertEqual(s.ns.SetAppOption(b"o", b"volume", b"7.4"), (True, 7))
        self.assertEqual(s.ns.SetAppOption(b"o", b"volume", b"loud"), (True, 7))  # not a number: as it was
        ok, v = s.ns.SetAppOption(b"o", b"topics", "raids，pvp, raids".encode())
        self.assertEqual(py(v), ["raids", "pvp"])
        self.assertEqual(s.ns.SetAppOption(b"o", b"mode", b"z"), (True, b"a"))
        self.assertEqual(s.ns.SetAppOption(b"o", b"loud", b"yes"), (True, True))
        self.assertIs(s.ns.SetAppOption(b"o", b"nope", b"1"), False)
        self.assertIs(s.ns.SetAppOption(b"zz", b"x", b"1"), False)
        self.assertEqual([e for e in self.events(s, "kit.option")],
                         [{"app": "o", "name": "volume", "value": 7}, {"app": "o", "name": "topics", "value": ["raids", "pvp"]},
                          {"app": "o", "name": "loud", "value": True}])
        self.assertEqual(self.lua(s, "WuxianKit:App('o'):Get('volume')"), 7)
        self.assertIsNone(s.ns.AppOptionList(b"zz"))
        s2 = self.start(s.reload())                                       # kept
        self.assertEqual(py(s2.ns.AppOptionList(b"o"))["topics"]["value"], ["raids", "pvp"])
        self.assertEqual(self.lua(s2, "WuxianKit:App('o').optionOrder"), ["loud", "mode", "name", "topics", "volume"])


if __name__ == "__main__":
    unittest.main()
