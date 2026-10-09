-- 调校 · 整理背包 (Tune: bags). tune.bags.sort: the client's own sort, as the bag window's button does it; it cannot be
-- undone (the preview says so).
local Kit = WuxianKit

local L = Kit:Words {
	zhCN = { SORT = "整理背包", SCOPE = "整理背包" },
	enUS = { SORT = "Sort bags", SCOPE = "Bag sorting" },
}

local tune = Kit:Extension("tune")
tune:Scope("bags", L"SCOPE")

tune:Do("bags.sort", { title = L"SORT", scope = "bags",
	doc = "sort the bags as the bag window's button does; it cannot be undone",
	apply = function()
		C_Container.SortBags()
		return true
	end })
