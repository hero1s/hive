
#include "bson.h"

namespace lbson {

    thread_local bson thread_bson;

    static int encode(lua_State* L) {
        return thread_bson.encode(L);
    }
    static int decode(lua_State* L) {
        return thread_bson.decode(L);
    }
    static int pairs(lua_State* L) {
        return thread_bson.pairs(L);
    }
    static int regex(lua_State* L) {
        return thread_bson.regex(L);
    }
    static int binary(lua_State* L) {
        return thread_bson.binary(L);
    }
    static int objectid(lua_State* L) {
        return thread_bson.objectid(L);
    }
    static int int64(lua_State* L, int64_t value) {
        return thread_bson.int64(L, value);
    }
    static int date(lua_State* L, int64_t value) {
        return thread_bson.date(L, value * 1000);
    }

    static void init_static_bson() {
        for (uint32_t i = 0; i < max_bson_index; ++i) {
            char tmp[8];
            bson_numstr_len[i] = sprintf(tmp, "%d", i);
            memcpy(bson_numstrs[i], tmp, bson_numstr_len[i]);
        }
    }

    static codec_base* mongo_codec() {
        mgocodec* codec = new mgocodec();
        codec->set_bson(&thread_bson);
        return codec;
    }

    luakit::lua_table open_lbson(lua_State* L) {
        luakit::kit_state kit_state(L);
        auto llbson = kit_state.new_table();
        llbson.set_function("mongocodec", mongo_codec);
        llbson.set_function("objectid", objectid);
        llbson.set_function("encode", encode);
        llbson.set_function("decode", decode);
        llbson.set_function("binary", binary);
        llbson.set_function("int64", int64);
        llbson.set_function("pairs", pairs);
        llbson.set_function("regex", regex);
        llbson.set_function("date", date);
        llbson.new_enum("BSON_TYPE",
            "BSON_EOO", bson_type::BSON_EOO,
            "BSON_REAL", bson_type::BSON_REAL,
            "BSON_STRING", bson_type::BSON_STRING,
            "BSON_DOCUMENT", bson_type::BSON_DOCUMENT,
            "BSON_ARRAY", bson_type::BSON_ARRAY,
            "BSON_BINARY", bson_type::BSON_BINARY,
            "BSON_OBJECTID", bson_type::BSON_OBJECTID,
            "BSON_BOOLEAN", bson_type::BSON_BOOLEAN,
            "BSON_DATE", bson_type::BSON_DATE,
            "BSON_NULL", bson_type::BSON_NULL,
            "BSON_REGEX", bson_type::BSON_REGEX,
            "BSON_JSCODE", bson_type::BSON_JSCODE,
            "BSON_INT32", bson_type::BSON_INT32,
            "BSON_INT64", bson_type::BSON_INT64,
            "BSON_INT128", bson_type::BSON_INT128,
            "BSON_MINKEY", bson_type::BSON_MINKEY,
            "BSON_MAXKEY", bson_type::BSON_MAXKEY
        );
        return llbson;
    }
}

extern "C" {
    LUALIB_API int luaopen_lbson(lua_State* L) {
        lbson::init_static_bson();
        auto lluabus = lbson::open_lbson(L);
        return lluabus.push_stack();
    }
}
