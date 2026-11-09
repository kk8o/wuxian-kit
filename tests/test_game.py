"""游戏动态 (Game events, ARCHITECTURE section 11): the source game (an app that hears game:<topic>, game:<kind> or
game:*), WuxianKit.Game:On / Off, the guild topic, and laziness (a topic's events are registered only while something
hears it). The detectors of the other topics are in test_game_combat.py, test_game_progress.py and test_game_guide.py;
GameTest here drives them all, through a temporary app (kit.app.open temp = true) named probe."""
import unittest

from kitmock import Session, lupa, py


class Game:
    """one UI session, logged in, every bus event caught"""

    def __init__(self, test, session=None, **kw):
        self.test = test
        self.s = session or Session(test, **kw)
        self.lua = self.s.lua
        self.lua.execute(b"__events = {} WuxianKit:On('*', function(topic, data) "
                         b"__events[#__events + 1] = { topic = topic, data = data } end)")
        self.s.login()
        self.s.run(1)

    def call(self, cap, args="{}"):
        self.lua.execute(f"__answer = WuxianKit:Call({cap!r}, {args})".encode())
        return py(self.s.g("__answer"))

    def try_call(self, cap, args="{}"):
        self.lua.execute(f"__ok, __answer = pcall(WuxianKit.Call, WuxianKit, {cap!r}, {args})".encode())
        return bool(self.s.g("__ok")), py(self.s.g("__answer"))

    def open_args(self, topics=None, me=None, minutes=60, temp=True):
        hear = ["game:" + t for t in topics] if topics is not None else ["game:*"]
        args = [f"app = 'probe', minutes = {minutes}, lease = 0", "hear = { " + ", ".join(repr(h) for h in hear) + " }"]
        if temp:
            args.append("temp = true")
        if me is not None:
            args.append(f"me = {'true' if me else 'false'}")
        return "{ " + ", ".join(args) + " }"

    def listen(self, topics=None, me=None, minutes=60, temp=True):
        """the app probe hears the topics (all: game:*), a temporary one unless temp is false; no lease"""
        return self.call("kit.app.open", self.open_args(topics, me, minutes, temp))

    def stop(self):
        return self.call("kit.app.stop", "{ app = 'probe' }")

    def events(self, topic="app.probe"):
        return [e["data"] for e in py(self.s.g("__events")) or [] if e["topic"] == topic]

    def moments(self, kind=None):
        """the items of the app probe's wakes (each wake one item: no digest)"""
        return [m for w in self.events() for m in w["items"] if kind is None or m["kind"] == kind]

    def kinds(self):
        return [m["kind"] for m in self.moments()]

    def active(self):
        """the topics running now"""
        return sorted(k.decode() for k, v in (self.s.ns[b"game"][b"active"] or {}).items() if v)

    def registered(self, topic):
        """the events the topic's own frame has registered now"""
        frame = self.s.ns[b"game"][b"topics"][topic.encode()][b"frame"]
        return sorted(k.decode() for k in (frame[b"events"] or {}).keys())

    def fire(self, event, *args):
        self.s.fire(event, *args)

    def run(self, seconds, dt=0.05):
        self.s.run(seconds, dt)

    def errors(self):
        return self.s.errors()


class GameTest(unittest.TestCase):
    """each test ends with no Lua error"""

    def setUp(self):
        if lupa is None:
            self.skipTest("pip install lupa")
        self.games = []

    def game(self, **kw):
        g = Game(self, **kw)
        self.games.append(g)
        return g

    def tearDown(self):
        for g in getattr(self, "games", []):
            self.assertEqual(g.errors(), [])


GUILD = r"""
ERR_GUILD_JOIN_S = "%s has joined the guild."
ERR_GUILD_LEAVE_S = "%s has left the guild."
__roster, __rosterAsks = {}, 0
function GetNumGuildMembers() return #__roster, #__roster end
function GetGuildRosterInfo(i)
	local m = __roster[i]
	if m then return m[1], "Member", 3, m[2] end
end
function GetMaxLevelForPlayerExpansion() return 60 end
C_GuildInfo.GuildRoster = function() __rosterAsks = __rosterAsks + 1 end
function __level(name, lv)
	for _, m in ipairs(__roster) do if m[1] == name then m[2] = lv end end
	__fire("GUILD_ROSTER_UPDATE", true)
end
"""


