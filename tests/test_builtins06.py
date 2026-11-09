"""The core's own extension in 0.6 (ARCHITECTURE section 12): the core option nickname (称呼), kit.me
{ name, nickname, aliases }, and kit.options for an extension or an app (exactly one of the two)."""
import unittest

from kitmock import Session, lupa, py


@unittest.skipIf(lupa is None, "lupa (Lua 5.1 for Python) is not installed")
class Builtins06(unittest.TestCase):
    def start(self, **kw):
        s = Session(self, **kw)
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

    def set_option(self, s, ext, name, value):
        s.lua.execute(f"__ok = __ns.SetOption(__ns.extensions[{ext!r}], {name!r}, {value})".encode())
        self.assertTrue(s.g("__ok"))

    def with_ns(self, s):
        s.lua.globals()[b"__ns"] = s.ns
        return s

    def test_the_nickname_option(self):
        s = self.with_ns(self.start())
        got = self.call(s, "kit.options", "{ extension = 'kit' }")["nickname"]
        self.assertEqual({k: got.get(k) for k in ("title", "kind", "value", "default")},
                         {"title": "What to call me", "kind": "text", "value": "", "default": ""})
        self.assertEqual(s.lua.eval(b"__ns.extensions.kit.options.nickname.hint()"),
                         b"How AI apps address you; empty: your character name")
        self.assertEqual(py(s.lua.eval(b"WuxianKit:Me()"))["nickname"], "")
        self.set_option(s, "kit", "nickname", "'  老王 '")
        self.assertEqual(py(s.lua.eval(b"WuxianKit:Me()"))["nickname"], "老王")
        z = self.with_ns(self.start(locale="zhCN"))
        got = self.call(z, "kit.options", "{ extension = 'kit' }")["nickname"]
        self.assertEqual(got["title"], "称呼")
        self.assertEqual(z.lua.eval(b"__ns.extensions.kit.options.nickname.hint()").decode(),
                         "AI 应用怎么叫你；留空就叫角色名")

    def test_kit_me(self):
        s = self.with_ns(self.start())
        me = self.call(s, "kit.me")
        self.assertEqual(me["name"], "Wuxian Forever")
        self.assertEqual(me["nickname"], "")
        self.assertEqual(me["aliases"], ["Wuxian Forever", "Wuxian", "Forever"])
        self.set_option(s, "chat", "aliases", "{ '大佬' }")
        self.set_option(s, "kit", "nickname", "'小王'")
        me = self.call(s, "kit.me")
        self.assertEqual((me["nickname"], me["aliases"][-1]), ("小王", "大佬"))
        s.ns[b"Disable"](s.ns[b"extensions"][b"chat"])
        self.assertFalse(self.call(s, "kit.me")["aliases"])                 # the chat extension off: none

    def test_kit_options_for_an_extension_or_an_app(self):
        s = self.with_ns(self.start())
        self.assertIn("aliases", self.call(s, "kit.options", "{ extension = 'chat' }"))
        self.assertIn("no extension nope", self.fails(s, "WuxianKit:Call('kit.options', { extension = 'nope' })"))
        self.assertIn("no app guild", self.fails(s, "WuxianKit:Call('kit.options', { app = 'guild' })"))
        s.lua.execute(b"__ns.AppOptionList = function(id) if id == 'guild' then "
                      b"return { topics = { title = 'Topics', kind = 'list', value = { 'raids' } } } end end")
        self.assertEqual(self.call(s, "kit.options", "{ app = 'guild' }"),
                         {"topics": {"title": "Topics", "kind": "list", "value": ["raids"]}})
        self.assertIn("no app other", self.fails(s, "WuxianKit:Call('kit.options', { app = 'other' })"))
        self.assertIn("not both", self.fails(s, "WuxianKit:Call('kit.options', { extension = 'chat', app = 'guild' })"))
        self.assertIn("give extension", self.fails(s, "WuxianKit:Call('kit.options', {})"))
        args = py(s.lua.eval(b"WuxianKit:Capability('kit.options').args"))
        self.assertEqual(args, {"extension": "string?", "app": "string?"})


if __name__ == "__main__":
    unittest.main()
