#include <stdlib.h>
#include <stdint.h>
#include "lua.h"
#include "lauxlib.h"

typedef struct _TableNode {
    uint32_t key;
    int next;

    char flag; // 0: empty, 'n': non-terminator, 'o': terminator
    void* value;
} TableNode;

typedef struct _Table {
    int capacity;

    TableNode* node;
    TableNode* lastfree;
} Table;

Table *g_dict = NULL;

inline static void
initnode(TableNode *node) {
    node->next = -1;

    node->flag = 0;
    node->value = NULL;
}

inline static int
tisnil(TableNode* node) {
    return node->flag == 0;
}

inline static TableNode*
tnode(Table *t, int index) {
    return t->node + index;
}

inline static int
tindex(Table *t, TableNode *node) {
    return node - t->node;
}

static TableNode*
mainposition(Table *t, uint32_t key) {
    return &t->node[(key & (t->capacity -1))];
}

static TableNode*
getfreenode(Table *t) {
    while(t->lastfree >= t->node) {
        if(tisnil(t->lastfree)) {
            return t->lastfree;
        }
        t->lastfree--;
    }
    return NULL;
}

static TableNode*
table_newkey(Table *t, uint32_t key);

static void
table_expand(Table *t) {
    int capacity = t->capacity;
    TableNode *node = t->node;

    // init new table
    t->capacity = t->capacity * 2;
    t->node = calloc(t->capacity, sizeof(TableNode));
    int i;
    for(i=0; i<t->capacity; i++) {
        initnode(t->node + i);
    }
    t->lastfree = t->node + (t->capacity - 1);

    // reinsert old node
    for(i=0; i< capacity; i++) {
        TableNode *old = node + i;
        if(tisnil(old)) {
            continue;
        }
        TableNode *new = table_newkey(t, old->key);
        new->flag = old->flag;
        new->value = old->value;
    }
    // free old node
    free(node);
}

/*
** inserts a new key into a hash table; first, check whether key's main
** position is free. If not, check whether colliding node is in its main
** position or not: if it is not, move colliding node to an empty place and
** put new key in its main position; otherwise (colliding node is in its main
** position), new key goes to an empty position.
*/
static TableNode*
table_newkey(Table *t, uint32_t key) {
    TableNode *mp = mainposition(t, key);
    if(!tisnil(mp)) {
        TableNode *n = getfreenode(t);
        if(n == NULL) {
            table_expand(t);
            return table_newkey(t, key);
        }
        TableNode *othern = mainposition(t, mp->key);
        if (othern != mp) {
            int mindex = tindex(t, mp);
            while(othern->next != mindex) {
                othern = tnode(t, othern->next);
            }
            othern->next = tindex(t, n);
            *n = *mp;
            initnode(mp);
        } else {
            n->next = mp->next;
            mp->next = tindex(t, n);
            mp = n;
        }
    }
    mp->key = key;
    mp->flag = 'n';
    return mp;
}

static TableNode*
table_get(Table *t, uint32_t key) {
    TableNode *n = mainposition(t, key);
    while(!tisnil(n)) {
        if(n->key == key) {
            return n;
        }
        if(n->next < 0) {
            break;
        }
        n = tnode(t, n->next);
    }
    return NULL;
}

static TableNode*
table_insert(Table *t, uint32_t key) {
    TableNode *node = table_get(t, key);
    if(node) {
        return node;
    }
    return table_newkey(t, key);
}

static Table*
table_new() {
    Table *t = malloc(sizeof(Table));
    t->capacity = 1;

    t->node = malloc(sizeof(TableNode));
    initnode(t->node);
    t->lastfree = t->node;
    return t;
}

// deconstruct dictinory tree
static void
_dict_close(Table *t) {
    if(t == NULL) {
        return;
    }
    int i = 0;
    for(i=0; i<t->capacity; i++) {
        TableNode *node = t->node + i;
        if(node->flag != 0) {
            _dict_close(node->value);
        }
    }
    free(t->node);
    free(t);
}

static void
_dict_dump(Table *t, int indent) {
    if(t == NULL) {
        return;
    }
    int i = 0;
    for(i=0; i<t->capacity; i++) {
        TableNode *node = t->node + i;
        printf("%*s", indent, " ");
        if(node->flag != 0) {
            printf("0x%x\n", node->key);
            _dict_dump(node->value, indent + 8);
        } else {
            printf("%s\n", "nil");
        }
    }
}

static int
_dict_insert(lua_State *L, Table* dict) {
    if(!lua_istable(L, -1)) {
        return 0;
    }

    size_t len = lua_rawlen(L, -1);
    size_t i;
    uint32_t rune;
    TableNode *node = NULL;
    for(i=1; i<=len; i++) {
        lua_rawgeti(L, -1, i);
        int isnum;
        rune = (uint32_t)lua_tointegerx(L, -1, &isnum);
        lua_pop(L, 1);

        if(!isnum) {
            return 0;
        }

        Table *tmp;
        if(node == NULL) {
            tmp = dict;
        } else {
            if(node->value == NULL) {
                node->value = table_new();
            } 
            tmp = node->value;
        }
        node = table_insert(tmp, rune);
    }
    if(node) {
        node->flag = 'o';
    }
    return 1;
}

static int
dict_open(lua_State *L) {
    luaL_checktype(L, 1, LUA_TTABLE);

    Table *dict = table_new();
    size_t len = lua_rawlen(L,1);
    size_t i;
    for(i=1;i<=len;i++) {
        lua_rawgeti(L, 1, i);
        if(!_dict_insert(L, dict)) {
            _dict_close(dict);
            return luaL_error(L, "illegal parameters in table index %d", i);
        }
        lua_pop(L, 1);
    }

    //_dict_dump(dict, 0);
    // don't close old g_dict, avoid crash
    g_dict = dict;
    return 0;
}

