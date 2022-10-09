
#include "lcodec.h"

namespace lcodec {

    static serializer* def_seri = nullptr;

    static slice* encode_slice(lua_State* L) {
        return def_seri->encode_slice(L);
    }
    static int decode_slice(lua_State* L, slice* buf) {
        return def_seri->decode_slice(L, buf);
    }
    static int serialize(lua_State* L) {
        return def_seri->serialize(L);
    }
    static int unserialize(lua_State* L) {
        return def_seri->unserialize(L);
    }
    static int encode(lua_State* L) {
        return def_seri->encode(L);
    }
    static int decode(lua_State* L, const char* buf, size_t len) {
        return def_seri->decode(L, buf, len);
    }
    static serializer* new_serializer() {
        return new serializer();
    }

    static void init_static_codec() {
        if (!def_seri) {
            def_seri = new serializer();
        }
    }

    luakit::lua_table open_lcodec(lua_State* L) {
        luakit::kit_state kit_state(L);
        auto llcodec = kit_state.new_table();
        llcodec.set_function("encode", encode);
        llcodec.set_function("decode", decode);
        llcodec.set_function("serialize", serialize);
        llcodec.set_function("unserialize", unserialize);
        llcodec.set_function("encode_slice", encode_slice);
        llcodec.set_function("decode_slice", decode_slice);
        llcodec.set_function("new_serializer", new_serializer);
        kit_state.new_class<slice>(
            "size", &slice::size,
            "read", &slice::read,
            "peek", &slice::check,
            "string", &slice::string,
            "contents", &slice::contents
            );
        kit_state.new_class<serializer>(
            "encode", &serializer::encode,
            "decode", &serializer::decode,
            "serialize", &serializer::serialize,
            "unserialize", &serializer::unserialize,
            "encode_slice", &serializer::encode_slice,
            "decode_slice", &serializer::decode_slice
            );
        return llcodec;
    }
}

extern "C" {
    LUALIB_API int luaopen_lcodec(lua_State* L) {
        lcodec::init_static_codec();
        auto lluabus = lcodec::open_lcodec(L);
        return lluabus.push_stack();
    }
}
