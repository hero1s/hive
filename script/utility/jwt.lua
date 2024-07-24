import("network/http_helper.lua")
local lcrypt           = require("lcrypt")
local lhmac_sha256     = lcrypt.hmac_sha256

local urlbase64_encode = http_helper.urlbase64_encode
local urlbase64_decode = http_helper.urlbase64_decode

local ssplit           = string_ext.split
local log_err          = logger.err

local JWT              = class()
local prop             = property(JWT)
prop:reader("alg", "HS256")
prop:reader("typ", "JWT")
prop:reader("secret", "")

function JWT:__init(key)
    self.secret = key
end

function JWT:encode(payload)
    local header          = {
        alg = self.alg,
        typ = self.typ
    }
    --将头部和载荷编码为Base64URL字符串
    local encoded_header  = urlbase64_encode(hive.json_encode(header))
    local encoded_payload = urlbase64_encode(hive.json_encode(payload))
    --构建待签名的数据
    local data            = encoded_header .. "." .. encoded_payload
    -- 使用密钥对数据进行HMAC SHA-256签名
    local signature       = urlbase64_encode(lhmac_sha256(self.secret, data))
    --构建JWT令牌
    local jwt_token       = data .. "." .. signature
    return jwt_token
end

function JWT:decode(jwt_token, check)
    local parts = ssplit(jwt_token, ".")
    if #parts ~= 3 then
        return nil, "Invalid token"
    end
    local payload = urlbase64_decode(parts[2])
    if not payload then
        return nil, "Invalid token"
    end
    payload = hive.json_decode(payload)
    if not payload then
        return nil, "Invalid token"
    end
    if check then
        local token = self:encode(payload)
        if token ~= jwt_token then
            log_err("Invalid token:{} -- {}", jwt_token, token)
            return nil, "Invalid token"
        end
    end
    return payload
end

return JWT
