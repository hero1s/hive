#pragma once

#include "lmdb.h"
#include "lua_kit.h"

using namespace std;
using namespace luakit;

namespace llmdb {
    class mdb_env {
    public:
        mdb_env(MDB_env* env) : _env{env} {}
        ~mdb_env() { close(); }

        void close() {
            if (_env) mdb_env_close(_env);
            _env = nullptr;
        }

        int32_t sync(bool force = true) { return mdb_env_sync(_env, force); }
        int32_t open(const char* path, uint32_t flags, int mode) { return mdb_env_open(_env, path, flags, mode); }
        int32_t set_flags(uint32_t flags, bool onoff = true) { return mdb_env_set_flags(_env, flags, onoff ? 1: 0); }

        int32_t set_mapsize(size_t size) { return mdb_env_set_mapsize(_env, size); }
        int32_t set_max_dbs(size_t count) { return mdb_env_set_maxdbs(_env, count); }
        int32_t set_max_readers(uint32_t count) { return mdb_env_set_maxreaders(_env, count); }

        void txn_abort() { mdb_txn_abort(_txn); }
        void txn_reset() { mdb_txn_reset(_txn); }
        size_t txn_id() { return mdb_txn_id(_txn); }
        int32_t commit() { return mdb_txn_commit(_txn); }
        int32_t drop(bool del = true) {
            if (_dbi > 0) {
                return mdb_drop(_txn, _dbi, del ? 1 : 0);
            }
            return MDB_SUCCESS;
        }
        int32_t begin(const char* name, int flags) {
            int rc = mdb_txn_begin(_env, nullptr, flags, &_txn);
            if (rc != MDB_SUCCESS) return rc;
            if (_dbi > 0) mdb_dbi_close(_env, _dbi);
            return mdb_dbi_open(_txn, name, flags, &_dbi);
        }
        int32_t put(std::string key, std::string val) {
            MDB_val mkey{ key.size(), (void*)key.c_str() };
            MDB_val mval{ val.size(), (void*)val.c_str() };
            return mdb_put(_txn, _dbi, &mkey, &mval, 0);
        }
        const char* get(std::string key) {
            MDB_val mval;
            MDB_val mkey{ key.size(), (void*)key.c_str() };
            int rc = mdb_get(_txn, _dbi, &mkey, &mval);
            if (rc != MDB_SUCCESS) return nullptr;
            return (const char*)mval.mv_data;
        }
        bool del(std::string key) {
            MDB_val mkey{ key.size(), (void*)key.c_str() };
            int rc = mdb_del(_txn, _dbi, &mkey, nullptr);
            if (rc != MDB_SUCCESS) return false;
            return true;
        }
        int32_t cursor_open() {
            return mdb_cursor_open(_txn, _dbi, &_cur);
        }
        int32_t cursor_put(std::string key, std::string val, int flag) {
            MDB_val mkey{ key.size(), (void*)key.c_str() };
            MDB_val mval{ val.size(), (void*)val.c_str() };
            return mdb_cursor_put(_cur, &mkey, &mval, flag);
        }
        const char* cursor_get(std::string key, int flag) {
            MDB_val mval;
            MDB_val mkey{ key.size(), (void*)key.c_str() };
            int rc = mdb_cursor_get(_cur, &mkey, &mval, (MDB_cursor_op)flag);
            if (rc != MDB_SUCCESS) return nullptr;
            return (const char*)mval.mv_data;
        }
        bool cursor_del(int flag) {
            return mdb_cursor_del(_cur, flag) != MDB_SUCCESS;
        }

    protected:
        MDB_dbi _dbi = 0;
        MDB_env* _env = nullptr;
        MDB_txn* _txn = nullptr;
        MDB_cursor* _cur = nullptr;
    };
}
