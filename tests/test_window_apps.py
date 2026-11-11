"""The window's apps (0.6, Core/UI/Window.lua) under Lua 5.1 in the mock client, over the apps' ns functions faked as in
test_app_panel: no list of apps, an app's card on the page of what it came with (its addon's row here; an extension's
and a local extension's in test_window_rows), the row marked while its app runs, the window first open on the first
such row; only an agent's own app a row (the last group, its page with remove; a temporary one marked), redrawn when
apps change; /wk <app> [words] (its controls, its words, what it takes, the page its card is on), /wk help, /wk's own
words (ns.SLASH_WORDS) before any other's; and the core's page drawing the core's own options (称呼, 0.6)."""
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

    def titles(self, w):
        return [b[b"label"][b"text"].decode() for b in shown(w[b"items"])]

    def pills(self, w):
        """the page's capsules that show: its kind, where it runs"""
        return [p[b"text"][b"text"].decode() for p in (w[b"pill"], w[b"where"]) if p[b"shown"]]

    def test_the_rows(self):
        """no app is a row: an addon's app is on its addon's row (已添加, in the game), the row with a dot while it
        runs; an agent's own is a row in the last group, there only then; a hidden one nowhere but the core's last
        lines; an app's page is found by its id; a new app shows once kit.app tells of it"""
        s = self.setup()
        s.lua.execute(b"__add('pipe', { by = 'agent', temp = true, hidden = true, decl = { title = 'Pipe' }, "
                      b"status = { app = 'pipe', on = true } })")
        w = self.window(s)
        self.assertEqual(texts(w[b"list"]), ["Built-in", "Added", "Agent apps"])
        titles = self.titles(w)
        self.assertEqual((titles[0], titles[-2:]), ("Framework", ["WxVoice", "Bot"]))
        for app in ("Voice", "Pipe", "pipe"):
            self.assertNotIn(app, titles)
        voice, bot = self.item(w, "WxVoice"), self.item(w, "Bot")
        self.assertEqual((voice[b"state"][b"text"], voice[b"state"][b"shown"], bot[b"state"][b"shown"]),
                         (b"Game", True, False))
        self.assertEqual((voice[b"dot"][b"shown"], bot[b"dot"][b"shown"]), (True, False))   # Voice runs
        self.assertEqual(py(voice[b"dot"][b"rgb"]), py(s.lua.eval(b"WuxianKit.Skin.C.ok")))
        core = self.item(w, "Framework")
        self.assertEqual((core[b"state"][b"shown"], core[b"dot"][b"shown"]), (False, False))
        self.assertEqual(texts(w[b"body"])[-2:], ["Background listeners", "pipe"])   # the core's page: what listens
        click(voice)
        body = texts(w[b"body"])
        self.assertEqual(body[:2], ["WxVoice", "App · Voice"])
        self.assertEqual(self.pills(w), ["Added", "Game"])
        self.assertTrue(body[2].startswith("Agent here"))
        self.assertNotIn("Background listeners", body)
        self.assertEqual(labels(w), ["Stop", "Mute", "Unmute"])                 # the card's; an addon's: no remove
        click(button(w, "Mute"))
        self.assertEqual(log(s), ["control voice mute"])
        click(bot)
        self.assertEqual(texts(w[b"body"])[:3], ["Bot", "Declared by an agent", "Ready to connect an agent"])
        self.assertEqual(self.pills(w), ["App"])
        self.assertEqual(labels(w), ["Hand to AI", "Remove"])
        click(button(w, "Remove"))
        self.assertEqual(log(s)[-1], "forget bot wipe")                         # the player's remove: all of it
        self.assertEqual(texts(w[b"body"])[0], "WxVoice")                       # gone: the first whose app runs
        self.assertNotIn("Bot", self.titles(w))
        self.assertEqual(texts(w[b"list"]), ["Built-in", "Added"])              # the last group: gone with it
        s.lua.execute(b"__add('later', { addon = 'WxVoice', decl = { title = 'Later' } }) "
                      b"WuxianKit:Emit('kit.app', { app = 'later', on = true })")
        s.run(0.1)
        self.assertIn("App · Later", texts(w[b"body"]))                         # the addon's second app: the same page
        self.assertEqual(self.titles(w).count("WxVoice"), 1)
        s.lua.execute(b"__ns.SetLanguage('zhCN')")
        self.assertEqual(texts(w[b"list"]), ["内置", "已添加"])
        self.assertEqual(self.item(w, "WxVoice")[b"state"][b"text"].decode(), "游戏")
        self.assertEqual(texts(w[b"body"])[1], "应用 · Voice")
        self.assertEqual(self.pills(w), ["已添加", "游戏"])
        self.window(s, "kit")
        self.assertEqual(texts(w[b"body"])[0], "扩展框架")
        self.window(s, "voice")                                                 # an app's id: the page its card is on
        self.assertEqual(texts(w[b"body"])[:2], ["WxVoice", "应用 · Voice"])
        s.lua.execute(b"WuxianKit:Extension('voice', { title = 'Voice ext' })")   # an extension of the same name first
        self.window(s, "voice")
        self.assertEqual(texts(w[b"body"])[0], "Voice ext")
        self.window(s, "app:voice")
        self.assertEqual(texts(w[b"body"])[0], "WxVoice")
        self.window(s, "nothing-of-the-kind")                                   # not there: the page it showed
        self.assertEqual(texts(w[b"body"])[0], "WxVoice")

    def test_the_first_page(self):
        """the window first opens on the first row whose app runs, its item marked; later on the page it showed last;
        with no app that runs, on the core's"""
        s = self.setup()
        self.slash(s, "")
        w = s.g("WuxianKitWindow")
        self.assertEqual(texts(w[b"body"])[:2], ["WxVoice", "App · Voice"])
        gold = py(s.lua.eval(b"WuxianKit.Skin.C.goldSoft"))
        marked = [b[b"label"][b"text"].decode() for b in shown(w[b"items"]) if py(b[b"bg"][b"rgb"]) == gold]
        self.assertEqual(marked, ["WxVoice"])
        click(self.item(w, "Framework"))
        self.slash(s, "")                                                       # closed
        self.assertFalse(w[b"shown"])
        self.slash(s, "")
        self.assertEqual(texts(w[b"body"])[0], "Framework")
        idle = start(self)
        idle.lua.execute(b"__add('bot', { by = 'agent', decl = { title = 'Bot', prompt = 'bot-run' } })")
        idle.g("SlashCmdList")[b"WUXIANKIT"](b"")                               # an app, but none that runs
        self.assertEqual(texts(idle.g("WuxianKitWindow")[b"body"])[0], "Framework")
        bare = start(self)
        bare.g("SlashCmdList")[b"WUXIANKIT"](b"")
        self.assertEqual(texts(bare.g("WuxianKitWindow")[b"body"])[0], "Framework")
        self.assertEqual(texts(bare.g("WuxianKitWindow")[b"list"]), ["Built-in"])

    def test_an_agents_apps_page(self):
        """an app an agent declared without a prompt: its page says an agent declared it, no main button (no 开始); a
        temporary app's capsule and its row say so; /wk <app> 开始|start is words like any other"""
        s = self.setup()
        s.lua.execute(b"__add('buddy', { by = 'agent', launch = true, controls = { 'mute', 'stop' }, "
                      b"decl = { title = 'Buddy', driver = 'program' } }) "
                      b"__add('peek', { by = 'agent', decl = { title = 'Peek', prompt = 'peek-run' }, temp = true, "
                      b"status = { app = 'peek', on = true, said = 0 } })")
        w = self.window(s, "buddy")
        self.assertEqual(texts(w[b"body"])[:3], ["Buddy", "Declared by an agent", "Ready to connect an agent"])
        self.assertEqual(self.pills(w), ["App"])
        self.assertEqual(labels(w), ["Remove"])
        buddy, peek = self.item(w, "Buddy"), self.item(w, "Peek")
        self.assertEqual((buddy[b"state"][b"shown"], buddy[b"dot"][b"shown"]), (False, False))
        self.assertEqual((peek[b"state"][b"text"], peek[b"dot"][b"shown"]), (b"Temporary", True))
        click(peek)
        self.assertEqual(texts(w[b"body"])[:2], ["Peek", "Declared by an agent"])
        self.assertEqual(self.pills(w), ["Temporary"])
        self.assertEqual(labels(w), ["Stop", "Remove"])
        s.lua.execute(b"__ns.SetLanguage('zhCN')")
        self.assertEqual(self.pills(w), ["临时"])
        self.assertEqual(texts(w[b"list"])[-1], "Agent 应用")
        self.assertEqual(self.item(w, "Peek")[b"state"][b"text"].decode(), "临时")
        click(self.item(w, "Buddy"))
        self.assertEqual(texts(w[b"body"])[1:3], ["Agent 声明", "可以接入 Agent"])
        self.assertEqual(self.pills(w), ["应用"])
        s.lua.execute(b"__ns.SetLanguage('enUS')")
        self.assertIn("Buddy takes: mute, stop", self.slash(s, "buddy start"))
        self.assertIn("/wk buddy: Buddy · mute, stop", self.slash(s, "help"))
        s.lua.execute(b"__ns.SetLanguage('zhCN')")
        self.assertIn("「Buddy」的指令：静音、停止", self.slash(s, "buddy 开始"))
        self.assertEqual(log(s), ["say buddy start", "say buddy 开始"])            # words, as any (it takes none)

    def test_the_page_ticks(self):
        """a page with an app's card is drawn again every few seconds while the window shows it"""
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
        s.lua.execute(b"__add('helper', { decl = { title = 'Helper' }, controls = { 'mute', 'brief' }, "
                      b"status = { app = 'helper', on = true } })")
        self.assertIn("Told Helper: xbrief", self.slash(s, "helper xbrief"))      # an own control, by its label
        self.assertEqual(log(s)[-1], "control helper brief")
        self.assertIn("Told Helper: xbrief", self.slash(s, "helper brief"))       # or its cmd
        self.assertIn("Helper takes: mute, brief", self.slash(s, "helper dance"))
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

    def test_the_words_of_the_slash_command(self):
        """ns.SLASH_WORDS is the set of /wk's own words, and each comes before an extension's command and an app's id
        of the same name (so neither takes it), whatever its case"""
        s = self.setup()
        words = s.lua.eval(b"(function() local t = {} for w, v in pairs(__ns.SLASH_WORDS) do assert(v == true) "
                           b"t[#t + 1] = w end table.sort(t) return table.concat(t, ' ') end)()")
        self.assertEqual(words, b"help lang no yes")
        s.lua.execute(b"local x = WuxianKit:Extension('mine', { title = 'Mine' }) __mine = {} "
                      b"for word in pairs(__ns.SLASH_WORDS) do "
                      b"  x:Command(word, function(self, rest) __mine[#__mine + 1] = word end, 'Mine ' .. word) "
                      b"  __add(word, { decl = { title = 'App ' .. word }, controls = { 'mute' }, say = true, "
                      b"    status = { app = word, on = true } }) "
                      b"end")
        s.run(0.1)
        self.assertIn("Apps:", self.slash(s, "help mute"))
        self.assertIn("Apps:", self.slash(s, "HELP"))
        self.assertNotIn("Mine help", self.slash(s, "help"))                    # a command no one can reach: not listed
        self.assertIn("/wk lang", self.slash(s, "lang mute"))                   # its usage
        self.slash(s, "lang zh")
        self.assertEqual(s.lua.eval(b"__ns.Lang()"), b"zhCN")
        self.slash(s, "lang en")
        self.assertIn("No proposal awaiting confirmation", self.slash(s, "yes mute"))
        self.assertIn("No pending proposals", self.slash(s, "no mute"))
        self.assertEqual((py(s.g("__mine")) or [], log(s)), ([], []))
        w = s.g("WuxianKitWindow")
        self.assertIsNone(w)                                                    # none opened an app's page either

    def test_a_label_that_names_another_control(self):
        """/wk <app> <word>: a word of the core's is the core's control (离开 and Stop are stop, whatever one of its
        own is labelled); one of its own answers to its cmd, and to its label only when that names nothing else"""
        s = self.setup()
        s.lua.execute("""
			__add('tricky', { addon = 'WxTricky', decl = { title = 'Tricky' }, status = { app = 'tricky', on = true },
				controls = { 'stop', 'brief', 'recap', 'again', 'echo', 'wave', 'nod' },
				labels = { brief = '离开', recap = 'Stop', again = 'Same', echo = 'same', wave = 'brief', nod = 'Nod!' } })
		""".encode())
        st = s.g("__apps")[b"tricky"][b"status"]
        for word in ("离开", "Stop", "停止", "stop"):
            st[b"on"] = True
            self.assertIn("Told Tricky: Stop", self.slash(s, "tricky " + word), word)
            self.assertEqual(log(s)[-2:], ["control tricky stop", "stop tricky player"], word)
        st[b"on"] = True
        self.assertIn("Told Tricky: brief", self.slash(s, "tricky brief"))      # its cmd: not the one labelled so
        self.assertEqual(log(s)[-1], "control tricky brief")
        self.assertIn("Told Tricky: Nod!", self.slash(s, "tricky Nod!"))
        self.assertEqual(log(s)[-1], "control tricky nod")
        self.assertIn("Told Tricky: echo", self.slash(s, "tricky ECHO"))
        self.assertEqual(log(s)[-1], "control tricky echo")
        usage = "Tricky takes: stop, brief, recap, again, echo, wave, nod"
        self.assertIn(usage, self.slash(s, "tricky Same"))                      # a label two have: neither's
        self.assertEqual(log(s)[-1], "say tricky Same")
        s.lua.execute(b"__ns.SetLanguage('zhCN')")
        self.assertIn("「Tricky」的指令：停止、brief、recap、again、echo、wave、Nod!", self.slash(s, "tricky 跳舞"))
        w = self.window(s, "tricky")
        self.assertEqual(labels(w), ["停止", "brief", "recap", "again", "echo", "wave", "Nod!"])

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
