
#include "lua_kit.h"
#include "lcrypt.h"
#include <memory.h>
#include <string.h>

#define SMALL_CHUNK 256
#define LZ_MAX_SIZE_CHUNK 65536

namespace lcrypt {

    static void hash(const char* str, int sz, char key[8]) {
        long djb_hash = 5381L;
        long js_hash = 1315423911L;
        int i;
        for (i = 0; i < sz; i++)
        {
            char c = (char)str[i];
            djb_hash += (djb_hash << 5) + c;
            js_hash ^= ((js_hash << 5) + c + (js_hash >> 2));
        }

        key[0] = djb_hash & 0xff;
        key[1] = (djb_hash >> 8) & 0xff;
        key[2] = (djb_hash >> 16) & 0xff;
        key[3] = (djb_hash >> 24) & 0xff;

        key[4] = js_hash & 0xff;
        key[5] = (js_hash >> 8) & 0xff;
        key[6] = (js_hash >> 16) & 0xff;
        key[7] = (js_hash >> 24) & 0xff;
    }

    static int lhashkey(lua_State* L) {
        size_t sz = 0;
        const char* key = luaL_checklstring(L, 1, &sz);
        char realkey[8];
        hash(key, (int)sz, realkey);
        lua_pushlstring(L, (const char*)realkey, 8);
        return 1;
    }

    static int tohex(lua_State* L, const unsigned char* text, size_t sz) {
        static char hex[] = "0123456789abcdef";
        char tmp[SMALL_CHUNK];
        char* buffer = tmp;
        if (sz > SMALL_CHUNK / 2)
        {
            buffer = (char*)lua_newuserdata(L, sz * 2);
        }
        for (int i = 0; i < sz; i++)
        {
            buffer[i * 2] = hex[text[i] >> 4];
            buffer[i * 2 + 1] = hex[text[i] & 0xf];
        }
        lua_pushlstring(L, buffer, sz * 2);
        return 1;
    }

    static int ltohex(lua_State* L) {
        size_t sz = 0;
        const unsigned char* text = (const unsigned char*)luaL_checklstring(L, 1, &sz);
        return tohex(L, text, sz);
    }

    static int lrandomkey(lua_State* L) {
        char tmp[8];
        int i;
        for (i = 0; i < 8; i++) {
            tmp[i] = rand() & 0xff;
        }
        if (luaL_optinteger(L, 1, 0)) {
            return tohex(L, (const unsigned char*)tmp, 8);
        }
        lua_pushlstring(L, tmp, 8);
        return 1;
    }

#define HEX(v,c) { char tmp = (char) c; if (tmp >= '0' && tmp <= '9') { v = tmp-'0'; } else { v = tmp - 'a' + 10; } }

    static int lfromhex(lua_State* L) {
        size_t sz = 0;
        const unsigned char* text = (const unsigned char*)luaL_checklstring(L, 1, &sz);
        if (sz & 2)
        {
            return luaL_error(L, "Invalid hex text size %d", (int)sz);
        }
        char tmp[SMALL_CHUNK];
        char* buffer = tmp;
        if (sz > SMALL_CHUNK * 2)
        {
            buffer = (char*)lua_newuserdata(L, sz / 2);
        }
        int i;
        for (i = 0; i < sz; i += 2)
        {
            char hi, low;
            HEX(hi, text[i]);
            HEX(low, text[i + 1]);
            if (hi > 16 || low > 16)
            {
                return luaL_error(L, "Invalid hex text", text);
            }
            buffer[i / 2] = hi << 4 | low;
        }
        lua_pushlstring(L, buffer, i / 2);
        return 1;
    }

    static int lxxtea_encode(lua_State* L) {
        size_t data_len = 0;
        size_t encode_len = 0;
        const char* key = luaL_checkstring(L, 1);
        const char* message = luaL_checklstring(L, 2, &data_len);
        char* encode_out = (char*)xxtea_encrypt(message, data_len, key, &encode_len);
        lua_pushlstring(L, encode_out, encode_len);
        free(encode_out);
        return 1;
    }

    static int lxxtea_decode(lua_State* L) {
        size_t data_len = 0;
        size_t decode_len = 0;
        const char* key = luaL_checkstring(L, 1);
        const char* message = luaL_checklstring(L, 2, &data_len);
        char* decode_out = (char*)xxtea_decrypt(message, data_len, key, &decode_len);
        lua_pushlstring(L, decode_out, decode_len);
        free(decode_out);
        return 1;
    }

