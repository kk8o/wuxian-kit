"""The window and what the runtime tells of an app beyond on and off (Core/UI/Window.lua, AppPanel.lua; the contract's
hidden, local and waiting), over Apps' ns functions faked as in test_app_panel: the hidden apps that run listed at the
end of the core's page (后台监听: its name, what it hears, until when, a stop; none, no heading), an app that waits
marked on its row, and an app a local extension brought on that extension's row (无限工坊 having named none)."""
import unittest

from kitmock import click, lupa, py, texts
from test_app_panel import button, labels, log, shown, start


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
        """the hidden apps that run are in no row, but the core's page ends with them: a line each, with the name of
        its local extension (else its id), what it hears (the first two, and how many), until when, and a stop that
        stops it; one that does not run, or none at all: not there; no other page has them"""
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
        w = self.window(s)
        self.assertEqual(self.titles(w)[-2:], ["WxVoice", "Bot"])
        for hidden in ("Reactions", "reactions", "pipe|r", "pipe||r", "idle"):
            self.assertNotIn(hidden, self.titles(w))
        until = s.lua.eval(f"date('%H:%M', {now + 600})".encode()).decode()
        lines = ["Background listeners",
                 f"Reactions  |cff9c9ea6chat:guild, game:quest, 4 in all · until {until}|r",
                 "pipe||r  |cff9c9ea6chat:||cff00ff00say||r|r"]
        self.assertEqual(texts(w[b"body"])[-3:], lines)
        self.assertEqual([b[b"label"][b"text"] for b in self.stops(w)], [b"Stop", b"Stop"])
        for other in ("WxVoice", "Bot"):                                        # the core's page only
            click(self.item(w, other))
            self.assertNotIn("Background listeners", texts(w[b"body"]))
            self.assertNotIn("Stop", labels(w))
        click(self.item(w, "Framework"))
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
        self.assertNotIn("Stop", labels(w))

    def test_a_listener_that_starts(self):
        """the core's page shows a hidden app once it runs (kit.app), after its history"""
        s = start(self)
        w = self.window(s)
        self.assertNotIn("Background listeners", texts(w[b"body"]))
        s.lua.execute(b"__add('pipe', { by = 'agent', temp = true, hidden = true, status = { app = 'pipe', on = true } }) "
                      b"WuxianKit:Emit('kit.app', { app = 'pipe', on = true })")
        s.run(0.1)
        self.assertEqual(texts(w[b"body"])[0], "Framework")
        self.assertEqual(texts(w[b"body"])[-2:], ["Background listeners", "pipe"])
        click(self.stops(w)[0])
        self.assertEqual(log(s)[-1], "stop pipe player")
        self.assertNotIn("Background listeners", texts(w[b"body"]))

    def test_an_app_that_waits(self):
        """an app that runs but waits: its row's dot is gold, not green; its page as its card"""
        s = start(self)
        s.lua.execute(b"__add('quest', { by = 'agent', decl = { title = 'Quest' }, "
                      b"status = { app = 'quest', on = true, said = 0, waiting = 'Needs the source rxp' } })")
        w = self.window(s, "quest")
        colour = lambda name: py(s.lua.eval(f"WuxianKit.Skin.C.{name}".encode()))
        dot = lambda: self.item(w, "Quest")[b"dot"]
        self.assertEqual((dot()[b"shown"], py(dot()[b"rgb"])), (True, colour("gold")))
        self.assertEqual(texts(w[b"body"])[:4],
                         ["Quest", "Declared by an agent", "Waiting · Needs the source rxp", "Starts by itself once ready"])
        self.assertEqual(labels(w), ["Stop", "Remove"])
        st = s.g("__apps")[b"quest"][b"status"]
        st[b"waiting"] = None
        s.lua.execute(b"WuxianKit:Emit('kit.app', { app = 'quest', on = true })")
        s.run(0.1)
        self.assertEqual((dot()[b"shown"], py(dot()[b"rgb"])), (True, colour("ok")))
        st[b"on"], st[b"waiting"] = False, b"Needs the source rxp"              # stopped: nothing waits
        s.lua.execute(b"WuxianKit:Emit('kit.app', { app = 'quest', on = false })")
        s.run(0.1)
        self.assertFalse(dot()[b"shown"])

    def test_a_local_extensions_app(self):
        """an app a local extension brought, 无限工坊 having named no such extension (it gave no list, the extension
        is gone, or an agent wrote the label): a row for that extension from the app's own label (已添加, on this
        computer), the page says 无限工坊 does not list it, and each app's card has a remove (nothing in 无限工坊's
        App would take it away): the app goes, and the row with its last one"""
        s = start(self)
        s.lua.execute(b"__add('pal', { by = 'agent', decl = { title = 'Pal', prompt = 'pal-run' }, "
                      b"['local'] = { id = 'pals', title = 'Pals |cff00ff00x|r' } }) "
                      b"__add('chum', { by = 'agent', decl = { title = 'Chum' }, ['local'] = { id = 'pals', title = 'Pals' } }) "
                      b"__add('bot', { by = 'agent', decl = { title = 'Bot' } })")
        w = self.window(s, "pal")
        self.assertEqual(self.titles(w)[-2:], ["Pals ||cff00ff00x||r", "Bot"])     # one row for both its apps
        self.assertEqual(texts(w[b"list"]), ["Built-in", "Added", "Agent apps"])
        self.assertEqual(self.item(w, "Pals ||cff00ff00x||r")[b"state"][b"text"], b"Local")
        self.assertEqual(texts(w[b"body"])[:3],
                         ["Pals ||cff00ff00x||r", "Wuxian Workshop does not list this extension", "App · Pal"])
        self.assertNotIn("Managed in the Wuxian Workshop app", texts(w[b"body"]))
        self.assertIn("App · Chum", texts(w[b"body"]))
        self.assertEqual([p[b"text"][b"text"] for p in (w[b"pill"], w[b"where"]) if p[b"shown"]], [b"Added", b"Local"])
        self.assertEqual(labels(w), ["Hand to AI", "Remove", "Remove"])
        checks = w[b"checks"]
        self.assertEqual([c for c in (checks[i] for i in range(1, len(checks) + 1)) if c[b"shown"]], [])   # no switch
        s.lua.execute(b"__ns.SetLanguage('zhCN')")
        self.assertEqual(texts(w[b"body"])[1:3], ["无限工坊未列出此扩展", "应用 · Pal"])
        self.assertEqual(labels(w), ["交给 AI", "移除", "移除"])
        self.assertEqual(self.item(w, "Pals ||cff00ff00x||r")[b"state"][b"text"].decode(), "本机")
        click(button(w, "移除"))                                                 # the first card's: pal
        self.assertEqual(log(s)[-1], "forget pal wipe")                         # the player's remove: all of it
        s.lua.execute(b"__ns.SetLanguage('enUS')")
        self.assertNotIn("App · Pal", texts(w[b"body"]))
        self.assertIn("App · Chum", texts(w[b"body"]))
        self.assertEqual(labels(w), ["Remove"])
        s.lua.execute(b"WuxianKit:Call('kit.local.set', { extensions = { { id = 'pals', title = 'Pals' } } })")
        s.run(0.1)                                                              # 无限工坊 lists it: managed there
        self.assertEqual(texts(w[b"body"])[:4], ["Pals", "Enabled", "Managed in the Wuxian Workshop app", "App · Chum"])
        self.assertEqual(labels(w), [])

if __name__ == "__main__":
    unittest.main()
