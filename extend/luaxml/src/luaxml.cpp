#define LUA_LIB

#include "lua_kit.h"
#include "tinyxml2.h"

using namespace luakit;
using namespace tinyxml2;

namespace luaxml {

    static void push_elem2lua(lua_State* L, const XMLElement* elem) {
        uint32_t count = elem->ChildElementCount();
        const XMLAttribute* attr = elem->FirstAttribute();
        const char* value = elem->GetText();
        if (count == 0 && attr == nullptr) {
            value = value ? value : "";
            if (lua_stringtonumber(L, value) == 0) {
                lua_pushstring(L, value);
            }
            return;
        }
        lua_createtable(L, 0, 4);
        if (value) {
            if (lua_stringtonumber(L, value) == 0) {
                lua_pushstring(L, value);
            }
            lua_seti(L, -2, 1);
        }
        if (attr) {
            lua_createtable(L, 0, 4);
            while (attr) {
                if (lua_stringtonumber(L, attr->Value()) == 0) {
                    lua_pushstring(L, attr->Value());
                }
                lua_setfield(L, -2, attr->Name());
                attr = attr->Next();
            }
            lua_setfield(L, -2, "_attr");
        }
        if (count > 0) {
            const XMLElement* child = elem->FirstChildElement();
            std::map<std::string, std::vector<const XMLElement*>> elems;
            while (child) {
                auto it = elems.find(child->Name());
                if (it != elems.end()) {
                    it->second.push_back(child);
                } else {
                    elems.insert(std::make_pair(child->Name(), std::vector{ child }));
                }
                child = child->NextSiblingElement();
            }
            for (auto it : elems) {
                size_t child_size = it.second.size();
                if (child_size == 1) {
                    push_elem2lua(L, it.second[0]);
                } else {
                    lua_createtable(L, 0, 4);
                    for (size_t i = 0; i < child_size; ++i) {
                        push_elem2lua(L, it.second[i]);
                        lua_seti(L, -2, i + 1);
                    }
                }
                lua_setfield(L, -2, it.first.c_str());
            }
        }
    }
    static void load_elem4lua(lua_State* L, XMLPrinter* printer);
    static void load_table4lua(lua_State* L, XMLPrinter* printer) {
        lua_guard g(L);
        if (lua_getfield(L, -1, "_attr") == LUA_TTABLE) {
            lua_pushnil(L);
            while (lua_next(L, -2) != 0) {
                const char* key = lua_tostring(L, -2);
                switch (lua_type(L, -1)) {
                case LUA_TSTRING: printer->PushAttribute(key, lua_tostring(L, -1)); break;
                case LUA_TBOOLEAN: printer->PushAttribute(key, lua_toboolean(L, -1)); break;
                case LUA_TNUMBER: lua_isinteger(L, -1) ? printer->PushAttribute(key, int64_t(lua_tointeger(L, -1))) : printer->PushAttribute(key, lua_tonumber(L, -1)); break;
                }
                lua_pop(L, 1);
            }
        }
        lua_pushnil(L);
        lua_setfield(L, -3, "_attr");
        switch (lua_geti(L, -2, 1)) {
        case LUA_TSTRING: printer->PushText(lua_tostring(L, -1)); break;
        case LUA_TBOOLEAN: printer->PushText(lua_toboolean(L, -1)); break;
        case LUA_TNUMBER: lua_isinteger(L, -1) ? printer->PushText(int64_t(lua_tointeger(L, -1))) : printer->PushText(lua_tonumber(L, -1)); break;
        }
        lua_pushnil(L);
        lua_seti(L, -4, 1);
        lua_pushnil(L);
        while (lua_next(L, -4) != 0) {
            load_elem4lua(L, printer);
            lua_pop(L, 1);
        }
    }