    static int lbase64_encode(lua_State* L) {
        size_t data_len = 0;
        const char* message = luaL_checklstring(L, 1, &data_len);
        char* encode_out = (char*)malloc(BASE64_ENCODE_OUT_SIZE(data_len));
        unsigned int encode_len = base64_encode((const unsigned char*)message, data_len, encode_out);
        lua_pushlstring(L, encode_out, encode_len);
        free(encode_out);
        return 1;
    }

    static int lbase64_decode(lua_State* L) {
        size_t data_len = 0;
        const char* message = luaL_checklstring(L, 1, &data_len);
        unsigned char* decode_out = (unsigned char*)malloc(BASE64_DECODE_OUT_SIZE(data_len));
        unsigned int decode_len = base64_decode((char*)message, data_len, decode_out);
        lua_pushlstring(L, (const char*)decode_out, decode_len);
        free(decode_out);
        return 1;
    }

    static int lmd5(lua_State* L) {
        size_t data_len = 0;
        const char* message = luaL_checklstring(L, 1, &data_len);
        char output[HASHSIZE];
        md5(message, data_len, output);
        if (luaL_optinteger(L, 2, 0)) {
            return tohex(L, (const unsigned char*)output, HASHSIZE);
        }
        lua_pushlstring(L, output, HASHSIZE);
        return 1;
    }

    static int des56_decrypt(lua_State* L) {
        char* decypheredText;
        keysched KS;
        int rel_index, abs_index;
        size_t cypherlen;
        const char* cypheredText = luaL_checklstring(L, 1, &cypherlen);
        const char* key = luaL_optstring(L, 2, NULL);
        int padinfo;

        padinfo = cypheredText[cypherlen - 1];
        cypherlen--;

        /* Aloca array */
        decypheredText = (char*)malloc((cypherlen + 1) * sizeof(char));
        /* Inicia decifragem */
        if (key && strlen(key) >= 8)
        {
            char k[8];
            int i;

            for (i = 0; i < 8; i++)
                k[i] = (unsigned char)key[i];
            fsetkey(k, &KS);
        }
        else
        {
            lua_pushstring(L, "Error decrypting file. Invalid key.");
            lua_error(L);
        }
        rel_index = 0;
        abs_index = 0;
        while (abs_index < (int)cypherlen)
        {
            decypheredText[abs_index] = cypheredText[abs_index];
            abs_index++;
            rel_index++;
            if (rel_index == 8)
            {
                rel_index = 0;
                fencrypt(&(decypheredText[abs_index - 8]), 1, &KS);
            }
        }
        decypheredText[abs_index] = 0;
        lua_pushlstring(L, decypheredText, (abs_index - padinfo));
        free(decypheredText);
        return 1;
    }

    static int des56_crypt(lua_State* L) {
        char* cypheredText;
        keysched KS;
        int rel_index, pad, abs_index;
        size_t plainlen;
        const char* plainText = luaL_checklstring(L, 1, &plainlen);
        const char* key = luaL_optstring(L, 2, NULL);

        cypheredText = (char*)malloc((plainlen + 8) * sizeof(char));
        if (key && strlen(key) >= 8)
        {
            char k[8];
            int i;
            for (i = 0; i < 8; i++)
                k[i] = (unsigned char)key[i];
            fsetkey(k, &KS);
        }
        else
        {
            lua_pushstring(L, "Error encrypting file. Invalid key.");
            lua_error(L);
        }

        rel_index = 0;
        abs_index = 0;
        while (abs_index < (int)plainlen)
        {
            cypheredText[abs_index] = plainText[abs_index];
            abs_index++;
            rel_index++;
            if (rel_index == 8)
            {
                rel_index = 0;
                fencrypt(&(cypheredText[abs_index - 8]), 0, &KS);
            }
        }

        pad = 0;
        if (rel_index != 0)
        { /* Pads remaining bytes with zeroes */
            while (rel_index < 8)
            {
                pad++;
                cypheredText[abs_index++] = 0;
                rel_index++;
            }
            fencrypt(&(cypheredText[abs_index - 8]), 0, &KS);
        }
        cypheredText[abs_index] = pad;
        lua_pushlstring(L, cypheredText, abs_index + 1);
        free(cypheredText);
        return 1;
    }

    static int lz4_encode(lua_State* L) {
        size_t data_len = 0;
        char dest[LZ_MAX_SIZE_CHUNK];
        const char* message = luaL_checklstring(L, 1, &data_len);
        int out_len = LZ4_compress_default(message, dest, data_len, LZ_MAX_SIZE_CHUNK);
        if (out_len > 0)
        {
            lua_pushlstring(L, dest, out_len);
            return 1;
        }
        lua_pushstring(L, "lz4 compress failed!");
        lua_error(L);
        return 1;
    }

