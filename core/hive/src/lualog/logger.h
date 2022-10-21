#pragma once

#include <list>
#include <array>
#include <ctime>
#include <mutex>
#include <vector>
#include <chrono>
#include <atomic>
#include <thread>
#include <fstream>
#include <iostream>
#include <filesystem>
#include <unordered_map>
#include <condition_variable>
#include <assert.h>

#include "fmt/core.h"

#ifdef WIN32
#include <process.h>
#define getpid _getpid
#else
#include <unistd.h>
#endif

using namespace std::chrono;
using namespace std::filesystem;

namespace logger {
    enum class log_level {
        LOG_LEVEL_DEBUG = 1,
        LOG_LEVEL_INFO,
        LOG_LEVEL_WARN,
        LOG_LEVEL_DUMP,
        LOG_LEVEL_ERROR,
        LOG_LEVEL_FATAL,
    };

    enum class rolling_type {
        HOURLY = 0,
        DAYLY = 1,
    }; //rolling_type

    const size_t QUEUE_MINI = 10;
    const size_t QUEUE_SIZE = 3000;
    const size_t MAX_LINE   = 100000;
    const size_t CLEAN_TIME = 7 * 24 * 3600;

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

    template <typename T>
    struct level_names {};
    template <> struct level_names<log_level> {
        constexpr std::array<const char*, 7> operator()() const {
            return { "UNKNW", "DEBUG", "INFO", "WARN", "DUMP", "ERROR","FATAL" };
        }
    };

    template <typename T>
    struct level_colors {};
    template <> struct level_colors<log_level> {
        constexpr std::array<const char*, 7> operator()() const {
            return { "\x1b[32m", "\x1b[37m", "\x1b[32m", "\x1b[33m", "\x1b[32m", "\x1b[31m", "\x1b[31m", };
        }
    };

    class log_filter {
    public:
        void filter(log_level llv, bool on) {
            if (on)
                switch_bits_ |= (1 << ((int)llv - 1));
            else
                switch_bits_ &= ~(1 << ((int)llv - 1));
        }
        bool is_filter(log_level llv) const {
            return 0 == (switch_bits_ & (1 << ((int)llv - 1)));
        }
    private:
        unsigned switch_bits_ = -1;
    }; // class log_filter

    class log_time : public ::tm {
    public:
        int tm_usec = 0;

        log_time() { }
        log_time(const ::tm& tm, int usec) : ::tm(tm), tm_usec(usec) { }
        static log_time now() {
            system_clock::duration dur = system_clock::now().time_since_epoch();
            time_t time = duration_cast<seconds>(dur).count();
            auto time_ms = duration_cast<milliseconds>(dur).count();
            return log_time(*std::localtime(&time), time_ms % 1000);
        }
    }; // class log_time

    template<log_level> class log_stream;
    class log_message {
    public:
        template<log_level>
        friend class log_stream;
        int line() const { return line_; }
        bool is_grow() const { return grow_; }
        void set_grow(bool grow) { grow_ = grow; }
        log_level level() const { return level_; }
        const std::string msg() const { return stream_; }
        const std::string source() const { return source_; }
        const std::string feature() const { return feature_; }
        const log_time& get_log_time()const { return log_time_; }
        void clear() {
            stream_.clear();
            stream_.shrink_to_fit();
        }
        template<class T>
        log_message& operator<<(const T& value) {
            fmt::format_to(std::back_inserter(stream_), "{}", value);
            return *this;
        }
    private:
        int                 line_ = 0;
        bool                grow_ = false;
        log_time            log_time_;
        std::string         source_, stream_, feature_;
        log_level           level_ = log_level::LOG_LEVEL_DEBUG;
    }; // class log_message
    typedef std::list<std::shared_ptr<log_message>> log_message_list;

    class log_message_pool {
    public:
        log_message_pool(size_t msg_size) {
            for (size_t i = 0; i < msg_size; ++i) {
                alloc_messages_->push_back(std::make_shared<log_message>());
            }
        }
        ~log_message_pool() {
            alloc_messages_->clear();
            free_messages_->clear();
        }
        std::shared_ptr<log_message> allocate() {
            if (alloc_messages_->empty()) {
                std::unique_lock<spin_mutex> lock(mutex_);
                alloc_messages_.swap(free_messages_);
            }
            if (alloc_messages_->empty()) {
                auto logmsg = std::make_shared<log_message>();
                logmsg->set_grow(true);
                return logmsg;
            }
            auto logmsg = alloc_messages_->front();
            alloc_messages_->pop_front();
            logmsg->clear();
            return logmsg;
        }
        void release(std::shared_ptr<log_message> logmsg) {
            if (!logmsg->is_grow()) {
                std::unique_lock<spin_mutex> lock(mutex_);
                free_messages_->push_back(logmsg);
            }
        }

