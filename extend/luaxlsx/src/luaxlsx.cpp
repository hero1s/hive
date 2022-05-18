#define LUA_LIB

extern "C"
{
    #include "lua.h"
    #include "lualib.h"
    #include "lauxlib.h"
}

#include "MiniExcel.h"

using namespace MiniExcel;

template<typename T>
static void newUserData(lua_State* L, T* p, const char* type)
{
    T** ret = (T**)lua_newuserdata(L, sizeof(T*));
    luaL_getmetatable(L, type);
    lua_setmetatable(L, -2);

    *ret = p;
}

template<typename T>
static T* to(lua_State* L, int n, const char* type)
{
    return *(T**)luaL_checkudata(L, n, type);
}

#define MINI_EXCEL_CELL "Cell"
#define MINI_EXCEL_RANGE "Range"
#define MINI_EXCEL_SHEET "Sheet"
#define MINI_EXCEL_EXCELFILE "ExcelFile"

#define toExcel(L, n) to<ExcelFile>(L, n, MINI_EXCEL_EXCELFILE)
#define toSheet(L, n) to<Sheet>(L, n, MINI_EXCEL_SHEET)
#define toRange(L, n) to<Range>(L, n, MINI_EXCEL_RANGE)
#define toCell(L, n) to<Cell>(L, n, MINI_EXCEL_CELL)

#define newExcel(L, p) newUserData<ExcelFile>(L, p, MINI_EXCEL_EXCELFILE)
#define newSheet(L, p) newUserData<Sheet>(L, p, MINI_EXCEL_SHEET)
#define newRange(L, p) newUserData<Range>(L, p, MINI_EXCEL_RANGE)
#define newCell(L, p)  newUserData<Cell>(L, p, MINI_EXCEL_CELL)

static int l_open_excel(lua_State* L)
{
    const char* file = luaL_checkstring(L, 1);

    ExcelFile* e = new ExcelFile;

    if (!e->open(file))
    {
        delete e;
        lua_pushnil(L);
        return 1;
    }

    newExcel(L, e);

    return 1;
}

static int l_excel_file_gc(lua_State* L) {
    ExcelFile* e = toExcel(L, 1);

    if (e)
        delete e;

    return 0;
}

static int l_getSheet(lua_State* L)
{
    ExcelFile* e = toExcel(L, 1);
    const char* name = luaL_checkstring(L, 2);

    Sheet* s = e->getSheet(name);

    if (s)
        newSheet(L, s);
    else
        lua_pushnil(L);

    return 1;
}

static int l_sheets(lua_State* L)
{
    ExcelFile* e = toExcel(L, 1);

    lua_createtable(L, 0, 0);

    auto& sheets = e->sheets();
    for (unsigned i = 0; i < sheets.size(); i++)
    {
        Sheet* sh = &sheets[i];
        newSheet(L, sh);
        lua_rawseti(L, -2, i + 1);
    }

    return 1;
}

static int l_visible(lua_State* L)
{
    Sheet* s = toSheet(L, 1);
    lua_pushboolean(L, !!s->visible());
    return 1;
}

static int l_name(lua_State* L)
{
    Sheet* s = toSheet(L, 1);
    lua_pushstring(L, s->getName().c_str());
    return 1;
}

static int l_dimension(lua_State* L)
{
    Sheet* s = toSheet(L, 1);
    newRange(L, &s->getDimension());
    return 1;
}

static int l_cell(lua_State* L)
{
    Sheet* s = toSheet(L, 1);
    int row = luaL_checkinteger(L, 2);
    int col = luaL_checkinteger(L, 3);

    Cell* c = s->getCell(row, col);

    if (c)
        newCell(L, c);
    else
        lua_pushnil(L);

    return 1;
}

static luaL_Reg Sheet_functions[] = {
    { "visible", l_visible},
    { "name", l_name },
    { "dimension", l_dimension },
    { "cell", l_cell },

    { NULL, NULL }
};

static luaL_Reg ExcelFile_functions[] = {
    { "getSheet", l_getSheet },
    { "sheets", l_sheets },
    { "__gc", l_excel_file_gc },

    { NULL, NULL }
};

static luaL_Reg mini_excel_functions[] = {
    { "open", l_open_excel },
    { NULL, NULL }
};

static int cell_func(lua_State* L)
{
    Cell* cell = toCell(L, 1);
    const char* name = luaL_checkstring(L, 2);

    if (strcmp(name, "value") == 0)
        lua_pushstring(L, cell->value.c_str());
    else if (strcmp(name, "type") == 0)
        lua_pushstring(L, cell->type.c_str());
    else if (strcmp(name, "fmtCode") == 0)
        lua_pushstring(L, cell->fmtCode.c_str());
    else if (strcmp(name, "fmtId") == 0)
        lua_pushinteger(L, cell->fmtId);
    else
        lua_pushnil(L);

    return 1;
}

static int range_func(lua_State* L)
{
    Range* range = toRange(L, 1);
    const char* name = luaL_checkstring(L, 2);

    if (strcmp(name, "firstRow") == 0)
        lua_pushinteger(L, range->firstRow);
    else if (strcmp(name, "lastRow") == 0)
        lua_pushinteger(L, range->lastRow);
    else if (strcmp(name, "firstCol") == 0)
        lua_pushinteger(L, range->firstCol);
    else if (strcmp(name, "lastCol") == 0)
        lua_pushinteger(L, range->lastCol);
    else
        lua_pushnil(L);

    return 1;
}


static void newMetatable1(lua_State* L, const char* name, luaL_Reg* reg) {
    luaL_newmetatable(L, name);
    luaL_setfuncs(L, reg, NULL);
    lua_pushvalue(L, -1);
    lua_setfield(L, -2, "__index");
}

static void newMetatable2(lua_State* L, const char* name, lua_CFunction f) {
    luaL_newmetatable(L, name);
    lua_pushcfunction(L, f);
    lua_setfield(L, -2, "__index");
}

static int miniexcel_open(lua_State* L) {
    newMetatable2(L, MINI_EXCEL_CELL, cell_func);
    newMetatable2(L, MINI_EXCEL_RANGE, range_func);
    newMetatable1(L, MINI_EXCEL_SHEET, Sheet_functions);
    newMetatable1(L, MINI_EXCEL_EXCELFILE, ExcelFile_functions);

    lua_newtable(L);
    luaL_setfuncs(L, mini_excel_functions, NULL);

    return 1;
}

extern "C" {
    LUALIB_API int luaopen_luaxlsx(lua_State* L) {
        return miniexcel_open(L);
    }
}




