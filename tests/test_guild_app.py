"""The kit's own app guild (公会聊天, Apps/Guild/App.lua, ARCHITECTURE section 10) under Lua 5.1 in the mock client:
the declaration loads, kit.apps and the manifest list it (addon WuxianKit, prompt guild-chat, driver prompt, docs
WuxianKit/Apps/Guild), it does not start outside a guild, it hears guild chat (with why and id) and the guild's joins
through the real chat and game sources, its options come in order, its skill is found in its docs folder and packaged
as the app's, and a second Kit:App("guild") by another addon (an older WuxianGuild) replaces it without an error."""
import importlib.util
import io
import os
import re
import sys
import unittest
import zipfile
from pathlib import Path

from kitmock import KIT_DIR, Session, lupa, py
from test_standalone import bridge

REPO = Path(__file__).resolve().parents[1]
START_EN = ('Start the 无限工坊 app "Guild chat": first call the 无限工坊 MCP tool wk_docs with {"skill": "guild-chat"} and follow '
            'the steps it gives.')
ME, ASKER = "Player-1-00000001", "Player-1-00000002"
GUILD = b"""
ERR_GUILD_JOIN_S = "%s has joined the guild."
ERR_GUILD_LEAVE_S = "%s has left the guild."
__events = {}
WuxianKit:On('*', function(topic, data) __events[#__events + 1] = { topic = topic, data = data } end)
"""
# WuxianGuild 0.3.0's declaration, as that addon still makes it
OLD = """
WuxianKit:App("guild", { title = "Guild chat (old)", prompt = "guild-chat", addon = "WuxianGuild", extension = "guild",
	hear = { "chat:guild", "game:guild" }, pace = true, controls = { "mute", "unmute", "stop" }, say = true,
	lease = 600, minutes = 120,
	options = { topics = { kind = "list", title = "想多聊的话题", default = {}, order = 1 },
		avoid = { kind = "list", title = "不聊的话题", default = {}, order = 2 } },
	check = function() if not IsInGuild() then return "你还没有加入公会" end end,
	enrich = function(item) if item.kind == "guild.join" then item.recruited = true end end })
"""


def load_package():
    spec = importlib.util.spec_from_file_location("kit_package", REPO / "tools" / "package.py")
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