    private:
        spin_mutex mutex_;
        std::shared_ptr<log_message_list> free_messages_ = std::make_shared<log_message_list>();
        std::shared_ptr<log_message_list> alloc_messages_ = std::make_shared<log_message_list>();
    }; // class log_message_pool

    class log_message_queue {
    public:
        void put(std::shared_ptr<log_message> logmsg) {
            std::unique_lock<spin_mutex> lock(spin_);
            write_messages_->push_back(logmsg);
        }

        std::shared_ptr<log_message_list> timed_getv() {
            {
                read_messages_->clear();
                std::unique_lock<spin_mutex> lock(spin_);
                read_messages_.swap(write_messages_);
            }
            if (read_messages_->empty()) {
                std::unique_lock<std::mutex> lock(mutex_);
                condv_.wait_for(lock, milliseconds(5));
            }
            return read_messages_;
        }

    private:
        spin_mutex                  spin_;
        std::mutex                  mutex_;
        std::condition_variable     condv_;
        std::shared_ptr<log_message_list> read_messages_ = std::make_shared<log_message_list>();
        std::shared_ptr<log_message_list> write_messages_ = std::make_shared<log_message_list>();
    }; // class log_message_queue

    class log_service;
    class log_dest {
    public:
        virtual void flush() {};
        virtual void raw_write(std::string& msg, log_level lvl) = 0;
        virtual void write(std::shared_ptr<log_message> logmsg);
        virtual std::string build_postfix(std::shared_ptr<log_message> logmsg);
    }; // class log_dest

    class stdio_dest : public log_dest {
    public:
        virtual void raw_write(std::string& msg, log_level lvl) {
#ifdef WIN32
            auto colors = level_colors<log_level>()();
            std::cout << colors[(int)lvl];
#endif // WIN32
            std::cout << msg;
        }
    }; // class stdio_dest

    class log_file_base : public log_dest {
    public:
        log_file_base(size_t max_line, size_t pid) : pid_(pid), line_(0), max_line_(max_line) {}
        virtual ~log_file_base() {
            if (file_) {
                file_->flush();
                file_->close();
            }
        }
        virtual void raw_write(std::string& msg, log_level lvl) {
            if (file_) file_->write(msg.c_str(), msg.size());
        }
        virtual void flush() {
            if (file_) file_->flush();
        }
        const log_time& file_time() const { return file_time_; }

    protected:
        virtual void create(path file_path, std::string& file_name, const log_time& file_time) {
            if (file_) {
                file_->flush();
                file_->close();
            }
            file_time_ = file_time;
            file_path.append(file_name);
            file_ = std::make_unique<std::ofstream>(file_path, std::ios::binary | std::ios::out | std::ios::app);
        }

        log_time        file_time_;
        size_t          pid_, line_, max_line_;
        std::unique_ptr<std::ofstream> file_ = nullptr;
    }; // class log_file

    class rolling_hourly {
    public:
        bool eval(const log_file_base* log_file, const std::shared_ptr<log_message> logmsg) const {
            const log_time& ftime = log_file->file_time();
            const log_time& ltime = logmsg->get_log_time();
            return ltime.tm_year != ftime.tm_year || ltime.tm_mon != ftime.tm_mon ||
                ltime.tm_mday != ftime.tm_mday || ltime.tm_hour != ftime.tm_hour;
        }

    }; // class rolling_hourly

    class rolling_daily {
    public:
        bool eval(const log_file_base* log_file, const std::shared_ptr<log_message> logmsg) const {
            const log_time& ftime = log_file->file_time();
            const log_time& ltime = logmsg->get_log_time();
            return ltime.tm_year != ftime.tm_year || ltime.tm_mon != ftime.tm_mon || ltime.tm_mday != ftime.tm_mday;
        }
    }; // class rolling_daily

    template<class rolling_evaler>
    class log_rollingfile : public log_file_base {
    public:
        log_rollingfile(size_t pid, size_t max_line = 10000) : log_file_base(max_line, pid) {}
        void setup(path& log_path, const std::string& service, const std::string& feature, size_t clean_time = CLEAN_TIME) {
            feature_ = feature;
            log_path_ = log_path;
            clean_time_ = clean_time;
            if (feature != service) {
                log_path_.append(feature);
            }
        }

