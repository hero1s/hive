#define LUA_LIB

#include "llmdb.h"
#include "lua_kit.h"

namespace llmdb {
    mdb_env* env_create(lua_State* L) {
        MDB_env* handle = nullptr;
        int rc = mdb_env_create(&handle);
        if (rc != MDB_SUCCESS) {
            luaL_error(L, "mdb env create failed!");
        }
        return new mdb_env(handle);
    }

    luakit::lua_table open_lmdb(lua_State* L) {
        luakit::kit_state kit_state(L);
        auto lmdb = kit_state.new_table();
        lmdb.set_function("create_env", env_create);
        kit_state.new_class<mdb_env>(
            "get", &mdb_env::get,
            "put", &mdb_env::put,
            "del", &mdb_env::del,
            "drop", &mdb_env::drop,
            "sync", &mdb_env::sync,
            "open", &mdb_env::open,
            "begin", &mdb_env::begin,
            "commit", &mdb_env::commit,
            "txn_id", &mdb_env::txn_id,
            "txn_abort", &mdb_env::txn_abort,
            "txn_reset", &mdb_env::txn_reset,
            "set_flags", &mdb_env::set_flags,
            "cursor_put", &mdb_env::cursor_put,
            "cursor_get", &mdb_env::cursor_get,
            "cursor_del", &mdb_env::cursor_del,
            "cursor_open", &mdb_env::cursor_open,
            "set_max_dbs", &mdb_env::set_max_dbs,
            "set_mapsize", &mdb_env::set_mapsize,
            "set_max_readers", &mdb_env::set_max_readers
        );
        lmdb.new_enum("MDB_CODE",
            "MDB_SUCCESS", MDB_SUCCESS,
            "MDB_KEYEXIST", MDB_KEYEXIST,
            "MDB_NOTFOUND", MDB_NOTFOUND,
            "MDB_PAGE_NOTFOUND", MDB_PAGE_NOTFOUND,
            "MDB_CORRUPTED", MDB_CORRUPTED,
            "MDB_PANIC", MDB_PANIC,
            "MDB_VERSION_MISMATCH", MDB_VERSION_MISMATCH,
            "MDB_INVALID", MDB_INVALID,
            "MDB_MAP_FULL", MDB_MAP_FULL,
            "MDB_DBS_FULL", MDB_DBS_FULL,
            "MDB_READERS_FULL", MDB_READERS_FULL,
            "MDB_TLS_FULL", MDB_TLS_FULL,
            "MDB_TXN_FULL", MDB_TXN_FULL,
            "MDB_CURSOR_FULL", MDB_CURSOR_FULL,
            "MDB_PAGE_FULL", MDB_PAGE_FULL,
            "MDB_MAP_RESIZED", MDB_MAP_RESIZED,
            "MDB_INCOMPATIBLE", MDB_INCOMPATIBLE,
            "MDB_BAD_RSLOT", MDB_BAD_RSLOT,
            "MDB_BAD_TXN", MDB_BAD_TXN,
            "MDB_BAD_VALSIZE", MDB_BAD_VALSIZE,
            "MDB_BAD_DBI", MDB_BAD_DBI,
            "MDB_PROBLEM", MDB_PROBLEM,
            "MDB_LAST_ERRCODE", MDB_LAST_ERRCODE
        );
        lmdb.new_enum("MDBI_FLAG",
            "MDB_REVERSEKEY", MDB_REVERSEKEY,
            "MDB_DUPSORT", MDB_DUPSORT,
            "MDB_INTEGERKEY", MDB_INTEGERKEY,
            "MDB_DUPFIXED", MDB_DUPFIXED,
            "MDB_INTEGERDUP", MDB_INTEGERDUP,
            "MDB_REVERSEDUP", MDB_REVERSEDUP,
            "MDB_CREATE", MDB_CREATE
        );
        lmdb.new_enum("MDB_CUROP",
            "MDB_FIRST", MDB_FIRST,
            "MDB_FIRST_DUP", MDB_FIRST_DUP,
            "MDB_GET_BOTH", MDB_GET_BOTH,
            "MDB_GET_BOTH_RANGE", MDB_GET_BOTH_RANGE,
            "MDB_GET_CURRENT", MDB_GET_CURRENT,
            "MDB_GET_MULTIPLE", MDB_GET_MULTIPLE,
            "MDB_LAST", MDB_LAST,
            "MDB_LAST_DUP", MDB_LAST_DUP,
            "MDB_NEXT", MDB_NEXT,
            "MDB_NEXT_DUP", MDB_NEXT_DUP,
            "MDB_NEXT_MULTIPLE", MDB_NEXT_MULTIPLE,
            "MDB_NEXT_NODUP", MDB_NEXT_NODUP,
            "MDB_PREV", MDB_PREV,
            "MDB_PREV_DUP", MDB_PREV_DUP,
            "MDB_PREV_NODUP", MDB_PREV_NODUP,
            "MDB_SET", MDB_SET,
            "MDB_SET_KEY", MDB_SET_KEY,
            "MDB_SET_RANGE", MDB_SET_RANGE,
            "MDB_PREV_MULTIPLE", MDB_PREV_MULTIPLE
        );
        lmdb.new_enum("MDB_WFLAG",
            "MDB_NOOVERWRITE", MDB_NOOVERWRITE,
            "MDB_NODUPDATA", MDB_NODUPDATA,
            "MDB_CURRENT", MDB_CURRENT,
            "MDB_RESERVE", MDB_RESERVE,
            "MDB_APPEND", MDB_APPEND,
            "MDB_APPENDDUP", MDB_APPENDDUP,
            "MDB_MULTIPLE", MDB_MULTIPLE
        );
        return lmdb;
    }
}

extern "C" {
    LUALIB_API int luaopen_lmdb(lua_State* L) {
        auto lmdb = llmdb::open_lmdb(L);
        return lmdb.push_stack();
    }
}