static int
dict_filter(lua_State *L) {
    if(!g_dict) {
        return luaL_error(L, "need open first");
    }

    Table* dict = g_dict;
    luaL_checktype(L, 1, LUA_TTABLE);

    size_t len = lua_rawlen(L,1);
    size_t i,j;
    int flag = 0;
    for(i=1;i<=len;) {
        TableNode *node = NULL;
        int step = 0;
        for(j=i;j<=len;j++) {
            lua_rawgeti(L, 1, j);
            uint32_t rune = (uint32_t) lua_tointeger(L, -1);
            lua_pop(L, 1);

            if(node == NULL) {
                node = table_get(dict, rune);
            } else {
                node = table_get(node->value, rune);
            }

            if(node && node->flag == 'o') step = j - i + 1;
            if(!(node && node->value)) break;
        }
        if(step > 0) {
            for(j=0;j<step;j++) {
                lua_pushinteger(L, '*');
                lua_rawseti(L, 1, i+j);
            }
            flag = 1;
            i = i + step;
        } else {
            i++;
        }
    }
    lua_pushboolean(L, flag);
    return 1;
}

/*
--------------------------utf8格式操作-------------------------------------------------------
*/
inline static int
_steps(uint8_t c) {
    if (c < 0x80) return 1;
    if (c < 0xc0) return 0;
    if (c < 0xe0) return 2;
    if (c < 0xf0) return 3;
    if (c < 0xf8) return 4;
    return 0;
}

inline static int
_bytes(uint32_t rune) {
    if (rune < 0x80) return 1;
    if (rune < 0x800) return 2;
    if (rune < 0x10000) return 3;
    if (rune < 0x110000) return 4;
    return 0;
}

inline static uint32_t
_decode(const char* str, int i, int step) {
    uint8_t c = str[i];
    uint32_t v = c & (0xff >> step);
    int j = 1;
    for (; j < step; j++) {
        v = v << 6;
        v = v | (str[i + j] & 0x3f);
    }
    return v;
}

#define FILL_LOW_BITS(str, pos, rune) str[pos] = (rune & 0x3f) | 0x80; rune >>= 6;

inline static uint8_t*
_encode(uint32_t rune, int bytes, uint8_t* str) {
    if (bytes == 1) {
        str[0] = rune & 0x7f;
    }
    else if (bytes == 2) {
        FILL_LOW_BITS(str, 1, rune)
            str[0] = rune | 0xc0;
    }
    else if (bytes == 3) {
        FILL_LOW_BITS(str, 2, rune)
            FILL_LOW_BITS(str, 1, rune)
            str[0] = rune | 0xe0;
    }
    else {
        FILL_LOW_BITS(str, 3, rune)
            FILL_LOW_BITS(str, 2, rune)
            FILL_LOW_BITS(str, 1, rune)
            str[0] = rune | 0xf0;
    }
    return str + bytes;
}

static int
_toutf32(lua_State* L) {
    size_t len;
    const char* str = luaL_checklstring(L, 1, &len);
    luaL_checktype(L, 2, LUA_TTABLE);

    int count = 0;

    int i, step;
    uint8_t c;
    for (i = 0; i < len;) {
        c = str[i];
        step = _steps(c);
        if (step == 0 || len < i + step) {
            count = -1;
            break;
        }
        lua_pushinteger(L, _decode(str, i, step));
        count = count + 1;
        lua_rawseti(L, 2, count);

        i = i + step;
    }

    if (count < 0) {
        return 0;
    }
    lua_pushinteger(L, count);
    return 1;
}

static int
_toutf8(lua_State* L) {
    luaL_checktype(L, 1, LUA_TTABLE);

    size_t sz = 0;
    size_t len = lua_rawlen(L, 1);
    size_t i;
    for (i = 1; i <= len; i++) {
        lua_rawgeti(L, 1, i);
        int isnum;
        uint32_t rune = (uint32_t)lua_tointegerx(L, -1, &isnum);
        lua_pop(L, 1);

        if (!isnum) {
            return 0;
        }
        int bytes = _bytes(rune);
        if (!bytes) {
            return 0;
        }
        sz += bytes;
    }

    uint8_t* str = lua_newuserdata(L, sz);
    uint8_t* tmp = str;
    for (i = 1; i <= len; i++) {
        lua_rawgeti(L, 1, i);
        uint32_t rune = lua_tointeger(L, -1);
        lua_pop(L, 1);

        int bytes = _bytes(rune);
        tmp = _encode(rune, bytes, tmp);
    }

    lua_pushlstring(L, (char*)str, sz);
    return 1;
}

static int
_len(lua_State* L) {
    size_t len;
    const char* str = luaL_checklstring(L, 1, &len);

    int count = 0;
    int i, step;
    uint8_t c;
    for (i = 0; i < len;) {
        c = str[i];
        step = _steps(c);
        i = i + step;
        if (!step || len < i) {
            count = -1;
            break;
        }
        count = count + 1;
    }
    if (count < 0) {
        return 0;
    }
    lua_pushinteger(L, count);
    return 1;
}
/*
--------------------------utf8格式操作-------------------------------------------------------
*/

int LUAMOD_API luaopen_lcrab(lua_State *L) {
	luaL_checkversion(L);

	luaL_Reg l[] = {
		{"open", dict_open},
		{"filter", dict_filter},

		{"len", _len},
		{"toutf32", _toutf32},
		{"toutf8", _toutf8},
		{NULL, NULL}
	};

	luaL_newlib(L, l);
	return 1;
}


