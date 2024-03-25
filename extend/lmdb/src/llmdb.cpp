#define LUA_LIB

#include "llmdb.h"

namespace llmdb {
    mdb_driver* create_criver(lua_State* L) {
        MDB_env* handle = nullptr;
        int rc = mdb_env_create(&handle);
        if (rc != MDB_SUCCESS) {
            luaL_error(L, "mdb env create failed!");
        }
        return new mdb_driver(handle);
    }

    luakit::lua_table open_lmdb(lua_State* L) {
        luakit::kit_state kit_state(L);
        auto lmdb = kit_state.new_table();
        lmdb.set_function("create", create_criver);
        kit_state.new_class<mdb_driver>(
            "get", &mdb_driver::get,
            "put", &mdb_driver::put,
            "del", &mdb_driver::del,
            "drop", &mdb_driver::drop,
            "sync", &mdb_driver::sync,
            "open", &mdb_driver::open,
            "close", &mdb_driver::close,
            "quick_put", &mdb_driver::quick_put,
            "quick_get", &mdb_driver::quick_get,
            "quick_del", &mdb_driver::quick_del,
            "batch_put", &mdb_driver::batch_put,
            "batch_get", &mdb_driver::batch_get,
            "batch_del", &mdb_driver::batch_del,
            "set_flags", &mdb_driver::set_flags,
            "begin_txn", &mdb_driver::begin_txn,
            "abort_txn", &mdb_driver::abort_txn,
            "reset_txn", &mdb_driver::reset_txn,
            "quick_drop", &mdb_driver::quick_drop,
            "commit_txn", &mdb_driver::commit_txn,
            "cursor_put", &mdb_driver::cursor_put,
            "cursor_get", &mdb_driver::cursor_get,
            "cursor_del", &mdb_driver::cursor_del,
            "cursor_open", &mdb_driver::cursor_open,
            "cursor_close", &mdb_driver::cursor_close,
            "set_max_readers", &mdb_driver::set_max_readers,
            "set_max_dbs", &mdb_driver::set_max_dbs,
            "set_mapsize", &mdb_driver::set_mapsize,
            "set_codec", &mdb_driver::set_codec
        );
        lmdb.new_enum("MDB_ENV_FLAG",
            "MDB_FIXEDMAP", MDB_FIXEDMAP,
            "MDB_NOSUBDIR", MDB_NOSUBDIR,
            "MDB_NOSYNC", MDB_NOSYNC,
            "MDB_RDONLY", MDB_RDONLY,
            "MDB_NOMETASYNC", MDB_NOMETASYNC,
            "MDB_WRITEMAP", MDB_WRITEMAP,
            "MDB_MAPASYNC", MDB_MAPASYNC,
            "MDB_NOTLS", MDB_NOTLS,
            "MDB_NOLOCK", MDB_NOLOCK,
            "MDB_NORDAHEAD", MDB_NORDAHEAD,
            "MDB_NOMEMINIT", MDB_NOMEMINIT,
            "MDB_PREVSNAPSHOT", MDB_PREVSNAPSHOT
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
        lmdb.new_enum("MDB_DBI_FLAG",
            "MDB_REVERSEKEY", MDB_REVERSEKEY,
            "MDB_DUPSORT", MDB_DUPSORT,
            "MDB_INTEGERKEY", MDB_INTEGERKEY,
            "MDB_DUPFIXED", MDB_DUPFIXED,
            "MDB_INTEGERDUP", MDB_INTEGERDUP,
            "MDB_REVERSEDUP", MDB_REVERSEDUP,
            "MDB_CREATE", MDB_CREATE
        );
        lmdb.new_enum("MDB_CUR_OP",
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
        lmdb.new_enum("MDB_WRITE_FLAG",
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