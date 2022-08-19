#define LUA_LIB

#include "lcurl.h"

namespace lcurl {

    luakit::lua_table open_lcurl(lua_State* L) {
        //类导出
        luakit::kit_state kit_state(L);
        luakit::lua_table luacurl = kit_state.new_table();
        kit_state.new_class<curlm_mgr>(
            "update", &curlm_mgr::update,
            "destory", &curlm_mgr::destory,
            "create_request", &curlm_mgr::create_request
            );
        kit_state.new_class<curl_request>(
            "call_get", &curl_request::call_get,
            "call_put", &curl_request::call_put,
            "call_del", &curl_request::call_del,
            "call_post", &curl_request::call_post,
            "set_header", &curl_request::set_header,
            "get_respond", &curl_request::get_respond
            );
        //创建管理器
        CURL* curle = curl_easy_init();
        CURLM* curlm = curl_multi_init();
        curlm_mgr* curl_mgr = new curlm_mgr(curlm, curle);
        luacurl.set("curlm_mgr", curl_mgr);
        //函数导出
        luacurl.set_function("url_encode", [&](lua_State* L, string str){
            char* output = curl_easy_escape(curle, str.c_str(), str.size());
            if (output) {
                lua_pushstring(L, output);
                curl_free(output);
                return 1;
            }
            return 0;
        });
        return luacurl;
    }
}

extern "C" {
    LUALIB_API int luaopen_lcurl(lua_State* L) {
        curl_version_info_data* data = curl_version_info(CURLVERSION_NOW);
        if (data->version_num < 0x070F04) {
            return luaL_error(L, "requires 7.15.4 or higher curl, current version is %s", data->version);
        }
        curl_global_init(CURL_GLOBAL_ALL);
        auto luacurl = lcurl::open_lcurl(L);
        return luacurl.push_stack();
    }
}