    static void load_elem4lua(lua_State* L, XMLPrinter* printer) {
        const char* key = lua_tostring(L, -2);
        if (!is_lua_array(L, -1)) {
            printer->OpenElement(key);
            switch (lua_type(L, -1)) {
            case LUA_TTABLE: load_table4lua(L, printer); break;
            case LUA_TSTRING: printer->PushText(lua_tostring(L, -1)); break;
            case LUA_TBOOLEAN: printer->PushText(lua_toboolean(L, -1)); break;
            case LUA_TNUMBER: lua_isinteger(L, -1) ? printer->PushText(int64_t(lua_tointeger(L, -1))) : printer->PushText(lua_tonumber(L, -1)); break;
            }
            printer->CloseElement();
            return;
        }
        lua_pushstring(L, key);
        int raw_len = lua_rawlen(L, -2);
        for (int i = 1; i <= raw_len; ++i) {
            lua_rawgeti(L, -2, i);
            load_elem4lua(L, printer);
            lua_pop(L, 1);
        }
        lua_pop(L, 1);
    }

    static int decode_xml(lua_State* L, const char* xml) {
        XMLDocument doc;
        if (doc.Parse(xml) != XML_SUCCESS) {
            lua_pushnil(L);
            lua_pushstring(L, "parse xml doc failed!");
            return 2;
        }
        lua_createtable(L, 0, 4);
        const XMLElement* root = doc.RootElement();
        push_elem2lua(L, root);
        lua_setfield(L, -2, root->Name());
        return 1;
    }

    static int encode_xml(lua_State* L) {
        XMLPrinter printer;
        const char* header = luaL_optstring(L, 2, nullptr);
        if (header) {
            printer.PushDeclaration(header);
        } else {
            printer.PushHeader(false, true);
        }
        lua_pushnil(L);
        while (lua_next(L, 1) != 0) {
            load_elem4lua(L, &printer);
            lua_pop(L, 1);
        }
        lua_pushlstring(L, printer.CStr(), printer.CStrSize());
        return 1;
    }

    static int open_xml(lua_State* L, const char* xmlfile) {
        XMLDocument doc;
        if (doc.LoadFile(xmlfile) != XML_SUCCESS) {
            lua_pushnil(L);
            lua_pushstring(L, "parse xml doc failed!");
            return 2;
        }
        lua_createtable(L, 0, 4);
        const XMLElement* root = doc.RootElement();
        push_elem2lua(L, root);
        lua_setfield(L, -2, root->Name());
        return 1;
    }

    static FILE* fopenxml(const char* filepath, const char* mode) {
#if defined(_MSC_VER)
        FILE* fp = 0;
        const errno_t err = fopen_s(&fp, filepath, mode);
        if (err) return 0;
#else
        FILE* fp = fopen(filepath, mode);
#endif
        return fp;
    }

    static int save_xml(lua_State* L, const char* xmlfile) {
        FILE* fp = fopenxml(xmlfile, "w");
        if (fp == nullptr) {
            lua_pushboolean(L, false);
            lua_pushstring(L, "file dont open, save xml failed!");
            return 2;
        }
        XMLPrinter printer(fp);
        const char* header = luaL_optstring(L, 3, nullptr);
        if (header) {
            printer.PushDeclaration(header);
        } else {
            printer.PushHeader(false, true);
        }
        lua_pushnil(L);
        while (lua_next(L, 2) != 0) {
            load_elem4lua(L, &printer);
            lua_pop(L, 1);
        }
        fclose(fp);
        return 1;
    }

    lua_table open_luaxml(lua_State* L) {
        kit_state kit_state(L);
        lua_table lxml = kit_state.new_table("xml");
        lxml.set_function("decode", decode_xml);
        lxml.set_function("encode", encode_xml);
        lxml.set_function("open", open_xml);
        lxml.set_function("save", save_xml);
        return lxml;
    }
}

extern "C" {
    LUALIB_API int luaopen_luaxml(lua_State* L) {
        auto luaxlsx = luaxml::open_luaxml(L);
        return luaxlsx.push_stack();
    }
}
