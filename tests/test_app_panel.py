"""The app card (0.6, Core/UI/AppPanel.lua) under Lua 5.1 in the mock client: WuxianKit:AppPanel draws an app's card from
what the apps' ns functions answer (faked here on the core's private table), its state line through every state (no
无限工坊 link, its extension off, its check's reason, running but waiting, running, ready), the connect, stop and control
buttons (one of its own by its cmd when its label could be taken for another control), its options with the window's
controls, an agent's texts escaped, and the redraws on the bus and every few seconds."""
import unittest

from kitmock import Session, click, lupa, py, texts, type_into

# Core/Apps/Api.lua's functions as the contract documents them, over __apps (id -> { decl, by, addon, status (with
# waiting, hear), controls, labels (cmd -> label; none: "x" .. cmd), options, say, temp, hidden, local }); what the card
# did goes to __log
FAKES = """
local ns = ...
__ns = ns
__apps, __order, __log = {}, {}, {}
local function Log(s) __log[#__log + 1] = s end
function __add(id, t)
	t.decl = t.decl or {}
	t.status = t.status or { app = id, on = false }
	t.controls = t.controls or {}
	__apps[id] = t
	__order[#__order + 1] = id
end
function ns.AppList()
	local out = {}
	for _, id in ipairs(__order) do
		local t = __apps[id]
		if t then
			out[#out + 1] = { id = id, title = t.decl.title, by = t.by or "addon", addon = t.addon,
				extension = t.decl.extension, on = t.status.on or false,
				ends = t.status.ends, present = t.status.present, prompt = t.decl.prompt,
				start = t.decl.prompt and t.decl.prompt:match("^[%w_%-]+$") and ("Start " .. t.decl.prompt) or nil,
				temp = t.temp or false, hidden = t.hidden, ["local"] = t["local"], waiting = t.status.waiting }
		end
	end
	return out
end
function ns.App(id) local t = __apps[id] return t and { decl = t.decl } or nil end
function ns.AppStatus(id) return __apps[id] and __apps[id].status end
function ns.AppStop(id, why)
	Log("stop " .. id .. " " .. why)
	__apps[id].status.on = false
	WuxianKit:Emit("kit.app", { app = id, on = false, why = why })
end
function ns.AppOptionList(id) return __apps[id] and __apps[id].options end
function ns.SetAppOption(id, name, v)
	local o = __apps[id] and __apps[id].options and __apps[id].options[name]
	if not o then return false end
	Log("option " .. id .. " " .. name .. " " .. tostring(v))
	o.value = v
	return true, v
end
function ns.AppControls(id)
	local out = {}
	local labels = __apps[id] and __apps[id].labels or {}
	for i, c in ipairs(__apps[id] and __apps[id].controls or {}) do out[i] = { cmd = c, label = labels[c] or "x" .. c } end
	return out
end
function ns.ForgetApp(id, wipe)
	Log("forget " .. id .. (wipe and " wipe" or ""))
	__apps[id] = nil
	return true
end
function WuxianKit:AppControl(id, cmd)
	Log("control " .. id .. " " .. cmd)
	local on = __apps[id] and __apps[id].status.on or false
	if on and cmd == "stop" then ns.AppStop(id, "player") end
	return on
end
function WuxianKit:AppSay(id, text)
	Log("say " .. id .. " " .. text)
	return __apps[id] and __apps[id].say and __apps[id].status.on and true or false
end
__online = true
function WuxianKit:AgentOnline() return __online end
__ctrl = false
function IsControlKeyDown() return __ctrl end
getmetatable(UIParent).HighlightText = function(self, a, b) self.highlighted = not (a == 0 and b == 0) end
"""

GLYPHS = "›»▸▶■✓✗"


def lua_str(text):
    """text as a Lua string literal"""
    return '"' + text.replace("\\", "\\\\").replace('"', '\\"') + '"'


def start(test, **kw):
    s = Session(test, **kw)
    s.login()
    s.run(1)
    s.lua.execute(FAKES.encode(), s.ns)
    test.addCleanup(lambda: test.assertEqual(s.errors(), []))
    return s


def shown(pool):
    return [pool[i] for i in range(1, len(pool) + 1) if pool[i][b"shown"]]


def labels(frame):
    return [b[b"label"][b"text"].decode() for b in shown(frame[b"buttons"])]


