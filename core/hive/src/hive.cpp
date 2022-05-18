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
#define setenv(k,v,o) _putenv_s(k, v);
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

static int hive_daemon() {
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
    return 0;
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
	return mem / 1024.0 / 1024.0;
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
	return vmrss / 1024.0;// cnvert VmRSS from KB to MB
#endif
}

void hive_app::set_signal(uint32_t n) {
    uint32_t mask = 1 << n;
    m_signal |= mask;
}

void hive_app::setup(int argc, const char* argv[]) {
    srand((unsigned)time(nullptr));
    //初始化日志
    m_logger = std::make_shared<log_service>();
    m_logger->start();
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

const char* hive_app::get_environ(std::string k) {
	auto iter = m_environs.find(k);
	if (iter == m_environs.end()) return nullptr;
	return iter->second.c_str();
}

bool hive_app::load(int argc, const char* argv[]) {
    bool bRet = true;
    luakit::kit_state lua;
    lua.set("platform", get_platform());
    //定义函数

    //设置默认参数
    set_environ("HIVE_SERVICE", "hive");
    set_environ("HIVE_INDEX", "1");
    set_environ("HIVE_HOST_IP", "127.0.0.1");
    //加载LUA配置
	lua.set_function("set_env", [&](std::string k, std::string v) {
		m_environs[k] = v;
	});
	lua.set_function("set_osenv", [&](std::string k, std::string v) {
		m_environs[k] = v;
		setenv(k.c_str(), v.c_str(), 1);
	});

	lua.run_file(argv[1], [&](std::string err) {
		std::cout << err << std::endl;
		bRet = false;
		return;
	});
    //将启动参数转换成环境变量
    for (int i = 2; i < argc; ++i) {
        std::string argvi = argv[i];
        auto pos = argvi.find("=");
        if (pos != std::string::npos) {
            auto evalue = argvi.substr(pos + 1);
            auto ekey = fmt::format("HIVE_{}", argvi.substr(2, pos - 2));
            std::transform(ekey.begin(), ekey.end(), ekey.begin(), [](auto c) { return std::toupper(c); });
            set_environ(ekey, evalue);
        }
    }
    return bRet;
}

void hive_app::init_logger() {
    std::string index = get_environ("HIVE_INDEX");
    std::string service = get_environ("HIVE_SERVICE");
    auto logpath = get_environ_def("HIVE_LOG_PATH", "./logs/");
    auto maxline = std::stoi(get_environ_def("HIVE_LOG_LINE", "100000"));
    auto rolltype = (logger::rolling_type)std::stoi(get_environ_def("HIVE_LOG_ROLL", "1"));
    m_logger->option(logpath, service, index, rolltype, maxline);
    m_logger->add_dest(service);
    if ((std::stoi(get_environ_def("HIVE_DAEMON", "0")) && strcmp(get_platform(),"windows") != 0)) {
        //hive_daemon();
        m_logger->daemon(true);
    }
}

void hive_app::run() {
    init_logger();
    luakit::kit_state lua;
    lua.set("platform", get_platform());
    open_custom_libs(lua.L());//添加扩展库
    auto hive = lua.new_table("hive");
    hive.set("pid", ::getpid());
    hive.set("environs", m_environs);
    hive.set("platform", get_platform());
    hive.set_function("hash_code", hash_code);
    hive.set_function("get_signal", [&]() { return m_signal; });
    hive.set_function("set_signal", [&](int n) { set_signal(n); });
    hive.set_function("get_logger", [&]() { return m_logger.get(); });
    hive.set_function("ignore_signal", [](int n) { signal(n, SIG_IGN); });
    hive.set_function("default_signal", [](int n) { signal(n, SIG_DFL); });
    hive.set_function("register_signal", [](int n) { signal(n, on_signal); });
    hive.set_function("getenv", [&](std::string k) { return get_environ(k); });
    hive.set_function("setenv", [&](std::string k, std::string v) { m_environs[k] = v; });
    hive.set_function("mem_usage", []() { return get_memory_usage(::getpid()); });

	lua.run_script(fmt::format("require '{}'", get_environ_def("HIVE_SANDBOX","sandbox")), [&](std::string err) {
		exception_handler("load sandbox err: ", err);
		});
	lua.run_script(fmt::format("require '{}'", get_environ("HIVE_ENTRY")), [&](std::string err) {
		exception_handler("load entry err: ", err);
		});
	while (hive.get_function("run")) {
        hive.call([&](std::string err) {
			exception_handler("hive run err: ", err);
			});
		check_input(lua);
	}
	lua.close();
	m_logger->stop();
}
