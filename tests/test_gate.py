"""远程 (Remote, gate) under Lua 5.1 in the mock client: two sessions are two players, and the addon messages one sends are
carried to the other as the client would, each sender named as this client names one ("Wuxian Forever": two parts). A
proposal handed to another player holds tune.* Change steps only; it is taken only from those the player allows (whole
names), shows as remote (pre-approval never counts for it) with its text escaped, one open at a time from each sender
and none for a while after one ended; a refusal says no more; its end comes back, and a result counts only from the one
it went to. The player's own broadcast heard back is not taken; a whisper to oneself comes back in the client."""
import unittest

from kitmock import Session, click, lupa, py, texts, type_into


@unittest.skipIf(lupa is None, "lupa (Lua 5.1 for Python) is not installed")
class Gate(unittest.TestCase):
    def start(self, name="Wuxian", surname="Forever"):
        s = Session(self)
        if name != "Wuxian":
            s.lua.execute(("local base = UnitName function UnitName(u) if u == 'player' then return '%s', '%s' end "
                           "return base(u) end" % (name, surname)).encode())
        s.lua.execute(b"__events = {} WuxianKit:On('*', function(topic, data) "
                      b"__events[#__events + 1] = { topic = topic, data = data } end)")
        s.login()
        s.run(1)
        s.carried = 0
        self.addCleanup(lambda: self.assertEqual(s.errors(), []))
        return s

    def call(self, s, cap, args="{}", opts="nil"):
        s.lua.execute(f"__answer = WuxianKit:Call({cap!r}, {args}, {opts})".encode())
        return py(s.g("__answer"))

    def fails(self, s, code):
        ok, err = s.lua.eval(f"pcall(function() {code} end)".encode())
        self.assertFalse(ok, code)
        return err.decode()

    def events(self, s, topic):
        return [e["data"] for e in py(s.g("__events")) or [] if e["topic"] == topic]

    def carry(self, src, dst, sender, name):
        """the addon messages src sent since the last carry reach dst, from sender (a whisper only when it is to name,
        whole or its first part)"""
        sent = src.g("__addon_sent")
        n = len(sent)
        for i in range(src.carried + 1, n + 1):
            m = sent[i]
            if m[b"channel"] == b"WHISPER" and m[b"target"].split(b" ")[0] != name.encode():
                continue
            dst.g("__fire")(b"CHAT_MSG_ADDON", m[b"prefix"], m[b"text"], m[b"channel"], sender.encode())
        src.carried = n

    def message(self, s, lua_table):
        """an addon message of the remote extension as one part on the wire"""
        return b"\4" + s.lua.eval(f"WuxianKit.Comm.Serialize({lua_table})".encode())

    def proposals(self, s):
        return py(s.lua.eval(b"WuxianKit:Proposals()")) or []

    def sent_id(self, s):
        """the id the last gate.propose that ran gave its proposal"""
        return self.proposals(s)[-1]["steps"][0]["result"]["id"]

    def run_it(self, s):
        click(s.g("WuxianKitProposal")[b"run"])

    def page(self, s, ext):
        if not (s.g("WuxianKitWindow") and s.g("WuxianKitWindow")[b"shown"]):
            s.g("SlashCmdList")[b"WUXIANKIT"](b"")
        w = s.g("WuxianKitWindow")
        items = w[b"items"]
        click(next(items[i] for i in range(1, len(items) + 1) if items[i][b"id"] == ext.encode()))
        return w

    def check(self, s, ext, label):
        w = self.page(s, ext)
        c = w[b"checks"]
        click(next(c[i] for i in range(1, len(c) + 1) if c[i][b"shown"] and c[i][b"label"][b"text"] == label.encode()))

    def names(self, s, text):
        w = self.page(s, "gate")
        type_into(next(e for e in w[b"edits"].values() if e[b"shown"]), text)

    def test_a_proposal_to_another_player(self):
        a, b = self.start(), self.start("Bob", "Smith")
        steps = "{ { cap = 'tune.cvar.set', args = { name = 'nameplateShowAll', value = 1 } } }"
        p = self.call(a, "gate.propose", f"{{ to = 'Bob Smith', title = 'Healer |cffff0000UI', steps = {steps} }}")
        self.assertEqual((p["steps"][0]["preview"], p["steps"][0]["scope"]),
                         (["To Bob Smith: Healer ||cffff0000UI (1 steps)", "1. tune.cvar.set name=nameplateShowAll value=1"],
                          "gate.propose"))
        self.run_it(a)
        self.carry(a, b, "Wuxian Forever", "Bob")
        gate = b.lua.eval(b"WuxianKit:Extension('gate')")
        self.assertEqual((gate[b"db"][b"blocked"], b.g("WuxianKitProposal")), (1, None))   # Bob takes none yet
        self.check(b, "tune", "Game settings")                             # Bob pre-approves game settings ...
        self.assertIn("Proposals: 0 accepted, 1 blocked", texts(self.page(b, "gate")[b"body"]))
        self.names(b, "Carol，Wuxian")                                     # a first part is not a name
        self.call(a, "gate.propose", f"{{ to = 'Bob Smith', title = 'Again', steps = {steps} }}")
        self.run_it(a)
        self.carry(a, b, "Wuxian Forever", "Bob")
        self.assertEqual((gate[b"db"][b"blocked"], b.g("WuxianKitProposal")), (2, None))
        self.names(b, "Carol，Wuxian Forever")
        self.call(a, "gate.propose", f"{{ to = 'Bob Smith', title = 'Healer |cffff0000UI', steps = {steps} }}")
        self.run_it(a)
        first = self.sent_id(a)
        self.carry(a, b, "Wuxian Forever", "Bob")
        mine = self.proposals(b)[-1]
        self.assertEqual((mine["state"], mine["source"], mine["title"], mine["steps"][0]["preview"][0]),
                         ("pending", "remote:Wuxian Forever", "Healer ||cffff0000UI", "nameplateShowAll: 0 → 1"))
        self.assertIn("From Wuxian Forever (remote)", "\n".join(texts(b.g("WuxianKitProposal"))))   # ... not a remote one
        self.call(a, "gate.propose", f"{{ to = 'Bob Smith', title = 'More', steps = {steps} }}")
        self.run_it(a)
        more = self.sent_id(a)
        self.carry(a, b, "Wuxian Forever", "Bob")
        self.carry(b, a, "Bob Smith", "Wuxian")
        self.assertEqual(self.events(a, "gate.result")[-1], {"from": "Bob Smith", "id": more, "state": "busy"})
        self.run_it(b)                                                      # Bob runs it
        self.assertEqual(b.lua.eval(b"__cvars.nameplateShowAll.value"), b"1")
        self.carry(b, a, "Bob Smith", "Wuxian")
        self.assertEqual(self.events(a, "gate.result")[-1], {"from": "Bob Smith", "id": first, "state": "done"})
        self.assertIn(f"Bob Smith · proposal #{first}: done", a.chat())
        self.call(a, "gate.propose", f"{{ to = 'Bob Smith', title = 'Soon', steps = {steps} }}")
        self.run_it(a)                                                      # within the cooldown: refused, no more said
        soon = self.sent_id(a)
        self.carry(a, b, "Wuxian Forever", "Bob")
        self.carry(b, a, "Bob Smith", "Wuxian")
        self.assertEqual(self.events(a, "gate.result")[-1], {"from": "Bob Smith", "id": soon, "state": "refused"})
        n = len(self.events(a, "gate.result"))
        a.g("__fire")(b"CHAT_MSG_ADDON", b"WKGATE", self.message(a, f"{{ k = 'r', id = {first}, state = 'done' }}"),
                      b"WHISPER", b"Mallory Evil")                          # a result from someone it did not go to
        self.assertEqual(len(self.events(a, "gate.result")), n)
        for args, why in (("{ title = 'x', steps = %s }" % steps, "one of to (a player) or channel"),
                          ("{ to = 'Bob', title = 'x', steps = {} }", "steps: 1 to 20"),
                          ("{ to = 'Bob', title = 'x', steps = { { cap = 'chat.send', args = { channel = 'say', "
                           "text = 'hi' } } } }", "each cap a tune.* one"),
                          ("{ channel = 'party', title = 'x', steps = %s }" % steps, "not in a group")):
            self.assertIn(why, self.fails(a, f"WuxianKit:Call('gate.propose', {args})"))

    def test_what_a_remote_proposal_may_hold(self):
        """only tune.* steps are taken (a chat message is refused, and the refusal says no more); text that comes in is
        escaped in the preview; an impostor sharing the first part of an allowed name, and the player's own broadcast
        heard back, are not taken"""
        b = self.start("Bob", "Smith")
        self.names(b, "Wuxian Forever")
        fire = b.g("__fire")
        chat = self.message(b, "{ k = 'p', id = 7, title = 'x', steps = { { 'chat.send', { channel = 'say', "
                               "text = 'WTS gold' } } } }")
        fire(b"CHAT_MSG_ADDON", b"WKGATE", chat, b"WHISPER", b"Wuxian Forever")
        self.assertEqual(self.proposals(b), [])
        reply = py(b.lua.eval(b"WuxianKit.Comm.Deserialize(__addon_sent[#__addon_sent].text:sub(2))"))
        self.assertEqual(reply, {"k": "r", "id": 7, "state": "refused"})
        macro = self.message(b, "{ k = 'p', id = 8, title = 'Heal', steps = { { 'tune.macro.set', { name = 'Heal', "
                                "value = '/cast Heal\\n|cff000000/run X()|r' } } } }")
        fire(b"CHAT_MSG_ADDON", b"WKGATE", macro, b"WHISPER", b"Wuxian Impostor")
        self.assertEqual(self.proposals(b), [])                             # a first part shared: not the one allowed
        fire(b"CHAT_MSG_ADDON", b"WKGATE", macro, b"WHISPER", b"Wuxian Forever")
        lines = self.proposals(b)[-1]["steps"][0]["preview"]
        self.assertIn("||cff000000/run X()||r", "\n".join(lines))            # nothing hidden in the preview
        a = self.start()
        own = self.message(a, "{ k = 'p', id = 9, title = 'mine', steps = { { 'tune.bags.sort', {} } } }")
        a.g("__fire")(b"CHAT_MSG_ADDON", b"WKGATE", own, b"PARTY", b"Wuxian Forever")
        self.assertEqual(self.proposals(a), [])                             # its own broadcast, heard back
        for cap in ("gate.ask", "gate.answer"):                              # no questions any more
            self.assertIsNone(a.lua.eval(f"WuxianKit:Capability('{cap}')".encode()))

    def test_to_oneself(self):
        """a whisper to oneself never leaves the client: it comes back at once, from the player's own whole name"""
        s = self.start()
        sent = len(s.g("__addon_sent"))
        self.call(s, "gate.propose", "{ to = 'Wuxian Forever', title = 'mine', steps = { { cap = 'tune.bags.sort' } } }")
        self.run_it(s)
        s.run(0.1)
        self.assertEqual(len(s.g("__addon_sent")), sent)                   # nothing went to the server
        mine = self.proposals(s)[-1]
        self.assertEqual((mine["state"], mine["source"], mine["title"]), ("pending", "remote:Wuxian Forever", "mine"))
        sent_id = self.proposals(s)[-2]["steps"][0]["result"]["id"]
        self.run_it(s)
        s.run(0.1)
        self.assertEqual(self.events(s, "gate.result")[-1], {"from": "Wuxian Forever", "id": sent_id, "state": "done"})


if __name__ == "__main__":
    unittest.main()
