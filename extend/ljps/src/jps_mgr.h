#pragma once
#include "jps.hpp"
#include "lua_kit.h"

#include <vector>
#include <cstdio>
#include <iostream>
#include <algorithm>
#include <string>
#include <chrono>
#include <ctime>
#include <memory>
#include <mutex>
#include <thread>
#include <strstream>

//地图数据
class MapGrid
{
public:
    bool init(unsigned w_, unsigned h_, std::string data)
    {
        w = w_;
        h = h_;
        map_data = data;
        if (data.size() < (w*h)){
            std::cout << "the map size is not eq data" << std::endl;
            return false;
        }
        std::cout << "W: " << w << "; H: " << h << "; Total cells: " << (w * h) << " size:"<< data.size() << std::endl;
        return true;
    }
    // Called by JPS to figure out whether the tile at (x, y) is walkable
    inline unsigned operator()(unsigned x, unsigned y) const
    {
        unsigned canwalk = x < w && y < h;
        if (canwalk){
            canwalk = map_data[y+x*h] == '0';
        }
        return canwalk;
    }
    void clear_out()
    {
        out.clear();
        for (unsigned j = 0; j < h; ++j) {
            std::strstream tmp;
            for (unsigned i = 0; i < w; ++i) {
                tmp << (map_data[i + j * h] == '0' ? '.' : '@');
            }
            out.push_back(tmp.str());
        }
    }
    void print_path(std::vector<JPS::Position>& path)
    {
        clear_out();
        unsigned c = 0;
        for (auto it = path.begin();it != path.cend();++it){
            out[it->x][it->y] = (c++ % 26) + 'a';
        }
        for(auto s:out){
            std::cout << s << std::endl;
        }
    }
protected:
    unsigned w, h;
    std::string map_data;
    mutable std::vector<std::string> out;
};

class CJpsMgr
{
public:
	CJpsMgr();
	~CJpsMgr();
    bool init(unsigned w_, unsigned h_, std::string data);
    int find_path(lua_State* L, int sx, int sy, int ex, int ey);
    void enable_debug(bool debug);
    int64_t cur_time() {
        return std::chrono::duration_cast<std::chrono::microseconds>(std::chrono::system_clock::now().time_since_epoch()).count();
    }
private:
    bool m_debug = true;
    MapGrid map;
    std::shared_ptr<JPS::Searcher<MapGrid>> m_search = nullptr;
};

