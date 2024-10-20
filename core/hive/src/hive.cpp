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

static std::string add_lua_cpath(vstring path) {
	auto p = getenv("LUA_CPATH");
	std::string cur_path = (p != NULL) ? p : "";
#ifdef WIN32
	cur_path.append("!/").append(path).append("?.dll;");
#else
	cur_path.append(path).append("?.so;");
#endif // #if WIN32	
	setenv("LUA_CPATH", cur_path.c_str(), 1);
	return cur_path;
}

static std::string add_lua_path(vstring path) {
	auto p = getenv("LUA_PATH");
	std::string cur_path = (p != NULL) ? p : "";
#ifdef WIN32
	cur_path.append("!/");
#endif // #if WIN32
	cur_path.append(path).append("?.lua;");
	setenv("LUA_PATH", cur_path.c_str(), 1);
	return cur_path;
}

static std::string compiler_info() {
#ifdef _MSC_VER
	return fmt::format("Compiler:MSVC {}", _MSC_VER);
#elif __GNUC__
	return fmt::format("Compiler:GCC {}.{}.{}", __GNUC__, __GNUC_MINOR__, __GNUC_PATCHLEVEL__);
#elif __clang__
	return fmt::format("Compiler:Clang {}.{}.{}", __clang_major__, __clang_minor__, __clang_patchlevel__);
#endif // _MSC_VER
	return fmt::format("Compiler:Unknown");
}


void hive_app::set_signal(uint32_t n, bool b) {
	uint32_t mask = 1 << n;
	if (b) {
		m_signal |= mask;
	} else {
		m_signal ^= mask;
	}
}

const char* hive_app::get_env(const char* key) {
	return getenv(key);
}

void hive_app::set_env(std::string key, std::string value, int over) {
	if (over == 1 || m_environs.find(key) == m_environs.end()) {
		setenv(key.c_str(), value.c_str(), 1);
		m_environs[key] = value;
	}
}

void hive_app::init_default_log(int rtype) {
	if (rtype != 0)return;//仅服务模式初始化文件日志

	auto index = get_environ_def("HIVE_INDEX", "1");
	auto service_name = get_environ_def("HIVE_SERVICE", "hive");
	auto path = get_environ_def("HIVE_LOG_PATH", "./logs/");
	
	log_service::instance()->option(path, service_name, index);
	log_service::instance()->add_dest(service_name, "");
}

void hive_app::setup(int argc, const char* argv[]) {
	srand((unsigned)time(nullptr));
	//加载配置
	auto iRet = load(argc, argv);
	if (iRet >= 0) {
		run(iRet);
	}
}

void hive_app::exception_handler(const std::string& err_msg) {
	LOG_FATAL(err_msg.c_str());
	log_service::instance()->stop();
	std::this_thread::sleep_for(std::chrono::seconds(1));
	exit(1);
}

int hive_app::load(int argc, const char* argv[]) {
	int iRet = 1;// -1失败，0服务，1工具
	//将启动参数转负责覆盖环境变量
	const char* lua_conf = nullptr;
	if (argc > 1) {
		std::string argvi = argv[1];
		if (argvi.find("=") == std::string::npos) {
			lua_conf = argv[1];
			iRet = 0;
			m_lua_conf = lua_conf;
		}
	}
	//加载LUA配置
	if (lua_conf) {		
		iRet = load_conf(iRet, false);
	}
	//将启动参数转负责覆盖环境变量
	for (int i = 1; i < argc; ++i) {
		std::string argvi = argv[i];
		auto pos = argvi.find("=");
		if (pos != std::string::npos) {
			auto evalue = argvi.substr(pos + 1);
			auto ekey = fmt::format("HIVE_{}", argvi.substr(2, pos - 2));
			std::transform(ekey.begin(), ekey.end(), ekey.begin(), [](auto c) { return std::toupper(c); });
			set_env(ekey.c_str(), evalue.c_str(), 1);
			m_cmd_environs[ekey] = evalue;
			continue;
		}
	}

	//检测缺失参数
	if (getenv("HIVE_ENTRY") == NULL) {
		std::cout << "HIVE_ENTRY is null" << std::endl;
		iRet = -1;
	}
	return iRet;
}

