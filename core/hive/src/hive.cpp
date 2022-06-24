#include <locale>
#include <stdlib.h>
#include <signal.h>
#include <functional>
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

static void check_input(luakit::kit_state& lua) {
#ifdef WIN32
    if (_kbhit()) {
        char cur = _getch();
        if (cur == '\xE0' || cur == '\x0') {
            if (_kbhit()) {
                _getch();
                return;
            }
        }
        lua.run_script(fmt::format("hive.console({:d})", cur));
    }
#endif
}

static int hash_code(lua_State* L) {
    size_t hcode = 0;
    int type = lua_type(L, 1);
    if (type == LUA_TNUMBER) {
        hcode = std::hash<int64_t>{}(lua_tointeger(L, 1));
    }
    else if (type == LUA_TSTRING) {
        hcode = std::hash<std::string>{}(lua_tostring(L, 1));
    }
    else {
        luaL_error(L, fmt::format("hashkey only support number or string!,not support:{}", lua_typename(L, type)).c_str());
    }
    size_t mod = luaL_optinteger(L, 2, 0);
    if (mod > 0) {
        hcode = (hcode % mod) + 1;
    }
    lua_pushinteger(L, hcode);
    return 1;
}

// get specific process physical memeory occupation size by pid (MB)
float get_memory_usage(int pid)
{
#ifdef WIN32
	uint64_t mem = 0;
	PROCESS_MEMORY_COUNTERS pmc;
	HANDLE process = OpenProcess(PROCESS_ALL_ACCESS, FALSE, pid);
	if (GetProcessMemoryInfo(process, &pmc, sizeof(pmc))){
		mem = pmc.WorkingSetSize;
	}
	CloseHandle(process);
	return float(mem / 1024.0 / 1024.0);
#else
#define VMRSS_LINE 22
	char file_name[64] = { 0 };
	FILE* fd;
	char line_buff[512] = { 0 };
	sprintf(file_name, "/proc/%d/status", pid);
	fd = fopen(file_name, "r");
	if (nullptr == fd)return 0;
	char name[64];
	int vmrss = 0;
	for (int i = 0; i < VMRSS_LINE - 1; i++)
		fgets(line_buff, sizeof(line_buff), fd);
	fgets(line_buff, sizeof(line_buff), fd);
	sscanf(line_buff, "%s %d", name, &vmrss);
	fclose(fd);
	return float(vmrss / 1024.0);// cnvert VmRSS from KB to MB
#endif
}

int get_cpu_core_num()
{
#ifdef WIN32
	SYSTEM_INFO info;
	GetSystemInfo(&info);
	return info.dwNumberOfProcessors;
#else
	return get_nprocs();
#endif
}


static int lset_env(lua_State* L) {
	const char* key = lua_tostring(L, 1);
	const char* value = lua_tostring(L, 2);
	auto overwrite = luaL_optinteger(L, 3, 1);
	setenv(key, value, int(overwrite));
	return 0;
}

void hive_app::set_signal(uint32_t n) {
    uint32_t mask = 1 << n;
    m_signal |= mask;
}

void hive_app::setup(int argc, const char* argv[]) {
    srand((unsigned)time(nullptr));
    //初始化日志
    m_logger = new log_service();
    //加载配置
    if (load(argc, argv)) {
        run();
    }
}

void hive_app::exception_handler(std::string msg, std::string& err) {
	LOG_FATAL(m_logger) << msg << err;
	m_logger->stop();
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
	setenv("HIVE_SANDBOX", "sandbox", 1);
	setenv("HIVE_SERVICE", "hive", 0);
	setenv("HIVE_INDEX", "1", 0);
	setenv("HIVE_HOST_IP", "127.0.0.1", 0);
    return bRet;
}

void hive_app::run() {
	if ((std::stoi(get_environ_def("HIVE_DAEMON", "0")))) {
		daemon();
	}
	m_logger->start();
    luakit::kit_state lua;
    lua.set("platform", get_platform());	

    open_custom_libs(lua.L());//添加扩展库
    auto hive = lua.new_table("hive");
    hive.set("pid", ::getpid());
    hive.set("platform", get_platform());
	hive.set("cpu_core_num", get_cpu_core_num());

    hive.set_function("hash_code", hash_code);
    hive.set_function("get_signal", [&]() { return m_signal; });
    hive.set_function("set_signal", [&](int n) { set_signal(n); });
    hive.set_function("get_logger", [&]() { return m_logger; });
    hive.set_function("ignore_signal", [](int n) { signal(n, SIG_IGN); });
    hive.set_function("default_signal", [](int n) { signal(n, SIG_DFL); });
    hive.set_function("register_signal", [](int n) { signal(n, on_signal); });
    hive.set_function("mem_usage", []() { return get_memory_usage(::getpid()); });
	
	lua.run_script(fmt::format("require '{}'", getenv("HIVE_SANDBOX")), [&](std::string err) {
		exception_handler("load sandbox err: ", err);
		});
	lua.run_script(fmt::format("require '{}'", getenv("HIVE_ENTRY")), [&](std::string err) {
		exception_handler("load entry err: ", err);
		});
	while (hive.get_function("run")) {
        hive.call([&](std::string err) {
			LOG_FATAL(m_logger) << "hive run err: " << err;
			});
		check_input(lua);
	}
	m_logger->stop();
	lua.close();
	m_logger = nullptr;
	//todo 这里m_logger已经在lua中gc了 后续优化 todo
}
