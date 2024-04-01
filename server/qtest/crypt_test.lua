--crypt_test.lua
local lcrypt        = require("lcrypt")

local log_info      = logger.info
local lmd5          = lcrypt.md5
local lrandomkey    = lcrypt.randomkey
local lb64encode    = lcrypt.b64_encode
local lb64decode    = lcrypt.b64_decode
local lhex_encode   = lcrypt.hex_encode
local rsa_init_pkey = lcrypt.rsa_init_pkey
local rsa_init_skey = lcrypt.rsa_init_skey

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
local ran           = lrandomkey()
local nonce         = lb64encode(ran)
local dnonce        = lb64decode(nonce)
log_info("b64encode-> ran: {}, nonce: {}, dnonce:{}", lhex_encode(ran), lhex_encode(nonce), lhex_encode(dnonce))

--sha
local value = "123456779"
local sha1  = lhex_encode(lsha1(value))
log_info("sha1: {}", sha1)
local sha224 = lhex_encode(lsha224(value))
log_info("sha224: {}", sha224)
local sha256 = lhex_encode(lsha256(value))
log_info("sha256: {}", sha256)
local sha384 = lhex_encode(lsha384(value))
log_info("sha384: {}", sha384)
local sha512 = lhex_encode(lsha512(value))
log_info("sha512: {}", sha512)

--md5
local omd5 = lmd5(value)
local nmd5 = lmd5(value, 1)
local hmd5 = lhex_encode(omd5)
log_info("md5: {}", nmd5)
log_info("omd5: {}, hmd5: {}", omd5, hmd5)

--hmac_sha
local key       = "1235456"
local hmac_sha1 = lhex_encode(lhmac_sha1(key, value))
log_info("hmac_sha1: {}", hmac_sha1)
local hmac_sha224 = lhex_encode(lhmac_sha224(key, value))
log_info("hmac_sha224: {}", hmac_sha224)
local hmac_sha256 = lhex_encode(lhmac_sha256(key, value))
log_info("hmac_sha256: {}", hmac_sha256)
local hmac_sha384 = lhex_encode(lhmac_sha384(key, value))
log_info("hmac_sha384: {}", hmac_sha384)
local hmac_sha512 = lhex_encode(lhmac_sha512(key, value))
log_info("hmac_sha512: {}", hmac_sha512)

--rsa
local pem_pub     = [[
MIGfMA0GCSqGSIb3DQEBAQUAA4GNADCBiQKBgQCWKUc5BTsvNKLv389mqShFhg7l
HbG8SyyAiHZ5gMMMoBGayBGgOCGXHDRDUabr0E8xFtSApu9Ppuj3frzwRDcj4Q69
yXc/x1+a18Jt96DI/DJEkmkmo/Mr+pmY4mVFk4a7pxnXpynBUz7E7vp9/XvMs84L
DFqqvGiSmW/YKJfsAQIDAQAB
]]

local pem_pri     = [[
MIICWwIBAAKBgQCWKUc5BTsvNKLv389mqShFhg7lHbG8SyyAiHZ5gMMMoBGayBGg
OCGXHDRDUabr0E8xFtSApu9Ppuj3frzwRDcj4Q69yXc/x1+a18Jt96DI/DJEkmkm
o/Mr+pmY4mVFk4a7pxnXpynBUz7E7vp9/XvMs84LDFqqvGiSmW/YKJfsAQIDAQAB
AoGANhfDnPJZ+izbf07gH0rTg4wB5J5YTwzDiL/f8fAlE3C8NsZYtx9RVmamGxQY
bf158aSYQ4ofTlHBvZptxJ3GQLzJQd2K15UBzBe67y2umN7oP3QD+nUhw83PnD/R
A+aTmEiujIXS9aezbfaADYGd5fFr2ExUPvw9t0Pijxjw8WMCQQDDsGLBH4RTQwPe
koVHia72LF7iQPP75AaOZIuhCTffaLsimA2icO+8/XT2yaeyiXqHn1Wzyk1ZrGgy
MTeTu9jPAkEAxHDPRxNpPUhWQ6IdPWflecKpzT7fPcNJDyd6/Mg3MghWjuWc1xTl
nmBDdlQGOvKsOY4K4ihDZjVMhBnqp16CLwJAOvaT2wMHGRtxOAhIFnUa/dwCvwO5
QGXFv/P1ypD/f9aLxHGycga7heOM8atzVy1reR/+b8z+H43+W1lPGLmaKwJAJ2zA
nPIvX+ZBsec6WRWd/5bq/09L/JhR9GGnFE6WjUsRHDLHDH+cKfIF+Bya93+2wwJX
+tW72Sp/Rc/xwU99bwJAfUw9Nfv8llVA2ZCHkHGNc70BjTyaT/TxLV6jcouDYMTW
RfSHi27F/Ew6pENe4AwY2sfEV2TXrwEdrvfjNWFSPw==
]]

local pub_pem_b64 = lb64decode(string.gsub(pem_pub, "\n", ""))
log_info("pub_pem_b64: {}", lhex_encode(pub_pem_b64))
local pri_pem_b64 = lb64decode(string.gsub(pem_pri, "\n", ""))
log_info("pri_pem_b64: {}", lhex_encode(pri_pem_b64))

local rsav1 = lcrypt.rsa_pencode("xiyoo0812", pub_pem_b64)
log_info("rsa_pencode: {}, {}", #rsav1, lhex_encode(rsav1))
local rsav2 = lcrypt.rsa_sdecode(rsav1, pri_pem_b64)
log_info("rsa_sdecode: {}", rsav2)
local rsav3 = lcrypt.rsa_sencode("xiyoo0812", pri_pem_b64)
log_info("rsa_sencode: {}, {}", #rsav3, lhex_encode(rsav3))
local rsav4 = lcrypt.rsa_pdecode(rsav3, pub_pem_b64)
log_info("rsa_pdecode: {}", rsav4)