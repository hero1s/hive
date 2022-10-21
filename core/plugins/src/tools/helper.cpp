#include "helper.h"
#include <algorithm>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <iostream>


#ifdef WIN32
#include <WinSock2.h>
#include <WS2tcpip.h>
#include <conio.h>
#include <windows.h>
#include <psapi.h>  
#include <direct.h>
#include <process.h>

#pragma comment(lib, "WS2_32.lib")
#else
#include <sys/types.h>
#include <sys/socket.h>
#include <fcntl.h>
#include <sys/stat.h>
#include <sys/sysinfo.h>
#include <sys/resource.h>
#include <sys/ioctl.h>
#include <netdb.h>
#include <arpa/inet.h>
#include <net/if.h>
#include <net/if_arp.h>
#include <netdb.h>
#include <netinet/in.h>
#include <unistd.h>
#include <sys/time.h>

inline void closesocket(int fd) { close(fd); }

#endif


namespace tools
{
	struct stIP {
		union {
			uint32_t uiIP;
			uint8_t arIP[4];
		};
	};

	std::string CHelper::GetLanIP()
	{
		std::vector<uint32_t> oIPs;
		if (GetAllHostIPs(oIPs) > 0) {
			for (size_t i = 0; i < oIPs.size(); ++i) {
				if (IsLanIP(oIPs[i])) {
					struct in_addr stAddr;
					stAddr.s_addr = oIPs[i];
					return inet_ntoa(stAddr);
				}
			}
		}
		return "1.1.0.1";
	}

	std::string CHelper::GetNetIP()
	{
		uint32_t uiNetIP = 0;
		std::vector<uint32_t> oIPs;
		if (GetAllHostIPs(oIPs) > 0) {
			for (size_t i = 0; i < oIPs.size(); ++i) {
				if (!IsLanIP(oIPs[i])) {
					if (uiNetIP == 0) {
						uiNetIP = oIPs[i];
					}
					else {
						break;
					}
				}
			}
		}
		struct in_addr stAddr;
		stAddr.s_addr = uiNetIP;
		return inet_ntoa(stAddr);
	}

	bool CHelper::IsHaveNetIP()
	{
		std::vector<uint32_t> oIPs;
		if (GetAllHostIPs(oIPs) > 0) {
			for (size_t i = 0; i < oIPs.size(); ++i) {
				if (!IsLanIP(oIPs[i])) {
					return true;
				}
			}
		}
		return false;
	}

	bool CHelper::IsLanIP(uint32_t uiIP)
	{
		stIP oIP;
		oIP.uiIP = uiIP;
		if (oIP.arIP[0] == 10) // 10.0.0.0 - 10.255.255.255
		{
			return true;
		}
		if (oIP.arIP[0] == 172 && (oIP.arIP[1] >= 16 && oIP.arIP[1] <= 31)) {
			return true;
		}
		if (oIP.arIP[0] == 192 && oIP.arIP[1] == 168) {
			return true;
		}
		if (oIP.arIP[0] == 169 && oIP.arIP[1] == 254) {
			return true;
		}
		return false;
	}

	size_t CHelper::GetAllHostIPs(std::vector<uint32_t>& oIPs)
	{

#ifdef WIN32
		char hostName[128] = { 0 };
		WSAData data;
		if (WSAStartup(MAKEWORD(2, 1), &data) != 0)
		{
			std::cout << "startup WSA faild" << std::endl;
		}
		int32_t ret = gethostname(hostName, 128);

		addrinfo hints;
		memset(&hints, 0, sizeof(addrinfo));
		addrinfo* addr = NULL;
		if (ret == 0)
		{
			getaddrinfo(hostName, NULL, &hints, &addr);
		}
		addrinfo* addrInfo = addr;
		while (addrInfo != NULL)
		{
			std::string sockAddr;
			if (addrInfo->ai_family == AF_INET || addrInfo->ai_family == PF_INET)
			{
				sockaddr_in addrin = *((sockaddr_in*)addrInfo->ai_addr);
				char* ip = inet_ntoa(addrin.sin_addr);
				//int32_t port = htons(addrin.sin_port);
				sockAddr = ip;
			}
			else
			{
				sockaddr_in6 addrin6 = *((sockaddr_in6*)addrInfo->ai_addr);
				char ip[64] = { 0 };
				getnameinfo((sockaddr*)&addrin6, sizeof(addrin6), ip, 64, NULL, 0, NI_NUMERICHOST);
				//int32_t port = htons(addrin6.sin6_port);

				sockAddr = ip;
			}
			oIPs.push_back(IPToValue(sockAddr));
			addrInfo = addrInfo->ai_next;
		}
		freeaddrinfo(addr);
		WSACleanup();
#else
		enum {
			MAXINTERFACES = 16,
		};
		int fd = 0;
		int intrface = 0;
		struct ifreq buf[MAXINTERFACES];
		struct ifconf ifc;
		if ((fd = socket(AF_INET, SOCK_DGRAM, 0)) >= 0) {
			ifc.ifc_len = sizeof(buf);
			ifc.ifc_buf = (caddr_t)buf;
			if (!ioctl(fd, SIOCGIFCONF, (char*)&ifc)) {
				intrface = ifc.ifc_len / sizeof(struct ifreq);
				while (intrface-- > 0) {
					if (!(ioctl(fd, SIOCGIFADDR, (char*)&buf[intrface]))) {
						uint32_t uiIP = ((struct sockaddr_in*)(&buf[intrface].ifr_addr))->sin_addr.s_addr;
						if (uiIP != 0 && uiIP != inet_addr("127.0.0.1")) {
							oIPs.push_back(uiIP);
						}
					}
				}
			}
		}
		close(fd);
#endif
		std::sort(oIPs.begin(), oIPs.end(), std::greater<uint32_t>());
		return oIPs.size();
	}

