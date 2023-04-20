#include <locale>
#include <stdlib.h>
#include <signal.h>
#include <functional>
#include "sandbox.h"
#include "hive.h"

#include "lua_kit.h"
#include <fmt/core.h>

#if WIN32
#include <conio.h>
#include <windows.h>
#include <psapi.h>  
#include <direct.h>
#include <process.h>
int setenv(const char* k, const char* v, int o) {
	if (!o && getenv(k)) return 0;
	return _putenv_s(k, v);
}
#else
#include <fcntl.h>
#include <unistd.h>
#include <sys/stat.h>
#include <sys/sysinfo.h>
#include <sys/time.h>
#endif

extern "C" void open_custom_libs(lua_State * L);

hive_app* g_app = nullptr;
static void on_signal(int signo) {
	if (g_app) {
		g_app->set_signal(signo);
	}
}

static const char* get_platform() {
#if defined(__linux)
	return "linux";
#elif defined(__APPLE__)
	return "apple";
#else
	return "windows";
#endif
}

static void daemon() {
#if defined(__linux) || defined(__APPLE__)
	pid_t pid = fork();
	if (pid != 0)
		exit(0);
	setsid();
	umask(0);
	int null = open("/dev/null", O_RDWR);
	if (null != -1) {
		dup2(null, STDIN_FILENO);
		dup2(null, STDOUT_FILENO);
		dup2(null, STDERR_FILENO);
		close(null);
	}
#endif
}

static int lset_env(lua_State* L) {
	const char* key = lua_tostring(L, 1);
	const char* value = lua_tostring(L, 2);
	auto overwrite = luaL_optinteger(L, 3, 1);
	setenv(key, value, int(overwrite));
	return 0;
}

static std::string add_lua_path(std::string path) {
	auto p = getenv("LUA_PATH");
	std::string cur_path = (p != NULL) ? p : "";
#ifdef WIN32
	cur_path.append("!/");
#endif // #if WIN32
	cur_path.append(path).append("?.lua;");
	setenv("LUA_PATH", cur_path.c_str(), 1);
	return cur_path;
}

void hive_app::set_signal(uint32_t n) {
	uint32_t mask = 1 << n;
	m_signal |= mask;
}

void hive_app::setup(int argc, const char* argv[]) {
	srand((unsigned)time(nullptr));
	//加载配置
	if (load(argc, argv)) {
		run();
	}
}

void hive_app::exception_handler(const std::string& msg, std::string& err) {
	LOG_FATAL(fmt::format(msg, err));
	log_service::instance()->stop();
#if WIN32
	_getch();
#endif
	exit(1);
}

bool hive_app::load(int argc, const char* argv[]) {
	bool bRet = true;
	//将启动参数转负责覆盖环境变量
	const char* lua_conf = nullptr;
	if (argc > 1) {
		std::string argvi = argv[1];
		if (argvi.find("=") == std::string::npos) {
			lua_conf = argv[1];
		}
	}
	if (lua_conf) {
		//加载LUA配置
		luakit::kit_state lua;
		lua.set("platform", get_platform());
		lua.set_function("set_env", lset_env);
		lua.set_function("add_lua_path", add_lua_path);

		lua.run_file(lua_conf, [&](std::string err) {
			std::cout << "load lua config err: " << err << std::endl;
			bRet = false;
			});
		lua.close();
	}
	//将启动参数转负责覆盖环境变量
	for (int i = 1; i < argc; ++i) {
		std::string argvi = argv[i];
		auto pos = argvi.find("=");
		if (pos != std::string::npos) {
			auto evalue = argvi.substr(pos + 1);
			auto ekey = fmt::format("HIVE_{}", argvi.substr(2, pos - 2));
			std::transform(ekey.begin(), ekey.end(), ekey.begin(), [](auto c) { return std::toupper(c); });
			setenv(ekey.c_str(), evalue.c_str(), 1);
			continue;
		}
	}
	//设置默认参数
	if (lua_conf) {
		setenv("HIVE_SERVICE", "hive", 0);
		setenv("HIVE_INDEX", "1", 0);
		setenv("HIVE_HOST_IP", "127.0.0.1", 0);
	}
	//默认lib目录
#if defined(__linux) || defined(__APPLE__)
	setenv("LUA_CPATH", "./lib/?.so;", 0);
#else
	setenv("LUA_CPATH", "!/lib/?.dll;", 0);
#endif

	return bRet;
}

void hive_app::run() {
	if ((std::stoi(get_environ_def("HIVE_DAEMON", "0")))) {
		daemon();
		log_service::instance()->daemon(true);
	}
	luakit::kit_state lua;
	lua.set("platform", get_platform());

	open_custom_libs(lua.L());//添加扩展库
	auto hive = lua.new_table("hive");
	hive.set("pid", ::getpid());
	hive.set("logtag", "[hive]");
	hive.set("platform", get_platform());
	
	hive.set_function("get_signal", [&]() { return m_signal; });
	hive.set_function("set_signal", [&](int n) { set_signal(n); });
	hive.set_function("ignore_signal", [](int n) { signal(n, SIG_IGN); });
	hive.set_function("default_signal", [](int n) { signal(n, SIG_DFL); });
	hive.set_function("register_signal", [](int n) { signal(n, on_signal); });
	//begin worker操作接口
	hive.set_function("worker_update", [&](size_t to) { m_schedulor.update(); });
	hive.set_function("worker_setup", [&](lua_State* L, std::string service) {
		m_schedulor.setup(L, service);
		return 0;
		});
	hive.set_function("worker_startup", [&](std::string name, std::string entry) {
		return m_schedulor.startup(name, entry);
		});
	hive.set_function("worker_call", [&](std::string name, slice* buf) {
		if (buf == nullptr)return false;
		return m_schedulor.call(name, buf);
		});
	hive.set_function("worker_shutdown", [&]() { m_schedulor.shutdown(); });
	//end worker接口

	lua.run_script(g_sandbox, [&](std::string err) {
		exception_handler("load sandbox err: ", err);
		});
	
	lua.run_script(fmt::format("require '{}'", getenv("HIVE_ENTRY")), [&](std::string err) {
		exception_handler(fmt::format("load entry [{}] err: ", getenv("HIVE_ENTRY")), err);
		});
	while (hive.get_function("run")) {
		hive.call([&](std::string err) {
			LOG_FATAL(fmt::format("hive run err: {} ", err));
			});
	}
	if (hive.get_function("exit")) {
		hive.call([&](std::string err) {
			LOG_FATAL(fmt::format("hive exit err: {} ", err));
			});
	}
	m_schedulor.shutdown();
	std::this_thread::sleep_for(std::chrono::milliseconds(1000));
	lua.close();
	log_service::instance()->stop();
}
