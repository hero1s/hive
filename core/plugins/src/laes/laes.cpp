#include "aes.h"
#include "lua_kit.h"
#include <vector>
#include <memory>

namespace laes {
    /*
    Examples of commonly used block sizes for data padding.
    WARNING: block size for PKCS7 padding can be 0 < BLOCK_SIZE < 256 bytes.
*/
    typedef enum {
        BLOCK_SIZE_128_BIT = 128 / 8,  /* 16 bytes block */
        BLOCK_SIZE_256_BIT = 256 / 8,  /* 32 bytes block */
        BLOCK_SIZE_CUSTOM_VALUE = 0         /* you can set your own constant to use */
    } paddingBlockSize;                     /* can be used as third argument to the function addPadding() */

    class PKCS7_Padding {
    public:
        PKCS7_Padding() {
            dataWithPadding = NULL;     /* result of adding padding to the data */
            dataLengthWithPadding = 0;  /* length of the result */
            valueOfByteForPadding = 0;  /* used for padding byte value */
        }
        ~PKCS7_Padding()
        {
            if (dataWithPadding) {
                free(dataWithPadding);
                dataWithPadding = NULL;
            }
        }
    public:
        void* dataWithPadding;           /* result of adding padding to the data */
        uint64_t dataLengthWithPadding;  /* length of the result */
        uint8_t  valueOfByteForPadding;  /* used for padding byte value */
    };

    std::shared_ptr<PKCS7_Padding> addPadding(const void* const data, const uint64_t dataLength, const uint8_t BLOCK_SIZE) {
        if (0 == BLOCK_SIZE) {
            puts("ERROR: block size value must be 0 < BLOCK_SIZE < 256");
            return nullptr;
        }
        auto paddingResult = std::make_shared<PKCS7_Padding>();
        uint8_t paddingBytesAmount = BLOCK_SIZE - (dataLength % BLOCK_SIZE);  /* number of bytes to be appended */
        paddingResult->valueOfByteForPadding = paddingBytesAmount;                      /* according to the PKCS7 */
        paddingResult->dataLengthWithPadding = dataLength + paddingBytesAmount;         /* size of the final result */

        uint8_t* dataWithPadding = (uint8_t*)malloc(paddingResult->dataLengthWithPadding);
        if (NULL == paddingResult)
        {
            perror("problem with uint8_t* dataWithPadding");  /* if memory allocation failed */
            return nullptr;
        }

        memcpy(dataWithPadding, data, dataLength);  /* copying the original data for further adding padding */
        for (uint8_t i = 0; i < paddingBytesAmount; i++)
        {
            dataWithPadding[dataLength + i] = paddingResult->valueOfByteForPadding;   /* adding padding bytes */
        }
        paddingResult->dataWithPadding = dataWithPadding;
        return paddingResult;
    }

    class PKCS7_unPadding {
    public:
        PKCS7_unPadding() {
            dataWithoutPadding = NULL;          /* result of remove padding from data */
            dataLengthWithoutPadding = 0;       /* length of the result */
            valueOfRemovedByteFromData = 0;     /* value of byte that was used for padding */
        }
        ~PKCS7_unPadding()
        {
            if (dataWithoutPadding) {
                free(dataWithoutPadding);
                dataWithoutPadding = NULL;
            }
        }
    public:
        void* dataWithoutPadding;         /* result of remove padding from data */
        uint64_t dataLengthWithoutPadding;   /* length of the result */
        uint8_t  valueOfRemovedByteFromData; /* value of byte that was used for padding */
    };

    /*
        Remove PKCS7 padding from data.
        Your data at the provided address does not change. A copy is created, to which the removing padding is applied.
    */
    std::shared_ptr<PKCS7_unPadding> removePadding(const void* const data, const uint64_t dataLength) {
        auto unpaddingResult = std::make_shared<PKCS7_unPadding>();
        uint8_t paddingBytesAmount = *((uint8_t*)data + dataLength - 1);  /* last byte contains length of data to be deleted */
        unpaddingResult->valueOfRemovedByteFromData = paddingBytesAmount;                   /* according to the PKCS7 */
        unpaddingResult->dataLengthWithoutPadding = dataLength - paddingBytesAmount;      /* size of the final result */
        uint8_t* dataWithoutPadding = (uint8_t*)malloc(unpaddingResult->dataLengthWithoutPadding);
        if (NULL == dataWithoutPadding)
        {
            perror("problem with uint8_t* dataWithoutPadding");   /* if memory allocation failed */
            return nullptr;
        }
        memcpy(dataWithoutPadding, data, unpaddingResult->dataLengthWithoutPadding);    /* taking data without bytes containing the padding value */
        unpaddingResult->dataWithoutPadding = dataWithoutPadding;
        return unpaddingResult;
    }

