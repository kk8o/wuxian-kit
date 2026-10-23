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


ME = "5.8.4.165-37.393-73.356-1*g1-2s_5-2t"           # the mock's priest: class, level, race, professions; worn: items 100, 101


def b36(n):
    out = ""
    while True:
        out = DIGITS[n % 36] + out
        n //= 36
        if not n:
            return out


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

    def test_gear_enchants_and_talents(self):
        """an enchanted weapon and the talent tree's nodes with points: the *g and *t parts the site's 战斗模拟器 reads"""
        s = self.start()
        s.lua.execute(b"__worn[16] = '|cffa335ee|Hitem:19019:1900::::::::60:::::::|h[Thunderfury]|h|r'"
                      b" C_ClassTalents.GetActiveConfigID = function() return 9 end"
                      b" C_Traits.GetConfigInfo = function(id) return { ID = id, treeIDs = { 1082 } } end"
                      b" C_Traits.GetTreeNodes = function() return { 104730, 104724, 104800, 104801 } end"
                      b" local r = { [104724] = 2, [104730] = 5, [104800] = 1 }"
                      b" C_Traits.GetNodeInfo = function(cfg, n) return { ID = n, ranksPurchased = r[n] or 0, maxRanks = 5 } end")
        s.g("SlashCmdList")[b"WUXIANKIT"](b"codex")
        c = py(s.lua.eval(b"WuxianKitDB.ext.codex.chars"))["Forever|Wuxian Forever"]
        self.assertEqual(c["gear"], [[1, 100, 0], [5, 101, 0], [16, 19019, 1900]])
        self.assertEqual(c["talents"], [[104724, 2], [104730, 5], [104800, 1]])
        payload = (f"5.8.4.165-37.393-73.356-1*g1-2s_5-2t_16-{b36(19019)}-{b36(1900)}*t2{b36(104724)}_56_1{b36(70)}"
                   "~Wuxian%20Forever@Forever")
        self.assertEqual(self.link(s), f"https://wuxianwow.com/#me={payload}!{check(payload)}")

    def test_kept_across_a_reload(self):
        s = self.start()
        s2 = s.reload()
        s2.login()
        self.assertIn("Forever|Wuxian Forever", py(s2.lua.eval(b"WuxianKitDB.ext.codex.chars")))


if __name__ == "__main__":
    unittest.main()
