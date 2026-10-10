-- 调校 · 按键 (Tune: key bindings). tune.binding.get / tune.binding.set: a Setting, what a key does (no command unbinds
-- the key), saved to the binding set in use (the account's or the character's); tune.binding.find: the binding commands
-- and their keys. A key as the client writes it (CTRL-SHIFT-F, 1, NUMPAD5, BUTTON4, MOUSEWHEELUP), its modifiers in any
-- order and case; a command is a binding's name (ACTIONBUTTON1, TOGGLEWORLDMAP: tune.binding.find lists them) or SPELL
-- <name>, ITEM <name>, MACRO <name>, CLICK <frame>:<button>. Like every Do it waits for the end of combat.
local Kit = WuxianKit

local L = Kit:Words {
	zhCN = { BINDING = "按键绑定", FIND = "查找按键绑定", SCOPE = "按键绑定", NAMED = "%s（%s）" },
	enUS = { BINDING = "Key bindings", FIND = "Find key bindings", SCOPE = "Key bindings", NAMED = "%s (%s)" },
}

local tune = Kit:Extension("tune")
tune:Scope("bindings", L"SCOPE")

local MODIFIERS = { ALT = 1, CTRL = 2, SHIFT = 3, META = 4 }     -- in the order the client writes them
local PREFIXES = { SPELL = true, ITEM = true, MACRO = true, CLICK = true }

-- "shift-ctrl-f" -> "CTRL-SHIFT-F", or nil and why
local function KeyName(text)
	local parts = {}
	for p in text:upper():gmatch("[^%-]+") do parts[#parts + 1] = p end
	if text:sub(-1) == "-" then parts[#parts + 1] = "-" end    -- the minus key itself
	local key = table.remove(parts)
	if not key then return nil, "no key" end
	for _, m in ipairs(parts) do
		if not MODIFIERS[m] then return nil, ("%s is not a modifier (ALT, CTRL, SHIFT, META)"):format(m) end
	end
	table.sort(parts, function(a, b) return MODIFIERS[a] < MODIFIERS[b] end)
	parts[#parts + 1] = key
	return table.concat(parts, "-")
end

-- the client's binding commands, read once: command -> { category, title }, and the commands in the client's order
local commands, order
local function Commands()
	if commands then return commands, order end
	commands, order = {}, {}
	for i = 1, GetNumBindings() do
		local command, category = GetBinding(i)
		if type(command) == "string" and not command:match("^HEADER_") then
			commands[command] = { category = category and (_G[category] or category) or nil, title = _G["BINDING_NAME_" .. command] }
			order[#order + 1] = command
		end
	end
	return commands, order
end

-- a command as the client keeps it: a binding's name upper case, SPELL / ITEM / MACRO / CLICK and their names as given
local function Command(v)
	if v == nil or v == "" then return nil end
	local prefix, rest = v:match("^(%a+)%s+(.+)$")
	if prefix and PREFIXES[prefix:upper()] then return prefix:upper() .. " " .. rest end
	return v:upper()
end

local function Action(k)
	local c = GetBindingAction(KeyName(k.key))
	return c ~= "" and c or nil
end

tune:Setting("binding", { title = L"BINDING", scope = "bindings",
	doc = "what a key does: key as the client writes it (CTRL-SHIFT-F, 1, NUMPAD5, BUTTON4, MOUSEWHEELUP; modifiers in any "
		.. "order)",
	change = "value: a command: a binding's name (ACTIONBUTTON1, TOGGLEWORLDMAP; tune.binding.find lists them), SPELL "
		.. "<name>, ITEM <name>, MACRO <name> or CLICK <frame>:<button>; no value unbinds the key",
	key = { key = "string" }, value = "string?",
	check = function(_, k)
		local _, why = KeyName(k.key)
		return why
	end,
	validate = function(_, _, v)
		if v == nil then return nil end
		if v:find("[|\r\n]") then return "a command has no | and no line break" end
		local prefix, rest = v:match("^(%u+) (.+)$")
		if prefix and PREFIXES[prefix] then
			if prefix == "MACRO" and GetMacroIndexByName(rest) == 0 then return ("no macro %s"):format(rest) end
			return nil
		end
		if not Commands()[v] then return ("no binding command %s (tune.binding.find lists them)"):format(v) end
	end,
	normalize = function(_, v) return Command(v) end,
	get = function(_, k) return Action(k) end,
	set = function(_, k, v)
		local key = KeyName(k.key)
		if not SetBinding(key, v) then error(("the game would not bind %s"):format(key), 0) end
		SaveBindings(GetCurrentBindingSet())
	end,
	label = function(_, k) return Kit:Escape(KeyName(k.key) or k.key) end,
	format = function(_, v)
		local c = Commands()[v]
		return c and c.title and L.NAMED:format(c.title, Kit:Escape(v)) or Kit:Escape(v)
	end,
	info = function(_, k)
		local c = Commands()[Action(k) or ""]
		return { key = KeyName(k.key), title = c and c.title, category = c and c.category }
	end })

tune:See("binding.find", { title = L"FIND", args = { text = "string?", limit = "number?" },
	doc = "binding commands and their keys: those whose command, name or keys hold `text` (no case), without text the ones "
		.. "that have a key; each {command, title, category, keys}; at most `limit` (30, up to 200)",
	run = function(_, a)
		local want = a.text and a.text:lower()
		local limit = math.max(1, math.min(tonumber(a.limit) or 30, 200))
		local all, list = Commands()
		local out = {}
		for _, command in ipairs(list) do
			local c, keys = all[command], { GetBindingKey(command) }
			local hit = not want and #keys > 0
			if want then
				hit = command:lower():find(want, 1, true) or (c.title and c.title:lower():find(want, 1, true))
				for _, key in ipairs(keys) do hit = hit or key:lower() == want end
			end
			if hit then
				out[#out + 1] = { command = command, title = c.title, category = c.category, keys = keys }
				if #out >= limit then break end
			end
		end
		return out
	end })
