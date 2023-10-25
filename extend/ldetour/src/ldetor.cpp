#define LUA_LIB

#include "detour.h"

namespace ldetour {

    static nav_mesh* create_mesh(const char* buf, size_t sz) {
        auto mesh = new nav_mesh();
        if (!dtStatusSucceed(mesh->create(buf, sz))) {
            delete mesh;
            return nullptr;
        }
        return mesh;
    }

    luakit::lua_table open_ldetour(lua_State* L) {
        luakit::kit_state kit_state(L);
        kit_state.new_class<nav_query>(
            "raycast", &nav_query::raycast,
            "find_path", &nav_query::find_path,
            "random_point", &nav_query::random_point,
            "point_valid", &nav_query::point_valid,
            "around_point", &nav_query::around_point,
            "find_valid_point", &nav_query::find_valid_point
            );
        kit_state.new_class<nav_mesh>(
            "create_query", &nav_mesh::create_query,
            "get_max_tiles", &nav_mesh::get_max_tiles
            );
        auto ldetour = kit_state.new_table();
        ldetour.set_function("create_mesh", create_mesh);
        return ldetour;
    }
}

extern "C" {
    LUALIB_API int luaopen_ldetour(lua_State* L) {
        auto ldetour = ldetour::open_ldetour(L);
        return ldetour.push_stack();
    }
}
