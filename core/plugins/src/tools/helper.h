#pragma once
#include <vector>
#include <string>
#include <iostream>
#include "lua_kit.h"

namespace tools
{
    class CHelper
    {
    public:
        static std::string GetLanIP();        
        static std::string GetNetIP();
        static bool IsHaveNetIP();
        static bool IsLanIP(uint32_t uiIP);
        static size_t GetAllHostIPs(std::vector<uint32_t>& oIPs);
        static uint32_t IPToValue(const std::string& strIP);
        static std::string ValueToIP(uint32_t ulAddr);
        static void serialize(lua_State* L, std::string& buf, int index, int depth, int line);
    private:

    };

}