class Source(GameTest):
    def test_listen_all_and_the_moment_shape(self):
        g = self.game()
        answer = g.listen()
        self.assertTrue(answer["on"])
        self.assertEqual((answer["hear"], answer["temp"]), (["game:*"], True))
        self.assertEqual(g.active(), ["aura", "combat", "growth", "guide", "guild", "quest", "travel"])
        g.fire("QUEST_TURNED_IN", 3001, 2150, 1500)
        [w] = g.events()
        self.assertEqual((w["app"], w["reason"]), ("probe", "item"))
        [m] = g.moments()
        self.assertEqual((m["source"], m["kind"], m["topic"], m["data"]), ("game", "quest.turnin", "quest",
                         {"quest": "Healing Herbs", "id": 3001, "xp": 2150, "money": 1500}))
        self.assertIsInstance(m["id"], int)
        self.assertIsInstance(m["time"], int)
        self.assertNotIn("me", m)
        recent = g.call("kit.app.recent", "{ app = 'probe' }")
        self.assertEqual([i["kind"] for i in recent["items"]], ["quest.turnin"])
        self.assertEqual(recent["next"], m["id"])

    def test_me_and_topics(self):
        g = self.game()
        answer = g.listen(topics=["quest", "combat", "quest", "quest.turnin"], me=True)
        self.assertEqual(answer["hear"], ["game:quest", "game:combat"])     # none twice, none another covers
        self.assertEqual(g.active(), ["combat", "quest"])
        g.fire("QUEST_TURNED_IN", 3001, 0, 0)
        g.lua.execute(b"__resting = true function IsResting() return __resting end")
        g.fire("PLAYER_UPDATE_RESTING")                                          # travel: not heard
        [m] = g.moments()                                                        # once, though two entries match
        self.assertEqual(m["kind"], "quest.turnin")
        self.assertEqual(m["me"]["name"], "Wuxian Forever")
        self.assertEqual(m["me"]["level"], 8)
        self.assertIs(m["me"]["combat"], False)

    def test_bad_topics_are_refused(self):
        g = self.game()
        ok, err = g.try_call("kit.app.open", g.open_args(topics=["combat", "loot"]))
        self.assertFalse(ok)
        self.assertIn("game:loot: a game source is a topic (combat, aura, growth, quest, travel, guild, guide)", err)
        self.assertEqual(g.active(), [])
        self.assertNotIn("probe", [x["id"] for x in g.call("kit.apps")])
        answer = g.listen(topics=["guild.join"])                                 # a kind turns its topic on
        self.assertEqual(answer["hear"], ["game:guild.join"])
        self.assertEqual(g.active(), ["guild"])

    def test_stop_and_the_end_of_its_time_turn_the_topics_off(self):
        g = self.game()
        g.listen(topics=["quest"])
        self.assertEqual(g.active(), ["quest"])
        g.stop()
        self.assertEqual(g.active(), [])
        g.fire("QUEST_TURNED_IN", 3001, 0, 0)
        self.assertEqual(g.moments(), [])
        g.listen(topics=["travel"], minutes=1)
        self.assertEqual(g.active(), ["travel"])
        g.run(70)
        self.assertEqual(g.active(), [])

    def test_a_reload_keeps_a_kept_app_and_its_topics(self):
        g = self.game()
        g.listen(topics=["quest"], temp=False)
        g2 = Game(self, session=g.s.reload())
        self.games.append(g2)
        self.assertEqual(g2.active(), ["quest"])
        g2.fire("QUEST_TURNED_IN", 3002, 0, 0)
        self.assertEqual([m["data"]["id"] for m in g2.moments()], [3002])

    def test_a_reload_ends_a_temporary_app(self):
        g = self.game()
        g.listen(topics=["quest"])
        g2 = Game(self, session=g.s.reload())
        self.games.append(g2)
        self.assertEqual(g2.active(), [])
        self.assertNotIn("probe", [x["id"] for x in g2.call("kit.apps")])

    def test_the_extension_off_stops_everything(self):
        g = self.game()
        g.lua.execute(b"__heard = {} WuxianKit.Game:On('*', function(item) __heard[#__heard + 1] = item.kind end)")
        g.listen()
        self.assertEqual(len(g.active()), 7)
        g.s.ns[b"Switch"](b"game", False)
        self.assertEqual(g.active(), [])
        g.fire("QUEST_TURNED_IN", 3001, 0, 0)
        self.assertEqual(g.moments(), [])
        self.assertEqual(py(g.lua.eval(b"__heard")) or [], [])
        self.assertEqual(g.registered("quest"), [])
        self.assertNotIn("probe", [x["id"] for x in g.call("kit.apps")])         # the app stopped (a temporary one goes)
        g.s.ns[b"Switch"](b"game", True)                                       # on again: the subscriber hears again
        self.assertEqual(len(g.active()), 7)
        g.fire("QUEST_TURNED_IN", 3001, 0, 0)
        self.assertEqual(py(g.lua.eval(b"__heard")), ["quest.turnin"])
        self.assertEqual(g.moments(), [])
        g.s.ns[b"Switch"](b"game", False)                                       # off: a new app is blocked
        answer = g.listen()
        self.assertEqual((answer["on"], answer["blocked"]), (False, "Needs the Game events extension on"))
        self.assertNotIn("probe", [x["id"] for x in g.call("kit.apps")])         # a temporary one is not kept


