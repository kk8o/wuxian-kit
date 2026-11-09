"""The window's apps (0.6, Core/UI/Window.lua) under Lua 5.1 in the mock client, over Apps.lua's ns functions faked as in
test_app_panel: the group 应用 first, before the extensions, with each app's state, the window first open on the first
app's page, an app's page (where it came from, its card; remove for an agent's; a temporary one marked), redrawn when
apps change; /wk <app> [words] (its controls, its words, what it takes, its page), /wk help; and
the core's page drawing the core's own options (称呼, 0.6)."""
import unittest

from kitmock import click, lupa, py, texts, type_into
from test_app_panel import button, labels, log, shown, start


@unittest.skipIf(lupa is None, "lupa (Lua 5.1 for Python) is not installed")
class WindowApps(unittest.TestCase):
    def setup(self, **kw):
        s = start(self, **kw)
        s.lua.execute(b"""
			__add('voice', { addon = 'WxVoice', decl = { title = 'Voice' }, controls = { 'mute', 'unmute', 'stop' },
				status = { app = 'voice', on = true, said = 1 } })
			__add('bot', { by = 'agent', decl = { title = 'Bot', prompt = 'bot-run' } })
		""")
        return s

    def window(self, s, page="kit"):
        s.lua.execute(f"WuxianKit:Window({page!r})".encode())
        return s.g("WuxianKitWindow")

    def slash(self, s, msg):
        s.lines.clear()
        s.g("SlashCmdList")[b"WUXIANKIT"](msg.encode())
        return s.chat()

    def item(self, w, title):
        return next(b for b in shown(w[b"items"]) if b[b"label"][b"text"].decode() == title)

    def test_the_apps_group(self):
        """the group comes first, before the extensions, each app with a dim state; its page is its title, where it
        came from and its card; an agent's has remove; one gone, the first app's page; a new app shows once kit.app
        tells of it"""
        s = self.setup()
        w = self.window(s)
        heads = texts(w[b"list"])
        self.assertEqual(heads[0], "Apps")
        self.assertLess(heads.index("Apps"), heads.index("Built-in"))
        voice, bot = self.item(w, "Voice"), self.item(w, "Bot")
        self.assertEqual((voice[b"state"][b"text"], bot[b"state"][b"text"]), (b"On", b"Off"))
        self.assertFalse(self.item(w, "Core")[b"state"][b"shown"])
        click(voice)
        body = texts(w[b"body"])
        self.assertEqual(body[:2], ["Voice", "Addon WxVoice"])
        self.assertEqual(w[b"pill"][b"text"][b"text"], b"App")
        self.assertTrue(body[2].startswith("Agent here"))
        self.assertEqual(labels(w), ["Stop", "Mute", "Unmute"])
        click(button(w, "Mute"))
        self.assertEqual(log(s), ["control voice mute"])
        click(bot)
        self.assertEqual(texts(w[b"body"])[:3], ["Bot", "Declared by an agent", "Ready to connect an agent"])
        self.assertEqual(labels(w), ["Hand to AI", "Remove"])
        click(button(w, "Remove"))
        self.assertEqual(log(s)[-1], "forget bot")
        self.assertEqual(texts(w[b"body"])[0], "Voice")                         # gone: the first app's page
        self.assertNotIn("Bot", [b[b"label"][b"text"].decode() for b in shown(w[b"items"])])
        s.lua.execute(b"__add('later', { decl = { title = 'Later' } }) "
                      b"WuxianKit:Emit('kit.app', { app = 'later', on = true })")
        s.run(0.1)
        self.item(w, "Later")
        s.lua.execute(b"__ns.SetLanguage('zhCN')")
        self.assertEqual(texts(w[b"list"])[0], "应用")
        self.assertEqual(self.item(w, "Voice")[b"state"][b"text"].decode(), "运行中")
        self.window(s, "voice")
        self.assertEqual(texts(w[b"body"])[1], "插件 WxVoice")
        self.assertEqual(w[b"pill"][b"text"][b"text"].decode(), "应用")
        s.lua.execute(b"WuxianKit:Extension('voice', { title = 'Voice ext' })")   # an extension of the same name first
        self.window(s, "voice")
        self.assertEqual(texts(w[b"body"])[0], "Voice ext")
        self.window(s, "app:voice")
        self.assertEqual(texts(w[b"body"])[1], "插件 WxVoice")

    def test_the_first_page(self):
        """the window first opens on the first app's page, its item marked; later on the page it showed last; with no
        app, on the core's"""
        s = self.setup()
        self.slash(s, "")
        w = s.g("WuxianKitWindow")
        self.assertEqual(texts(w[b"body"])[:2], ["Voice", "Addon WxVoice"])
        gold = py(s.lua.eval(b"WuxianKit.Skin.C.goldSoft"))
        marked = [b[b"label"][b"text"].decode() for b in shown(w[b"items"]) if py(b[b"bg"][b"rgb"]) == gold]
        self.assertEqual(marked, ["Voice"])
        click(self.item(w, "Core"))
        self.slash(s, "")                                                       # closed
        self.assertFalse(w[b"shown"])
        self.slash(s, "")
        self.assertEqual(texts(w[b"body"])[0], "Core")
        bare = start(self)
        bare.g("SlashCmdList")[b"WUXIANKIT"](b"")
        self.assertEqual(texts(bare.g("WuxianKitWindow")[b"body"])[0], "Core")

    def test_an_agents_apps_page(self):
        """an app an agent declared without a prompt: its page says an agent declared it, no main button (no 开始), its
        item on or off; a temporary app's capsule says so; /wk <app> 开始|start is words like any other"""
        s = self.setup()
        s.lua.execute(b"__add('buddy', { by = 'agent', launch = true, controls = { 'mute', 'stop' }, "
                      b"decl = { title = 'Buddy', driver = 'program' } }) "
                      b"__add('peek', { by = 'agent', decl = { title = 'Peek', prompt = 'peek-run' }, temp = true, "
                      b"status = { app = 'peek', on = true, said = 0 } })")
        w = self.window(s, "buddy")
        self.assertEqual(texts(w[b"body"])[:3], ["Buddy", "Declared by an agent", "Ready to connect an agent"])
        self.assertEqual(w[b"pill"][b"text"][b"text"], b"App")
        self.assertEqual(labels(w), ["Remove"])
        self.assertEqual(self.item(w, "Buddy")[b"state"][b"text"], b"Off")
        click(self.item(w, "Peek"))
        self.assertEqual(texts(w[b"body"])[:2], ["Peek", "Declared by an agent"])
        self.assertEqual(w[b"pill"][b"text"][b"text"], b"Temporary")
        self.assertEqual(labels(w), ["Stop", "Remove"])
        s.lua.execute(b"__ns.SetLanguage('zhCN')")
        self.assertEqual(w[b"pill"][b"text"][b"text"].decode(), "临时")
        self.assertEqual(self.item(w, "Buddy")[b"state"][b"text"].decode(), "未运行")
        click(self.item(w, "Buddy"))
        self.assertEqual(texts(w[b"body"])[1:3], ["Agent 声明", "可以接入 Agent"])
        self.assertEqual(w[b"pill"][b"text"][b"text"].decode(), "应用")
        s.lua.execute(b"__ns.SetLanguage('enUS')")
        self.assertIn("Buddy takes: mute, stop", self.slash(s, "buddy start"))
        self.assertIn("/wk buddy: Buddy · mute, stop", self.slash(s, "help"))
        s.lua.execute(b"__ns.SetLanguage('zhCN')")
        self.assertIn("「Buddy」的指令：静音、停止", self.slash(s, "buddy 开始"))
        self.assertEqual(log(s), ["say buddy start", "say buddy 开始"])            # words, as any (it takes none)

    def test_the_page_ticks(self):
        """an app's page is drawn again every few seconds while the window shows it"""
        s = self.setup()
        now = int(s.lua.eval(b"time()"))
        s.g("__apps")[b"voice"][b"status"][b"seen"] = now - 61
        w = self.window(s, "voice")
        self.assertIn("Last answer 1 min ago", texts(w[b"body"])[2])
        s.run(65)
        self.assertIn("Last answer 2 min ago", texts(w[b"body"])[2])

    def test_the_slash_command(self):
        """/wk <app> <word>: one of its controls (English or Chinese) to Kit:AppControl; else its words to Kit:AppSay;
        else what it takes. /wk <app> opens its page; an extension's own command comes first; /wk help lists the apps"""
        s = self.setup()
        self.assertIn("Told Voice: Mute", self.slash(s, "voice mute"))
        self.assertEqual(log(s), ["control voice mute"])
        self.assertIn("Told Voice: Mute", self.slash(s, "voice MUTE"))
        self.assertIn("Told Voice: Unmute", self.slash(s, "voice 开声"))
        self.assertIn("Told Voice: Stop", self.slash(s, "voice 离开"))
        self.assertEqual(log(s)[-1], "stop voice player")
        self.assertIn("Voice is not running", self.slash(s, "voice mute"))
        self.assertIn("Voice takes: mute, unmute, stop", self.slash(s, "voice less please"))   # not one of its controls
        self.assertEqual(log(s)[-1], "say voice less please")
        s.lua.execute(b"__apps.voice.say = true __apps.voice.status.on = true")
        self.assertIn("Passed on to Voice", self.slash(s, "voice how are you"))
        self.assertEqual(log(s)[-1], "say voice how are you")
        self.assertIn("Bot takes no commands", self.slash(s, "bot hello"))
        w = s.g("WuxianKitWindow")
        self.assertIsNone(w)
        self.slash(s, "bot")
        w = s.g("WuxianKitWindow")
        self.assertTrue(w[b"shown"])
        self.assertEqual(texts(w[b"body"])[0], "Bot")
        self.slash(s, "bot")                                                    # opens, never closes
        self.assertTrue(w[b"shown"])
        help = self.slash(s, "help")
        self.assertIn("Apps:", help)
        self.assertIn("/wk voice: Voice · mute, unmute, stop", help)
        self.assertIn("/wk bot: Bot", help)
        s.lua.execute(b"__ns.SetLanguage('zhCN')")
        self.assertIn("/wk voice：Voice · 静音、开声、停止", self.slash(s, "help"))
        self.assertIn("已告知「Voice」：静音", self.slash(s, "voice 静音"))
        self.assertIn("「Bot」不接受指令", self.slash(s, "bot 你好"))
        s.lua.execute(b"__apps.voice.say = false")
        self.assertIn("「Voice」的指令：静音、开声、停止", self.slash(s, "voice 唱歌"))
        s.lua.execute(b"local x = WuxianKit:Extension('mine', { title = 'Mine' }) "
                      b"x:Command('voice', function(self, rest) __mine = rest end)")
        s.run(0.1)
        before = len(log(s))
        self.slash(s, "voice mute")
        self.assertEqual((s.g("__mine"), len(log(s))), (b"mute", before))      # the extension's own command

    def test_the_core_page_draws_the_cores_options(self):
        """the core's page draws the options the core declares (称呼, 0.6) as rows like its language row (the title on
        the left, the box beside it, the hint under the box; no heading), changed as any extension's; with eight lines of
        history the page still fits the window"""
        s = start(self)
        s.lua.execute(b"WuxianKit:Extension('kit'):Option('nickname', { title = 'Nickname', kind = 'text', default = '', "
                      b"hint = 'How AI apps call you' })")
        for i in range(12):
            s.lua.execute(f"WuxianKit:Call('tune.cvar.set', {{ name = 'graphicsQuality', value = {i % 5 + 1} }}, "
                          f"{{ title = 'q' }})".encode())
            click(s.g("WuxianKitProposal")[b"run"])
        w = self.window(s, "kit")
        body = texts(w[b"body"])
        self.assertNotIn("Options", body)
        self.assertEqual(body[2:5], ["Language", "Nickname", "How AI apps call you"])
        edit = shown(w[b"edits"])[0]
        regions = {r[b"text"].decode(): r for r in w[b"body"][b"__regions"].values() if r[b"shown"] and r[b"text"]}
        self.assertEqual((edit[b"point"][4], regions["How AI apps call you"][b"point"][4]), (76, 76))
        self.assertEqual(sum(1 for t in body if t.startswith("#")), 8)
        shown_regions = [r for r in w[b"body"][b"__regions"].values() if r[b"shown"]]
        self.assertLessEqual(max(-r[b"point"][5] + 14 for r in shown_regions), 404)   # inside the page
        type_into(edit, "Tim")
        self.assertEqual(s.lua.eval(b"WuxianKit:Extension('kit'):Get('nickname')"), b"Tim")
        s.lua.execute(b"__ns.SetLanguage('zhCN')")
        self.assertEqual(texts(w[b"body"])[2], "语言")


if __name__ == "__main__":
    unittest.main()
