-- 记录 (Data): records kept on this computer (WuxianKitDB), for the agent and for other addons: data.put, data.get,
-- data.list, data.delete (Keep: at once, nothing in the game changes). A record is a key (1-64 bytes; "addon/thing" keeps
-- addons apart) and a value of strings, numbers, booleans and tables; a big one comes back to the agent in parts
-- (WoWBridge pieces long answers). Sizes as WuxianKit.Comm writes values: a record at most 64 KB, all of them 1 MB.
local Kit = WuxianKit

local L = Kit:Words {
	zhCN = { TITLE = "数据", PUT = "保存数据", GET = "读取数据", LIST = "数据列表", DELETE = "删除数据",
		STATUS = "%d 条记录，共 %s" },
	enUS = { TITLE = "Data", PUT = "Save data", GET = "Read data", LIST = "Data list", DELETE = "Delete data",
		STATUS = "%d records, %s" },
}

local data = Kit:Extension("data", { title = L"TITLE", version = Kit.VERSION, docs = "Extensions/Data", defaults = { records = {}, sizes = {} } })

local MAX_KEY, MAX_ONE, MAX_ALL = 64, 64 * 1024, 1024 * 1024

local function Size(v) return #Kit.Comm.Serialize(v) end

local function Total(self)
	local n, bytes = 0, 0
	for _, size in pairs(self.db.sizes) do
		n, bytes = n + 1, bytes + size
	end
	return n, bytes
end

local function Bytes(n)
	if n < 1024 then return n .. " B" end
	return ("%.1f KB"):format(n / 1024)
end

local function Key(key)
	if key == "" or #key > MAX_KEY then error(("key is 1 to %d bytes"):format(MAX_KEY), 0) end
	return key
end

-- a record as it is kept and handed out: a copy (the caller's table, changed later, changes nothing kept, and what is
-- kept stays as large as Size said)
local function Copy(v)
	if type(v) ~= "table" then return v end
	local t = {}
	for k, x in pairs(v) do t[Copy(k)] = Copy(x) end
	return t
end

data:Keep("put", { title = L"PUT", args = { key = "string", value = "any" },
	doc = "keep a record: key (1-64 bytes; 'addon/thing' keeps addons apart) and value (strings, numbers, booleans, "
		.. "tables); a record of that key is replaced; at most 64 KB a record and 1 MB in all; answers {key, bytes}",
	run = function(self, a)
		local key = Key(a.key)
		local ok, size = pcall(Size, a.value)
		if not ok then error(("value: %s"):format(tostring(size)), 0) end
		if size > MAX_ONE then error(("value is %d bytes, more than %d"):format(size, MAX_ONE), 0) end
		local _, all = Total(self)
		local after = all - (self.db.sizes[key] or 0) + size
		if after > MAX_ALL then error(("all records would be %d bytes, more than %d"):format(after, MAX_ALL), 0) end
		self.db.records[key], self.db.sizes[key] = Copy(a.value), size
		return { key = key, bytes = size }
	end })

data:Keep("get", { title = L"GET", args = { key = "string" },
	doc = "a record: {key, value, bytes}, or {key} when there is none of that key",
	run = function(self, a)
		return { key = a.key, value = Copy(self.db.records[a.key]), bytes = self.db.sizes[a.key] }
	end })

data:Keep("list", { title = L"LIST", args = { prefix = "string?" },
	doc = "the records whose key starts with prefix (all without): {key, bytes}, by key",
	run = function(self, a)
		local out = {}
		for key, size in pairs(self.db.sizes) do
			if not a.prefix or key:sub(1, #a.prefix) == a.prefix then out[#out + 1] = { key = key, bytes = size } end
		end
		table.sort(out, function(x, y) return x.key < y.key end)
		return out
	end })

data:Keep("delete", { title = L"DELETE", args = { key = "string" },
	doc = "delete a record; answers whether there was one",
	run = function(self, a)
		local had = self.db.sizes[a.key] ~= nil
		self.db.records[a.key], self.db.sizes[a.key] = nil, nil
		return had
	end })

data:Status(function(self)
	local n, bytes = Total(self)
	return L.STATUS:format(n, Bytes(bytes))
end)
