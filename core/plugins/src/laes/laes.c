#include <stdlib.h>
#include <stdint.h>
#include <string.h>
#include <malloc.h>
#include "lua.h"
#include "lauxlib.h"
#include "aes.h"
#include "PKCS7.h"

typedef enum {
	Mode_ECB = 1,
	Mode_CBC = 2,
	Mode_CTR = 3,
} AES_Mode;

typedef struct {
	AES_Mode mode;
	struct AES_ctx ctx;
} AES;

static int lencrypt(lua_State *L) {
	AES *aes = lua_touserdata(L,1);
	luaL_argcheck(L,aes != NULL,1,"Need a aes object");
	size_t length = 0;
	const char *in = luaL_checklstring(L,2,&length);
	//PKCS
	PKCS7_Padding* pPaddingResult = addPadding(in, length, BLOCK_SIZE_128_BIT);
	if (pPaddingResult == NULL) {
		return luaL_argerror(L, 1, "input string's param");
	}
	length = pPaddingResult->dataLengthWithPadding;
	uint8_t* buf = pPaddingResult->dataWithPadding;
	if (length == 0 || length % 16 != 0) {
		freePaddingResult(pPaddingResult);
		return luaL_argerror(L,1,"input string's length must be divided by 16");
	}
	if (aes->mode == Mode_ECB) {
		if (length != 16) {
			freePaddingResult(pPaddingResult);
			return luaL_argerror(L,1,"ECB input string's length must be 16");
		}
		AES_ECB_encrypt(&aes->ctx,buf);
	} else if(aes->mode == Mode_CBC) {
		AES_CBC_encrypt_buffer(&aes->ctx,buf,length);
	} else if (aes->mode == Mode_CTR) {
		AES_CTR_xcrypt_buffer(&aes->ctx,buf,length);
	}
	lua_pushlstring(L,(const char*)buf,length);
	freePaddingResult(pPaddingResult);
	return 1;
}

static int ldecrypt(lua_State *L) {
	AES *aes = lua_touserdata(L,1);
	luaL_argcheck(L,aes != NULL,1,"Need a aes object");
	size_t length = 0;
	const char *in = luaL_checklstring(L,2,&length);
	if (length == 0 || length % 16 != 0) {
		return luaL_argerror(L,1,"input string's length must be divided by 16");
	}
	uint8_t *buf = (uint8_t*)malloc(length);
	memcpy(buf,in,length);
	if (aes->mode == Mode_ECB) {
		if (length != 16) {
			free(buf);
			return luaL_argerror(L,1,"ECB input string'slength must be 16");
		}
		AES_ECB_decrypt(&aes->ctx,buf);
	} else if(aes->mode == Mode_CBC) {
		AES_CBC_decrypt_buffer(&aes->ctx,buf,length);
	} else if (aes->mode == Mode_CTR) {
		AES_CTR_xcrypt_buffer(&aes->ctx,buf,length);
	}
	PKCS7_unPadding* pUnpaddingResult = removePadding(buf,length);
	if (pUnpaddingResult == NULL) {
		free(buf);
		return luaL_argerror(L, 1, "remove padding error");
	}
	lua_pushlstring(L, (const char*)pUnpaddingResult->dataWithoutPadding, pUnpaddingResult->dataLengthWithoutPadding);
	free(buf);
	freeUnPaddingResult(pUnpaddingResult);
	return 1;
}

static int lnew(lua_State *L) {
	int n = lua_gettop(L);
	if (n < 2) {
		luaL_error(L,"aes.new(mode,key,[iv])");
		return 0;
	}
	int mode = luaL_checkinteger(L,1);
	if (mode != Mode_ECB &&	mode != Mode_CBC &&	mode != Mode_CTR) {
		return luaL_argerror(L,1,"mode must be CBC|ECB|CTR");
	}
	size_t length = 0;
	const char* key = luaL_checklstring(L,2,&length);
	if (length != AES_KEYLEN) {
		luaL_error(L,"key length must be %d",AES_KEYLEN);
		return 0;
	}
	uint8_t *iv = NULL;
	if (n >= 3) {
		length = 0;
		const char *tmp = luaL_checklstring(L,3,&length);
		if (length != 16) {
			return luaL_argerror(L,3,"iv length must be 16");
		}
		iv = (uint8_t*)tmp;
	}
	AES *aes = (AES*)lua_newuserdata(L,sizeof(AES));
	aes->mode = mode;
	AES_init_ctx(&aes->ctx,(const uint8_t*)key);
	if (iv) {
		if (aes->mode == Mode_ECB) {
			luaL_error(L,"ECB donn't need iv");
			return 0;
		}
		AES_ctx_set_iv(&aes->ctx,iv);
	}
	return 1;
}

static void
aes_newlib(lua_State *L) {
	luaL_checkversion(L);
	luaL_Reg l[] = {
		{"new",lnew},
		{"encrypt",lencrypt},
		{"decrypt",ldecrypt},
		{NULL,NULL},
	};
	luaL_newlibtable(L,l);
	lua_pushinteger(L,Mode_CBC);
	lua_setfield(L,-2,"CBC");
	lua_pushinteger(L,Mode_ECB);
	lua_setfield(L,-2,"ECB");
	lua_pushinteger(L,Mode_CTR);
	lua_setfield(L,-2,"CTR");
	luaL_setfuncs(L,l,0);
}


#if defined(AES256) && (AES256 == 1)
LUAMOD_API int
luaopen_aes256(lua_State *L) {
	aes_newlib(L);
	return 1;
}
#elif defined(AES192) && (AES192 == 1)
LUAMOD_API int
luaopen_aes192(lua_State *L) {
	aes_newlib(L);
	return 1;
}
#else
LUAMOD_API int
luaopen_aes128(lua_State *L) {
	aes_newlib(L);
	return 1;
}
#endif
