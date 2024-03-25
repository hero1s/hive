#pragma once

#include "lmdb.h"
#include "lua_kit.h"

using namespace std;
using namespace luakit;

namespace llmdb {
    const uint16_t  max_key_size = 4096;

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
        int32_t commit_txn() {
            return mdb_txn_commit(_txn);
        }
        int32_t drop(const char* name, bool del = true) {
            return mdb_drop(_txn, _dbi, del ? 1 : 0);
        }
        int32_t quick_drop(const char* name, bool del = true) {
            int rc = begin_txn(name);
            if (rc != MDB_SUCCESS) return rc;
            rc = mdb_drop(_txn, _dbi, del ? 1 : 0);
            mdb_txn_commit(_txn);
            return rc;
        }
        int32_t begin_txn(const char* name) {
            int rc = mdb_txn_begin(_env, nullptr, 0, &_txn);
            if (rc != MDB_SUCCESS) return rc;
            return mdb_dbi_open(_txn, name, MDB_CREATE, &_dbi);
        }
        int32_t begin_rotxn(const char* name) {
            if (!_ro_txn) {
                int rc = mdb_txn_begin(_env, nullptr, MDB_RDONLY, &_ro_txn);
                if (rc != MDB_SUCCESS) return rc;
            }
            mdb_txn_reset(_ro_txn);
            int rc = mdb_txn_renew(_ro_txn);
            if (rc != MDB_SUCCESS) return rc;
            return mdb_dbi_open(_ro_txn, name, 0, &_dbi);
        }
        int put(lua_State* L) {
            MDB_val mkey, mval;
            read_key(L, 1, mkey);
            read_value(L, 2, mval);
            int rc = mdb_put(_txn, _dbi, &mkey, &mval, 0);
            lua_pushinteger(L, rc);
            return 1;
        }
        int quick_put(lua_State* L) {
            int rc = begin_txn(luaL_optstring(L, 3, nullptr));
            if (rc != MDB_SUCCESS) goto exit;
            MDB_val mkey, mval;
            read_key(L, 1, mkey);
            read_value(L, 2, mval);
            rc = mdb_put(_txn, _dbi, &mkey, &mval, 0);
            if (rc != MDB_SUCCESS) goto exit;
        exit:
            mdb_txn_commit(_txn);
            lua_pushinteger(L, rc);
            return 1;
        }
        int batch_put(lua_State* L) {
            luaL_checktype(L, 1, LUA_TTABLE);
            int rc = begin_txn(luaL_optstring(L, 2, nullptr));
            if (rc != MDB_SUCCESS) goto exit;
            lua_pushnil(L);
            MDB_val mkey, mval;
            while (lua_next(L, 1) != 0) {
                read_key(L, -2, mkey);
                read_value(L, -1, mval);
                lua_pop(L, 1);
                rc = mdb_put(_txn, _dbi, &mkey, &mval, 0);
                if (rc != MDB_SUCCESS) goto exit;
            }
        exit:
            mdb_txn_commit(_txn);
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
                return 2;
            }
            push_value(L, mval);
            lua_pushinteger(L, rc);
            return 2;
        }
        int quick_get(lua_State* L) {
            int rc = begin_rotxn(luaL_optstring(L, 2, nullptr));
            if (rc != MDB_SUCCESS) goto exit;
            MDB_val mkey, mval;
            read_key(L, 1, mkey);
            rc = mdb_get(_ro_txn, _dbi, &mkey, &mval);
            if (rc != MDB_SUCCESS) goto exit;
            push_value(L, mval);
            lua_pushinteger(L, rc);
            return 2;
        exit:
            lua_pushnil(L);
            lua_pushinteger(L, rc);
            return 2;
        }
        int batch_get(lua_State* L) {
            lua_createtable(L, 0, 4);
            luaL_checktype(L, 1, LUA_TTABLE);
            int rc = begin_rotxn(luaL_optstring(L, 2, nullptr));
            if (rc != MDB_SUCCESS) goto exit;
            lua_pushnil(L);
            MDB_val mkey, mval;
            while (lua_next(L, 1) != 0) {
                read_key(L, -1, mkey);
                rc = mdb_get(_ro_txn, _dbi, &mkey, &mval);
                if (rc == MDB_SUCCESS) {
                    push_value(L, mval);
                    lua_settable(L, 3);
                } else {
                    lua_pop(L, 1);
                    if (rc != MDB_NOTFOUND) goto exit;
                }
            }
        exit:
            lua_pushinteger(L, rc);
            return 2;
        }
        int del(lua_State* L) {
            int rc;
            MDB_val mkey;
            read_key(L, 1, mkey);
            if (lua_gettop(L) == 1) {
                rc = mdb_del(_txn, _dbi, &mkey, nullptr);
            } else {
                MDB_val mval;
                read_value(L, 2, mval);
                rc = mdb_del(_txn, _dbi, &mkey, &mval);
            }
            bool success = (rc == MDB_SUCCESS || rc == MDB_NOTFOUND);
            if (!success) mdb_txn_reset(_txn);
            lua_pushboolean(L, success);
            return 1;
        }
        int quick_del(lua_State* L) {
            int rc = begin_txn(luaL_optstring(L, 2, nullptr));
            if (rc != MDB_SUCCESS) goto exit;
            MDB_val mkey;
            read_key(L, 1, mkey);
            if (lua_type(L, 3) == LUA_TNONE) {
                rc = mdb_del(_txn, _dbi, &mkey, nullptr);
            } else {
                MDB_val mval;
                read_value(L, 3, mval);
                rc = mdb_del(_txn, _dbi, &mkey, &mval);
            }
        exit:
            mdb_txn_commit(_txn);
            lua_pushinteger(L, rc);
            return 1;
        }
        int batch_del(lua_State* L) {
            MDB_val mkey;
            luaL_checktype(L, 1, LUA_TTABLE);
            int rc = begin_txn(luaL_optstring(L, 2, nullptr));
            if (rc != MDB_SUCCESS) goto exit;
            lua_pushnil(L);
            while (lua_next(L, 1) != 0) {
                read_key(L, -1, mkey);
                lua_pop(L, 1);
                rc = mdb_del(_txn, _dbi, &mkey, nullptr);
                if ((rc != MDB_SUCCESS && rc != MDB_NOTFOUND)) goto exit;
            }
        exit:
            mdb_txn_commit(_txn);
            lua_pushinteger(L, rc);
            return 1;
        }
        int32_t cursor_open(const char* name) {
            int rc = begin_txn(name);
            if (rc != MDB_SUCCESS) return rc;
            return mdb_cursor_open(_txn, _dbi, &_cur);
        }
        void cursor_close() {
            mdb_cursor_close(_cur);
            mdb_txn_commit(_txn);
        }
        int cursor_put(lua_State* L) {
            MDB_val mkey, mval;
            read_key(L, 1, mkey);
            read_value(L, 2, mval);
            int flag = luaL_optinteger(L, 3, 0);
            int rc = mdb_cursor_put(_cur, &mkey, &mval, (MDB_cursor_op)flag);
            lua_pushinteger(L, rc);
            return 1;
        }
        int cursor_get(lua_State* L) {
            MDB_val mkey, mval;
            read_key(L, 1, mkey);
            int flag = luaL_optinteger(L, 2, 0);
            int rc = mdb_cursor_get(_cur, &mkey, &mval, (MDB_cursor_op)flag);
            if (rc != MDB_SUCCESS) {
                lua_pushinteger(L, rc);
                return 1;
            }
            lua_pushinteger(L, rc);
            push_value(L, mkey);
            push_value(L, mval);
            return 3;
        }
        int32_t cursor_del(int flag) {
            return mdb_cursor_del(_cur, flag);
        }

    protected:
        void read_key(lua_State* L, int idx, MDB_val& val) {
            int type = lua_type(L, idx);
            if (m_jcodec) {
                switch (type) {
                case LUA_TNIL:
                    val.mv_size = 0;
                    break;
                case LUA_TNUMBER: {
                        size_t len;
                        char* body = (char*)m_jcodec->encode(L, idx, &len);
                        strncpy(m_keys, body, len);
                        val = MDB_val{ len, (void*)m_keys };
                    }
                    break;
                case LUA_TSTRING: {
                        size_t len;
                        const char* body = lua_tolstring(L, idx, &len);
                        if (len >= max_key_size) luaL_error(L, "lmdb read key size %d ge 4096!", len);
                        val = MDB_val{ len, (void*)body };
                    }
                    break;
                default:
                    luaL_error(L, "lmdb read key type %s not suppert!", lua_typename(L, idx));
                    break;
                }
                return;
            }
            if (type != LUA_TSTRING) luaL_error(L, "lmdb read key type %s not suppert!", lua_typename(L, idx));
            size_t len;
            const char* data = lua_tolstring(L, idx, &len);
            val = MDB_val{ len, (void*)data };
        }

        void read_value(lua_State* L, int idx, MDB_val& val) {
            int type = lua_type(L, idx);
            if (m_jcodec) {
                switch (type) {
                case LUA_TNIL:
                case LUA_TTABLE:
                case LUA_TNUMBER:
                case LUA_TSTRING:
                case LUA_TBOOLEAN: {
                        size_t len;
                        char* body = (char*)m_jcodec->encode(L, idx, &len);
                        val = MDB_val{ len, (void*)body };
                    }
                    break;
                default:
                    luaL_error(L, "lmdb read value type %s not suppert!", lua_typename(L, idx));
                    break;
                }
                return;
            }
            switch (type) {
            case LUA_TNUMBER:
            case LUA_TSTRING: {
                    size_t len;
                    const char* data = lua_tolstring(L, idx, &len);
                    val = MDB_val{ len, (void*)data };
                }
                break;
            default:
                luaL_error(L, "lmdb read value type %d not suppert!", type);
                break;
            }
        }

        void push_value(lua_State* L, MDB_val& val) {
            if (m_jcodec) {
                try {
                    m_jcodec->decode(L, (uint8_t*)val.mv_data, val.mv_size);
                } catch (...) {
                    lua_pushlstring(L, (const char*)val.mv_data, val.mv_size);
                }
                return;
            }
            std::string buf = { (const char*)val.mv_data, val.mv_size };
            if (lua_stringtonumber(L, buf.c_str()) == 0) {
                lua_pushlstring(L, (const char*)buf.c_str(), buf.size());
            }
        }

    protected:
        MDB_dbi _dbi = 0;
        MDB_env* _env = nullptr;
        MDB_txn* _txn = nullptr;
        MDB_txn* _ro_txn = nullptr;
        MDB_cursor* _cur = nullptr;
        codec_base* m_jcodec = nullptr;
        char m_keys[max_key_size];
    };
}