class Subscribers(GameTest):
    def test_on_by_kind_topic_and_all(self):
        g = self.game()
        g.lua.execute(b"""
            __got = { kind = {}, topic = {}, all = {} }
            __t1 = WuxianKit.Game:On('quest.turnin', function(item) table.insert(__got.kind, item) end)
            __t2 = WuxianKit.Game:On('travel', function(item) table.insert(__got.topic, item.kind) end)
            __t3 = WuxianKit.Game:On('*', function(item) table.insert(__got.all, item.kind) item.data.id = 0 end)
        """)
        self.assertEqual(g.active(), ["aura", "combat", "growth", "guide", "guild", "quest", "travel"])
        g.fire("QUEST_TURNED_IN", 3001, 0, 0)
        g.lua.execute(b"__resting = true function IsResting() return __resting end")
        g.fire("PLAYER_UPDATE_RESTING")
        got = py(g.lua.eval(b"__got"))
        [item] = got["kind"]
        self.assertEqual(sorted(item), ["data", "kind", "time", "topic"])        # no id
        self.assertEqual((item["kind"], item["topic"], item["data"]["id"]), ("quest.turnin", "quest", 3001))
        self.assertEqual(got["topic"], ["rest"])
        self.assertEqual(got["all"], ["quest.turnin", "rest"])
        self.assertEqual(g.events(), [])                                        # no app: no wakes
        g.lua.execute(b"WuxianKit.Game:Off(__t3)")
        self.assertEqual(g.active(), ["quest", "travel"])
        g.lua.execute(b"WuxianKit.Game:Off(__t1) WuxianKit.Game:Off(__t2)")
        self.assertEqual(g.active(), [])

    def test_bad_what_is_an_error(self):
        g = self.game()
        ok = g.lua.eval(b"(pcall(WuxianKit.Game.On, WuxianKit.Game, 'loot', function() end))")
        self.assertFalse(ok)
        self.assertEqual(g.active(), [])

    def test_subscriber_and_app_together(self):
        g = self.game()
        g.lua.execute(b"__n = 0 __t = WuxianKit.Game:On('quest', function() __n = __n + 1 end)")
        g.listen(topics=["growth"])
        self.assertEqual(g.active(), ["growth", "quest"])
        g.fire("QUEST_TURNED_IN", 3001, 0, 0)
        self.assertEqual(g.lua.eval(b"__n"), 1)
        self.assertEqual(g.moments(), [])                                       # the app hears growth only
        g.stop()
        self.assertEqual(g.active(), ["quest"])


class Laziness(GameTest):
    def test_nothing_registered_while_nobody_hears(self):
        g = self.game()
        for topic in ("combat", "aura", "growth", "quest", "guild", "guide", "travel"):
            self.assertEqual(g.registered(topic), [], topic)
        g.listen(topics=["combat", "aura"])
        combat = g.registered("combat")
        self.assertIn("UNIT_SPELLCAST_SUCCEEDED", combat)
        self.assertIn("PLAYER_REGEN_DISABLED", combat)
        for busy in ("UNIT_COMBAT", "UNIT_HEALTH", "NAME_PLATE_UNIT_REMOVED"):  # only during a fight
            self.assertNotIn(busy, combat)
        self.assertNotIn("COMBAT_LOG_EVENT_UNFILTERED", combat)
        self.assertIn("UNIT_AURA", g.registered("aura"))
        g.lua.execute(b"__combat(true)")
        self.assertIn("UNIT_COMBAT", g.registered("combat"))
        self.assertNotIn("UNIT_AURA", g.registered("aura"))                    # auras: out of combat only
        g.run(1)
        g.lua.execute(b"__combat(false)")
        self.assertNotIn("UNIT_COMBAT", g.registered("combat"))
        self.assertIn("UNIT_AURA", g.registered("aura"))
        self.assertEqual(g.registered("growth"), [])
        g.stop()
        self.assertEqual(g.registered("combat"), [])
        self.assertEqual(g.registered("aura"), [])

    def test_a_fight_ticker_only_in_a_fight_heard(self):
        g = self.game()
        g.listen(topics=["combat"])
        g.lua.execute(b"__combat(true)")
        g.run(0.6)
        g.stop()                                                                 # mid-fight
        self.assertEqual(g.registered("combat"), [])
        g.run(3)
        g.lua.execute(b"__combat(false)")
        self.assertEqual(g.moments("combat.end"), [])

    def test_baselines_rebuilt_when_a_topic_turns_on(self):
        g = self.game()
        g.listen(topics=["quest"])
        g.stop()
        g.lua.execute(b"__quests[2].objectives[1].finished = true __quests[2].complete = true")
        g.listen(topics=["quest"])                                               # the change happened unheard
        g.fire("QUEST_LOG_UPDATE")
        g.run(0.5)
        self.assertEqual(g.moments(), [])


