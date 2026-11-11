-- The addon of ARCHITECTURE.md's example app (section 10): an extension of its own, myguild, and what its app's
-- declaration leans on. The app is in Apps/Officers/App.lua, as the document writes it.
local addonName, ns = ...
local Kit = WuxianKit
local L = Kit:Words { zhCN = { TITLE = "公会工具" }, enUS = { TITLE = "Guild tools" } }

Kit:Extension("myguild", { title = L"TITLE", version = "1.0.0", addon = addonName })

-- whether this player recruited the one who joined (the example's own fact; nobody here)
function ns.IsMine(name) return ns.mine and ns.mine[name] or false end
