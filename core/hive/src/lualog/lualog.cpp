#include "logger.h"
#include "lua_kit.h"

using namespace std;
using namespace luakit;

namespace logger {

    size_t log_limit_len(log_level logLv) {
        if (logLv < log_level::LOG_LEVEL_DEBUG || logLv > log_level::LOG_LEVEL_WARN)return 65536;
        return 4096;
    }
    string read_args(lua_State* L, int flag, int index, size_t max_len) {
        switch (lua_type(L, index)) {
        case LUA_TNIL: return "nil";
        case LUA_TTHREAD: return "thread";
        case LUA_TFUNCTION: return "function";
        case LUA_TUSERDATA:  return "userdata";
        case LUA_TLIGHTUSERDATA: return "userdata";
        case LUA_TSTRING: return lua_tostring(L, index);
        case LUA_TBOOLEAN: return lua_toboolean(L, index) ? "true" : "false";
        case LUA_TTABLE:
            if ((flag & 0x01) == 0x01) {
                thread_buff.clean();
                serialize_one(L, &thread_buff, index, 1, (flag & 0x02) == 0x02, max_len);
                return string((char*)thread_buff.head(), thread_buff.size());
            }
            return luaL_tolstring(L, index, nullptr);
        case LUA_TNUMBER:
            if (lua_isinteger(L, index)) {
                return fmt::format("{}", lua_tointeger(L, index));
            }
            return fmt::format("{}", lua_tonumber(L, index));
        }
        return "unsuppert data type";
    }

    int zformat(lua_State* L, log_level lvl, cstring& tag, cstring& feature, cstring& msg) {
        if (log_service::instance()->need_hook(lvl) ) {
            lua_pushlstring(L, msg.c_str(), msg.size());
            log_service::instance()->output(lvl, msg, tag, feature);
            return 1;
        }
        log_service::instance()->output(lvl, msg, tag, feature);
        return 0;
    }

    template<size_t... integers>
    int tformat(lua_State* L, log_level lvl, cstring& tag, cstring& feature, int flag, vstring vfmt, size_t max_len, std::index_sequence<integers...>&&) {
        try {
            auto msg = fmt::format(vfmt, read_args(L, flag, integers + 6, max_len)...);
            return zformat(L, lvl, tag, feature, msg);
        }
        catch (const exception& e) {
            luaL_error(L, "log format failed: %s!", e.what());
        }
        return 0;
    }

    template<size_t... integers>
    int fformat(lua_State* L, int flag, vstring vfmt, std::index_sequence<integers...>&&) {
        try {
            auto msg = fmt::format(vfmt, read_args(L, flag, integers + 3, 0)...);
            lua_pushlstring(L, msg.c_str(), msg.size());
            return 1;
        }
        catch (const exception& e) {
            luaL_error(L, "log format failed: %s!", e.what());
        }
        return 0;
    }

    void replace_fmt(vstring vfmt) {
#ifdef SUPPORT_FORMAT_LUA
        char* pfmt = const_cast<char*>(vfmt.data());
        if (vfmt.size() > 1) {
            for (auto i = 0; i < vfmt.size() - 1; ++i) {
                if (pfmt[i] == '%' && (pfmt[i+1] == 's' || pfmt[i+1] == 'd')) {
                    pfmt[i] = '{';
                    pfmt[i + 1] = '}';
                    ++i;
                }
            }
        }
#endif // SUPPORT_FORMAT_LUA
    }

