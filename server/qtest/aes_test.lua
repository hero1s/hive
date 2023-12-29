local aes   = require "laes"

local input = "yinguohua"
local key   = "abcdef1234567890abcdef1234567890"
local iv    = "1234567890abcdef"
print("test_encrypt_cbc", string.len(key), string.len(iv))
local got = aes.EncryptCBC(aes.AESKeyLength.AES_256, key, iv, input)
logger.debug("encrypt:{},len:{}", got, string.len(got))
local out = aes.DecryptCBC(aes.AESKeyLength.AES_256, key, iv, got)
logger.debug("{} --> {} --> {}", input, got, out)

--main()
