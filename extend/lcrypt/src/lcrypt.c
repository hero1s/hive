
#include "lua.h"
#include "lauxlib.h"
#include "lualib.h"
#include "lz4.h"
#include "md5.h"
#include "sha1.h"
#include "sha2.h"
#include "xxtea.h"
#include "des56.h"
#include "base64.h"
#include "guid.h"
#include "lcrypt.h"
#include <memory.h>
#include <string.h>

static int lrandomkey(lua_State *L)
{
    char tmp[8];
    int i;
    for (i=0;i<8;i++)
    {
        tmp[i] = rand() & 0xff;
    }
    lua_pushlstring(L, tmp, 8);
    return 1;
}

static void hash(const char * str, int sz, char key[8])
{
    long djb_hash = 5381L;
    long js_hash = 1315423911L;
    int i;
    for (i=0;i<sz;i++)
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

static int lhashkey(lua_State *L)
{
    size_t sz = 0;
    const char * key = luaL_checklstring(L, 1, &sz);
    char realkey[8];
    hash(key,(int)sz,realkey);
    lua_pushlstring(L, (const char *)realkey, 8);
    return 1;
}

static int tohex(lua_State *L, const unsigned char* text, size_t sz)
{
    static char hex[] = "0123456789abcdef";
    char tmp[SMALL_CHUNK];
    char *buffer = tmp;
    if (sz > SMALL_CHUNK/2)
    {
        buffer = (char *)lua_newuserdata(L, sz * 2);
    }
    for (int i=0;i<sz;i++)
    {
        buffer[i*2] = hex[text[i] >> 4];
        buffer[i*2+1] = hex[text[i] & 0xf];
    }
    lua_pushlstring(L, buffer, sz * 2);
    return 1;
}

static int ltohex(lua_State *L)
{
    size_t sz = 0;
    const unsigned char * text = (const unsigned char *)luaL_checklstring(L, 1, &sz);
    return tohex(L, text, sz);
}

#define HEX(v,c) { char tmp = (char) c; if (tmp >= '0' && tmp <= '9') { v = tmp-'0'; } else { v = tmp - 'a' + 10; } }

static int lfromhex(lua_State *L)
{
    size_t sz = 0;
    const unsigned char * text = (const unsigned char*)luaL_checklstring(L, 1, &sz);
    if (sz & 2)
    {
        return luaL_error(L, "Invalid hex text size %d", (int)sz);
    }
    char tmp[SMALL_CHUNK];
    char *buffer = tmp;
    if (sz > SMALL_CHUNK*2)
    {
        buffer = (char *)lua_newuserdata(L, sz / 2);
    }
    int i;
    for (i=0;i<sz;i+=2)
    {
        char hi,low;
        HEX(hi, text[i]);
        HEX(low, text[i+1]);
        if (hi > 16 || low > 16)
        {
            return luaL_error(L, "Invalid hex text", text);
        }
        buffer[i/2] = hi<<4 | low;
    }
    lua_pushlstring(L, buffer, i/2);
    return 1;
}

static int lxxtea_encode(lua_State* L)
{
    size_t data_len = 0;
    size_t encode_len = 0;
    const char* key = luaL_checkstring(L, 1);
    const char* message = luaL_checklstring(L, 2, &data_len);
    char* encode_out = (char *)xxtea_encrypt(message, data_len, key, &encode_len);
    lua_pushlstring(L, encode_out, encode_len);
    free(encode_out);
    return 1;
}

static int lxxtea_decode(lua_State* L)
{
    size_t data_len = 0;
    size_t decode_len = 0;
    const char* key = luaL_checkstring(L, 1);
    const char* message = luaL_checklstring(L, 2, &data_len);
    char* decode_out = (char *)xxtea_decrypt(message, data_len, key, &decode_len);
    lua_pushlstring(L, decode_out, decode_len);
    free(decode_out);
    return 1;
}

static int lbase64_encode(lua_State* L)
{
    size_t data_len = 0;
    const char* message = luaL_checklstring(L, 1, &data_len);
    char* encode_out =  (char *)malloc(BASE64_ENCODE_OUT_SIZE(data_len));
    unsigned int encode_len = base64_encode((const unsigned char*)message, data_len, encode_out);
    lua_pushlstring(L, encode_out, encode_len);
    free(encode_out);
    return 1;
}

static int lbase64_decode(lua_State* L)
{
    size_t data_len = 0;
    const char* message = luaL_checklstring(L, 1, &data_len);
    unsigned char* decode_out = (unsigned char*)malloc(BASE64_DECODE_OUT_SIZE(data_len));
    unsigned int decode_len = base64_decode((char*)message, data_len, decode_out);
    lua_pushlstring(L, (const char*)decode_out, decode_len);
    free(decode_out);
    return 1;
}

static int lmd5(lua_State* L)
{
    size_t data_len = 0;
    const char* message = luaL_checklstring(L, 1, &data_len);
    char output[HASHSIZE];
    md5(message, data_len, output);
    if (luaL_optinteger(L, 2, 0))
    {
        return tohex(L, output, HASHSIZE);
    }
    lua_pushlstring(L, output, HASHSIZE);
    return 1;
}

static int des56_decrypt( lua_State *L )
{
    char* decypheredText;
    keysched KS;
    int rel_index, abs_index;
    size_t cypherlen;
    const char *cypheredText = luaL_checklstring(L, 1, &cypherlen);
    const char *key = luaL_optstring(L, 2, NULL);
    int padinfo;

    padinfo = cypheredText[cypherlen-1];
    cypherlen--;

    /* Aloca array */
    decypheredText = (char *) malloc((cypherlen+1) * sizeof(char));
    /* Inicia decifragem */
    if (key && strlen(key) >= 8)
    {
        char k[8];
        int i;

        for (i=0; i<8; i++)
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
    while (abs_index < (int) cypherlen)
    {
        decypheredText[abs_index] = cypheredText[abs_index];
        abs_index++;
        rel_index++;
        if( rel_index == 8 )
        {
            rel_index = 0;
            fencrypt(&(decypheredText[abs_index - 8]), 1, &KS);
        }
    }
    decypheredText[abs_index] = 0;
    lua_pushlstring(L, decypheredText, (abs_index-padinfo));
    free(decypheredText);
    return 1;
}

static int des56_crypt( lua_State *L )
{
    char *cypheredText;
    keysched KS;
    int rel_index, pad, abs_index;
    size_t plainlen;
    const char *plainText = luaL_checklstring( L, 1, &plainlen );
    const char *key = luaL_optstring( L, 2, NULL );

    cypheredText = (char *) malloc( (plainlen+8) * sizeof(char));
    if (key && strlen(key) >= 8)
    {
        char k[8];
        int i;
        for (i=0; i<8; i++)
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
    while (abs_index < (int) plainlen)
    {
        cypheredText[abs_index] = plainText[abs_index];
        abs_index++;
        rel_index++;
        if( rel_index == 8 )
        {
            rel_index = 0;
            fencrypt(&(cypheredText[abs_index - 8]), 0, &KS);
        }
    }

    pad = 0;
    if(rel_index != 0)
    { /* Pads remaining bytes with zeroes */
        while(rel_index < 8)
        {
            pad++;
            cypheredText[abs_index++] = 0;
            rel_index++;
        }
        fencrypt(&(cypheredText[abs_index - 8]), 0, &KS);
    }
    cypheredText[abs_index] = pad;
    lua_pushlstring( L, cypheredText, abs_index+1 );
    free( cypheredText );
    return 1;
}

static int lz4_encode(lua_State* L)
{
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

static int lz4_decode(lua_State* L)
{
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

static int lsha1(lua_State* L)
{
    size_t sz = 0;
    uint8_t digest[SHA1_DIGEST_SIZE];
    const uint8_t* buffer = (const uint8_t*)luaL_checklstring(L, 1, &sz);
    sha1(buffer, sz, digest);
    lua_pushlstring(L, (const char*)digest, SHA1_DIGEST_SIZE);
    return 1;
}

static int lsha224(lua_State* L)
{
    size_t sz = 0;
    uint8_t digest[SHA224_DIGEST_SIZE];
    const uint8_t* buffer = (const uint8_t*)luaL_checklstring(L, 1, &sz);
    sha224(buffer, sz, digest);
    lua_pushlstring(L, (const char*)digest, SHA224_DIGEST_SIZE);
    return 1;
}

static int lsha256(lua_State* L)
{
    size_t sz = 0;
    uint8_t digest[SHA256_DIGEST_SIZE];
    const uint8_t* buffer = (const uint8_t*)luaL_checklstring(L, 1, &sz);
    sha256(buffer, sz, digest);
    lua_pushlstring(L, (const char*)digest, SHA256_DIGEST_SIZE);
    return 1;
}

static int lsha384(lua_State* L)
{
    size_t sz = 0;
    uint8_t digest[SHA384_DIGEST_SIZE];
    const uint8_t* buffer = (const uint8_t*)luaL_checklstring(L, 1, &sz);
    sha384(buffer, sz, digest);
    lua_pushlstring(L, (const char*)digest, SHA384_DIGEST_SIZE);
    return 1;
}

static int lsha512(lua_State* L)
{
    size_t sz = 0;
    uint8_t digest[SHA512_DIGEST_SIZE];
    const uint8_t* buffer = (const uint8_t*)luaL_checklstring(L, 1, &sz);
    sha512(buffer, sz, digest);
    lua_pushlstring(L, (const char*)digest, SHA512_DIGEST_SIZE);
    return 1;
}

static int lhmac_sha1(lua_State *L)
{
    size_t key_sz = 0, text_sz = 0;
    uint8_t digest[SHA1_DIGEST_SIZE];
    const uint8_t* key = (const uint8_t*)luaL_checklstring(L, 1, &key_sz);
    const uint8_t* text = (const uint8_t*)luaL_checklstring(L, 2, &text_sz);
    hmac_sha1(key, key_sz, text, text_sz, digest);
    lua_pushlstring(L, (const char*)digest, SHA1_DIGEST_SIZE);
    return 1;
}

static int lhmac_sha224(lua_State* L)
{
    size_t key_sz = 0, text_sz = 0;
    uint8_t digest[SHA224_DIGEST_SIZE];
    const uint8_t* key = (const uint8_t*)luaL_checklstring(L, 1, &key_sz);
    const uint8_t* text = (const uint8_t*)luaL_checklstring(L, 2, &text_sz);
    hmac_sha224(key, key_sz, text, text_sz, digest);
    lua_pushlstring(L, (const char*)digest, SHA224_DIGEST_SIZE);
    return 1;
}

static int lhmac_sha256(lua_State* L)
{
    size_t key_sz = 0, text_sz = 0;
    uint8_t digest[SHA256_DIGEST_SIZE];
    const uint8_t* key = (const uint8_t*)luaL_checklstring(L, 1, &key_sz);
    const uint8_t* text = (const uint8_t*)luaL_checklstring(L, 2, &text_sz);
    hmac_sha256(key, key_sz, text, text_sz, digest);
    lua_pushlstring(L, (const char*)digest, SHA256_DIGEST_SIZE);
    return 1;
}

static int lhmac_sha384(lua_State* L)
{
    size_t key_sz = 0, text_sz = 0;
    uint8_t digest[SHA384_DIGEST_SIZE];
    const uint8_t* key = (const uint8_t*)luaL_checklstring(L, 1, &key_sz);
    const uint8_t* text = (const uint8_t*)luaL_checklstring(L, 2, &text_sz);
    hmac_sha384(key, key_sz, text, text_sz, digest);
    lua_pushlstring(L, (const char*)digest, SHA384_DIGEST_SIZE);
    return 1;
}

static int lhmac_sha512(lua_State* L)
{
    size_t key_sz = 0, text_sz = 0;
    uint8_t digest[SHA512_DIGEST_SIZE];
    const uint8_t* key = (const uint8_t*)luaL_checklstring(L, 1, &key_sz);
    const uint8_t* text = (const uint8_t*)luaL_checklstring(L, 2, &text_sz);
    hmac_sha512(key, key_sz, text, text_sz, digest);
    lua_pushlstring(L, (const char*)digest, SHA512_DIGEST_SIZE);
    return 1;
}

static int lguid_new(lua_State* L) {
    size_t group = 0, index = 0;
    int top = lua_gettop(L);
    if (top > 1) {
        group = lua_tointeger(L, 1);
        index = lua_tointeger(L, 2);
    }
    else if (top > 0) {
        group = lua_tointeger(L, 1);
        index = rand();
    }
    else {
        group = rand();
        index = rand();
    }
    size_t guid = new_guid(group, index);
    lua_pushinteger(L, guid);
    return 1;
}

static int lguid_string(lua_State* L) {
    size_t group = 0, index = 0;
    int top = lua_gettop(L);
    if (top > 1) {
        group = lua_tointeger(L, 1);
        index = lua_tointeger(L, 2);
    }
    else if (top > 0) {
        group = lua_tointeger(L, 1);
        index = rand();
    }
    else {
        group = rand();
        index = rand();
    }
    char sguid[32];
    size_t guid = new_guid(group, index);
    snprintf(sguid, 32, "%llx", guid);
    lua_pushstring(L, sguid);
    return 1;
}

static int lguid_tostring(lua_State* L) {
    char sguid[32];
    size_t guid = lua_tointeger(L, 1);
    snprintf(sguid, 32, "%llx", guid);
    lua_pushstring(L, sguid);
    return 1;
}

static int lguid_number(lua_State* L) {
    char* chEnd = NULL;
    const char* guid = lua_tostring(L, 1);
    lua_pushinteger(L, strtoull(guid, &chEnd, 16));
    return 1;
}

size_t lguid_fmt_number(lua_State* L) {
    if (lua_type(L, 1) == LUA_TSTRING) {
        char* chEnd = NULL;
        const char* sguid = lua_tostring(L, 1);
        return strtoull(sguid, &chEnd, 16);
    }
    else {
        return lua_tointeger(L, 1);
    }
}

static int lguid_group(lua_State* L) {
    size_t guid = lguid_fmt_number(L);
    lua_pushinteger(L, guid & 0x3ff);
    return 1;
}

static int lguid_index(lua_State* L) {
    size_t guid = lguid_fmt_number(L);
    lua_pushinteger(L, (guid >> GROUP_BITS) & 0x3ff);
    return 1;
}

static int lguid_time(lua_State* L) {
    size_t guid = lguid_fmt_number(L);
    size_t time = (guid >> (GROUP_BITS + INDEX_BITS + SNUM_BITS)) & 0x3fffffff;
    lua_pushinteger(L, time + BASE_TIME);
    return 1;
}

static int lguid_source(lua_State* L) {
    size_t guid = lguid_fmt_number(L);
    lua_pushinteger(L, guid & 0x3ff);
    lua_pushinteger(L, (guid >> GROUP_BITS) & 0x3ff);
    lua_pushinteger(L, ((guid >> (GROUP_BITS + INDEX_BITS + SNUM_BITS)) & 0x3fffffff) + BASE_TIME);
    return 3;
}

static int lxor_byte(lua_State *L) {
    size_t len1,len2;
    const char *s1 = luaL_checklstring(L,1,&len1);
    const char *s2 = luaL_checklstring(L,2,&len2);
    if (len2 == 0) {
        return luaL_error(L, "Can't xor empty string");
    }
    luaL_Buffer b;
    char * buffer = luaL_buffinitsize(L, &b, len1);
    int i;
    for (i=0;i<len1;i++) {
        buffer[i] = s1[i] ^ s2[i % len2];
    }
    luaL_addsize(&b, len1);
    luaL_pushresult(&b);
    return 1;
}

static const luaL_Reg lcrypt_funcs[] = {
    { "md5", lmd5 },
    { "sha1", lsha1 },
    { "sha224", lsha224 },
    { "sha256", lsha256 },
    { "sha384", lsha384 },
    { "sha512", lsha512 },
    { "hmac_sha1", lhmac_sha1 },
    { "hmac_sha224", lhmac_sha224 },
    { "hmac_sha256", lhmac_sha256 },
    { "hmac_sha384", lhmac_sha384 },
    { "hmac_sha512", lhmac_sha512 },
    { "hashkey", lhashkey },
    { "randomkey", lrandomkey },
    { "hex_encode", ltohex },
    { "hex_decode", lfromhex },
    { "des_encode", des56_crypt },
    { "des_encode", des56_decrypt },
    { "lz4_encode", lz4_encode },
    { "lz4_decode", lz4_decode },
    { "b64_encode", lbase64_encode },
    { "b64_decode", lbase64_decode },
    { "xxtea_encode", lxxtea_encode },
    { "xxtea_decode", lxxtea_decode },
    { "guid_new", lguid_new },
    { "guid_string", lguid_string },
    { "guid_tostring", lguid_tostring },
    { "guid_number", lguid_number },
    { "guid_group", lguid_group },
    { "guid_index", lguid_index },
    { "guid_time", lguid_time },
    { "guid_source", lguid_source },
    { "xor_byte", lxor_byte },
    { NULL, NULL },
};

LCRYPT_API int luaopen_lcrypt(lua_State* L) {
    luaL_checkversion(L);
    luaL_newlib(L, lcrypt_funcs);
    return 1;
}