    luakit::lua_table open_lualog(lua_State* L) {
        luakit::kit_state kit_state(L);
        auto lualog = kit_state.new_table();
        lualog.new_enum("LOG_LEVEL",
            "TRACE", log_level::LOG_LEVEL_TRACE,
            "DEBUG", log_level::LOG_LEVEL_DEBUG,
            "INFO", log_level::LOG_LEVEL_INFO,
            "WARN", log_level::LOG_LEVEL_WARN,
            "ERROR", log_level::LOG_LEVEL_ERROR,
            "FATAL", log_level::LOG_LEVEL_FATAL
        );
        log_service::instance()->start();
        lualog.set_function("print", [](lua_State* L) {
            log_level lvl = (log_level)lua_tointeger(L, 1);
            if (log_service::instance()->is_filter(lvl)) return 0;
            size_t flag = lua_tointeger(L, 2);
            sstring tag = lua_to_native<sstring>(L, 3);
            sstring feature = lua_to_native<sstring>(L, 4);
            vstring vfmt = lua_to_native<vstring>(L, 5);
            replace_fmt(vfmt);          
            int arg_num = lua_gettop(L) - 5;
            auto max_len = log_limit_len(lvl);
            switch (arg_num) {
            case 0: return zformat(L, lvl, tag, feature, string(vfmt.data(), vfmt.size()));
            case 1: return tformat(L, lvl, tag, feature, flag, vfmt, max_len, make_index_sequence<1>{});
            case 2: return tformat(L, lvl, tag, feature, flag, vfmt, max_len, make_index_sequence<2>{});
            case 3: return tformat(L, lvl, tag, feature, flag, vfmt, max_len, make_index_sequence<3>{});
            case 4: return tformat(L, lvl, tag, feature, flag, vfmt, max_len, make_index_sequence<4>{});
            case 5: return tformat(L, lvl, tag, feature, flag, vfmt, max_len, make_index_sequence<5>{});
            case 6: return tformat(L, lvl, tag, feature, flag, vfmt, max_len, make_index_sequence<6>{});
            case 7: return tformat(L, lvl, tag, feature, flag, vfmt, max_len, make_index_sequence<7>{});
            case 8: return tformat(L, lvl, tag, feature, flag, vfmt, max_len, make_index_sequence<8>{});
            case 9: return tformat(L, lvl, tag, feature, flag, vfmt, max_len, make_index_sequence<9>{});
            case 10: return tformat(L, lvl, tag, feature, flag, vfmt, max_len, make_index_sequence<10>{});
            case 11: return tformat(L, lvl, tag, feature, flag, vfmt, max_len, make_index_sequence<11>{});
            case 12: return tformat(L, lvl, tag, feature, flag, vfmt, max_len, make_index_sequence<12>{});
            default: luaL_error(L, "log format args is error : %d !",arg_num); break;
            }
            return 0;
            });
        lualog.set_function("format", [](lua_State* L) {
            vstring vfmt = lua_to_native<vstring>(L, 1);
            size_t flag = lua_tointeger(L, 2);
            int arg_num = lua_gettop(L) - 2;
            switch (arg_num) {
            case 0: lua_pushstring(L, vfmt.data()); return 1;
            case 1: return fformat(L, flag, vfmt, make_index_sequence<1>{});
            case 2: return fformat(L, flag, vfmt, make_index_sequence<2>{});
            case 3: return fformat(L, flag, vfmt, make_index_sequence<3>{});
            case 4: return fformat(L, flag, vfmt, make_index_sequence<4>{});
            case 5: return fformat(L, flag, vfmt, make_index_sequence<5>{});
            case 6: return fformat(L, flag, vfmt, make_index_sequence<6>{});
            case 7: return fformat(L, flag, vfmt, make_index_sequence<7>{});
            case 8: return fformat(L, flag, vfmt, make_index_sequence<8>{});
            case 9: return fformat(L, flag, vfmt, make_index_sequence<9>{});
            case 10: return fformat(L, flag, vfmt, make_index_sequence<10>{});
            case 11: return fformat(L, flag, vfmt, make_index_sequence<11>{});
            case 12: return fformat(L, flag, vfmt, make_index_sequence<12>{});
            default: luaL_error(L, "log format args is error : %d !", arg_num); break;
            }
            return 0;
            });

        lualog.set_function("daemon", [](bool status) { log_service::instance()->daemon(status); });
        lualog.set_function("set_max_logsize", [](size_t logsize) { log_service::instance()->set_max_logsize(logsize); });
        lualog.set_function("set_clean_time", [](size_t time) { log_service::instance()->set_clean_time(time); });
        lualog.set_function("filter", [](int lv, bool on) { log_service::instance()->filter((log_level)lv, on); });
        lualog.set_function("is_filter", [](int lv) { return log_service::instance()->is_filter((log_level)lv); });
        lualog.set_function("del_dest", [](vstring feature) { log_service::instance()->del_dest(feature); });
        lualog.set_function("add_dest", [](vstring feature, vstring log_path) { return log_service::instance()->add_dest(feature,log_path); });
        lualog.set_function("del_lvl_dest", [](int lv) { log_service::instance()->del_lvl_dest((log_level)lv); });
        lualog.set_function("add_lvl_dest", [](int lv) { return log_service::instance()->add_lvl_dest((log_level)lv); });
        lualog.set_function("ignore_prefix", [](vstring feature, bool prefix) { log_service::instance()->ignore_prefix(feature, prefix); });
        lualog.set_function("ignore_suffix", [](vstring feature, bool suffix) { log_service::instance()->ignore_suffix(feature, suffix); });
        lualog.set_function("ignore_def", [](vstring feature, bool def) { log_service::instance()->ignore_def(feature, def); });
        lualog.set_function("option", [](vstring log_path, vstring service, vstring index, rolling_type type, log_level hook_lv){
            log_service::instance()->option(log_path, service, index, type, hook_lv);
        });
        return lualog;
    }
}

extern "C" {
    LUALIB_API int luaopen_lualog(lua_State* L) {
        auto llog = logger::open_lualog(L);
        return llog.push_stack();
    }
}
