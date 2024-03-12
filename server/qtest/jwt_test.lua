local JWT     = import("utility/jwt.lua")

local jwt     = JWT("bejson")

local payload = {
    username = "www.bejson.com",
    sub      = "demo",
    iat      = 1709278981,
    nbf      = 1709278981,
    exp      = 1709365381
}

local token   = jwt:encode(payload)

local result  = jwt:decode(token,true)

logger.debug("token:%s,resutl:%s", token, result)