"""The apps that run, told to WoWBridge's panel (0.10.0: its handle's Overview(rows); ARCHITECTURE section 7): a line
for each app that runs (its title, who drives the run: its local extension's program, an agent, or the addon that
started its own), the first six by when they started, a click that opens the window on the page the app's card is on;
no line for a hidden app; the lines given whole when they changed (a start, a stop, a declaration, the language, the
login) and not again when they did not, first (none) once the handle is bound; lines WoWBridge refuses break nothing
and are given again; with a handle that has no Overview (an older WoWBridge) nothing is done."""
import unittest

from kitmock import Session, lupa, py, texts
from test_app_reconcile import Case
from test_standalone import bridge

# handle:Overview as the contract has it: rows nil or an array of at most 6 { text (1-60 bytes), note? (at most 30),
# tone?, click? }, an error on any other; kept in __overviews, unless __refuse
PANEL = """
	__overviews = __overviews or {}
	if rows ~= nil and type(rows) ~= 'table' then error('rows is a table', 2) end
	rows = rows or {}
	local n = 0
	for _ in pairs(rows) do n = n + 1 end
	if n ~= #rows or n > 6 then error('rows is an array of at most 6', 2) end
	for _, r in ipairs(rows) do
		if type(r) ~= 'table' then error('a row is a table', 2) end
		if type(r.text) ~= 'string' or #r.text < 1 or #r.text > 60 then error('text is 1-60 bytes', 2) end
		if r.note ~= nil and (type(r.note) ~= 'string' or #r.note > 30) then error('note is at most 30 bytes', 2) end
		if r.tone ~= nil and r.tone ~= 'ok' and r.tone ~= 'warn' and r.tone ~= 'bad' then error('tone', 2) end
		if r.click ~= nil and type(r.click) ~= 'function' then error('click is a function', 2) end
	end
	if __refuse then error('refused', 2) end
	__overviews[#__overviews + 1] = rows
"""

LOCAL = "['local'] = { id = 'cocreate', title = 'Co-create' }"
DRIVEN = f"{{ app = 'cc', title = 'Data', {LOCAL}, driver = 'local', hear = {{ 'bus:demo.*' }}, lease = 0 }}"


