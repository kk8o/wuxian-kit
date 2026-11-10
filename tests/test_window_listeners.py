"""The window and what the runtime tells of an app beyond on and off (Core/UI/Window.lua, AppPanel.lua; the contract's
hidden, local and waiting), over Apps' ns functions faked as in test_app_panel: the hidden apps that run listed under an
app's page (后台监听: its name, what it hears, until when, a stop; none, no heading; with no app in the list, under the
core's page), an app that waits marked in the list, and an app a local extension brought removed as an agent's is."""
import unittest

from kitmock import click, lupa, texts
from test_app_panel import labels, log, shown, start


@unittest.skipIf(lupa is None, "lupa (Lua 5.1 for Python) is not installed")
class WindowListeners(unittest.TestCase):
    def window(self, s, page="kit"):
        s.lua.execute(f"WuxianKit:Window({page!r})".encode())
        return s.g("WuxianKitWindow")

    def item(self, w, title):
        return next(b for b in shown(w[b"items"]) if b[b"label"][b"text"].decode() == title)

    def titles(self, w):
        return [b[b"label"][b"text"].decode() for b in shown(w[b"items"])]

    def stops(self, w):
        """the buttons of the lines under the heading (each line's stop), in order"""
        body = w[b"body"]
        head = next(r for r in body[b"__regions"].values()
                    if r[b"kind"] == b"FontString" and r[b"shown"] and r[b"text"] in (b"Background listeners", "后台监听".encode()))
        return [b for b in shown(w[b"buttons"]) if -b[b"point"][5] > -head[b"point"][5]]

    def test_the_listeners(self):
        """the hidden apps that run are not in the list, but every app's page ends with them: a line each, with the
        name of its local extension (else its id), what it hears (the first two, and how many), until when, and a stop
        that stops it; one that does not run, or none at all: not there"""
        s = start(self)
        now = int(s.lua.eval(b"time()"))
        s.lua.execute(f"""
			__add('voice', {{ addon = 'WxVoice', decl = {{ title = 'Voice' }} }})
			__add('bot', {{ by = 'agent', decl = {{ title = 'Bot' }} }})
			__add('reactions', {{ by = 'agent', temp = true, hidden = true, ['local'] = {{ id = 'react', title = 'Reactions' }},
				status = {{ app = 'reactions', on = true, ends = {now + 600},
					hear = {{ 'chat:guild', 'game:quest', 'game:loot', 'combat:death' }} }} }})
			__add('pipe|r', {{ by = 'agent', temp = true, hidden = true, decl = {{ title = 'Shown nowhere' }},
				status = {{ app = 'pipe|r', on = true, hear = {{ 'chat:|cff00ff00say|r' }} }} }})
			__add('idle', {{ by = 'agent', temp = true, hidden = true, status = {{ app = 'idle', on = false }} }})
		""".encode())
        w = self.window(s, "voice")
        self.assertEqual(self.titles(w)[:2], ["Voice", "Bot"])
        for hidden in ("Reactions", "reactions", "pipe|r", "pipe||r", "idle"):
            self.assertNotIn(hidden, self.titles(w))
        until = s.lua.eval(f"date('%H:%M', {now + 600})".encode()).decode()
        lines = ["Background listeners",
                 f"Reactions  |cff9c9ea6chat:guild, game:quest, 4 in all · until {until}|r",
                 "pipe||r  |cff9c9ea6chat:||cff00ff00say||r|r"]
        self.assertEqual(texts(w[b"body"])[-3:], lines)
        self.assertEqual(labels(w), ["Stop", "Stop"])                           # (Voice does not run: no button of its own)
        click(self.item(w, "Bot"))                                              # every app's page
        self.assertEqual(texts(w[b"body"])[-3:], lines)
        click(self.item(w, "Core"))                                             # not the core's, while an app's has them
        self.assertNotIn("Background listeners", texts(w[b"body"]))
        click(self.item(w, "Voice"))
        s.lua.execute(b"__ns.SetLanguage('zhCN')")
        self.assertEqual(texts(w[b"body"])[-3:-1],
                         ["后台监听", f"Reactions  |cff9c9ea6chat:guild、game:quest 等 4 项 · 至 {until}|r"])
        s.lua.execute(b"__ns.SetLanguage('enUS')")
        first, second = self.stops(w)
        self.assertEqual((first[b"label"][b"text"], first[b"point"][5]), (b"Stop", second[b"point"][5] + 19))
        click(first)
        self.assertEqual(log(s)[-2:], ["control reactions stop", "stop reactions player"])
        self.assertEqual(texts(w[b"body"])[-2:], ["Background listeners", lines[2]])
        click(self.stops(w)[0])
        self.assertEqual(log(s)[-1], "stop pipe|r player")
        self.assertNotIn("Background listeners", texts(w[b"body"]))             # none left: no heading
        self.assertEqual(labels(w), [])

    def test_the_listeners_without_an_app(self):
        """with no app in the list there is no app's page: the core's lists them, after its history"""
        s = start(self)
        w = self.window(s)
        self.assertNotIn("Background listeners", texts(w[b"body"]))
        s.lua.execute(b"__add('pipe', { by = 'agent', temp = true, hidden = true, status = { app = 'pipe', on = true } }) "
                      b"WuxianKit:Emit('kit.app', { app = 'pipe', on = true })")
        s.run(0.1)
        self.assertEqual(texts(w[b"body"])[0], "Core")
        self.assertEqual(texts(w[b"body"])[-2:], ["Background listeners", "pipe"])
        click(self.stops(w)[0])
        self.assertEqual(log(s)[-1], "stop pipe player")
        self.assertNotIn("Background listeners", texts(w[b"body"]))

    def test_an_app_that_waits(self):
        """an app that runs but waits: the list says so, not that it runs; its page as its card"""
        s = start(self)
        s.lua.execute(b"__add('quest', { by = 'agent', decl = { title = 'Quest' }, "
                      b"status = { app = 'quest', on = true, said = 0, waiting = 'Needs the source rxp' } })")
        w = self.window(s, "quest")
        self.assertEqual(self.item(w, "Quest")[b"state"][b"text"], b"Waiting")
        self.assertEqual(texts(w[b"body"])[:4],
                         ["Quest", "Declared by an agent", "Waiting · Needs the source rxp", "Starts by itself once ready"])
        self.assertEqual(labels(w), ["Stop", "Remove"])
        s.lua.execute(b"__ns.SetLanguage('zhCN')")
        self.assertEqual(self.item(w, "Quest")[b"state"][b"text"].decode(), "等待中")
        st = s.g("__apps")[b"quest"][b"status"]
        st[b"waiting"] = None
        s.lua.execute(b"WuxianKit:Emit('kit.app', { app = 'quest', on = true })")
        s.run(0.1)
        self.assertEqual(self.item(w, "Quest")[b"state"][b"text"].decode(), "运行中")
        st[b"on"], st[b"waiting"] = False, b"Needs the source rxp"              # stopped: nothing waits
        s.lua.execute(b"WuxianKit:Emit('kit.app', { app = 'quest', on = false })")
        s.run(0.1)
        self.assertEqual(self.item(w, "Quest")[b"state"][b"text"].decode(), "未运行")

    def test_a_local_extensions_app_is_removed(self):
        """an app a local extension brought: its page says so, and has the remove an agent's has, the player's
        (ns.ForgetApp(id, true)), with nothing asked first"""
        s = start(self)
        s.lua.execute(b"__add('pal', { by = 'agent', decl = { title = 'Pal', prompt = 'pal-run' }, "
                      b"['local'] = { id = 'pals', title = 'Pals |cff00ff00x|r' } }) "
                      b"__add('bot', { by = 'agent', decl = { title = 'Bot' } })")
        w = self.window(s, "pal")
        self.assertEqual(texts(w[b"body"])[:2],
                         ["Pal", "From the local extension Pals ||cff00ff00x||r; added again while it is on"])
        self.assertEqual(labels(w), ["Hand to AI", "Remove"])
        s.lua.execute(b"__ns.SetLanguage('zhCN')")
        self.assertEqual(texts(w[b"body"])[1], "来自本机扩展「Pals ||cff00ff00x||r」，扩展启用时自动添加")
        self.assertEqual(labels(w), ["交给 AI", "移除"])
        click(next(b for b in shown(w[b"buttons"]) if b[b"label"][b"text"].decode() == "移除"))
        self.assertEqual(log(s), ["forget pal wipe"])
        self.assertEqual(texts(w[b"body"])[0], "Bot")                           # gone: the first app's page


if __name__ == "__main__":
    unittest.main()
