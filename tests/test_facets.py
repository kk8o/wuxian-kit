"""Facets (状态面): ext:Facet registers a state apps see; an app declares see = { names } and each of its wakes carries
state = { [name] = read() }; kit.app.state reads it at once (a heartbeat); a facet's on and off follow whether an app
that runs sees it; its extension off stops those apps and blocks them; a remembered declaration keeps a facet not
registered yet (blocked until it is); a state is cut to FACET_MAX; the core's me and sense's group; the manifest."""
import unittest

from kitmock import py
from test_apps import AppCase

# an extension of the test's, with a facet whose on and off are counted and whose read gives __probe
PROBE = b"""
__ons, __offs, __probe = 0, 0, { n = 1 }
__px = WuxianKit:Extension('probe', { title = 'Probe' })
__px:Facet('probe', { title = 'Probe', doc = 'a probe', fields = { n = 'number' },
	read = function() return __probe end,
	on = function() __ons = __ons + 1 end,
	off = function() __offs = __offs + 1 end })
"""


class FacetCase(AppCase):
    def probe(self, s):
        s.lua.execute(PROBE)
        s.run(0.1)                                                         # (another addon's: on a moment later)
        return s

    def counts(self, s):
        return self.lua(s, "__ons"), self.lua(s, "__offs")

    def raises(self, s, code):
        ok, err = s.lua.eval(f"pcall(function() {code} end)".encode())
        self.assertFalse(ok, code)
        return err.decode()


class Register(FacetCase):
    def test_the_spec_is_checked(self):
        s = self.probe(self.start())
        self.assertIn("a facet's name is lowercase", self.raises(s, "__px:Facet('Bad', { read = print })"))
        self.assertIn("a facet's name is lowercase", self.raises(s, "__px:Facet(('x'):rep(25), { read = print })"))
        self.assertIn("facet x's spec has read(self)", self.raises(s, "__px:Facet('x', {})"))
        self.assertIn("facet x's on is a function", self.raises(s, "__px:Facet('x', { read = print, on = 1 })"))
        self.assertIn("facet x's fields is a table", self.raises(s, "__px:Facet('x', { read = print, fields = 'n' })"))
        self.assertIn("probe: the facet me is extension kit's", self.raises(s, "__px:Facet('me', { read = print })"))
        s.lua.execute(b"__px:Facet('probe', { title = 'Probe 2', read = function() return { n = 2 } end })")   # replaced
        self.assertEqual(self.lua(s, "#__px.facetOrder"), 1)
        self.assertEqual(py(s.ns.FacetRead(s.ns.facets[b"probe"])), {"n": 2})

    def test_the_manifest(self):
        s = self.probe(self.start())
        m = self.lua(s, "WuxianKit:Manifest()")
        ext = {e["id"]: e for e in m["extensions"]}
        [me] = ext["kit"]["facets"]
        self.assertEqual((me["name"], me["title"], me["fields"]["xp"], me["fields"]["level"]),
                         ("me", "The player now", "number?", "number"))
        self.assertIn("dead (dead or a ghost)", me["doc"])
        self.assertEqual([f["name"] for f in ext["sense"]["facets"]], ["group"])
        self.assertEqual(ext["probe"]["facets"], [{"name": "probe", "title": "Probe", "doc": "a probe",
                                                   "fields": {"n": "number"}}])
        self.assertEqual(ext["chat"]["facets"], {})
        rev = m["revision"]
        self.opens(s, "{ app = 'v', hear = { 'bus:demo.*' }, see = { 'me', 'probe' } }")
        m = self.lua(s, "WuxianKit:Manifest()")
        self.assertEqual(next(a for a in m["apps"] if a["id"] == "v")["see"], ["me", "probe"])
        self.assertNotEqual(m["revision"], rev)
        doc = next(c for c in self.agent(s, "kit.capabilities") if c["id"] == "kit.app.declare")["doc"]
        self.assertIn("see (at most 8 states", doc)
        self.assertIn("me: the player now", doc)
        self.assertIn("group: the player's group now", doc)
        self.assertIn("probe: a probe", doc)
        self.assertNotIn("me (the items", doc)
        caps = [c["id"] for c in self.agent(s, "kit.capabilities")]
        self.assertIn("kit.app.state", caps)


