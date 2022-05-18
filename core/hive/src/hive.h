#pragma once
#include <map>

#include "logger.h"

using environ_map = std::map<std::string, std::string>;

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

    std::shared_ptr<log_service> get_logger() { return m_logger; }
protected:
    void init_logger();
	const char* get_environ(std::string k);
	std::string get_environ_def(std::string key, std::string def) {	auto value = get_environ(key);return value ? value : def;};
	void set_environ(std::string k, std::string v) { m_environs[k] = v; }
    void exception_handler(std::string msg, std::string& err);

private:
    uint64_t m_signal = 0;
    environ_map m_environs;

    std::shared_ptr<log_service> m_logger;
};

extern hive_app* g_app;
