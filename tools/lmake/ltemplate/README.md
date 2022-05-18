# ltemplate
基于Lua的模板文件生成的工具库！

# 语法支持
- `{{% lua_code %}}` 嵌入执行一段lua代码
- `{{%= lua_variable %}}` 使用lua变量替换此内容

# 嵌入式用法
```lua
local ltmpl = require "ltemplate"

local tpl = [[
Hello {{%= name %}},
Here are your items:
{{% for i, item in pairs(items) do %}}
    * {{%= item %}}
{{% end %}}
]]

local env = {
  name = "leafo",
  items = { "Shoe", "Reflector", "Scarf" }
}
print(ltmpl.render(tpl, env))

--[[
output:
--------------------------------------------------------
Hello leafo,
Here are your items:
    * Shoe
    * Reflector
    * Scarf
--------------------------------------------------------
]]
```

# 工具式用法

```shell
--------------------------------------------------------
--test.tpl
Hello {{%= name %}},
Here are your items:
{{% for i, item in pairs(items) do %}}
    * {{%= item %}}
{{% end %}}
--------------------------------------------------------

--------------------------------------------------------
--test.var
name = "leafo"
items = { "Shoe", "Reflector", "Scarf" }
--------------------------------------------------------

./lua.exe ltemplate.lua test.tpl test.out test.var

--------------------------------------------------------
Hello leafo,
Here are your items:
    * Shoe
    * Reflector
    * Scarf
--------------------------------------------------------
```