        virtual void write(std::shared_ptr<log_message> logmsg) {
            line_++;
            if (file_ == nullptr || rolling_evaler_.eval(this, logmsg) || line_ >= max_line_) {
                try { create_directories(log_path_); } catch (...) {}
                for (auto entry : recursive_directory_iterator(log_path_)) {
                    if (!entry.is_directory() && entry.path().extension().string() == ".log") {
                        auto ftime = last_write_time(entry.path());
                        if ((size_t)duration_cast<seconds>(file_time_type::clock::now() - ftime).count() > clean_time_) {
                            try { remove(entry.path()); } catch (...) {}
                        }
                    }
                }
                std::string file_name = new_log_file_path(logmsg);
                create(log_path_, file_name, logmsg->get_log_time());
                assert(file_);
                line_ = 0;
            }
            log_file_base::write(logmsg);
        }

    protected:
        std::string new_log_file_path(const std::shared_ptr<log_message> logmsg) {
            const log_time& t = logmsg->get_log_time();
            return fmt::format("{}-{:4d}{:02d}{:02d}-{:02d}{:02d}{:02d}.{:03d}.p{}.log", feature_, t.tm_year + 1900, t.tm_mon + 1, t.tm_mday, t.tm_hour, t.tm_min, t.tm_sec, t.tm_usec, pid_);
        }

        path                    log_path_;
        std::string             feature_;
        rolling_evaler          rolling_evaler_;
        size_t                  clean_time_ = CLEAN_TIME;
    }; // class log_rollingfile

    typedef log_rollingfile<rolling_hourly> log_hourlyrollingfile;
    typedef log_rollingfile<rolling_daily> log_dailyrollingfile;

    class log_service {
    public:
        ~log_service() { stop(); }
        void daemon(bool status) { log_daemon_ = status; }
        void option(std::string& log_path, std::string& service, std::string& index, rolling_type type) {
            log_path_ = log_path, service_ = service; rolling_type_ = type;
            log_path_.append(fmt::format("{}-{}", service, index));
        }
        log_filter* get_filter() { return &log_filter_; }
        log_message_pool* message_pool() { return message_pool_.get(); }

        void set_max_line(size_t max_line) { max_line_ = max_line; }
        void set_clean_time(size_t clean_time) { clean_time_ = clean_time; }

        bool add_dest(std::string& feature) {
            std::unique_lock<spin_mutex> lock(mutex_);
            if (dest_features_.find(feature) == dest_features_.end()) {
                std::shared_ptr<log_dest> logfile = nullptr;
                if (rolling_type_ == rolling_type::DAYLY) {
                    auto dlogfile = std::make_shared<log_dailyrollingfile>(log_pid_, max_line_);
                    dlogfile->setup(log_path_, service_, feature, clean_time_);
                    logfile = dlogfile;
                } else {
                    auto hlogfile = std::make_shared<log_hourlyrollingfile>(log_pid_, max_line_);
                    hlogfile->setup(log_path_, service_, feature, clean_time_);
                    logfile = hlogfile;
                }
                if (!def_dest_) {
                    def_dest_ = logfile;
                    return true;
                }
                dest_features_.insert(std::make_pair(feature, logfile));
                return true;
            }
            return false;
        }

        bool add_lvl_dest(log_level log_lvl) {
            auto names = level_names<log_level>()();
            std::string feature = names[(int)log_lvl];
            std::transform(feature.begin(), feature.end(), feature.begin(), [](auto c) { return std::tolower(c); });
            std::unique_lock<spin_mutex> lock(mutex_);
            if (rolling_type_ == rolling_type::DAYLY) {
                auto logfile = std::make_shared<log_dailyrollingfile>(log_pid_, max_line_);
                logfile->setup(log_path_, service_, feature, clean_time_);
                dest_lvls_.insert(std::make_pair(log_lvl, logfile));
            }
            else {
                auto logfile = std::make_shared<log_hourlyrollingfile>(log_pid_, max_line_);
                logfile->setup(log_path_, service_, feature, clean_time_);
                dest_lvls_.insert(std::make_pair(log_lvl, logfile));
            }
            return true;
        }

        void del_dest(std::string& feature) {
            std::unique_lock<spin_mutex> lock(mutex_);
            auto it = dest_features_.find(feature);
            if (it != dest_features_.end()) {
                dest_features_.erase(it);
            }
        }