class Declare(FacetCase):
    def test_see_is_checked(self):
        s = self.start()
        err = self.fails(s, "kit.app.declare", "{ app = 'v', hear = { 'bus:demo.*' }, see = { 'nope' } }")
        self.assertIn("see: no state nope (the states: group, me, route, today)", err)
        err = self.fails(s, "kit.app.declare", "{ app = 'v', see = { 'a', 'b', 'c', 'd', 'e', 'f', 'g', 'h', 'i' } }")
        self.assertIn("see is a list of at most 8 states", err)
        self.assertIn("see: 3 is not a state's name", self.fails(s, "kit.app.declare", "{ app = 'v', see = { 3 } }"))
        self.assertIn("no argument me", self.fails(s, "kit.app.declare", "{ app = 'v', hear = { 'bus:x' }, me = true }"))
        st = self.opens(s, "{ app = 'v', hear = { 'bus:demo.*' }, see = { 'me', 'group', 'me' } }")
        self.assertEqual((st["on"], st["see"]), (True, ["me", "group"]))
        self.assertEqual(next(a for a in self.agent(s, "kit.apps") if a["id"] == "v")["see"], ["me", "group"])
        self.assertNotIn("see", next(a for a in self.agent(s, "kit.apps") if a["id"] == "guild"))   # none: not listed
        st = self.agent(s, "kit.app.declare", "{ app = 'p', see = { 'me' } }")
        self.assertEqual(st["see"], ["me"])

    def test_a_remembered_declaration_waits_for_its_facet(self):
        s = self.start()
        s.lua.execute(b"WuxianKitDB.apps.later = { decl = { title = 'Later', hear = { 'bus:demo.*' }, see = { 'probe' } } }")
        s2 = self.start(s.reload())
        st = self.agent(s2, "kit.app.status", "{ app = 'later' }")
        self.assertEqual((st["on"], st["see"], st["blocked"]), (False, ["probe"], "Needs the state probe"))
        st = self.agent(s2, "kit.app.open", "{ app = 'later' }")
        self.assertEqual((st["on"], st["blocked"]), (False, "Needs the state probe"))
        self.probe(s2)                                                      # its addon has loaded
        st = self.agent(s2, "kit.app.open", "{ app = 'later' }")
        self.assertEqual(st["on"], True)
        self.assertEqual(self.counts(s2), (1, 0))


class Wakes(FacetCase):
    def test_each_wake_carries_the_state_read_then(self):
        s = self.probe(self.start())
        self.opens(s, "{ app = 'v', hear = { 'bus:demo.*' }, see = { 'me', 'group', 'probe' } }")
        self.opens(s, "{ app = 'plain', hear = { 'bus:demo.*' } }")
        s.lua.execute(b"WuxianKit:Emit('demo.x', 1)")
        [w] = self.wakes(s, "v")
        me = w["state"]["me"]
        self.assertEqual((me["name"], me["level"], me["class"], me["combat"], me["dead"], me["resting"], me["xp"]),
                         ("Wuxian Forever", 8, "Priest", False, False, False, 3))       # 190 of 5400: 3 %
        self.assertEqual(w["state"]["group"], {"kind": "solo", "size": 1})
        self.assertEqual(w["state"]["probe"], {"n": 1})
        self.assertNotIn("me", w["items"][0])
        [p] = self.wakes(s, "plain")
        self.assertNotIn("state", p)                                       # no see: no state
        s.lua.execute(b"__probe = { n = 2 } __group = { { name = 'Ann', class = 'MAGE', level = 9 } } "
                      b"function IsResting() return true end")
        s.lua.execute(b"WuxianKit:Emit('demo.x', 2)")
        w = self.wakes(s, "v")[1]
        self.assertEqual((w["state"]["probe"], w["state"]["group"], w["state"]["me"]["resting"]),
                         ({"n": 2}, {"kind": "party", "size": 2}, True))

    def test_kit_app_state_reads_at_once_and_is_a_heartbeat(self):
        s = self.probe(self.start())
        self.opens(s, "{ app = 'v', hear = { 'bus:demo.*' }, see = { 'probe', 'me' } }")
        s.run(30)
        r = self.agent(s, "kit.app.state", "{ app = 'v' }")
        now = s.lua.eval(b"time()")
        self.assertEqual((r["app"], r["at"], r["state"]["probe"], r["state"]["me"]["level"]), ("v", now, {"n": 1}, 8))
        self.assertEqual(self.agent(s, "kit.app.status", "{ app = 'v' }")["seen"], now)
        self.assertEqual(self.agent(s, "kit.app.state", "{ app = 'guild' }")["state"], {})    # it sees nothing
        self.assertIn("no app ghost", self.fails(s, "kit.app.state", "{ app = 'ghost' }"))
        s.lua.execute(b"__probe = nil")
        self.assertNotIn("probe", self.agent(s, "kit.app.state", "{ app = 'v' }")["state"])   # none now

    def test_the_items_wait_not_the_state(self):
        s = self.start()
        s.lua.execute(b"""
		local px = WuxianKit:Extension('fat', { title = 'Fat' })
		for i = 1, 8 do
			px:Facet('fat' .. i, { read = function() return { text = ('x'):rep(560) } end })
		end""")
        s.run(0.1)
        see = ", ".join(f"'fat{i}'" for i in range(1, 9))
        self.opens(s, f"{{ app = 'v', hear = {{ 'bus:demo.*' }}, see = {{ {see} }}, "
                                      f"digest = {{ gather = 0, every = 10, most = 30 }} }}")
        for i in range(12):
            s.lua.execute(f"WuxianKit:Emit('demo.x', ('y'):rep(300))".encode())
        s.run(14)
        ws = self.wakes(s, "v")
        self.assertLess(len(ws[0]["items"]), 12)                           # what did not fit: with the next wake
        self.assertEqual((sum(len(w["items"]) for w in ws), sum(w["skipped"] for w in ws)), (12, 0))
        for w in ws:
            self.assertEqual(sorted(w["state"]), [f"fat{i}" for i in range(1, 9)])
            self.assertTrue(all("text" in f for f in w["state"].values()))  # whole, each of them
        for e in s.lua.eval(b"__events").values():                         # as WoWBridge writes it: its line is 8000
            if e.topic == b"app.v":
                self.assertLessEqual(s.ns.WireSize(e.data), 7200)


