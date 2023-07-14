
#include "lcodec.h"

namespace lcodec {

    thread_local ketama thread_ketama;
    thread_local serializer thread_seri;
    static slice* encode_slice(lua_State* L) {
        return thread_seri.encode_slice(L);
    }
    static int decode_slice(lua_State* L, slice* buf) {
        return thread_seri.decode_slice(L, buf);
    }
    static int serialize(lua_State* L) {
        return thread_seri.serialize(L);
    }
    static int unserialize(lua_State* L) {
        return thread_seri.unserialize(L);
    }
    static int encode(lua_State* L) {
        return thread_seri.encode(L);
    }
    static int decode(lua_State* L, const char* buf, size_t len) {
        return thread_seri.decode(L, buf, len);
    }
    static bool ketama_insert(std::string name, uint32_t node_id) {
        return thread_ketama.insert(name, node_id, 255);
    }
    static void ketama_remove(uint32_t node_id) {
        thread_ketama.remove(node_id);
    }
    static uint32_t ketama_next(uint32_t node_id) {
        return thread_ketama.next(node_id);
    }
    static std::map<uint32_t, uint32_t> ketama_map() {
        return thread_ketama.virtual_map;
    }

    static std::string utf8_gbk(std::string str) {
        char pOut[1024];
        memset(pOut, 0, sizeof(pOut));
        utf8_to_gb(str.c_str(), pOut, sizeof(pOut));        
        return pOut;
    }
    static std::string gbk_utf8(std::string str) {
        char pOut[1024];
        memset(pOut, 0, sizeof(pOut));
        gb_to_utf8(str.c_str(), pOut, sizeof(pOut));
        return pOut;
    }

    static bitarray* barray(lua_State* L, size_t nbits) {
        bitarray* barray = new bitarray();
        if (!barray->general(nbits)) {
            delete barray;
            return nullptr;
        }
        return barray;
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
        llcodec.set_function("guid_new", guid_new);
        llcodec.set_function("guid_encode", guid_encode);
        llcodec.set_function("guid_decode", guid_decode);
        llcodec.set_function("guid_group", guid_group);
        llcodec.set_function("guid_index", guid_index);
        llcodec.set_function("guid_type", guid_type); 
        llcodec.set_function("guid_serial", guid_serial);
        llcodec.set_function("guid_time", guid_time);
        llcodec.set_function("guid_source", guid_source);
        llcodec.set_function("hash_code", hash_code);
        llcodec.set_function("jumphash", jumphash_l);
        llcodec.set_function("fnv_1_32", fnv_1_32_l);
        llcodec.set_function("fnv_1a_32", fnv_1a_32_l);
        llcodec.set_function("murmur3_32", murmur3_32_l);
        llcodec.set_function("ketama_insert", ketama_insert);
        llcodec.set_function("ketama_remove", ketama_remove);
        llcodec.set_function("ketama_next", ketama_next);
        llcodec.set_function("ketama_map", ketama_map);
        llcodec.set_function("bitarray", barray);

        llcodec.set_function("utf8_gbk", utf8_gbk);
        llcodec.set_function("gbk_utf8", gbk_utf8);

        kit_state.new_class<bitarray>(
            "flip", &bitarray::flip,
            "fill", &bitarray::fill,
            "equal", &bitarray::equal,
            "clone", &bitarray::clone,
            "slice", &bitarray::slice,
            "concat", &bitarray::concat,
            "lshift", &bitarray::lshift,
            "rshift", &bitarray::rshift,
            "length", &bitarray::length,
            "resize", &bitarray::resize,
            "reverse", &bitarray::reverse,
            "set_bit", &bitarray::set_bit,
            "get_bit", &bitarray::get_bit,
            "flip_bit", &bitarray::flip_bit,
            "to_string", &bitarray::to_string,
            "from_string", &bitarray::from_string,
            "to_uint8", &bitarray::to_number<uint8_t>,
            "to_uint16", &bitarray::to_number<uint16_t>,
            "to_uint32", &bitarray::to_number<uint32_t>,
            "to_uint64", &bitarray::to_number<uint64_t>,
            "from_uint8", &bitarray::from_number<uint8_t>,
            "from_uint16", &bitarray::from_number<uint16_t>,
            "from_uint32", &bitarray::from_number<uint32_t>,
            "from_uint64", &bitarray::from_number<uint64_t>
            );

        return llcodec;
    }
}

extern "C" {
    LUALIB_API int luaopen_lcodec(lua_State* L) {
        auto lcodec = lcodec::open_lcodec(L);
        return lcodec.push_stack();
    }
}
