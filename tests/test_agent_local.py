"""An app a local extension drives (driver "local"), end to end: 无限工坊 0.10.0's own manifest check and declaration
(local/manifest.py, local/adds.py), its real WoWBridge, link and Service, and WuxianKit from this repo. What the
workshop sends is what WuxianKit takes: the roster (kit.local.set), the declaration, kit.app.open without minutes,
kit.app.report, the heartbeat, kit.app.recent and kit.app.stop with why "extension". Needs WUXIAN_WORKSHOP, as
test_agent.py does; skipped without it."""
import asyncio
import json
import tempfile
import unittest
from pathlib import Path

import test_agent
from test_agent import Session, lupa

MANIFEST = {
    "id": "ledger", "title": "账本", "version": "0.1.0", "run": ["python", "main.py"],
    "apps": [{"app": "ledger", "title": "账本", "driver": "local", "hear": ["game:quest"],
              "controls": ["stop", {"cmd": "export", "label": "导出", "call": "export"}]}],
}


@unittest.skipIf(Session is None or lupa is None, "无限工坊's source is not there (WUXIAN_WORKSHOP)")
class LocalApp(test_agent.Agent):
    def declaration(self):
        from wuxianworkshop.local import adds, manifest
        with tempfile.TemporaryDirectory() as d:
            (Path(d) / "wuxian-extension.json").write_text(json.dumps(MANIFEST, ensure_ascii=False), encoding="utf-8")
            (Path(d) / "main.py").write_text("", encoding="utf-8")
            m, problems = manifest.check_manifest(d)
        self.assertIsNotNone(m, problems)
        self.assertEqual(m["start"], "workshop")                       # derived from driver "local"
        return adds.declaration(m["apps"][0], m["id"], m["title"])

    def roster(self, running):
        return {"extensions": [{"id": "ledger", "title": "账本", "version": "0.1.0", "where": "local", "on": True,
                                "running": running, "addons": []}]}

    def test_the_workshop_drives_it(self):
        ApiError = test_agent.ApiError
        self.call("kit.local.set", self.roster(True))
        self.call("kit.app.declare", self.declaration())
        row = next(r for r in self.call("kit.apps") if r["id"] == "ledger")
        self.assertEqual((row["driver"], row["on"], row["local"]["id"]), ("local", False, "ledger"))

        status = self.call("kit.app.open", {"app": "ledger"})          # as local/drive.py opens it: no minutes
        self.assertTrue(status["on"])
        self.assertEqual(status.get("by"), "local")
        self.assertIsNone(status.get("ends"))                          # it does not expire
        self.assertTrue(status.get("lease"))                           # the heartbeat's lease is there all the same
        self.s.run(2)
        on = [e["data"] for e in self.events("kit.app") if e["data"].get("app") == "ledger"]
        self.assertTrue(on and on[-1]["on"])

        with self.assertRaises(ApiError):                              # minutes and driver "local" do not go together
            self.call("kit.app.open", {"app": "ledger", "minutes": 30})

        report = {"app": "ledger", "key": "1794938824:Horde", "state": "run", "step": "fetch", "text": "取回中",
                  "done": 3, "total": 36, "data": {"n": 376047}, "at": 1794938900}
        self.assertEqual(self.call("kit.app.report", report), {"kept": True})
        self.assertEqual(self.call("kit.app.report", dict(report, state="done", step="submit", text="审核后发布",
                                                          late=True)), {"kept": True})
        with self.assertRaises(ApiError):                              # only an app a local extension drives
            self.call("kit.app.report", dict(report, app="nobody"))

        self.assertTrue(self.call("kit.app.status", {"app": "ledger"})["on"])              # the heartbeat
        recent = self.call("kit.app.recent", {"app": "ledger", "since": 0, "limit": 100})
        self.assertIn("items", recent)

        self.call("kit.app.stop", {"app": "ledger", "why": "extension"})                   # its process ended
        self.s.run(2)
        off = [e["data"] for e in self.events("kit.app") if e["data"].get("app") == "ledger"][-1]
        self.assertEqual((off["on"], off.get("why")), (False, "extension"))
        self.assertFalse(self.call("kit.app.status", {"app": "ledger"})["on"])


if __name__ == "__main__":
    unittest.main()
