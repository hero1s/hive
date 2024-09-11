#pragma once

#include <set>
#include <list>
#include <string>
#include <chrono>
#include <unordered_map>
#include <math.h>

#include "lua_kit.h"

using namespace std;
using namespace luakit;
using namespace std::chrono;

using cpchar = const char*;

namespace lprofile {
    
    static thread_local bool t_profilable = false;

    struct call_frame {
        bool inlua = true;
        bool tail = false;
        cpchar name = nullptr;
        cpchar source = nullptr;
        uint32_t line = 0;
        uint64_t pointer = 0;
        uint64_t sub_cost = 0;
        uint64_t call_tick = 0;
    };

    struct call_info {
        lua_State* co = nullptr;
        uint64_t leave_tick = 0;
        list<call_frame> call_list;
    };

    class eval_data {
    public:
        //自定义比较函数
        bool operator<(const eval_data& b) const {
            if (total_time == b.total_time) return pointer > b.pointer;
            return total_time > b.total_time;
        }

        bool inlua = true;
        uint32_t line = 0;
        uint64_t min_time = 0;
        uint64_t max_time = 0;
        uint64_t pointer = 0;
        uint64_t call_tick = 0;
        uint64_t call_count = 0;
        uint64_t total_time = 0;
        cpchar source = nullptr;
        cpchar name = nullptr;
    };

    class profile {
    public:
        void enable() {
            t_profilable = true;
        }

        void disable() {
            t_profilable = false;
        }

        int ignore(lua_State* L, cpchar key) {
            lua_guard g(L);
            lua_getglobal(L, key);
            if (lua_istable(L, -1)) {
                lua_pushnil(L);
                while (lua_next(L, -2) != 0) {
                    if (lua_isfunction(L, -1)) {
                        char buf[CHAR_MAX] = {};
                        snprintf(buf, CHAR_MAX, "%s.%s", key, lua_tostring(L, -2));
                        uint64_t pointer = (uint64_t)lua_topointer(L, -1);
                        m_ignore_funcs.emplace(pointer, buf);
                    }
                    lua_pop(L, 1);
                }
                return 0;
            }
            if (lua_isfunction(L, -1)) {
                uint64_t pointer = (uint64_t)lua_topointer(L, -1);
                m_ignore_funcs.emplace(pointer, key);
            }
            return 0;
        }

        void ignore_file(cpchar filename) {
            m_ignore_files.emplace(filename, true);
        }

        void ignore_func(cpchar funcname) {
            m_ignore_names.emplace(funcname, true);
        }

        int watch(lua_State* L) {
            cpchar name = lua_tolstring(L, 1, nullptr);
            if (lua_type(L, 2) == LUA_TTABLE) {
                lua_getfield(L, 2, name);
                if (lua_isfunction(L, -1)) {
                    uint64_t pointer = (uint64_t)lua_topointer(L, -1);
                    m_watch_funcs.emplace(pointer, name);
                }
                return 0;
            }
            m_watch_files.emplace(name, true);
            return 0;
        }

        int hook(lua_State* L) {
            auto luahook = [](lua_State* DL, lua_Debug* ar) {
                if (!t_profilable) return;
                lua_guard g(DL);
                lua_getfield(DL, LUA_REGISTRYINDEX, "profile");
                profile* prof = (profile*)lua_touserdata(DL, -1);
                if (prof) prof->prof_hook(DL, ar);
            };
            lua_guard g(L);
            lua_getglobal(L, "coroutine");
            lua_push_function(L, [&](lua_State* L) -> int {
                luaL_checktype(L, 1, LUA_TFUNCTION);
                lua_State* NL = lua_newthread(L);
                lua_pushvalue(L, 1);  /* move function to top */
                lua_sethook(NL, luahook, LUA_MASKCALL | LUA_MASKRET, 0);
                lua_xmove(L, NL, 1);  /* move function from L to NL */
                return 1;
            });
            lua_setfield(L, -2, "create");
            //save profile context
            lua_pushlightuserdata(L, this);
            lua_setfield(L, LUA_REGISTRYINDEX, "profile");
            //init lua ignore
            init_lua_ignore(L);
            //hook self
            lua_sethook(L, luahook, LUA_MASKCALL | LUA_MASKRET, 0);
            return 0;
        }

        int dump(lua_State* L, int top = 0) {
            set<eval_data> evals;
            for (auto& [_, data] : m_evals) {                
                evals.insert(data);
            }
            int i = 1;
            lua_newtable(L);
            for (auto& data : evals) {
                lua_newtable(L);
                native_to_lua(L, data.name);
                lua_setfield(L, -2, "name");
                native_to_lua(L, data.line);
                lua_setfield(L, -2, "line");
                native_to_lua(L, data.source);
                lua_setfield(L, -2, "src");
                native_to_lua(L, data.inlua ? "L" : "C");
                lua_setfield(L, -2, "flag");
                native_to_lua(L, round(data.total_time / data.call_count) / 1000);
                lua_setfield(L, -2, "avg");
                native_to_lua(L, round(data.total_time * 1000 / m_all_times) / 10);
                lua_setfield(L, -2, "per");
                native_to_lua(L, double(data.min_time) / 1000);
                lua_setfield(L, -2, "min");
                native_to_lua(L, double(data.max_time) / 1000);
                lua_setfield(L, -2, "max");
                native_to_lua(L, double(data.total_time) / 1000);
                lua_setfield(L, -2, "all");
                native_to_lua(L, data.call_count);
                lua_setfield(L, -2, "count");
                lua_seti(L, -2, i++);
                if (top > 0 && i >= top) break;
            }
            m_evals.clear();
            return 1;
        }

