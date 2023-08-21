#include "logger.h"
#include "lua_kit.h"

namespace logger {

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
        lualog.set_function("trace", [](vstring msg, vstring tag, vstring feature) { log_service::instance()->output(log_level::LOG_LEVEL_TRACE,msg,tag, feature); });
        lualog.set_function("debug", [](vstring msg, vstring tag, vstring feature) { log_service::instance()->output(log_level::LOG_LEVEL_DEBUG,msg, tag, feature); });
        lualog.set_function("info", [](vstring msg, vstring tag, vstring feature) { log_service::instance()->output(log_level::LOG_LEVEL_INFO,msg, tag, feature); });
        lualog.set_function("warn", [](vstring msg, vstring tag, vstring feature) { log_service::instance()->output(log_level::LOG_LEVEL_WARN,msg, tag, feature); });
        lualog.set_function("error", [](vstring msg, vstring tag, vstring feature) { log_service::instance()->output(log_level::LOG_LEVEL_ERROR,msg, tag, feature); });
        lualog.set_function("fatal", [](vstring msg, vstring tag, vstring feature) { log_service::instance()->output(log_level::LOG_LEVEL_FATAL,msg, tag, feature); });
        lualog.set_function("option", [](vstring log_path, vstring service, vstring index, rolling_type type){
            log_service::instance()->option(log_path, service, index, type);
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