def button(frame, label):
    return next(b for b in shown(frame[b"buttons"]) if b[b"label"][b"text"].decode() == label)


def log(s):
    return py(s.g("__log")) or []


@unittest.skipIf(lupa is None, "lupa (Lua 5.1 for Python) is not installed")
class AppPanel(unittest.TestCase):
    def panel(self, s, app, width=320):
        s.lua.execute(f"__host = __host or CreateFrame('Frame', nil, UIParent) "
                      f"__p = WuxianKit:AppPanel({app!r}, __host, {width})".encode())
        return s.g("__p")

    def redraw(self, s):
        s.lua.execute(b"__p:Refresh()")
        return texts(s.g("__p"))

    def ink(self, s, fs, name):
        want = py(s.lua.eval(f"WuxianKit.Skin.C.{name}".encode()))
        self.assertEqual([round(x, 3) for x in py(fs[b"color"])], [round(x, 3) for x in want])

    def first(self, p):
        return next(r for r in p[b"__regions"].values() if r[b"kind"] == b"FontString" and r[b"shown"] and r[b"text"])

    def test_the_states(self):
        """the state line is the first that holds: no link, its extension off, its check's reason (the status's, else
        its check asked), running (here until, last answer, said today), ready; each in its colour"""
        s = start(self)
        s.lua.execute("""
			WuxianKit:Extension('guildx', { title = 'Guild X' })
			__reason = nil
			__add('guild', { addon = 'WuxianGuild', decl = { title = 'Guild chat', prompt = 'guild-chat', extension = 'guildx',
				controls = { 'stop' }, check = function() return __reason end }, controls = { 'stop' } })
		""".encode())
        st = s.g("__apps")[b"guild"][b"status"]
        s.lua.execute(b"__online = false")
        p = self.panel(s, "guild")
        self.assertEqual(p[b"w"], 320)
        self.assertEqual(texts(p)[:2], ["Wuxian Workshop not connected",
                                       "Open the Wuxian Workshop app; keep the game in front or windowed"])
        self.ink(s, self.first(p), "gold")
        self.assertEqual(labels(p), ["Hand to AI"])
        self.assertFalse(button(p, "Hand to AI")[b"primary"])
        s.lua.execute(b"__online = true __ns.Switch('guildx', false)")
        self.assertEqual(self.redraw(s)[:2], ["Extension Guild X is off", "Turn it on to connect"])
        click(button(p, "Open its page"))                                       # the extension's page in the window
        w = s.g("WuxianKitWindow")
        self.assertTrue(w[b"shown"])
        self.assertIn("Guild X", texts(w[b"body"]))
        s.lua.execute(b"__ns.Switch('guildx', true)")
        st[b"blocked"] = b"You are not in a guild"
        self.assertEqual(self.redraw(s)[0], "You are not in a guild")
        self.ink(s, self.first(p), "muted")
        st[b"blocked"] = None
        s.lua.execute(b"__reason = 'No guild yet'")                            # none in the status: its check
        self.assertEqual(self.redraw(s)[0], "No guild yet")
        s.lua.execute(b"__reason = nil")
        self.assertEqual(self.redraw(s), ["Ready to connect an agent"])
        self.ink(s, self.first(p), "sky")
        self.assertEqual(labels(p), ["Hand to AI"])                              # no connect: the start line only
        self.assertTrue(button(p, "Hand to AI")[b"primary"])
        click(button(p, "Hand to AI"))
        f = s.g("WuxianKitCopyWindow")
        self.assertEqual((f[b"shown"], f[b"edit"][b"text"], texts(f)[0]), (True, b"Start guild-chat", "Guild chat"))
        now = int(s.lua.eval(b"time()"))
        st[b"on"], st[b"ends"], st[b"said"] = True, now + 3600, 2
        hhmm = s.lua.eval(f"date('%H:%M', {now + 3600})".encode()).decode()
        self.assertEqual(self.redraw(s)[0], f"Agent here until {hhmm} · Agent has not answered yet · Said today: 2")
        self.ink(s, self.first(p), "ok")
        self.assertEqual(labels(p), ["Stop"])                                   # no hand, stop once
        st[b"seen"] = now - 30
        self.assertIn("Last answer just now", self.redraw(s)[0])
        st[b"seen"] = now - 600
        self.assertIn("Last answer 10 min ago", self.redraw(s)[0])
        st[b"present"] = False
        self.assertEqual(self.redraw(s)[0], "Agent has left · Last answer 10 min ago · Said today: 2")
        self.ink(s, self.first(p), "gold")
        st[b"present"] = None
        s.lua.execute(b"__ns.SetLanguage('zhCN')")
        self.assertEqual(self.redraw(s)[0], f"Agent 在场至 {hhmm} · 最近应答 10 分钟前 · 今天发言 2 条")
        self.assertEqual(labels(p), ["停止"])
        click(button(p, "停止"))
        self.assertEqual(log(s), ["control guild stop", "stop guild player"])
        self.assertEqual(texts(p), ["可以接入 Agent"])                           # redrawn at once
        self.assertEqual(labels(p), ["交给 AI"])
        click(button(p, "交给 AI"))
        self.assertIn("按 Ctrl+C 复制，粘贴到 AI 对话里", texts(s.g("WuxianKitCopyWindow")))
        s.lua.execute(b"__online = false")
        self.assertEqual(self.redraw(s)[:2], ["无限工坊未连接", "打开无限工坊 App，游戏保持在前台或窗口模式"])
        s.lua.execute(b"__online = true __ns.Switch('guildx', false)")
        self.assertEqual(self.redraw(s)[:2], ["扩展「Guild X」未启用", "启用后才能接入"])
        s.lua.execute(b"__ns.Switch('guildx', true)")
        st[b"on"], st[b"present"] = True, False
        self.assertEqual(self.redraw(s)[0], "Agent 已离开 · 最近应答 10 分钟前 · 今天发言 2 条")
        st[b"seen"] = None
        self.assertIn("Agent 尚未应答", self.redraw(s)[0])

    def test_controls_and_options(self):
        """a running app's controls are buttons (stop once) through Kit:AppControl; its options are drawn with the
        window's controls, the core's first, and a change goes to ns.SetAppOption; nil for no such app"""
        s = start(self)
        s.lua.execute("""
			__add('voice', { decl = { title = 'Voice', controls = { 'mute', 'unmute', 'stop' }, pace = true },
				controls = { 'mute', 'unmute', 'stop' }, status = { app = 'voice', on = true, said = 0 },
				options = {
					topics = { title = 'Topics', kind = 'list', value = { 'a', 'b' } },
					quiet = { title = 'Quiet hours', kind = 'text', value = '01:00-08:00', hint = 'Like 01:00-08:00' },
					activity = { title = 'Activity', kind = 'choice', value = 'normal', choices = {
						{ value = 'quiet', label = 'Quiet' }, { value = 'normal', label = 'Normal' },
						{ value = 'lively', label = 'Lively' } } },
					loud = { title = 'Loud', kind = 'boolean', value = false },
					vol = { title = 'Volume', kind = 'number', value = 3, unit = 'steps', min = 0, max = 10 },
				} })
		""".encode())
        p = self.panel(s, "voice")
        self.assertEqual(labels(p), ["Stop", "Mute", "Unmute", "Quiet", "Normal", "Lively"])
        click(button(p, "Mute"))
        self.assertEqual(log(s), ["control voice mute"])
        shown_texts = texts(p)
        order = [shown_texts.index(t) for t in ("Options", "Activity", "Quiet hours", "Like 01:00-08:00", "Topics",
                                                "Separate with commas", "Volume", "steps")]
        self.assertEqual(order, sorted(order))                                  # the core's first, then by name
        checks = {c[b"label"][b"text"].decode(): c for c in shown(p[b"checks"])}
        self.assertEqual(list(checks), ["Loud"])
        self.assertTrue(button(p, "Normal")[b"primary"])
        click(button(p, "Lively"))
        self.assertTrue(button(p, "Lively")[b"primary"])
        self.assertFalse(button(p, "Normal")[b"primary"])
        click(checks["Loud"])
        edits = shown(p[b"edits"])
        self.assertEqual([e[b"text"].decode() for e in edits], ["01:00-08:00", "a, b", "3"])
        type_into(edits[1], "c， d")
        type_into(edits[2], "7")
        self.assertEqual(log(s)[1:], ["option voice activity lively", "option voice loud true",
                                      "option voice topics c， d", "option voice vol 7"])
        self.assertGreater(p[b"h"], 200)
        s.lua.execute(b"__ns.SetLanguage('zhCN')")
        s.lua.execute(b"__p:Refresh()")
        self.assertEqual(labels(p)[:3], ["停止", "静音", "开声"])
        self.assertIn("选项", texts(p))
        for code in (b"WuxianKit:AppPanel('nope', UIParent)", b"WuxianKit:AppPanel(nil, UIParent)"):
            self.assertIsNone(s.lua.eval(code), code)
        self.assertEqual(s.lua.eval(b"WuxianKit:AppPanel('voice', CreateFrame('Frame')).w"), 300)   # no width: 300
        s.lua.execute(b"__apps.voice.options = nil __p:Refresh()")
        self.assertNotIn("选项", texts(p))
        self.assertTrue(all(not set(GLYPHS) & set(t) for t in texts(p)))

    def test_waiting(self):
        """an app that runs but waits for what it hears to be there (its addon has not loaded) says so and why, in
        gold with a hint, not that the agent is here; the reason is the status's, else the row's: the runtime's own
        sentence (Core/Apps/Run.lua's), shown as it is, never put together again here; its stop is there"""
        s = start(self)
        s.lua.execute(b"__add('quest', { by = 'agent', decl = { title = 'Quest' }, controls = { 'stop' }, "
                      b"status = { app = 'quest', on = true, said = 0, waiting = 'Needs the source rxp' } })")
        p = self.panel(s, "quest")
        self.assertEqual(texts(p), ["Waiting · Needs the source rxp", "Starts by itself once ready"])
        self.ink(s, self.first(p), "gold")
        self.assertEqual(labels(p), ["Stop"])
        st = s.g("__apps")[b"quest"][b"status"]
        for why, line in (("Needs the state guild:roster", "Waiting · Needs the state guild:roster"),
                          ("source rxp", "Waiting · source rxp"),                       # (no words of its own for any)
                          ("extension", "Waiting · extension"),
                          ("Its addon is |cffff0000late|r", "Waiting · Its addon is ||cffff0000late||r"),
                          (True, "Waiting")):
            st[b"waiting"] = why if why is True else why.encode()
            self.assertEqual(self.redraw(s)[0], line)
        s.lua.execute(b"__ns.SetLanguage('zhCN')")
        st[b"waiting"] = "需要来源「rxp」".encode()
        self.assertEqual(self.redraw(s), ["等待中 · 需要来源「rxp」", "就绪后自动开始"])
        st[b"waiting"] = "所属扩展「guide」未载入".encode()
        self.assertEqual(self.redraw(s)[0], "等待中 · 所属扩展「guide」未载入")
        s.lua.execute(b"__ns.SetLanguage('enUS')")
        st[b"waiting"] = None                                                   # it hears now
        self.assertTrue(self.redraw(s)[0].startswith("Agent here"))
        st[b"on"], st[b"waiting"] = False, b"Needs the source rxp"              # not running: nothing waits
        self.assertEqual(self.redraw(s)[0], "Ready to connect an agent")
        s.lua.execute(b"__online = false")
        st[b"on"] = True
        self.assertEqual(self.redraw(s)[0], "Wuxian Workshop not connected")    # the earlier states hold first

    def test_a_control_whose_label_names_another(self):
        """one of its own controls is drawn by its cmd, not its label, when the label is a word of the core's (离开 is
        stop), another control's cmd, or another's label too; its button gives its own cmd, never stop"""
        s = start(self)
        s.lua.execute("""
			__add('tricky', { decl = { title = 'Tricky' }, status = { app = 'tricky', on = true },
				controls = { 'stop', 'brief', 'recap', 'again', 'echo', 'wave', 'nod' },
				labels = { brief = '离开', recap = 'Stop', again = 'Same', echo = 'same', wave = 'brief', nod = 'Nod!' } })
		""".encode())
        p = self.panel(s, "tricky")
        self.assertEqual(labels(p), ["Stop", "brief", "recap", "again", "echo", "wave", "Nod!"])
        for label, cmd in (("brief", "brief"), ("recap", "recap"), ("wave", "wave"), ("Nod!", "nod")):
            click(button(p, label))
            self.assertEqual(log(s)[-1], "control tricky " + cmd)
        self.assertNotIn("stop tricky player", log(s))
        s.lua.execute(b"__ns.SetLanguage('zhCN')")
        self.redraw(s)
        self.assertEqual(labels(p), ["停止", "brief", "recap", "again", "echo", "wave", "Nod!"])

    def test_an_agents_texts_are_escaped(self):
        """an app an agent declared shows its title, check reason and options' texts as they are (no colour code takes
        effect); a prompt that is not a skill's name gives no start line, no 交给 AI"""
        s = start(self)
        s.lua.execute("""
			__add('bot', { by = 'agent', decl = { title = '|cffff0000Bot|r', prompt = 'x y|r' },
				status = { app = 'bot', on = false, blocked = 'not |Hitem:1|h now' },
				options = { tone = { title = 'Tone |cff00ff00green|r', kind = 'choice', value = 'a',
					choices = { { value = 'a', label = '|cffA|r' } } } } })
		""".encode())
        p = self.panel(s, "bot")
        shown_texts = texts(p)
        self.assertEqual(shown_texts[0], "not ||Hitem:1||h now")
        self.assertIn("Tone ||cff00ff00green||r", shown_texts)
        self.assertEqual(labels(p), ["||cffA||r"])                              # the choice; no 交给 AI
        self.assertEqual(py(s.lua.eval(b"__ns.UI.Apps()[1].title")), "||cffff0000Bot||r")

    def test_hand_to_ai(self):
        """an app with a start line has 交给 AI (primary when ready; no connect button): the copy box with the app's
        title, the start line selected with the keyboard in it, how to copy it under it; what is typed goes back to
        the line, selected again; focus selects it; Esc, Enter, the close button and Ctrl+C close it; none while it
        runs, none without a start line; an agent's title escaped above it, the line as it is"""
        s = start(self)
        line = 'Start the app "Guild chat": first call wk_docs with {"skill": "guild-chat"}.'
        s.lua.execute(("__add('guild', { decl = { title = 'Guild chat', prompt = 'guild-chat' }, "
                       "status = { app = 'guild', on = false, start = %s } })" % lua_str(line)).encode())
        p = self.panel(s, "guild")
        self.assertEqual(labels(p), ["Hand to AI"])
        self.assertTrue(button(p, "Hand to AI")[b"primary"])
        f = s.g("WuxianKitCopyWindow")
        self.assertIsNone(f)
        click(button(p, "Hand to AI"))
        f = s.g("WuxianKitCopyWindow")
        edit = f[b"edit"]
        self.assertEqual((f[b"shown"], edit[b"text"].decode(), edit[b"focus"], edit[b"highlighted"]),
                         (True, line, True, True))
        self.assertEqual(texts(f)[:2], ["Guild chat", "Press Ctrl+C to copy, then paste it into your AI chat"])
        self.assertNotIn("Ctrl+C to copy", texts(f))
        edit[b"highlighted"] = False
        edit.SetText(edit, b"something else")                                  # typed: the line comes back
        edit[b"scripts"][b"OnTextChanged"](edit, True)
        self.assertEqual((edit[b"text"].decode(), edit[b"highlighted"]), (line, True))
        edit[b"highlighted"] = False
        edit[b"scripts"][b"OnEditFocusGained"](edit)
        self.assertTrue(edit[b"highlighted"])
        edit[b"scripts"][b"OnEnterPressed"](edit)
        self.assertFalse(f[b"shown"])
        self.assertFalse(edit[b"focus"])
        click(button(p, "Hand to AI"))
        edit[b"scripts"][b"OnEscapePressed"](edit)
        self.assertFalse(f[b"shown"])
        click(button(p, "Hand to AI"))
        click(f[b"close"])
        self.assertFalse(f[b"shown"])
        click(button(p, "Hand to AI"))
        s.lua.execute(b"__ctrl = true")
        edit[b"scripts"][b"OnKeyDown"](edit, b"C")
        self.assertIn("Copied", texts(f))
        s.run(0.5)
        self.assertFalse(f[b"shown"])
        s.lua.execute(b"__ctrl = false __ns.SetLanguage('zhCN') __p:Refresh()")
        self.assertEqual(labels(p), ["交给 AI"])
        click(button(p, "交给 AI"))
        self.assertEqual(texts(f)[:2], ["Guild chat", "按 Ctrl+C 复制，粘贴到 AI 对话里"])
        edit[b"scripts"][b"OnEscapePressed"](edit)
        s.lua.execute(b"__ns.SetLanguage('enUS')")
        st = s.g("__apps")[b"guild"][b"status"]
        st[b"on"] = True                                                        # running: no hand
        self.redraw(s)
        self.assertEqual(labels(p), ["Stop"])
        st[b"on"] = False
        s.lua.execute(b"__add('plain', { decl = { title = 'Plain' } })")              # no prompt, no start line: none
        self.assertEqual(labels(self.panel(s, "plain")), [])
        s.lua.execute(("__add('bot', { by = 'agent', decl = { title = '|cffff0000Bot|r', prompt = 'bot-run' }, "
                       "status = { app = 'bot', on = false, start = %s } })" % lua_str("Start |cffBot|r")).encode())
        p = self.panel(s, "bot")
        click(button(p, "Hand to AI"))
        self.assertEqual(texts(f)[0], "||cffff0000Bot||r")
        self.assertEqual(f[b"edit"][b"text"].decode(), "Start |cffBot|r")

    def test_an_app_without_a_prompt(self):
        """an app without a prompt has no main button (no 交给 AI, no 开始), whatever else its row says; running, its
        stop and controls as any app's"""
        s = start(self)
        s.lua.execute(b"__add('voice', { by = 'agent', controls = { 'mute', 'stop' }, launch = true, "
                      b"decl = { title = 'Voice', driver = 'program' } })")
        st = s.g("__apps")[b"voice"][b"status"]
        p = self.panel(s, "voice")
        self.assertEqual(texts(p), ["Ready to connect an agent"])
        self.ink(s, self.first(p), "sky")
        self.assertEqual(labels(p), [])
        st[b"on"], st[b"said"] = True, 0
        self.assertTrue(self.redraw(s)[0].startswith("Agent here"))
        self.assertEqual(labels(p), ["Stop", "Mute"])
        st[b"on"] = False
        s.lua.execute(b"__online = false")
        self.assertEqual(self.redraw(s), ["Wuxian Workshop not connected", "Open the Wuxian Workshop app; keep the game "
                                          "in front or windowed"])
        self.assertEqual(labels(p), [])
        s.lua.execute(b"__online = true __ns.SetLanguage('zhCN')")
        self.assertEqual(self.redraw(s), ["可以接入 Agent"])
        self.assertEqual(labels(p), [])
        self.assertTrue(all(not set(GLYPHS) & set(t) for t in texts(p) + labels(p)))

    def test_a_temporary_app(self):
        """a temporary app (an agent's, kept in memory only) has no 交给 AI; running, its stop as any app's"""
        s = start(self)
        s.lua.execute(b"__add('peek', { by = 'agent', decl = { title = 'Peek', prompt = 'peek-run' }, temp = true })")
        p = self.panel(s, "peek")
        self.assertEqual(texts(p), ["Ready to connect an agent"])
        self.assertEqual(labels(p), [])
        s.g("__apps")[b"peek"][b"status"][b"on"] = True
        self.redraw(s)
        self.assertEqual(labels(p), ["Stop"])
        self.assertEqual(py(s.lua.eval(b"__ns.UI.Apps()[1].temp")), True)

    def test_redraws(self):
        """a card redraws a moment after kit.app, kit.option, kit.changed or app.<id>, and every few seconds while it
        shows (the minutes since the last answer); a hidden one waits"""
        s = start(self)
        s.lua.execute(b"__add('voice', { decl = { title = 'Voice' } })")
        p = self.panel(s, "voice")
        st = s.g("__apps")[b"voice"][b"status"]
        now = int(s.lua.eval(b"time()"))
        st[b"on"], st[b"ends"], st[b"seen"] = True, now + 600, now - 61
        for topic in ("kit.app", "kit.option", "kit.changed", "app.voice"):
            st[b"said"] = len(topic)
            s.lua.execute(f"WuxianKit:Emit({topic!r}, {{ app = 'voice' }})".encode())
            s.run(0.1)
            self.assertIn(f"Said today: {len(topic)}", texts(p)[0], topic)
        self.assertIn("Last answer 1 min ago", texts(p)[0])
        s.run(65)                                                               # no event: the clock redraws it
        self.assertIn("Last answer 2 min ago", texts(p)[0])
        s.lua.execute(b"__host:Hide()")
        s.run(65)
        self.assertIn("Last answer 2 min ago", texts(p)[0])
        s.lua.execute(b"__host:Show()")
        s.run(5)
        self.assertIn("Last answer 3 min ago", texts(p)[0])


if __name__ == "__main__":
    unittest.main()