class Cut(FacetCase):
    def read(self, s, literal):
        s.lua.execute(b"__probe = " + literal.encode())
        v = s.ns.FacetRead(s.ns.facets[b"probe"])
        size = s.lua.eval(b"function(v) return #WuxianKit.Comm.Serialize(v) end")(v)
        return py(v), size

    def test_a_big_state_is_cut(self):
        s = self.probe(self.start())
        v, size = self.read(s, "{ n = 5, name = ('名'):rep(100) }")             # 300 bytes: as it is
        self.assertEqual((v["n"], v["name"], v.get("cut")), (5, "名" * 100, None))
        v, size = self.read(s, "{ key = 'k', goals = (function() local t = {} for i = 1, 40 do t[i] = { op = 'kill', "
                               "target = 'Raptor ' .. i } end return t end)() }")
        self.assertLessEqual(size, 600)
        self.assertIs(v["cut"], True)
        self.assertEqual(v["key"], "k")
        self.assertEqual(v["goals"][0], {"op": "kill", "target": "Raptor 1"})   # the first stay, the last go
        self.assertLess(len(v["goals"]), 40)
        v, size = self.read(s, "{ text = ('x'):rep(2000), more = ('y'):rep(2000) }")   # texts shorten
        self.assertLessEqual(size, 600)
        self.assertIs(v["cut"], True)
        self.assertTrue(v["text"].startswith("xxx"))
        v, size = self.read(s, "'not a table'")
        self.assertIsNone(v)


