#pragma once

#include <mutex>
#include <atomic>
#include <thread>

#include "../lcodec/buffer.h"
#include "fmt/core.h"

using namespace lcodec;
using namespace luakit;

namespace lworker {

    static slice* read_slice(std::shared_ptr<var_buffer> buff, size_t* pack_len) {
        uint8_t* plen = buff->peek_data(sizeof(uint16_t));
        if (plen) {
            uint16_t len = *(uint16_t*)plen;
            uint8_t* pdata = buff->peek_data(len);
            if (pdata) {
                *pack_len = sizeof(uint16_t) + len;
                return buff->get_slice(len, sizeof(uint16_t));
            }
        }
        return nullptr;
    }

    class spin_mutex {
    public:
        spin_mutex() = default;
        spin_mutex(const spin_mutex&) = delete;
        spin_mutex& operator = (const spin_mutex&) = delete;
        void lock() {
            while(flag.test_and_set(std::memory_order_acquire));
        }
        void unlock() {
            flag.clear(std::memory_order_release);
        }
    private:
        std::atomic_flag flag = ATOMIC_FLAG_INIT;
    }; //spin_mutex

    class worker;
    class ischeduler {
    public:
        virtual void wakeup(slice* buf) = 0;
        virtual void callback(slice* buf) = 0;
        virtual void destory(std::string& name, std::shared_ptr<worker> workor) = 0;
    };

    class worker :public std::enable_shared_from_this<worker>
    {
    public:
        worker(ischeduler* schedulor, std::string& name, std::string& entry, std::string& service, std::string& sandbox)
            : m_schedulor(schedulor), m_name(name), m_entry(entry), m_service(service), m_sandbox(sandbox) { }

        ~worker() {
            m_running = false;
            if (m_thread.joinable()) {
                m_thread.join();
            }
        }

        const char* get_env(const char* key) {
            return getenv(key);
        }

        bool call(slice* buf) {
            std::unique_lock<spin_mutex> lock(m_mutex);
            m_write_buf->write<uint16_t>(buf->size());
            m_write_buf->push_data(buf->head(), buf->size());
            return true;
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
                m_lua->table_call(service, "on_worker", nullptr, std::tie(), slice);
                m_read_buf->pop_size(plen);
                slice = read_slice(m_read_buf, &plen);
            }
        }

        void startup(){            
            std::thread(&worker::run, this).swap(m_thread);            
        }

        void run(){
            auto hive = m_lua->new_table(m_service.c_str());
            hive.set("logtag", fmt::format("[{}]", m_name));
            hive.set_function("stop", [&]() { stop(); });
            hive.set_function("update", [&]() { update(); });
            hive.set_function("getenv", [&](const char* key) { return get_env(key); });
            hive.set_function("wakeup", [&](slice* buf) { m_schedulor->wakeup(buf); });
            hive.set_function("callback", [&](slice* buf) { m_schedulor->callback(buf); });
            m_lua->run_script(fmt::format("require '{}'", m_sandbox), [&](std::string err) {
                printf("worker load %s failed, because: %s", m_sandbox.c_str(), err.c_str());
                m_schedulor->destory(m_name, shared_from_this());
                return;
            });
            m_lua->run_script(fmt::format("require '{}'", m_entry), [&](std::string err) {
                printf("worker load %s failed, because: %s", m_entry.c_str(), err.c_str());
                m_schedulor->destory(m_name, shared_from_this());
                return;
            });
            m_running = true;
            const char* service = m_service.c_str();
            while (m_running) {
                m_lua->table_call(service, "run");
            }
            m_schedulor->destory(m_name, shared_from_this());
        }

        void stop(){
            m_running = false;
        }

    private:
        spin_mutex m_mutex;
        std::thread m_thread;
        bool m_running = false;
        ischeduler* m_schedulor = nullptr;
        std::string m_name, m_entry, m_service, m_sandbox;
        std::shared_ptr<kit_state> m_lua = std::make_shared<kit_state>();
        std::shared_ptr<var_buffer> m_read_buf = std::make_shared<var_buffer>();
        std::shared_ptr<var_buffer> m_write_buf = std::make_shared<var_buffer>();
    };
}

