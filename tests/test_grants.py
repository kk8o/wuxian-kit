"""Pre-approval (Proposals.lua) under Lua 5.1 in the mock client: scopes layered by their dots (a parent covers its
children), budgets { per, most } on a grant (only the steps that ran without the click count, each step of a proposal,
asked again right before it runs), the suggested budget, what is saved and loaded, ns.Grants and WuxianKit:Granted."""
import unittest
from unittest import mock

import kitmock
from kitmock import Session, click, lupa, py

DEMO = (b"local x = WuxianKit:Extension('demo', { title = 'Demo' }) "
        b"x:Scope('talk', 'Talk') x:Scope('talk.reply', 'Replies') x:Scope('talk.ask', 'Questions') "
        b"x:Say('say', { title = 'Say', args = { text = 'string', scope = 'string' }, "
        b"scope = function(_, a) return a.scope end, "
        b"preview = function(_, a) return 'Say ' .. a.text end, "
        b"apply = function(_, a) __said = __said or {} __said[#__said + 1] = a.text end })")


@unittest.skipIf(lupa is None, "lupa (Lua 5.1 for Python) is not installed")
class Grants(unittest.TestCase):
    def setUp(self):
        real = kitmock.run_files

        def keep_ns(test, lua, folder, ns=None):          # the core's private table, as __ns, for ns.Act and ns.Grants
            ns = real(test, lua, folder, ns)
            if folder == kitmock.KIT_DIR:
                lua.globals()[b"__ns"] = ns
            return ns

        patch = mock.patch.object(kitmock, "run_files", keep_ns)
        patch.start()
        self.addCleanup(patch.stop)

    def start(self, **kw):
        s = Session(self, **kw)
        s.login()
        s.lua.execute(DEMO)
        s.run(1)
        self.addCleanup(lambda: self.assertEqual(s.errors(), []))
        return s

    def grant(self, s, scope, on=True, budget="nil"):
        budget = "false" if budget is False else budget
        return s.lua.eval(f"__ns.Act('grant', {scope!r}, {'true' if on else 'false'}, {budget})".encode())

    def say(self, s, scope, text="hi", opts="{ source = 'agent' }"):
        s.lua.execute(f"__p = WuxianKit:Call('demo.say', {{ text = {text!r}, scope = {scope!r} }}, {opts})".encode())
        return py(s.g("__p"))

    def propose(self, s, *scopes, opts="{ source = 'agent' }"):
        steps = ", ".join(f"{{ 'demo.say', {{ text = 'm{i}', scope = {sc!r} }} }}" for i, sc in enumerate(scopes))
        s.lua.execute(f"__p = WuxianKit:Propose({{ {steps} }}, {opts})".encode())
        return py(s.g("__p"))

    def grants(self, s):
        return py(s.lua.eval(b"__ns.Grants()")) or {}

    def granted(self, s, scope):
        return s.lua.eval(f"WuxianKit:Granted({scope!r})".encode())

    def state(self, s, pid):
        return py(s.lua.eval(f"WuxianKit:Proposal({pid})".encode()))["state"]

    def test_layering(self):
        """a grant covers its scope and the ones below it; a child's grant covers neither its parent nor its siblings;
        the bare extension id never counts"""
        s = self.start()
        self.assertTrue(self.grant(s, "demo.talk.reply"))
        self.assertEqual(self.say(s, "talk.reply")["state"], "done")
        self.assertEqual(self.say(s, "talk")["state"], "pending")          # the child does not cover its parent
        self.assertEqual(self.say(s, "talk.ask")["state"], "pending")      # nor its sibling
        self.grant(s, "demo.talk")
        for scope in ("talk", "talk.ask", "talk.reply"):
            self.assertEqual(self.say(s, scope)["state"], "done", scope)
        self.assertEqual(self.propose(s, "talk", "talk.ask")["state"], "done")
        self.assertEqual(self.say(s, "talk", opts="{ source = 'remote:Somebody' }")["state"], "pending")
        self.assertEqual(self.say(s, "talk", opts="{ source = 'import:shared' }")["state"], "pending")
        self.grant(s, "demo.talk", on=False)
        self.grant(s, "demo")                                                # an extension id is no scope
        self.assertEqual(self.say(s, "talk")["state"], "pending")
        self.assertIs(self.granted(s, "demo.talk.reply"), True)             # no limit: no second value
        self.assertIs(self.granted(s, "demo.talk.reply.more"), True)
        self.assertEqual(self.granted(s, "demo.talk"), False)
        self.assertEqual(self.granted(s, "demo"), False)

    def test_a_budget(self):
        """up to `most` steps in `per` seconds run without the click, then it asks and its preview says why; the steps
        that ran leave the window after `per` seconds; a click does not count"""
        s = self.start()
        self.assertTrue(self.grant(s, "demo.talk", budget="{ per = 600, most = 2 }"))
        self.assertEqual(self.granted(s, "demo.talk.reply"), (True, 2))
        self.assertEqual([self.say(s, "talk.reply")["state"], self.say(s, "talk")["state"]], ["done", "done"])
        self.assertEqual(self.granted(s, "demo.talk"), (False, 0))
        p = self.say(s, "talk.reply", "third")
        self.assertEqual(p["state"], "pending")
        self.assertEqual(p["steps"][0]["preview"][0], "Say third")
        full = p["steps"][0]["preview"][-1]
        self.assertIn("Pre-approval limit reached (per ", full)
        self.assertIn(": at most 2)", full)
        click(s.g("WuxianKitProposal")[b"run"])                             # the player's click: runs, not counted
        s.run(1.5)
        self.assertEqual(self.state(s, p["id"]), "done")
        self.assertEqual(self.grants(s)["demo.talk"], {"per": 600, "most": 2, "used": 2})
        s.run(300, dt=1)
        self.assertEqual(self.say(s, "talk")["state"], "pending")          # still within the 600 s
        s.run(301, dt=1)                                                     # the first two are older than 600 s
        self.assertEqual(self.grants(s)["demo.talk"]["used"], 0)
        self.assertEqual(self.granted(s, "demo.talk"), (True, 2))
        self.assertEqual(self.say(s, "talk")["state"], "done")
        self.assertEqual(self.grants(s)["demo.talk"]["used"], 1)

    def test_every_step_counts(self):
        """a proposal of several steps counts each step under its grant, and goes over the budget as a whole"""
        s = self.start()
        self.grant(s, "demo.talk", budget="{ per = 60, most = 3 }")
        self.grant(s, "demo.talk.ask", budget=False)                         # a nearer grant without a limit
        self.assertEqual(self.say(s, "talk")["state"], "done")
        self.assertEqual(self.propose(s, "talk", "talk.reply", "talk.ask")["state"], "done")
        self.assertEqual(self.grants(s), {"demo.talk": {"per": 60, "most": 3, "used": 3}, "demo.talk.ask": {}})
        self.assertEqual(self.say(s, "talk.ask")["state"], "done")          # its own grant: no limit
        s.run(61, dt=1)
        self.say(s, "talk")
        p = self.propose(s, "talk", "talk.reply", "talk.ask")                # 1 + 2 under demo.talk = 3: runs
        self.assertEqual(p["state"], "done")
        s.run(61, dt=1)
        self.say(s, "talk")
        self.say(s, "talk")
        p = self.propose(s, "talk", "talk.reply")                            # 2 + 2 > 3: asks, the line once
        self.assertEqual(p["state"], "pending")
        self.assertEqual(len([line for st in p["steps"] for line in st["preview"] if "limit reached" in line]), 1)
        self.assertIn("limit reached", p["steps"][0]["preview"][-1])

    def test_asked_again_before_it_runs(self):
        """a proposal that was to run without the click later (after) asks when the budget is spent by the time it would
        run; one that does not go over runs and is counted then"""
        s = self.start()
        self.grant(s, "demo.talk", budget="{ per = 600, most = 1 }")
        later = self.say(s, "talk", "later", opts="{ source = 'agent', after = time() + 5 }")
        self.assertEqual((later["state"], later["auto"]), ("waiting", True))
        self.assertEqual(self.grants(s)["demo.talk"]["used"], 0)            # not counted before it runs
        self.assertEqual(self.say(s, "talk", "now")["state"], "done")
        s.run(6)
        p = py(s.lua.eval(f"WuxianKit:Proposal({later['id']})".encode()))
        self.assertEqual((p["state"], p.get("auto")), ("pending", None))
        self.assertIn("limit reached", p["steps"][0]["preview"][-1])
        self.assertIn(f"Proposal #{later['id']}: Pre-approval limit reached", s.chat())
        self.assertEqual(self.grants(s)["demo.talk"]["used"], 1)
        s2 = self.start()                                                    # within the budget: counted when it runs
        self.grant(s2, "demo.talk", budget="{ per = 600, most = 1 }")
        later = self.say(s2, "talk", "later", opts="{ source = 'agent', after = time() + 5 }")
        s2.run(6)
        self.assertEqual(self.state(s2, later["id"]), "done")
        self.assertEqual(self.grants(s2)["demo.talk"]["used"], 1)

    def test_budget_choices(self):
        """none takes the scope's suggested budget (unlimited without one), false no limit, a table in range a budget;
        one out of range changes nothing; taking the grant back drops it"""
        s = self.start()
        self.grant(s, "demo.talk")
        self.assertEqual(self.grants(s), {"demo.talk": {}})                 # no suggestion: no limit
        s.lua.execute(b"__ns.ScopeBudget = function(scope) if scope == 'demo.talk' then "
                      b"return { per = 3600, most = 5 } end end")
        self.grant(s, "demo.talk")
        self.grant(s, "demo.talk.ask")
        self.assertEqual(self.grants(s), {"demo.talk": {"per": 3600, "most": 5, "used": 0}, "demo.talk.ask": {}})
        self.grant(s, "demo.talk", budget=False)
        self.assertEqual(self.grants(s)["demo.talk"], {})
        for bad in ("{ per = 59, most = 1 }", "{ per = 86401, most = 1 }", "{ per = 60, most = 0 }",
                    "{ per = 60, most = 101 }", "{ per = 'x', most = 1 }", "{ per = 1/0, most = 1 }", "{}", "'some'"):
            self.assertFalse(self.grant(s, "demo.talk", budget=bad), bad)
        self.assertEqual(self.grants(s)["demo.talk"], {})                    # unchanged
        self.assertTrue(self.grant(s, "demo.talk", budget="{ per = 60.5, most = 100 }"))
        self.assertEqual(self.grants(s)["demo.talk"], {"per": 60, "most": 100, "used": 0})
        self.grant(s, "demo.talk", on=False)
        self.assertNotIn("demo.talk", self.grants(s))
        self.assertFalse(s.lua.eval(b"__ns.Act('grant', 5, true)"))

    def test_saved_and_loaded(self):
        """grants with a budget are saved as { per, most }, without one as true; loading takes true and valid tables
        (an old save's true is no limit) and drops the rest"""
        s = self.start()
        self.grant(s, "demo.talk", budget="{ per = 120, most = 3 }")
        self.grant(s, "demo.talk.ask", budget=False)
        s.fire("PLAYER_LOGOUT")
        self.assertEqual(py(s.g("WuxianKitDB"))["grants"],
                         {"demo.talk": {"per": 120, "most": 3}, "demo.talk.ask": True})
        s2 = s.reload()
        s2.login()
        s2.lua.execute(DEMO)
        s2.run(1)
        self.addCleanup(lambda: self.assertEqual(s2.errors(), []))
        self.assertEqual(self.grants(s2), {"demo.talk": {"per": 120, "most": 3, "used": 0}, "demo.talk.ask": {}})
        old = self.start(saved={"WuxianKitDB": b"{ grants = { ['demo.talk'] = true, ['demo.a'] = { per = 5, most = 1 }, "
                                               b"['demo.b'] = 'yes', ['demo.c'] = { per = 120, most = 3 }, [7] = true } }"})
        self.assertEqual(self.grants(old), {"demo.talk": {}, "demo.c": {"per": 120, "most": 3, "used": 0}})
        self.assertEqual(self.say(old, "talk.reply")["state"], "done")

    def test_the_window_still_ticks(self):
        """the window's check box (ns.Act without a budget) grants and takes back as before"""
        s = self.start()
        s.g("SlashCmdList")[b"WUXIANKIT"](b"")
        w = s.g("WuxianKitWindow")
        items = w[b"items"]
        click(next(items[i] for i in range(1, len(items) + 1) if items[i][b"id"] == b"demo"))
        c = w[b"checks"]
        boxes = {c[i][b"label"][b"text"].decode(): c[i] for i in range(1, len(c) + 1) if c[i][b"shown"]}
        click(boxes["Replies"])
        self.assertEqual(self.grants(s), {"demo.talk.reply": {}})
        self.assertEqual(self.say(s, "talk.reply")["state"], "done")


if __name__ == "__main__":
    unittest.main()
