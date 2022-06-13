#include "helper.h"
#include <algorithm>

#ifdef WIN32
#include <WinSock2.h>
#include <WS2tcpip.h>

#pragma comment(lib, "WS2_32.lib")
#else
#include <sys/types.h>
#include <sys/socket.h>
#include <sys/stat.h>
#include <sys/resource.h>
#include <sys/ioctl.h>
#include <netdb.h>
#include <arpa/inet.h>
#include <net/if.h>
#include <net/if_arp.h>
#include <netdb.h>
#include <netinet/in.h>
#include <unistd.h>

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


#define MAX_DEPTH  16

#define SERIALIZE_VALUE(buf, val) buf.append(val, strlen(val))
#define SERIALIZE_QUOTE(buf, val, l, r)\
SERIALIZE_VALUE(buf, l); \
SERIALIZE_VALUE(buf, val); \
SERIALIZE_VALUE(buf, r);
#define SERIALIZE_UDATA(buf, val) SERIALIZE_QUOTE(buf, val ? val : "userdata(null)", "'", "'")
#define SERIALIZE_CRCN(buf, cnt, line) {\
    if(line > 0) {\
        buf.append("\n", 1);\
        for(int i = 0; i < cnt - 1; ++i) {\
            buf.append("\t", 1);\
        }\
    }\
}

	void serialize_table(lua_State* L, std::string& buf, int index, int depth, int line) {
		if (index < 0) {
			index = lua_gettop(L) + index + 1;
		}
		int size = 0;
		lua_pushnil(L);
		SERIALIZE_VALUE(buf, "{");
		SERIALIZE_CRCN(buf, depth, line);
		while (lua_next(L, index) != 0) {
			if (size++ > 0) {
				SERIALIZE_VALUE(buf, ",");
				SERIALIZE_CRCN(buf, depth, line);
			}
			if (lua_isnumber(L, -2)) {
				lua_pushnil(L);
				lua_copy(L, -3, -1);
				SERIALIZE_QUOTE(buf, lua_tostring(L, -1), "[", "]=");
				lua_pop(L, 1);
			}
			else if (lua_type(L, -2) == LUA_TSTRING) {
				SERIALIZE_VALUE(buf, lua_tostring(L, -2));
				SERIALIZE_VALUE(buf, "=");
			}
			else {
                CHelper::serialize(L, buf, -2, depth, line);
			}
            CHelper::serialize(L, buf, -1, depth, line);
			lua_pop(L, 1);
		}
		SERIALIZE_CRCN(buf, depth - 1, line);
		SERIALIZE_VALUE(buf, "}");
	}

	void CHelper::serialize(lua_State* L, std::string& buf, int index, int depth, int line) {
		if (depth > MAX_DEPTH) {
			luaL_error(L, "serialize can't pack too depth table");
		}
		int type = lua_type(L, index);
		switch (type) {
		case LUA_TNIL:
			SERIALIZE_VALUE(buf, "nil");
			break;
		case LUA_TBOOLEAN:
			SERIALIZE_VALUE(buf, lua_toboolean(L, index) ? "true" : "false");
			break;
		case LUA_TSTRING:
			SERIALIZE_QUOTE(buf, lua_tostring(L, index), "'", "'");
			break;
		case LUA_TNUMBER:
			SERIALIZE_VALUE(buf, lua_tostring(L, index));
			break;
		case LUA_TTABLE:
			serialize_table(L, buf, index, depth + 1, line);
			break;
		case LUA_TUSERDATA:
		case LUA_TLIGHTUSERDATA:
			SERIALIZE_UDATA(buf, lua_tostring(L, index));
			break;
		default:
			SERIALIZE_QUOTE(buf, lua_typename(L, type), "'unsupport(", ")'");
			break;
		}
	}

	int lserialize(lua_State* L) {
		static std::string binary;
        binary.clear();// 线程不安全,多线程导出序列化对象
		CHelper::serialize(L, binary, 1, 1, luaL_optinteger(L, 2, 0));
		lua_pushlstring(L, binary.c_str(), binary.length());
		return 1;
	}

    luakit::lua_table open_lhelper(lua_State* L) {
        luakit::kit_state lua(L);
        auto helper = lua.new_table();
        helper.set_function("get_lan_ip", []() { return CHelper::GetLanIP(); });
        helper.set_function("get_net_ip", []() { return CHelper::GetNetIP(); });
        helper.set_function("ip_to_value", [](std::string ip) { return CHelper::IPToValue(ip); });
        helper.set_function("value_to_ip", [](uint32_t addr) { return CHelper::ValueToIP(addr); });
        helper.set_function("serialize", lserialize);

        return helper;
    }
}


extern "C"
{
    int LUAMOD_API luaopen_lhelper(lua_State* L) {
        return tools::open_lhelper(L).push_stack();
    }
}