    static int lz4_decode(lua_State* L) {
        size_t data_len = 0;
        char dest[LZ_MAX_SIZE_CHUNK];
        const char* message = luaL_checklstring(L, 1, &data_len);
        int out_len = LZ4_decompress_safe(message, dest, data_len, LZ_MAX_SIZE_CHUNK);
        if (out_len > 0)
        {
            lua_pushlstring(L, dest, out_len);
            return 1;
        }
        lua_pushstring(L, "lz4 decompress failed!");
        lua_error(L);
        return 1;
    }

    static int lsha1(lua_State* L) {
        size_t sz = 0;
        uint8_t digest[SHA1_DIGEST_SIZE];
        const uint8_t* buffer = (const uint8_t*)luaL_checklstring(L, 1, &sz);
        sha1(buffer, sz, digest);
        lua_pushlstring(L, (const char*)digest, SHA1_DIGEST_SIZE);
        return 1;
    }

    static int lsha224(lua_State* L) {
        size_t sz = 0;
        uint8_t digest[SHA224_DIGEST_SIZE];
        const uint8_t* buffer = (const uint8_t*)luaL_checklstring(L, 1, &sz);
        sha224(buffer, sz, digest);
        lua_pushlstring(L, (const char*)digest, SHA224_DIGEST_SIZE);
        return 1;
    }

    static int lsha256(lua_State* L) {
        size_t sz = 0;
        uint8_t digest[SHA256_DIGEST_SIZE];
        const uint8_t* buffer = (const uint8_t*)luaL_checklstring(L, 1, &sz);
        sha256(buffer, sz, digest);
        lua_pushlstring(L, (const char*)digest, SHA256_DIGEST_SIZE);
        return 1;
    }

    static int lsha384(lua_State* L) {
        size_t sz = 0;
        uint8_t digest[SHA384_DIGEST_SIZE];
        const uint8_t* buffer = (const uint8_t*)luaL_checklstring(L, 1, &sz);
        sha384(buffer, sz, digest);
        lua_pushlstring(L, (const char*)digest, SHA384_DIGEST_SIZE);
        return 1;
    }

    static int lsha512(lua_State* L) {
        size_t sz = 0;
        uint8_t digest[SHA512_DIGEST_SIZE];
        const uint8_t* buffer = (const uint8_t*)luaL_checklstring(L, 1, &sz);
        sha512(buffer, sz, digest);
        lua_pushlstring(L, (const char*)digest, SHA512_DIGEST_SIZE);
        return 1;
    }

    static int lhmac_sha1(lua_State* L) {
        size_t key_sz = 0, text_sz = 0;
        uint8_t digest[SHA1_DIGEST_SIZE];
        const uint8_t* key = (const uint8_t*)luaL_checklstring(L, 1, &key_sz);
        const uint8_t* text = (const uint8_t*)luaL_checklstring(L, 2, &text_sz);
        hmac_sha1(key, key_sz, text, text_sz, digest);
        lua_pushlstring(L, (const char*)digest, SHA1_DIGEST_SIZE);
        return 1;
    }

    static int lhmac_sha224(lua_State* L) {
        size_t key_sz = 0, text_sz = 0;
        uint8_t digest[SHA224_DIGEST_SIZE];
        const uint8_t* key = (const uint8_t*)luaL_checklstring(L, 1, &key_sz);
        const uint8_t* text = (const uint8_t*)luaL_checklstring(L, 2, &text_sz);
        hmac_sha224(key, key_sz, text, text_sz, digest);
        lua_pushlstring(L, (const char*)digest, SHA224_DIGEST_SIZE);
        return 1;
    }

    static int lhmac_sha256(lua_State* L) {
        size_t key_sz = 0, text_sz = 0;
        uint8_t digest[SHA256_DIGEST_SIZE];
        const uint8_t* key = (const uint8_t*)luaL_checklstring(L, 1, &key_sz);
        const uint8_t* text = (const uint8_t*)luaL_checklstring(L, 2, &text_sz);
        hmac_sha256(key, key_sz, text, text_sz, digest);
        lua_pushlstring(L, (const char*)digest, SHA256_DIGEST_SIZE);
        return 1;
    }