    protected:
        void prof_hook(lua_State* L, lua_Debug* arv) {
            uint64_t co_cost = 0;
            uint64_t nowtick = now();
            call_info* old_ci = m_cur_ci;
            if (old_ci && old_ci->co != L) {
                old_ci->leave_tick = nowtick;
            }
            auto it = m_call_infos.find(L);
            if (it == m_call_infos.end()) {
                m_cur_ci = new call_info{ L };
                m_call_infos.emplace(L, m_cur_ci);
            } else {
                m_cur_ci = it->second;
                if (old_ci != m_cur_ci && m_cur_ci->leave_tick > 0) {
                    co_cost = nowtick - m_cur_ci->leave_tick;
                }
            }
            if (arv->event == LUA_HOOKCALL || arv->event == LUA_HOOKTAILCALL) {
                lua_Debug ar;
                lua_getstack(L, 0, &ar);
                lua_getinfo(L, "nSlf", &ar);
                call_frame frame;
                frame.source = ar.source;
                frame.line = ar.linedefined;
                if (ar.what[0] == 'C') {
                    frame.inlua = false;
                    lua_Debug arv;
                    int i = 0;
                    while (true) {
                        if (!lua_getstack(L, ++i, &arv)) break;
                        lua_getinfo(L, "Sl", &arv);
                        if (arv.what[0] != 'C') {
                            frame.line = arv.currentline;
                            frame.source = arv.source;
                            break;
                        }
                    }
                }
                frame.name = ar.name ? ar.name : "null";
                frame.pointer = (uint64_t)lua_topointer(L, -1);
                frame.tail = arv->event == LUA_HOOKTAILCALL;
                frame.call_tick = now();
                m_cur_ci->call_list.push_back(frame);
                return;
            }
            if (arv->event == LUA_HOOKRET) {
                auto& call_list = m_cur_ci->call_list;
                if (call_list.empty()) return;
                while (true) {
                    uint64_t now_tick = now();
                    call_frame& cur_frame = call_list.back();
                    uint64_t diff = now_tick - cur_frame.call_tick;
                    uint64_t call_cost = diff - cur_frame.sub_cost;
                    record_eval(cur_frame, call_cost);
                    call_list.pop_back();
                    if (call_list.empty()) break;
                    //排除掉记录的时间
                    uint64_t rd_tick = now() - now_tick;
                    call_list.back().sub_cost += (cur_frame.sub_cost + rd_tick + co_cost);
                    if (!call_list.back().tail) break;
                }
            }
        }

        bool is_filter(call_frame& frame) {
            //load加载的函数, 不记录
            if (frame.line == 0) return true;
            //观察的函数，需要记录
            if (m_watch_funcs.find(frame.pointer) != m_watch_funcs.end()) return false;
            //命中函数名过滤，不记录
            if (m_ignore_names.find(frame.name) != m_ignore_names.end()) return true;
            //命中系统函数，不记录
            if (!frame.inlua) {
                if (m_ignore_funcs.find(frame.pointer) != m_ignore_funcs.end()) return true;
            }
            if (m_watch_files.empty()) {
                //关注文件为空，检查过滤文件
                return m_ignore_files.find(frame.source) != m_ignore_files.end();
            }
            return m_watch_files.find(frame.source) != m_watch_files.end();
        }

        void record_eval(call_frame& frame, uint64_t call_cost) {
            //总时间累加
            m_all_times += call_cost;
            if (is_filter(frame)) return;
            auto id = (uint64_t)frame.pointer;
            auto it = m_evals.find(id);
            if (it == m_evals.end()) {
                eval_data edata;
                edata.call_count++;
                edata.name = frame.name;
                edata.line = frame.line;
                edata.inlua = frame.inlua;
                edata.source = frame.source;
                edata.pointer = frame.pointer;
                edata.min_time = call_cost;
                edata.max_time = call_cost;
                edata.total_time += call_cost;
                m_evals.emplace(id, edata);
                return;
            }
            eval_data& edata = it->second;
            edata.call_count++;
            edata.total_time += call_cost;
            if (call_cost > edata.max_time) {
                edata.max_time = call_cost;
            }
            if (call_cost < edata.min_time) edata.min_time = call_cost;
        }

        void init_lua_ignore(lua_State* L) {
            auto ignores = {
                //lua system library
                "io", "os", "math", "utf8", "debug", "table", "string", "package", "profile", "coroutine",
                // lua system function
                "type", "next", "load", "print", "pcall", "pairs", "error", "assert", "rawget", "rawset",
                "rawlen", "xpcall", "ipairs", "select", "dofile", "require", "loadfile", "tostring",
                "tonumber", "rawequal", "setmetatable", "getmetatable", "collectgarbage",
            };
            for (auto& name : ignores) {
                ignore(L, name);
            }
            // lua special function
            ignore_func("for iterator");
        }

        uint64_t now() {
            system_clock::duration dur = system_clock::now().time_since_epoch();
            return duration_cast<microseconds>(dur).count();
        }

    protected:
        uint64_t m_all_times = 0;
        call_info* m_cur_ci = nullptr;
        unordered_map<uint64_t, eval_data> m_evals;
        unordered_map<string, bool> m_watch_files;
        unordered_map<string, bool> m_ignore_names;
        unordered_map<string, bool> m_ignore_files;
        unordered_map<uint64_t, string> m_watch_funcs;
        unordered_map<uint64_t, string> m_ignore_funcs;
        unordered_map<lua_State*, call_info*> m_call_infos;
    };
}
