---@meta

error("DO NOT REQUIRE THIS FILE")

---@class json
---@field null lightuserdata @ Represents json "null" values
local yyjson = {}

---@param t table|number|string|boolean
---@param empty_as_array? boolean @default true
---@param format? boolean @default true, pretty
---@return string
function yyjson.encode(t, empty_as_array, format)
end

---@param t table
---@return string
function yyjson.pretty_encode(t) end

---@param str string|cstring_ptr
---@param n? integer
---@return table
function yyjson.decode(str, n) end

return yyjson