@unittest.skipIf(lupa is None, "lupa (Lua 5.1 for Python) is not installed")
class Overview(Case):
    def start(self, s=None, **kw):
        if s is None:
            kw.setdefault("saved", {"WoWBridge": bridge("0.10.0", overview=PANEL)})
        return super().start(s, **kw)

    def given(self, s):
        """what WoWBridge was given, oldest first: each time the lines as (text, note)"""
        return [[(r["text"], r.get("note")) for r in rows] for rows in py(s.g("__overviews")) or []]

    def click(self, s, n):
        """the player clicks line n of the lines WoWBridge has; the window's page"""
        rows = s.g("__overviews")
        rows[len(rows)][n][b"click"]()
        w = s.g("WuxianKitWindow")
        self.assertTrue(w[b"shown"])
        return texts(w[b"body"])[0]

    def test_a_line_while_it_runs(self):
        s = self.start()
        self.assertEqual(self.given(s), [[]])                             # bound: no lines, told once
        self.agent(s, "kit.app.declare", "{ app = 'notes', title = 'Notes', hear = { 'bus:demo.*' } }")
        self.assertEqual(self.given(s), [[]])                             # declared is not running
        self.agent(s, "kit.app.open", "{ app = 'notes' }")
        self.assertEqual(self.given(s)[1:], [[("Notes", "Agent")]])
        self.agent(s, "kit.app.open", "{ app = 'notes', minutes = 30 }")  # it goes on: the same lines, not given again
        self.agent(s, "kit.app.status", "{ app = 'notes' }")
        s.lua.execute(b"WuxianKit:Emit('demo.a', 1)")
        s.run(5)
        self.assertEqual(len(self.given(s)), 2)
        self.agent(s, "kit.app.declare", "{ app = 'notes', title = 'Notes 2', hear = { 'bus:demo.*' } }")
        self.assertEqual(self.given(s)[2:], [[("Notes 2", "Agent")]])     # its title changed
        self.agent(s, "kit.app.stop", "{ app = 'notes' }")
        self.assertEqual(self.given(s)[3:], [[]])                         # none runs: no lines
        self.agent(s, "kit.app.open", "{ app = 'notes', minutes = 1 }")
        s.run(62)                                                         # its time is over
        self.assertEqual(self.given(s)[4:], [[("Notes 2", "Agent")], []])

    def test_who_drives_it(self):
        """本机端, Agent, 插件: its local extension's program; an agent (its own app, or an addon's it opened or
        joined); the addon that started its own"""
        s = self.start()
        self.agent(s, "kit.app.declare", DRIVEN)
        self.agent(s, "kit.app.open", "{ app = 'cc' }")
        s.run(1)
        self.opens(s, "{ app = 'bot', title = 'Bot' }")
        s.run(1)
        s.lua.execute(b"WuxianKit:App('mine', { title = 'Mine', hear = { 'bus:demo.*' } }) "
                      b"WuxianKit:App('theirs', { title = 'Theirs' })")
        self.call(s, "kit.app.open", "{ app = 'mine' }")                  # the addon starts its own
        s.run(1)
        self.agent(s, "kit.app.open", "{ app = 'theirs' }")               # an agent starts an addon's
        lines = [("Data", "Local"), ("Bot", "Agent"), ("Mine", "Addon"), ("Theirs", "Agent")]
        self.assertEqual(self.given(s)[-1], lines)
        s.ns.SetLanguage(b"zhCN")
        self.assertEqual(self.given(s)[-1], [("Data", "本机端"), ("Bot", "Agent"), ("Mine", "插件"), ("Theirs", "Agent")])
        s.ns.SetLanguage(b"enUS")
        told = len(self.given(s))
        self.agent(s, "kit.app.status", "{ app = 'mine' }")               # an agent is heard from: it drives it now
        self.assertEqual(self.given(s)[told:], [lines[:2] + [("Mine", "Agent"), ("Theirs", "Agent")]])
        self.agent(s, "kit.app.status", "{ app = 'mine' }")
        self.assertEqual(len(self.given(s)), told + 1)

    def test_six_lines_at_most_by_when_they_started(self):
        s = self.start()
        for i in range(1, 9):
            self.agent(s, "kit.app.declare", f"{{ app = 'a{i}', title = 'App {i}' }}")
        for i in range(8, 0, -1):                                         # started last declared first
            self.agent(s, "kit.app.open", f"{{ app = 'a{i}' }}")
            s.run(1)
        self.assertEqual([t for t, _ in self.given(s)[-1]], [f"App {i}" for i in (8, 7, 6, 5, 4, 3)])
        told = len(self.given(s))
        self.assertEqual(told, 7)                                         # the seventh and the eighth: no new lines
        self.agent(s, "kit.app.stop", "{ app = 'a8' }")                   # one of the six stops: the next moves up
        self.assertEqual([t for t, _ in self.given(s)[told:][0]], [f"App {i}" for i in (7, 6, 5, 4, 3, 2)])
        self.agent(s, "kit.app.stop", "{ app = 'a1' }")                   # one that had no line: nothing new
        self.assertEqual(len(self.given(s)), told + 1)

    def test_a_click_opens_the_page_its_card_is_on(self):
        s = self.start()
        s.lua.execute(b"WuxianKit:App('salon', { title = 'Salon', extension = 'tune' })")
        self.agent(s, "kit.app.open", "{ app = 'salon' }")                # an extension's app
        s.run(1)
        self.opens(s, "{ app = 'bot', title = 'Bot' }")                   # an agent's own
        s.run(1)
        self.agent(s, "kit.app.declare", DRIVEN)                          # a local extension's
        self.agent(s, "kit.app.open", "{ app = 'cc' }")
        self.assertEqual([t for t, _ in self.given(s)[-1]], ["Salon", "Bot", "Data"])
        self.assertIsNone(s.g("WuxianKitWindow"))
        tune = s.lua.eval(b"__ns.T(WuxianKit:Extension('tune').title)").decode()
        self.assertTrue(self.click(s, 1).startswith(tune))
        self.assertTrue(self.click(s, 2).startswith("Bot"))
        self.assertTrue(self.click(s, 3).startswith("Co-create"))
        s.g("WuxianKitWindow").Hide(s.g("WuxianKitWindow"))
        self.assertTrue(self.click(s, 2).startswith("Bot"))               # closed: open again, on that page

    def test_no_line_for_a_hidden_app(self):
        s = self.start()
        self.agent(s, "kit.app.open", "{ app = 'pipe', temp = { hidden = true, hear = { 'bus:demo.*' } } }")
        self.assertIs(self.status(s, "pipe")["on"], True)
        self.assertEqual(self.given(s), [[]])
        self.agent(s, "kit.app.open", "{ app = 'peek', temp = { title = 'Peek', hear = { 'bus:demo.*' } } }")
        self.assertEqual(self.given(s)[1:], [[("Peek", "Agent")]])        # a temporary one that is the player's: a line
        self.agent(s, "kit.app.stop", "{ app = 'peek' }")
        self.agent(s, "kit.app.stop", "{ app = 'pipe' }")
        self.assertEqual(self.given(s)[2:], [[]])

    def test_a_title_within_what_the_panel_takes(self):
        """60 bytes: cut on a character; plain text, as it was given: the panel (WoWBridge) escapes what it draws"""
        s = self.start()
        s.lua.execute(f"WuxianKit:App('long', {{ title = '{'字' * 30}' }})".encode())
        self.agent(s, "kit.app.open", "{ app = 'long' }")
        self.assertEqual(self.given(s)[-1], [("字" * 19 + "…", "Agent")])
        self.agent(s, "kit.app.stop", "{ app = 'long' }")
        self.opens(s, f"{{ app = 'pipes', title = '{'|' * 40}' }}")
        self.assertEqual(self.given(s)[-1], [("|" * 40, "Agent")])
        self.agent(s, "kit.app.declare", "{ app = 'pipes', title = 'a|cffff0000b' }")
        self.assertEqual(self.given(s)[-1], [("a|cffff0000b", "Agent")])

    def test_through_a_reload(self):
        s = self.start()
        self.opens(s, "{ app = 'notes', title = 'Notes', lease = 0 }")
        s.run(1)
        self.opens(s, "{ app = 'brief', title = 'Brief', lease = 60 }")
        self.assertEqual(self.given(s)[-1], [("Notes", "Agent"), ("Brief", "Agent")])
        s2 = self.start(s.reload())                                       # the runs kept: their lines at the login
        self.assertEqual(self.given(s2), [[], [("Notes", "Agent"), ("Brief", "Agent")]])
        s3 = self.start(s2.reload(t0=s2.now() + 600))                     # back later: one's agent left meanwhile
        self.assertEqual(self.given(s3), [[], [("Notes", "Agent")]])

    def test_lines_wowbridge_refuses(self):
        """nothing breaks, and they are given again the next time something happens"""
        s = self.start()
        s.lua.execute(b"__refuse = true")
        self.opens(s, "{ app = 'notes', title = 'Notes' }")
        self.assertEqual(self.given(s), [[]])
        self.assertIs(self.status(s, "notes")["on"], True)
        s.lua.execute(b"__refuse = false")
        self.agent(s, "kit.app.declare", "{ app = 'other', title = 'Other' }")
        self.assertEqual(self.given(s)[1:], [[("Notes", "Agent")]])

    def test_a_wowbridge_without_overview(self):
        """an older WoWBridge (its handle has no Overview), or none: apps run as ever, nothing is told, no error"""
        for saved in ({"WoWBridge": bridge("0.9.13")}, None):
            s = Session(self, saved=saved)
            s.lua.execute(b"local ns = ... __ns = ns", s.ns)
            s.login()
            s.run(1)
            self.assertIsNone(s.ns.Overview)
            s.lua.execute(b"WuxianKit:App('mine', { title = 'Mine' })")
            self.assertIs(self.call(s, "kit.app.open", "{ app = 'mine' }")["on"], True)
            s.ns.SetLanguage(b"zhCN")
            s.run(2)
            self.assertIs(self.call(s, "kit.app.stop", "{ app = 'mine' }")["on"], False)
            self.assertIsNone(s.g("__overviews"))
            self.assertEqual(s.errors(), [])
