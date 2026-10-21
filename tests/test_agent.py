"""WuxianKit and the AI agent, end to end through 无限工坊's real WoWBridge, link and Service: the workshop's own mock
client (its tests.support.wowmock) with the kit's API mock (kitmock.KIT) on top and WuxianKit from this repo. Needs the
workshop's source (the environment variable WUXIAN_WORKSHOP names its folder) and its Python packages; skipped without
them."""
import asyncio
import os
import sys
import unittest
from pathlib import Path

from kitmock import KIT, KIT_DIR, install, py, run_files

WORKSHOP = Path(os.environ.get("WUXIAN_WORKSHOP") or "/nonexistent")
try:
    if not (WORKSHOP / "src" / "wuxianworkshop").is_dir():
        raise ImportError("WUXIAN_WORKSHOP does not name 无限工坊's source")
    sys.path[:0] = [str(WORKSHOP), str(WORKSHOP / "src")]
    from tests.support.wowmock import Session, lupa                  # the workshop's tests package
    from wuxianworkshop.daemon.api import ApiError, parse_run
    from wuxianworkshop.daemon.journal import Journal
    from wuxianworkshop.daemon.service import Service
    from wuxianworkshop.transport import link
except ImportError as e:                                               # pragma: no cover
    Session = lupa = None
    MISSING = str(e)


@unittest.skipIf(Session is None or lupa is None, "无限工坊's source is not there (WUXIAN_WORKSHOP)")
class Agent(unittest.TestCase):
    def setUp(self):
        self.got, self.journal = [], Journal()
        s = Session(self)
        self.addCleanup(s.close)
        lua = s.lua
        lua.execute(KIT.encode(), lua.table_from({b"load_addon": lambda name: None}))
        install(lua, [KIT_DIR], loaded=("WuxianKit",))
        run_files(self, lua, KIT_DIR)
        s.loaded.append("WuxianKit")

        def on_debug(kind, text):
            self.got.append((kind, text))
            self.journal.add(kind, text)
        comp = link.Companion(s.addons, clock=s.now, log=lambda text: None, on_debug=on_debug)
        s.comp = comp
        svc = Service(lambda **kw: None, journal=self.journal)
        got = self.got

        async def data(verb, payload, timeout_ms=10000, what="call"):     # the daemon's data call, over this session
            job = comp.data_call(verb, payload)
            for _ in range(400):
                s.run(0.25)
                text = next((t for k, t in got if k == "RUN" and t.startswith(f"{job} ")), None)
                if text is not None:
                    return job, Service.run_result(parse_run(text))
            self.fail(f"no RUN result for data call {job}")
        svc.data, svc.data_calls = data, comp.data_calls
        comp.new_process("P1-100")
        s.login()
        s.run(8)
        self.s, self.svc = s, svc

    def events(self, topic):
        return asyncio.run(self.svc.addon_events(addon="WuxianKit", topic=topic, limit=1000))["events"]

    def call(self, name, args=None):
        return asyncio.run(self.svc.call_exposed("WuxianKit", name, args))["result"]

    def test_the_agent_calls_and_hears(self):
        s, svc = self.s, self.svc
        api = asyncio.run(svc.addon_api("WuxianKit"))
        names = [e["name"] for e in api["exposed"]]
        for want in ("kit.propose", "kit.extensions", "kit.extension.set", "kit.undo", "tune.cvar.set", "tune.cvar.find",
                     "chat.send", "chat.listen", "chat.listen.stop"):
            self.assertIn(want, names)
        doc = next(e["doc"] for e in api["exposed"] if e["name"] == "tune.cvar.set")
        self.assertTrue(doc.startswith("[Change: a proposal.] proposes to change a client setting (CVar)"), doc)
        self.assertIn("Options: _title, _ttl", doc)
        ready = self.events("kit.ready")[0]["data"]
        self.assertEqual({e["id"] for e in ready["extensions"]}, {"kit", "chat", "tune", "gate", "data", "guide", "sense", "codex"})
        found = self.call("tune.cvar.find", {"text": "maxdistance", "limit": 1})
        self.assertEqual([c["name"] for c in found], ["nameplateMaxDistance"])
        s.slash("set hotLoad off")                                        # only data calls from here on
        res = self.call("tune.cvar.set", {"name": "nameplateShowAll", "value": 1, "_title": "show all nameplates"})
        self.assertEqual((res["state"], res["source"], res["title"]), ("pending", "agent", "show all nameplates"))
        plain = lambda p: [line for st in p["steps"] for line in st["preview"]]          # the agent reads no color codes
        self.assertTrue(plain(res) and not any("|c" in line or "|r" in line for line in plain(res)), plain(res))
        self.assertIn("If true, nameplates are shown all the time.", plain(res))      # the help line, its color gone
        s.run(4)
        self.assertEqual([e["data"]["state"] for e in self.events("kit.proposal")], ["pending"])
        run = s.lua.globals()[b"WuxianKitProposal"][b"run"]
        run.Click(run)
        s.run(4)
        done = self.events("kit.proposal")[-1]["data"]
        self.assertEqual((done["id"], done["state"]), (res["id"], "done"))
        self.assertEqual(plain(done), plain(res))                                  # the event as plain as the answer
        self.assertEqual(s.lua.globals()[b"__cvars"][b"nameplateShowAll"][b"value"], b"1")
        ran = self.call("kit.history")[-1]
        self.assertEqual((ran["id"], set(ran["steps"][0]), plain(ran)), (res["id"], {"cap", "args", "preview"}, plain(res)))
        both = self.call("kit.propose", {"title": "quieter", "steps": [
            {"cap": "tune.cvar.set", "args": {"name": "Sound_MasterVolume", "value": 0.3}},
            {"cap": "chat.send", "args": {"channel": "guild", "text": "brb"}}]})
        self.assertEqual([st["cap"] for st in both["steps"]], ["tune.cvar.set", "chat.send"])
        with self.assertRaises(ApiError) as cm:
            self.call("tune.cvar.set", {"name": "secureThing", "value": 0})
        self.assertIn("secureThing is secure", cm.exception.message)
        self.call("chat.listen", {"channels": ["guild"], "minutes": 5})
        s.lua.globals()[b"__fire"](b"CHAT_MSG_GUILD", b"anyone know the way?", b"Asker-Realm", b"", b"", b"", b"", 0, 0, b"", 1,
                                   90, b"Player-1-00000002")
        s.run(4)
        heard = self.events("chat.message")[-1]["data"]
        self.assertEqual((heard["plain"], heard["sender"], heard["channel"]), ("anyone know the way?", "Asker", "guild"))
        self.assertEqual(self.events("kit.feed")[-1]["data"]["feed"], "listen")
        self.assertEqual(py(s.lua.eval(b"__errors")) or [], [])


if __name__ == "__main__":
    unittest.main()
