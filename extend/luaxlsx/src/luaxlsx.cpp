#define LUA_LIB

#include "excel.h"

namespace lxlsx {

    static excel_file* open_xcel(const char* filename) {
        auto excel = new excel_file();
        if (!excel->open(filename)) {
            delete excel;
            return nullptr;
        }
        return excel;
    }

    luakit::lua_table open_luaxlsx(lua_State* L) {
        luakit::kit_state kit_state(L);
        luakit::lua_table luaxlsx = kit_state.new_table();
        luaxlsx.set_function("open", open_xcel);
        kit_state.new_class<cell>(
            "type", &cell::type,
            "value", &cell::value,
            "fmt_id", &cell::fmt_id,
            "fmt_code", &cell::fmt_code
            );
        kit_state.new_class<sheet>(
            "name", &sheet::name,
            "last_row", &sheet::last_row,
            "last_col", &sheet::last_col,
            "first_row", &sheet::first_row,
            "first_col", &sheet::first_col,
            "get_cell", &sheet::get_cell
            );
        kit_state.new_class<excel_file>(
            "sheets", &excel_file::sheets,
            "get_sheet", &excel_file::get_sheet
            );
        return luaxlsx;
    }
}

extern "C" {
    LUALIB_API int luaopen_luaxlsx(lua_State* L) {
        auto luaxlsx = lxlsx::open_luaxlsx(L);
        return luaxlsx.push_stack();
    }
}
