#pragma once
#include <map>

#include "lualog/logger.h"
#include "worker/scheduler.h"

using namespace logger;
class hive_app final
{
public:
	hive_app() { }
	~hive_app() { }

	void run();
	void setup(int argc, const char* argv[]);
	bool load(int argc, const char* argv[]);
	void set_signal(uint32_t n, bool b = true);
protected:
	std::string get_environ_def(const std::string_view key, const std::string_view def) { auto value = getenv(key.data()); return value ? value : def.data(); };
	void exception_handler(const std::string& err_msg);

private:
	uint64_t m_signal = 0;
	lworker::scheduler m_schedulor;
};

extern hive_app* g_app;
