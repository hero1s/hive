#ifndef __SCHEDULER_H__
#define __SCHEDULER_H__
#include <condition_variable>

#include "worker.h"

using namespace std::chrono;
using vstring = std::string_view;

namespace lworker {

    class scheduler : public ischeduler
    {
    public:
        void setup(lua_State* L, vstring service) {
            m_service = service;
            m_lua = std::make_unique<kit_state>(L);
            m_codec = m_lua->create_codec();
        }

        std::shared_ptr<worker> find_worker(vstring name) {
            std::unique_lock<spin_mutex> lock(m_mutex);
            auto it = m_worker_map.find(name);
            if (it != m_worker_map.end()) {
                return it->second;
            }
            return nullptr;
        }

        bool startup(vstring name, vstring entry, vstring incl) {
            std::unique_lock<spin_mutex> lock(m_mutex);
            auto it = m_worker_map.find(name);
            if (it == m_worker_map.end()) {
                auto workor = std::make_shared<worker>(this, name, entry, incl, m_service);
                m_worker_map.insert(std::make_pair(name, workor));
                workor->startup();
                return true;
            }
            LOG_ERROR(fmt::format("thread [{}] work is repeat startup", name));
            return false;
        }

        int broadcast(lua_State* L) {
            std::unique_lock<spin_mutex> lock(m_mutex);
            for (auto it : m_worker_map) {
                it.second->call(L);
            }
            return 0;
        }
        
        int call(lua_State* L, vstring name) {
            if (name == "master") {
                lua_pushboolean(L, call(L));
                return 1;
            }
            auto workor = find_worker(name);
            if (workor) {
                lua_pushboolean(L, workor->call(L));
                return 1;
            }
            LOG_ERROR(fmt::format("thread call [{}] work is not exist", name));
            lua_pushboolean(L, false);
            return 1;
        }

        bool call(lua_State* L) {
            size_t data_len;
            std::unique_lock<spin_mutex> lock(m_mutex);
            uint8_t* data = m_codec->encode(L, 2, &data_len);
            uint8_t* target = m_write_buf->peek_space(data_len + sizeof(uint32_t));
            if (target) {
                m_write_buf->write<uint32_t>(data_len);
                m_write_buf->push_data(data, data_len);
                return true;
            }
            LOG_ERROR(fmt::format("master thread call buffer is full!,size:{}",m_write_buf->size()));
            return false;
        }

        void update(uint64_t clock_ms) {
            if (m_read_buf->empty()) {
                if (m_write_buf->empty()) {
                    return;
                }
                std::unique_lock<spin_mutex> lock(m_mutex);
                m_read_buf.swap(m_write_buf);
            }
            size_t plen = 0,pcount = 0;
            const char* service = m_service.c_str();
            slice* slice = read_slice(m_read_buf, &plen);
            while (slice) {
                m_codec->set_slice(slice);
                m_lua->table_call(service, "on_scheduler", nullptr, m_codec, std::tie());
                if (m_codec->failed()) {
                    m_read_buf->clean();
                    break;
                }
                m_read_buf->pop_size(plen);
                ++pcount;
                auto cost_time = ltimer::steady_ms() - clock_ms;
                if (cost_time > 100) {
                    LOG_ERROR(fmt::format("on_scheduler is busy,cost:{},pcount:{},remain:{}", cost_time, pcount, m_read_buf->size()));
                    break;
                }
                slice = read_slice(m_read_buf, &plen);
            }
        }

        void destory(vstring name) {
            std::unique_lock<spin_mutex> lock(m_mutex);
            auto it = m_worker_map.find(name);
            if (it != m_worker_map.end()) {
                m_worker_map.erase(it);
            }
        }

        void shutdown() {
            std::unique_lock<spin_mutex> lock(m_mutex);
            for (auto it : m_worker_map) {
                it.second->stop();
            }
            m_worker_map.clear();
        }

        std::vector<std::string> workers() {
            std::vector<std::string> vec;
            for (auto it : m_worker_map) {
                vec.push_back(it.first);
            }
            return vec;
        }

    private:
        spin_mutex m_mutex;
        std::string m_service;
        codec_base* m_codec = nullptr;
        std::unique_ptr<kit_state> m_lua = nullptr;
        std::shared_ptr<luabuf> m_read_buf = std::make_shared<luabuf>(32,32);
        std::shared_ptr<luabuf> m_write_buf = std::make_shared<luabuf>(32,32);
        std::map<std::string, std::shared_ptr<worker>, std::less<>> m_worker_map;
    };
}

#endif