@unittest.skipIf(lupa is None, "lupa (Lua 5.1 for Python) is not installed")
class GuildApp(unittest.TestCase):
    line = 7000

    def start(self, before=None, **kw):
        kw.setdefault("saved", {"WoWBridge": bridge("0.9.7")})
        s = Session(self, **kw)
        if before:
            s.lua.execute(before.encode())
        s.lua.execute(GUILD)
        s.login()
        s.run(1)
        self.addCleanup(lambda: self.assertEqual(s.errors(), []))
        return s

    def agent(self, s, cap, args="{}"):
        s.lua.execute(f"__r = __fns[{cap!r}]({args})".encode())
        return py(s.g("__r"))

    def fails(self, s, cap, args="{}"):
        ok, err = s.lua.eval(f"pcall(__fns[{cap!r}], {args})".encode())
        self.assertFalse(ok, args)
        return err.decode()

    def say(self, s, text, sender="Asker-Realm", guid=ASKER):
        GuildApp.line += 1
        s.fire("CHAT_MSG_GUILD", text, sender, "", "", "", "", 0, 0, "", 1, GuildApp.line, guid)

    def wakes(self, s):
        return [e["data"] for e in py(s.g("__events")) or [] if e["topic"] == "app.guild"]

    def test_the_declaration(self):
        s = self.start()
        app = py(s.lua.eval(b"WuxianKit:App('guild').decl"))
        self.assertEqual((app["prompt"], app["addon"], app["extension"], app["hear"], app["controls"], app["say"],
                          app["lease"], app["minutes"]),
                         ("guild-chat", "WuxianKit", "chat", ["chat:guild", "game:guild"], ["mute", "unmute", "stop"],
                          True, 600, 120))
        self.assertEqual(sorted(app["pace"]), ["lively", "normal", "quiet"])
        self.assertNotIn("enrich", app)
        self.assertEqual((app["driver"], app["docs"]), ("prompt", "Apps/Guild"))
        self.assertEqual(self.agent(s, "kit.apps"), [{"id": "guild", "title": "Guild chat", "by": "addon",
                                                      "addon": "WuxianKit", "on": False, "present": False,
                                                      "prompt": "guild-chat", "start": START_EN, "extension": "chat",
                                                      "driver": "prompt", "launch": False, "temp": False,
                                                      "launching": False}])
        m = py(s.lua.eval(b"WuxianKit:Manifest()"))
        self.assertEqual(m["apps"], [{"id": "guild", "title": "Guild chat", "by": "addon", "addon": "WuxianKit",
                                      "topic": "app.guild", "hear": ["chat:guild", "game:guild"],
                                      "prompt": "guild-chat", "start": START_EN, "extension": "chat",
                                      "driver": "prompt", "docs": "WuxianKit/Apps/Guild", "launch": False,
                                      "temp": False}])
        zh = self.start(locale="zhCN")
        self.assertEqual(self.agent(zh, "kit.apps")[0]["title"], "公会聊天")
        self.assertEqual(self.agent(zh, "kit.apps")[0]["start"],
                         '开始无限工坊的应用「公会聊天」：先调用无限工坊 MCP 的工具 wk_docs，参数 {"skill": "guild-chat"}，照读到的步骤做。')
        o = py(zh.ns.AppOptionList(b"guild"))
        self.assertEqual((o["topics"]["title"], o["avoid"]["title"], o["avoid"]["hint"]),
                         ("想多聊的话题", "不聊的话题", "Agent 不会主动提起"))

    def test_options_in_order(self):
        s = self.start()
        self.assertEqual(py(s.lua.eval(b"WuxianKit:App('guild').optionOrder")), ["activity", "quiet", "topics", "avoid"])
        o = py(s.ns.AppOptionList(b"guild"))
        self.assertEqual((o["topics"]["kind"], o["topics"]["value"], o["topics"]["title"], o["avoid"]["kind"],
                          o["avoid"]["title"], o["activity"]["value"]),
                         ("list", {}, "Topics to talk about", "list", "Topics to avoid", "normal"))
        self.assertIn("dungeons", o["topics"]["hint"])

    def test_not_in_a_guild(self):
        s = self.start(before="__guild = false")
        st = self.agent(s, "kit.app.open", "{ app = 'guild' }")
        self.assertEqual((st["on"], st["blocked"]), (False, "Your character is not in a guild"))
        self.assertEqual(py(s.ns.AppStatus(b"guild"))["blocked"], "Your character is not in a guild")

    def test_hand_to_ai_on_its_card(self):
        """the /wk window's page of the app: 交给 AI opens the copy box with the start line kit.apps gives"""
        s = self.start()
        s.lua.execute(b"WuxianKit:Window('app:guild')")
        w = s.g("WuxianKitWindow")
        hand = next(b for b in w[b"buttons"].values() if b[b"shown"] and b[b"label"][b"text"] == b"Hand to AI")
        hand.Click(hand)
        f = s.g("WuxianKitCopyWindow")
        self.assertEqual((f[b"shown"], f[b"edit"][b"text"].decode(), f[b"title"][b"text"].decode()),
                         (True, START_EN, "Guild chat"))
        self.assertEqual(f[b"status"][b"text"].decode(), "Press Ctrl+C to copy, then paste it into your AI chat")

    def test_options_carry_over(self):
        """the options a player set for WuxianGuild 0.3's guild app (WuxianKitDB.apps.guild) stay"""
        s = self.start(saved={"WoWBridge": bridge("0.9.7"),
                              "WuxianKitDB": "{ apps = { guild = { options = { topics = { 'raids' }, activity = 'lively' } } } }".encode()})
        o = py(s.ns.AppOptionList(b"guild"))
        self.assertEqual((o["topics"]["value"], o["activity"]["value"]), (["raids"], "lively"))

    def test_hears_the_guild(self):
        s = self.start()
        st = self.agent(s, "kit.app.open", "{ app = 'guild', minutes = 30 }")
        self.assertEqual((st["on"], st["by"], st["pace"], st["lease"]), (True, "addon", "normal", 600))
        s.fire("CHAT_MSG_SYSTEM", "|Hplayer:Newbie-Forever|h[Newbie]|h has joined the guild.")
        self.say(s, "anyone know where the dungeon is?")
        s.run(6)
        w = self.wakes(s)
        self.assertEqual([x["reason"] for x in w], ["urgent"])
        self.assertEqual((w[0]["app"], w[0]["pace"], w[0]["quiet"], w[0]["skipped"]), ("guild", "normal", False, 0))
        join, line = w[0]["items"]
        self.assertEqual((join["source"], join["kind"], join["data"]), ("game", "guild.join", {"name": "Newbie"}))
        self.assertNotIn("recruited", join)
        self.assertEqual((line["source"], line["channel"], line["why"], line["plain"]),
                         ("chat", "guild", "question", "anyone know where the dungeon is?"))
        self.assertIsInstance(line["id"], int)
        self.assertEqual(s.lua.eval(f"WuxianKit.Chat.Message({line['id']}).plain".encode()).decode(), line["plain"])
        self.say(s, "hi wuxian")
        s.run(6)
        mention = self.wakes(s)[-1]["items"][-1]
        self.assertEqual((mention["why"], mention["sender"]), ("mention", "Asker"))
        s.g("SlashCmdList")[b"WUXIANKIT"](b"guild mute")
        s.run(0.5)
        self.assertEqual(self.wakes(s)[-1]["items"][-1]["cmd"], "mute")
        st = self.agent(s, "kit.app.stop", "{ app = 'guild' }")
        self.assertEqual((st["on"], st["why"]), (False, "stopped"))

    def test_a_second_declaration_by_another_addon(self):
        """an older WuxianGuild (0.3.0) loads after the kit and declares guild again: no error, its declaration replaces
        the kit's (one app, the same id and stored options)"""
        s = self.start(before=OLD)
        apps = self.agent(s, "kit.apps")
        self.assertEqual([(a["id"], a["addon"], a["title"]) for a in apps], [("guild", "WuxianGuild", "Guild chat (old)")])
        s.lua.execute(f"__ok, __err = pcall(function() {OLD} end)".encode())   # and again, after login
        self.assertIs(s.g("__ok"), True, s.g("__err"))
        self.assertEqual(len(self.agent(s, "kit.apps")), 1)

    def test_the_skill(self):
        root = KIT_DIR
        p = root / "Apps" / "Guild" / "skills" / "guild-chat.md"
        text = p.read_text(encoding="utf-8")
        self.assertNotIn(b"\r\n", p.read_bytes())
        head = dict(re.findall(r"^([a-z-]+): (.+)$", text.split("---")[1], re.M))
        self.assertEqual((head["name"], head["title"], head["title-zh"], head["arguments"], head["needs"],
                          head["mcp"]),
                         ("guild-chat", "Guild chat", "公会聊天", "hours?", "shell", "wuxianwow https://wuxianwow.com/mcp"))
        for gone in ("chatlink", "FACTS", "wk_guild_brief", "recruited", "mcp__codex__", "C:\\", "wow-forever"):
            self.assertNotIn(gone, text)
        for there in ("https://wuxianwow.com/mcp", "https://wuxianwow.com/ai",
                      "claude mcp add --transport http wuxianwow", "wuxian listen guild --once --since <next>",
                      "0.9.13", "CLAUDE.md", "wk_sense_guild", "wk_kit_app_stop", "report_issue", "guild/"):
            self.assertIn(there.replace(" ", ""), re.sub(r"\s+", "", text), there)
        # the app's docs folder holds it (the workshop reads <docs>/skills/*.md), not the chat extension's
        s = self.start()
        m = py(s.lua.eval(b"WuxianKit:Manifest()"))
        guild = next(a for a in m["apps"] if a["id"] == "guild")
        self.assertEqual(guild["docs"], "WuxianKit/Apps/Guild")
        self.assertTrue((root.parent / guild["docs"] / "skills" / "guild-chat.md").is_file())
        chat = next(e for e in m["extensions"] if e["id"] == "chat")
        self.assertFalse((root.parent / chat["docs"] / "skills").exists())
        # packaged: in the catalog entry's skills (the app's) and in the zip
        package = load_package()
        skill = next(x for x in package.skills() if x["name"] == "guild-chat")
        self.assertEqual((skill["app"], skill.get("extension")), ("guild", None))
        self.assertEqual(skill["title"], {"zh": "公会聊天", "en": "Guild chat"})
        names = zipfile.ZipFile(io.BytesIO(package.pack())).namelist()
        for f in ("WuxianKit/Apps/Guild/App.lua", "WuxianKit/Apps/Guild/skills/guild-chat.md"):
            self.assertIn(f, names)
        self.assertEqual([n for n in names if "GuildApp" in n or "Chat/skills" in n], [])

    @unittest.skipUnless(os.environ.get("WUXIAN_WORKSHOP"), "无限工坊's source is not there (WUXIAN_WORKSHOP)")
    def test_the_workshop_serves_it(self):
        ws = Path(os.environ["WUXIAN_WORKSHOP"])
        sys.path[:0] = [str(ws / "src")]
        try:
            from wuxianworkshop.mcp.kit import skills_in
        except ImportError as e:                                       # pragma: no cover
            self.skipTest(str(e))
        found = {x["name"]: x for x in skills_in(str(KIT_DIR.parent), "WuxianKit/Apps/Guild")}
        self.assertEqual(found["guild-chat"]["arguments"], [("hours", False)])
        self.assertIn("{{hours}}", found["guild-chat"]["body"])


if __name__ == "__main__":
    unittest.main()
