#pragma once
#include <map>

#include "lualog/logger.h"
#include "worker/scheduler.h"

using namespace logger;
using vstring = std::string_view;
using MAP_ENV = std::map<std::string, std::string>;

class hive_app final
{
public:
	hive_app() { }
	~hive_app() { }

	void run(int rtype);
	void setup(int argc, const char* argv[]);
	int load(int argc, const char* argv[]);
	int load_conf(int iRet, bool reload);
	void reload_conf(std::vector<std::string>& diff_keys);

	void set_signal(uint32_t n, bool b = true);

protected:
	std::string get_environ_def(vstring key, vstring def) { auto value = get_env(key.data()); return value ? value : def.data(); };
	void exception_handler(const std::string& err_msg);
	const char* get_env(const char* key);
	void set_env(std::string key, std::string value, int over = 0);
	void init_default_log(int rtype);

private:
	std::string m_lua_conf;
	uint64_t m_signal = 0;
	MAP_ENV m_environs;
	MAP_ENV m_cmd_environs;
	lworker::scheduler m_schedulor;
};

extern hive_app* g_app;
