"""The small helpers of 0.6 (ARCHITECTURE section 12): Value, Clean, Links, Unit, Pattern, NewId (one counter through
reloads), Me, ext:Char."""
import unittest

from kitmock import Session, lupa, py


@unittest.skipIf(lupa is None, "lupa (Lua 5.1 for Python) is not installed")
class Helpers(unittest.TestCase):
    def start(self, **kw):
        s = Session(self, **kw)
        s.login()
        s.run(1)
        self.addCleanup(lambda: self.assertEqual(s.errors(), []))
        return s

    def test_clean_and_links(self):
        s = self.start()
        text = "|cffff0000红|r 字 |Hitem:2589::::|h[亚麻布]|h\n|Tx:0|t 尾  "
        s.lua.execute(("__t = [==[" + text + "]==]").encode())
        self.assertEqual(s.lua.eval(b"WuxianKit:Clean(__t)"), "红 字 [亚麻布] 尾".encode())
        self.assertIsNone(s.lua.eval(b"WuxianKit:Clean('  |r ')"))
        self.assertIsNone(s.lua.eval(b"WuxianKit:Clean(nil)"))
        self.assertEqual(py(s.lua.eval(b"WuxianKit:Links(__t)")), [{"kind": "item", "id": 2589, "name": "亚麻布"}])
        self.assertFalse(py(s.lua.eval(b"WuxianKit:Links(nil)")))

    def test_value_and_pattern(self):
        s = self.start()
        self.assertEqual(s.lua.eval(b"WuxianKit:Value(3)"), 3)
        self.assertIsNone(s.lua.eval(b"WuxianKit:Value(nil)"))
        s.lua.execute(b"issecretvalue = function(v) return v == 'secret' end")
        self.assertIsNone(s.lua.eval(b"WuxianKit:Value('secret')"))
        self.assertEqual(s.lua.eval(b"WuxianKit:Value('plain')"), b"plain")
        pat = s.lua.eval("WuxianKit:Pattern('%s加入了公会。')".encode())
        self.assertEqual(s.lua.eval("(('小明加入了公会。'):match(WuxianKit:Pattern('%s加入了公会。')))".encode()),
                         "小明".encode())
        self.assertIsNotNone(pat)
        self.assertEqual(py(s.lua.eval(b"{ ('3 of 5 (x)'):match(WuxianKit:Pattern('%d of %d (x)')) }")), ["3", "5"])
        self.assertIsNone(s.lua.eval(b"WuxianKit:Pattern('')"))

    def test_new_id_one_counter_through_reloads(self):
        s = self.start()
        a = s.lua.eval(b"WuxianKit:NewId()")
        b = s.lua.eval(b"WuxianKit:NewId()")
        self.assertEqual(b, a + 1)
        self.assertEqual(s.lua.eval(b"WuxianKitDB.lastId"), b)
        s.lua.execute(b"WuxianKitDB.lastId = 500")
        self.assertEqual(s.lua.eval(b"WuxianKit:NewId()"), 501)

    def test_me_unit_and_char(self):
        s = self.start()
        me = py(s.lua.eval(b"WuxianKit:Me()"))
        self.assertIn("name", me)
        self.assertEqual(me["nickname"], "")
        self.assertIs(me["combat"], False)
        unit = py(s.lua.eval(b"WuxianKit:Unit('player')"))
        self.assertTrue(unit is None or isinstance(unit, dict))
        s.lua.execute(b"__x = WuxianKit:Extension('ch', { title = 'CH' })")
        s.run(1)
        s.lua.execute(b"__x:Char().seen = 1")
        self.assertEqual(s.lua.eval(b"__x:Char().seen"), 1)
        self.assertIsNotNone(s.lua.eval(b"__x.db.chars"))


if __name__ == "__main__":
    unittest.main()
