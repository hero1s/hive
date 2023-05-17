#ifndef __SCHEDULER_H__
#define __SCHEDULER_H__
#include <condition_variable>

#include "worker.h"

using namespace std::chrono;

namespace lworker {

    class scheduler : public ischeduler
    {
    public:
        void setup(lua_State* L, std::string& service) {
            m_service = service;
            m_lua = std::make_shared<kit_state>(L);
        }

        std::shared_ptr<worker> find_worker(std::string& name) {
            std::unique_lock<spin_mutex> lock(m_mutex);
            auto it = m_worker_map.find(name);
            if (it != m_worker_map.end()) {
                return it->second;
            }
            return nullptr;
        }

        bool startup(std::string& name, std::string& entry) {
            std::unique_lock<spin_mutex> lock(m_mutex);
            auto it = m_worker_map.find(name);
            if (it == m_worker_map.end()) {
                auto workor = std::make_shared<worker>(this, name, entry, m_service);
                m_worker_map.insert(std::make_pair(name, workor));
                workor->startup();
                return true;
            }
            return false;
        }

        void broadcast(slice* buf) {
            std::unique_lock<spin_mutex> lock(m_mutex);
            for (auto it : m_worker_map) {
                it.second->call(buf);
            }
        }
        
        bool call(std::string& name, slice* buf) {
            if (name == "master") {
                return call(buf);
            }
            auto workor = find_worker(name);
            if (workor) {
                return workor->call(buf);
            }
            return false;
        }

        bool call(slice* buf) {
            uint8_t* target = m_write_buf->peek_space(buf->size() + sizeof(uint32_t));
            if (target) {
                std::unique_lock<spin_mutex> lock(m_mutex);
                m_write_buf->write<uint32_t>(buf->size());
                m_write_buf->push_data(buf->head(), buf->size());
                return true;
            }
            return false;
        }

        void update() {
            uint64_t clock_ms = ltimer::steady_ms();
            if (m_read_buf->empty()) {
                if (m_write_buf->empty()) {
                    return;
                }
                std::unique_lock<spin_mutex> lock(m_mutex);
                m_read_buf.swap(m_write_buf);
            }            
            size_t plen = 0;
            const char* service = m_service.c_str();
            slice* slice = read_slice(m_read_buf, &plen);
            while (slice) {
                m_lua->table_call(service, "on_scheduler", nullptr, std::tie(), slice);
                m_read_buf->pop_size(plen);
                slice = read_slice(m_read_buf, &plen);
                if (ltimer::steady_ms() - clock_ms > 100) break;
            }
        }

        void destory(std::string& name, std::shared_ptr<worker> workor) {
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
        }

    private:
        spin_mutex m_mutex;
        std::string m_service;
        std::shared_ptr<kit_state> m_lua = nullptr;
        std::map<std::string, std::shared_ptr<worker>> m_worker_map;
        std::shared_ptr<var_buffer> m_slice = std::make_shared<var_buffer>();
        std::shared_ptr<var_buffer> m_read_buf = std::make_shared<var_buffer>();
        std::shared_ptr<var_buffer> m_write_buf = std::make_shared<var_buffer>();
    };
}

#endif