    static int lhmac_sha384(lua_State* L) {
        size_t key_sz = 0, text_sz = 0;
        uint8_t digest[SHA384_DIGEST_SIZE];
        const uint8_t* key = (const uint8_t*)luaL_checklstring(L, 1, &key_sz);
        const uint8_t* text = (const uint8_t*)luaL_checklstring(L, 2, &text_sz);
        hmac_sha384(key, key_sz, text, text_sz, digest);
        lua_pushlstring(L, (const char*)digest, SHA384_DIGEST_SIZE);
        return 1;
    }

    static int lhmac_sha512(lua_State* L) {
        size_t key_sz = 0, text_sz = 0;
        uint8_t digest[SHA512_DIGEST_SIZE];
        const uint8_t* key = (const uint8_t*)luaL_checklstring(L, 1, &key_sz);
        const uint8_t* text = (const uint8_t*)luaL_checklstring(L, 2, &text_sz);
        hmac_sha512(key, key_sz, text, text_sz, digest);
        lua_pushlstring(L, (const char*)digest, SHA512_DIGEST_SIZE);
        return 1;
    }

    static int lxor_byte(lua_State* L) {
        size_t len1, len2;
        const char* s1 = luaL_checklstring(L, 1, &len1);
        const char* s2 = luaL_checklstring(L, 2, &len2);
        if (len2 == 0) {
            return luaL_error(L, "Can't xor empty string");
        }
        luaL_Buffer b;
        char* buffer = luaL_buffinitsize(L, &b, len1);
        int i;
        for (i = 0; i < len1; i++) {
            buffer[i] = s1[i] ^ s2[i % len2];
        }
        luaL_addsize(&b, len1);
        luaL_pushresult(&b);
        return 1;
    }

    static bool lrsa_init_public_key(lua_State* L, rsa_pk_t* pk) {
        size_t pubkey_sz = 0;
        uint8_t* pubkey_b64 = (uint8_t*)luaL_checklstring(L, 2, &pubkey_sz);
        int code = rsa_init_public_key(pubkey_b64, pubkey_sz, pk);
        if (code != 0) {
            lua_pushnil(L);
            lua_pushinteger(L, code);
            return false;
        }
        return true;
    }

    static int lrsa_init_private_key(lua_State* L, rsa_sk_t* sk) {
        size_t prikey_sz = 0;
        uint8_t* prikey_b64 = (uint8_t*)luaL_checklstring(L, 2, &prikey_sz);
        int code = rsa_init_private_key(prikey_b64, prikey_sz, sk);
        if (code != 0) {
            lua_pushnil(L);
            lua_pushinteger(L, code);
            return false;
        }
        return true;
    }

    static int lrsa_public_encrypt(lua_State* L) {
        rsa_pk_t spk;
        if (!lrsa_init_public_key(L, &spk)) {
            return 2;
        }
        size_t key_sz = 0; uint32_t dest_sz = 0, out_sz = 0;
        uint8_t* key = (uint8_t*)luaL_checklstring(L, 1, &key_sz);
        int ss = RSA_ENCODE_OUT_SIZE(key_sz);
        char* dest = (char*)malloc(RSA_ENCODE_OUT_SIZE(key_sz));
        while (key_sz > 0) {
            int in_sz = key_sz > RSA_MAX_ENCODE_LEN ? RSA_MAX_ENCODE_LEN : key_sz;
            int code = rsa_public_encrypt((uint8_t*)dest + dest_sz, &out_sz, key, in_sz, &spk);
            if (code != 0) {
                lua_pushnil(L);
                lua_pushinteger(L, code);
                free(dest);
                return 2;
            }
            key += in_sz;
            key_sz -= in_sz;
            dest_sz += out_sz;
        }
        lua_pushlstring(L, (const char*)dest, dest_sz);
        free(dest);
        return 1;
    }

    static int lrsa_public_decrypt(lua_State* L) {
        rsa_pk_t spk;
        if (!lrsa_init_public_key(L, &spk)) {
            return 2;
        }
        size_t key_sz = 0; uint32_t dest_sz = 0, out_sz = 0;
        uint8_t* key = (uint8_t*)luaL_checklstring(L, 1, &key_sz);
        char* dest = (char*)malloc(RSA_DECODE_OUT_SIZE(key_sz));
        while (key_sz > 0) {
            int in_sz = key_sz > RSA_MAX_MODULUS_LEN ? RSA_MAX_MODULUS_LEN : key_sz;
            int code = rsa_public_decrypt((uint8_t*)dest + dest_sz, &out_sz, key, in_sz, &spk);
            if (code != 0) {
                lua_pushnil(L);
                lua_pushinteger(L, code);
                free(dest);
                return 2;
            }
            key += in_sz;
            key_sz -= in_sz;
            dest_sz += out_sz;
        }
        lua_pushlstring(L, (const char*)dest, dest_sz);
        free(dest);
        return 1;
    }

