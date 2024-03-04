#pragma once

#include "lmdb.h"
#include "lua_kit.h"

using namespace std;
using namespace luakit;

#ifdef _MSC_VER
#define strncasecmp _strnicmp
#endif

namespace llmdb {
    class mdb_driver {
    public:
        mdb_driver(MDB_env* env) : _env{env} {}
        ~mdb_driver() { close(); }

        void close() {
            if (_env) mdb_env_close(_env);
            _env = nullptr;
        }

        void set_codec(codec_base* codec) {
            m_jcodec = codec;
        }

        int32_t sync(bool force = true) {
            return mdb_env_sync(_env, force);
        }
        int32_t open(const char* path, uint32_t flags, int mode) {
            return mdb_env_open(_env, path, flags, mode);
        }
        int32_t set_flags(uint32_t flags, bool onoff = true) {
            return mdb_env_set_flags(_env, flags, onoff ? 1: 0);
        }
        int32_t set_mapsize(size_t size) {
            return mdb_env_set_mapsize(_env, size);
        }
        int32_t set_max_dbs(size_t count) {
            return mdb_env_set_maxdbs(_env, count);
        }
        int32_t set_max_readers(uint32_t count) {
            return mdb_env_set_maxreaders(_env, count);
        }
        void abort_txn() {
            mdb_txn_abort(_txn);
        }
        void reset_txn() {
            mdb_txn_reset(_txn);
        }
        int32_t renew_txn() {
            return mdb_txn_renew(_txn);
        }
        int32_t commit_txn() {
            return mdb_txn_commit(_txn);
        }
        int32_t drop(bool del = true) {
            if (_dbi > 0) {
                int rc = mdb_drop(_txn, _dbi, del ? 1 : 0);
                if (rc != MDB_SUCCESS) mdb_txn_reset(_txn);
                return rc;
            }
            return MDB_SUCCESS;
        }
        int32_t begin_txn(const char* name, int flags) {
            int rc = mdb_txn_begin(_env, nullptr, flags, &_txn);
            if (rc != MDB_SUCCESS) return rc;
            rc = mdb_dbi_open(_txn, name, flags, &_dbi);
            if (rc != MDB_SUCCESS) mdb_txn_abort(_txn);
            return rc;
        }
        int put(lua_State* L) {
            MDB_val mkey, mval;
            read_key(L, 1, mkey);
            read_value(L, 2, mval);
            int rc = mdb_put(_txn, _dbi, &mkey, &mval, 0);
            if (rc != MDB_SUCCESS) {
                mdb_txn_reset(_txn);
                lua_pushinteger(L, rc);
                return 1;
            }
            lua_pushinteger(L, rc);
            return 1;
        }
        int easy_put(lua_State* L) {
            const char* name = luaL_optstring(L, 3, nullptr);
            int rc = mdb_txn_begin(_env, nullptr, 0, &_txn);
            if (rc != MDB_SUCCESS) goto exit;
            rc = mdb_dbi_open(_txn, name, MDB_CREATE, &_dbi);
            if (rc != MDB_SUCCESS) goto exit;
            MDB_val mkey, mval;
            read_key(L, 1, mkey);
            read_value(L, 2, mval);
            rc = mdb_put(_txn, _dbi, &mkey, &mval, 0);
            if (rc != MDB_SUCCESS) goto exit;
            rc = mdb_txn_commit(_txn);
            if (rc != MDB_SUCCESS) goto exit;
            lua_pushinteger(L, rc);
            return 1;
        exit:
            mdb_txn_reset(_txn);
            lua_pushinteger(L, rc);
            return 1;
        }
        int get(lua_State* L) {
            MDB_val mkey, mval;
            read_key(L, 1, mkey);
            int rc = mdb_get(_txn, _dbi, &mkey, &mval);
            if (rc != MDB_SUCCESS) {
                lua_pushnil(L);
                lua_pushinteger(L, rc);
                mdb_txn_reset(_txn);
                return 2;
            }
            push_value(L, mval);
            lua_pushinteger(L, rc);
            return 2;
        }
        int easy_get(lua_State* L) {
            const char* name = luaL_optstring(L, 3, nullptr);
            int rc = mdb_txn_begin(_env, nullptr, MDB_RDONLY, &_txn);
            if (rc != MDB_SUCCESS) goto exit;
            rc = mdb_dbi_open(_txn, name, MDB_CREATE, &_dbi);
            if (rc != MDB_SUCCESS) goto exit;
            MDB_val mkey, mval;
            read_key(L, 1, mkey);
            rc = mdb_get(_txn, _dbi, &mkey, &mval);
            if (rc != MDB_SUCCESS) goto exit;
            rc = mdb_txn_commit(_txn);
            if (rc != MDB_SUCCESS) goto exit;
            push_value(L, mval);
            lua_pushinteger(L, rc);
            return 2;
        exit:
            lua_pushnil(L);
            lua_pushinteger(L, rc);
            mdb_txn_reset(_txn);
            return 2;
        }
        int del(lua_State* L) {
            MDB_val mkey;
            read_key(L, 1, mkey);
            if (lua_gettop(L) == 1) {
                int rc = mdb_del(_txn, _dbi, &mkey, nullptr);
                if (rc != MDB_SUCCESS) mdb_txn_reset(_txn);
                lua_pushboolean(L, rc != MDB_SUCCESS);
                return 1;
            }
            MDB_val mval;
            read_value(L, 2, mval);
            int rc = mdb_del(_txn, _dbi, &mkey, &mval);
            if (rc != MDB_SUCCESS) mdb_txn_reset(_txn);
            lua_pushboolean(L, rc != MDB_SUCCESS);
            return 1;
        }
        int easy_del(lua_State* L) {
            const char* name = luaL_optstring(L, 3, nullptr);
            int rc = mdb_txn_begin(_env, nullptr, 0, &_txn);
            if (rc != MDB_SUCCESS) goto exit;
            rc = mdb_dbi_open(_txn, name, MDB_CREATE, &_dbi);
            if (rc != MDB_SUCCESS) goto exit;
            MDB_val mkey;
            read_key(L, 1, mkey);
            if (lua_gettop(L) == 1) {
                rc = mdb_del(_txn, _dbi, &mkey, nullptr);
                if (rc != MDB_SUCCESS) goto exit;
            } else {
                MDB_val mval;
                read_value(L, 2, mval);
                rc = mdb_del(_txn, _dbi, &mkey, &mval);
                if (rc != MDB_SUCCESS) goto exit;
            }
            rc = mdb_txn_commit(_txn);
            if (rc != MDB_SUCCESS) goto exit;
            lua_pushboolean(L, true);
            return 1;
        exit:
            lua_pushboolean(L, false);
            mdb_txn_reset(_txn);
            return 1;
        }
        int32_t cursor_open() {
            return mdb_cursor_open(_txn, _dbi, &_cur);
        }
        void cursor_close() {
            mdb_cursor_close(_cur);
        }
        int cursor_put(lua_State* L) {
            MDB_val mkey, mval;
            read_key(L, 1, mkey);
            read_value(L, 2, mval);
            int flag = luaL_optinteger(L, 3, 0);
            int rc = mdb_cursor_put(_cur, &mkey, &mval, (MDB_cursor_op)flag);
            if (rc != MDB_SUCCESS) {
                mdb_txn_reset(_txn);
                lua_pushinteger(L, rc);
                return 1;
            }
            lua_pushinteger(L, rc);
            return 1;
        }
        int cursor_get(lua_State* L) {
            MDB_val mkey, mval;
            read_key(L, 1, mkey);
            int flag = luaL_optinteger(L, 2, 0);
            int rc = mdb_cursor_get(_cur, &mkey, &mval, (MDB_cursor_op)flag);
            if (rc != MDB_SUCCESS) {
                mdb_txn_reset(_txn);
                lua_pushnil(L);
                lua_pushnil(L);
                lua_pushinteger(L, rc);
                return 3;
            }
            push_value(L, mval);
            push_value(L, mkey);
            lua_pushinteger(L, rc);
            return 3;
        }
        bool cursor_del(int flag) {
            int rc = mdb_cursor_del(_cur, flag);
            if (rc != MDB_SUCCESS) mdb_txn_reset(_txn);
            return rc != MDB_SUCCESS;
        }

