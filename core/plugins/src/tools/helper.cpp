#include "helper.h"
#include <algorithm>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <iostream>


#ifdef WIN32
#include <conio.h>
#include <windows.h>
#include <psapi.h>  
#include <direct.h>
#include <process.h>
#else
#include <sys/types.h>
#include <fcntl.h>
#include <sys/stat.h>
#include <sys/sysinfo.h>
#include <sys/resource.h>
#include <sys/ioctl.h>
#include <unistd.h>
#include <sys/time.h>
#endif


namespace tools
{
#ifdef WIN32
	__int64 CompareFileTime(FILETIME time1, FILETIME time2)
	{
		__int64 a = (__int64)time1.dwHighDateTime << 32 | time1.dwLowDateTime;
		__int64 b = (__int64)time2.dwHighDateTime << 32 | time2.dwLowDateTime;
		return (b - a);
	}
#else
	typedef struct MEMPACKED //定义一个mem occupy的结构体  
	{
		char name1[20];
		unsigned long Total;
		char name2[20];
	}MEM_OCCUPY;

	typedef struct CPUPACKED         //定义一个cpu occupy的结构体  
	{
		char name[20];      //定义一个char类型的数组名name有20个元素  
		unsigned int user; //定义一个无符号的int类型的user  
		unsigned int nice; //定义一个无符号的int类型的nice  
		unsigned int system;//定义一个无符号的int类型的system  
		unsigned int idle; //定义一个无符号的int类型的idle  
		unsigned int lowait;
		unsigned int irq;
		unsigned int softirq;
	}CPU_OCCUPY;

	void get_cpuoccupy(CPU_OCCUPY* cpust) //对无类型get函数含有一个形参结构体类弄的指针O  
	{
		FILE* fd;
		char buff[256];
		fd = fopen("/proc/stat", "r");
		fgets(buff, sizeof(buff), fd);
		sscanf(buff, "%s %u %u %u %u %u %u %u", cpust->name, &cpust->user, &cpust->nice, &cpust->system, &cpust->idle, &cpust->lowait, &cpust->irq, &cpust->softirq);
		fclose(fd);
	}
	double cal_cpuoccupy(CPU_OCCUPY* o, CPU_OCCUPY* n)
	{
		unsigned long od, nd;
		double cpu_use = 0;
		od = (unsigned long)(o->user + o->nice + o->system + o->idle + o->lowait + o->irq + o->softirq);//第一次(用户+优先级+系统+空闲)的时间再赋给od  
		nd = (unsigned long)(n->user + n->nice + n->system + n->idle + n->lowait + n->irq + n->softirq);//第二次(用户+优先级+系统+空闲)的时间再赋给nd  
		auto sum = nd - od;
		if (sum != 0) {
			double idle = n->idle - o->idle;
			cpu_use = 100.00 - idle / sum * 100.00;
		}
		return cpu_use;
	}
#endif
	//可用内存
	void CHelper::MemAvailable(double& total, double& available)
	{
#ifdef WIN32
		MEMORYSTATUS ms;
		::GlobalMemoryStatus(&ms);
		total = ms.dwTotalPhys / 1024 / 1024;
		available = ms.dwAvailPhys / 1024 / 1024;
#else
		FILE* fd;
		MEM_OCCUPY m;
		char buff[256];
		fd = fopen("/proc/meminfo", "r");
		//从fd文件中读取长度为buff的字符串再存到起始地址为buff这个空间里   
		fgets(buff, sizeof(buff), fd);
		sscanf(buff, "%s %lu %s\n", m.name1, &m.Total, m.name2);
		total = m.Total / 1024;
		fgets(buff, sizeof(buff), fd);
		sscanf(buff, "%s %lu %s\n", m.name1, &m.Total, m.name2);
		double mem_free = m.Total;
		fgets(buff, sizeof(buff), fd);
		sscanf(buff, "%s %lu %s\n", m.name1, &m.Total, m.name2);
		available = m.Total / 1024;
		fclose(fd);     //关闭文件fd  
#endif // WIN32
	}
	double CHelper::CpuUsePercent()
	{
#ifdef WIN32
		return 1;
#else
		static thread_local CPU_OCCUPY last;
		CPU_OCCUPY cur;
		get_cpuoccupy(&cur);
		auto cpu_use = cal_cpuoccupy(&last, &cur);
		last = cur;
		return cpu_use;
#endif
	}

	float CHelper::MemUsage(int pid) {
#ifdef WIN32
		uint64_t mem = 0;
		PROCESS_MEMORY_COUNTERS pmc;
		HANDLE process = OpenProcess(PROCESS_ALL_ACCESS, FALSE, pid);
		if (process == NULL)return 0;

		if (GetProcessMemoryInfo(process, &pmc, sizeof(pmc))) {
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
	int CHelper::CpuCoreNum() {
#ifdef WIN32
		SYSTEM_INFO info;
		GetSystemInfo(&info);
		return info.dwNumberOfProcessors;
#else
		return get_nprocs();
#endif
	}

	luakit::lua_table open_lhelper(lua_State* L) {
		luakit::kit_state lua(L);
		auto helper = lua.new_table();

		helper.set_function("mem_available", [](lua_State* L) {
			double total = 0, available = 0;
			CHelper::MemAvailable(total, available);
			return luakit::variadic_return(L, total, available);
			});
		helper.set_function("cpu_use_percent", []() { return CHelper::CpuUsePercent(); });
		helper.set_function("cpu_core_num", []() { return CHelper::CpuCoreNum(); });
		helper.set_function("mem_usage", []() { return CHelper::MemUsage(::getpid()); });

		return helper;
	}
}

extern "C"
{
	LUAMOD_API int luaopen_lhelper(lua_State* L) {
		return tools::open_lhelper(L).push_stack();
	}
}