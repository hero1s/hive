#ifndef __SCHEDULER_H__
#define __SCHEDULER_H__
#include <condition_variable>

#include "worker.h"

using namespace std::chrono;

namespace lworker {

    typedef std::vector<std::shared_ptr<worker>> worker_list;
    class scheduler : public ischeduler
    {
    public:
        void setup(lua_State* L, std::string& service, std::string& sandbox) {
            m_service = service;
            m_sandbox = sandbox;
            m_lua = std::make_shared<kit_state>(L);
        }

        std::shared_ptr<worker> find_worker(std::string& name, size_t hash) {
            std::unique_lock<spin_mutex> lock(m_mutex);
            auto it = m_worker_map.find(name);
            if (it != m_worker_map.end()){
                worker_list& wlist = it->second;
                size_t count = wlist.size();
                if (count > 0) {
                    return wlist[hash % count];
                }
            }
            return nullptr;
        }

        void startup(std::string& name, std::string& entry) {
            auto workor = std::make_shared<worker>(this, name, entry, m_service, m_sandbox);
            std::unique_lock<spin_mutex> lock(m_mutex);
            auto it = m_worker_map.find(name);
            if (it == m_worker_map.end()){
                worker_list wlist = { workor };
                m_worker_map.insert(std::make_pair(name, wlist));
            } else {
                it->second.push_back(workor);
            }
            workor->startup();
        }
        
        slice* suspend(size_t timeout) {
            //enum class cv_status { no_timeout, timeout };
            std::unique_lock<std::mutex> lock(m_cvmutex);
            if (m_condv.wait_for(lock, milliseconds(timeout)) == std::cv_status::no_timeout) {
                return m_slice->get_slice();
            }
            return nullptr;
        }

        void wakeup(slice* buf) {
            std::unique_lock<std::mutex> lock(m_cvmutex);
            m_slice->reset();
            m_slice->push_data(buf->head(), buf->size());
            m_condv.notify_all();
        }

        bool call(std::string& name, slice* buf, size_t hash) {
            auto workor = find_worker(name, hash);
            if (workor) {
                return workor->call(buf);
            }
            return false;
        }

        bool callback(slice* buf) {
            if (buf->size() < UINT32_MAX) {
                std::unique_lock<spin_mutex> lock(m_mutex);
                m_write_buf->write<uint32_t>(buf->size());
                m_write_buf->push_data(buf->head(), buf->size());
                return true;
            }
            return false;
        }

        void update() {
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
            }
        }

        void destory(std::string& name, std::shared_ptr<worker> workor) {
            std::unique_lock<spin_mutex> lock(m_mutex);
            auto it = m_worker_map.find(name);
            if (it != m_worker_map.end()) {
                for (auto it2 = it->second.begin(); it2 != it->second.end(); ++it2) {
                    if (*it2 == workor) {
                        it->second.erase(it2);
                        break;
                    }
                }
            }
        }

    private:
        spin_mutex m_mutex;
        std::mutex m_cvmutex;
        std::condition_variable m_condv;
        std::string m_service, m_sandbox;
        std::shared_ptr<kit_state> m_lua = nullptr;
        std::map<std::string, worker_list> m_worker_map;
        std::shared_ptr<var_buffer> m_slice = std::make_shared<var_buffer>();
        std::shared_ptr<var_buffer> m_read_buf = std::make_shared<var_buffer>();
        std::shared_ptr<var_buffer> m_write_buf = std::make_shared<var_buffer>();
    };
}

#endif