class Guild(GameTest):
    def guild_game(self):
        g = self.game()
        g.lua.execute(GUILD.encode())
        return g

    def test_join_leave_and_achievement(self):
        g = self.guild_game()
        g.listen(topics=["guild"])
        g.fire("CHAT_MSG_SYSTEM", "|Hplayer:Aya-Forever|h[Aya]|h has joined the guild.")
        g.fire("CHAT_MSG_SYSTEM", "Bob has left the guild.")
        g.fire("CHAT_MSG_SYSTEM", "You are now AFK.")
        g.fire("CHAT_MSG_GUILD_ACHIEVEMENT", "%s has earned the achievement |cffffff00|Hachievement:6:Player-1:1:1:1:"
               "25:4294967295:4294967295:4294967295:4294967295|h[Level 10]|h|r!", "Aya-Forever")
        g.fire("CHAT_MSG_GUILD_ACHIEVEMENT", "<secret>", "Aya")
        g.fire("CHAT_MSG_SYSTEM", "<secret>")
        self.assertEqual([(m["kind"], m["data"]) for m in g.moments()], [
            ("guild.join", {"name": "Aya"}),
            ("guild.leave", {"name": "Bob"}),
            ("guild.achievement", {"name": "Aya", "plain": "Aya has earned the achievement [Level 10]!",
                                   "links": [{"kind": "achievement", "id": 6, "name": "Level 10"}]})])

    def test_chinese_format_strings(self):
        g = self.guild_game()
        g.lua.execute("ERR_GUILD_JOIN_S = '%s加入了公会。' ERR_GUILD_LEAVE_S = '%s离开了公会。'".encode())
        g.listen(topics=["guild"])
        g.fire("CHAT_MSG_SYSTEM", "小明加入了公会。")
        g.fire("CHAT_MSG_SYSTEM", "小红离开了公会。")
        self.assertEqual([(m["kind"], m["data"]["name"]) for m in g.moments()],
                         [("guild.join", "小明"), ("guild.leave", "小红")])

    def test_level_ups_tenth_and_top_only_after_the_first_roster(self):
        g = self.guild_game()
        g.lua.execute(b"__roster = { { 'Aya-Forever', 18 }, { 'Bob', 59 }, { 'Cid', 30 }, { '<secret>', 9 } }")
        g.fire("GUILD_ROSTER_UPDATE", True)                                      # nobody hears: nothing kept
        g.listen(topics=["guild"])
        self.assertEqual(g.lua.eval(b"__rosterAsks"), 1)                         # asked for one at the start
        g.lua.execute(b"__roster[1][2] = 19 __roster[3][2] = 41")
        g.fire("GUILD_ROSTER_UPDATE", True)                                      # the first roster: only kept
        g.lua.execute(b"__level('Aya-Forever', 20)")                             # 19 -> 20: a tenth level
        g.lua.execute(b"__level('Cid', 42)")                                     # 41 -> 42: not told
        g.lua.execute(b"__level('Bob', 60)")                                     # the top level
        g.lua.execute(b"__level('<secret>', 10)")
        self.assertEqual([m["data"] for m in g.moments("guild.level")],
                         [{"name": "Aya", "level": 20}, {"name": "Bob", "level": 60}])
        g.run(61)
        self.assertEqual(g.lua.eval(b"__rosterAsks"), 2)                         # every 60 s while it runs
        g.stop()
        g.run(130)
        self.assertEqual(g.lua.eval(b"__rosterAsks"), 2)
        g.listen(topics=["guild"])                                               # a new start: a new first roster
        g.lua.execute(b"__level('Cid', 50)")
        g.lua.execute(b"__level('Cid', 51)")
        self.assertEqual(len(g.moments("guild.level")), 2)

    def test_not_in_a_guild_asks_for_nothing(self):
        g = self.guild_game()
        g.lua.execute(b"__guild = false")
        g.listen(topics=["guild"])
        g.run(61)
        self.assertEqual(g.lua.eval(b"__rosterAsks"), 0)


if __name__ == "__main__":
    unittest.main()
