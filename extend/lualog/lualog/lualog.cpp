#define LUA_LIB

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
		kit_state.new_class<log_service>(
			"stop", &log_service::stop,
			"start", &log_service::start,
			"daemon", &log_service::daemon,
			"option", &log_service::option,
			"filter", &log_service::filter,
			"add_dest", &log_service::add_dest,
			"del_dest", &log_service::del_dest,
			"is_filter", &log_service::is_filter,
			"add_lvl_dest", &log_service::add_lvl_dest,
			"del_lvl_dest", &log_service::del_lvl_dest,
			"info", &log_service::output<log_level::LOG_LEVEL_INFO>,
			"warn", &log_service::output<log_level::LOG_LEVEL_WARN>,
			"dump", &log_service::output<log_level::LOG_LEVEL_DUMP>,
			"debug", &log_service::output<log_level::LOG_LEVEL_DEBUG>,
			"error", &log_service::output<log_level::LOG_LEVEL_ERROR>,
			"fatal", &log_service::output<log_level::LOG_LEVEL_FATAL>
			);
		return lualog;
	}
}

extern "C" {
    LUALIB_API int luaopen_lualog(lua_State* L) {
        system("echo logger service init.");
		return logger::open_lualog(L).push_stack();
    }
}