    protected:
        void read_key(lua_State* L, int idx, MDB_val& val) {
            int type = lua_type(L, idx);
            switch (type) {
            case LUA_TNUMBER: {
                    auto cval = lua_isinteger(L, idx) ? to_string(lua_tointeger(L, idx)) : to_string(lua_tonumber(L, idx));
                    val = { cval.size(), (void*)cval.c_str() };
                }
                break;
            case LUA_TSTRING: {
                    size_t len;
                    const char* data = lua_tolstring(L, idx, &len);
                    val = { len, (void*)data };
                }
                break;
            default:
                luaL_error(L, "lmdb read key type %d not suppert!", type);
                break;
            }
        }

        void read_value(lua_State* L, int idx, MDB_val& val) {
            int type = lua_type(L, idx);
            switch (type) {
            case LUA_TNIL:
                val = MDB_val { 3, (void*)"nil" };
                break;
            case LUA_TBOOLEAN: {
                    auto cval = (lua_toboolean(L, idx) == 1) ? to_string(true) : to_string(false);
                    val = MDB_val{ cval.size(), (void*)cval.c_str() };
                }
                break;
            case LUA_TNUMBER: {
                    auto cval = lua_isinteger(L, idx) ? to_string(lua_tointeger(L, idx)) : to_string(lua_tonumber(L, idx));
                    val = MDB_val{ cval.size(), (void*)cval.c_str() };
                }
                break;
            case LUA_TSTRING: {
                    size_t len;
                    const char* data = lua_tolstring(L, idx, &len);
                    val = MDB_val{ len, (void*)data };
                }
                break;
            case LUA_TTABLE: {
                    if (!m_jcodec) {
                        luaL_error(L, "lmdb read table value not suppert!");
                    }
                    size_t len;
                    char* body = (char*)m_jcodec->encode(L, idx, &len);
                    val = MDB_val{ len, (void*)body };
                };
                break;
            default:
                luaL_error(L, "lmdb read value type %d not suppert!", type);
                break;
            }
        }

        void push_value(lua_State* L, MDB_val& val) {
            if (m_jcodec && !strncasecmp((const char*)val.mv_data, "{", 1)) {
                try {
                    m_jcodec->decode(L, (uint8_t*)val.mv_data, val.mv_size);
                    return;
                } catch (...) {
                    lua_pushlstring(L, (const char*)val.mv_data, val.mv_size);
                }
            }
            lua_pushlstring(L, (const char*)val.mv_data, val.mv_size);
        }

    protected:
        MDB_dbi _dbi = 0;
        MDB_env* _env = nullptr;
        MDB_txn* _txn = nullptr;
        MDB_cursor* _cur = nullptr;
        codec_base* m_jcodec = nullptr;
    };
}
