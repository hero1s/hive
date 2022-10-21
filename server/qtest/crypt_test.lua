--crypt_test.lua
local lcrypt    = require("lcrypt")

local log_info      = logger.info
local lmd5          = lcrypt.md5
local lrandomkey    = lcrypt.randomkey
local lb64encode    = lcrypt.b64_encode
local lb64decode    = lcrypt.b64_decode
local lhex_encode   = lcrypt.hex_encode

local lsha1         = lcrypt.sha1
local lsha224       = lcrypt.sha224
local lsha256       = lcrypt.sha256
local lsha384       = lcrypt.sha384
local lsha512       = lcrypt.sha512

local lhmac_sha1    = lcrypt.hmac_sha1
local lhmac_sha224  = lcrypt.hmac_sha224
local lhmac_sha256  = lcrypt.hmac_sha256
local lhmac_sha384  = lcrypt.hmac_sha384
local lhmac_sha512  = lcrypt.hmac_sha512

--base64
local ran = lrandomkey()
local nonce = lb64encode(ran)
local dnonce = lb64decode(nonce)
log_info("b64encode-> ran: %s, nonce: %s, dnonce:%s", lhex_encode(ran), lhex_encode(nonce), lhex_encode(dnonce))

--sha
local value = "123456779"
local sha1 = lhex_encode(lsha1(value))
log_info("sha1: %s", sha1)
local sha224 = lhex_encode(lsha224(value))
log_info("sha224: %s", sha224)
local sha256 = lhex_encode(lsha256(value))
log_info("sha256: %s", sha256)
local sha384 = lhex_encode(lsha384(value))
log_info("sha384: %s", sha384)
local sha512 = lhex_encode(lsha512(value))
log_info("sha512: %s", sha512)

--md5
local omd5 = lmd5(value)
local nmd5 = lmd5(value, 1)
local hmd5 = lhex_encode(omd5)
log_info("md5: %s", nmd5)
log_info("omd5: %s, hmd5: %s", omd5, hmd5)

--hmac_sha
local key = "1235456"
local hmac_sha1 = lhex_encode(lhmac_sha1(key, value))
log_info("hmac_sha1: %s", hmac_sha1)
local hmac_sha224 = lhex_encode(lhmac_sha224(key, value))
log_info("hmac_sha224: %s", hmac_sha224)
local hmac_sha256 = lhex_encode(lhmac_sha256(key, value))
log_info("hmac_sha256: %s", hmac_sha256)
local hmac_sha384 = lhex_encode(lhmac_sha384(key, value))
log_info("hmac_sha384: %s", hmac_sha384)
local hmac_sha512 = lhex_encode(lhmac_sha512(key, value))
log_info("hmac_sha512: %s", hmac_sha512)

