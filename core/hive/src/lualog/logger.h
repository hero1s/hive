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
#include <map>
#include <condition_variable>
#include <assert.h>

#include "fmt/core.h"
#include "thread_name.hpp"

#ifdef WIN32
#include <process.h>
#define getpid _getpid
#else
#include <unistd.h>
#endif

using namespace std::chrono;
using namespace std::filesystem;
using sstring = std::string;
using vstring = std::string_view;
using cstring = const std::string;

template <class T>
using sptr = std::shared_ptr<T>;

namespace logger {
    enum class log_level : uint8_t {
        LOG_LEVEL_TRACE = 1,
        LOG_LEVEL_DEBUG,
        LOG_LEVEL_INFO,
        LOG_LEVEL_WARN,
        LOG_LEVEL_ERROR,
        LOG_LEVEL_FATAL,
    };

    enum class rolling_type {
        HOURLY = 0,
        DAYLY = 1,
    }; //rolling_type

    const size_t QUEUE_MINI      = 10;
    const size_t QUEUE_SIZE      = 300;
    const size_t MAX_LOG_SIZE    = 50*1024*1024;//50M
    const size_t CLEAN_TIME      = 7 * 24 * 3600;

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
            return { "UNKNW","TRACE","DEBUG", "INFO", "WARN", "ERROR","FATAL" };
        }
    };

    template <typename T>
    struct level_colors {};
    template <> struct level_colors<log_level> {
        constexpr std::array<const char*, 7> operator()() const {
            return { "\x1b[32m","\x1b[36m", "\x1b[37m", "\x1b[32m", "\x1b[33m",  "\x1b[31m", "\x1b[35m", };
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

    class log_message {
    public:
        int line() const { return line_; }
        bool is_grow() const { return grow_; }
        void set_grow(bool grow) { grow_ = grow; }
        log_level level() const { return level_; }
        vstring tag() const { return tag_; }
        vstring msg() const { return msg_; }
        vstring source() const { return source_; }
        vstring feature() const { return feature_; }
        const log_time& get_log_time()const { return log_time_; }
        void option(log_level level, cstring& msg, cstring& tag, cstring& feature, cstring& source, int line) {
            log_time_ = log_time::now();
            msg_ = std::move(msg);
            tag_ = std::move(tag);
            feature_ = std::move(feature);
            source_ = std::move(source);
            level_ = level;
            line_ = line;
        }

    private:
        int                 line_ = 0;
        bool                grow_ = false;
        log_time            log_time_;
        sstring             source_, msg_, feature_, tag_;
        log_level           level_ = log_level::LOG_LEVEL_DEBUG;
    }; // class log_message
    typedef std::list<sptr<log_message>> log_message_list;

    class log_message_pool {
    public:
        log_message_pool(size_t msg_size) {
            for (size_t i = 0; i < msg_size; ++i) {
                alloc_messages_->push_back(std::make_shared<log_message>());
            }
            pool_size_ = msg_size;
        }
        ~log_message_pool() {
            alloc_messages_->clear();
            free_messages_->clear();
        }
        sptr<log_message> allocate() {
            std::unique_lock<spin_mutex> lock(mutex_);
            if (alloc_messages_->empty()) {                
                alloc_messages_.swap(free_messages_);
            }
            if (alloc_messages_->empty()) {
                auto logmsg = std::make_shared<log_message>();                
                if (pool_size_ < QUEUE_SIZE) {
                    pool_size_++;
                }else{
                    logmsg->set_grow(true);
                }
                return logmsg;
            }
            auto logmsg = alloc_messages_->front();
            alloc_messages_->pop_front();
            return logmsg;
        }
        void release(sptr<log_message> logmsg) {
            if (!logmsg->is_grow()) {
                std::unique_lock<spin_mutex> lock(mutex_);
                free_messages_->push_back(logmsg);
            }
        }

    private:
        size_t pool_size_ = 0;
        spin_mutex mutex_;
        sptr<log_message_list> free_messages_ = std::make_shared<log_message_list>();
        sptr<log_message_list> alloc_messages_ = std::make_shared<log_message_list>();
    }; // class log_message_pool

    class log_message_queue {
    public:
        void put(sptr<log_message> logmsg, bool notify) {
            std::unique_lock<spin_mutex> lock(spin_);
            write_messages_->push_back(logmsg);
            if (notify || write_messages_->size() > 10) {
                condv_.notify_all();
            }
        }

        sptr<log_message_list> timed_getv() {
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
        sptr<log_message_list> read_messages_   = std::make_shared<log_message_list>();
        sptr<log_message_list> write_messages_  = std::make_shared<log_message_list>();
    }; // class log_message_queue

    class log_service;
    class log_dest {
    public:
        virtual void flush() {};
        virtual void raw_write(vstring msg, log_level lvl) = 0;
        virtual void write(sptr<log_message> logmsg);
        virtual void ignore_prefix(bool prefix) { ignore_prefix_ = prefix; }
        virtual void ignore_suffix(bool suffix) { ignore_suffix_ = suffix; }
        virtual void ignore_def(bool def) { ignore_def_ = def; }
        virtual cstring build_prefix(sptr<log_message> logmsg);
        virtual cstring build_suffix(sptr<log_message> logmsg);
        virtual bool log_def() { return !ignore_def_; }

    protected:
        bool ignore_suffix_ = true;
        bool ignore_prefix_ = false;
        bool ignore_def_ = false;
    }; // class log_dest

    class stdio_dest : public log_dest {
    public:
        virtual void raw_write(vstring msg, log_level lvl) {
#ifdef WIN32
            auto colors = level_colors<log_level>()();
            std::cout << colors[(int)lvl];
#endif // WIN32
            std::cout << msg;
        }
    }; // class stdio_dest

    class log_file_base : public log_dest {
    public:
        log_file_base(size_t max_logsize) : logsize_(0), max_logsize_(max_logsize) {}
        virtual ~log_file_base() {
            if (file_) {
                file_->flush();
                file_->close();
            }
        }
        virtual void raw_write(vstring msg, log_level lvl) {
            logsize_ += msg.size();
            if (file_) file_->write(msg.data(), msg.size());
        }
        virtual void flush() {
            if (file_) file_->flush();
        }
        const log_time& file_time() const { return file_time_; }

    protected:
        virtual void create(path file_path, vstring file_name, const log_time& file_time) {
            if (file_) {
                file_->flush();
                file_->close();
            }
            file_time_ = file_time;
            file_path.append(file_name);
            file_ = std::make_unique<std::ofstream>(file_path, std::ios::binary | std::ios::out | std::ios::app);
        }

        log_time        file_time_;
        size_t          logsize_, max_logsize_;
        std::unique_ptr<std::ofstream> file_ = nullptr;
    }; // class log_file

    class rolling_hourly {
    public:
        bool eval(const log_file_base* log_file, const sptr<log_message> logmsg) const {
            const log_time& ftime = log_file->file_time();
            const log_time& ltime = logmsg->get_log_time();
            return ltime.tm_year != ftime.tm_year || ltime.tm_mon != ftime.tm_mon ||
                ltime.tm_mday != ftime.tm_mday || ltime.tm_hour != ftime.tm_hour;
        }

    }; // class rolling_hourly

    class rolling_daily {
    public:
        bool eval(const log_file_base* log_file, const sptr<log_message> logmsg) const {
            const log_time& ftime = log_file->file_time();
            const log_time& ltime = logmsg->get_log_time();
            return ltime.tm_year != ftime.tm_year || ltime.tm_mon != ftime.tm_mon || ltime.tm_mday != ftime.tm_mday;
        }
    }; // class rolling_daily

    template<class rolling_evaler>
    class log_rollingfile : public log_file_base {
    public:
        log_rollingfile(size_t max_logsize = 10000) : log_file_base(max_logsize) {}
        void setup(path& log_path, vstring service, vstring feature, size_t clean_time = CLEAN_TIME) {
            feature_ = feature;
            log_path_ = log_path;
            clean_time_ = clean_time;
        }

        virtual void write(sptr<log_message> logmsg) {
            if (file_ == nullptr || rolling_evaler_.eval(this, logmsg) || logsize_ >= max_logsize_) {
                create_directories(log_path_);
                try {
                    for (auto entry : recursive_directory_iterator(log_path_)) {
                        if (!entry.is_directory() && entry.path().extension().string() == ".log") {
                            auto ftime = last_write_time(entry.path());
                            if ((size_t)duration_cast<seconds>(file_time_type::clock::now() - ftime).count() > clean_time_) {
                                remove(entry.path());
                            }
                        }
                    }
                }
                catch (...) {}
                create(log_path_, new_log_file_path(logmsg), logmsg->get_log_time());
                assert(file_);
                logsize_ = 0;
            }
            log_file_base::write(logmsg);
        }

    protected:
        cstring new_log_file_path(const sptr<log_message> logmsg) {
            const log_time& t = logmsg->get_log_time();
            return fmt::format("{}-{:4d}{:02d}{:02d}-{:02d}{:02d}{:02d}.{:03d}.p{}.log", feature_, t.tm_year + 1900, t.tm_mon + 1, t.tm_mday, t.tm_hour, t.tm_min, t.tm_sec, t.tm_usec, ::getpid());
        }

        path                    log_path_;
        sstring                 feature_;
        rolling_evaler          rolling_evaler_;
        size_t                  clean_time_ = CLEAN_TIME;
    }; // class log_rollingfile

    typedef log_rollingfile<rolling_hourly> log_hourlyrollingfile;
    typedef log_rollingfile<rolling_daily> log_dailyrollingfile;

    class log_service {
    public:
        ~log_service() { stop(); }
        void daemon(bool status) { log_daemon_ = status; }
        void option(vstring log_path, vstring service, vstring index, rolling_type type, log_level hook_lv) {
            log_path_ = log_path, service_ = service; rolling_type_ = type; hook_lv_ = hook_lv > log_level::LOG_LEVEL_INFO ? hook_lv_ : log_level::LOG_LEVEL_ERROR;
            log_path_.append(fmt::format("{}-{}", service, index));
        }

        path build_path(vstring feature, vstring lpath) {
            if (lpath.empty()) {
                path log_path = log_path_;
                if (feature != service_) {
                    log_path.append(feature);
                }
                return log_path;
            }
            return lpath;
        }

        log_filter* get_filter() { return &log_filter_; }
        log_message_pool* message_pool() { return message_pool_.get(); }

        void set_max_logsize(size_t max_logsize) { max_logsize_ = max_logsize; }
        void set_clean_time(size_t clean_time) { clean_time_ = clean_time; }
        bool need_hook(log_level lvl) { return lvl >= hook_lv_; }

        bool add_dest(vstring feature, vstring log_path) {
            std::unique_lock<spin_mutex> lock(mutex_);
            if (dest_features_.find(feature) == dest_features_.end()) {
                sptr<log_dest> logfile = nullptr;
                path logger_path = build_path(feature, log_path);
                if (rolling_type_ == rolling_type::DAYLY) {
                    auto dlogfile = std::make_shared<log_dailyrollingfile>(max_logsize_);
                    dlogfile->setup(logger_path, service_, feature, clean_time_);
                    logfile = dlogfile;
                } else {
                    auto hlogfile = std::make_shared<log_hourlyrollingfile>(max_logsize_);
                    hlogfile->setup(logger_path, service_, feature, clean_time_);
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
            sstring feature = names[(int)log_lvl];
            std::transform(feature.begin(), feature.end(), feature.begin(), [](auto c) { return std::tolower(c); });
            path logger_path = build_path(feature, "");
            std::unique_lock<spin_mutex> lock(mutex_);
            if (rolling_type_ == rolling_type::DAYLY) {
                auto logfile = std::make_shared<log_dailyrollingfile>(max_logsize_);
                logfile->setup(logger_path, service_, feature, clean_time_);
                dest_lvls_.insert(std::make_pair(log_lvl, logfile));
            }
            else {
                auto logfile = std::make_shared<log_hourlyrollingfile>(max_logsize_);
                logfile->setup(logger_path, service_, feature, clean_time_);
                dest_lvls_.insert(std::make_pair(log_lvl, logfile));
            }
            return true;
        }

        void del_dest(vstring feature) {
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

        void ignore_prefix(vstring feature, bool prefix) {
            auto iter = dest_features_.find(feature);
            if (iter != dest_features_.end()) {
                iter->second->ignore_prefix(prefix);
                return;
            }
            if (def_dest_) def_dest_->ignore_prefix(prefix);
            if (std_dest_) std_dest_->ignore_prefix(prefix);
            for (auto dest : dest_lvls_) dest.second->ignore_prefix(prefix);
        }

        void ignore_suffix(vstring feature, bool suffix) {
            auto iter = dest_features_.find(feature);
            if (iter != dest_features_.end()) {
                iter->second->ignore_suffix(suffix);
                return;
            }
            if (def_dest_) def_dest_->ignore_suffix(suffix);
            if (std_dest_) std_dest_->ignore_suffix(suffix);
            for (auto dest : dest_lvls_) dest.second->ignore_suffix(suffix);
        }

        void ignore_def(vstring feature, bool def) {
            auto iter = dest_features_.find(feature);
            if (iter != dest_features_.end()) {
                iter->second->ignore_def(def);
                return;
            }
        }

        void start() {
            if (!stop_msg_ && !std_dest_) {
                logmsgque_ = std::make_shared<log_message_queue>();
                message_pool_ = std::make_shared<log_message_pool>(QUEUE_MINI);
                std_dest_ = std::make_shared<stdio_dest>();
                stop_msg_ = message_pool_->allocate();
                std::thread(&log_service::run, this).swap(thread_);
                utility::set_thread_name(thread_, "log");
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
                logmsgque_->put(stop_msg_,true);
            }
            if (thread_.joinable()) {
                thread_.join();
            }
        }

        void submit(sptr<log_message> logmsg) {
            if (stop_msg_) {
                logmsgque_->put(logmsg,false);
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

        void output(log_level level, cstring& msg, cstring& tag, cstring& feature, cstring& source = "", int line = 0) {
            if (!log_filter_.is_filter(level)) {
                auto logmsg_ = message_pool_->allocate();
                logmsg_->option(level, msg, tag, feature, source, line);
                submit(logmsg_);
            }
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
                        if (itFea->second->log_def()) {
                            if (def_dest_) {
                                def_dest_->write(logmsg);
                            }
                        }
                    } else {
                        if (def_dest_) {
                            def_dest_->write(logmsg);
                        }
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
        log_level       hook_lv_ = log_level::LOG_LEVEL_ERROR;
        std::thread     thread_;
        sstring         service_;
        sptr<log_dest>  std_dest_ = nullptr;
        sptr<log_dest>  def_dest_ = nullptr;
        sptr<log_message> stop_msg_ = nullptr;
        sptr<log_message_queue> logmsgque_ = nullptr;
        sptr<log_message_pool> message_pool_ = nullptr;
        std::map<log_level, sptr<log_dest>> dest_lvls_;
        std::map<sstring, sptr<log_dest>,std::less<>> dest_features_;
        size_t max_logsize_ = MAX_LOG_SIZE, clean_time_ = CLEAN_TIME;
        bool log_daemon_ = false;
    }; // class log_service

    // class log_dest
    // --------------------------------------------------------------------------------
    inline void log_dest::write(sptr<log_message> logmsg) {
        auto logtxt = fmt::format("{}{}{}\n", build_prefix(logmsg), logmsg->msg(), build_suffix(logmsg));
        raw_write(logtxt, logmsg->level());
    }

    inline cstring log_dest::build_prefix(sptr<log_message> logmsg) {
        if (!ignore_prefix_) {
            auto names = level_names<log_level>()();
            const log_time& t = logmsg->get_log_time();
            return fmt::format("[{:4d}-{:02d}-{:02d} {:02d}:{:02d}:{:02d}.{:03d}][{}][{}]",
                t.tm_year + 1900, t.tm_mon + 1, t.tm_mday, t.tm_hour, t.tm_min, t.tm_sec, t.tm_usec, logmsg->tag(), names[(int)logmsg->level()]);
        }
        return "";
    }

    inline cstring log_dest::build_suffix(sptr<log_message> logmsg) {
        if (!ignore_suffix_) {
            return fmt::format("[{}:{}]", logmsg->source().data(), logmsg->line());
        }
        return "";
    }
}

#define LOG_TRACE(msg) logger::log_service::instance()->output(logger::log_level::LOG_LEVEL_TRACE, msg,"","", __FILE__, __LINE__)
#define LOG_DEBUG(msg) logger::log_service::instance()->output(logger::log_level::LOG_LEVEL_DEBUG, msg,"","", __FILE__, __LINE__)
#define LOG_WARN(msg) logger::log_service::instance()->output(logger::log_level::LOG_LEVEL_WARN, msg,"","", __FILE__, __LINE__)
#define LOG_INFO(msg) logger::log_service::instance()->output(logger::log_level::LOG_LEVEL_INFO, msg,"","", __FILE__, __LINE__)
#define LOG_ERROR(msg) logger::log_service::instance()->output(logger::log_level::LOG_LEVEL_ERROR, msg,"","", __FILE__, __LINE__)
#define LOG_FATAL(msg) logger::log_service::instance()->output(logger::log_level::LOG_LEVEL_FATAL, msg,"","", __FILE__, __LINE__)

#define LOGF_TRACE(msg, tag, feature) logger::log_service::instance()->output(logger::log_level::LOG_LEVEL_TRACE, msg,tag,feature, __FILE__, __LINE__)
#define LOGF_DEBUG(msg, tag, feature) logger::log_service::instance()->output(logger::log_level::LOG_LEVEL_DEBUG, msg,tag,feature, __FILE__, __LINE__)
#define LOGF_WARN(msg, tag, feature)  logger::log_service::instance()->output(logger::log_level::LOG_LEVEL_WARN, msg,tag,feature, __FILE__, __LINE__)
#define LOGF_INFO(msg, tag, feature)  logger::log_service::instance()->output(logger::log_level::LOG_LEVEL_INFO, msg,tag,feature, __FILE__, __LINE__)
#define LOGF_ERROR(msg, tag, feature) logger::log_service::instance()->output(logger::log_level::LOG_LEVEL_ERROR, msg,tag,feature, __FILE__, __LINE__)
#define LOGF_FATAL(msg, tag, feature) logger::log_service::instance()->output(logger::log_level::LOG_LEVEL_FATAL, msg,tag,feature, __FILE__, __LINE__)