class OnOff(FacetCase):
    def test_on_with_the_first_app_off_with_the_last(self):
        s = self.probe(self.start())
        self.assertEqual(self.counts(s), (0, 0))
        self.agent(s, "kit.app.declare", "{ app = 'a', hear = { 'bus:demo.*' }, see = { 'probe' } }")
        self.assertEqual(self.counts(s), (0, 0))                           # declared, not running: nobody looks
        self.agent(s, "kit.app.open", "{ app = 'a' }")
        self.assertEqual(self.counts(s), (1, 0))
        self.opens(s, "{ app = 'b', hear = { 'bus:demo.*' }, see = { 'probe' } }")
        self.agent(s, "kit.app.open", "{ app = 'a' }")                     # goes on: still one look of a's
        self.assertEqual(self.counts(s), (1, 0))
        self.agent(s, "kit.app.stop", "{ app = 'a' }")
        self.assertEqual(self.counts(s), (1, 0))
        self.opens(s, "{ app = 'b', hear = { 'bus:demo.*' }, see = { 'me' } }")   # b no longer sees it
        self.assertEqual(self.counts(s), (1, 1))
        self.agent(s, "kit.app.open", "{ app = 'a' }")
        self.assertEqual(self.counts(s), (2, 1))
        s.run(7201)                                                        # its time is up
        self.assertEqual(self.counts(s), (2, 2))

    def test_its_extension_off_stops_the_apps_that_see_it(self):
        s = self.probe(self.start())
        self.opens(s, "{ app = 'a', hear = { 'bus:demo.*' }, see = { 'probe' } }")
        self.opens(s, "{ app = 'b', hear = { 'bus:demo.*' }, see = { 'me' } }")
        s.ns.Switch(b"probe", False)
        self.assertEqual(self.counts(s), (1, 1))
        st = self.agent(s, "kit.app.status", "{ app = 'a' }")
        self.assertEqual((st["on"], st["why"], st["blocked"]), (False, "extension", "Needs the Probe extension on"))
        self.assertIs(self.agent(s, "kit.app.status", "{ app = 'b' }")["on"], True)   # it does not see it
        st = self.agent(s, "kit.app.open", "{ app = 'a' }")
        self.assertEqual((st["on"], st["blocked"]), (False, "Needs the Probe extension on"))
        s.ns.Switch(b"probe", True)
        self.assertEqual(self.counts(s), (1, 1))                           # nobody looks now
        self.agent(s, "kit.app.open", "{ app = 'a' }")
        self.assertEqual(self.counts(s), (2, 1))
        s.ns.Switch(b"sense", False)                                        # another's: a goes on
        self.assertIs(self.agent(s, "kit.app.status", "{ app = 'a' }")["on"], True)

    # the same facet again with its on and off counted apart from the first one's (__ons2, __offs2)
    AGAIN = (b"__ons2, __offs2 = 0, 0 "
             b"__px:Facet('probe', { title = 'Probe 2', read = function() return { n = 2 } end, "
             b"on = function() __ons2 = __ons2 + 1 end, off = function() __offs2 = __offs2 + 1 end })")

    def counts2(self, s):
        return self.lua(s, "__ons2"), self.lua(s, "__offs2")

    def test_registered_again_while_an_app_looks(self):
        s = self.probe(self.start())
        self.opens(s, "{ app = 'a', hear = { 'bus:demo.*' }, see = { 'probe' } }")
        self.opens(s, "{ app = 'b', hear = { 'bus:demo.*' }, see = { 'probe' } }")
        s.lua.globals()[b"__ns"] = s.ns
        s.lua.execute(b"__facet = __ns.facets.probe")
        s.lua.execute(self.AGAIN)                                          # a hot reload of its addon
        self.assertEqual(self.counts(s), (1, 1))                           # the old on has its off
        self.assertEqual(self.counts2(s), (1, 0))                          # the new one is looked at: on, once
        self.assertTrue(s.lua.eval(b"__ns.facets.probe == __facet and __facet.spec.title == 'Probe 2'"))   # the same facet
        self.assertEqual(s.ns.facets[b"probe"][b"n"], 2)                   # each app counted once
        self.assertEqual(self.agent(s, "kit.app.state", "{ app = 'a' }")["state"]["probe"], {"n": 2})
        self.agent(s, "kit.app.stop", "{ app = 'a' }")
        self.assertEqual(self.counts2(s), (1, 0))                          # b still looks
        self.agent(s, "kit.app.stop", "{ app = 'b' }")
        self.assertEqual(self.counts2(s), (1, 1))                          # the last one stopped: off, once
        self.assertEqual(self.counts(s), (1, 1))
        self.assertEqual(s.ns.facets[b"probe"][b"n"], 0)
        s.lua.execute(self.AGAIN)                                          # nobody looks: neither is called
        self.assertEqual(self.counts2(s), (0, 0))
        self.agent(s, "kit.app.open", "{ app = 'a' }")
        self.agent(s, "kit.app.stop", "{ app = 'a' }")
        self.assertEqual(self.counts2(s), (1, 1))

    def test_registered_again_while_its_extension_is_off(self):
        s = self.probe(self.start())
        watcher = s.lua.eval(b"{}")
        s.ns.FacetWatch(s.ns.facets[b"probe"], watcher, True)
        s.ns.Switch(b"probe", False)
        self.assertEqual(self.counts(s), (1, 1))
        s.lua.execute(self.AGAIN)                                          # off already: nothing to pair
        self.assertEqual((self.counts(s), self.counts2(s)), ((1, 1), (0, 0)))
        s.ns.Switch(b"probe", True)                                        # still looked at: the new one's on
        self.assertEqual(self.counts2(s), (1, 0))
        s.ns.FacetWatch(s.ns.facets[b"probe"], watcher, False)
        self.assertEqual((self.counts(s), self.counts2(s)), ((1, 1), (1, 1)))

    def test_taken_back(self):
        s = self.probe(self.start())
        facet, watcher = s.ns.facets[b"probe"], s.lua.eval(b"{}")
        s.ns.FacetWatch(facet, watcher, True)
        s.lua.execute(b"__px:Facet('probe', nil)")
        self.assertEqual(self.counts(s), (1, 1))                           # looked at: its off
        self.assertIsNone(s.ns.facets[b"probe"])
        self.assertTrue(facet[b"gone"])
        self.assertEqual((self.lua(s, "#__px.facetOrder"), py(s.ns.facetOrder).count("probe")), (0, 0))
        s.ns.FacetWatch(facet, watcher, False)                             # the one who looked lets go: not off again
        s.ns.FacetWatch(facet, watcher, True)
        self.assertEqual(self.counts(s), (1, 1))
        s.lua.execute(b"__px:Facet('probe', nil)")                         # not there: nothing
        s.lua.execute(self.AGAIN)                                          # and registered anew: another facet
        self.assertEqual((s.ns.facets[b"probe"][b"n"], self.counts2(s)), (0, (0, 0)))
        self.assertIn("probe: the facet me is extension kit's", self.raises(s, "__px:Facet('me', nil)"))

    def test_what_the_apps_are_told(self):
        s = self.probe(self.start())
        s.lua.globals()[b"__ns"] = s.ns
        s.lua.execute(b"__told = {} __ns.OnChange(function(what, x) "
                      b"if what == 'facet' then __told[#__told + 1] = { x.name, __ns.facets[x.name] == x, x.gone or false } "
                      b"elseif what == 'extension' and x.id == 'probe' then "
                      b"__told[#__told + 1] = { 'ext', x.active, table.concat(x.facetOrder, ' ') } end end)")
        s.lua.execute(self.AGAIN)
        s.ns.Switch(b"probe", False)
        s.ns.Switch(b"probe", True)
        s.lua.execute(b"__px:Facet('probe', nil)")
        s.lua.execute(b"__px:Facet('other', { read = print })")
        self.assertEqual(py(s.g("__told")), [["probe", True, False], ["ext", False, "probe"], ["ext", True, "probe"],
                                             ["probe", False, True], ["other", True, False]])

    def test_through_a_reload(self):
        s = self.probe(self.start())
        self.opens(s, "{ app = 'a', hear = { 'bus:demo.*' }, see = { 'probe' } }")
        s2 = self.start(s.reload())                                        # the run goes on; the facet comes later
        self.probe(s2)
        self.assertEqual(self.counts(s2), (1, 0))
        s2.lua.execute(b"WuxianKit:Emit('demo.x', 1)")
        self.assertEqual(self.wakes(s2, "a")[0]["state"], {"probe": {"n": 1}})


class Me(FacetCase):
    def test_xp_dead_and_the_top_level(self):
        s = self.start()
        s.lua.execute(b"function UnitIsDeadOrGhost() return true end")
        me = self.lua(s, "WuxianKit:Me()")
        self.assertEqual((me["dead"], me["xp"]), (True, 3))
        s.lua.execute(b"function GetMaxLevelForPlayerExpansion() return 8 end")
        self.assertNotIn("xp", self.lua(s, "WuxianKit:Me()"))              # at the top level: none
        s.lua.execute(b"GetMaxLevelForPlayerExpansion = nil __player.xpMax = 0")
        self.assertNotIn("xp", self.lua(s, "WuxianKit:Me()"))

    def test_group_in_an_instance(self):
        s = self.start()
        s.lua.execute(b"function IsInInstance() return true, 'party' end "
                      b"function GetInstanceInfo() return 'Deadmines', 'party', 1 end "
                      b"function IsInRaid() return true end __group = { {}, {}, {}, {}, {}, {} }")
        g = py(s.ns.FacetRead(s.ns.facets[b"group"]))
        self.assertEqual(g, {"kind": "raid", "size": 7, "instance": "Deadmines", "instanceType": "party"})


if __name__ == "__main__":
    unittest.main()
