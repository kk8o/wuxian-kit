-- Arguments. A spec is "string", "number", "boolean", "table" or "any", several of those ("string|number|boolean"), or
-- the strings it may be ("guild|party"); a "?" after it makes it optional. A capability's args are { name = spec }: what a call brings is checked against them (an
-- argument that is not declared is refused: the agent learns the shape from the error) and copied.
local _, ns = ...

local Schema = {}
ns.Schema = Schema

local TYPES = { string = true, number = true, boolean = true, table = true, any = true }

local function One(text)
	if type(text) ~= "string" or text == "" then error("an argument's spec is a string such as \"string\" or \"number?\"", 0) end
	local optional = text:sub(-1) == "?"
	local base = optional and text:sub(1, -2) or text
	if TYPES[base] then return { type = base, optional = optional, text = text } end
	local one, types = {}, true
	for v in base:gmatch("[^|]+") do
		one[v] = true
		if not TYPES[v] then types = false end
	end
	if types then return { types = one, optional = optional, text = text, base = base:gsub("|", " or ") } end
	return { type = "string", optional = optional, one = one, text = text }
end

-- { name = spec text } -> ({ name = spec }, "a (string), b (number?)")
function Schema.Parse(args)
	local out, names = {}, {}
	for name, text in pairs(args or {}) do
		out[name] = One(text)
		names[#names + 1] = ("%s (%s)"):format(name, text)
	end
	table.sort(names)
	return out, #names > 0 and table.concat(names, ", ") or "no arguments"
end

-- what a call brought, checked against capability cap (its id, args, argText): a copy of the declared ones
function Schema.Check(cap, args)
	if args == nil then args = {} end
	if type(args) ~= "table" then error(("%s: args is a table (a JSON object)"):format(cap.id), 0) end
	local out = {}
	for name, spec in pairs(cap.args) do
		local v = args[name]
		if v == nil then
			if not spec.optional then error(("%s: %s is missing (%s)"):format(cap.id, name, spec.text), 0) end
		elseif spec.types then
			if not spec.types[type(v)] then error(("%s: %s is a %s, not a %s"):format(cap.id, name, spec.base, type(v)), 0) end
		elseif spec.type ~= "any" and type(v) ~= spec.type then
			error(("%s: %s is a %s, not a %s"):format(cap.id, name, spec.type, type(v)), 0)
		elseif spec.one and not spec.one[v] then
			error(("%s: %s is one of %s, not %q"):format(cap.id, name, spec.text, ns.Text(v)), 0)
		end
		out[name] = v
	end
	for name in pairs(args) do
		if not cap.args[name] then
			error(("%s: no argument %s (it takes %s)"):format(cap.id, ns.Text(name), cap.argText), 0)
		end
	end
	return out
end