        void del_lvl_dest(log_level log_lvl) {
            std::unique_lock<spin_mutex> lock(mutex_);
            auto it = dest_lvls_.find(log_lvl);
            if (it != dest_lvls_.end()) {
                dest_lvls_.erase(it);
            }
        }

        void start() {
            if (!stop_msg_ && !std_dest_) {
                log_pid_ = ::getpid();
                logmsgque_ = std::make_shared<log_message_queue>();
                message_pool_ = std::make_shared<log_message_pool>(QUEUE_SIZE);
                std_dest_ = std::make_shared<stdio_dest>();
                stop_msg_ = message_pool_->allocate();
                std::thread(&log_service::run, this).swap(thread_);
            }
        }

        void terminal() {
            if (!std_dest_) {
                std_dest_ = std::make_shared<stdio_dest>();
                message_pool_ = std::make_shared<log_message_pool>(QUEUE_MINI);
            }
        }

        void stop() {
            if (stop_msg_) {
                logmsgque_->put(stop_msg_);
            }
            if (thread_.joinable()) {
                thread_.join();
            }
        }

        void submit(std::shared_ptr<log_message> logmsg) {
            if (stop_msg_) {
                logmsgque_->put(logmsg);
                return;
            }
            if (std_dest_) {
                std_dest_->write(logmsg);
            }
        }

        void flush() {
            std::unique_lock<spin_mutex> lock(mutex_);
            for (auto dest : dest_features_)
                dest.second->flush();
            for (auto dest : dest_lvls_)
                dest.second->flush();
            if (def_dest_) {
                def_dest_->flush();
            }
        }

        bool is_ignore_postfix() const { return ignore_postfix_; }
        void ignore_postfix() { ignore_postfix_ = true; }

        bool is_filter(log_level lv) {
            return log_filter_.is_filter(lv); 
        }

        void filter(log_level lv, bool on) {
            log_filter_.filter(lv, on);
        }

        static log_service* instance() {
            static log_service service;
            return &service;
        }

        template<log_level level>
        log_stream<level> hold(std::string feature, std::string source = "", int line = 0) {
            return log_stream<level>(feature, source, line);
        }

        template<log_level level>
        log_stream<level> print(std::string feature, std::string source = "", int line = 0) {
            return log_stream<level>(feature, source, line);
        }

        template<log_level level>
        void output(std::string& msg, std::string& feature) {
            hold<level>(feature, __FILE__, __LINE__) << msg;
        }

    private:
        void run() {
            bool loop = true;
            while (loop) {
                auto logmsgs = logmsgque_->timed_getv().get();
                for (auto logmsg : *logmsgs) {
                    if (logmsg == stop_msg_) {
                        loop = false;
                        continue;
                    }
                    if (!log_daemon_) {
                        std_dest_->write(logmsg);
                    }
                    auto itLvl = dest_lvls_.find(logmsg->level());
                    if (itLvl != dest_lvls_.end()) {
                        itLvl->second->write(logmsg);
                    }
                    auto itFea = dest_features_.find(logmsg->feature());
                    if (itFea != dest_features_.end()) {
                        itFea->second->write(logmsg);
                    }
                    if (def_dest_) {
                        def_dest_->write(logmsg);
                    }
                    message_pool_->release(logmsg);
                }
                flush();
            }
        }

        path            log_path_;
        spin_mutex      mutex_;
        log_filter      log_filter_;
        rolling_type    rolling_type_;
        std::thread     thread_;
        std::string     service_;
        std::shared_ptr<log_dest> std_dest_ = nullptr;
        std::shared_ptr<log_dest> def_dest_ = nullptr;
        std::shared_ptr<log_message> stop_msg_ = nullptr;
        std::shared_ptr<log_message_queue> logmsgque_ = nullptr;
        std::shared_ptr<log_message_pool> message_pool_ = nullptr;
        std::unordered_map<log_level, std::shared_ptr<log_dest>> dest_lvls_;
        std::unordered_map<std::string, std::shared_ptr<log_dest>> dest_features_;
        size_t log_pid_ = 0, max_line_ = MAX_LINE, clean_time_ = CLEAN_TIME;
        bool log_daemon_ = false, ignore_postfix_ = true;
    }; // class log_service

