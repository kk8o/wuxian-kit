"""图鉴 (Codex) under Lua 5.1 in the mock client: every character that logs in is kept, and /wk codex shows the link for
wuxianwow.com's 我的角色 (#me=<code>!<check>), with or without the names; the site's app/src/mychar.ts reads the same code."""
import unittest

from kitmock import Session, lupa, py

DIGITS = "0123456789abcdefghijklmnopqrstuvwxyz"


def check(payload):
    h = 0
    for b in payload.encode("utf-8"):
        h = (h * 31 + b) % 1296
    return DIGITS[h // 36] + DIGITS[h % 36]


ME = "5.8.4.165-37.393-73.356-1"                      # the mock's priest: class, level, race, professions


@unittest.skipIf(lupa is None, "lupa (Lua 5.1 for Python) is not installed")
class Codex(unittest.TestCase):
    def start(self, **kw):
        s = Session(self, **kw)
        s.login()
        s.run(1)
        self.addCleanup(lambda: self.assertEqual(s.errors(), []))
        return s

    def link(self, s):
        return s.lua.eval(b"WuxianKitCodexWindow.edit:GetText()").decode("utf-8")

    def test_the_character_is_kept_and_the_link_shown(self):
        s = self.start()
        kept = py(s.lua.eval(b"WuxianKitDB.ext.codex.chars"))
        self.assertEqual(list(kept), ["Forever|Wuxian Forever"])
        c = kept["Forever|Wuxian Forever"]
        self.assertEqual((c["name"], c["realm"], c["cls"], c["race"], c["lv"], c["profs"]),
                         ("Wuxian Forever", "Forever", 5, 4, 8, [[165, 37], [393, 73], [356, 1]]))
        s.g("SlashCmdList")[b"WUXIANKIT"](b"codex")
        self.assertTrue(s.lua.eval(b"WuxianKitCodexWindow:IsShown()"))
        payload = ME + "~Wuxian%20Forever@Forever"
        self.assertEqual(self.link(s), f"https://wuxianwow.com/#me={payload}!{check(payload)}")
        self.assertTrue(s.lua.eval(b"WuxianKitCodexWindow.edit:HasFocus()"))     # ready for Ctrl+C
        s.lua.execute(b"local c = WuxianKitCodexWindow.name; c:SetChecked(false); c:GetScript('OnClick')(c)")
        self.assertEqual(self.link(s), f"https://wuxianwow.com/#me={ME}!{check(ME)}")
        s.lua.execute(b"local e = WuxianKitCodexWindow.edit; e:SetText('typed'); e:GetScript('OnTextChanged')(e, true)")
        self.assertEqual(self.link(s), f"https://wuxianwow.com/#me={ME}!{check(ME)}")          # read only

    def test_several_characters_and_ticking_them_off(self):
        s = self.start()
        s.lua.execute(b"WuxianKitDB.ext.codex.chars['Forever|Alt'] = { name = 'Alt', realm = 'Forever', cls = 1, race = 3,"
                      b" lv = 60, profs = { { 164, 300 } }, seen = 1 }")
        s.g("SlashCmdList")[b"WUXIANKIT"](b"codex")
        both = ME + "~Wuxian%20Forever@Forever,1.60.3.164-300~Alt@Forever"
        self.assertEqual(self.link(s), f"https://wuxianwow.com/#me={both}!{check(both)}")      # the latest first
        s.lua.execute(b"local c = WuxianKitCodexWindow.rows[1]; c:SetChecked(false); c:GetScript('OnClick')(c)")
        alt = "1.60.3.164-300~Alt@Forever"
        self.assertEqual(self.link(s), f"https://wuxianwow.com/#me={alt}!{check(alt)}")
        s.lua.execute(b"local x = WuxianKitCodexWindow.forgets[2]; x:GetScript('OnClick')(x)")   # 移除 the alt
        self.assertEqual(list(py(s.lua.eval(b"WuxianKitDB.ext.codex.chars"))), ["Forever|Wuxian Forever"])

    def test_kept_across_a_reload(self):
        s = self.start()
        s2 = s.reload()
        s2.login()
        self.assertIn("Forever|Wuxian Forever", py(s2.lua.eval(b"WuxianKitDB.ext.codex.chars")))


if __name__ == "__main__":
    unittest.main()