	uint32_t CHelper::IPToValue(const std::string& strIP)
	{
		uint32_t a[4];
		std::string IP = strIP;
		std::string strTemp;
		size_t pos;
		size_t i = 3;
		do {
			pos = IP.find(".");
			if (pos != std::string::npos) {
				strTemp = IP.substr(0, pos);
				a[i] = atoi(strTemp.c_str());
				i--;
				IP.erase(0, pos + 1);
			}
			else {
				strTemp = IP;
				a[i] = atoi(strTemp.c_str());
				break;
			}

		} while (1);

		uint32_t nResult = (a[3]) + (a[2] << 8) + (a[1] << 16) + (a[0] << 24);
		return nResult;
	}

	std::string CHelper::ValueToIP(uint32_t ulAddr)
	{
		char strTemp[20];
		memset(strTemp, 0, sizeof(strTemp));
		sprintf(strTemp, "%d.%d.%d.%d", (ulAddr & 0x000000ff), (ulAddr & 0x0000ff00) >> 8, (ulAddr & 0x00ff0000) >> 16, (ulAddr & 0xff000000) >> 24);
		return std::string(strTemp);
	}

	bool CHelper::PortIsUsed(int port)
	{
		int fd = socket(AF_INET, SOCK_STREAM, 0);
		struct sockaddr_in addr;
		addr.sin_family = AF_INET;
		addr.sin_port = htons(port);
		inet_pton(AF_INET, "0.0.0.0", &addr.sin_addr);
		if (bind(fd, (struct sockaddr*)(&addr), sizeof(sockaddr_in)) < 0) {
			closesocket(fd);
			return true;
		}
		closesocket(fd);
		return false;
	}

	std::string CHelper::GetHostByDomain(std::string& domain)
	{
		std::string host_ip;
#ifdef WIN32
		struct hostent* host = gethostbyname(domain.c_str());
		if (host && host->h_addrtype == AF_INET && *(host->h_addr_list) != nullptr) {
			struct in_addr addr;
			addr.s_addr = *(u_long*)(*(host->h_addr_list));
			char* ipAddr = inet_ntoa(addr);
			return std::string(ipAddr);
		}
#else
		struct addrinfo hints;
		memset(&hints, 0, sizeof(struct addrinfo));
		hints.ai_family = AF_UNSPEC;
		hints.ai_flags = AI_CANONNAME;
		hints.ai_socktype = SOCK_STREAM;
		hints.ai_protocol = 0;  /* any protocol */
		struct addrinfo* result, * result_pointer;
		if (getaddrinfo(domain.c_str(), NULL, &hints, &result) == 0) {
			for (result_pointer = result; result_pointer != NULL; result_pointer = result_pointer->ai_next) {
				if (AF_INET == result_pointer->ai_family) {
					char ipAddr[32] = { 0 };
					if (getnameinfo(result_pointer->ai_addr, result_pointer->ai_addrlen, ipAddr, sizeof(ipAddr), nullptr, 0, NI_NUMERICHOST) == 0) {
						host_ip = std::string(ipAddr);
						freeaddrinfo(result);
						return host_ip;
					}
				}
			}
			freeaddrinfo(result);
		}
#endif
		return host_ip;
	}

#ifdef WIN32
	__int64 CompareFileTime(FILETIME time1, FILETIME time2)
	{
		__int64 a = time1.dwHighDateTime << 32 | time1.dwLowDateTime;
		__int64 b = time2.dwHighDateTime << 32 | time2.dwLowDateTime;
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

	int get_cpuoccupy(CPU_OCCUPY* cpust) //对无类型get函数含有一个形参结构体类弄的指针O  
	{
		FILE* fd;
		char buff[256];
		fd = fopen("/proc/stat", "r");
		fgets(buff, sizeof(buff), fd);
		sscanf(buff, "%s %u %u %u %u %u %u %u", cpust->name, &cpust->user, &cpust->nice, &cpust->system, &cpust->idle, &cpust->lowait, &cpust->irq, &cpust->softirq);
		fclose(fd);
		return 0;
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
		static CPU_OCCUPY last;
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
		helper.set_function("get_lan_ip", []() { return CHelper::GetLanIP(); });
		helper.set_function("get_net_ip", []() { return CHelper::GetNetIP(); });
		helper.set_function("ip_to_value", [](std::string ip) { return CHelper::IPToValue(ip); });
		helper.set_function("value_to_ip", [](uint32_t addr) { return CHelper::ValueToIP(addr); });
		helper.set_function("is_lan_ip", [](std::string ip) { return CHelper::IsLanIP(CHelper::IPToValue(ip)); });
		helper.set_function("port_is_used", [](int port) { return CHelper::PortIsUsed(port); });
		helper.set_function("dns", [](std::string domain) { return CHelper::GetHostByDomain(domain); });

		helper.set_function("mem_available", [](lua_State* L) {
			luakit::kit_state kit_state(L);
			double total = 0, available = 0;
			CHelper::MemAvailable(total, available);
			return kit_state.as_return(total, available);
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