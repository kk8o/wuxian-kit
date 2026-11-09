"""Game links in texts (0.6) under Lua 5.1 in the mock client: WuxianKit:Link for each kind the client gives a link for
(item loaded or not, spell, recipe, achievement, currency, quest in the log or not), WuxianKit:Links reading them back,
Linkify / Unlink / Preload; chat.send linking at send time with its byte limit counted after the links; the proposal
window and the guide's note showing the client's links, the agent's own | codes escaped, a tooltip on hover."""
import unittest

from kitmock import Session, click, lupa, py, texts

LINEN = "|cnIQ1:|Hitem:2589::::::::1:::::::|h[亚麻布]|h|r"
RECIPE = "|cffffd000|Henchant:2538|h[烹饪: 烧烤狼肉]|h|r"
ACHIEVEMENT = "|cffffff00|Hachievement:61502:Player-1-00000001:0:0:0:-1:0:0:0:0|h[新手德鲁伊]|h|r"
CURRENCY = "|cffffffff|Hcurrency:3402:0|h[商人青睐]|h|r"
QUEST = "|cffffff00|Hquest:962:0|h[毒蛇花]|h|r"

# the client's link calls as measured on this client, for the ids above; quest 962 only while it is in the log
STUBS = f"""
__items[2589] = {{ name = "亚麻布" }}
local get = C_Item.GetItemInfo
C_Item.GetItemInfo = function(id)
	local i = __items[id]
	if id == 2589 and i.known then return i.name, "{LINEN}" end
	return get(id)
end
__requested = {{}}
local request = C_Item.RequestLoadItemDataByID
C_Item.RequestLoadItemDataByID = function(id) __requested[#__requested + 1] = id request(id) end
local spell = C_Spell.GetSpellLink
C_Spell.GetSpellLink = function(id) if id == 99 then error("no such spell") end return spell(id) end
C_TradeSkillUI = {{ GetRecipeLink = function(id) if id == 2538 then return "{RECIPE}" end end }}
function GetAchievementLink(id) if id == 61502 then return "{ACHIEVEMENT}" end end
C_CurrencyInfo.GetCurrencyLink = function(id) if id == 3402 then return "{CURRENCY}" end end
__inLog = {{ [962] = true }}
function GetQuestLink(id) if __inLog[id] then return "{QUEST}" end end
"""