int hive_app::load_conf(int iRet, bool reload) {
	luakit::kit_state lua;
	lua.set("platform", get_platform());
	lua.set_function("set_env", [&](std::string key, std::string value) {
			if (reload) {
				if (m_cmd_environs.find(key) != m_cmd_environs.end())return;				
			}
			return set_env(key, value, 1); 
		});
	lua.set_function("add_lua_path", add_lua_path);
	lua.set_function("add_lua_cpath", add_lua_cpath);

	lua.run_file(m_lua_conf, [&](vstring err) {
		std::cout << "load lua config err: " << err << std::endl;
		iRet = -1;
		});
	lua.close();

	//设置默认参数
	if (!reload) {
		set_env("HIVE_SERVICE", "hive", 0);
		set_env("HIVE_INDEX", "1", 0);
		set_env("HIVE_HOST_IP", "127.0.0.1", 0);
	}
	
	return iRet;
}

void hive_app::reload_conf(std::vector<std::string>& diff_keys) {
	MAP_ENV olds = m_environs;
	load_conf(0, true);
	for (auto [k, v] : m_environs) {
		if (olds[k] != v) {
			diff_keys.push_back(k);
		}
	}
}

void hive_app::run(int rtype) {
	if ((std::stoi(get_environ_def("HIVE_DAEMON", "0")))) {
		daemon();
		log_service::instance()->daemon(true);
	}
	luakit::kit_state lua;
	lua.set("platform", get_platform());
	lua.set_function("set_env", [&](std::string key, std::string value) { return set_env(key, value, 1); });

	open_custom_libs(lua.L());//添加扩展库
	auto hive = lua.new_table("hive");
	hive.set("pid", ::getpid());
	hive.set("title", "hive");
	hive.set("platform", get_platform());
	
	hive.set_function("get_signal", [&]() { return m_signal; });
	hive.set_function("set_signal", [&](int n, bool b) { set_signal(n, b); });
	hive.set_function("ignore_signal", [](int n) { signal(n, SIG_IGN); });
	hive.set_function("default_signal", [](int n) { signal(n, SIG_DFL); });
	hive.set_function("register_signal", [](int n) { signal(n, on_signal); });
	hive.set_function("getenv", [&](const char* key) { return get_env(key); });
	hive.set_function("setenv", [&](std::string key, std::string value) { return set_env(key, value, 1); });
	hive.set_function("environs", [&]() { return m_environs; });
	hive.set_function("reload_env", [&]() { std::vector<std::string> diffs; reload_conf(diffs); return diffs; });

	//begin worker操作接口
	hive.set_function("worker_update", [&](uint64_t clock_ms) { m_schedulor.update(clock_ms); });
	hive.set_function("worker_shutdown", [&]() { m_schedulor.shutdown(); });
	hive.set_function("worker_broadcast", [&](lua_State* L) { return m_schedulor.broadcast(L); });
	hive.set_function("worker_setup", [&](lua_State* L, vstring service) {
		m_schedulor.setup(L, service);
		return 0;
		});
	hive.set_function("worker_startup", [&](vstring name, vstring entry, vstring incl) {
		return m_schedulor.startup(name, entry, incl);
		});
	hive.set_function("worker_call", [&](lua_State* L, vstring name) {
		size_t data_len;
		uint8_t* data = m_schedulor.encode(L, data_len);
		return m_schedulor.call(L, name, data, data_len);
		});
	hive.set_function("worker_names", [&]() { return m_schedulor.workers(); });
	//end worker接口
	
	init_default_log(rtype);
	LOG_INFO(fmt::format("hive engine run.build in[{}] time:{} {}", compiler_info(), __DATE__, __TIME__));

	lua.run_script(g_sandbox, [&](vstring err) {
		exception_handler(fmt::format("load sandbox err:{}", err));
		});	
	lua.run_script(fmt::format("require '{}'", getenv("HIVE_ENTRY")), [&](vstring err) {
		exception_handler(fmt::format("load entry [{}] err:{}", getenv("HIVE_ENTRY"), err));
		});
	
	while (hive.get_function("run")) {
		hive.call([&](vstring err) {
			LOG_FATAL(fmt::format("hive run err: {} ", err));
			});
	}
	if (hive.get_function("exit")) {
		hive.call([&](vstring err) {
			LOG_FATAL(fmt::format("hive exit err: {} ", err));
			});
	}
	m_schedulor.shutdown();
	std::this_thread::sleep_for(std::chrono::seconds(2));
	//lua.close(); todo 优化析构逻辑
	log_service::instance()->stop();
}