    static int EncryptECB(lua_State* L) {
        int n = lua_gettop(L);
        if (n < 3) {
            luaL_error(L, "aes(mode,key,buf)");
            return 0;
        }
        AESKeyLength mode = (AESKeyLength)luaL_checkinteger(L, 1);
        size_t key_len = 0;
        const uint8_t* key = (const uint8_t*)luaL_checklstring(L, 2, &key_len);
        size_t data_len = 0;
        const char* in = luaL_checklstring(L, 3, &data_len);
        //PKCS
        auto pPaddingResult = addPadding(in, data_len, BLOCK_SIZE_128_BIT);
        if (pPaddingResult == nullptr) {
            return luaL_argerror(L, 3, "input string's param");
        }
        data_len = pPaddingResult->dataLengthWithPadding;
        uint8_t* buf = (uint8_t*)pPaddingResult->dataWithPadding;
        AES aes(mode);
        unsigned char* out = aes.EncryptECB(buf,data_len,key);
        lua_pushlstring(L, (const char*)out, data_len);
        delete[] out;
        return 1;
    }
    static int DecryptECB(lua_State* L) {
        int n = lua_gettop(L);
        if (n < 3) {
            luaL_error(L, "aes(mode,key,buf)");
            return 0;
        }
        AESKeyLength mode = (AESKeyLength)luaL_checkinteger(L, 1);
        size_t key_len = 0;
        const uint8_t* key = (const uint8_t*)luaL_checklstring(L, 2, &key_len);
        size_t data_len = 0;
        const uint8_t* in = (const uint8_t*)luaL_checklstring(L, 3, &data_len);
        AES aes(mode);
        unsigned char* out = aes.DecryptECB(in, data_len, key);
        auto pUnpaddingResult = removePadding(out, data_len);
        if (pUnpaddingResult == nullptr) {
            delete[] out;
            return luaL_argerror(L, 4, "remove padding error");
        }
        lua_pushlstring(L, (const char*)pUnpaddingResult->dataWithoutPadding, pUnpaddingResult->dataLengthWithoutPadding);
        delete[] out;
        return 1;
    }
    static int EncryptCBC(lua_State* L) {
        int n = lua_gettop(L);
        if (n < 4) {
            luaL_error(L, "aes(mode,key,iv,buf)");
            return 0;
        }
        AESKeyLength mode = (AESKeyLength)luaL_checkinteger(L, 1);
        size_t key_len = 0;
        const uint8_t* key = (const uint8_t*)luaL_checklstring(L, 2, &key_len);
        const uint8_t* iv  = (const uint8_t*)luaL_checklstring(L, 3, &key_len);
        size_t data_len = 0;
        const char* in = luaL_checklstring(L, 4, &data_len);
        //PKCS
        auto pPaddingResult = addPadding(in, data_len, BLOCK_SIZE_128_BIT);
        if (pPaddingResult == NULL) {
            return luaL_argerror(L, 4, "input string's param");
        }
        data_len = pPaddingResult->dataLengthWithPadding;
        uint8_t* buf = (uint8_t*)pPaddingResult->dataWithPadding;
        AES aes(mode);
        unsigned char* out = aes.EncryptCBC(buf, data_len, key,iv);
        lua_pushlstring(L, (const char*)out, data_len);
        delete[] out;
        return 1;
    }
    static int DecryptCBC(lua_State* L) {
        int n = lua_gettop(L);
        if (n < 4) {
            luaL_error(L, "aes(mode,key,iv,buf)");
            return 0;
        }
        AESKeyLength mode = (AESKeyLength)luaL_checkinteger(L, 1);
        size_t key_len = 0;
        const uint8_t* key = (const uint8_t*)luaL_checklstring(L, 2, &key_len);
        const uint8_t* iv = (const uint8_t*)luaL_checklstring(L, 3, &key_len);
        size_t data_len = 0;
        const uint8_t* in = (const uint8_t*)luaL_checklstring(L, 4, &data_len);
        AES aes(mode);
        unsigned char* out = aes.DecryptCBC(in, data_len, key, iv);
        auto pUnpaddingResult = removePadding(out, data_len);
        if (pUnpaddingResult == NULL) {
            delete[] out;
            return luaL_argerror(L, 4, "remove padding error");
        }
        lua_pushlstring(L, (const char*)pUnpaddingResult->dataWithoutPadding, pUnpaddingResult->dataLengthWithoutPadding);
        delete[] out;
        return 1;
    }
    static int EncryptCFB(lua_State* L) {
        int n = lua_gettop(L);
        if (n < 4) {
            luaL_error(L, "aes(mode,key,iv,buf)");
            return 0;
        }
        AESKeyLength mode = (AESKeyLength)luaL_checkinteger(L, 1);
        size_t key_len = 0;
        const uint8_t* key = (const uint8_t*)luaL_checklstring(L, 2, &key_len);
        const uint8_t* iv = (const uint8_t*)luaL_checklstring(L, 3, &key_len);
        size_t data_len = 0;
        const char* in = luaL_checklstring(L, 4, &data_len);
        //PKCS
        auto pPaddingResult = addPadding(in, data_len, BLOCK_SIZE_128_BIT);
        if (pPaddingResult == NULL) {
            return luaL_argerror(L, 4, "input string's param");
        }
        data_len = pPaddingResult->dataLengthWithPadding;
        uint8_t* buf = (uint8_t*)pPaddingResult->dataWithPadding;
        AES aes(mode);
        unsigned char* out = aes.EncryptCFB(buf, data_len, key, iv);
        lua_pushlstring(L, (const char*)out, data_len);
        delete[] out;
        return 1;
    }
    static int DecryptCFB(lua_State* L) {
        int n = lua_gettop(L);
        if (n < 4) {
            luaL_error(L, "aes(mode,key,iv,buf)");
            return 0;
        }
        AESKeyLength mode = (AESKeyLength)luaL_checkinteger(L, 1);
        size_t key_len = 0;
        const uint8_t* key = (const uint8_t*)luaL_checklstring(L, 2, &key_len);
        const uint8_t* iv = (const uint8_t*)luaL_checklstring(L, 3, &key_len);
        size_t data_len = 0;
        const uint8_t* in = (const uint8_t*)luaL_checklstring(L, 4, &data_len);
        AES aes(mode);
        unsigned char* out = aes.DecryptCFB(in, data_len, key, iv);
        auto pUnpaddingResult = removePadding(out, data_len);
        if (pUnpaddingResult == NULL) {
            delete[] out;
            return luaL_argerror(L, 4, "remove padding error");
        }
        lua_pushlstring(L, (const char*)pUnpaddingResult->dataWithoutPadding, pUnpaddingResult->dataLengthWithoutPadding);
        delete[] out;
        return 1;
    }

    luakit::lua_table open_laes(lua_State* L) {
        luakit::kit_state kit_state(L);
        auto laes = kit_state.new_table();
        laes.new_enum("AESKeyLength",
            "AES_128", AESKeyLength::AES_128,
            "AES_192", AESKeyLength::AES_192,
            "AES_256", AESKeyLength::AES_256
        );
        laes.set_function("EncryptECB", EncryptECB);
        laes.set_function("DecryptECB", DecryptECB);
        laes.set_function("EncryptCBC", EncryptCBC);
        laes.set_function("DecryptCBC", DecryptCBC);
        laes.set_function("EncryptCFB", EncryptCFB);
        laes.set_function("DecryptCFB", DecryptCFB);
        return laes;
    }
}

extern "C" {
    LUALIB_API int luaopen_laes(lua_State* L) {
        auto laes = laes::open_laes(L);
        return laes.push_stack();
    }
}
