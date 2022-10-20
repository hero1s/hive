#include "logger.h"
#include "lua_kit.h"

namespace logger {

    luakit::lua_table open_lualog(lua_State* L) {
        luakit::kit_state kit_state(L);
        auto lualog = kit_state.new_table();
        lualog.new_enum("LOG_LEVEL",
            "INFO", log_level::LOG_LEVEL_INFO,
            "WARN", log_level::LOG_LEVEL_WARN,
            "DUMP", log_level::LOG_LEVEL_DUMP,
            "DEBUG", log_level::LOG_LEVEL_DEBUG,
            "ERROR", log_level::LOG_LEVEL_ERROR,
            "FATAL", log_level::LOG_LEVEL_FATAL
        );
        log_service::instance()->start();
        lualog.set_function("daemon", [](bool status) { log_service::instance()->daemon(status); });
        lualog.set_function("set_max_line", [](size_t line) { log_service::instance()->set_max_line(line); });
        lualog.set_function("set_clean_time", [](size_t time) { log_service::instance()->set_clean_time(time); });
        lualog.set_function("filter", [](int lv, bool on) { log_service::instance()->filter((log_level)lv, on); });
        lualog.set_function("is_filter", [](int lv) { return log_service::instance()->is_filter((log_level)lv); });
        lualog.set_function("del_dest", [](std::string feature) { log_service::instance()->del_dest(feature); });
        lualog.set_function("add_dest", [](std::string feature) { return log_service::instance()->add_dest(feature); });
        lualog.set_function("del_lvl_dest", [](int lv) { log_service::instance()->del_lvl_dest((log_level)lv); });
        lualog.set_function("add_lvl_dest", [](int lv) { return log_service::instance()->add_lvl_dest((log_level)lv); });
        lualog.set_function("info", [](std::string msg, std::string feature) { log_service::instance()->output<log_level::LOG_LEVEL_INFO>(msg, feature); });
        lualog.set_function("warn", [](std::string msg, std::string feature) { log_service::instance()->output<log_level::LOG_LEVEL_WARN>(msg, feature); });
        lualog.set_function("dump", [](std::string msg, std::string feature) { log_service::instance()->output<log_level::LOG_LEVEL_DUMP>(msg, feature); });
        lualog.set_function("debug", [](std::string msg, std::string feature) { log_service::instance()->output<log_level::LOG_LEVEL_DEBUG>(msg, feature); });
        lualog.set_function("error", [](std::string msg, std::string feature) { log_service::instance()->output<log_level::LOG_LEVEL_ERROR>(msg, feature); });
        lualog.set_function("fatal", [](std::string msg, std::string feature) { log_service::instance()->output<log_level::LOG_LEVEL_FATAL>(msg, feature); });
        lualog.set_function("option", [](std::string log_path, std::string service, std::string index, rolling_type type){
            log_service::instance()->option(log_path, service, index, type);
        });
        return lualog;
    }
}

extern "C" {
    LUALIB_API int luaopen_lualog(lua_State* L) {
        system("echo logger service init.");
        auto llog = logger::open_lualog(L);
        return llog.push_stack();
    }
}
