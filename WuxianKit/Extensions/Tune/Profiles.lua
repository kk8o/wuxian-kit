-- 调校 · 配置档 (Tune: profiles). A profile is a named list of steps, each a Do capability of any extension and its args
-- (a setting, a key, a layout, a macro ...), kept on this computer. tune.profile.save / .capture / .import / .delete
-- (Keep) keep them, tune.profile.list / .get / .export (See) read them, and tune.profile.apply (Point) puts a profile's
-- steps in front of the player as one proposal: one click runs them all, one undo takes them all back. A profile's share
-- string is "WK1:" and the base64 of its CBOR, compressed (the client's C_EncodingUtil). A profile someone shared
-- (imported) is applied as such (source "import:<name>"): pre-approval never counts for it, the player always clicks.
local Kit = WuxianKit

local L = Kit:Words {
	zhCN = { SAVE = "保存配置档", CAPTURE = "从当前状态创建配置档", IMPORT = "导入配置档", DELETE = "删除配置档",
		LIST = "配置档列表", GET = "配置档内容", EXPORT = "导出配置档", APPLY = "应用配置档", APPLY_TITLE = "应用配置档「%s」" },
	enUS = { SAVE = "Save profile", CAPTURE = "Create profile from current state", IMPORT = "Import profile",
		DELETE = "Delete profile", LIST = "Profile list", GET = "Profile details", EXPORT = "Export profile",
		APPLY = "Apply profile", APPLY_TITLE = "Apply profile \"%s\"" },
}

local tune = Kit:Extension("tune")

local MAX_STEPS, PREFIX = 40, "WK1:"

-- steps as a profile keeps them ({ cap, args }), each a live Do capability with the args it takes; or an error
local function Checked(steps)
	if type(steps) ~= "table" or #steps == 0 then error("steps: a list of {cap, args}", 0) end
	if #steps > MAX_STEPS then error(("steps: at most %d"):format(MAX_STEPS), 0) end
	local out = {}
	for i, s in ipairs(steps) do
		if type(s) ~= "table" then error(("step %d is {cap, args}"):format(i), 0) end
		local id, args = s.cap or s[1], s.args or s[2] or {}
		local cap = type(id) == "string" and Kit:Capability(id)
		if not cap then error(("step %d: no capability %s (or its extension is off)"):format(i, tostring(id)), 0) end
		if cap.kind ~= "do" then error(("step %d: %s is a %s capability; a profile holds Do ones"):format(i, id, cap.kind), 0) end
		if type(args) ~= "table" then error(("step %d: args is a table"):format(i), 0) end
		for name, spec in pairs(cap.args) do
			if args[name] == nil and spec:sub(-1) ~= "?" then error(("step %d: %s is missing (%s)"):format(i, name, spec), 0) end
		end
		for name in pairs(args) do
			if not cap.args[name] then error(("step %d: %s takes no argument %s"):format(i, id, tostring(name)), 0) end
		end
		out[i] = { cap = id, args = args }
	end
	return out
end

local function Profile(self, name)
	local p = self.db.profiles[name]
	if not p then error(("no profile %s (tune.profile.list lists them)"):format(tostring(name)), 0) end
	return p
end

-- keeps a profile; answers {name, steps, imported, warnings}: the steps that would be refused now (a name this client
-- lacks, a value out of range ...), kept all the same (a profile may suit another time, or another computer)
local function Keep(self, name, steps, imported)
	if type(name) ~= "string" or name == "" then error("name: the profile's name", 0) end
	local kept = Checked(steps)
	self.db.profiles[name] = { steps = kept, saved = time(), imported = imported or nil }
	local warnings = {}
	for i, s in ipairs(kept) do
		local why = Kit:Check(s.cap, s.args)
		if why then warnings[#warnings + 1] = ("step %d (%s): %s"):format(i, s.cap, why) end
	end
	return { name = name, steps = #kept, imported = imported or nil, warnings = #warnings > 0 and warnings or nil }
end

-- the value a .get capability reads now
local function Now(id, args)
	local ok, got = pcall(Kit.Call, Kit, id, args)
	if not ok then error(tostring(got), 0) end
	return type(got) == "table" and got.value or nil
end

tune:Keep("profile.save", { title = L"SAVE", args = { name = "string", steps = "table" },
	doc = "keeps a profile: a name and steps [{cap, args}], at most 40, each cap the id of a Change capability with dots "
		.. "(\"tune.cvar.set\", \"tune.binding.set\", \"tune.layout.set\" ...; not the tool name); a profile of that name is "
		.. "replaced. Answers {name, steps, warnings}: warnings lists the steps that would be refused now (a misspelled "
		.. "setting ...); the profile is kept all the same",
	run = function(self, a) return Keep(self, a.name, a.steps) end })

tune:Keep("profile.capture", { title = L"CAPTURE",
	args = { name = "string", cvars = "table?", options = "table?", keys = "table?", macros = "table?", layout = "boolean?",
		talent = "boolean?" },
	doc = "keep things as they are now as a profile: the settings named in cvars, the Settings panel's options named in "
		.. "options (tune.setting.find's names for tune.option.set), the keys in keys, the macros in macros, and with "
		.. "layout / talent true the layout and the talent loadout in use; applying it later puts them back",
	run = function(self, a)
		local steps = {}
		for _, name in ipairs(a.cvars or {}) do
			steps[#steps + 1] = { cap = "tune.cvar.set", args = { name = name, value = Now("tune.cvar.get", { name = name }) } }
		end
		for _, name in ipairs(a.options or {}) do
			steps[#steps + 1] = { cap = "tune.option.set", args = { name = name, value = Now("tune.option.get", { name = name }) } }
		end
		for _, key in ipairs(a.keys or {}) do
			steps[#steps + 1] = { cap = "tune.binding.set", args = { key = key, value = Now("tune.binding.get", { key = key }) } }
		end
		for _, name in ipairs(a.macros or {}) do
			steps[#steps + 1] = { cap = "tune.macro.set", args = { name = name, value = Now("tune.macro.get", { name = name }) } }
		end
		if a.layout then steps[#steps + 1] = { cap = "tune.layout.set", args = { value = Now("tune.layout.get", {}) } } end
		if a.talent then
			local loadout = Now("tune.talent.get", {})
			if loadout then steps[#steps + 1] = { cap = "tune.talent.set", args = { value = loadout } } end
		end
		return Keep(self, a.name, steps)
	end })

tune:Keep("profile.delete", { title = L"DELETE", args = { name = "string" },
	doc = "delete a profile",
	run = function(self, a)
		Profile(self, a.name)
		self.db.profiles[a.name] = nil
		return true
	end })

tune:See("profile.list", { title = L"LIST",
	doc = "the profiles: name, steps (how many), saved (a time()), imported (one someone shared)",
	run = function(self)
		local out = {}
		for name, p in pairs(self.db.profiles) do
			out[#out + 1] = { name = name, steps = #p.steps, saved = p.saved, imported = p.imported }
		end
		table.sort(out, function(x, y) return x.name < y.name end)
		return out
	end })

tune:See("profile.get", { title = L"GET", args = { name = "string" },
	doc = "a profile: name, steps [{cap, args}], saved",
	run = function(self, a)
		local p = Profile(self, a.name)
		return { name = a.name, steps = p.steps, saved = p.saved }
	end })

tune:Point("profile.apply", { title = L"APPLY", args = { name = "string" }, proposes = true,
	doc = "makes one proposal of a profile's steps (one click runs them all, one undo takes them all back). An imported "
		.. "profile always waits for the player's click (pre-approval does not count for it)",
	run = function(self, a, opts)
		local p, steps = Profile(self, a.name), {}
		for i, s in ipairs(p.steps) do steps[i] = { s.cap, s.args } end
		return Kit:Propose(steps, { source = p.imported and ("import:" .. a.name) or opts.source,
			title = opts.title or L.APPLY_TITLE:format(a.name), ttl = opts.ttl, after = opts.after })
	end })

tune:See("profile.export", { title = L"EXPORT", args = { name = "string" },
	doc = "a profile as a share string (\"WK1:...\") that tune.profile.import takes, here or on another computer",
	run = function(self, a)
		local p = Profile(self, a.name)
		local data = C_EncodingUtil.SerializeCBOR({ v = 1, name = a.name, steps = p.steps })
		return { name = a.name, text = PREFIX .. C_EncodingUtil.EncodeBase64(C_EncodingUtil.CompressString(data)) }
	end })

tune:Keep("profile.import", { title = L"IMPORT", args = { text = "string", name = "string?", replace = "boolean?" },
	doc = "keep a profile from its share string (tune.profile.export), under its own name or `name`; a profile of that "
		.. "name is replaced only with replace = true; its steps must be capabilities this client has",
	run = function(self, a)
		local body = a.text:match("^" .. PREFIX .. "(.+)$")
		if not body then error(("text is not a profile's share string (it starts with %s)"):format(PREFIX), 0) end
		local ok, v = pcall(function()
			return C_EncodingUtil.DeserializeCBOR(C_EncodingUtil.DecompressString(C_EncodingUtil.DecodeBase64(body)))
		end)
		if not ok or type(v) ~= "table" or type(v.steps) ~= "table" then error("the share string is damaged", 0) end
		local name = a.name or v.name
		if self.db.profiles[name] and not a.replace then
			error(("there is a profile %s already (replace = true replaces it)"):format(tostring(name)), 0)
		end
		return Keep(self, name, v.steps, true)
	end })
