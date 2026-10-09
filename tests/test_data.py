"""记录 (Data) under Lua 5.1 in the mock client: records kept, read, listed, deleted, kept through a reload, within
their sizes (64 KB a record, 1 MB in all)."""
import unittest

from kitmock import Session, lupa, py


@unittest.skipIf(lupa is None, "lupa (Lua 5.1 for Python) is not installed")
class Data(unittest.TestCase):
    def start(self, s=None):
        s = s or Session(self)
        s.login()
        s.run(1)
        self.addCleanup(lambda: self.assertEqual(s.errors(), []))
        return s

    def call(self, s, cap, args="{}"):
        s.lua.execute(f"__answer = WuxianKit:Call({cap!r}, {args})".encode())
        return py(s.g("__answer"))

    def fails(self, s, code):
        ok, err = s.lua.eval(f"pcall(function() {code} end)".encode())
        self.assertFalse(ok, code)
        return err.decode()

    def test_records(self):
        s = self.start()
        self.assertEqual(self.call(s, "data.put", "{ key = 'agent/notes', value = { 'copper', n = 3 } }"),
                         {"key": "agent/notes", "bytes": 21})
        self.call(s, "data.put", "{ key = 'agent/last', value = 'Ironforge' }")
        self.call(s, "data.put", "{ key = 'other/x', value = true }")
        self.assertEqual(self.call(s, "data.get", "{ key = 'agent/notes' }"),
                         {"key": "agent/notes", "value": {1: "copper", "n": 3}, "bytes": 21})
        self.assertEqual(self.call(s, "data.get", "{ key = 'nope' }"), {"key": "nope"})
        self.assertEqual([r["key"] for r in self.call(s, "data.list", "{ prefix = 'agent/' }")], ["agent/last", "agent/notes"])
        self.assertTrue(self.call(s, "data.delete", "{ key = 'other/x' }"))
        self.assertFalse(self.call(s, "data.delete", "{ key = 'other/x' }"))
        s2 = self.start(s.reload())                                          # kept through a reload
        self.assertEqual(self.call(s2, "data.get", "{ key = 'agent/last' }")["value"], "Ironforge")
        self.assertIn("key is 1 to 64 bytes", self.fails(s2, "WuxianKit:Call('data.put', { key = '', value = 1 })"))
        self.assertIn("more than 65536", self.fails(s2, "WuxianKit:Call('data.put', { key = 'big', value = string.rep('x', 70000) })"))
        s2.lua.execute(b"for i = 1, 17 do WuxianKit:Call('data.put', { key = 'k' .. i, value = string.rep('x', 60000) }) end")
        self.assertIn("all records would be", self.fails(s2, "WuxianKit:Call('data.put', { key = 'k18', value = string.rep('x', 60000) })"))


    def test_a_record_is_a_copy(self):
        """what is kept is a copy: the caller's table changed later changes nothing kept, nor does a table handed out"""
        s = self.start()
        s.lua.execute(b"__v = { a = 1 } WuxianKit:Call('data.put', { key = 'k', value = __v }) __v.a = 2 "
                      b"__v.b = string.rep('x', 100000)")
        self.assertEqual(self.call(s, "data.get", "{ key = 'k' }")["value"], {"a": 1})
        s.lua.execute(b"WuxianKit:Call('data.get', { key = 'k' }).value.a = 3")
        self.assertEqual(self.call(s, "data.get", "{ key = 'k' }")["value"], {"a": 1})

if __name__ == "__main__":
    unittest.main()