    template<log_level level>
    class log_stream {
    public:
        log_stream(std::string& feature, std::string& source, int line) {
            auto service = log_service::instance();
            if (!service->is_filter(level)) {
                logmsg_ = service->message_pool()->allocate();
                logmsg_->log_time_ = log_time::now();
                logmsg_->level_ = level;
                logmsg_->feature_ = feature;
                logmsg_->source_ = source;
                logmsg_->line_ = line;
            }
        }
        ~log_stream() {
            if (nullptr != logmsg_) {
                log_service::instance()->submit(logmsg_);
                logmsg_ = nullptr;
            }
        }

        template<class T>
        log_stream& operator<<(const T& value) {
            if (nullptr != logmsg_) {
                *logmsg_ << value;
            }
            return *this;
        }

    private:
        std::shared_ptr<log_message> logmsg_ = nullptr;
    };

    inline void log_dest::write(std::shared_ptr<log_message> logmsg) {
        auto names = level_names<log_level>()();
        const log_time& t = logmsg->get_log_time();
        auto logtxt = fmt::format("[{:4d}-{:02d}-{:02d} {:02d}:{:02d}:{:02d}.{:03d}][{}] {}{}\n",
            t.tm_year + 1900, t.tm_mon + 1, t.tm_mday, t.tm_hour, t.tm_min, t.tm_sec, t.tm_usec, 
            names[(int)logmsg->level()], build_postfix(logmsg), logmsg->msg());
        raw_write(logtxt, logmsg->level());
    }

    inline std::string log_dest::build_postfix(std::shared_ptr<log_message> logmsg) {
        if (!log_service::instance()->is_ignore_postfix()) {
            return fmt::format("[{}:{}]", logmsg->source().c_str(), logmsg->line());
        }
        return "";
    }
}

#define LOG_WARN logger::log_service::instance()->hold<logger::log_level::LOG_LEVEL_WARN>("", __FILE__, __LINE__)
#define LOG_INFO logger::log_service::instance()->hold<logger::log_level::LOG_LEVEL_INFO>("", __FILE__, __LINE__)
#define LOG_DUMP logger::log_service::instance()->hold<logger::log_level::LOG_LEVEL_DUMP>("", __FILE__, __LINE__)
#define LOG_DEBUG logger::log_service::instance()->hold<logger::log_level::LOG_LEVEL_DEBUG>("", __FILE__, __LINE__)
#define LOG_ERROR logger::log_service::instance()->hold<logger::log_level::LOG_LEVEL_ERROR>("", __FILE__, __LINE__)
#define LOG_FATAL logger::log_service::instance()->hold<logger::log_level::LOG_LEVEL_FATAL>("", __FILE__, __LINE__)
#define PRINT_WARN logger::log_service::instance()->print<logger::log_level::LOG_LEVEL_WARN>("", __FILE__, __LINE__)
#define PRINT_INFO logger::log_service::instance()->print<logger::log_level::LOG_LEVEL_INFO>("", __FILE__, __LINE__)
#define PRINTLOG_DUMP logger::log_service::instance()->print<logger::log_level::LOG_LEVEL_DUMP>("", __FILE__, __LINE__)
#define PRINT_DEBUG logger::log_service::instance()->print<logger::log_level::LOG_LEVEL_DEBUG>("", __FILE__, __LINE__)
#define PRINT_ERROR logger::log_service::instance()->print<logger::log_level::LOG_LEVEL_ERROR>("", __FILE__, __LINE__)
#define PRINT_FATAL logger::log_service::instance()->print<logger::log_level::LOG_LEVEL_FATAL>("", __FILE__, __LINE__)
#define LOGF_WARN(feature) logger::log_service::instance()->hold<logger::log_level::LOG_LEVEL_WARN>(feature, __FILE__, __LINE__)
#define LOGF_INFO(feature) logger::log_service::instance()->hold<logger::log_level::LOG_LEVEL_INFO>(feature, __FILE__, __LINE__)
#define LOGF_DUMP(feature) logger::log_service::instance()->hold<logger::log_level::LOG_LEVEL_DUMP>(feature, __FILE__, __LINE__)
#define LOGF_DEBUG(feature) logger::log_service::instance()->hold<logger::log_level::LOG_LEVEL_DEBUG>(feature, __FILE__, __LINE__)
#define LOGF_ERROR(feature) logger::log_service::instance()->hold<logger::log_level::LOG_LEVEL_ERROR>(feature, __FILE__, __LINE__)
#define LOGF_FATAL(feature) logger::log_service::instance()->hold<logger::log_level::LOG_LEVEL_FATAL>(feature, __FILE__, __LINE__)