@unittest.skipIf(lupa is None, "lupa (Lua 5.1 for Python) is not installed")
class Links(unittest.TestCase):
    def start(self):
        s = Session(self)
        s.lua.execute(STUBS.encode())
        s.lua.execute(b"TestButton = CreateFrame('Button', 'TestButton', UIParent)")
        s.login()
        s.run(1)
        self.addCleanup(lambda: self.assertEqual(s.errors(), []))
        return s

    def ev(self, s, code):
        return py(s.lua.eval(code.encode()))

    def call(self, s, cap, args="{}", opts="nil"):
        s.lua.execute(f"__answer = WuxianKit:Call({cap!r}, {args}, {opts})".encode())
        return py(s.g("__answer"))

    def link(self, s, kind, id_):
        return self.ev(s, f"WuxianKit:Link({kind!r}, {id_})")

    def test_each_kind(self):
        s = self.start()
        self.assertIsNone(self.link(s, "item", 2589))                       # not loaded: asked for, nil now
        self.assertEqual(py(s.g("__requested")), [2589])
        self.assertEqual(self.link(s, "item", 2589), LINEN)                  # loaded a moment later
        self.assertEqual(self.link(s, "spell", 458), "|cff71d5ff|Hspell:458:0|h[Spell 458]|h|r")
        self.assertIsNone(self.link(s, "spell", 99))                         # the client's call fails: nil
        self.assertEqual(self.link(s, "recipe", 2538), RECIPE)
        self.assertEqual(self.link(s, "enchant", 2538), RECIPE)              # a recipe's link type, as a kind
        self.assertEqual(self.link(s, "achievement", 61502), ACHIEVEMENT)
        self.assertEqual(self.link(s, "currency", 3402), CURRENCY)
        self.assertIsNone(self.link(s, "currency", 1))
        self.assertEqual(self.link(s, "quest", 962), QUEST)                  # in the player's log
        self.assertIsNone(self.link(s, "quest", 963))                        # not in it
        for kind, id_ in (("npc", 1), ("Item", "'x'"), ("item", -1), ("item", 1.5), ("item", "0/0"), ("nil", 1)):
            self.assertIsNone(self.ev(s, f"WuxianKit:Link({'nil' if kind == 'nil' else repr(kind)}, {id_})"), kind)
        # the mirror: what Links reads of each link is the kind and id it was made from
        back = self.ev(s, "WuxianKit:Links(WuxianKit:Linkify('{item:2589:x}{spell:458:x}{recipe:2538:x}"
                          "{achievement:61502:x}{currency:3402:x}{quest:962:x}'))")
        self.assertEqual([(x["kind"], x["id"]) for x in back],
                         [("item", 2589), ("spell", 458), ("recipe", 2538), ("achievement", 61502), ("currency", 3402),
                          ("quest", 962)])
        self.assertEqual(back[0]["name"], "亚麻布")

    def test_linkify_unlink_preload(self):
        s = self.start()
        s.lua.execute(b"__items[2590] = { name = 'Wool' }")
        self.assertEqual(self.ev(s, "WuxianKit:Preload('{item:2589:亚麻布} {item:2590} {spell:458:x} {item:2589:again}')"),
                         2)                                                  # asked for, still loading
        self.assertEqual(py(s.g("__requested")), [2589, 2590])              # (the mock loads it at once)
        self.assertEqual(self.ev(s, "WuxianKit:Preload('{item:2589:亚麻布}')"), 0)
        s.lua.execute("__t, __n = WuxianKit:Linkify('带 {item:2589:亚麻布} 和 {quest:963:迷路} {npc:5:路人} {quest:962} "
                      "{spell:7}')".encode())
        self.assertEqual(py(s.g("__t")), f"带 {LINEN} 和 [迷路] [路人] {QUEST} |cff71d5ff|Hspell:7:0|h[Spell 7]|h|r")
        self.assertEqual(s.g("__n"), 3)
        self.assertEqual(self.ev(s, "WuxianKit:Unlink('{item:2589:亚麻布}、{x:3:y}、{item:12}、{item:abc:z}')"),
                         "[亚麻布]、[y]、[12]、{item:abc:z}")
        self.assertEqual(self.ev(s, "select(2, WuxianKit:Linkify('no tokens'))"), 0)
        self.assertEqual(self.ev(s, "WuxianKit:Linkify(nil) == nil and WuxianKit:Unlink(5) == 5 and WuxianKit:Preload({})"), 0)

    def test_chat_send_links_when_sent(self):
        s = self.start()
        s.lua.execute(b"__inLog[962] = nil")
        p = self.call(s, "chat.send", "{ channel = 'guild', text = '{item:2589:亚麻布} 交给 {quest:962:毒蛇花}' }")
        self.assertEqual(py(s.g("__requested")), [2589])                    # the proposal asked for the item
        self.assertEqual(p["steps"][0]["preview"], ["Guild: [亚麻布] 交给 [毒蛇花]"])   # the agent's copy: plain
        window = s.g("WuxianKitProposal")
        self.assertIn(f"Guild: {LINEN} 交给 [毒蛇花]", texts(window))       # the window: the client's link
        s.lua.execute(b"__inLog[962] = true")                               # the quest is in the log by the click
        click(window[b"run"])
        self.assertEqual(py(s.g("__sent"))[-1]["text"], f"{LINEN} 交给 {QUEST}")
        # 255 bytes: checked as the player reads it, and again with the links in when it is sent
        long = "x" * 230
        self.assertIn("more than 255", self.call_fails(s, f"{{ channel = 'guild', text = '{'x' * 250}{{item:2589:亚麻布}}' }}"))
        p = self.call(s, "chat.send", f"{{ channel = 'guild', text = '{long}{{item:2589:亚麻布}}' }}")
        s.run(1.1)
        click(s.g("WuxianKitProposal")[b"run"])
        done = self.ev(s, f"WuxianKit:Proposal({p['id']})")
        self.assertEqual(done["state"], "failed")
        self.assertIn("bytes with its links, more than 255", done["error"])
        self.assertEqual(len(py(s.g("__sent"))), 1)

    def call_fails(self, s, args):
        ok, err = s.lua.eval(f"pcall(WuxianKit.Call, WuxianKit, 'chat.send', {args})".encode())
        self.assertFalse(ok)
        return err.decode()

    def test_the_window_escapes_then_links(self):
        s = self.start()
        s.lua.execute(b"""
            local x = WuxianKit:Extension('linktest', { title = 'Link test' })
            x:Say('post', { title = 'Post', args = { text = 'string' }, links = true,
                preview = function(_, a) return { WuxianKit:Escape(a.text), 'plain {item:2589:x}' } end,
                apply = function() end })
            x:Say('bare', { title = 'Bare', args = { text = 'string' },
                preview = function(_, a) return WuxianKit:Escape(a.text) end, apply = function() end })""")
        s.run(0.1)
        text = "|cffff0000red|r |Hitem:1|h[fake]|h {item:2589:亚麻布}"
        p = self.call(s, "linktest.post", "{ text = [[" + text + "]] }")
        self.assertEqual(p["steps"][0]["preview"][0], "||cffff0000red||r ||Hitem:1||h[fake]||h [亚麻布]")
        window = s.g("WuxianKitProposal")
        s.run(1.1)                                                            # drawn again every second
        lines = texts(window)
        self.assertIn(f"||cffff0000red||r ||Hitem:1||h[fake]||h {LINEN}", lines)   # only the client's link works
        self.assertIn(f"plain {LINEN}", lines)                                # the client's name, not the token's
        self.assertTrue(window[b"hyperlinks"])
        enter, leave = window[b"scripts"][b"OnHyperlinkEnter"], window[b"scripts"][b"OnHyperlinkLeave"]
        enter(window, b"item:2589::::::::1:::::::", "[亚麻布]".encode())
        tip = s.g("GameTooltip")
        self.assertEqual((tip[b"link"], tip[b"shown"], s.lua.eval(b"GameTooltip.owner == WuxianKitProposal")),
                         (b"item:2589::::::::1:::::::", True, True))
        leave(window)
        self.assertFalse(tip[b"shown"])
        enter(window, b"garbage")                                             # a link the tooltip refuses: hidden
        self.assertFalse(tip[b"shown"])
        click(window[b"decline"])
        s.run(1.1)
        self.call(s, "linktest.bare", "{ text = '{item:2589:亚麻布}' }")
        self.assertIn("{item:2589:亚麻布}", texts(s.g("WuxianKitProposal")))   # no links = true: as it is

    def test_guide_texts(self):
        s = self.start()
        s.lua.execute("WuxianKit:Call('guide.note', { title = '{spell:458:棕马}', "
                      "text = '|cffff0000拿|r {item:2589:亚麻布}\\n交给 {quest:962:毒蛇花}' })".encode())
        note = s.g("WuxianKitGuideNote")
        spell = "|cff71d5ff|Hspell:458:0|h[Spell 458]|h|r"
        self.assertEqual(texts(note)[:2], [spell, f"||cffff0000拿||r [亚麻布]\n交给 {QUEST}"])   # the item still loading
        self.assertTrue(note[b"hyperlinks"] and note[b"motion"])
        s.fire("GET_ITEM_INFO_RECEIVED", 2589, True)                          # its data came: drawn again
        self.assertEqual(texts(note)[1], f"||cffff0000拿||r {LINEN}\n交给 {QUEST}")
        self.assertTrue(callable(note[b"scripts"][b"OnHyperlinkEnter"]))
        s.lua.execute(b"WuxianKit:Call('guide.note', { text = 'nothing linked' })")
        self.assertFalse(note[b"motion"])                                     # no link: the mouse goes through
        s.lua.execute("WuxianKit:Call('guide.tour', { title = '{currency:3402:商人青睐}', steps = { "
                      "{ text = '去拿 {recipe:2538:烧烤狼肉}', frame = 'TestButton' }, { text = '完成' } } })".encode())
        self.assertEqual(texts(note)[:2], [f"{CURRENCY} · 1/2", f"去拿 {RECIPE}"])
        self.assertIn("[商人青睐]", self.ev(s, "WuxianKit:Extension('guide').status()") or "")
        s.lua.execute("WuxianKit:Call('guide.highlight', { frame = 'TestButton', text = '{achievement:61502:新手}' })".encode())
        boxes = [f[b"box"] for f in (s.g("UIParent")[b"__kids"] or {}).values() if f[b"edges"] and f[b"shown"]]
        self.assertIn(ACHIEVEMENT, [b[b"__regions"] and texts(b) and texts(b)[0] for b in boxes])
        self.assertTrue(any(b[b"motion"] for b in boxes))


if __name__ == "__main__":
    unittest.main()
