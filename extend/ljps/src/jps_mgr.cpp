
#include "jps_mgr.h"
#include <functional>

CJpsMgr::CJpsMgr(){}
CJpsMgr::~CJpsMgr() {}

bool CJpsMgr::init(unsigned w_, unsigned h_, std::string data)
{
    if (!map.init(w_,h_,data))
    {
        return false;
    }
    m_search = std::make_shared<JPS::Searcher<MapGrid>>(map);
    return true;
}

int CJpsMgr::find_path(lua_State* L, int sx, int sy, int ex, int ey)
{
    auto btime = cur_time();
    std::vector<JPS::Position> path;
    auto ret = m_search->findPath(path, JPS::Pos(sx, sy), JPS::Pos(ex, ey), 0);
    auto cost_time = cur_time() - btime;
    if (m_debug) {
        std::cout << "start: " << sx << "," << sy << " end: " << ex << "," << ey << std::endl;
        std::cout << "path found result:" << ret << std::endl;
        map.print_path(path);
        std::cout << std::endl << "cost time:" << cost_time << " nodes expanded:" << m_search->getNodesExpanded() << " memory used:" << m_search->getTotalMemoryInUse() << " bytes"<< std::endl;
    }
    lua_newtable(L);
    for (size_t i = 0; i < path.size(); i++)
    {
        lua_newtable(L);
        lua_pushinteger(L, path[i].x);
        lua_rawseti(L, -2, 1);
        lua_pushinteger(L, path[i].y);
        lua_rawseti(L, -2, 2);
        lua_rawseti(L, -2, i+1);
    }
    return 1;
}

void CJpsMgr::enable_debug(bool debug)
{
    m_debug = debug;
}



