"""The core (WuxianKit/Core) under Lua 5.1 in the mock client (kitmock.py): extensions and their capabilities, the Setting
pattern, the proposal pipeline (the click, combat, `after`, stopping one before it runs, failures put back, undo), what
only the window sets,
extensions going on and off (built in, and another addon's: tests/fixtures/WxDemo), and their storage through a reload."""
import unittest

from pathlib import Path

from kitmock import KIT_DIR, Session, click, lupa, py, texts, type_into


@unittest.skipIf(lupa is None, "lupa (Lua 5.1 for Python) is not installed")
class Core(unittest.TestCase):
    def start(self, **kw):
        s = Session(self, **kw)
        s.lua.execute(b"__events = {} WuxianKit:On('*', function(topic, data) "
                      b"__events[#__events + 1] = { topic = topic, data = data } end)")
        s.login()
        s.run(1)
        return s

    def tearDown(self):
        for s in getattr(self, "sessions", []):
            self.assertEqual(s.errors(), [])

    def call(self, s, cap, args="{}", opts="nil"):
        s.lua.execute(f"__answer = WuxianKit:Call({cap!r}, {args}, {opts})".encode())
        return py(s.g("__answer"))

    def fails(self, s, code):
        ok, err = s.lua.eval(f"pcall(function() {code} end)".encode())
        self.assertFalse(ok, code)
        return err.decode()

    def cvar(self, s, name):
        return s.g("__cvars")[name.encode()][b"value"].decode()

    def events(self, s, topic):
        return [e["data"] for e in py(s.g("__events")) or [] if e["topic"] == topic]

    def proposals(self, s, state=None):
        return [p for p in self.events(s, "kit.proposal") if state is None or p["state"] == state]

    def run_button(self, s):
        return s.g("WuxianKitProposal")[b"run"]

    def window(self, s, page=None):
        """the core's window, open, on an extension's page"""
        if not (s.g("WuxianKitWindow") and s.g("WuxianKitWindow")[b"shown"]):
            s.g("SlashCmdList")[b"WUXIANKIT"](b"")
        w = s.g("WuxianKitWindow")
        if page:
            items = w[b"items"]
            click(next(items[i] for i in range(1, len(items) + 1) if items[i][b"id"] == page.encode()))
        return w

    def checks(self, w):
        c = w[b"checks"]
        return {c[i][b"label"][b"text"].decode(): c[i] for i in range(1, len(c) + 1) if c[i][b"shown"]}

    def buttons(self, w):
        b = w[b"buttons"]
        return [b[i] for i in range(1, len(b) + 1) if b[i][b"shown"]]

    def test_extensions_and_capabilities(self):
        s = self.start(fixtures=("WxDemo",))
        exts = {e["id"]: e for e in self.call(s, "kit.extensions")}
        self.assertEqual({k: (e["state"], e.get("builtin")) for k, e in exts.items()},
                         {"kit": ("on", True), "tune": ("on", True), "chat": ("on", True), "gate": ("on", True), "data": ("on", True),
                          "guide": ("on", True), "sense": ("on", True),
                          "demo": ("on", None)})
        self.assertEqual((exts["demo"]["addon"], exts["demo"]["version"]), ("WxDemo", "1.2.3"))
        caps = {c["id"]: c for c in py(s.lua.eval(b"WuxianKit:Capabilities()"))}
        for cap, kind in (("tune.cvar.get", "see"), ("tune.cvar.set", "do"), ("chat.send", "say"), ("chat.listen", "see"),
                          ("chat.listen.stop", "see"), ("chat.listen.status", "see"), ("kit.extension.set", "do"),
                          ("kit.undo", "do"), ("demo.volume.set", "do"), ("demo.note", "keep")):
            self.assertEqual(caps[cap]["kind"], kind, cap)
        self.assertEqual(caps["tune.cvar.set"]["args"], {"name": "string", "value": "string|number|boolean"})
        self.assertTrue(caps["tune.cvar.set"]["undoable"])
        for code, why in (("WuxianKit:Call('tune.cvar.get', {})", "tune.cvar.get: name is missing (string)"),
                          ("WuxianKit:Call('tune.cvar.get', { name = 1 })", "name is a string, not a number"),
                          ("WuxianKit:Call('tune.cvar.set', { name = 'x', value = {} })",
                           "value is a string or number or boolean, not a table"),
                          ("WuxianKit:Call('tune.cvar.get', { name = 'x', other = 1 })",
                           "no argument other (it takes name (string))"),
                          ("WuxianKit:Call('chat.send', { channel = 'shout', text = 'x' })", "channel is one of guild|officer"),
                          ("WuxianKit:Call('nope.nope', {})", "no capability nope.nope"),
                          ("WuxianKit:Call('tune.cvar.get', { name = 'nothing' })", "no setting nothing"),
                          ("WuxianKit:Call('tune.cvar.set', { name = 'secureThing', value = 0 })", "secureThing is secure"),
                          ("WuxianKit:Call('tune.cvar.set', { name = 'readOnlyThing', value = 0 })", "read-only"),
                          ("WuxianKit:Propose({ { 'tune.cvar.get', { name = 'x' } } })", "a proposal holds Say and Do ones"),
                          ("WuxianKit:Call('kit.extension.set', { extension = 'kit', value = false })",
                           "WuxianKit's core stays on")):
            self.assertIn(why, self.fails(s, code))
        self.assertEqual(self.proposals(s), [])                         # refused ones never became proposals
        self.sessions = [s]

    def test_a_setting_is_a_proposal_that_can_be_undone(self):
        s = self.start()
        got = self.call(s, "tune.cvar.get", "{ name = 'NAMEPLATESHOWALL' }")
        self.assertEqual((got["name"], got["value"], got["category"]), ("nameplateShowAll", "0", "game"))
        p = self.call(s, "tune.cvar.set", "{ name = 'nameplateShowAll', value = true }", "{ source = 'agent', title = 'see all' }")
        self.assertEqual((p["state"], p["source"], p["title"], p["steps"][0]["scope"]),
                         ("pending", "agent", "see all", "tune.settings.game"))
        self.assertEqual(self.cvar(s, "nameplateShowAll"), "0")          # nothing changed yet
        text = "\n".join(texts(s.g("WuxianKitProposal")))
        for want in ("Proposal #1", "From Agent", "expires in 5:00", "see all", "[Change] Client settings",
                     "nameplateShowAll: 0 → 1", "If true, nameplates are shown all the time."):
            self.assertIn(want, text)
        click(self.run_button(s))
        self.assertEqual(self.cvar(s, "nameplateShowAll"), "1")
        done = self.proposals(s, "done")[0]
        self.assertEqual((done["steps"][0]["result"], done["undoable"]), ({"value": "1"}, True))
        self.assertFalse(s.g("WuxianKitProposal")[b"shown"])
        self.assertIn("Proposal #1 done", s.chat())
        history = py(s.g("WuxianKitDB"))["history"]
        self.assertEqual(history[0]["steps"][0]["snap"], {"name": "nameplateShowAll", "value": "0"})
        w = self.window(s)                                                 # the core's page: what ran, with Undo
        self.assertIn("#1", "\n".join(texts(w[b"body"])))
        click(next(b for b in self.buttons(w) if b[b"label"][b"text"] == b"Undo"))
        self.assertEqual(self.cvar(s, "nameplateShowAll"), "0")
        self.assertEqual(self.proposals(s)[-1]["state"], "undone")
        self.assertIn("was undone already", self.fails(s, "WuxianKit:Call('kit.undo', { id = 1 })"))
        self.sessions = [s]

    def test_decline_expiry_and_several_waiting(self):
        s = self.start()
        a = self.call(s, "tune.cvar.set", "{ name = 'nameplateShowAll', value = 1 }")
        b = self.call(s, "tune.cvar.set", "{ name = 'graphicsQuality', value = 5 }", "{ ttl = 30 }")
        w = s.g("WuxianKitProposal")
        self.assertIn("1/2", "\n".join(texts(w)))
        click(w[b"decline"])                                               # the oldest one is in front
        self.assertEqual([p["id"] for p in self.proposals(s, "declined")], [a["id"]])
        self.assertIn(f"Proposal #{b['id']}", "\n".join(texts(w)))
        s.run(31)
        self.assertEqual([p["id"] for p in self.proposals(s, "expired")], [b["id"]])
        self.assertEqual((self.cvar(s, "nameplateShowAll"), self.cvar(s, "graphicsQuality")), ("0", "3"))
        self.assertFalse(w[b"shown"])
        self.sessions = [s]

    def test_combat_and_after(self):
        s = self.start()
        s.g("__combat")(True)
        self.call(s, "tune.cvar.set", "{ name = 'nameplateShowAll', value = 1 }")
        self.assertIn("In combat: runs after combat", "\n".join(texts(s.g("WuxianKitProposal"))))
        click(self.run_button(s))
        self.assertEqual((self.proposals(s)[-1]["state"], self.cvar(s, "nameplateShowAll")), ("queued", "0"))
        s.g("__combat")(False)
        self.assertEqual((self.proposals(s)[-1]["state"], self.cvar(s, "nameplateShowAll")), ("done", "1"))
        now = s.lua.eval(b"time()")
        self.call(s, "tune.cvar.set", "{ name = 'graphicsQuality', value = 1 }", f"{{ after = {now + 5} }}")
        self.assertFalse(self.run_button(s)[b"enabled"])                   # Run stays off before its time
        self.assertIn("Available in 5 s", "\n".join(texts(s.g("WuxianKitProposal"))))
        s.g("SlashCmdList")[b"WUXIANKIT"](b"yes")
        self.assertEqual(self.cvar(s, "graphicsQuality"), "3")
        s.run(6)
        self.assertTrue(self.run_button(s)[b"enabled"])
        s.g("SlashCmdList")[b"WUXIANKIT"](b"yes")
        self.assertEqual(self.cvar(s, "graphicsQuality"), "1")
        self.sessions = [s]

    def test_stopped_before_it_runs(self):
        """until a proposal runs the player can stop it: one let go without asking that waits for its time (Cancel on the
        core's page), one confirmed in combat (/wk no), one without asking queued in combat (/wk no <id>)"""
        s = self.start()
        click(self.checks(self.window(s, "tune"))["Game settings"])
        now = s.lua.eval(b"time()")
        p = self.call(s, "tune.cvar.set", "{ name = 'nameplateShowAll', value = 1 }", f"{{ after = {now + 30} }}")
        self.assertEqual((p["state"], p["auto"]), ("waiting", True))
        self.assertIn(f"Proposal #{p['id']} (pre-approved) is on hold: runs in 30 s (/wk no {p['id']} to cancel)",
                      s.chat())
        w = self.window(s, "kit")
        self.assertIn(f"#{p['id']}  |cff7fb3e0Waiting|r  nameplateShowAll: 0 → 1", texts(w[b"body"]))
        click(next(b for b in self.buttons(w) if b[b"label"][b"text"] == b"Cancel"))
        self.assertIn(f"Proposal #{p['id']} cancelled", s.chat())
        self.assertNotIn("Pending", texts(w[b"body"]))
        s.run(31)
        self.assertEqual(self.cvar(s, "nameplateShowAll"), "0")
        s.g("__combat")(True)
        q = self.call(s, "tune.cvar.set", "{ name = 'graphicsQuality', value = 1 }")    # graphics: asks
        click(self.run_button(s))
        self.assertIn(f"Proposal #{q['id']} confirmed: runs after combat (/wk no {q['id']} to cancel)", s.chat())
        s.g("SlashCmdList")[b"WUXIANKIT"](b"no")                          # nothing shown: the oldest not run yet
        r = self.call(s, "tune.cvar.set", "{ name = 'nameplateShowAll', value = 1 }")   # game: without asking
        self.assertEqual(r["state"], "queued")
        self.assertIn(f"Proposal #{r['id']} (pre-approved) runs after combat (/wk no {r['id']} to cancel)", s.chat())
        s.g("SlashCmdList")[b"WUXIANKIT"](f"no {r['id']}".encode())
        s.g("SlashCmdList")[b"WUXIANKIT"](b"no 999")
        self.assertIn("Proposal #999 is not pending", s.chat())
        s.g("__combat")(False)
        self.assertEqual((self.cvar(s, "nameplateShowAll"), self.cvar(s, "graphicsQuality")), ("0", "3"))
        self.assertEqual([x["id"] for x in self.proposals(s, "declined")], [p["id"], q["id"], r["id"]])
        self.assertEqual(self.proposals(s, "done"), [])
        self.sessions = [s]

    def test_the_hub_page(self):
        """the core's page: the scopes, then what ran, newest first, one line each, as much as fits (8 at most); not the
        core's own capabilities (the agent's); an undo's proposal shows what it takes back"""
        s = self.start()
        for v in range(12):
            self.call(s, "tune.cvar.set", f"{{ name = 'graphicsQuality', value = {v % 5 + 1} }}", "{ title = 'q' }")
            click(self.run_button(s))
        w = self.window(s, "kit")
        body = texts(w[b"body"])
        self.assertNotIn("Capabilities", body)
        self.assertEqual(sum(1 for t in body if t.startswith("#")), 8)
        self.assertEqual(body[-1], "... 4 more")
        regions = [r for r in w[b"body"][b"__regions"].values() if r[b"shown"]]
        self.assertLessEqual(max(-r[b"point"][5] + 14 for r in regions), 404)    # inside the page
        p = self.call(s, "kit.undo", "{ id = 12 }")
        self.assertEqual(p["steps"][0]["preview"], ["Undo proposal #12", "Revert: graphicsQuality: 1 → 2"])
        self.sessions = [s]

    def test_options_and_commands(self):
        """an extension's options are the player's choices on its page (a check box, a text box), kept, and no capability
        changes them; its command runs as /wk <word>, and /wk help lists it"""
        s = self.start()
        s.lua.execute(b"local x = WuxianKit:Extension('opt', { title = 'Opt' }) "
                      b"x:Option('take', { title = 'Take them', default = false }) "
                      b"x:Option('names', { title = 'Names', kind = 'text', default = '', hint = 'commas between' }) "
                      b"x:Command('hello', function(self, rest) __hello = rest end, 'say hello')")
        s.run(0.1)
        w = self.window(s, "opt")
        self.assertIn("Options", texts(w[b"body"]))
        click(self.checks(w)["Take them"])
        edits = [e for e in w[b"edits"].values() if e[b"shown"]]
        type_into(edits[0], "Ann, Bob")
        self.assertEqual((s.lua.eval(b"WuxianKit:Extension('opt'):Get('take')"),
                          s.lua.eval(b"WuxianKit:Extension('opt'):Get('names')")), (True, b"Ann, Bob"))
        self.assertEqual(py(s.g("WuxianKitDB"))["ext"]["opt"]["options"], {"take": True, "names": "Ann, Bob"})
        self.assertFalse([c for c in py(s.lua.eval(b"WuxianKit:Capabilities()")) if c["id"].startswith("opt.")])
        s.g("SlashCmdList")[b"WUXIANKIT"](b"hello  there you ")
        self.assertEqual(s.g("__hello"), b"there you")
        s.g("SlashCmdList")[b"WUXIANKIT"](b"help")
        self.assertIn("/wk hello: say hello", s.chat())
        self.sessions = [s]

    def test_the_window_for_other_addons(self):
        """WuxianKit:Window(page): the window open, on that extension's page; without one, or with one not there, on the
        page it showed last; open already, it stays open (what other addons' buttons call)"""
        s = self.start()
        title = lambda ext: s.lua.eval(f"(function() local t = WuxianKit:Extension('{ext}').title return type(t) == 'function' and t() or t end)()".encode()).decode()
        self.assertTrue(s.lua.eval(b"WuxianKit:Window('tune')"))
        w = s.g("WuxianKitWindow")
        self.assertTrue(w[b"shown"])
        self.assertTrue(texts(w[b"body"])[0].startswith(title("tune")))
        for again in (b"WuxianKit:Window()", b"WuxianKit:Window('nope')", b"WuxianKit:Window(42)"):
            s.lua.execute(again)
            self.assertTrue(w[b"shown"])
            self.assertTrue(texts(w[b"body"])[0].startswith(title("tune")))
        s.lua.execute(b"WuxianKit:Window('kit')")
        self.assertTrue(texts(w[b"body"])[0].startswith(title("kit")))
        self.sessions = [s]

    def test_the_language(self):
        """the words follow the client (Chinese on a Chinese one) or the player's choice (/wk lang, the buttons on the
        core's page), at once: the window, the extensions' titles and what they can do, the proposal window; the choice is
        kept over a reload"""
        zh = self.start(locale="zhCN")
        w = self.window(zh, "tune")
        self.assertTrue(texts(w[b"body"])[0].startswith("调校"))
        s = self.start()
        w = self.window(s, "tune")
        self.assertTrue(texts(w[b"body"])[0].startswith("Tune"))
        self.call(s, "tune.cvar.set", "{ name = 'nameplateShowAll', value = 1 }")
        s.g("SlashCmdList")[b"WUXIANKIT"](b"lang zh")
        self.assertIn("语言：中文", s.chat())
        self.assertEqual(py(s.g("WuxianKitDB"))["lang"], "zhCN")
        body = texts(w[b"body"])
        self.assertTrue(body[0].startswith("调校  |cff9c9ea6版本 "))
        self.assertIn("更改：客户端设置、按键绑定、宏、编辑模式布局、导入布局、天赋配置、切换装备方案、保存装备方案、整理背包、插件启用状态",
                      body)
        self.assertIn("无限工坊 · 扩展框架", texts(w))
        items = w[b"items"]
        self.assertEqual([items[i][b"label"][b"text"].decode() for i in range(1, len(items) + 1) if items[i][b"shown"]],
                         ["核心", "调校", "聊天", "远程", "数据", "指引", "角色信息"])
        proposal = s.g("WuxianKitProposal")
        self.assertEqual((proposal[b"run"][b"label"][b"text"].decode(), proposal[b"decline"][b"label"][b"text"].decode()),
                         ("执行", "拒绝"))
        self.assertIn("[更改] 客户端设置", texts(proposal))
        self.assertIn("来源：插件 · 5:00 后过期", texts(proposal))
        s2 = s.reload()                                                   # kept
        s2.login()
        s2.run(1)
        w2 = self.window(s2, "kit")
        self.assertTrue(texts(w2[b"body"])[0].startswith("核心"))
        english = next(b for b in self.buttons(w2) if b[b"label"][b"text"] == b"English")
        click(english)                                                    # the core's page: the buttons
        self.assertIn("Language: English", s2.chat())
        self.assertTrue(texts(w2[b"body"])[0].startswith("Core"))
        s2.g("SlashCmdList")[b"WUXIANKIT"](b"lang auto")
        self.assertIn("Language: Auto (client language)", s2.chat())
        self.assertIsNone(py(s2.g("WuxianKitDB")).get("lang"))
        s2.g("SlashCmdList")[b"WUXIANKIT"](b"lang klingon")
        self.assertIn("Usage: /wk lang auto|zh|en", s2.chat())
        self.sessions = [zh, s, s2]

    def test_the_manifest(self):
        """the manifest (the Agent access spec): every extension with its state and docs folder, the capabilities and
        events of those that are on, a revision that stays while nothing changes and changes, told by kit.changed half a
        second later, when an extension goes off; kit.manifest and kit.revision answer it"""
        s = self.start(fixtures=("WxDemo",))
        m = py(s.lua.eval(b"WuxianKit:Manifest()"))
        self.assertEqual((m["protocol"], m["language"]), (1, "enUS"))
        self.assertRegex(m["revision"], r"^[0-9a-f]{8}$")
        ext = {e["id"]: e for e in m["extensions"]}
        self.assertEqual(list(ext)[:7], ["kit", "tune", "chat", "gate", "data", "guide", "sense"])
        self.assertEqual((ext["kit"]["docs"], ext["tune"]["docs"], ext["demo"]["docs"]),
                         ("WuxianKit", "WuxianKit/Extensions/Tune", "WxDemo"))
        cvar = next(c for c in ext["tune"]["capabilities"] if c["id"] == "tune.cvar.set")
        self.assertEqual((cvar["kind"], cvar["title"], cvar["args"]["name"]), ("do", "Client settings", "string"))
        self.assertEqual([v["topic"] for v in ext["kit"]["events"]], ["kit.proposal", "kit.extension", "kit.dropped", "kit.changed", "kit.ready", "kit.feed"])
        self.assertEqual([v["topic"] for v in ext["gate"]["events"]], ["gate.result"])
        message = ext["chat"]["events"][0]
        self.assertEqual((message["topic"], message["data"]["sender"]), ("chat.message", "string"))
        self.assertEqual(ext["guide"]["events"][0]["topic"], "guide.tour")
        self.assertEqual(self.call(s, "kit.revision")["revision"], m["revision"])
        self.assertEqual(self.call(s, "kit.manifest")["revision"], m["revision"])
        told = [e["revision"] for e in self.events(s, "kit.ready") + self.events(s, "kit.changed")]
        self.assertEqual(told[-1], m["revision"])                          # the last one told is the one now
        s.run(2)
        self.assertEqual(len(self.events(s, "kit.changed")), len(told) - 1)   # nothing changed: nothing told
        w = self.window(s, "chat")
        click(self.checks(w)["Enabled"])                                   # chat off
        s.run(1)
        off = py(s.lua.eval(b"WuxianKit:Manifest()"))
        chat = next(e for e in off["extensions"] if e["id"] == "chat")
        self.assertEqual((chat["state"], chat.get("capabilities")), ("off", None))
        self.assertNotEqual(off["revision"], m["revision"])
        self.assertEqual(self.events(s, "kit.changed")[-1]["revision"], off["revision"])
        self.sessions = [s]

    def test_the_architecture_example(self):
        """ARCHITECTURE.md's example extension, loaded as another addon would be: listed with its docs folder, its
        Setting's read and change (preview, validate, undo), its event in the manifest, its title in both languages"""
        s = self.start(fixtures=("DocDemo",))
        m = py(s.lua.eval(b"WuxianKit:Manifest()"))
        demo = next(e for e in m["extensions"] if e["id"] == "demo")
        self.assertEqual((demo["title"], demo["addon"], demo["docs"], demo["state"]), ("Demo", "DocDemo", "DocDemo", "on"))
        self.assertEqual(sorted(c["id"] for c in demo["capabilities"]), ["demo.volume.get", "demo.volume.set"])
        self.assertEqual(demo["events"], [{"topic": "demo.changed", "doc": "the volume changed", "data": {"volume": "number"}}])
        self.assertEqual(self.call(s, "demo.volume.get")["value"], 3)
        self.fails(s, "WuxianKit:Call('demo.volume.set', { value = 11 })")              # validate: 0-10
        p = self.call(s, "demo.volume.set", "{ value = 5 }")
        self.assertEqual((p["state"], p["steps"][0]["preview"]), ("pending", ["Volume: 3 → 5"]))
        click(self.run_button(s))
        self.assertEqual(self.call(s, "demo.volume.get")["value"], 5)
        undo = self.call(s, "kit.undo", f"{{ id = {p['id']} }}")
        click(self.run_button(s))
        self.assertEqual((self.proposals(s, "undone")[0]["id"], self.call(s, "demo.volume.get")["value"]), (p["id"], 3))
        s.g("SlashCmdList")[b"WUXIANKIT"](b"lang zh")
        self.assertEqual(next(e for e in py(s.lua.eval(b"WuxianKit:Manifest()"))["extensions"] if e["id"] == "demo")["title"], "示例")
        doc = (KIT_DIR / "ARCHITECTURE.md").read_text(encoding="utf-8")       # the document shows it as it runs
        demo_lua = (Path(__file__).parent / "fixtures" / "DocDemo" / "DocDemo.lua").read_text(encoding="utf-8")
        for line in demo_lua.splitlines()[1:]:
            if line.strip():
                self.assertIn(line.strip(), doc)
        self.sessions = [s]

    def test_the_skills_name_real_tools(self):
        """every skill shipped with WuxianKit has its name, Chinese title, descriptions and arguments, and every wk_ tool
        or capability id it names is one the manifest has (or the App's own wk_docs, wk_wait, wk_propose)"""
        import re
        from pathlib import Path
        s = self.start()
        m = py(s.lua.eval(b"WuxianKit:Manifest()"))
        caps = {c["id"] for e in m["extensions"] for c in e.get("capabilities") or []}
        tools = {"wk_" + c.replace(".", "_") for c in caps} | {"wk_docs", "wk_wait", "wk_propose"}
        root = Path(__file__).resolve().parents[1] / "WuxianKit"
        skills = sorted(root.glob("skills/*.md")) + sorted(root.glob("Extensions/*/skills/*.md"))
        self.assertEqual([p.stem for p in skills], ["kit-extension", "guide-tour", "tune-setup"])
        for p in skills:
            text = p.read_text(encoding="utf-8")
            head = dict(re.findall(r"^([a-z-]+): (.+)$", text.split("---")[1], re.M))
            self.assertEqual(head["name"], p.stem)
            for key in ("title-zh", "description", "description-zh", "arguments"):
                self.assertTrue(head.get(key), (p.name, key))
            named = set(re.findall(r"\bwk_[a-z_]+", text)) - {"wk_"}
            self.assertEqual(named - tools, set(), p.name)
            ids = set(re.findall(r"`((?:tune|guide|kit|chat|gate|data|sense)\.[a-z.]+)`", text))
            self.assertEqual(ids - caps, set(), p.name)
        self.sessions = [s]

    def test_a_failing_step_puts_back_the_ones_before(self):
        s = self.start()
        s.lua.execute(b"WuxianKit:Propose({ { 'tune.cvar.set', { name = 'nameplateShowAll', value = 1 } }, "
                      b"{ 'tune.cvar.set', { name = 'stubborn', value = 'b' } } }, { title = 'two' })")
        click(self.run_button(s))
        failed = self.proposals(s, "failed")[0]
        self.assertIn("step 2 (tune.cvar.set): the game kept stubborn at a", failed["error"])
        self.assertEqual(self.cvar(s, "nameplateShowAll"), "0")           # step 1 was put back
        self.assertIn("earlier steps rolled back", s.chat())
        self.assertEqual(py(s.g("WuxianKitDB"))["history"], {})          # nothing ran: nothing to undo
        self.sessions = [s]

    def test_without_asking(self):
        """a scope ticked in the window runs without the click, for the agent and addons but not for other players'
        proposals; what counts is kept in the core and written to the saved variables at logout over whatever else wrote
        there; nothing in the public table changes it"""
        s = self.start()
        w = self.window(s, "tune")
        boxes = self.checks(w)
        self.assertEqual(list(boxes), ["Enabled", "Graphics settings", "Sound settings", "Game settings", "Combat settings",
                                       "Network settings", "Other settings", "Key bindings", "Macros",
                                       "Edit Mode layouts", "Talent loadouts", "Equipment sets", "Bag sorting",
                                       "Addon state"])
        click(boxes["Game settings"])
        p = self.call(s, "tune.cvar.set", "{ name = 'nameplateShowAll', value = 1 }", "{ source = 'agent' }")
        self.assertEqual((p["state"], p["auto"], self.cvar(s, "nameplateShowAll")), ("done", True, "1"))
        self.assertIn("done (pre-approved)", s.chat())
        remote = self.call(s, "tune.cvar.set", "{ name = 'nameplateShowAll', value = 0 }", "{ source = 'remote:Somebody' }")
        self.assertEqual(remote["state"], "pending")                     # another player's always asks
        self.assertEqual(self.call(s, "tune.cvar.set", "{ name = 'graphicsQuality', value = 1 }")["state"], "pending")
        s.lua.execute(b"WuxianKitDB.grants = { ['tune.settings.graphics'] = true }")    # written by someone else
        self.assertEqual(self.call(s, "tune.cvar.set", "{ name = 'graphicsQuality', value = 2 }")["state"], "pending")
        public = py(s.lua.eval(b"(function() local out = {} for k in pairs(WuxianKit) do out[#out + 1] = k end "
                               b"table.sort(out) return out end)()"))
        self.assertEqual(public, ["AgentOnline", "Call", "Capabilities", "Capability", "Comm", "Emit", "Escape", "Extension",
                                  "Granted", "Manifest", "Off", "On", "Proposal", "Proposals", "Propose", "Skin", "VERSION", "Window",
                                  "Words"])
        s.lua.execute(b"WuxianKitDB = { grants = { ['tune.settings.sound'] = true } }")   # even replaced
        s.fire("PLAYER_LOGOUT")
        self.assertEqual(py(s.g("WuxianKitDB"))["grants"], {"tune.settings.game": True})
        self.assertIn("history", py(s.g("WuxianKitDB")))                # the table the core had, put back
        self.sessions = [s]

    def test_an_extension_off_and_on(self):
        """off from the window: its capabilities refuse, its feed stops, it stays off after a reload; on again by a
        proposal (kit.extension.set, a Setting), which can be undone"""
        s = self.start()
        self.call(s, "chat.listen", "{ channels = { 'guild' } }")
        w = self.window(s, "chat")
        self.assertIn("Listen to channels: Guild (until", "\n".join(texts(w[b"body"])))
        click(self.checks(w)["Enabled"])
        self.assertIn('Disabled: Chat', s.chat())
        self.assertIn("no capability chat.send", self.fails(s, "WuxianKit:Call('chat.send', { channel = 'guild', text = 'x' })"))
        self.assertEqual(self.events(s, "kit.feed")[-1], {"extension": "chat", "feed": "listen", "on": False})
        exts = {e["id"]: e["state"] for e in self.call(s, "kit.extensions")}
        self.assertEqual(exts["chat"], "off")
        s2 = s.reload()
        s2.login()
        s2.lua.execute(b"__events = {} WuxianKit:On('*', function(topic, data) "
                       b"__events[#__events + 1] = { topic = topic, data = data } end)")
        self.assertFalse(s2.lua.eval(b"WuxianKit:Capability('chat.send')"))
        p = self.call(s2, "kit.extension.set", "{ extension = 'chat', value = true }", "{ source = 'agent' }")
        self.assertEqual(p["steps"][0]["preview"], ["Chat: Disabled → Enabled"])
        click(self.run_button(s2))
        self.assertTrue(s2.lua.eval(b"WuxianKit:Capability('chat.send')"))
        self.assertEqual(self.call(s2, "chat.listen.status"), {"on": False})   # its feed did not come back on
        self.call(s2, "kit.undo", f"{{ id = {p['id']} }}")
        click(self.run_button(s2))
        self.assertFalse(s2.lua.eval(b"WuxianKit:Capability('chat.send')"))
        self.sessions = [s, s2]

    def test_pre_approval_taken_back(self):
        """a proposal that was to run without the click asks for it when the player took back its scope meanwhile: one
        waiting for its time, one queued in combat"""
        s = self.start()
        click(self.checks(self.window(s, "tune"))["Game settings"])
        now = s.lua.eval(b"time()")
        p = self.call(s, "tune.cvar.set", "{ name = 'nameplateShowAll', value = 1 }", f"{{ after = {now + 20} }}")
        s.g("__combat")(True)
        q = self.call(s, "tune.cvar.set", "{ name = 'nameplateMaxDistance', value = 50 }")
        self.assertEqual((p["state"], q["state"]), ("waiting", "queued"))
        click(self.checks(self.window(s, "tune"))["Game settings"])            # the player takes it back
        s.g("__combat")(False)
        s.run(21)
        self.assertEqual((self.cvar(s, "nameplateShowAll"), self.cvar(s, "nameplateMaxDistance")), ("0", "41"))
        last = {x["id"]: x["state"] for x in self.proposals(s)}
        self.assertEqual((last[p["id"]], last[q["id"]]), ("pending", "pending"))
        self.assertIn(f"Proposal #{q['id']} needs confirmation: its pre-approval was withdrawn", s.chat())
        self.assertTrue(s.g("WuxianKitProposal")[b"shown"])
        self.sessions = [s]

    def test_an_extension_off_takes_its_proposals(self):
        """an extension turned off takes its proposals not run yet with it: one pre-approved waiting for its time, one
        waiting for the click"""
        s = self.start(fixtures=("WxDemo",))
        click(self.checks(self.window(s, "demo"))["Demo volume"])
        now = s.lua.eval(b"time()")
        auto = self.call(s, "demo.volume.set", "{ value = 5 }", f"{{ after = {now + 10} }}")
        asks = self.call(s, "demo.volume.set", "{ value = 7 }", "{ source = 'remote:Somebody' }")
        self.assertEqual((auto["state"], asks["state"]), ("waiting", "pending"))
        click(self.checks(self.window(s, "demo"))["Enabled"])
        s.run(11)
        last = {x["id"]: x["state"] for x in self.proposals(s)}
        self.assertEqual((last[auto["id"]], last[asks["id"]]), ("declined", "declined"))
        self.assertIn(f"Proposal #{asks['id']} cancelled: Demo was disabled", s.chat())
        self.assertEqual(py(s.g("WuxianKitDB"))["ext"]["demo"]["volume"], 3)
        self.assertFalse(s.g("WuxianKitProposal")[b"shown"])
        self.sessions = [s]

    def test_checked_again_after_combat_and_between_steps(self):
        """confirmed in combat, it is checked again when combat ends (chat lockdown: it waits until it can run); a step
        that must not run in a fight that began while the one before settled waits for the end of it, then the rest
        runs; stopped half way in combat, what ran is put back after it"""
        s = self.start()
        s.g("__combat")(True)
        s.lua.execute(b"WuxianKit:Propose({ { 'tune.cvar.set', { name = 'graphicsQuality', value = 1 } }, "
                      b"{ 'chat.send', { channel = 'guild', text = 'hi' } } })")
        click(self.run_button(s))
        self.assertEqual(self.proposals(s)[-1]["state"], "queued")
        s.lua.execute(b"__lockdown = true")
        s.g("__combat")(False)
        self.assertEqual((self.proposals(s)[-1]["state"], self.cvar(s, "graphicsQuality")), ("waiting", "3"))
        self.assertEqual(len(s.g("__sent")), 0)
        s.lua.execute(b"__lockdown = false")
        s.run(1.1)
        self.assertEqual((self.proposals(s)[-1]["state"], self.cvar(s, "graphicsQuality")), ("done", "1"))
        s.lua.execute(b"WuxianKit:Propose({ { 'tune.macro.set', { name = 'Heal', value = '/cast Heal' } }, "
                      b"{ 'tune.cvar.set', { name = 'nameplateShowAll', value = 1 } } })")
        click(self.run_button(s))
        s.g("__combat")(True)                                                  # before the macro shows
        s.run(0.5)
        self.assertEqual((self.proposals(s)[-1]["state"], self.cvar(s, "nameplateShowAll")), ("queued", "0"))
        self.assertIn("paused for combat: the rest runs after combat", s.chat())
        s.g("__combat")(False)
        self.assertEqual((self.proposals(s)[-1]["state"], self.cvar(s, "nameplateShowAll")), ("done", "1"))
        s.lua.execute(b"WuxianKit:Propose({ { 'tune.macro.set', { name = 'Shield', value = '/cast Shield' } }, "
                      b"{ 'tune.cvar.set', { name = 'graphicsQuality', value = 2 } } })")
        click(self.run_button(s))
        s.g("__combat")(True)
        s.run(0.5)
        r = self.proposals(s)[-1]
        s.g("SlashCmdList")[b"WUXIANKIT"](f"no {r['id']}".encode())
        self.assertIn(f"Proposal #{r['id']}: what ran is put back after combat", s.chat())
        s.g("__combat")(False)
        s.run(0.5)
        self.assertEqual(self.proposals(s)[-1]["state"], "declined")
        self.assertEqual((s.lua.eval(b"GetMacroIndexByName('Shield')"), self.cvar(s, "graphicsQuality")), (0, "1"))
        self.sessions = [s]

    def test_after_and_title_from_outside(self):
        """`after` is a finite time before the proposal's end; a title from outside is escaped and cut"""
        s = self.start()
        now = s.lua.eval(b"time()")
        for opts in ("{ after = 1/0 }", "{ after = 0/0 }", f"{{ after = {now + 400} }}"):
            self.assertIn("after:", self.fails(
                s, f"WuxianKit:Call('tune.cvar.set', {{ name = 'nameplateShowAll', value = 1 }}, {opts})"))
        p = self.call(s, "tune.cvar.set", "{ name = 'nameplateShowAll', value = 1 }",
                      "{ title = 'Lower |cffff0000music|r\\nnow' }")
        self.assertEqual(p["title"], "Lower ||cffff0000music||r now")
        self.assertIn("Lower ||cffff0000music||r now", texts(s.g("WuxianKitProposal")))
        long = self.call(s, "tune.cvar.set", "{ name = 'graphicsQuality', value = 2 }", "{ title = string.rep('x', 300) }")
        self.assertEqual(long["title"], "x" * 120 + "…")
        self.sessions = [s]

    def test_the_proposal_in_front_changes(self):
        """when another proposal takes the place of the one shown, Run and /wk yes wait a second: a click meant for the
        one before never runs one the player has not seen"""
        s = self.start()
        self.call(s, "tune.cvar.set", "{ name = 'nameplateShowAll', value = 1 }")
        self.call(s, "tune.cvar.set", "{ name = 'graphicsQuality', value = 5 }")
        click(self.run_button(s))                                              # runs the first; the second takes its place
        self.assertEqual(self.cvar(s, "nameplateShowAll"), "1")
        click(self.run_button(s))                                              # too soon: nothing
        s.g("SlashCmdList")[b"WUXIANKIT"](b"yes")
        self.assertEqual(self.cvar(s, "graphicsQuality"), "3")
        self.assertFalse(self.run_button(s)[b"enabled"])
        s.run(2.1)
        self.assertTrue(self.run_button(s)[b"enabled"])
        click(self.run_button(s))
        self.assertEqual(self.cvar(s, "graphicsQuality"), "5")
        self.sessions = [s]

    def test_option_defaults_and_a_feed_without_event(self):
        """ext:Get gives an option's declared default before the player set any; a feed without `event` is heard under
        its own name"""
        s = self.start()
        s.lua.execute(b"local x = WuxianKit:Extension('xdemo', { title = 'X' }) "
                      b"x:Option('flag', { default = true }) x:Option('who', { kind = 'text', default = 'Ann' }) "
                      b"x:Feed('hear', { title = 'Hear', events = { 'CHAT_MSG_SAY' }, "
                      b"read = function(self, ev, text) return { text = text } end }) __x = x")
        s.run(0.1)                                                             # on once its file has run
        self.assertEqual((s.lua.eval(b"__x:Get('flag')"), s.lua.eval(b"__x:Get('who')")), (True, b"Ann"))
        self.call(s, "xdemo.hear")
        s.fire("CHAT_MSG_SAY", "hello")
        self.assertEqual(self.events(s, "xdemo.hear"), [{"text": "hello"}])
        self.assertIn("a feed's spec has read", self.fails(s, "WuxianKit:Extension('xdemo'):Feed('bad', {})"))
        self.sessions = [s]

    def test_feeds_end_and_belong_to_their_character(self):
        """a feed whose time is up stops by itself (the player and the bus hear it); a feed is the character's that
        started it: another character neither hears through it nor stops it, and it is back when that one logs in"""
        s = self.start()
        self.call(s, "chat.listen", "{ channels = { 'guild' }, minutes = 1 }")
        s.run(66)
        self.assertEqual(self.events(s, "kit.feed")[-1], {"extension": "chat", "feed": "listen", "on": False})
        self.assertIn("Listen to channels: stopped", s.chat())
        self.call(s, "chat.listen", "{ channels = { 'guild' } }")
        s2 = s.reload()
        s2.lua.execute(b"__guid = 'Player-1-00000002'")
        s2.login()
        self.assertEqual(self.call(s2, "chat.listen.status"), {"on": False})
        self.call(s2, "chat.listen.stop")
        s3 = s2.reload()
        s3.login()
        self.assertTrue(self.call(s3, "chat.listen.status")["on"])
        self.sessions = [s, s2, s3]

    def test_history_belongs_to_its_character(self):
        """what ran is undone only on the character it ran on: another one neither lists it nor undoes it"""
        s = self.start()
        p = self.call(s, "tune.cvar.set", "{ name = 'nameplateShowAll', value = 1 }")
        click(self.run_button(s))
        s2 = s.reload()
        s2.lua.execute(b"__guid = 'Player-1-00000002'")
        s2.login()
        self.assertFalse(self.call(s2, "kit.history"))
        self.assertIn(f"no proposal {p['id']} in the history",
                      self.fails(s2, f"WuxianKit:Call('kit.undo', {{ id = {p['id']} }})"))
        self.assertIn("None", texts(self.window(s2)[b"body"]))
        s3 = s2.reload()
        s3.login()
        self.assertEqual([h["id"] for h in self.call(s3, "kit.history")], [p["id"]])
        self.sessions = [s, s2, s3]

    def test_a_step_that_changed_the_game_before_it_failed_is_put_back(self):
        """a setting the client keeps at another value than asked (it clamps it) fails its step, and the step itself is
        put back too"""
        s = self.start()
        self.call(s, "tune.cvar.set", "{ name = 'nameplateClamped', value = 100 }")
        click(self.run_button(s))
        self.assertIn("the game kept nameplateClamped at 60", self.proposals(s, "failed")[0]["error"])
        self.assertEqual(self.cvar(s, "nameplateClamped"), "41")
        self.sessions = [s]

    def test_comm_numbers(self):
        """a number in an addon message only in the decimal form Serialize writes: no nan, inf or hex"""
        s = self.start()
        for text in ("n0x10;", "nnan;", "n1e999;", "ninf;", "n-nan;"):
            self.assertIsNone(s.lua.eval(f"(WuxianKit.Comm.Deserialize({text!r}))".encode()), text)
        for v in ("1.5", "-2.25e-07", "123456789012", "0"):
            self.assertEqual(s.lua.eval(f"WuxianKit.Comm.Deserialize(WuxianKit.Comm.Serialize({v})) == {v}".encode()), True)
        self.sessions = [s]

    def test_another_addons_extension(self):
        """WxDemo (## X-WuxianKit-Extension: demo, load on demand) is loaded at login and goes on: its storage, its
        Setting as a proposal, its Keep, its timer only while on, its status line; off at login it is not even loaded,
        and the window loads it again"""
        s = self.start(fixtures=("WxDemo",))
        self.assertEqual(s.loaded, ["WuxianKit", "WxDemo"])
        self.assertEqual(self.call(s, "demo.volume.get"), {"value": 3})
        p = self.call(s, "demo.volume.set", "{ value = 5 }")
        self.assertEqual(p["steps"][0]["preview"], ["Demo volume: 3 → 5"])
        click(self.run_button(s))
        self.assertEqual(self.call(s, "demo.note", "{ text = 'hello' }"), 1)
        s.run(21)
        db = py(s.g("WuxianKitDB"))["ext"]["demo"]
        self.assertEqual((db["volume"], db["notes"], db["ticks"]), (5, ["hello"], 2))
        w = self.window(s, "demo")
        self.assertIn("ticks: 2", "\n".join(texts(w[b"body"])))
        click(self.checks(w)["Enabled"])                                        # off: the timer stops
        s.run(21)
        self.assertEqual(py(s.g("WuxianKitDB"))["ext"]["demo"]["ticks"], 2)
        s2 = s.reload()
        s2.login()
        self.assertEqual(s2.loaded, ["WuxianKit"])                         # off: not loaded at login
        exts = {e["id"]: e for e in py(s2.lua.eval(b"WuxianKit:Call('kit.extensions', {})"))}
        self.assertEqual((exts["demo"]["state"], exts["demo"]["addon"]), ("off", "WxDemo"))
        w2 = self.window(s2, "demo")
        click(self.checks(w2)["Enabled"])
        self.assertEqual(s2.loaded, ["WuxianKit", "WxDemo"])
        self.assertEqual(py(s2.lua.eval(b"WuxianKit:Call('demo.volume.get', {})")), {"value": 5})   # its storage kept
        s3 = Session(self, fixtures=("WxDemo",), disabled=("WxDemo",))
        s3.login()
        exts = {e["id"]: e["state"] for e in py(s3.lua.eval(b"WuxianKit:Call('kit.extensions', {})"))}
        self.assertEqual(exts["demo"], "disabled")                         # turned off in the game's addon list
        self.sessions = [s, s2, s3]


if __name__ == "__main__":
    unittest.main()
