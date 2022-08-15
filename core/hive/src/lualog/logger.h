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
#include <string>
#include <locale>
#include <codecvt>
#include <process.h>
#define getpid _getpid
#else
#include <unistd.h>
#endif

using namespace std::chrono;

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
		void put(std::shared_ptr<log_message> logmsg,bool notify) {
			std::unique_lock<spin_mutex> lock(spin_);
			write_messages_->push_back(logmsg);
            if (notify || write_messages_->size() > 10) {
                condv_.notify_all();
            }
		}

		std::shared_ptr<log_message_list> timed_getv() {
			{
				read_messages_->clear();
				std::unique_lock<spin_mutex> lock(spin_);
				read_messages_.swap(write_messages_);
			}
			if (read_messages_->empty()) {
				std::unique_lock<std::mutex> lock(mutex_);
				condv_.wait_for(lock, std::chrono::milliseconds(5));
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
        log_dest(log_service* service) : log_service_(service) {}
        virtual ~log_dest() { }

        virtual void flush() {};
        virtual void raw_write(std::string msg, log_level lvl) = 0;
        virtual void write(std::shared_ptr<log_message> logmsg);
        virtual std::string build_postfix(std::shared_ptr<log_message> logmsg);

    protected:
        log_service*    log_service_ = nullptr;
    }; // class log_dest

    class stdio_dest : public log_dest {
    public:
        stdio_dest(log_service* service) : log_dest(service) {}
        virtual ~stdio_dest() { }

        virtual void raw_write(std::string msg, log_level lvl) {
#ifdef WIN32
            try
            {
                msg = locale_strCnv->to_bytes(strCnv.from_bytes(msg));
            }
            catch (const std::exception& e)
            {
                std::cout << "change chinese fail:" << e.what() << std::endl;
            }
			auto colors = level_colors<log_level>()();
            std::cout << colors[(int)lvl];
#endif // WIN32
            std::cout << msg;
        }
#ifdef WIN32
        typedef std::codecvt_byname<wchar_t, char, std::mbstate_t> F;
        std::shared_ptr<std::wstring_convert<F>> locale_strCnv = std::make_shared<std::wstring_convert<F> >(new F("Chinese"));
        std::wstring_convert<std::codecvt_utf8<wchar_t> > strCnv;
#endif
    }; // class stdio_dest

    class log_file_base : public log_dest {
    public:
        log_file_base(log_service* service, size_t max_line, int pid)
            : log_dest(service), pid_(pid), line_(0), max_line_(max_line){ }

        virtual ~log_file_base() {
            if (file_) {
                file_->flush();
                file_->close();
            }
        }
        virtual void raw_write(std::string msg, log_level lvl) {
            if (file_) file_->write(msg.c_str(), msg.size());
        }
        virtual void flush() {
            if (file_) file_->flush();
        }
        const log_time& file_time() const { return file_time_; }

    protected:
        virtual void create(std::filesystem::path file_path, std::string file_name, const log_time& file_time) {
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
        log_rollingfile(log_service* logservice, int pid, std::filesystem::path& log_path, const std::string& service, const std::string& feature, size_t max_line = 10000)
            : log_file_base(logservice, max_line, pid), feature_(feature), log_path_(log_path){
            if (feature != service) {
                log_path_.append(feature);
            }
        }

        virtual void write(std::shared_ptr<log_message> logmsg) {
            line_++;
            if (file_ == nullptr || rolling_evaler_.eval(this, logmsg) || line_ >= max_line_) {
                std::filesystem::create_directories(log_path_);
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

        std::string             feature_;
        std::filesystem::path   log_path_;
        rolling_evaler          rolling_evaler_;
    }; // class log_rollingfile

    typedef log_rollingfile<rolling_hourly> log_hourlyrollingfile;
    typedef log_rollingfile<rolling_daily> log_dailyrollingfile;

    class log_service {
    public:
        void daemon(bool status) { log_daemon_ = status; }
        void option(std::string log_path, std::string service, std::string index, rolling_type type, int max_line) {
            log_path_ = log_path, service_ = service; rolling_type_ = type; max_line_ = max_line;
            log_path_.append(fmt::format("{}-{}", service, index));
        }
        std::shared_ptr<log_filter> get_filter() { return log_filter_; }
        std::shared_ptr<log_message_pool> message_pool() { return message_pool_; }

        bool add_dest(std::string feature) {
            std::unique_lock<spin_mutex> lock(mutex_);
            if (dest_features_.find(feature) == dest_features_.end()) {
                std::shared_ptr<log_dest> logfile = nullptr;
                if (rolling_type_ == rolling_type::DAYLY) {
                    logfile = std::make_shared<log_dailyrollingfile>(this, log_pid_, log_path_, service_, feature, max_line_);
                } else {
                    logfile = std::make_shared<log_hourlyrollingfile>(this, log_pid_, log_path_, service_, feature, max_line_);
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
                auto logfile = std::make_shared<log_dailyrollingfile>(this, log_pid_, log_path_, service_, feature, max_line_);
                dest_lvls_.insert(std::make_pair(log_lvl, logfile));
            }
            else {
                auto logfile = std::make_shared<log_hourlyrollingfile>(this, log_pid_, log_path_, service_, feature, max_line_);
                dest_lvls_.insert(std::make_pair(log_lvl, logfile));
            }
            return true;
        }

        void del_dest(std::string feature) {
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
            if (stop_msg_ == nullptr) {
                log_pid_ = ::getpid();
                stop_msg_ = message_pool_->allocate();
                log_filter_ = std::make_shared<log_filter>();
                std_dest_ = std::make_shared<stdio_dest>(this);
                std::thread(&log_service::run, this).swap(thread_);
            }
        }

        void stop() {
            logmsgque_->put(stop_msg_,true);
            if (thread_.joinable()) {
                thread_.join();
            }
        }

        void submit(std::shared_ptr<log_message> logmsg) {
            logmsgque_->put(logmsg,false);
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
            return log_filter_->is_filter(lv); 
        }

        void filter(log_level lv, bool on) {
            log_filter_->filter(lv, on);
        }

        template<log_level level>
        log_stream<level> hold(std::string feature, std::string source = "", int line = 0) {
            return log_stream<level>(this, feature, source, line);
        }

        template<log_level level>
        void output(std::string msg, std::string feature) {
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
						break;
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

        bool log_daemon_ = false, ignore_postfix_ = true;
        int  log_pid_ = 0, max_line_ = 100000;
        spin_mutex              mutex_;
        std::thread             thread_;
        rolling_type            rolling_type_;
        std::string             service_;
        std::filesystem::path   log_path_;
        std::shared_ptr<log_dest>       std_dest_ = nullptr;
        std::shared_ptr<log_dest>       def_dest_ = nullptr;
        std::shared_ptr<log_message>    stop_msg_ = nullptr;
        std::shared_ptr<log_filter>     log_filter_ = nullptr;
        std::unordered_map<log_level,       std::shared_ptr<log_dest>> dest_lvls_;
        std::unordered_map<std::string,     std::shared_ptr<log_dest>> dest_features_;
        std::shared_ptr<log_message_queue>  logmsgque_ = std::make_shared<log_message_queue>();
        std::shared_ptr<log_message_pool>   message_pool_ = std::make_shared<log_message_pool>(3000);
    }; // class log_service

    template<log_level level>
    class log_stream {
    public:
        log_stream(log_service* service, std::string feature, std::string source = "", int line = 0)
            : service_(service) {
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
                service_->submit(logmsg_);
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
        log_service* service_ = nullptr;
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
        if (!log_service_->is_ignore_postfix()) {
            return fmt::format("[{}:{}]", logmsg->source().c_str(), logmsg->line());
        }
        return "";
    }
}

#define LOG_WARN(service) service->hold<logger::log_level::LOG_LEVEL_WARN>("", __FILE__, __LINE__)
#define LOG_INFO(service) service->hold<logger::log_level::LOG_LEVEL_INFO>("", __FILE__, __LINE__)
#define LOG_DUMP(service) service->hold<logger::log_level::LOG_LEVEL_DUMP>("", __FILE__, __LINE__)
#define LOG_DEBUG(service) service->hold<logger::log_level::LOG_LEVEL_DEBUG>("", __FILE__, __LINE__)
#define LOG_ERROR(service) service->hold<logger::log_level::LOG_LEVEL_ERROR>("", __FILE__, __LINE__)
#define LOG_FATAL(service) service->hold<logger::log_level::LOG_LEVEL_FATAL>("", __FILE__, __LINE__)
#define LOGF_WARN(service, feature) service->hold<logger::log_level::LOG_LEVEL_WARN>(feature, __FILE__, __LINE__)
#define LOGF_INFO(service, feature) service->hold<logger::log_level::LOG_LEVEL_INFO>(feature, __FILE__, __LINE__)
#define LOGF_DUMP(service, feature) service->hold<logger::log_level::LOG_LEVEL_DUMP>(feature, __FILE__, __LINE__)
#define LOGF_DEBUG(service, feature) service->hold<logger::log_level::LOG_LEVEL_DEBUG>(feature, __FILE__, __LINE__)
#define LOGF_ERROR(service, feature) service->hold<logger::log_level::LOG_LEVEL_ERROR>(feature, __FILE__, __LINE__)
#define LOGF_FATAL(service, feature) service->hold<logger::log_level::LOG_LEVEL_FATAL>(feature, __FILE__, __LINE__)