    static int lrsa_private_encrypt(lua_State* L) {
        rsa_sk_t ssk;
        if (!lrsa_init_private_key(L, &ssk)) {
            return 2;
        }
        size_t key_sz = 0; uint32_t dest_sz = 0, out_sz = 0;
        uint8_t* key = (uint8_t*)luaL_checklstring(L, 1, &key_sz);
        char* dest = (char*)malloc(RSA_ENCODE_OUT_SIZE(key_sz));
        while (key_sz > 0) {
            int in_sz = key_sz > RSA_MAX_ENCODE_LEN ? RSA_MAX_ENCODE_LEN : key_sz;
            int code = rsa_private_encrypt((uint8_t*)dest + dest_sz, &out_sz, key, in_sz, &ssk);
            if (code != 0) {
                lua_pushnil(L);
                lua_pushinteger(L, code);
                free(dest);
                return 2;
            }
            key += in_sz;
            key_sz -= in_sz;
            dest_sz += out_sz;
        }
        lua_pushlstring(L, (const char*)dest, dest_sz);
        free(dest);
        return 1;
    }

    static int lrsa_private_decrypt(lua_State* L) {
        rsa_sk_t ssk;
        if (!lrsa_init_private_key(L, &ssk)) {
            return 2;
        }
        size_t key_sz = 0; uint32_t dest_sz = 0, out_sz = 0;
        uint8_t* key = (uint8_t*)luaL_checklstring(L, 1, &key_sz);
        int ss = RSA_DECODE_OUT_SIZE(key_sz);
        char* dest = (char*)malloc(RSA_DECODE_OUT_SIZE(key_sz));
        while (key_sz > 0) {
            int in_sz = key_sz > RSA_MAX_MODULUS_LEN ? RSA_MAX_MODULUS_LEN : key_sz;
            int code = rsa_private_decrypt((uint8_t*)dest + dest_sz, &out_sz, key, in_sz, &ssk);
            if (code != 0) {
                lua_pushnil(L);
                lua_pushinteger(L, code);
                free(dest);
                return 2;
            }
            key += in_sz;
            key_sz -= in_sz;
            dest_sz += out_sz;
        }
        lua_pushlstring(L, (const char*)dest, dest_sz);
        free(dest);
        return 1;
    }

    luakit::lua_table open_lcrypt(lua_State* L) {
        luakit::kit_state kit_state(L);
        auto luacrypt = kit_state.new_table();
        luacrypt.set_function("md5", lmd5);
        luacrypt.set_function("sha1", lsha1);
        luacrypt.set_function("sha224", lsha224);
        luacrypt.set_function("sha256", lsha256);
        luacrypt.set_function("sha384", lsha384);
        luacrypt.set_function("sha512", lsha512);
        luacrypt.set_function("hmac_sha1", lhmac_sha1);
        luacrypt.set_function("hmac_sha224", lhmac_sha224);
        luacrypt.set_function("hmac_sha256", lhmac_sha256);
        luacrypt.set_function("hmac_sha384", lhmac_sha384);
        luacrypt.set_function("hmac_sha512", lhmac_sha512);
        luacrypt.set_function("hashkey", lhashkey);
        luacrypt.set_function("randomkey", lrandomkey);
        luacrypt.set_function("hex_encode", ltohex);
        luacrypt.set_function("hex_decode", lfromhex);
        luacrypt.set_function("des_encode", des56_crypt);
        luacrypt.set_function("des_encode", des56_decrypt);
        luacrypt.set_function("lz4_encode", lz4_encode);
        luacrypt.set_function("lz4_decode", lz4_decode);
        luacrypt.set_function("b64_encode", lbase64_encode);
        luacrypt.set_function("b64_decode", lbase64_decode);
        luacrypt.set_function("xxtea_encode", lxxtea_encode);
        luacrypt.set_function("xxtea_decode", lxxtea_decode);
        luacrypt.set_function("xor_byte", lxor_byte);
        luacrypt.set_function("rsa_pencode", lrsa_public_encrypt);
        luacrypt.set_function("rsa_sencode", lrsa_private_encrypt);
        luacrypt.set_function("rsa_pdecode", lrsa_public_decrypt);
        luacrypt.set_function("rsa_sdecode", lrsa_private_decrypt);

        return luacrypt;
    }
}

extern "C" {
    LUALIB_API int luaopen_lcrypt(lua_State* L) {
        auto crypt = lcrypt::open_lcrypt(L);
        return crypt.push_stack();
    }
}