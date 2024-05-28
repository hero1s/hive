--yaml_test.lua
--luacheck: ignore 631

local log_dump = logger.dump
local yaml     = require("lyaml")
local cxml     = [[
base: &base
  name: Everyone has same name
  id: 123456

foo: &foo
  <<: *base
  age: 10

bar: &bar
  <<: *base
  age: 20

]]

local xlua     = yaml.decode(cxml)
log_dump("lyxml decode yxml:{}", xlua)
local yxml = yaml.encode(xlua)
log_dump("lyxml encode yxml:{}", yxml)

local ok = yaml.save("./bb.yaml", xlua)
log_dump("lyxml save yxml:{}", ok)
local flua = yaml.open("./bb.yaml")
log_dump("lyxml open yaml:{}", flua)
