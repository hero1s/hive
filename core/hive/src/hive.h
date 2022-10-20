#pragma once
#include <map>

#include "lualog/logger.h"

using namespace logger;
class hive_app final
{
public:
	hive_app() { }
	~hive_app() { }

	void run();
	void setup(int argc, const char* argv[]);
	bool load(int argc, const char* argv[]);
	void set_signal(uint32_t n);
protected:
	std::string get_environ_def(std::string key, std::string def) { auto value = getenv(key.c_str()); return value ? value : def; };
	void exception_handler(std::string msg, std::string& err);

private:
	uint64_t m_signal = 0;
};

extern hive_app* g_app;
